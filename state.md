# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session.
# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session.

**Last updated:** 2026-06-13
**Milestone:** v0.2 (in development)

## Current focus

Pipeline skelet (Faza 1): foundation.sh + app-layer.sh + Makefile v repu.
Naslednji korak: QEMU launcher (instančni overlay + `-kernel` + AF_VSOCK +
waypipe host user service) — vrata faze 1.

## Open problems

1. **Suspend/resume failure under `linux-hardened`** (dev laptop, Intel iGPU):
   screen stays off, unresponsive after resume; `mem_sleep` confirmed `[deep]`/S3.
   Next: capture `journalctl -b -1 -k`, compare against stock `linux`.
2. **Installer secrets** (v0.2 blocker, zavestna začasna odločitev za dev):
   WireGuard key, WiFi PSK, credentials — ven pred odpiranjem power-userjem.

## Recently resolved

- ADR-014 (domain model + three-layer composition), ADR-010/011 accepted.
- Pipeline skelet v repo (commita c899f37, cf6c079).
- Codeberg push: main → origin/main.

## Next steps

- QEMU launcher (Faza 1 vrata)
- Kernel sub-pipeline (Debian LTS + katmate-microvm config, ADR-005)
- vm-agent build hook (`out/vm-agent`)
- `katmate-update` MVP (Faza 2)
- RTL8125 passthrough — odblokira se po katmate-update (Faza 2→3)

## Open questions

ADR-012 (image distribution), ADR-013 (image signing) — še Proposed.
vm-agent RUN whitelist → per-manifest (keepassxc za vault, Faza 4).
