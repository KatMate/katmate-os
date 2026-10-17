# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-17 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- cu1 closed and merged (`57f6a22`): builder VM measured on MINIS — web 109 s,
  office 91 s, vault 45 s; same 316 packages as host-built; H3 passed,
  operator-observed. [ADR-043](docs/adr/ADR-043.md) **Proposed**, gates B1–B4.
- iso1: `01026ac`, [ADR-042](docs/adr/ADR-042.md) (**Proposed**), [docs/INSTALL.md](docs/INSTALL.md).
  w2: [ADR-041](docs/adr/ADR-041.md) (Accepted; experimental, opt-in).
- MINIS runs `7.2.10-hardened1-1` (since 2026-10-14); its
  `/var/lib/katmate/instances/` is empty, so no installed AppVM starts (w2 H1 D10).

## Active open problems

Full list: [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md).
- #17 netVM VMM privilege (C1, C2, C3, C5a) · #18 global vsock CID space (C6).
- #21 every stop is a hard termination · #31 GUI ingress not in version control.
- #58 no CID uniqueness rule · #59 Windows guest's overnight reboot (`ev2.ps1`).
- #63 installer `disk` check · #64 no `panic=` in any product unit.
- #65–#68 install medium: IOMMU-group glob; builds refused from about
  2026-11-01 (keyring); ISO signing not in the release; unexecuted branches.
- #69, #70 layer builder: canonical `MANIFEST_SHA256` path not run (gate B2);
  the builder is dev scaffolding.

## Next steps

1. ADR-043 code pass: builder unit and program, manifest schema and the T1/T3
   paths, the RUN list out of vm-agent.
2. Gate B1 on the Cubi; then the Windows class ADR (`class = win`).
3. A tagged release from `main` with its medium (fresh netVM image, so a MINIS
   reboot first; before ~2026-11-01, #66), then the Cubi install gate (#68).
4. Launch daemon (step 3b); `validate-properties.fish`, `katmate-cid` to en_US.
5. Next Windows boot, before anything else: `ev2.ps1` read-only (#59); then
   remove the `vm_win_w1` leftovers.

## Leftovers and waits on the operator

- **Guest `vm_win_w1`:** rule `KatMate-RDP-baseline`, the baseline adapter's
  address config, `w2-events.txt`; `rail` admin until `kmadmin` is verified.
- **MINIS, kept by ruling:** `vm_app_gw_w2` (broken, no EGL/GLES),
  `vm_app_gw_w2b` (working), `vm_gw_w2_home`, both gateway deltas, the FreeRDP
  build chroot, tarballs and scripts under `~/katmate-dev/w2/`;
  `~/katmate-iso/dev/` (iso1: dev ISOs, test disks, logs).
- **Operator:** ISO signing (#67); the post-release backlog (UEFI entry name,
  download resume, retry count, `vconsole.conf` before pacstrap, Intel early
  KMS, LTE MTU); ROADMAP candidates; GitHub issues for alpha feedback.
