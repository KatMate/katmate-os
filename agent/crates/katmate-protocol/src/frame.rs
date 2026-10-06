//! frame.rs — wire-format definition and codec for the KatMate VSOCK
//! control channel. Single source of truth for the protocol (the design
//! item previously called "protocol.h").
//!
//! This is the old `agent/src/protocol.rs`, promoted into the shared
//! `katmate-protocol` crate — the graduation its own header anticipated.
//! Both agents and the host client now link the same encoder/decoder:
//! the agents use read_request + write_response, the client uses
//! write_request + read_response.
//!
//! THE ONE STRUCTURAL CHANGE on promotion: `read_request` no longer maps
//! the opcode byte.
//!
//!   before:  Request    { cmd: Cmd, args, payload }   // Cmd::from_u8 inside
//!   after:   RawRequest { opcode: u8, args, payload }
//!
//! The shared decoder validates the wire (version, argc, every length)
//! and then stops. Mapping opcode -> handler is the CALLER's job, via its
//! own `Op` enum (see `crate::opcode` for the value registry, and each
//! binary's `op.rs` for what it may actually execute). This is what makes
//! a forbidden opcode fail at DECODE in the binary that must not run it,
//! rather than at a runtime gate (ADR-021).
//!
//! What is NOT here — it was never protocol, it was appVM policy, and
//! netvm-agent must not inherit it: WHITELIST, INIT_SOCK, SHUTDOWN_CMD,
//! DEFAULT_WAYPIPE_PORT, DEFAULT_HOST_CID. Those live in `crates/vm-agent`.
//!
//! Wire format (PROTOCOL v1, little-endian, daemon-to-daemon):
//!
//! REQUEST
//!   u8    version        (PROTOCOL_VERSION)
//!   u8    opcode         (a value from `crate::opcode`)
//!   u8    argc           (number of arguments, <= MAX_ARGC)
//!   u64   payload_len    (trailing payload size, <= MAX_PAYLOAD)
//!   repeated argc times:
//!     u32 arg_len        (<= MAX_ARG_LEN)
//!     u8[arg_len] arg    (raw bytes; space / newline / NUL allowed)
//!   u8[payload_len] payload   (present iff payload_len > 0)
//!
//! RESPONSE
//!   u8    version        (PROTOCOL_VERSION)
//!   u8    status         (0x00 OK, 0x01 ERR)
//!   u64   payload_len    (<= MAX_PAYLOAD; 0 if none)
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

/// Maximum payload size, in bytes (64 KiB), in either direction: one
/// constant, read by `read_request` and `read_response` alike. It replaced
/// the C-era MAX_FILE_SIZE (100 MiB) when the file opcodes that sized it were
/// retired (`crate::opcode::RETIRED`; operator ruling of 2026-10-06). The
/// largest payload any handler reads is a NETCFG ADD at netvm-agent's
/// MAX_ROUTES, 57 bytes (21 + 4 x 9; a test there pins it), and v1 accepts at
/// most 30. RUN, PING and SHUTDOWN carry none, and no response carries one.
/// An unhandled opcode is read in full before its ERR, so this is also the
/// most such a request can make an agent allocate for its payload.
pub const MAX_PAYLOAD: u64 = 64 * 1024;

// --- transport default ---------------------------------------------

/// Control-channel VSOCK port. Genuinely shared: both agents listen on
/// it (in different CIDs) and the client dials it. Overridable from the
/// environment; this is the source-of-truth fallback.
pub const DEFAULT_CONTROL_PORT: u32 = 1025;

// --- decoded request -----------------------------------------------

/// A decoded request, with the opcode left RAW. The shared codec has
/// validated the frame but deliberately formed no opinion about what the
/// opcode means — that is the caller's `Op` enum. `payload` holds the
/// trailing bytes (NETCFG's structured body); for opcodes without a
/// payload it is empty.
#[derive(Debug)]
pub struct RawRequest {
    pub opcode: u8,
    pub args: Vec<Vec<u8>>,
    pub payload: Vec<u8>,
}

