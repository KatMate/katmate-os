//! netvm-agent — VSOCK control agent for the KatMate netVM (sysVM).
//!
//! Runs inside the netVM. Unlike vm-agent it is NOT the unprivileged
//! session user: its systemd unit grants it CAP_NET_ADMIN (for NETCFG, the
//! internal /32 route lifecycle) and CAP_KILL (for SHUTDOWN, signalling
//! PID 1). RUN, and the retired 0x03 / 0x04, have no variant in this
//! binary's `Op`, so they die in `Op::try_from` at decode (op.rs is the security boundary;
//! ADR-021, ADR-024).
//!
//! This file is a deliberate SUBTRACTION from `vm-agent/src/main.rs`. It
//! keeps only the transport skeleton the two agents genuinely share and
//! drops everything that was appVM policy:
//!
//!   kept    — AF_VSOCK socket, bind(VMADDR_CID_ANY, control_port), listen,
//!             the accept loop with its host-CID check, and the synchronous
//!             single-client per-connection loop.
//!   dropped — config.rs (no per-appVM config surface), the WHITELIST /
//!             INIT_SOCK / SHUTDOWN_CMD policy constants,
//!             posix_spawn + environ (no child to launch — no spawn() at
//!             all in this binary), and the SIGCHLD SIG_IGN (nothing here forks, so there are no
//!             children to reap).
//!
//! SHUTDOWN (ADR-024): unlike RUN, SHUTDOWN is NOT dropped — it is
//! handled here. It does NOT go through katmate-init (there is none; netVM
//! runs systemd) and it does NOT go through vm-agent's INIT_SOCK. It asks
//! netVM's own PID 1 — systemd — for a clean stop, by sending SIGRTMIN+4,
//! systemd's documented signal for poweroff.target. This reverses ADR-021's
//! "no SHUTDOWN in netvm-agent": that rule assumed the host could power netVM
//! down over QMP -> ACPI -> logind, but logind needs dbus and the manifest
//! deliberately omits it, so the path was proven inert (ADR-024). The
//! mechanism costs one capability (CAP_KILL) and no daemon: no dbus, no
//! polkit, no acpid, no CAP_SYS_BOOT.
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

mod netcfg;
mod netlink;
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
// unless the error indicates the peer is gone.

/// PING → OK. Liveness. The only opcode both agents handle, and the one
/// this listener gate proves (`ping-client ping 3 → OK`).
fn handle_ping(fd: RawFd) -> Result<()> {
    frame::write_ok(fd)
}

/// NETCFG → install / withdraw an appVM's internal /32 p2p link. The sole
/// justification for CAP_NET_ADMIN.
///
/// Reply AFTER the act — the deliberate mirror of SHUTDOWN's reply-first
/// (ADR-024). There the reply must precede an act that kills the agent; here
/// the reply IS the postcondition report, and the agent survives it. OK means
/// the desired state was reached; ERR means re-issue or escalate, never
/// "nothing was touched" (ADR-025: convergence, not rollback).
///
/// Payload validation, the record set and the rtnetlink mechanism live in
/// `netcfg.rs` / `netlink.rs`; this stays a thin wire adapter.
fn handle_netcfg(fd: RawFd, req: &RawRequest) -> Result<()> {
    match netcfg::handle(req) {
        Ok(()) => frame::write_ok(fd),
        Err(e) => {
            log_error("NETCFG", &e);
            frame::write_err(fd)
        }
    }
}

