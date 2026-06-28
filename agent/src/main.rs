//! vm-agent — VSOCK control agent for Katmate guests.
//!
//! Runs inside each guest (as the unprivileged session user, started by
//! a systemd --user unit). It speaks a small binary, length-prefixed
//! protocol over a VSOCK control channel and accepts connections only
//! from the host CID.
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

mod config;
mod error;
mod protocol;

use std::os::fd::RawFd;

use config::Config;
use error::{AgentError, Result};
use protocol::{Cmd, Request};

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

// --- path confinement ----------------------------------------------

/// Check that `path` is confined under HOME_PREFIX and contains no
/// parent-directory (`..`) components. This is traversal-safe without
/// requiring the path to exist (FILEPUT targets may be new files), so
/// it does not rely on canonicalize(), which fails on missing paths.
///
/// We reject `..` outright rather than trying to resolve it: inside the
/// confined subtree there is no legitimate need for it, and rejecting
/// is simpler to reason about than normalising.
fn path_is_allowed(path: &str) -> bool {
    use std::path::Component;

    if !path.starts_with(protocol::HOME_PREFIX) {
        return false;
    }
    // Absolute path with no `..` component anywhere. RootDir and Normal
    // components are fine; ParentDir is not; CurDir is harmless but we
    // allow it. A `Prefix` component cannot occur on Unix.
    std::path::Path::new(path)
        .components()
        .all(|c| !matches!(c, Component::ParentDir))
}

// --- command handlers ----------------------------------------------
// Each returns Result<()>. An Err is logged once by the caller and
// turned into an ERR response; the connection stays open for the next
// request unless the error indicates the peer is gone.

/// PING → OK.
fn handle_ping(fd: RawFd) -> Result<()> {
    protocol::write_ok(fd)
}

/// RUN <app> → launch `app` under waypipe (GUI forwarded over VSOCK).
fn handle_run(fd: RawFd, req: &Request, cfg: &Config) -> Result<()> {
    let app = req.arg_str(0)?;

    if !protocol::WHITELIST.contains(&app) {
        log_error("RUN", &AgentError::AppNotAllowed(app.to_string()));
        return protocol::write_err(fd);
    }

    // waypipe --vsock --socket <host_cid>:<waypipe_port> server <app>
    // The socket argument is composed from configuration rather than
    // hardcoded; host_cid/waypipe_port come from the environment (the
    // unit) or the protocol defaults.
    let socket_arg = format!("{}:{}", cfg.host_cid, cfg.waypipe_port);
    let argv = ["waypipe", "--vsock", "--socket", &socket_arg, "server", app];

    // Debug visibility into exactly how waypipe is launched — this is
    // the information that was missing when the Wayland environment was
    // hard to get right. Compiled out of release builds.
    log_debug!("RUN argv: {argv:?}");
    log_debug!(
        "RUN env: WAYLAND_DISPLAY={:?} XDG_RUNTIME_DIR={:?}",
        std::env::var("WAYLAND_DISPLAY").ok(),
        std::env::var("XDG_RUNTIME_DIR").ok()
    );

    match spawn(&argv) {
        Ok(pid) => {
            log_debug!("RUN spawned waypipe pid {pid}");
            protocol::write_ok(fd)
        }
        Err(e) => {
            log_error("RUN spawn", &e);
            protocol::write_err(fd)
        }
    }
}

/// FILEGET <path> → OK + file bytes, streamed (never fully buffered).
fn handle_fileget(fd: RawFd, req: &Request) -> Result<()> {
    use std::io::Read;

    let path = req.arg_str(0)?;
    if !path_is_allowed(path) {
        log_error("FILEGET", &AgentError::PathNotAllowed(path.to_string()));
        return protocol::write_err(fd);
    }

    let mut file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(e) => {
            log_error("FILEGET open", &AgentError::Io(e));
            return protocol::write_err(fd);
        }
    };

    let size = match file.metadata() {
        Ok(m) => m.len(),
        Err(e) => {
            log_error("FILEGET stat", &AgentError::Io(e));
            return protocol::write_err(fd);
        }
    };

    if size > protocol::MAX_FILE_SIZE {
        log_error("FILEGET", &AgentError::PayloadTooLarge(size));
        return protocol::write_err(fd);
    }

    // Announce the size, then stream the body in fixed-size chunks. If
    // the file shrinks under us mid-stream we stop early; the announced
    // length would then be wrong, so we surface that as an error to the
    // caller (the connection is suspect at that point).
    protocol::write_response_header(fd, protocol::STATUS_OK, size)?;

    let mut buf = [0u8; 64 * 1024];
    let mut sent: u64 = 0;
    while sent < size {
        let want = std::cmp::min(buf.len() as u64, size - sent) as usize;
        let n = file.read(&mut buf[..want])?;
        if n == 0 {
            // File ended before the announced size — truncated read.
            return Err(AgentError::UnexpectedEof);
        }
        protocol::write_raw(fd, &buf[..n])?;
        sent += n as u64;
    }
    Ok(())
}

