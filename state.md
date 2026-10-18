# State

Early days (everything up to the first public release, session records
included): <https://github.com/KatMate/katmate-os/tree/v0.2.0-alpha2>

**Last updated:** 2026-10-18 · **Milestone:** v0.2 — `v0.2.0-alpha2` published

This file is rewritten, not appended, at the end of every session, and stays
under ~50 lines. Permanent material lives in [docs/INVARIANTS.md](docs/INVARIANTS.md),
[docs/DEV-ENV.md](docs/DEV-ENV.md), [docs/OPEN-PROBLEMS.md](docs/OPEN-PROBLEMS.md)
and [docs/DECISIONS.md](docs/DECISIONS.md).

## Current focus

- fz1: fuzzel replaces the waybar GTK menus. Launcher on `$mod+space` (no bar
  button; generated entries from `katmate-launch`'s `APPS`, plus *KatMate:
  AppVMs* for state and stop); power menu on the mark (Lock, Logout, Reboot,
  Shutdown; no Suspend). Deployed on MINIS, menus operator-observed. Its
  first unit is on `main` as `5104568` under cu1's copied message (operator,
  by accident); the rest is on branch `fz1`.
- cu1: [ADR-043](docs/adr/ADR-043.md) **Proposed**, gates B1–B4.
  iso1: [ADR-042](docs/adr/ADR-042.md) (**Proposed**). w2: [ADR-041](docs/adr/ADR-041.md).
- MINIS: `pacman -Syu` on 2026-10-18 (fourth attempt; the mirror stalled
  three times), rebooted into `7.2.10-hardened1-3` the same day; `libnotify`
  installed, km-launch's failure notification observed. netVM `enabled`
  and `active` (it was found `disabled` after the reboot). Four TPM units
  (`systemd-pcrlogin@*`, `-pcrproduct`, `-tpm2-setup-early`) fail at boot,
  cause unread. `/var/lib/katmate/instances/` is empty, so no installed
  AppVM starts (w2 H1 D10).

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

1. fz1 on the Cubi install: a real launch, a stop with Yes, Lock (swaylock);
   the installer's desktop block.
2. ADR-043 code pass: builder unit and program, manifest schema, T1/T3 paths.
3. Gate B1 on the Cubi; then the Windows class ADR (`class = win`).
4. A tagged release from `main` with its medium (before ~2026-11-01, #66),
   then the Cubi install gate (#68).
5. Launch daemon (step 3b); `validate-properties.fish`, `katmate-cid` to en_US.
6. Next Windows boot: `ev2.ps1` read-only (#59); then the `vm_win_w1` leftovers.

## Leftovers and waits on the operator

- **Guest `vm_win_w1`:** rule `KatMate-RDP-baseline`, the baseline adapter's
  address config, `w2-events.txt`; `rail` admin until `kmadmin` is verified.
- **MINIS, kept by ruling:** `vm_app_gw_w2` (broken, no EGL/GLES),
  `vm_app_gw_w2b` (working), `vm_gw_w2_home`,
  both gateway deltas, the FreeRDP chroot and `~/katmate-dev/w2/`;
  `~/katmate-iso/dev/`; `~/.local/bin/menu-power` and
  `~/.config/waybar/config.disabled` (fz1). fz1 scripts in `~/katmate-dev/fz1/`.
- **Operator:** ISO signing (#67); the post-release backlog; ROADMAP
  candidates; GitHub issues for alpha feedback; squash of `fz1` onto `main`.
