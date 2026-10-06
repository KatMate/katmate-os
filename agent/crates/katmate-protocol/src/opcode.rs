//! opcode.rs — the shared registry of on-wire opcode VALUES.
//!
//! This is a registry, NOT a capability grant. It exists so that the wire has
//! exactly one definition (and so the host client can encode any opcode it
//! needs to drive either agent). What a given binary may actually *execute* is
//! decided elsewhere: in that binary's own `Op` enum + `TryFrom<u8>` + handler
//! set. See the crate-level docs and ADR-021.
//!
//! Values are the ones already on the wire (from the pre-workspace
//! `protocol.rs::Cmd::to_u8`) — they are NOT enum discriminants and must not be
//! renumbered: a foundation image and a host client can be updated
//! independently, so these bytes are a compatibility surface.
//!
//! Who handles what (ADR-021; the SHUTDOWN row as ADR-024 changed it):
//!
//! | opcode   | vm-agent (appVM, uid 1000) | netvm-agent (CAP_NET_ADMIN) |
//! |----------|----------------------------|-----------------------------|
//! | PING     | handler                    | handler                     |
//! | RUN      | handler (whitelist)        | absent                      |
//! | 0x03     | retired (was FILEGET)      | retired                     |
//! | 0x04     | retired (was FILEPUT)      | retired                     |
//! | SHUTDOWN | handler (-> katmate-init)  | handler (-> systemd, PID 1) |
//! | NETCFG   | absent                     | handler (privileged)        |
//!
//! SHUTDOWN is handled by both agents, each asking its own PID 1 (ADR-024).
//! vm-agent asks katmate-init over its unix socket; netvm-agent signals
//! systemd with SIGRTMIN+4 under CAP_KILL. ADR-021 had left SHUTDOWN out of
//! netvm-agent on the premise that the host powers q35 down over QMP
//! `system_powerdown` -> ACPI -> logind; logind needs dbus, which netVM does not
//! carry, so that path was proven inert and ADR-024 reversed the rule.
//!
//! 0x03 (FILEGET) and 0x04 (FILEPUT) were retired on 2026-10-06: nothing on
//! the host called them, and a file surface into every AppVM was carried for
//! no user. Their values are listed in `RETIRED` and are never reused, so an
//! old host client that still sends one meets the plain ERR reply every agent
//! gives an opcode it has no variant for — never a different handler.

/// Liveness check. The only opcode BOTH agents handle.
pub const OP_PING: u8 = 0x01;

/// Launch a whitelisted app under waypipe. appVM only.
pub const OP_RUN: u8 = 0x02;

/// Values that once named an opcode and are retired: 0x03 (FILEGET) and
/// 0x04 (FILEPUT), retired 2026-10-06. NEVER REUSE ONE. A value here has no
/// variant in any binary's `Op`, so it is answered with ERR at decode; giving
/// it a new meaning would let a client written against the old one drive the
/// new handler. `retired_values_are_never_reused` below enforces it.
pub const RETIRED: &[u8] = &[0x03, 0x04];

/// Power the guest off from inside. Both agents handle it (ADR-024): vm-agent
/// asks katmate-init, PID 1, to call `reboot(2)` (microvm has no ACPI);
/// netvm-agent signals systemd, PID 1, with SIGRTMIN+4.
pub const OP_SHUTDOWN: u8 = 0x05;

/// Install / withdraw the per-appVM internal `/32` route in netVM. netVM only,
/// and the sole reason netvm-agent holds CAP_NET_ADMIN.
///
/// New in the workspace split: 0x06 is the first free value after the five
/// opcodes the C-era agent defined.
pub const OP_NETCFG: u8 = 0x06;

/// Human-readable name for an opcode value — for logs and `ping-client`
/// diagnostics ONLY. Naming an opcode is not permission to run it: a binary
/// that has no handler for a value still rejects it at decode.
pub fn name(op: u8) -> &'static str {
    match op {
        OP_PING => "PING",
        OP_RUN => "RUN",
        OP_SHUTDOWN => "SHUTDOWN",
        OP_NETCFG => "NETCFG",
        v if RETIRED.contains(&v) => "RETIRED",
        _ => "UNKNOWN",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The wire values are a compatibility surface: a renumbering would let an
    /// old host client silently drive the wrong handler on a new agent. Pin
    /// them explicitly so such a change cannot pass CI unnoticed.
    #[test]
    fn wire_values_are_pinned() {
        assert_eq!(OP_PING, 0x01);
        assert_eq!(OP_RUN, 0x02);
        assert_eq!(RETIRED, &[0x03, 0x04]);
        assert_eq!(OP_SHUTDOWN, 0x05);
        assert_eq!(OP_NETCFG, 0x06);
    }

    /// The set of live opcodes, for the two tests below.
    const LIVE: [u8; 4] = [OP_PING, OP_RUN, OP_SHUTDOWN, OP_NETCFG];

    /// A retired value must never come back as a live opcode (0x03 and 0x04,
    /// retired 2026-10-06). A new opcode takes the next free value, 0x07.
    #[test]
    fn retired_values_are_never_reused() {
        for v in RETIRED {
            assert!(!LIVE.contains(v), "retired opcode {v:#04x} reused");
            assert_eq!(name(*v), "RETIRED");
        }
    }

    /// No two opcodes may share a value (a collision would make one of them
    /// unreachable, or — worse — silently aliased onto the other's handler).
    #[test]
    fn wire_values_are_unique() {
        let mut seen = LIVE;
        seen.sort_unstable();
        let before = seen.len();
        let mut dedup = seen.to_vec();
        dedup.dedup();
        assert_eq!(dedup.len(), before, "duplicate opcode value in registry");
    }
}
