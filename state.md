# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-30 · **Milestone:** v0.2 — `v0.2.0-beta` published (prerelease)

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- `v0.2.0-beta` published 2026-10-30: tag at `690c48d`, 24 assets whose
  digests match the signed `SHA256SUMS`. `v0.2.0-alpha2`'s release is
  deleted, its tag kept. The run: rel2 on MINIS (2026-10-23/24; ISO, images,
  netVM release build, two reboots), rel3 the media (2026-10-26), and the
  Cubi gate **PASS** (2026-10-30, operator): an install from the medium with
  a `KMRELEASE` disk, the first real `katmate-vm provision` and
  installer-written menu, all five AppVMs launched. #67 closed, #68 narrowed.
  The procedure is [docs/DEV-ENV.md](docs/DEV-ENV.md), *Release run*.
- Done before it: cu3–cu5f and hs1 (`katmate-alloc`, `katmate-vm`
  `create`/`status`/`delete`/`provision`/`menu`, `--home-size`), fz1, iso1.
- ADR-043 **Proposed** (gates B1–B4); [ADR-042](docs/adr/ADR-042.md)
  **Proposed**, its status the operator's; [ADR-041](docs/adr/ADR-041.md)
  (w2) Accepted.
- MINIS: `7.2.10-hardened1-3`, booted 2026-10-24; netVM is the beta's release
  build, booted since. Four TPM units fail at boot, cause unread.

## Active open problems

Full list: [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md).
- #17 netVM VMM privilege (C1, C2, C3, C5a) · #18 global vsock CID space (C6).
- #21 every stop is a hard termination (Firefox reports an improper exit)
  · #31 GUI ingress not in version control.
- #59 Windows guest's overnight reboot (`ev2.ps1`).
- #63 installer `disk` check · #64 no `panic=` in any product unit.
- #66 the next release run needs a newer `archlinux-keyring` · #68 the
  medium's remaining branches (URL download, no-network install, Wi-Fi,
  refusals).
- #69, #70 layer builder: `MANIFEST_SHA256` path not run (B2), dev scaffolding.
- #71 no supported way to renew instance deltas after a layer rebuild.

## Next steps

1. The Windows class ADR (`class = win`): the next major step (operator,
   2026-10-30), on ADR-041's gateway path.
2. cu6: the builder as T3 and `create --from <T1 manifest>` (#70, gate B3);
   gates B1 and B2.
3. Post-release backlog: #63, #64, #71, per-VM vCPU and memory limits, a
   named UEFI boot entry (`KatMate OS`, not `UEFI OS`), `make-release.sh`'s
   message for an LV held by `jbd2`.
4. Launch daemon (step 3b); `validate-properties.fish`, `katmate-cid` to en_US.
5. Next Windows boot: `ev2.ps1` read-only (#59); then the `vm_win_w1` leftovers.

## Leftovers and waits on the operator

- **Guest `vm_win_w1`:** rule `KatMate-RDP-baseline`, the baseline adapter's
  address config, `w2-events.txt`; `rail` admin until `kmadmin` is verified.
- **MINIS, kept by ruling:** w2's gateway LVs, home, deltas, FreeRDP chroot
  and `~/katmate-dev/w2/`; `~/katmate-iso/dev/`.
- **MINIS, removable now:** `~/katmate-dev/{hs1-prev,rel1,rel2,rel3,fz1}/`,
  fz1's `~/.local/bin/menu-power` and `~/.config/waybar/config.disabled`,
  `/home/host/release-v0.2.0-beta/` (the set is on GitHub; `iso/work/` 1.2 GB).
- **Operator:** ROADMAP candidates; GitHub issues for beta feedback.
