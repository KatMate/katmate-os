//! netvm-agent — VSOCK control agent for the KatMate netVM (sysVM).
//!
//! Runs inside the netVM. Unlike vm-agent it is NOT the unprivileged
//! session user: its systemd unit grants it CAP_NET_ADMIN, and that one
//! capability buys exactly one operation — NETCFG, the internal /32 route
//! lifecycle. Everything else the appVM agent can do is ABSENT here, not
//! merely refused: RUN, FILEGET, FILEPUT and SHUTDOWN have no variant in
//! this binary's `Op`, so they die in `Op::try_from` at decode (op.rs is
//! the security boundary; ADR-021).
//!
//! This file is a deliberate SUBTRACTION from `vm-agent/src/main.rs`. It
//! keeps only the transport skeleton the two agents genuinely share and
//! drops everything that was appVM policy:
//!
//!   kept    — AF_VSOCK socket, bind(VMADDR_CID_ANY, control_port), listen,
//!             the accept loop with its host-CID check, and the synchronous
//!             single-client per-connection loop.
//!   dropped — config.rs (no per-appVM config surface), the WHITELIST /
//!             HOME_PREFIX / INIT_SOCK / SHUTDOWN_CMD policy constants,
//!             posix_spawn + environ (no child to launch — no spawn() at
//!             all in this binary), signal_init_shutdown (no SHUTDOWN),
//!             path_is_allowed (no file surface), and the SIGCHLD SIG_IGN
//!             (nothing here forks, so there are no children to reap).
//!
//! Design, unchanged from vm-agent (ADR):
//!   * Synchronous, single-client. One peer (the host launch daemon); one
//!     connection handled to completion before the next is accepted. No
//!     threads, no async runtime — smallest TCB in the most network-exposed
//!     VM in the system.
//!   * std + libc only. VSOCK has no std abstraction, so the listener uses
//!     raw syscalls; every `unsafe` block notes the invariant it upholds.
//!   * Accepts connections from the host CID only.
//!
//! Port: netVM listens on the shared `DEFAULT_CONTROL_PORT` (1025), the same
//! control port vm-agent uses — different CID, same port, exactly as the wire
//! intends. netVM has no config.rs, so the port is not env-overridable here;
//! that was appVM config, not protocol. (See the note in vm-agent's
//! config.rs: "netvm-agent has NO config.rs … if it ever needs one, it
//! gets its own.")

mod op;

use std::os::fd::RawFd;

use katmate_protocol::error::{AgentError, Result};
use katmate_protocol::frame::{self, RawRequest};

use op::Op;

// --- logging --------------------------------------------------------
// Identical policy to vm-agent: debug-only chatter compiled out of release
// builds; structured error logging present in all builds but only on an
// actual error path, never on the hot path.

/// Debug-only log. Expands to an `eprintln!` (→ journal, since the unit
/// routes StandardError=journal) in debug builds, and to nothing in
/// release builds — the arguments are not even evaluated.
#[macro_export]
macro_rules! log_debug {
    ($($arg:tt)*) => {
        if cfg!(debug_assertions) {
            eprintln!("[netvm-agent debug] {}", format!($($arg)*));
        }
    };
}

/// Error log, present in all builds. Cheap: only called on an error
/// path, never on a normal request.
fn log_error(context: &str, err: &AgentError) {
    eprintln!("[netvm-agent] {context}: {err}");
}

// --- command handlers ----------------------------------------------
// Each returns Result<()>. An Err is logged once by the caller and turned
// into an ERR response; the connection stays open for the next request
// unless the error indicates the peer is gone. Only two handlers exist —
// that is the whole point of this binary.

/// PING → OK. Liveness. The only opcode both agents handle, and the one
/// this listener gate proves (`ping-client ping 3 → OK`).
fn handle_ping(fd: RawFd) -> Result<()> {
    frame::write_ok(fd)
}

/// NETCFG → install / withdraw an appVM's internal /32 p2p link. The sole
/// privileged operation in the binary and the sole justification for
/// CAP_NET_ADMIN.
///
/// STUB for the listener gate. The typed, link-scoped payload (ADR-023) and
/// its in-guest mechanism (networkd fragment vs rtnetlink) are a separate
/// architecture session — this session lands the transport only. Until that
/// handler exists, NETCFG is answered honestly with ERR: the opcode DECODES
/// here (it is a real capability of this binary, unlike RUN), but there is no
/// implementation yet, so it is rejected at the handler rather than pretended
/// to have succeeded.
fn handle_netcfg(fd: RawFd, _req: &RawRequest) -> Result<()> {
    log_error("NETCFG", &AgentError::Rejected("NETCFG not yet implemented"));
    frame::write_err(fd)
}

// --- per-connection loop -------------------------------------------