impl RawRequest {
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

/// A decoded response. The client cares about `status` (OK / ERR). No
/// opcode answers with a payload today, but the frame carries a
/// `payload_len`, so it is decoded and bounded. The mirror of the agent's
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

/// Read and decode one request from `fd`. Validates the version and
/// every length field against the configured limits before allocating
/// for arguments or payload. It does NOT map the opcode: the raw byte is
/// handed back in `RawRequest::opcode`, and the caller decides — via its
/// own `Op::try_from` — whether it is an opcode this binary may execute
/// at all (ADR-021).
///
/// On a clean connection close at a frame boundary this returns
/// AgentError::UnexpectedEof, which the caller treats as "client
/// disconnected".
pub fn read_request(fd: RawFd) -> Result<RawRequest> {
    // Fixed header: version, opcode, argc, payload_len.
    let version = read_u8(fd)?;
    if version != PROTOCOL_VERSION {
        return Err(AgentError::VersionMismatch {
            got: version,
            expected: PROTOCOL_VERSION,
        });
    }

    // Raw, unmapped. The codec has no opinion about who may run what.
    let opcode = read_u8(fd)?;

    let argc = read_u8(fd)?;
    if argc > MAX_ARGC {
        return Err(AgentError::TooManyArguments(argc));
    }

    let payload_len = read_u64(fd)?;
    if payload_len > MAX_PAYLOAD {
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

    // Payload (validated above against MAX_PAYLOAD).
    let payload = if payload_len > 0 {
        let mut p = vec![0u8; payload_len as usize];
        read_exact(fd, &mut p)?;
        p
    } else {
        Vec::new()
    };

    Ok(RawRequest {
        opcode,
        args,
        payload,
    })
}

// --- response encoding (agent side) --------------------------------

/// Write an OK response with no payload.
pub fn write_ok(fd: RawFd) -> Result<()> {
    write_response(fd, STATUS_OK, &[])
}

/// Write an ERR response with no payload.
pub fn write_err(fd: RawFd) -> Result<()> {
    write_response(fd, STATUS_ERR, &[])
}

/// Encode and write a response header followed by its payload. Every
/// response today is written with an empty payload (write_ok, write_err).
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

// --- client-side codec (request encoding / response decoding) ------
// The mirror image of read_request + write_response above. The agent
// binaries link but do not call these; the host-side client uses them to
// talk to either agent. Keeping both halves in one module is exactly
// what let this file graduate to the shared `katmate-protocol` crate:
// in a library crate `pub` items do not fire dead_code, so the
// #[allow(dead_code)] attributes the pre-workspace file carried are now
// simply unnecessary and have been dropped.

/// Encode a request into a single owned buffer. Pure and infallible:
/// the wire format is a fixed header plus length-prefixed fields, and
/// every *validation* lives on the decode side (read_request), where
/// an untrusted peer sits on the other end. Kept separate from
/// write_request so it can be unit-tested without a socket.
///
/// `op` is a raw value from `crate::opcode`, not a typed command: the
/// client drives BOTH agents, so it is not constrained to any one
/// binary's `Op`. Encoding an opcode grants nothing — the agent that
/// receives it still has to have a handler for it.
pub fn encode_request(op: u8, args: &[&[u8]], payload: &[u8]) -> Vec<u8> {
    let mut buf = Vec::with_capacity(1 + 1 + 1 + 8 + payload.len());
    buf.push(PROTOCOL_VERSION);
    buf.push(op);
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
pub fn write_request(fd: RawFd, op: u8, args: &[&[u8]], payload: &[u8]) -> Result<()> {
    write_all(fd, &encode_request(op, args, payload))
}

/// Read and decode one response from `fd`. The symmetric counterpart
/// to the agent's write_response: it validates the version and bounds
/// the payload length against MAX_PAYLOAD before allocating, exactly
/// as read_request does for the request direction.
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
    if payload_len > MAX_PAYLOAD {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::opcode;

    /// encode_request is pure: assert the header shape against the wire
    /// spec in the module docs, so a silent field reordering cannot pass
    /// CI unnoticed.
    #[test]
    fn encode_request_header_shape() {
        let buf = encode_request(opcode::OP_RUN, &[b"foot"], &[]);
        assert_eq!(buf[0], PROTOCOL_VERSION);
        assert_eq!(buf[1], opcode::OP_RUN);
        assert_eq!(buf[2], 1); // argc
        assert_eq!(&buf[3..11], &0u64.to_le_bytes()); // payload_len
        assert_eq!(&buf[11..15], &4u32.to_le_bytes()); // arg_len
        assert_eq!(&buf[15..19], b"foot");
        assert_eq!(buf.len(), 19);
    }

    /// The codec is opcode-agnostic BY CONSTRUCTION: it will happily
    /// encode a byte no binary handles. That is not a hole — the
    /// receiving agent rejects it in `Op::try_from`. This test pins the
    /// property, because the moment the codec starts policing opcodes,
    /// the ADR-021 boundary has silently moved back into the shared
    /// crate, which is exactly what the split was for.
    #[test]
    fn max_payload_is_64_kib() {
        assert_eq!(MAX_PAYLOAD, 65_536);
    }

    fn pair() -> (RawFd, RawFd) {
        let mut sv = [0 as RawFd; 2];
        // SAFETY: sv is a valid two-element out-array for socketpair.
        let rc = unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_STREAM, 0, sv.as_mut_ptr()) };
        assert_eq!(rc, 0, "socketpair: {}", std::io::Error::last_os_error());
        (sv[0], sv[1])
    }

    fn close(fds: [RawFd; 2]) {
        // SAFETY: both are valid fds the caller owns; each closed once here.
        unsafe {
            libc::close(fds[0]);
            libc::close(fds[1]);
        }
    }

    fn request_header(len: u64) -> Vec<u8> {
        let mut h = vec![PROTOCOL_VERSION, opcode::OP_PING, 0];
        h.extend_from_slice(&len.to_le_bytes());
        h
    }

    /// A request header declaring MAX_PAYLOAD + 1 is refused at the length
    /// check, before the decoder allocates for or reads the payload. No
    /// payload byte follows the header and the writer is shut, so a decoder
    /// that allocated and read first would end in UnexpectedEof instead: the
    /// variant is what tells the two orders apart.
    #[test]
    fn oversized_payload_len_is_refused_before_allocation() {
        let (rx, tx) = pair();
        write_all(tx, &request_header(MAX_PAYLOAD + 1)).unwrap();
        // SAFETY: tx is a valid socket fd.
        unsafe { libc::shutdown(tx, libc::SHUT_WR) };
        match read_request(rx) {
            Err(AgentError::PayloadTooLarge(n)) => assert_eq!(n, MAX_PAYLOAD + 1),
            other => panic!("expected PayloadTooLarge, got {other:?}"),
        }
        close([rx, tx]);

        // The response direction carries the same bound.
        let (rx, tx) = pair();
        let mut resp = vec![PROTOCOL_VERSION, STATUS_OK];
        resp.extend_from_slice(&(MAX_PAYLOAD + 1).to_le_bytes());
        write_all(tx, &resp).unwrap();
        // SAFETY: tx is a valid socket fd.
        unsafe { libc::shutdown(tx, libc::SHUT_WR) };
        assert!(matches!(read_response(rx), Err(AgentError::PayloadTooLarge(_))));
        close([rx, tx]);
    }

    /// The bound is inclusive: a payload of exactly MAX_PAYLOAD decodes.
    #[test]
    fn max_payload_itself_is_admitted() {
        let (rx, tx) = pair();
        let mut req = request_header(MAX_PAYLOAD);
        req.extend(std::iter::repeat_n(0xA5u8, MAX_PAYLOAD as usize));
        write_all(tx, &req).unwrap();
        assert_eq!(read_request(rx).unwrap().payload.len() as u64, MAX_PAYLOAD);
        close([rx, tx]);
    }

    #[test]
    fn encoder_does_not_police_opcodes() {
        let buf = encode_request(0xFF, &[], &[]);
        assert_eq!(buf[1], 0xFF);
    }
}
