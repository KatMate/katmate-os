//! frame.rs — the length-prefixed codec + VSOCK transport.
//!
//! CODE SESSION: this is the existing `agent/src/protocol.rs`, moved, with
//! exactly ONE structural change (below). Everything else — PROTOCOL_VERSION,
//! STATUS_OK/ERR, MAX_ARGC / MAX_ARG_LEN / MAX_FILE_SIZE, read_exact/write_all,
//! the streaming helpers, encode_request / write_request / read_response —
//! carries over verbatim.
//!
//! THE ONE CHANGE: `read_request` no longer maps the opcode byte.
//!
//!   before:  Request { cmd: Cmd, args, payload }   // Cmd::from_u8 inside
//!   after:   RawRequest { opcode: u8, args, payload }
//!
//! The shared decoder validates the wire (version, argc, every length) and then
//! stops. Mapping opcode -> handler is the CALLER's job, via its own `Op` enum.
//! This is what makes a forbidden opcode fail at decode in the binary that must
//! not run it, rather than at a runtime gate (ADR-021).
//!
//! What moves OUT of here (they were never protocol — they were vm-agent
//! policy, and netvm-agent must not inherit them):
//!   WHITELIST, HOME_PREFIX, INIT_SOCK, SHUTDOWN_CMD,
//!   DEFAULT_WAYPIPE_PORT, DEFAULT_HOST_CID   -> crates/vm-agent
//! What stays (genuinely shared transport):
//!   PROTOCOL_VERSION, STATUS_*, MAX_*, DEFAULT_CONTROL_PORT
//!
//! (Placeholder — the real body is the current protocol.rs with that change.)

use std::os::fd::RawFd;

use crate::error::Result;

pub const PROTOCOL_VERSION: u8 = 0x01;

pub const STATUS_OK: u8 = 0x00;
pub const STATUS_ERR: u8 = 0x01;

pub const MAX_ARGC: u8 = 8;
pub const MAX_ARG_LEN: u32 = 4096;
pub const MAX_FILE_SIZE: u64 = 100 * 1024 * 1024;

/// Control-channel VSOCK port. Shared: both agents listen on it (in different
/// CIDs), and the client dials it.
pub const DEFAULT_CONTROL_PORT: u32 = 1025;

/// A decoded request, with the opcode left RAW. The shared codec has validated
/// the frame but deliberately formed no opinion about what the opcode means.
#[derive(Debug)]
pub struct RawRequest {
    pub opcode: u8,
    pub args: Vec<Vec<u8>>,
    pub payload: Vec<u8>,
}

impl RawRequest {
    /// Argument `i` as UTF-8, or an error. (Unchanged from Request::arg_str.)
    pub fn arg_str(&self, _i: usize) -> Result<&str> {
        todo!("move from protocol.rs::Request::arg_str")
    }
}

#[derive(Debug)]
pub struct Response {
    pub status: u8,
    pub payload: Vec<u8>,
}

/// Decode one request. Validates version + all lengths; does NOT map the opcode.
pub fn read_request(_fd: RawFd) -> Result<RawRequest> {
    todo!("move from protocol.rs::read_request, returning the raw opcode byte")
}

pub fn write_ok(_fd: RawFd) -> Result<()> {
    todo!("move from protocol.rs")
}

pub fn write_err(_fd: RawFd) -> Result<()> {
    todo!("move from protocol.rs")
}

/// Encode a request. Takes the opcode as a raw value from `crate::opcode` —
/// the client drives BOTH agents, so it is not constrained to one binary's Op.
pub fn write_request(_fd: RawFd, _op: u8, _args: &[&[u8]], _payload: &[u8]) -> Result<()> {
    todo!("move from protocol.rs::write_request; cmd.to_u8() -> plain u8 arg")
}

pub fn read_response(_fd: RawFd) -> Result<Response> {
    todo!("move from protocol.rs")
}

// Streaming helpers (FILEGET/FILEPUT), unchanged:
//   write_response_header, write_raw, read_raw
