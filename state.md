# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-20 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- cu4 done (2026-10-20, `d23cbe5`), step 3 of user-created AppVMs:
  `katmate-vm` `create`/`status`/`delete`/`provision` (T4, root only,
  `app_*` names; ADR-043's note of 2026-10-20) and `katmate-t1-read`. The
  installer seeds `installer/t1/*.toml.in` and provisions through
  `katmate-vm` in `arch-chroot`, not yet in a real install. C1–C6 and D.2
  observed on MINIS; not claimed: netVM's LINK_ID records, `--offline`,
  non-default `--mem`/`--vcpus`, lock contention, a wrong purge name.
- cu3 done (2026-10-18): `katmate-alloc`, per-run slots, opaque LINK_ID, CID
  uniqueness at every launch (#58 closed). cu2: ADR-043 §5–7, step 1.
- ADR-043 stays **Proposed**, gates B1–B4. iso1: [ADR-042](docs/adr/ADR-042.md)
  (**Proposed**). w2: [ADR-041](docs/adr/ADR-041.md). fz1 done.
- MINIS: `7.2.10-hardened1-3` since 2026-10-18; `/var/lib/katmate/instances`
  and its deltas `root:root` since 2026-10-20 (were `host:host`). Four TPM
  units fail at boot, cause unread.
- MINIS: two units drift from the tree by one comment line; reinstalled at
  the next netVM restart.

## Active open problems

Full list: [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md).
- #17 netVM VMM privilege (C1, C2, C3, C5a) · #18 global vsock CID space (C6).
- #21 every stop is a hard termination · #31 GUI ingress not in version control.
- #59 Windows guest's overnight reboot (`ev2.ps1`).
- #63 installer `disk` check · #64 no `panic=` in any product unit.
- #65–#68 install medium: IOMMU-group glob; builds refused from about
  2026-11-01 (keyring); ISO signing not in the release; unexecuted branches.
- #69, #70 layer builder: canonical `MANIFEST_SHA256` path not run (gate B2);
  the builder is dev scaffolding and writes no guest whitelist yet.

## Next steps

1. Step 4 of user-created AppVMs: T1 menu entries (a `katmate-vm create`
   instance appears in the launcher); then the builder as T3 and
   `create --from <T1 manifest>` (#70, gate B3).
2. fz1 on the Cubi install: a real launch, a stop with Yes, Lock (swaylock).
3. Gate B1 on the Cubi; then the Windows class ADR (`class = win`).
4. A tagged release from `main` with its medium (before ~2026-11-01, #66),
   then the Cubi install gate (#68): the first real run of `katmate-vm
   provision` in the installer.
5. Launch daemon (step 3b); `validate-properties.fish`, `katmate-cid` to en_US.
6. Next Windows boot: `ev2.ps1` read-only (#59); then the `vm_win_w1` leftovers.

## Leftovers and waits on the operator

- **Guest `vm_win_w1`:** rule `KatMate-RDP-baseline`, the baseline adapter's
  address config, `w2-events.txt`; `rail` admin until `kmadmin` is verified.
- **MINIS, kept by ruling:** w2's gateway LVs, home, deltas, FreeRDP chroot
  and `~/katmate-dev/w2/`; `~/katmate-iso/dev/`; fz1's leftovers
  (`~/.local/bin/menu-power`, `~/.config/waybar/config.disabled`,
  `~/katmate-dev/fz1/`).
- **Operator:** ISO signing (#67); the post-release backlog;
  ROADMAP candidates; GitHub issues for alpha feedback.
