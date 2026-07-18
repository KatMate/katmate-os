//! op.rs — the netVM agent's opcode set. THIS FILE IS THE SECURITY BOUNDARY.
//!
//! `netvm-agent` is the ONLY privileged agent in the system (CAP_NET_ADMIN +
//! CAP_KILL, via its systemd unit). A capability set has to buy exactly what
//! this enum admits, and nothing more — enforced here by omission:
//!
//!   * NO Run             — the privileged agent cannot launch a process. Not
//!                          "refuses to": has no variant, so RUN dies in
//!                          try_from. There is no spawn() in this binary at all.
//!   * NO FileGet/FilePut — no file surface in the network domain.
//!
//! What it DOES admit:
//!
//!   * Ping     — liveness.
//!   * Netcfg   — the internal /32 route lifecycle; the sole justification for
//!                CAP_NET_ADMIN.
//!   * Shutdown — graceful power-off, by asking PID 1 (systemd) over
//!                SIGRTMIN+4; the sole justification for CAP_KILL (ADR-024).
//!                This REVERSES the ADR-021 "no Shutdown" rule: the QMP ->
//!                ACPI -> logind path it assumed was proven inert (logind
//!                needs dbus, which the manifest deliberately omits — see
//!                ADR-024 for the full contradiction). SHUTDOWN returns to the
//!                agent, asking its own init exactly as vm-agent asks
//!                katmate-init. CAP_SYS_BOOT stays rejected (it is not graceful
//!                under systemd PID 1, and unlocks kexec); dbus/polkit/acpid
//!                stay out of the manifest.

use katmate_protocol::error::AgentError;
use katmate_protocol::opcode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op {
    Ping,
    /// Install / withdraw an appVM's internal /32 route. The launch daemon
    /// calls this at VM launch and at teardown.
    Netcfg,
    /// Graceful power-off: reply OK, then signal PID 1 (systemd) to start
    /// poweroff.target. Mirrors vm-agent's SHUTDOWN (which asks katmate-init);
    /// the transport differs by init system, the trust shape does not
    /// (ADR-024).
    Shutdown,
}

impl TryFrom<u8> for Op {
    type Error = AgentError;

    fn try_from(raw: u8) -> Result<Op, AgentError> {
        match raw {
            opcode::OP_PING => Ok(Op::Ping),
            opcode::OP_NETCFG => Ok(Op::Netcfg),
            opcode::OP_SHUTDOWN => Ok(Op::Shutdown),
            // RUN / FILEGET / FILEPUT all land here: they exist on the wire,
            // but not in this binary.
            other => Err(AgentError::UnknownCommand(other)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The security boundary as an executable assertion: a CAP_NET_ADMIN +
    /// CAP_KILL binary that STILL cannot be made to run a process or touch a
    /// file — because those opcodes do not decode here at all. SHUTDOWN is no
    /// longer in this set (ADR-024 admitted it); RUN/FILE* remain absent. If
    /// someone later adds one of these variants, this test fails and asks why.
    #[test]
    fn forbidden_opcodes_fail_at_decode() {
        for raw in [opcode::OP_RUN, opcode::OP_FILEGET, opcode::OP_FILEPUT] {
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
        assert_eq!(Op::try_from(opcode::OP_SHUTDOWN).unwrap(), Op::Shutdown);
    }
}
