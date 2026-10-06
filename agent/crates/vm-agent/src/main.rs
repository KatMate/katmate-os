//! vm-agent — VSOCK control agent for KatMate appVMs.
//!
//! Runs inside each appVM (as the unprivileged session user, uid 1000,
//! started by katmate-init, PID 1, after the privilege drop). It speaks a small binary,
//! length-prefixed protocol over a VSOCK control channel and accepts
//! connections only from the host CID.
//!
//! Design (deliberate, see ADR):
//!   * Synchronous, single-client. The control channel has exactly one
//!     peer (the host client); one connection is handled to completion
//!     before the next is accepted. No threads, no async runtime —
//!     smaller TCB, simpler reasoning.
//!   * std + libc only. VSOCK has no std abstraction, so the listener
//!     uses raw syscalls; every `unsafe` block notes the invariant it
//!     upholds.
//!   * Children (waypipe for RUN) are started with posix_spawn — argv
//!     is built in the parent before the call, avoiding the
//!     not-async-signal-safe work-after-fork pattern of the original C
//!     agent.
//!   * Zombies are reaped by the kernel: SIGCHLD is set to SIG_IGN once
//!     at startup, so finished children are auto-reaped without a
//!     handler or explicit waitpid.
//!   * Debug logging (RUN environment, argv, child stderr) is compiled
//!     out of release builds via `log_debug!` / cfg!(debug_assertions),
//!     so it costs nothing — and leaks nothing — in the shipped image.
//!     Structured error logging stays in all builds, but only fires on
//!     an actual error, never on the hot path.
//!
//! SHUTDOWN is NOT performed by the agent: it is uid 1000 and cannot
//! call reboot(2). Instead it asks PID 1 (katmate-init) — the single
//! root process in the guest — over a local Unix socket. This replaces
//! the former setuid power-helper, removing that root binary entirely.
//! It exists here because appVMs are microvm: no ACPI, so the host has no
//! power-button to press, and there is no init but katmate-init to ask.
//! netVM ALSO carries a SHUTDOWN opcode, but a different mechanism: it runs
//! systemd, so its agent signals PID 1 with SIGRTMIN+4 rather than writing
//! INIT_SOCK (ADR-024). The QMP `system_powerdown` path once assumed for
//! netVM was proven inert — it needs logind, hence dbus, which netVM omits.
//! Both agents therefore do the same thing: ask their own PID 1.
//!
//! WORKSPACE SPLIT (ADR-021): the codec now comes from the shared
//! `katmate-protocol` crate; the opcode SET does not. Dispatch matches
//! on the LOCAL `Op` (op.rs), obtained via `Op::try_from(req.opcode)?`,
//! so an opcode this binary must not run — NETCFG — fails at DECODE
//! rather than at a runtime gate. The appVM-only policy constants below
//! used to sit in protocol.rs; they are policy, not wire format, and
//! netvm-agent must not inherit them.

mod config;
mod op;

use std::os::fd::RawFd;

use katmate_protocol::error::{AgentError, Result};
use katmate_protocol::frame::{self, RawRequest};

use config::Config;
use op::Op;

// --- appVM policy constants ----------------------------------------
// Formerly in protocol.rs. They were never protocol: they describe what
// THIS agent is permitted to do inside an appVM. netvm-agent has no
// whitelist and no init socket — not because it
// declines to use them, but because they do not exist in that binary.

/// VSOCK port used by waypipe for the GUI channel (RUN). Separate from
/// the control port; the host waypipe client listens here.
pub const DEFAULT_WAYPIPE_PORT: u32 = 1024;

/// Host CID. On a standard QEMU/KVM setup the host is CID 2. Used as the
/// waypipe target, not by the protocol itself.
pub const DEFAULT_HOST_CID: u32 = 2;

/// Apps that RUN may launch via waypipe.
pub const WHITELIST: &[&str] = &["firefox-esr", "foot", "pcmanfm", "libreoffice", "keepassxc"];