/// SHUTDOWN → OK, then ask PID 1 (systemd) to power the netVM off.
///
/// Reply-first, exactly as vm-agent's handle_shutdown: the host gets its
/// acknowledgement before the signal, because the poweroff sequence stops
/// `netvm-agent.service` early (observed live, ADR-024 E7/E8) — a reply
/// attempted after the signal would race this process's own death.
///
/// The signal is SIGRTMIN+4, systemd's documented request to start
/// poweroff.target — byte-for-byte the same clean stop as `systemctl
/// poweroff`, but with no bus, no logind, no polkit. It is delivered under
/// CAP_KILL (granted by the unit); a plain uid without it gets EPERM (proven,
/// ADR-024 E6). Best-effort after the ack: if kill(2) fails we log it, but the
/// host already has its OK and can still force the VM down as a last resort.
fn handle_shutdown(fd: RawFd) -> Result<()> {
    frame::write_ok(fd)?;

    // SIGRTMIN is not a constant under glibc (the first few RT signals are
    // reserved for the NPTL implementation, so the runtime base is typically
    // 34, not 32); libc exposes it as a function. SIGRTMIN+4 is systemd's
    // documented signal for poweroff.target.
    let sig = libc::SIGRTMIN() + 4;

    // SAFETY: kill(2) with a valid signal number to PID 1. We hold CAP_KILL
    // (unit-granted), so this is permitted; without it the kernel returns
    // EPERM and the VM stays up. PID 1 (systemd) is always present. No memory
    // is touched; the only effect is the queued signal.
    let rc = unsafe { libc::kill(1, sig) };
    if rc != 0 {
        let os = std::io::Error::last_os_error();
        log_error(
            "SHUTDOWN signal PID 1",
            &AgentError::Rejected("kill(1, SIGRTMIN+4) failed"),
        );
        log_debug!("kill errno: {os}");
    }

    // Return Ok regardless: the host has its ack, and poweroff (if it fired)
    // is asynchronous — this function returns normally and the connection loop
    // ends on the disconnect that follows as the VM goes down.
    Ok(())
}

// --- per-connection loop -------------------------------------------

/// Handle one accepted connection until the peer disconnects or a fatal
/// stream error occurs. Each request is dispatched; per-request errors are
/// logged and answered with ERR, but the connection continues. A disconnect
/// (EOF at a frame boundary) ends the loop quietly.
///
/// Mirrors vm-agent's handle_connection exactly, minus the `cfg` argument
/// (no config) and with the three-branch dispatch of this binary's `Op`.
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

        // Map the raw opcode into THIS binary's op set. RUN exists on the
        // wire but has no variant here, and neither do the retired 0x03 /
        // 0x04 (opcode::RETIRED), so they die
        // right at this line: answered with ERR, no handler ever reached.
        // Absent, not disabled (ADR-021). SHUTDOWN now DOES decode here
        // (ADR-024). An unmapped opcode is NOT fatal to the connection — the
        // peer asked for something this binary does not implement, it did not
        // corrupt the stream — so we log, ERR, and keep serving. (Matches the
        // judgement recorded for the workspace split; reverting to
        // drop-the-connection is a one-line change.)
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
            Op::Shutdown => handle_shutdown(fd),
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

#[cfg(test)]
mod tests {
    use super::*;

    /// An opcode this binary has no variant for — RUN, a retired one, an
    /// unassigned one — gets the ERR reply and the connection keeps serving:
    /// no panic, no dropped connection. Driven through handle_connection over
    /// a socketpair, so the dispatch path under test is the production one.
    /// The PING sent last proves the connection survived the refusals.
    #[test]
    fn retired_and_unknown_opcodes_get_err_and_the_connection_survives() {
        use katmate_protocol::opcode;

        let mut sv = [0 as RawFd; 2];
        // SAFETY: sv is a valid two-element out-array for socketpair.
        let rc = unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_STREAM, 0, sv.as_mut_ptr()) };
        assert_eq!(rc, 0, "socketpair: {}", std::io::Error::last_os_error());
        let (agent, host) = (sv[0], sv[1]);

        let sent = [opcode::OP_RUN, 0x03, 0x04, 0xFF, opcode::OP_PING];
        for op in sent {
            frame::write_request(host, op, &[], &[]).unwrap();
        }
        // SAFETY: host is a valid socket fd; SHUT_WR gives the agent EOF at
        // the frame boundary after the last request.
        unsafe { libc::shutdown(host, libc::SHUT_WR) };

        handle_connection(agent);
        // SAFETY: agent is a valid fd we own; closed exactly once here.
        unsafe { libc::close(agent) };

        let got: Vec<u8> = sent
            .iter()
            .map(|_| frame::read_response(host).unwrap().status)
            .collect();
        assert_eq!(
            got,
            [frame::STATUS_ERR, frame::STATUS_ERR, frame::STATUS_ERR, frame::STATUS_ERR, frame::STATUS_OK]
        );
        // Exactly one reply per request, then the end of the stream.
        assert!(frame::read_response(host).unwrap_err().is_disconnect());
        // SAFETY: host is a valid fd we own; closed exactly once here.
        unsafe { libc::close(host) };
    }
}
