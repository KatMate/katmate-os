# Katmate OS

*Codename: Cyberdome*

A security- and privacy-oriented desktop operating system built on compartmentalization.
Application workloads run in isolated QEMU/KVM MicroVMs; the host remains a minimal,
auditable trusted computing base.

**Status:** pre-alpha · milestone **v0.2** in development · single developer · not ready for production use

## Why

Modern desktop operating systems place nearly all applications inside a single trust
domain. Katmate OS separates workloads — browser, office, development, disposable —
into isolated MicroVMs, so that compromise of one workload does not automatically
compromise the rest of the system.

The approach is inspired by Qubes OS, but deliberately built on a standard Linux
stack (QEMU/KVM instead of Xen) with **usability for ordinary users** as an explicit
design goal: updates and VM plumbing must work without the user administering
templates, kernels, or forwarding layers. See [ADR-001](docs/DECISIONS.md#adr-001).

## Key properties

- **Host:** Arch Linux, `linux-hardened` kernel, LUKS2 full-disk encryption, LVM (thin pool for VM storage), systemd-boot
- **Guests:** minimal Debian stable MicroVMs with a custom-built LTS kernel, direct kernel boot
- **Communication:** AF_VSOCK only — control, file transfer, GUI; no guest network exposure for the control plane
- **GUI forwarding:** Waypipe over VSOCK into the host Wayland compositor (Hyprland)
- **Template model:** versioned immutable base images + per-AppVM overlays; updates handled by `katmate-update`, transparent to the user

## Documentation map

| Document | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture: host, guests, kernels, storage/template model, communication, GUI, networking, desktop layer |
| [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md) | Threat model, trust boundaries, controls per component, known gaps |
| [docs/INSTALL.md](docs/INSTALL.md) | Requirements, installer walkthrough, disk layout, tested hardware, caveats |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Architecture Decision Records (Accepted / Proposed) |
| [ROADMAP.md](ROADMAP.md) | Milestones v0.1 → v1.0 |
| [CHANGELOG.md](CHANGELOG.md) | Per-milestone change history |
| [state.md](state.md) | Volatile working state: open problems, next steps (regenerated per session) |

Maintenance rules: every fact lives in exactly one document (others link to it);
every behavior change produces a CHANGELOG entry; every decision with alternatives
becomes an ADR; `state.md` never holds permanent truths.

## Development philosophy

Prefer simple code, explicit behavior, open standards, Linux-native solutions.
Avoid unnecessary abstraction, large management stacks, hidden magic, excessive
dependencies.

**Privacy. Security. Isolation. Simplicity.**
