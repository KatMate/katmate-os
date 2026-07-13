//! netvm-agent — privileged VSOCK control agent for the netVM sysVM (ADR-021).
//!
//! Runs under systemd (`netvm-agent.service`, already scaffolded in
//! `build/netvm.sh` step 7) with CAP_NET_ADMIN and nothing else:
//! NoNewPrivileges=yes, ProtectSystem=strict, ReadWritePaths=/etc/systemd/
//! network + /run. Listens on the shared control port, accepts the host CID
//! only, and shares the codec with `vm-agent` (katmate-protocol) — but NOT the
//! opcode set (see op.rs: PING + NETCFG, nothing else).
//!
//! CODE SESSION — reuse, do not reinvent. The listener, the bind/listen/accept
//! loop, the `peer.svm_cid != VMADDR_CID_HOST` rejection, and the
//! per-connection request loop are structurally identical to vm-agent's; copy
//! that shape. The differences are all subtractive:
//!
//!   * dispatch table is two arms wide (Ping, Netcfg)
//!   * NO spawn() / posix_spawn — this binary never creates a process, so it
//!     also never needs SIGCHLD=SIG_IGN
//!   * NO init socket, NO file handling, NO path confinement (no file surface)
//!   * NO config.rs — no waypipe target to resolve
//!
//! NETCFG semantics (pin these in the code session, per ADR-021):
//!   decode a TYPED payload (not a shell string) -> validate it is a
//!   well-formed internal /32 for a legitimate appVM CID -> write a networkd
//!   fragment under /etc/systemd/network/ -> `networkctl reload`. Reject
//!   anything else. The host is trusted, but a typed+validated surface is the
//!   entire reason this is an agent and not an ssh shell: the privileged
//!   operation has a fixed shape that cannot be widened from the wire.
//!
//! FIRST LIVE GATE (after `netvm.sh` bakes the binary): `ping-client ping 3`
//! -> OK. That is the first control path into netVM since the image locked
//! root, and it unblocks in-guest verification of WireGuard + inner segment.

mod op;

fn main() {
    todo!("VSOCK listener (mirror vm-agent's shape), dispatch on op::Op (PING + NETCFG)")
}
