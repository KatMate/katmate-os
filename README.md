# Katmate OS

A security- and privacy-oriented desktop operating system built on compartmentalization.
Application workloads run in isolated QEMU/KVM MicroVMs; the host remains a minimal,
auditable trusted computing base.

**Status:** alpha · first public prerelease [`v0.2.0-alpha2`](https://github.com/KatMate/katmate-os/releases/tag/v0.2.0-alpha2) (milestone **v0.2**) · single developer · not ready for production use

## Why

Modern desktop operating systems place nearly all applications inside a single trust
domain. Katmate OS separates workloads — browser, office, development, disposable —
into isolated MicroVMs, so that compromise of one workload does not automatically
compromise the rest of the system.

The approach is inspired by Qubes OS, but deliberately built on a standard Linux
stack (QEMU/KVM instead of Xen) with **usability for ordinary users** as an explicit
design goal: updates and VM plumbing must work without the user administering
templates, kernels, or forwarding layers. See [ADR-001](docs/adr/ADR-001.md).

## Key properties

- **Host:** Arch Linux, `linux-hardened` kernel, LUKS2 full-disk encryption, LVM (thin pool for VM storage), systemd-boot
- **Guests:** minimal Debian stable MicroVMs with a custom-built LTS kernel, direct kernel boot
- **Communication:** AF_VSOCK only — control and GUI; no guest network exposure for the control plane. There is no host↔guest file-transfer opcode: FILEGET/FILEPUT were retired before the first release (2026-10-06)
- **GUI forwarding:** Waypipe over VSOCK into the host Wayland compositor (Sway by default, Hyprland optional — [ADR-016](docs/adr/ADR-016.md))
- **Template model:** versioned immutable base images + per-AppVM overlays; updates handled by `katmate-update`, transparent to the user

## Known limitations (alpha)

- **The clipboard is shared across all VMs and the host.** There is one compositor, and every AppVM's waypipe is one of its clients, so whatever is copied in one domain can be pasted in any other. Do not copy secrets between domains. KeePassXC clears the clipboard 10 s after a copy by default. Per-domain clipboard isolation is planned for the next release.
- **The sandbox VM has no root: software installs into the home directory only.** `app_sandbox` is for trying software KatMate does not ship, from tarballs, extracted AppImages and static binaries unpacked into its persistent home. There is no `sudo` and no package manager access in it, as in every AppVM.
- **Any VM can open windows on the desktop.** The host's GUI listener (waypipe on vsock port 1024) accepts a connection from any VM, netVM included, with no check of which VM is calling, before it parses that VM's Wayland stream (trust-boundary audit of 2026-09-18, finding 7). It is the same boundary as the shared clipboard above, and the fix ships with it in the next release.
- **netVM needs a wired PCI Ethernet card.** The installer offers PCI Ethernet controllers only; a wireless card cannot be assigned to netVM in the alpha. Two cards with the same vendor and device id cannot be told apart and are refused.
- **USB network adapters are not supported.** netVM takes its card by PCI passthrough only. A USB NIC (for example the RTL8153/r8152 used on development hosts) cannot be assigned to netVM in the alpha.
- **Window labels are guest-set, so a VM can spoof them.** An AppVM window's title starts with `[<instance>]`, for example `[app_web] …`. The guest's own waypipe adds that prefix, so a compromised VM can show any label it likes. It is a hint, not a security boundary. Labels the host assigns are planned for the next release.
- **KeePassXC starts in the light theme on a fresh install.** It reads no system-wide setting, so the guests' dark GTK theme does not reach it. Set the theme to dark once in KeePassXC's settings in the vault; the choice persists.
- **No Wi-Fi UI.** The network uplink is a physical NIC passed through to netVM. The host has no network of its own to configure, and there is no Wi-Fi settings panel.
- **No screen lock.** No screen locker ships yet, so neither the power menu nor idle can lock the screen.

## Documentation map

| Document | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture: host, guests, kernels, storage/template model, communication, GUI, networking, desktop layer |
| [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md) | Threat model, trust boundaries, controls per component, known gaps |
| [docs/HOST-CONFIG.md](docs/HOST-CONFIG.md) | Host configuration KatMate depends on that lives outside git — an input to the installer |
| [docs/INSTALL.md](docs/INSTALL.md) | Requirements, installer walkthrough, disk layout, tested hardware, caveats |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Index of the Architecture Decision Records (Accepted / Proposed); one file per ADR in [docs/adr/](docs/adr/) |
| [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md) | Open problems, by number |
| [docs/INVARIANTS.md](docs/INVARIANTS.md) | Invariants and gotchas: the traps, with their diagnoses |
| [docs/DEV-ENV.md](docs/DEV-ENV.md) | The development machines, dev network and dev access |
| [docs/PARAMETERS.md](docs/PARAMETERS.md) | Per-instance parameters the alpha integration sets by hand, and the component that will own each |
| [ROADMAP.md](ROADMAP.md) | Milestones v0.1 → v1.0 |
| [state.md](state.md) | Current state: focus, active open problems, next steps (~50 lines, rewritten every session) |
| [AI.md](AI.md) | How AI is used in this project |
| [Early days](https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2) | The tree at `v0.2.0-alpha2`, with the session record (`docs/SESSIONS.md`) and the long `state.md` |

Maintenance rules: every fact lives in exactly one document (others link to it);
every decision with alternatives becomes an ADR, one file in `docs/adr/`, listed
in `docs/DECISIONS.md`; `state.md` never holds permanent truths, stays under ~50
lines and is rewritten, not appended, at the end of every session; open problems
live in `docs/OPEN-PROBLEMS.md` under numbers that are never reused; session
notes, briefs and reports are kept outside the repository; anything the host
must be configured to do, but git does not carry, belongs in
`docs/HOST-CONFIG.md` with its failure mode stated.

## Development philosophy

Prefer simple code, explicit behavior, open standards, Linux-native solutions.
Avoid unnecessary abstraction, large management stacks, hidden magic, excessive
dependencies.

**Privacy. Security. Isolation. Simplicity.**

## License

Katmate OS is licensed under the GNU General Public License, version 3 only
(GPL-3.0-only). The full text is in [LICENSE](LICENSE); the decision is
[ADR-031](docs/adr/ADR-031.md). Third-party work the project derives
from is credited in [CREDITS.md](CREDITS.md).

## Contributing

Contributions and pull requests are not accepted yet. The project will open
to others as it grows.
