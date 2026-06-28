//! protocol.rs — wire-format definition and codec for the vm-agent
//! control channel. Single source of truth for the protocol (the
//! design item previously called "protocol.h").
//!
//! This module is intentionally self-contained: constants, the frame
//! layout, and the encode/decode routines all live here so that, once
//! a binary host-side client exists, this file can be promoted to a
//! shared `katmate-protocol` crate without a refactor — both daemons
//! would then link the same encoder/decoder. As of 2026-06-23 that
//! client exists (`ping-client`), and both halves of the codec now
//! live here: the agent uses read_request + write_response, the client
//! uses write_request + read_response.
//!
//! Wire format (PROTOCOL v1, little-endian, daemon-to-daemon):
//!
//! REQUEST
//!   u8    version        (PROTOCOL_VERSION)
//!   u8    cmd            (Cmd discriminant)
//!   u8    argc           (number of arguments, <= MAX_ARGC)
//!   u64   payload_len    (trailing payload size, <= MAX_FILE_SIZE)
//!   repeated argc times:
//!     u32 arg_len        (<= MAX_ARG_LEN)
//!     u8[arg_len] arg    (raw bytes; space / newline / NUL allowed)
//!   u8[payload_len] payload   (present iff payload_len > 0)
//!
//! RESPONSE
//!   u8    version        (PROTOCOL_VERSION)
//!   u8    status         (0x00 OK, 0x01 ERR)
//!   u64   payload_len    (<= MAX_FILE_SIZE; 0 if none)
//!   u8[payload_len] payload   (present iff payload_len > 0)
//!
//! The reader always consumes the fixed-size header first, validates
//! every length field against the limits below, and only then reads
//! variable-length data. Lengths are never trusted enough to drive an
//! allocation before validation — this is the core hardening over the
//! original C agent, which used atol() and hoped.

use std::os::fd::RawFd;

use crate::error::{AgentError, Result};

// --- protocol version ----------------------------------------------

/// On-wire protocol version. Both sides must agree. A mismatch is
/// rejected rather than silently misparsed — relevant once the
/// foundation image and the host client can be updated independently.
pub const PROTOCOL_VERSION: u8 = 0x01;

// --- response status codes -----------------------------------------

pub const STATUS_OK: u8 = 0x00;
pub const STATUS_ERR: u8 = 0x01;

// --- limits (DoS guards; every breach maps to an error, never an
// --- allocation against an unvalidated length) ---------------------

/// Maximum number of arguments in a single request.
pub const MAX_ARGC: u8 = 8;

/// Maximum length of one argument, in bytes. Paths are not longer.
pub const MAX_ARG_LEN: u32 = 4096;

/// Maximum payload size, in bytes (100 MiB). Mirrors the original C
/// MAX_FILE_SIZE and bounds both FILEPUT input and FILEGET output.
pub const MAX_FILE_SIZE: u64 = 100 * 1024 * 1024;

// --- transport defaults (overridable from the environment; see
// --- main.rs). These are the source-of-truth fallbacks. ------------

/// Control-channel VSOCK port the agent listens on. Distinct from the
/// waypipe GUI port below — they are two separate, purposeful ports.
pub const DEFAULT_CONTROL_PORT: u32 = 1025;

/// VSOCK port used by waypipe for the GUI channel (RUN). Separate from
/// the control port; the host waypipe client listens here.
pub const DEFAULT_WAYPIPE_PORT: u32 = 1024;

/// Host CID. On a standard QEMU/KVM setup the host is CID 2.
pub const DEFAULT_HOST_CID: u32 = 2;

/// Apps that RUN may launch via waypipe.
pub const WHITELIST: &[&str] = &["firefox-esr", "foot", "nautilus"];

/// Path prefix that FILEGET / FILEPUT are confined to. Note: a prefix
/// test alone is not traversal-safe; the handler additionally rejects
/// ".." components (see the path guard in main.rs).
pub const HOME_PREFIX: &str = "/home/user/";

