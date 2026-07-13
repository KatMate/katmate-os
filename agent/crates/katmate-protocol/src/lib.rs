//! katmate-protocol — the shared wire format for the KatMate VSOCK control
//! channel. Linked by every binary that speaks it: the appVM `vm-agent`, the
//! netVM `netvm-agent`, and the host `ping-client`.
//!
//! This crate is the promotion of the old `agent/src/protocol.rs` +
//! `agent/src/error.rs` (which `ping-client` consumed via symlinks). The
//! symlinks are gone; both halves of the codec now live here as `pub` items,
//! which also retires the `#[allow(dead_code)]` markers — in a library crate,
//! unused `pub` items do not fire dead_code.
//!
//! # What is shared, and what is deliberately NOT (ADR-021)
//!
//! Shared here:
//!   * framing + transport (`frame`): the length-prefixed request/response
//!     codec and its bounds checks. Every length is validated BEFORE it drives
//!     an allocation — the core hardening over the original C agent.
//!   * `error`: one error type for all three binaries.
//!   * `opcode`: the *registry* of on-wire opcode VALUES. One source of truth
//!     for the wire, so `ping-client` can encode any opcode and the two agents
//!     can never disagree about what byte 0x02 means.
//!
//! NOT shared — and this is the security boundary:
//!   * the opcode *enums* and their *handlers*. Each binary defines its own
//!     `Op` with `TryFrom<u8>` mapping ONLY the opcodes it is allowed to
//!     execute. `read_request` therefore returns a RAW `u8` opcode
//!     (`RawRequest`), never a pre-typed command — the shared codec has no
//!     opinion about who may do what.
//!
//! The payoff is "absent, not disabled": `netvm-agent` cannot execute RUN
//! because `RUN` does not parse into a variant of ITS `Op` — the request fails
//! at DECODE, not at a runtime `if` that someone could later invert. Same for
//! NETCFG in the unprivileged `vm-agent`. Membership in the registry below
//! grants nothing; only a handler does.

pub mod error;
pub mod frame;
pub mod opcode;

// Convenience re-exports so callers can `use katmate_protocol::{Result, ...}`
// without reaching through the module path for the items they always need.
pub use error::{AgentError, Result};