/// Handle one accepted connection until the peer disconnects or a fatal
/// stream error occurs. Each request is dispatched; per-request errors are
/// logged and answered with ERR, but the connection continues. A disconnect
/// (EOF at a frame boundary) ends the loop quietly.
///
/// Mirrors vm-agent's handle_connection exactly, minus the `cfg` argument
/// (no config) and with the two-branch dispatch of this binary's `Op`.
fn handle_connection(fd: RawFd) {
    loop {
        let req = match frame::read_request(fd) {
            Ok(r) => r,
            Err(e) => {
                if !e.is_disconnect() {
                    log_error("read_request", &e);
                    // Try to inform the peer; ignore failure (peer may
                    // already be gone).
                    let _ = frame::write_err(fd);
                }
                return;
            }
        };

        // Map the raw opcode into THIS binary's op set. RUN / FILEGET /
        // FILEPUT / SHUTDOWN exist on the wire but have no variant here, so
        // they die right at this line: answered with ERR, no handler ever
        // reached. Absent, not disabled (ADR-021). An unmapped opcode is NOT
        // fatal to the connection — the peer asked for something this binary
        // does not implement, it did not corrupt the stream — so we log, ERR,
        // and keep serving. (Matches the judgement recorded for the workspace
        // split; reverting to drop-the-connection is a one-line change.)
        let op = match Op::try_from(req.opcode) {
            Ok(op) => op,
            Err(e) => {
                log_error("dispatch", &e);
                let _ = frame::write_err(fd);
                continue;
            }
        };

        let result = match op {
            Op::Ping => handle_ping(fd),
            Op::Netcfg => handle_netcfg(fd, &req),
        };

        if let Err(e) = result {
            // A write/stream error here usually means the peer is gone;
            // log and drop the connection rather than spinning.
            if !e.is_disconnect() {
                log_error("handler", &e);
            }
            return;
        }
    }
}

// --- listener -------------------------------------------------------

fn main() {
    // No SIGCHLD SIG_IGN: this binary never forks, so there are no children
    // to reap. (vm-agent needs it for the waypipe children RUN spawns.)

    // SAFETY: standard socket creation; result checked immediately.
    let sock = unsafe { libc::socket(libc::AF_VSOCK, libc::SOCK_STREAM, 0) };
    if sock < 0 {
        eprintln!(
            "[netvm-agent] socket(AF_VSOCK) failed: {}",
            std::io::Error::last_os_error()
        );
        std::process::exit(1);
    }

    // bind to (VMADDR_CID_ANY, DEFAULT_CONTROL_PORT). netVM has no config.rs,
    // so the port is the shared protocol default, not an env override.
    let control_port = frame::DEFAULT_CONTROL_PORT;

    let mut addr: libc::sockaddr_vm = unsafe { std::mem::zeroed() };
    addr.svm_family = libc::AF_VSOCK as libc::sa_family_t;
    addr.svm_port = control_port;
    addr.svm_cid = libc::VMADDR_CID_ANY;

    // SAFETY: addr is a fully initialised sockaddr_vm; size matches.
    let rc = unsafe {
        libc::bind(
            sock,
            &addr as *const libc::sockaddr_vm as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_vm>() as libc::socklen_t,
        )
    };
    if rc < 0 {
        eprintln!(
            "[netvm-agent] bind(port {}) failed: {}",
            control_port,
            std::io::Error::last_os_error()
        );
        std::process::exit(1);
    }

    // SAFETY: sock is a valid bound socket.
    if unsafe { libc::listen(sock, 5) } < 0 {
        eprintln!(
            "[netvm-agent] listen failed: {}",
            std::io::Error::last_os_error()
        );
        std::process::exit(1);
    }

    log_debug!("listening on VSOCK port {}", control_port);

    loop {
        let mut peer: libc::sockaddr_vm = unsafe { std::mem::zeroed() };
        let mut peer_len = std::mem::size_of::<libc::sockaddr_vm>() as libc::socklen_t;

        // SAFETY: peer / peer_len are valid out-parameters for accept.
        let client = unsafe {
            libc::accept(
                sock,
                &mut peer as *mut libc::sockaddr_vm as *mut libc::sockaddr,
                &mut peer_len,
            )
        };
        if client < 0 {
            let err = std::io::Error::last_os_error();
            if err.raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            // Log transient accept errors but keep serving.
            eprintln!("[netvm-agent] accept failed: {err}");
            continue;
        }

        // Accept connections from the host only.
        if peer.svm_cid != libc::VMADDR_CID_HOST {
            log_debug!("rejecting connection from CID {}", peer.svm_cid);
            // SAFETY: client is a valid fd from accept.
            unsafe { libc::close(client) };
            continue;
        }

        handle_connection(client);

        // SAFETY: client is a valid fd we own; closed exactly once here.
        unsafe { libc::close(client) };
    }
}