/// Unix socket on which PID 1 (katmate-init) listens for privileged
/// requests. SHUTDOWN is delegated here rather than to a setuid helper:
/// the agent is uid 1000 and cannot call reboot(2), so it asks init —
/// the single root process in the guest — to power the VM off. This
/// must match INIT_SOCK in katmate-init.c. The socket is SOCK_SEQPACKET.
pub const INIT_SOCK: &str = "/run/katmate-init.sock";

/// Command token the agent writes to INIT_SOCK to request power-off.
/// init matches this prefix and triggers reboot(RB_AUTOBOOT).
pub const SHUTDOWN_CMD: &[u8] = b"SHUTDOWN";

// --- commands -------------------------------------------------------

/// Request command, matching the on-wire `cmd` byte.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cmd {
    Ping,
    Run,
    FileGet,
    FilePut,
    Shutdown,
}

impl Cmd {
    /// Map the on-wire byte to a command, or reject an unknown opcode.
    pub fn from_u8(b: u8) -> Result<Cmd> {
        match b {
            0x01 => Ok(Cmd::Ping),
            0x02 => Ok(Cmd::Run),
            0x03 => Ok(Cmd::FileGet),
            0x04 => Ok(Cmd::FilePut),
            0x05 => Ok(Cmd::Shutdown),
            other => Err(AgentError::UnknownCommand(other)),
        }
    }

    /// Map a command back to its on-wire byte. The inverse of from_u8.
    /// Deliberately NOT the enum discriminant: `Cmd::Ping as u8` is 0,
    /// but the wire value is 0x01, so the mapping is written out by
    /// hand. Required by the host-side client to encode requests; the
    /// agent never calls it.
    pub fn to_u8(self) -> u8 {
        match self {
            Cmd::Ping => 0x01,
            Cmd::Run => 0x02,
            Cmd::FileGet => 0x03,
            Cmd::FilePut => 0x04,
            Cmd::Shutdown => 0x05,
        }
    }
}

// --- decoded request -----------------------------------------------

/// A fully decoded request. `payload` holds the trailing bytes (for
/// FILEPUT); for commands without a payload it is empty.
#[derive(Debug)]
pub struct Request {
    pub cmd: Cmd,
    pub args: Vec<Vec<u8>>,
    pub payload: Vec<u8>,
}

impl Request {
    /// Return argument `i` as a UTF-8 string slice, or an error if it
    /// is missing or not valid UTF-8. Used for paths and app names,
    /// which are expected to be text even though the wire allows raw
    /// bytes.
    pub fn arg_str(&self, i: usize) -> Result<&str> {
        let raw = self.args.get(i).ok_or(AgentError::MissingArgument(i))?;
        std::str::from_utf8(raw).map_err(|_| AgentError::InvalidArgumentEncoding(i))
    }
}

// --- decoded response (client side) --------------------------------

/// A decoded response. The client cares about `status` (OK / ERR) and,
/// for FILEGET, the returned `payload`. The mirror of the agent's
/// write_response.
#[derive(Debug)]
pub struct Response {
    pub status: u8,
    pub payload: Vec<u8>,
}

// --- low-level fixed-size reads ------------------------------------
// These wrap a raw fd. They loop until the exact number of bytes has
// been read, returning AgentError::UnexpectedEof on a short read so a
// truncated frame can never be parsed as if it were complete.

fn read_exact(fd: RawFd, buf: &mut [u8]) -> Result<()> {
    let mut done = 0;
    while done < buf.len() {
        // SAFETY: raw read into a valid, owned slice region. We uphold
        // the fd / pointer / length invariants here, as in C.
        let r = unsafe {
            libc::read(
                fd,
                buf[done..].as_mut_ptr() as *mut libc::c_void,
                buf.len() - done,
            )
        };
        if r < 0 {
            let err = std::io::Error::last_os_error();
            // A syscall interrupted by a signal is not a failure: retry.
            if err.raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            return Err(AgentError::Io(err));
        }
        if r == 0 {
            return Err(AgentError::UnexpectedEof);
        }
        done += r as usize;
    }
    Ok(())
}

