# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-23 · **Milestone:** v0.2 — `v0.2.0-alpha2` published, `v0.2.0-beta` in preparation

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- rel1 done (2026-10-23, `3c32a76`, `3b4a80d`): `make-release.sh` takes
  `--archive` and `--iso` and binds the medium in a step 0 (name, `iso.env`
  tag, 60 days, embedded archive, `.sha256`); refusals G1–G7 observed on MINIS,
  steps 5–6 not yet run (#67). #65 closed: install.sh refuses a netVM card
  without an IOMMU group (fake sysfs, not hardware). Release run documented in
  [docs/DEV-ENV.md](docs/DEV-ENV.md), *Release run*.
- hs1 done (2026-10-22): `katmate-vm create --home-size <n>G` (default 10G).
  cu5f, cu5, cu4, cu3 done (2026-10-18–22): `katmate-alloc`, `katmate-vm`
  `create`/`status`/`delete`/`provision`/`menu`, launcher entries as state.
- ADR-043 stays **Proposed**, gates B1–B4. iso1: [ADR-042](docs/adr/ADR-042.md)
  (**Proposed**). w2: [ADR-041](docs/adr/ADR-041.md). fz1 done.
- MINIS: `7.2.10-hardened1-3` since 2026-10-18; instance deltas `root:root`
  since 2026-10-20. Four TPM units fail at boot, cause unread.

## Active open problems

Full list: [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md).
- #17 netVM VMM privilege (C1, C2, C3, C5a) · #18 global vsock CID space (C6).
- #21 every stop is a hard termination · #31 GUI ingress not in version control.
- #59 Windows guest's overnight reboot (`ev2.ps1`).
- #63 installer `disk` check · #64 no `panic=` in any product unit.
- #66 the keyring: a release run must finish its MINIS half by
  **2026-10-31 UTC** · #67 `make-release.sh` steps 5–6 unrun · #68 the
  medium's unexecuted branches.
- #69, #70 layer builder: canonical `MANIFEST_SHA256` path not run (gate B2);
  the builder is dev scaffolding and writes no guest whitelist yet.

## Next steps

1. The `v0.2.0-beta` release run (DEV-ENV, *Release run*), MINIS half by
   2026-10-31 UTC; then the Cubi install gate from its medium (#68), the first
   real `katmate-vm provision` and installer-written menu, fz1 (a real launch,
   a stop with Yes, Lock) and gate B1 in the same session; publish after PASS.
2. cu6: the builder as T3 and `create --from <T1 manifest>` (#70, gate B3).
3. The Windows class ADR (`class = win`), after B1.
4. Launch daemon (step 3b); `validate-properties.fish`, `katmate-cid` to en_US.
5. Next Windows boot: `ev2.ps1` read-only (#59); then the `vm_win_w1` leftovers.

## Leftovers and waits on the operator

- **Guest `vm_win_w1`:** rule `KatMate-RDP-baseline`, the baseline adapter's
  address config, `w2-events.txt`; `rail` admin until `kmadmin` is verified.
- **MINIS, kept by ruling:** w2's gateway LVs, home, deltas, FreeRDP chroot
  and `~/katmate-dev/w2/`; `~/katmate-iso/dev/`; fz1's leftovers
  (`~/.local/bin/menu-power`, `~/.config/waybar/config.disabled`,
  `~/katmate-dev/fz1/`); `~/katmate-dev/hs1-prev/`; rel1's scratch
  `~/katmate-dev/rel1/`.
- **Operator:** the release run and publish; the post-release backlog (#63,
  #64, per-VM vCPU and memory limits); ROADMAP candidates; GitHub issues for
  alpha feedback.
