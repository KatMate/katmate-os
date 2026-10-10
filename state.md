# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-10 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- `v0.2.0-alpha2` (tag on `03bffaf`) is published as a GitHub prerelease,
  2026-10-09T21:27:39Z.
- The repository is public since 2026-10-10 00:35 CEST, the project's
  inception date.
- Cubi reproducibility gate: PASS — alpha2 installed on the MSI Cubi on
  2026-10-09 (the operator).
- Documentation reset in progress: one file per ADR, a short `state.md`,
  session records out of the repository.

## Active open problems

Full list, with text: [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md).

- #3 — Installer secrets, recorded as a v0.2 blocker; status after alpha2 unruled.
- #17 — netVM VMM privilege, C-gate remainder (C1, C2, C3, C5a).
- #18 — vsock CID space is global on the host (C6).
- #21 — Every stop is a hard termination; the clean path is not wired.
- #31 — The GUI ingress cannot be located in version control.
- #58 — The validator has no CID uniqueness rule.

## Next steps

1. Launch daemon, build order step 3b (`ROADMAP.md`); its output
   specification is `docs/PARAMETERS.md` with `katmate-launch`'s tables.
2. Finish the documentation reset: the operator's squash-merge, then the
   rulings it raised.
3. Rule on the post-release backlog (UEFI entry name, download resume,
   retry count, `vconsole.conf` before pacstrap, Intel early KMS, LTE MTU).
4. Translate `tools/validate-properties.fish` and `bin/katmate-cid` to
   en_US, with the `LC_ALL=C` pin, in one commit.

## Waits on the operator

- Squash-merge of the documentation reset branch.
- Rulings: open problems #3 and #13; the post-release backlog; ROADMAP
  candidates from the old *Next steps*; GitHub issues for alpha feedback.
