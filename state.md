# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-18 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- cu3 done (2026-10-18, `1c10921`), step 2 of user-created AppVMs: the
  `katmate-alloc` crate. A routed AppVM claims the lowest free or stale slot
  of its netVM's pool per run (never 05/06; one `flock`); LINK_ID is an
  opaque tmpfs counter from 1000 (ADR-035 §6); no T1 key carries a slot.
  `katmate-launch` has no instance tables: T1 admits, `--faces` gives the
  link's faces, CID uniqueness over T1 at every launch (`--cid-check`; #58
  closed). Desktop entries come from T1 `class = app`. Gates A1–A4 passed on
  MINIS (slots 00/01, CID 32, LINK_IDs 1000–1002).
- cu2 done: [ADR-043](docs/adr/ADR-043.md) §5–7, step 1 (layer manifests as
  TOML, `run` per layer, stale or writable layers refused).
- ADR-043 stays **Proposed**, gates B1–B4. iso1: [ADR-042](docs/adr/ADR-042.md)
  (**Proposed**). w2: [ADR-041](docs/adr/ADR-041.md). fz1 done.
- MINIS: booted 2026-10-18 16:51 into `7.2.10-hardened1-3`. Foundation
  `BUILD_DATE=2026-10-18T17:27:21Z`; five fresh instance deltas; all AppVMs
  stopped, netVM active. Four TPM units fail at boot, cause unread.
- MINIS: `katmate-sys-driver@.service` and `katmate-app-offline@.service`
  drift from the tree by one comment line (`49a172d` vs `a92b3ef`); they get
  reinstalled at the next netVM restart.

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

1. Step 3 of user-created AppVMs, cu4: the `katmate-vm-create`/`delete`/
   `status` CLI in Rust, linking `katmate_alloc` (T1 manifest ownership lands
   there). Its gates include what cu3 did not verify live: the stale-owner
   path, the kept path, `--stop-all`, netVM's records for the LINK_IDs,
   traffic from slot 00, the release and installer lines. Then step 4, T1
   menu entries; the builder unit and program.
2. fz1 on the Cubi install: a real launch, a stop with Yes, Lock (swaylock).
3. Gate B1 on the Cubi; then the Windows class ADR (`class = win`).
4. A tagged release from `main` with its medium (before ~2026-11-01, #66),
   then the Cubi install gate (#68).
5. Launch daemon (step 3b); `validate-properties.fish`, `katmate-cid` to en_US.
6. Next Windows boot: `ev2.ps1` read-only (#59); then the `vm_win_w1` leftovers.

## Leftovers and waits on the operator

- **Guest `vm_win_w1`:** rule `KatMate-RDP-baseline`, the baseline adapter's
  address config, `w2-events.txt`; `rail` admin until `kmadmin` is verified.
- **MINIS, kept by ruling:** `vm_app_gw_w2` (broken, no EGL/GLES),
  `vm_app_gw_w2b` (working; both origin-less since cu2 removed the old
  foundation), `vm_gw_w2_home`, both gateway deltas, the FreeRDP chroot and
  `~/katmate-dev/w2/`; `~/katmate-iso/dev/`; `~/.local/bin/menu-power` and
  `~/.config/waybar/config.disabled` (fz1). fz1 scripts in `~/katmate-dev/fz1/`.
- **Operator:** ISO signing (#67); the post-release backlog;
  ROADMAP candidates; GitHub issues for alpha feedback.
