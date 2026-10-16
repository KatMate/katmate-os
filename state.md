# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-16 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- Install medium (iso1, 2026-10-16): in code at `01026ac`, recorded as
  [ADR-042](docs/adr/ADR-042.md) (**Proposed**); measured in QEMU on MINIS.
  Install path: [docs/INSTALL.md](docs/INSTALL.md).
- w2 spike closed 2026-10-15: [ADR-041](docs/adr/ADR-041.md) (Accepted;
  feature experimental, opt-in).
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
- #65–#68 — install medium: IOMMU-group glob; builds refused from about
  2026-11-01 (keyring); ISO signing not in the release; unexecuted branches.

## Next steps

1. A tagged release built from `main`, with its install medium. It needs a
   fresh netVM image (`tools/make-release.sh` refuses a booted one), so a
   MINIS reboot first (`CLAUDE.md`, reboot procedure). Before about
   2026-11-01, or after a keyring that extends the two keys of #66.
2. The Cubi gate: end-to-end install from that release's medium; closes #68
   and promotes ADR-042.
3. Launch daemon, build order step 3b (`ROADMAP.md`).
4. Code: translate `tools/validate-properties.fish` and `bin/katmate-cid` to
   en_US (the stale location strings were fixed in `9a0cf68`).
5. Next Windows boot, before anything else: run `ev2.ps1` read-only (#59);
   then remove the guest leftovers below.

## Leftovers

- **Guest `vm_win_w1`:** firewall rule `KatMate-RDP-baseline` and the
  baseline adapter's address config; `C:\Users\RAIL\Documents\w2-events.txt`;
  `rail` still in Administrators until `kmadmin` is verified at the console.
- **MINIS, kept by ruling:** `vm_app_gw_w2` (broken, no EGL/GLES),
  `vm_app_gw_w2b` (working), `vm_gw_w2_home`, both gateway deltas, the
  FreeRDP build chroot, tarballs and scripts under `~/katmate-dev/w2/`.
- **MINIS, iso1:** `~/katmate-iso/dev/` (dev ISOs, test disks, logs).

## Waits on the operator

- ISO signing in the release process (#67).
- Ruling on the post-release backlog (UEFI entry name, download resume,
  retry count, `vconsole.conf` before pacstrap, Intel early KMS, LTE MTU).
- ROADMAP candidates from the old *Next steps*; GitHub issues for alpha
  feedback.
