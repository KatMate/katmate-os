//! vm-agent — VSOCK control agent for KatMate appVMs (uid 1000).
//!
//! CODE SESSION: this is the existing `agent/src/main.rs`, essentially
//! UNCHANGED. Every design note in its header still holds (synchronous
//! single-client, std+libc only, posix_spawn, SIGCHLD=SIG_IGN, SHUTDOWN
//! delegated to PID 1 rather than privileging the agent). Only two things move:
//!
//!   1. `mod protocol; mod error;`  ->  `use katmate_protocol::{frame, opcode};`
//!   2. dispatch matches on the LOCAL `Op` (op.rs), obtained via
//!      `Op::try_from(req.opcode)?`, instead of the codec handing back a `Cmd`.
//!
//! The vm-agent-only policy constants that used to sit in protocol.rs live here
//! now — they are appVM policy, not wire format, and netvm-agent must not
//! inherit them:
//!
//!   WHITELIST            (firefox-esr / foot / nautilus)
//!   HOME_PREFIX          (/home/user/)
//!   INIT_SOCK            (/run/katmate-init.sock)
//!   SHUTDOWN_CMD         (b"SHUTDOWN")
//!   DEFAULT_HOST_CID     (2)      -- waypipe target, not protocol
//!   DEFAULT_WAYPIPE_PORT (1024)   -- GUI channel, not the control channel
//!
//! REGRESSION GATE for the workspace split: `ping-client ping 5 -> OK` and a
//! GUI `run 5 nautilus` must BOTH still pass before netvm-agent is touched.
//! This crate's behaviour must be bit-identical to the pre-split agent; if the
//! gate fails, the split is wrong, not the agent.

mod config;
mod op;

fn main() {
    todo!("move from agent/src/main.rs; dispatch on op::Op::try_from(req.opcode)")
}
