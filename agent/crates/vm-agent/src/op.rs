//! op.rs — the appVM agent's opcode set. THIS FILE IS THE SECURITY BOUNDARY.
//!
//! `vm-agent` runs as uid 1000 inside an appVM. It handles the guest-facing
//! opcodes and, notably, does NOT handle NETCFG: an unprivileged app-domain
//! agent has no business touching netVM's routing table, and here that is not a
//! policy check but a parse failure — NETCFG's byte does not map to a variant
//! of this enum, so the request dies in `try_from` before reaching any handler.
//! Adding NETCFG to this file would be the ONLY way to grant it, which is
//! exactly the property ADR-021 wants: absent, not disabled.

use katmate_protocol::error::AgentError;
use katmate_protocol::opcode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op {
    Ping,
    Run,
    FileGet,
    FilePut,
    /// appVMs are microvm: no ACPI, so the host has no power-button to press.
    /// The agent (uid 1000, cannot call reboot(2)) asks katmate-init — PID 1,
    /// the single root process in the guest — over its unix socket. netVM does
    /// NOT have this opcode; it is q35, so the host uses QMP instead.
    Shutdown,
}

impl TryFrom<u8> for Op {
    type Error = AgentError;

    fn try_from(raw: u8) -> Result<Op, AgentError> {
        match raw {
            opcode::OP_PING => Ok(Op::Ping),
            opcode::OP_RUN => Ok(Op::Run),
            opcode::OP_FILEGET => Ok(Op::FileGet),
            opcode::OP_FILEPUT => Ok(Op::FilePut),
            opcode::OP_SHUTDOWN => Ok(Op::Shutdown),
            // OP_NETCFG lands here: known to the wire, absent from this binary.
            other => Err(AgentError::UnknownCommand(other)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn netcfg_is_absent_from_the_appvm_agent() {
        assert!(Op::try_from(opcode::OP_NETCFG).is_err());
    }

    #[test]
    fn handled_opcodes_map() {
        assert_eq!(Op::try_from(opcode::OP_PING).unwrap(), Op::Ping);
        assert_eq!(Op::try_from(opcode::OP_SHUTDOWN).unwrap(), Op::Shutdown);
    }
}
