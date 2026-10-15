# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-15 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- w2 spike (RDP gateway microVM, Word as a RemoteApp window) closed
  2026-10-15; recorded as [ADR-041](docs/adr/ADR-041.md) (Accepted; feature
  experimental, opt-in) and [docs/RAIL-TESTS.md](docs/RAIL-TESTS.md).
- MINIS runs `7.2.10-hardened1-1` since the reboot of 2026-10-14.
- `/var/lib/katmate/instances/` on MINIS is empty: no installed AppVM can
  start as things stand (w2 H1 D10).

## Active open problems

Full list, with text: [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md).

- #17 — netVM VMM privilege, C-gate remainder (C1, C2, C3, C5a).
- #18 — vsock CID space is global on the host (C6).
- #21 — Every stop is a hard termination; the clean path is not wired.
- #31 — The GUI ingress is not in version control.
- #58 — The validator has no CID uniqueness rule.
- #59 — Cause of the Windows guest's overnight reboot (`ev2.ps1` not run).
- #63, #64 — installer `disk` check; no `panic=` in any product unit.

## Next steps

1. Launch daemon, build order step 3b (`ROADMAP.md`).
2. Code fix: `installer/preflight.sh:307`, `build/netvm.sh:264` stale
   location strings; translate `tools/validate-properties.fish` and
   `bin/katmate-cid` to en_US (one commit).
3. Next Windows boot, before anything else: run `ev2.ps1` read-only (#59);
   then remove the guest leftovers below.

## Leftovers

- **Guest `vm_win_w1`:** firewall rule `KatMate-RDP-baseline` and the
  baseline adapter's address config; `C:\Users\RAIL\Documents\w2-events.txt`;
  `rail` still in Administrators until `kmadmin` is verified at the console.
- **MINIS, kept by ruling:** `vm_app_gw_w2` (broken, no EGL/GLES),
  `vm_app_gw_w2b` (working), `vm_gw_w2_home`, both gateway deltas, the
  FreeRDP build chroot, tarballs and scripts under `~/katmate-dev/w2/`.

## Waits on the operator

- Ruling on the post-release backlog (UEFI entry name, download resume,
  retry count, `vconsole.conf` before pacstrap, Intel early KMS, LTE MTU).
- ROADMAP candidates from the old *Next steps*; GitHub issues for alpha
  feedback.
- `CLAUDE.md` row: reboot right after a kernel upgrade on MINIS (proposed).
