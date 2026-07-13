//! error.rs — the shared error type and Result alias.
//!
//! CODE SESSION: this is a MOVE of the existing `agent/src/error.rs`, verbatim.
//! Nothing in it needs to change: it is already binary-agnostic (no opcode
//! knowledge, no handler knowledge), which is precisely why it can be shared.
//!
//! One note for the move: `AgentError::UnknownCommand(u8)` keeps its name and
//! its meaning, but it now fires in a NEW and more important place. Previously
//! it came from `Cmd::from_u8` inside the shared decoder. Now the shared
//! decoder does not map opcodes at all — so this variant is what a per-binary
//! `Op::try_from(raw)` returns when a binary is handed an opcode it must not
//! execute. It IS the "absent, not disabled" rejection (ADR-021): RUN sent to
//! netvm-agent, or NETCFG sent to vm-agent, surfaces here.
//!
//! (Placeholder — the real body is the current error.rs, unchanged.)

use std::fmt;

#[derive(Debug)]
pub enum AgentError {
    // ... unchanged from agent/src/error.rs ...
    Io(std::io::Error),
    UnexpectedEof,
    VersionMismatch { got: u8, expected: u8 },
    /// Opcode not handled by THIS binary (see module docs).
    UnknownCommand(u8),
    TooManyArguments(u8),
    ArgumentTooLarge(u32),
    PayloadTooLarge(u64),
    MissingArgument(usize),
    InvalidArgumentEncoding(usize),
    AppNotAllowed(String),
    PathNotAllowed(String),
    SpawnFailed(std::io::Error),
    Rejected(&'static str),
}

pub type Result<T> = std::result::Result<T, AgentError>;

impl fmt::Display for AgentError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // ... unchanged ...
        write!(f, "{self:?}")
    }
}

impl std::error::Error for AgentError {}

impl From<std::io::Error> for AgentError {
    fn from(e: std::io::Error) -> Self {
        AgentError::Io(e)
    }
}

impl AgentError {
    pub fn is_disconnect(&self) -> bool {
        matches!(self, AgentError::UnexpectedEof)
    }
}
