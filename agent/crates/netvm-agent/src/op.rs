//! op.rs — the netVM agent's opcode set. THIS FILE IS THE SECURITY BOUNDARY.
//!
//! `netvm-agent` is the ONLY privileged agent in the system (CAP_NET_ADMIN, via
//! its systemd unit). A capability set has to buy exactly one thing, and this
//! enum is where that is enforced — by omission:
//!
//!   * NO Run             — the privileged agent cannot launch a process. Not
//!                          "refuses to": has no variant, so RUN dies in
//!                          try_from. There is no spawn() in this binary at all.
//!   * NO FileGet/FilePut — no file surface in the network domain.
//!   * NO Shutdown        — netVM is q35, hence has ACPI. The host powers it
//!                          down with QMP `system_powerdown` -> logind -> clean
//!                          stop of networkd / wg-quick / nftables, which is
//!                          what releases the RTL8125 for the FLReset- restart
//!                          cycle. Consequently: no shutdown handler, no
//!                          CAP_SYS_BOOT, and no dbus/polkit dragged into the
//!                          most network-exposed VM in the system.
//!
//! That leaves PING (liveness) and NETCFG (the internal /32 route lifecycle) —
//! and NETCFG alone is the justification for holding CAP_NET_ADMIN.

use katmate_protocol::error::AgentError;
use katmate_protocol::opcode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op {
    Ping,
    /// Install / withdraw an appVM's internal /32 route. The launch daemon
    /// calls this at VM launch and at teardown. The sole privileged operation
    /// in the entire binary.
    Netcfg,
}

impl TryFrom<u8> for Op {
    type Error = AgentError;

    fn try_from(raw: u8) -> Result<Op, AgentError> {
        match raw {
            opcode::OP_PING => Ok(Op::Ping),
            opcode::OP_NETCFG => Ok(Op::Netcfg),
            // RUN / FILEGET / FILEPUT / SHUTDOWN all land here: they exist on
            // the wire, but not in this binary.
            other => Err(AgentError::UnknownCommand(other)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The whole point of the workspace split, as an executable assertion: a
    /// CAP_NET_ADMIN binary that cannot be made to run a process, touch a file,
    /// or power the VM off — because those opcodes do not decode here at all.
    /// If someone later adds a variant, this test fails and asks them why.
    #[test]
    fn forbidden_opcodes_fail_at_decode() {
        for raw in [
            opcode::OP_RUN,
            opcode::OP_FILEGET,
            opcode::OP_FILEPUT,
            opcode::OP_SHUTDOWN,
        ] {
            assert!(
                Op::try_from(raw).is_err(),
                "{} must not decode in netvm-agent",
                opcode::name(raw)
            );
        }
    }

    #[test]
    fn handled_opcodes_map() {
        assert_eq!(Op::try_from(opcode::OP_PING).unwrap(), Op::Ping);
        assert_eq!(Op::try_from(opcode::OP_NETCFG).unwrap(), Op::Netcfg);
    }
}
