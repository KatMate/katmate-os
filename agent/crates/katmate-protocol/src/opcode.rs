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
//! Who handles what (ADR-021):
//!
//! | opcode   | vm-agent (appVM, uid 1000) | netvm-agent (CAP_NET_ADMIN) |
//! |----------|----------------------------|-----------------------------|
//! | PING     | handler                    | handler                     |
//! | RUN      | handler (whitelist)        | absent                      |
//! | FILEGET  | handler (HOME_PREFIX)      | absent                      |
//! | FILEPUT  | handler (HOME_PREFIX)      | absent                      |
//! | SHUTDOWN | handler (-> katmate-init)  | absent — host QMP/ACPI      |
//! | NETCFG   | absent                     | handler (privileged)        |
//!
//! SHUTDOWN is absent from netvm-agent by design: netVM is q35, hence has ACPI,
//! so the host powers it down with QMP `system_powerdown` (-> logind) and the
//! agent needs no shutdown privilege at all. appVMs are microvm — no ACPI — so
//! they must carry an in-guest SHUTDOWN. The asymmetry follows from the machine
//! type, not from inconsistency.

/// Liveness check. The only opcode BOTH agents handle.
pub const OP_PING: u8 = 0x01;

/// Launch a whitelisted app under waypipe. appVM only.
pub const OP_RUN: u8 = 0x02;

/// Read a file from the guest's confined home subtree. appVM only.
pub const OP_FILEGET: u8 = 0x03;

/// Write a file into the guest's confined home subtree. appVM only.
pub const OP_FILEPUT: u8 = 0x04;

/// Power the guest off from inside. appVM only (microvm has no ACPI; the agent
/// asks katmate-init, PID 1, to call `reboot(2)`). netVM does NOT handle this —
/// the host uses QMP `system_powerdown` instead.
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
        OP_FILEGET => "FILEGET",
        OP_FILEPUT => "FILEPUT",
        OP_SHUTDOWN => "SHUTDOWN",
        OP_NETCFG => "NETCFG",
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
        assert_eq!(OP_FILEGET, 0x03);
        assert_eq!(OP_FILEPUT, 0x04);
        assert_eq!(OP_SHUTDOWN, 0x05);
        assert_eq!(OP_NETCFG, 0x06);
    }

    /// No two opcodes may share a value (a collision would make one of them
    /// unreachable, or — worse — silently aliased onto the other's handler).
    #[test]
    fn wire_values_are_unique() {
        let all = [
            OP_PING,
            OP_RUN,
            OP_FILEGET,
            OP_FILEPUT,
            OP_SHUTDOWN,
            OP_NETCFG,
        ];
        let mut seen = all;
        seen.sort_unstable();
        let before = seen.len();
        let mut dedup = seen.to_vec();
        dedup.dedup();
        assert_eq!(dedup.len(), before, "duplicate opcode value in registry");
    }
}