/// Unix socket on which PID 1 (katmate-init) listens for privileged
/// requests. SHUTDOWN is delegated here rather than to a setuid helper:
/// the agent is uid 1000 and cannot call reboot(2), so it asks init —
/// the single root process in the guest — to power the VM off. This
/// must match INIT_SOCK in katmate-init.c. The socket is SOCK_SEQPACKET.
pub const INIT_SOCK: &str = "/run/katmate-init.sock";

/// Command token the agent writes to INIT_SOCK to request power-off.
/// init matches this prefix and triggers reboot(RB_AUTOBOOT).
pub const SHUTDOWN_CMD: &[u8] = b"SHUTDOWN";

/// Variables vm-agent sets for every RUN child, replacing any inherited
/// value of the same name (R146, ADR-021's note of 2026-10-03). Fixed
/// constants: Qt 5.15 picks its `xcb` platform unless told otherwise, and
/// the guest has no X display, only waypipe's Wayland socket; and with no
/// `LANG` the locale is `C`, which foot warns about. Everything else the
/// child gets is the agent's own environment, which is katmate-init's.
pub const RUN_ENV: &[(&str, &str)] = &[
    ("QT_QPA_PLATFORM", "wayland"),
    ("XDG_SESSION_TYPE", "wayland"),
    ("LANG", "C.UTF-8"),
];

// --- logging --------------------------------------------------------

/// Debug-only log. Expands to an `eprintln!` (→ journal, since the unit
/// routes StandardError=journal) in debug builds, and to nothing in
/// release builds — the arguments are not even evaluated.
#[macro_export]
macro_rules! log_debug {
    ($($arg:tt)*) => {
        if cfg!(debug_assertions) {
            eprintln!("[vm-agent debug] {}", format!($($arg)*));
        }
    };
}

/// Error log, present in all builds. Cheap: only called on an error
/// path, never on a normal request.
fn log_error(context: &str, err: &AgentError) {
    eprintln!("[vm-agent] {context}: {err}");
}

// --- whether the child's stderr goes to the journal or to /dev/null --
// Debug builds keep child stderr (so a failing waypipe is visible);
// release builds discard it (quiet, and no information leak).
const CHILD_STDERR_TO_DEVNULL: bool = !cfg!(debug_assertions);

// --- command handlers ----------------------------------------------
// Each returns Result<()>. An Err is logged once by the caller and
// turned into an ERR response; the connection stays open for the next
// request unless the error indicates the peer is gone.

/// PING → OK.
fn handle_ping(fd: RawFd) -> Result<()> {
    frame::write_ok(fd)
}

/// RUN <app> → launch `app` under waypipe (GUI forwarded over VSOCK).
fn handle_run(fd: RawFd, req: &RawRequest, cfg: &Config) -> Result<()> {
    let app = req.arg_str(0)?;

    if !WHITELIST.contains(&app) {
        log_error("RUN", &AgentError::AppNotAllowed(app.to_string()));
        return frame::write_err(fd);
    }

    // waypipe --vsock --socket <host_cid>:<waypipe_port> server <app>
    // The socket argument is composed from configuration rather than
    // hardcoded; host_cid/waypipe_port come from the environment (the
    // unit) or the defaults above.
    let socket_arg = format!("{}:{}", cfg.host_cid, cfg.waypipe_port);
    let prefix = title_prefix(&instance_name());
    let argv = waypipe_argv(&socket_arg, prefix.as_deref(), app);

    // Debug visibility into exactly how waypipe is launched — this is
    // the information that was missing when the Wayland environment was
    // hard to get right. Compiled out of release builds.
    let envp = run_child_env(std::env::vars_os());
    log_debug!("RUN argv: {argv:?}");
    log_debug!(
        "RUN env: {:?}",
        envp.iter().map(|e| String::from_utf8_lossy(e)).collect::<Vec<_>>()
    );

    match spawn(&argv, &envp) {
        Ok(pid) => {
            log_debug!("RUN spawned waypipe pid {pid}");
            frame::write_ok(fd)
        }
        Err(e) => {
            log_error("RUN spawn", &e);
            frame::write_err(fd)
        }
    }
}