/// FILEPUT <path> (+payload) → write payload to path, streamed.
fn handle_fileput(fd: RawFd, req: &Request) -> Result<()> {
    use std::io::Write;

    let path = req.arg_str(0)?;
    if !path_is_allowed(path) {
        log_error("FILEPUT", &AgentError::PathNotAllowed(path.to_string()));
        return protocol::write_err(fd);
    }

    // The payload was already read into req.payload by read_request,
    // bounded by MAX_FILE_SIZE. Write it via a temp file + atomic
    // rename so a failed transfer never leaves a partial file in place.
    let tmp_path = format!("{path}.vm-agent.partial");

    let mut tmp = match std::fs::File::create(&tmp_path) {
        Ok(f) => f,
        Err(e) => {
            log_error("FILEPUT create", &AgentError::Io(e));
            return protocol::write_err(fd);
        }
    };

    if let Err(e) = tmp.write_all(&req.payload) {
        log_error("FILEPUT write", &AgentError::Io(e));
        let _ = std::fs::remove_file(&tmp_path);
        return protocol::write_err(fd);
    }

    if let Err(e) = tmp.sync_all() {
        log_error("FILEPUT sync", &AgentError::Io(e));
        let _ = std::fs::remove_file(&tmp_path);
        return protocol::write_err(fd);
    }
    drop(tmp);

    if let Err(e) = std::fs::rename(&tmp_path, path) {
        log_error("FILEPUT rename", &AgentError::Io(e));
        let _ = std::fs::remove_file(&tmp_path);
        return protocol::write_err(fd);
    }

    protocol::write_ok(fd)
}

/// SHUTDOWN → OK, then ask PID 1 (katmate-init) to power the VM off.
fn handle_shutdown(fd: RawFd) -> Result<()> {
    // Reply before signalling, as the original did: the host gets its
    // acknowledgement even though the VM is about to go down.
    protocol::write_ok(fd)?;

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

    let path = protocol::INIT_SOCK.as_bytes();
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
            protocol::SHUTDOWN_CMD.as_ptr() as *const libc::c_void,
            protocol::SHUTDOWN_CMD.len(),
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

// --- child spawning (posix_spawn) ----------------------------------

/// Spawn `argv[0]` with arguments `argv`, searching PATH, inheriting the
/// agent's environment. Returns the child PID. Uses posix_spawn so all
/// argument marshalling happens in the parent — no allocation or other
/// non-async-signal-safe work between fork and exec.
fn spawn(argv: &[&str]) -> Result<libc::pid_t> {
    use std::ffi::CString;

    // Build owned C strings; these must outlive the posix_spawn call.
    let c_args: Vec<CString> = argv
        .iter()
        .map(|a| CString::new(*a))
        .collect::<std::result::Result<_, _>>()
        .map_err(|_| AgentError::Rejected("argument contains NUL byte"))?;

    // argv array of pointers into c_args, NULL-terminated.
    let mut c_argv: Vec<*const libc::c_char> =
        c_args.iter().map(|c| c.as_ptr()).collect();
    c_argv.push(std::ptr::null());

    let mut pid: libc::pid_t = 0;

    // File actions: in release builds, redirect the child's stderr to
    // /dev/null. In debug builds, leave stderr inherited (→ journal).
    let mut actions: libc::posix_spawn_file_actions_t =
        unsafe { std::mem::zeroed() };
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

    // SAFETY: c_argv is NULL-terminated and its pointers reference
    // c_args, which is still alive. environ gives the child our
    // environment (inheriting WAYLAND_DISPLAY / XDG_RUNTIME_DIR from the
    // unit). posix_spawnp searches PATH for argv[0].
    let rc = unsafe {
        libc::posix_spawnp(
            &mut pid,
            c_argv[0],
            &actions,
            std::ptr::null(),
            c_argv.as_ptr() as *const *mut libc::c_char,
            environ(),
        )
    };

    // SAFETY: actions was initialised; destroy it exactly once.
    unsafe {
        libc::posix_spawn_file_actions_destroy(&mut actions);
    }

    if rc != 0 {
        return Err(AgentError::SpawnFailed(std::io::Error::from_raw_os_error(rc)));
    }
    Ok(pid)
}

/// The process environment pointer, for passing to posix_spawn.
fn environ() -> *const *mut libc::c_char {
    extern "C" {
        static environ: *const *mut libc::c_char;
    }
    // SAFETY: `environ` is the standard POSIX global; reading the
    // pointer is safe. posix_spawn only reads through it.
    unsafe { environ }
}

// --- per-connection loop -------------------------------------------

/// Handle one accepted connection until the peer disconnects or a fatal
/// stream error occurs. Each request is dispatched; per-request errors
/// are logged and answered with ERR, but the connection continues. A
/// disconnect (EOF at a frame boundary) ends the loop quietly.
fn handle_connection(fd: RawFd, cfg: &Config) {
    loop {
        let req = match protocol::read_request(fd) {
            Ok(r) => r,
            Err(e) => {
                if !e.is_disconnect() {
                    log_error("read_request", &e);
                    // Try to inform the peer; ignore failure (peer may
                    // already be gone).
                    let _ = protocol::write_err(fd);
                }
                return;
            }
        };

        let result = match req.cmd {
            Cmd::Ping => handle_ping(fd),
            Cmd::Run => handle_run(fd, &req, cfg),
            Cmd::FileGet => handle_fileget(fd, &req),
            Cmd::FilePut => handle_fileput(fd, &req),
            Cmd::Shutdown => handle_shutdown(fd),
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
