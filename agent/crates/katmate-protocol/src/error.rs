//! error.rs — the agent's error type and Result alias.
//!
//! Every fallible operation returns `Result<T>`; errors propagate up
//! to the per-connection loop with `?`, where they are logged in a
//! structured form (journal, via stderr) and turned into an ERR
//! response. This replaces the original C agent's pattern of ignoring
//! return values and writing a bare "ERR\n".
//!
//! Moved verbatim from `agent/src/error.rs` into the shared crate: it is
//! binary-agnostic (no opcode knowledge, no handler knowledge), which is
//! precisely why it can be shared by vm-agent, netvm-agent and ping-client.

use std::fmt;

/// All error conditions the agent distinguishes. Variants are kept
/// specific enough to be useful in the journal without leaking
/// internals to the client (the client only ever sees OK / ERR).
#[derive(Debug)]
pub enum AgentError {
    /// Underlying I/O syscall failure (read/write/socket/etc.).
    Io(std::io::Error),

    /// The connection closed (or was truncated) mid-frame. At a frame
    /// boundary this is the normal "client disconnected" signal.
    UnexpectedEof,

    /// Request carried a protocol version we do not speak.
    VersionMismatch { got: u8, expected: u8 },

    /// Opcode not handled by THIS binary. It no longer comes from a shared
    /// `Cmd::from_u8` inside the decoder — the decoder does not map opcodes at
    /// all. This now fires from a per-binary `Op::try_from(raw)`, and IS the
    /// "absent, not disabled" rejection (ADR-021): RUN sent to netvm-agent, or
    /// NETCFG sent to vm-agent, surfaces here — at DECODE, not at a runtime
    /// gate someone could later invert.
    UnknownCommand(u8),

    /// argc exceeded MAX_ARGC.
    TooManyArguments(u8),

    /// An argument's declared length exceeded MAX_ARG_LEN.
    ArgumentTooLarge(u32),

    /// The declared payload length exceeded MAX_FILE_SIZE.
    PayloadTooLarge(u64),

    /// A required argument was absent (e.g. RUN with no app name).
    MissingArgument(usize),

    /// An argument expected to be text was not valid UTF-8.
    InvalidArgumentEncoding(usize),

    /// The requested app is not on the launch whitelist.
    AppNotAllowed(String),

    /// The requested path failed the confinement / traversal check.
    PathNotAllowed(String),

    /// A spawned child process could not be created.
    SpawnFailed(std::io::Error),

    /// Request was structurally valid but semantically rejected
    /// (e.g. FILEPUT with a non-positive size). Carries a short reason
    /// for the journal.
    Rejected(&'static str),
}

/// Crate-wide Result alias.
pub type Result<T> = std::result::Result<T, AgentError>;

impl fmt::Display for AgentError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AgentError::Io(e) => write!(f, "io error: {e}"),
            AgentError::UnexpectedEof => write!(f, "unexpected end of stream"),
            AgentError::VersionMismatch { got, expected } => {
                write!(
                    f,
                    "protocol version mismatch: got {got}, expected {expected}"
                )
            }
            AgentError::UnknownCommand(b) => {
                write!(f, "opcode not handled by this binary: {b:#04x}")
            }
            AgentError::TooManyArguments(n) => write!(f, "too many arguments: {n}"),
            AgentError::ArgumentTooLarge(n) => write!(f, "argument too large: {n} bytes"),
            AgentError::PayloadTooLarge(n) => write!(f, "payload too large: {n} bytes"),
            AgentError::MissingArgument(i) => write!(f, "missing argument at index {i}"),
            AgentError::InvalidArgumentEncoding(i) => {
                write!(f, "argument {i} is not valid UTF-8")
            }
            AgentError::AppNotAllowed(a) => write!(f, "app not on whitelist: {a}"),
            AgentError::PathNotAllowed(p) => write!(f, "path not allowed: {p}"),
            AgentError::SpawnFailed(e) => write!(f, "failed to spawn child: {e}"),
            AgentError::Rejected(why) => write!(f, "request rejected: {why}"),
        }
    }
}

impl std::error::Error for AgentError {}

/// Convenience: allow `?` on std::io::Result inside functions that
/// return our Result, mapping the io::Error into AgentError::Io.
impl From<std::io::Error> for AgentError {
    fn from(e: std::io::Error) -> Self {
        AgentError::Io(e)
    }
}

impl AgentError {
    /// True when this error simply means the peer closed the
    /// connection at a frame boundary, i.e. not a fault to log loudly.
    pub fn is_disconnect(&self) -> bool {
        matches!(self, AgentError::UnexpectedEof)
    }
}