/// SHUTDOWN → OK, then ask PID 1 (katmate-init) to power the VM off.
fn handle_shutdown(fd: RawFd) -> Result<()> {
    // Reply before signalling, as the original did: the host gets its
    // acknowledgement even though the VM is about to go down.
    frame::write_ok(fd)?;

    // We are uid 1000 and cannot call reboot(2). Delegate to init over
    // its control socket. Best-effort: if it fails we log it, but the
    // host already has its ack, and a stuck VM can still be killed by
    // the host as a last resort.
    if let Err(e) = signal_init_shutdown() {
        log_error("SHUTDOWN signal init", &e);
    }
    Ok(())
}

// --- shutdown delegation to PID 1 ----------------------------------

/// Connect to katmate-init's control socket and send the SHUTDOWN
/// token. The socket is AF_UNIX/SOCK_SEQPACKET (matching init's
/// listener); init verifies our peer credentials (uid 1000) before
/// acting. We use raw syscalls for symmetry with the VSOCK listener and
/// to avoid depending on UnixStream's SEQPACKET support.
fn signal_init_shutdown() -> Result<()> {
    // SAFETY: standard socket creation; result checked immediately.
    let sock = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
    if sock < 0 {
        return Err(AgentError::Io(std::io::Error::last_os_error()));
    }

    // Build the sockaddr_un for INIT_SOCK.
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;

    let path = INIT_SOCK.as_bytes();
    if path.len() >= addr.sun_path.len() {
        // SAFETY: sock is a valid fd we own.
        unsafe { libc::close(sock) };
        return Err(AgentError::Rejected("init socket path too long"));
    }
    for (i, &b) in path.iter().enumerate() {
        addr.sun_path[i] = b as libc::c_char;
    }

    // SAFETY: addr is a fully initialised sockaddr_un; size matches.
    let rc = unsafe {
        libc::connect(
            sock,
            &addr as *const libc::sockaddr_un as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
        )
    };
    if rc < 0 {
        let err = std::io::Error::last_os_error();
        // SAFETY: sock is a valid fd we own.
        unsafe { libc::close(sock) };
        return Err(AgentError::Io(err));
    }

    // Send the command token as a single SEQPACKET message.
    // SAFETY: SHUTDOWN_CMD is a valid, owned byte slice; sock is open.
    let n = unsafe {
        libc::send(
            sock,
            SHUTDOWN_CMD.as_ptr() as *const libc::c_void,
            SHUTDOWN_CMD.len(),
            0,
        )
    };
    let result = if n < 0 {
        Err(AgentError::Io(std::io::Error::last_os_error()))
    } else {
        Ok(())
    };

    // SAFETY: sock is a valid fd we own; closed exactly once here.
    unsafe { libc::close(sock) };
    result
}

// --- RUN child environment -------------------------------------------

/// The environment a RUN child receives, as `NAME=value` entries: every
/// inherited entry in its order, except those named in RUN_ENV, followed
/// by RUN_ENV's entries in RUN_ENV's order. So each RUN_ENV name appears
/// exactly once, with vm-agent's value, and nothing else is added or
/// removed. `inherited` is the agent's own environment in production
/// (`std::env::vars_os()`), which katmate-init sets; the function takes
/// it as a parameter so the composition can be tested.
fn run_child_env<I>(inherited: I) -> Vec<Vec<u8>>
where
    I: IntoIterator<Item = (std::ffi::OsString, std::ffi::OsString)>,
{
    use std::os::unix::ffi::OsStrExt;

    let mut env: Vec<Vec<u8>> = inherited
        .into_iter()
        .filter(|(k, _)| !RUN_ENV.iter().any(|(name, _)| k.as_bytes() == name.as_bytes()))
        .map(|(k, v)| [k.as_bytes(), b"=", v.as_bytes()].concat())
        .collect();
    env.extend(
        RUN_ENV
            .iter()
            .map(|(k, v)| [k.as_bytes(), b"=", v.as_bytes()].concat()),
    );
    env
}

