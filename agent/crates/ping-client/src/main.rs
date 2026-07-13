//! ping-client — host-side client for the KatMate control channel.
//!
//! CODE SESSION: MOVE of `bin/ping-client/src/main.rs`. The note its header
//! already carried — "when a katmate-protocol crate exists, the two `mod` lines
//! become `use katmate_protocol::*` and the symlinks go away, nothing else
//! changes" — is now cashed in. Exactly that, and nothing else: the
//! `#[allow(dead_code)]` markers go too (unused `pub` items in a library crate
//! do not fire dead_code).
//!
//! This is the one binary that legitimately spans BOTH agents — it drives appVM
//! (run / fileget / fileput / shutdown) and netVM (netcfg) — which is precisely
//! why opcode VALUES live in a shared registry while enums and handlers do not.
//! The client encodes raw `opcode::OP_*` values and has no `Op` enum of its own,
//! because it executes nothing. It is a wire driver, not a policy domain.
//!
//! Sending a "forbidden" opcode is allowed here, and SHOULD be: it is how the
//! absent-not-disabled property gets tested against a live agent rather than
//! only in a unit test. `ping-client run 3 foot` (RUN aimed at netVM) must come
//! back ERR — the agent failing at decode — not a launched process.
//!
//! Subcommands after the move:
//!   ping-client ping     <cid> [port]
//!   ping-client run      <cid> <app> [port]     (appVM only)
//!   ping-client shutdown <cid> [port]           (appVM only; netVM = host QMP)
//!   ping-client netcfg   <cid> <...> [port]     (netVM; arg shape lands with
//!                                                the NETCFG payload design)
//!
//! PATH CHANGE, do not forget: the binary is now
//!   agent/target/release/ping-client   (was bin/ping-client/target/release/...)
//! Anything on MINIS that invokes it, plus the rsync exclude set (which lists
//! `agent/target/`), needs the update.

fn main() {
    todo!("move from bin/ping-client/src/main.rs; use katmate_protocol frame + opcode")
}
