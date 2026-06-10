# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session.

**Last updated:** 2026-06-10
**Milestone:** v0.2 (in development)

## Current focus

- Documentation restructure **done** (this change): content migrated into
  README / ROADMAP / CHANGELOG / docs/{ARCHITECTURE, SECURITY-MODEL, INSTALL,
  DECISIONS} / state.md. `KatmateOS_Documentation.md`,
  `KatmateOS_ProjectBook.md` and `base_structure.md` are retired.

## Open problems

1. **Suspend/resume failure under `linux-hardened`** (dev laptop, Intel iGPU):
   screen stays off, system unresponsive after resume; `mem_sleep` confirmed
   `[deep]`/S3. Suspects: kernel lockdown mode vs GPU/ACPI driver path.
   Next: capture post-suspend `journalctl -b -1 -k`, compare behavior against
   stock `linux` kernel on the same machine.
2. **Installer secrets** (v0.2 blocker): rotate the burned WireGuard key; move
   SSID/PSK/credentials to install-time prompts / `wg genkey`; drop
   `Hidden=true` from the iwd profile (SECURITY-MODEL gaps #1–#2).

## Recently resolved

- Waypipe 0.11.0 guest source build → clipboard guest↔host works (ADR-008)
- Hyprland: plugin rebuild automation, startup log suppression; Plymouth
  theme prompt/throbber fixes (CHANGELOG 0.2.0)

## Next steps

- `katmate-update` MVP (version detection + base rebuild trigger)
- Base image build pipeline → decide ADR-011
- Overlay/storage formalization → decide ADR-010
- Align installer header version with milestone versioning at next
  `install.sh` edit; same edit removes hardcoded secrets
- Desktop layer installer integration (requires `kms` in mkinitcpio HOOKS)
- Hibernation decision: add `resume` support or shrink swap (INSTALL caveats)

## Open questions

Tracked as **Proposed** ADRs in [docs/DECISIONS.md](docs/DECISIONS.md):
ADR-010 (storage mechanism), ADR-011 (build pipeline), ADR-012 (image
distribution), ADR-013 (image signing).

## Session log notes

- 2026-06-10: docs restructured to docs-as-code layout; English chosen as the
  documentation language; maintenance rules defined in README.