// --- the window-title label (alpha) --------------------------------
// Every window a RUN child opens is titled "[<instance>] <title>", so the
// host's window list says which AppVM it came from (operator ruling
// 2026-10-05, rule 6). COSMETIC, NOT A SECURITY LABEL: the guest composes the
// title, so a compromised guest can show any label it likes. The label a
// user may trust is host-assigned (per-VM waypipe listeners and --secctx),
// the next release's. UNVERIFIED that waypipe v0.11.0 applies --title-prefix
// in server mode: its man page describes ssh mode only, where the prefix is
// applied on the client side, and the source was not read. Settled by a
// window from app_web titled "[app_web] ..." in `swaymsg -t get_tree`.

/// The instance name: the guest's hostname, which katmate-init sets from
/// km.name= after validating it (R125). Read back with gethostname(2)
/// rather than parsed a second time from /proc/cmdline, so km.name= keeps
/// one parser. Empty if the call fails.
fn instance_name() -> Vec<u8> {
    let mut buf = [0u8; 256];
    // SAFETY: buf is a valid, writable buffer of the length passed;
    // gethostname writes at most that many bytes into it.
    let rc = unsafe { libc::gethostname(buf.as_mut_ptr().cast(), buf.len()) };
    if rc != 0 {
        return Vec::new();
    }
    let len = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    buf[..len].to_vec()
}

/// "[<name>] " for a name katmate-init would have accepted from km.name=
/// (1-63 bytes of [A-Za-z0-9_-]); None otherwise, so an AppVM booted
/// without km.name= (whose hostname is the kernel's default) runs its
/// windows unlabelled rather than under a label nobody assigned.
fn title_prefix(name: &[u8]) -> Option<String> {
    let ok = (1..=63).contains(&name.len())
        && name
            .iter()
            .all(|&b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-');
    // The bytes are ASCII, checked above.
    ok.then(|| format!("[{}] ", String::from_utf8_lossy(name)))
}

/// waypipe's argv for RUN. --title-prefix is a global option, so it comes
/// before the `server` subcommand.
fn waypipe_argv<'a>(socket_arg: &'a str, prefix: Option<&'a str>, app: &'a str) -> Vec<&'a str> {
    let mut argv = vec!["waypipe", "--vsock", "--socket", socket_arg];
    if let Some(p) = prefix {
        argv.extend(["--title-prefix", p]);
    }
    argv.extend(["server", app]);
    argv
}

// --- child spawning (posix_spawn) ----------------------------------

/// Spawn `argv[0]` with arguments `argv` and environment `envp` (entries
/// of the form `NAME=value`), searching PATH. Returns the child PID. Uses
/// posix_spawn so all argument marshalling happens in the parent — no
/// allocation or other non-async-signal-safe work between fork and exec.
fn spawn(argv: &[&str], envp: &[Vec<u8>]) -> Result<libc::pid_t> {
    use std::ffi::CString;

    // Build owned C strings; these must outlive the posix_spawn call.
    let c_args: Vec<CString> = argv
        .iter()
        .map(|a| CString::new(*a))
        .collect::<std::result::Result<_, _>>()
        .map_err(|_| AgentError::Rejected("argument contains NUL byte"))?;
    let c_env: Vec<CString> = envp
        .iter()
        .map(|e| CString::new(e.as_slice()))
        .collect::<std::result::Result<_, _>>()
        .map_err(|_| AgentError::Rejected("environment entry contains NUL byte"))?;

    // argv and envp arrays of pointers into c_args / c_env, NULL-terminated.
    let mut c_argv: Vec<*const libc::c_char> = c_args.iter().map(|c| c.as_ptr()).collect();
    c_argv.push(std::ptr::null());
    let mut c_envp: Vec<*const libc::c_char> = c_env.iter().map(|c| c.as_ptr()).collect();
    c_envp.push(std::ptr::null());

    let mut pid: libc::pid_t = 0;

    // File actions: in release builds, redirect the child's stderr to
    // /dev/null. In debug builds, leave stderr inherited (→ journal).
    let mut actions: libc::posix_spawn_file_actions_t = unsafe { std::mem::zeroed() };
    // SAFETY: actions is zeroed; init/destroy are paired below.
    unsafe {
        libc::posix_spawn_file_actions_init(&mut actions);
    }

    let devnull = CString::new("/dev/null").unwrap();
    if CHILD_STDERR_TO_DEVNULL {
        // SAFETY: actions initialised above; devnull is a valid C string
        // living until after posix_spawn returns.
        unsafe {
            libc::posix_spawn_file_actions_addopen(
                &mut actions,
                libc::STDERR_FILENO,
                devnull.as_ptr(),
                libc::O_WRONLY,
                0,
            );
        }
    }

    // SAFETY: c_argv and c_envp are NULL-terminated and their pointers
    // reference c_args and c_env, which are still alive. The child's
    // environment is exactly envp (run_child_env: the agent's own, which
    // katmate-init sets, plus RUN_ENV). posix_spawnp searches PATH for
    // argv[0].
    let rc = unsafe {
        libc::posix_spawnp(
            &mut pid,
            c_argv[0],
            &actions,
            std::ptr::null(),
            c_argv.as_ptr() as *const *mut libc::c_char,
            c_envp.as_ptr() as *const *mut libc::c_char,
        )
    };

    // SAFETY: actions was initialised; destroy it exactly once.
    unsafe {
        libc::posix_spawn_file_actions_destroy(&mut actions);
    }

    if rc != 0 {
        return Err(AgentError::SpawnFailed(std::io::Error::from_raw_os_error(
            rc,
        )));
    }
    Ok(pid)
}