fn write_all(fd: RawFd, buf: &[u8]) -> Result<()> {
    let mut done = 0;
    while done < buf.len() {
        // SAFETY: raw write from a valid, owned slice region.
        let r = unsafe {
            libc::write(
                fd,
                buf[done..].as_ptr() as *const libc::c_void,
                buf.len() - done,
            )
        };
        if r < 0 {
            let err = std::io::Error::last_os_error();
            // A syscall interrupted by a signal is not a failure: retry.
            if err.raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            return Err(AgentError::Io(err));
        }
        if r == 0 {
            return Err(AgentError::UnexpectedEof);
        }
        done += r as usize;
    }
    Ok(())
}

fn read_u8(fd: RawFd) -> Result<u8> {
    let mut b = [0u8; 1];
    read_exact(fd, &mut b)?;
    Ok(b[0])
}

fn read_u32(fd: RawFd) -> Result<u32> {
    let mut b = [0u8; 4];
    read_exact(fd, &mut b)?;
    Ok(u32::from_le_bytes(b))
}

fn read_u64(fd: RawFd) -> Result<u64> {
    let mut b = [0u8; 8];
    read_exact(fd, &mut b)?;
    Ok(u64::from_le_bytes(b))
}

// --- request decoding (agent side) ---------------------------------

/// Read and decode one request from `fd`. Validates the version, the
/// command, and every length field against the configured limits
/// before allocating for arguments or payload. On a clean connection
/// close at a frame boundary this returns AgentError::UnexpectedEof,
/// which the caller treats as "client disconnected".
pub fn read_request(fd: RawFd) -> Result<Request> {
    // Fixed header: version, cmd, argc, payload_len.
    let version = read_u8(fd)?;
    if version != PROTOCOL_VERSION {
        return Err(AgentError::VersionMismatch {
            got: version,
            expected: PROTOCOL_VERSION,
        });
    }

    let cmd = Cmd::from_u8(read_u8(fd)?)?;

    let argc = read_u8(fd)?;
    if argc > MAX_ARGC {
        return Err(AgentError::TooManyArguments(argc));
    }

    let payload_len = read_u64(fd)?;
    if payload_len > MAX_FILE_SIZE {
        return Err(AgentError::PayloadTooLarge(payload_len));
    }

    // Arguments: each is length-prefixed; the length is validated
    // before the bytes are read, so a hostile length cannot drive a
    // large allocation.
    let mut args: Vec<Vec<u8>> = Vec::with_capacity(argc as usize);
    for _ in 0..argc {
        let arg_len = read_u32(fd)?;
        if arg_len > MAX_ARG_LEN {
            return Err(AgentError::ArgumentTooLarge(arg_len));
        }
        let mut arg = vec![0u8; arg_len as usize];
        read_exact(fd, &mut arg)?;
        args.push(arg);
    }

    // Payload (validated above against MAX_FILE_SIZE).
    let payload = if payload_len > 0 {
        let mut p = vec![0u8; payload_len as usize];
        read_exact(fd, &mut p)?;
        p
    } else {
        Vec::new()
    };

    Ok(Request { cmd, args, payload })
}

// --- response encoding (agent side) --------------------------------

/// Write an OK response with no payload.
pub fn write_ok(fd: RawFd) -> Result<()> {
    write_response(fd, STATUS_OK, &[])
}

/// Write an OK response carrying a payload (e.g. FILEGET file bytes).
pub fn write_ok_payload(fd: RawFd, payload: &[u8]) -> Result<()> {
    write_response(fd, STATUS_OK, payload)
}

/// Write an ERR response with no payload.
pub fn write_err(fd: RawFd) -> Result<()> {
    write_response(fd, STATUS_ERR, &[])
}

/// Encode and write a response header followed by its payload. The
/// header is assembled in a small stack buffer and written first, then
/// the payload streams out — so a large FILEGET does not require
/// buffering the whole file plus a header copy.
fn write_response(fd: RawFd, status: u8, payload: &[u8]) -> Result<()> {
    let mut header = [0u8; 1 + 1 + 8];
    header[0] = PROTOCOL_VERSION;
    header[1] = status;
    header[2..10].copy_from_slice(&(payload.len() as u64).to_le_bytes());
    write_all(fd, &header)?;
    if !payload.is_empty() {
        write_all(fd, payload)?;
    }
    Ok(())
}

