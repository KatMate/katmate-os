# Architecture Decision Records

Format: context → decision → consequences. Status: **Accepted**, **Proposed**
(open question under evaluation), or **Superseded**. Open questions enter as
Proposed and are promoted on decision. Dates are approximate where
reconstructed; backfill from git history where it matters.

---

One file per ADR, under [`adr/`](adr/). The status column is the first word
of each ADR's **Status** line; the ADR file is the authority.

| ADR | Title | Status |
|---|---|---|
| [ADR-001](adr/ADR-001.md) | Compartmentalization via QEMU/KVM MicroVMs, not Xen | Accepted |
| [ADR-002](adr/ADR-002.md) | Arch Linux host, Debian stable guests | Accepted |
| [ADR-003](adr/ADR-003.md) | AF_VSOCK as the only host↔guest channel | Accepted |
| [ADR-004](adr/ADR-004.md) | Host kernel: `linux-hardened` from the Arch repo | Accepted |
| [ADR-005](adr/ADR-005.md) | Guest kernel: custom build from Debian LTS sources | Accepted |
| [ADR-006](adr/ADR-006.md) | systemd-boot instead of GRUB | Accepted |
| [ADR-007](adr/ADR-007.md) | Versioned immutable base image + per-AppVM overlays | Accepted |
| [ADR-008](adr/ADR-008.md) | Waypipe version-locked host↔guest; guest builds from source | Accepted |
| [ADR-009](adr/ADR-009.md) | NetVM as the sole network-facing domain | Accepted |
| [ADR-010](adr/ADR-010.md) | Storage: three-level LVM-thin chain for system images, raw thin LVs for home | Accepted |
| [ADR-011](adr/ADR-011.md) | Base image build pipeline: shell scripts orchestrated by Make | Accepted |
| [ADR-012](adr/ADR-012.md) | Base image distribution model | Proposed |
| [ADR-013](adr/ADR-013.md) | Base image signing & integrity verification | Proposed |
| [ADR-014](adr/ADR-014.md) | AppVM domain model & three-layer image composition | Accepted |
| [ADR-015](adr/ADR-015.md) | VM properties: machine-readable schema (TOML, per-instance) | Accepted |
| [ADR-016](adr/ADR-016.md) | Two desktop profiles: shared visual layer, Sway default + Hyprland optional | Accepted |
| [ADR-017](adr/ADR-017.md) | Dynamic CID allocation for disposable AppVMs | Accepted |
| [ADR-018](adr/ADR-018.md) | Foundation build: LVM-thin from scratch, external-vmlinuz kernel, systemd-free init | Accepted |
| [ADR-019](adr/ADR-019.md) | Waypipe as a project-maintained component: pinned upstream tag + KatMate patch queue, one tree for both host and guest binaries | Accepted |
| [ADR-020](adr/ADR-020.md) | Release is a pre-baked signed ISO; install-time carries no build-time dependencies | Accepted |
| [ADR-021](adr/ADR-021.md) | netVM is a distinct sysVM component class: separate, declarative build, its own control agent and update track | Accepted |
| [ADR-022](adr/ADR-022.md) | Network topology is a graph; the physical NIC is an assignable object | Accepted |
| [ADR-023](adr/ADR-023.md) | NETCFG describes a link, never an AppVM | Accepted |
| [ADR-024](adr/ADR-024.md) | netVM SHUTDOWN returns to the agent: ask PID 1 via SIGRTMIN+4 under CAP_KILL | Accepted |
| [ADR-025](adr/ADR-025.md) | NETCFG payload: fixed binary layout, v1-tight total validation, convergence over rollback | Accepted |
| [ADR-026](adr/ADR-026.md) | Domain indicator carriers: host-resolved waypipe CID, never guest-supplied window properties | Accepted |
| [ADR-027](adr/ADR-027.md) | VMM containment is a precondition, not an alternative | Accepted |
| [ADR-028](adr/ADR-028.md) | virtio-vsock transport placement | Accepted |
| [ADR-029](adr/ADR-029.md) | The launch daemon orders units; systemd owns the VMM process | Accepted |
| [ADR-030](adr/ADR-030.md) | What the launch daemon reads: four artefacts, authorship as the tier boundary | Accepted |
| [ADR-031](adr/ADR-031.md) | License: GPL-3.0-only, one copyright holder, relicensing kept open until contributions | Accepted |
| [ADR-032](adr/ADR-032.md) | Where each tier lives: the path is the tier, and T4 is more than the template | Accepted |
| [ADR-033](adr/ADR-033.md) | AppVM link topology: p2p over AF_UNIX datagrams, from a static slot pool | Accepted |
| [ADR-034](adr/ADR-034.md) | Kernel provenance: a sidecar captured at build, carried into T2, checked at install | Accepted |
| [ADR-035](adr/ADR-035.md) | The netVM link pool: a slot is an index, and every face of a slot is a function of that index | Proposed |
| [ADR-036](adr/ADR-036.md) | The distributable unit is the enforcing set of the trust model; the host base is a pinned composition, neither a mutable install nor a distribution | Proposed |
| [ADR-037](adr/ADR-037.md) | netVM's vanilla network stack: direct uplink egress, dnsmasq, dhcpcd, and a read-only config disk | Accepted |
| [ADR-038](adr/ADR-038.md) | AppVM guest addressing: katmate-init applies a `/32` from typed `km.*` command-line parameters | Accepted |
| [ADR-039](adr/ADR-039.md) | vm-agent: Rust rewrite and a versioned binary control protocol | Accepted |
| [ADR-040](adr/ADR-040.md) | IOMMU kernel parameters: translated host DMA domain, vendor-specific enablement, no passthrough | Accepted |