// --- per-connection loop -------------------------------------------

/// Handle one accepted connection until the peer disconnects or a fatal
/// stream error occurs. Each request is dispatched; per-request errors
/// are logged and answered with ERR, but the connection continues. A
/// disconnect (EOF at a frame boundary) ends the loop quietly.
fn handle_connection(fd: RawFd, cfg: &Config) {
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

        // Map the raw opcode into THIS binary's op set. An opcode that
        // exists on the wire but has no variant here — NETCFG, or a
        // retired value (opcode::RETIRED) — dies right at this line: the request is answered with ERR and no
        // handler is ever reached. Absent, not disabled (ADR-021).
        let op = match Op::try_from(req.opcode) {
            Ok(op) => op,
            Err(e) => {
                log_error("dispatch", &e);
                let _ = frame::write_err(fd);
                // Not fatal to the connection: the peer sent something
                // we do not implement, not something that broke the
                // stream. Keep serving.
                continue;
            }
        };

        let result = match op {
            Op::Ping => handle_ping(fd),
            Op::Run => handle_run(fd, &req, cfg),
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
    let cfg = Config::from_env();
    log_debug!("config: {cfg:?}");

    // Reap children automatically: with SIGCHLD ignored, the kernel
    // does not keep zombies for us, and we never need waitpid.
    // SAFETY: setting a signal disposition to SIG_IGN is always valid.
    unsafe {
        libc::signal(libc::SIGCHLD, libc::SIG_IGN);
    }

    // SAFETY: standard socket creation; result checked immediately.
    let sock = unsafe { libc::socket(libc::AF_VSOCK, libc::SOCK_STREAM, 0) };
    if sock < 0 {
        eprintln!(
            "[vm-agent] socket(AF_VSOCK) failed: {}",
            std::io::Error::last_os_error()
        );
        std::process::exit(1);
    }

    // bind to (VMADDR_CID_ANY, control_port)
    let mut addr: libc::sockaddr_vm = unsafe { std::mem::zeroed() };
    addr.svm_family = libc::AF_VSOCK as libc::sa_family_t;
    addr.svm_port = cfg.control_port;
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
            "[vm-agent] bind(port {}) failed: {}",
            cfg.control_port,
            std::io::Error::last_os_error()
        );
        std::process::exit(1);
    }

    // SAFETY: sock is a valid bound socket.
    if unsafe { libc::listen(sock, 5) } < 0 {
        eprintln!(
            "[vm-agent] listen failed: {}",
            std::io::Error::last_os_error()
        );
        std::process::exit(1);
    }

    log_debug!("listening on VSOCK port {}", cfg.control_port);

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
            eprintln!("[vm-agent] accept failed: {err}");
            continue;
        }

        // Accept connections from the host only.
        if peer.svm_cid != libc::VMADDR_CID_HOST {
            log_debug!("rejecting connection from CID {}", peer.svm_cid);
            // SAFETY: client is a valid fd from accept.
            unsafe { libc::close(client) };
            continue;
        }

        handle_connection(client, &cfg);

        // SAFETY: client is a valid fd we own; closed exactly once here.
        unsafe { libc::close(client) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An opcode this binary has no variant for, a retired one included,
    /// gets the ERR reply and the connection keeps serving: no panic, no
    /// dropped connection. Driven through handle_connection itself over a
    /// socketpair, so the dispatch path under test is the production one.
    /// The PING sent last proves the connection survived the four refusals.
    #[test]
    fn retired_and_unknown_opcodes_get_err_and_the_connection_survives() {
        use katmate_protocol::opcode;

        let mut sv = [0 as RawFd; 2];
        // SAFETY: sv is a valid two-element out-array for socketpair.
        let rc = unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_STREAM, 0, sv.as_mut_ptr()) };
        assert_eq!(rc, 0, "socketpair: {}", std::io::Error::last_os_error());
        let (agent, host) = (sv[0], sv[1]);

        let sent = [0x03, 0x04, 0xFF, opcode::OP_NETCFG, opcode::OP_PING];
        for op in sent {
            frame::write_request(host, op, &[], &[]).unwrap();
        }
        // SAFETY: host is a valid socket fd; SHUT_WR gives the agent EOF at
        // the frame boundary after the last request.
        unsafe { libc::shutdown(host, libc::SHUT_WR) };

        handle_connection(agent, &Config::from_env());
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

    /// A request declaring a payload of MAX_PAYLOAD + 1 bytes gets the ERR
    /// reply, sent before any payload byte exists on the wire, and the agent
    /// then closes: an over-limit length leaves the stream unframed, so it is
    /// not served further (read_request's error path in handle_connection).
    #[test]
    fn oversized_payload_gets_err_before_any_payload_is_sent() {
        let mut sv = [0 as RawFd; 2];
        // SAFETY: sv is a valid two-element out-array for socketpair.
        let rc = unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_STREAM, 0, sv.as_mut_ptr()) };
        assert_eq!(rc, 0, "socketpair: {}", std::io::Error::last_os_error());
        let (agent, host) = (sv[0], sv[1]);

        let mut header = vec![frame::PROTOCOL_VERSION, 0x01, 0];
        header.extend_from_slice(&(frame::MAX_PAYLOAD + 1).to_le_bytes());
        // SAFETY: header is a valid owned buffer; host is a valid socket fd.
        let n = unsafe { libc::write(host, header.as_ptr().cast(), header.len()) };
        assert_eq!(n, header.len() as isize);

        // SAFETY: host is a valid socket fd. With the write side shut, an
        // agent that tried to read the payload would meet EOF, which is a
        // quiet disconnect with no reply, and the ERR assertion would fail.
        unsafe { libc::shutdown(host, libc::SHUT_WR) };
        handle_connection(agent, &Config::from_env());
        // SAFETY: agent is a valid fd we own; closed exactly once here.
        unsafe { libc::close(agent) };

        assert_eq!(frame::read_response(host).unwrap().status, frame::STATUS_ERR);
        assert!(frame::read_response(host).unwrap_err().is_disconnect());
        // SAFETY: host is a valid fd we own; closed exactly once here.
        unsafe { libc::close(host) };
    }

    /// RUN's whitelist is a compile-time constant for the alpha, so the set
    /// is pinned here: a change to it is a foundation rebuild (ADR-021).
    #[test]
    fn run_whitelist() {
        assert_eq!(
            WHITELIST,
            &["firefox-esr", "foot", "pcmanfm", "libreoffice", "keepassxc"]
        );
    }

    /// The RUN child's environment (R146): the input, minus any inherited
    /// value of the three RUN_ENV names, plus those three with vm-agent's
    /// values, each exactly once. This pins the COMPOSITION only. The
    /// five inherited constants below are katmate-init's today
    /// (init/katmate-init.c, spawn_agent), and this test does not pin
    /// them: they are katmate-init's, not vm-agent's.
    #[test]
    fn run_child_env_composition() {
        use std::ffi::OsString;
        let input = |pairs: &[(&str, &str)]| -> Vec<(OsString, OsString)> {
            pairs
                .iter()
                .map(|(k, v)| (OsString::from(k), OsString::from(v)))
                .collect()
        };
        let init_five = [
            ("HOME", "/home/user"),
            ("USER", "user"),
            ("LOGNAME", "user"),
            ("XDG_RUNTIME_DIR", "/run/user/1000"),
            ("PATH", "/usr/local/bin:/usr/bin:/bin"),
        ];
        let expected: Vec<Vec<u8>> = [
            "HOME=/home/user",
            "USER=user",
            "LOGNAME=user",
            "XDG_RUNTIME_DIR=/run/user/1000",
            "PATH=/usr/local/bin:/usr/bin:/bin",
            "QT_QPA_PLATFORM=wayland",
            "XDG_SESSION_TYPE=wayland",
            "LANG=C.UTF-8",
        ]
        .iter()
        .map(|s| s.as_bytes().to_vec())
        .collect();

        // katmate-init's environment as it is: the three are added.
        assert_eq!(run_child_env(input(&init_five)), expected);

        // An input that already carries the three, with other values (and
        // LANG twice): each is replaced, and appears once.
        let mut with_three = init_five.to_vec();
        with_three.insert(1, ("LANG", "sl_SI.UTF-8"));
        with_three.push(("QT_QPA_PLATFORM", "xcb"));
        with_three.push(("XDG_SESSION_TYPE", "x11"));
        with_three.push(("LANG", "C"));
        assert_eq!(run_child_env(input(&with_three)), expected);

        // An empty input yields exactly the three.
        assert_eq!(run_child_env(Vec::new()), expected[5..].to_vec());
    }

    /// The title label (rule 6): a name katmate-init accepts becomes
    /// "[name] "; anything else, including the kernel's default hostname,
    /// gives no label.
    #[test]
    fn title_prefix_from_hostname() {
        assert_eq!(title_prefix(b"app_web").as_deref(), Some("[app_web] "));
        assert_eq!(title_prefix(b"app-vault-2").as_deref(), Some("[app-vault-2] "));
        assert_eq!(title_prefix(&[b'a'; 63]).map(|p| p.len()), Some(66));

        assert_eq!(title_prefix(b""), None);
        assert_eq!(title_prefix(&[b'a'; 64]), None);
        assert_eq!(title_prefix(b"(none)"), None);
        assert_eq!(title_prefix(b"app web"), None);
        assert_eq!(title_prefix(b"app]web"), None);
        assert_eq!(title_prefix("app_wéb".as_bytes()), None);
    }

    /// instance_name() is the kernel's hostname, the one katmate-init set:
    /// read back here through /proc as an independent second reading.
    #[test]
    fn instance_name_reads_the_kernel_hostname() {
        let proc = std::fs::read("/proc/sys/kernel/hostname").expect("procfs");
        assert_eq!(instance_name(), proc.trim_ascii_end());
    }

    /// waypipe's argv: the prefix, when there is one, is a global option
    /// before `server`; without one the argv is the pre-label form.
    #[test]
    fn waypipe_argv_with_and_without_label() {
        assert_eq!(
            waypipe_argv("2:1024", Some("[app_web] "), "foot"),
            ["waypipe", "--vsock", "--socket", "2:1024", "--title-prefix", "[app_web] ", "server", "foot"]
        );
        assert_eq!(
            waypipe_argv("2:1024", None, "foot"),
            ["waypipe", "--vsock", "--socket", "2:1024", "server", "foot"]
        );
    }
}