// --- streaming helpers for large file bodies -----------------------
// FILEGET / FILEPUT must not hold an entire file in memory just to
// frame it. These expose the validated low-level primitives so the
// handlers can stream directly between a file and the socket while
// still going through this module's bounds-checked reads/writes.

/// Write a response header announcing `payload_len` bytes to follow,
/// without sending the payload itself. The caller then streams exactly
/// `payload_len` bytes via `write_raw`. Used by FILEGET to send a file
/// without buffering it.
pub fn write_response_header(fd: RawFd, status: u8, payload_len: u64) -> Result<()> {
    let mut header = [0u8; 1 + 1 + 8];
    header[0] = PROTOCOL_VERSION;
    header[1] = status;
    header[2..10].copy_from_slice(&payload_len.to_le_bytes());
    write_all(fd, &header)
}

/// Stream raw bytes to the socket (post-header). Thin wrapper over the
/// bounds-checked write loop.
pub fn write_raw(fd: RawFd, buf: &[u8]) -> Result<()> {
    write_all(fd, buf)
}

/// Read raw bytes from the socket into `buf` (used when streaming a
/// FILEPUT payload to disk in chunks). Thin wrapper over read_exact.
pub fn read_raw(fd: RawFd, buf: &mut [u8]) -> Result<()> {
    read_exact(fd, buf)
}

// --- client-side codec (request encoding / response decoding) ------
// The mirror image of read_request + write_response above. The agent
// binary links but does not call these (hence #[allow(dead_code)] —
// the same treatment the streaming helpers get until wired); the
// host-side client uses them to talk to the agent. Keeping both halves
// in one module is exactly what lets this file graduate to a shared
// `katmate-protocol` crate: in a library crate `pub` items do not fire
// dead_code, so the attributes below simply become unnecessary.

/// Encode a request into a single owned buffer. Pure and infallible:
/// the wire format is a fixed header plus length-prefixed fields, and
/// every *validation* lives on the decode side (read_request), where
/// an untrusted peer sits on the other end. Kept separate from
/// write_request so it can be unit-tested without a socket.
#[allow(dead_code)]
pub fn encode_request(cmd: Cmd, args: &[&[u8]], payload: &[u8]) -> Vec<u8> {
    let mut buf = Vec::with_capacity(1 + 1 + 1 + 8 + payload.len());
    buf.push(PROTOCOL_VERSION);
    buf.push(cmd.to_u8());
    buf.push(args.len() as u8);
    buf.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    for arg in args {
        buf.extend_from_slice(&(arg.len() as u32).to_le_bytes());
        buf.extend_from_slice(arg);
    }
    buf.extend_from_slice(payload);
    buf
}

/// Encode and send a request on `fd`. The symmetric counterpart to the
/// agent's read_request.
#[allow(dead_code)]
pub fn write_request(fd: RawFd, cmd: Cmd, args: &[&[u8]], payload: &[u8]) -> Result<()> {
    write_all(fd, &encode_request(cmd, args, payload))
}

/// Read and decode one response from `fd`. The symmetric counterpart
/// to the agent's write_response: it validates the version and bounds
/// the payload length against MAX_FILE_SIZE before allocating, exactly
/// as read_request does for the request direction.
#[allow(dead_code)]
pub fn read_response(fd: RawFd) -> Result<Response> {
    let version = read_u8(fd)?;
    if version != PROTOCOL_VERSION {
        return Err(AgentError::VersionMismatch {
            got: version,
            expected: PROTOCOL_VERSION,
        });
    }

    let status = read_u8(fd)?;

    let payload_len = read_u64(fd)?;
    if payload_len > MAX_FILE_SIZE {
        return Err(AgentError::PayloadTooLarge(payload_len));
    }

    let payload = if payload_len > 0 {
        let mut p = vec![0u8; payload_len as usize];
        read_exact(fd, &mut p)?;
        p
    } else {
        Vec::new()
    };

    Ok(Response { status, payload })
}
