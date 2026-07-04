# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Last updated:** 2026-07-03 — **ADR-019 version-lock chain COMPLETE**: the remaining three open items landed and were validated end-to-end. Patch-queue scaffold (`third_party/waypipe/patches/`, level 0), host build script `build/waypipe-host.sh` (built on MINIS → `lz4/zstd true`, `gbm/dmabuf/video false`), and the launch preflight in `app_web.con` (version lock placed BEFORE LVM activation — cheapest gate first). Negative test (forced `v0.10.0` mismatch → FATAL before activation) and positive test (match → normal boot) both pass. The whole waypipe version-lock backbone (ADR-008's "katmate-update enforces the lock") is now real.
**Milestone:** v0.2 (in development)

## Current focus

The **entire build chain is now scripted and proven from nothing**: a single
`make foundation` builds the shared base from scratch (debootstrap → base →
waypipe-from-source → bake init/agent/user → freeze), then `make app-web` /
`make app-vault` snapshot it, and an instance boots end-to-end. The old hand-built
`vm_tpl_foundation` (Apr-13 systemd image — the source of much earlier confusion)
is **replaced** by a clean systemd-free foundation. Remaining work shifts to
`katmate-update`, the disposable-VM launch model, and migrating the live AppVMs
onto the foundation chain. The release model is now fixed (ADR-020): the whole
build chain is a *developer-side* pipeline whose output is a signed ISO; the
user installs by verify → bake → boot → provision, never by building.

The full slice, re-proven on a freshly-scripted foundation (`vm_app_web`, CID 5):
`foundation (thin RO) ← vm_app_web (thin snap RO) ← qcow2 delta` → custom
microvm kernel `6.12.87` (external `-kernel`) → **katmate-init (PID 1)** →
**vm-agent (uid 1000)** → VSOCK control channel (PING `status=0x00 OK`). systemd
is baked nowhere into the boot path (the binary still ships in the image as dead
mass — a later minimal-TCB purge). GUI RUN (nautilus over waypipe) re-proven on
the three-flag `6.12.87` kernel on 2026-07-01.

The **waypipe version-lock chain (ADR-019) is now complete**: host binary built
from the pinned tree (`/opt/katmate/bin/waypipe`), `foundation.meta` records the
tag, and the `app_web.con` preflight refuses to boot on host↔foundation version
mismatch. What remains of `katmate-update` is the orchestrator itself (bump pin →
rebase → build host → make foundation → make app → recreate deltas → update meta).

Direction unchanged: IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only
frozen (ADR-015). MINIS is primary host and merge target.

## This session (2026-07-03) — ADR-019 chain closed (items #2–#4)

Implementation session; the three remaining version-lock items landed and were
validated live on MINIS. No design changes — the ADR-019/020 decisions from
2026-07-02 held as written.

- **Patch-queue scaffold (committed):** `third_party/waypipe/patches/` with
  `.gitkeep` + `README.md`. Convention fixed to `git apply` (README aligned to
  match `waypipe-host.sh` and the guest recipe — the earlier `patch -p1` note is
  gone). Empty, patch level 0.
- **`build/waypipe-host.sh` (committed, bash):** clone pinned `v0.11.0` → apply
  patch queue (`git apply`, ascending filename order) → `cargo fetch` → `meson`
  with the SAME flags as the guest (`lz4/zstd enabled`, `gbm/dmabuf/video
  disabled`) → install to `/opt/katmate/bin/waypipe`. Build-deps are CHECKED
  only (`command -v` + `pkg-config --exists`), never auto-installed (ADR-020);
  no build-dep purge (host is not an appliance). Ephemeral clone in `mktemp -d`
  with a cleanup trap; patch dir resolved relative to the script.
  - **Live build on MINIS:** the only missing host dep was `bindgen` (Arch
    package `rust-bindgen`); after install the build succeeded. Result:
    `waypipe 0.11.0`, `lz4: true, zstd: true, dmabuf: false, video: false`. Gate
    passed.
- **Launch preflight (committed, fish, in `app_web.con`):** reads `WAYPIPE_TAG`
  from `/var/lib/katmate/foundation.meta`, strips leading `v`, compares against
  `waypipe --version` (parsed with `string match -rg`). Placed FIRST — before
  the `lvchange -K -ay` activation block — because it is the cheapest gate (a
  file read, no sudo, no LVM). An initial version had it AFTER activation; the
  negative test exposed the wrong order and it was moved up.
  - **Negative test:** meta temporarily set to `WAYPIPE_TAG=v0.10.0` → preflight
    prints FATAL mismatch and exits BEFORE `activating backing chain`. Meta
    restored to `v0.11.0`.
  - **Positive test:** `waypipe version OK (0.11.0, matches foundation)` prints
    before activation, then normal boot (kernel `6.12.87-dirty` on ttyS0).
- **`ping-client` built on MINIS:** `cargo build --release` in
  `~/katmate-build/bin/ping-client/` — the `error.rs`/`protocol.rs` symlinks into
  `agent/src/` resolved correctly. Binary at
  `bin/ping-client/target/release/ping-client`; `shutdown <cid> [port]`
  subcommand present. (Closes the standing "next immediate step".)

### Notes / cosmetics observed this session

- **rsync `--delete` without excludes** still tries to remove MINIS-only
  build output (`trixie-build/`, root-owned) → `Permission denied` noise.
  Harmless (source transferred fine) but a standing wart; a fixed `--exclude`
  set (`.git/ trixie-build/ out/ agent/target/ git-cli.txt`) or a `sync.fish`
  wrapper is the clean fix. NOT yet done.
- **`zoxide` error** in `~/.config/fish/config.fish:81` on MINIS prints on every
  script invocation (`zoxide` not installed there). Non-blocking; guard the line
  (`command -q zoxide; and zoxide init fish | source`) or install it.

## This session (2026-07-02) — ADR-019/020, `foundation.meta` writer

Design/doc session, one implementation slice landed. No new live boot proof;
scope was the waypipe ownership model, the release boundary, and the first
concrete piece of the version-lock machinery.

- **ADR-019 (committed):** waypipe is now a project-maintained *patch-queue
  fork* — one pinned upstream tag (`v0.11.0`) + a KatMate patch queue
  (`third_party/waypipe/patches/`, strip & harden only), both host and guest
  binaries built from the same tree. Host binary lives at
  `/opt/katmate/bin/waypipe`, outside pacman. Drift impossible by construction.
- **`foundation.meta` writer (committed):** `foundation.sh` writes
  `/var/lib/katmate/foundation.meta` at RO-freeze — flat `KEY=value`,
  POSIX-sourceable, no parser needed by the launch preflight. Placed AFTER the
  freeze and AFTER the rollback trap is disarmed: a meta-write failure dies
  loudly (`set -e`) without destroying a valid frozen LV. `WAYPIPE_PATCH_LEVEL`
  counts `*.patch` in `WAYPIPE_PATCHES_DIR` (0 until the scaffold lands).
  `config.sh` gains `FOUNDATION_META` + `WAYPIPE_PATCHES_DIR`;
  `KERNEL_VERSION` is now the declared source for the meta field (not filename
  parse). This is the first of ADR-019's four open items.
- **Existing frozen foundation covered:** meta hand-written on MINIS
  (`WAYPIPE_TAG=v0.11.0`, `KERNEL_VERSION=6.12.87`, patch level 0) so the future
  preflight will not reject the current live foundation. Host waypipe on MINIS
  confirmed `0.11.0`.
- **ADR-020 (committed):** the build-time / install-time boundary is now
  formal. Release = a pre-baked, GPG-signed **ISO** carrying every prebuilt
  component (foundation, app-layers, external vmlinuz, both waypipe binaries);
  install = verify → bake USB → boot → provision, **never build**. No git, no
  toolchain, no fetch of project components on the user's machine — a security
  requirement (network + supply-chain surface at the worst moment), not
  convenience. This scopes ALL pipeline scripts (`foundation.sh`,
  `app-layer.sh`, `waypipe-host.sh`, kernel build) to build-time developer
  tooling whose *output* is the ISO.
- **Ordering correction for the remaining ADR-019 items:** the host build
  script (`waypipe-host.sh`) must come BEFORE the launch preflight — the
  preflight compares against `/opt/katmate/bin/waypipe`, which the host build
  script produces. Preflight was drafted (fish, in `app_web.con`) but parked
  until the host binary exists. Decisions taken for it: compare bare `x.y.z`
  (strip leading `v` both sides); version only, NOT patch level (`waypipe
  --version` does not report the patch queue); hard path `/opt/katmate/bin/
  waypipe`, no fallback to the distro binary.
- **Convention (recorded):** build/pipeline scripts are bash
  (`#!/usr/bin/env bash`); `app_web.con` stays fish (host-side launcher). Guest
  = bash everywhere. Matt uses fish interactively on MINIS + Acer only.

## Proven this session (2026-07-01) — kernel rebuild, three flags, live-validated

Added three config flags to the monolithic microvm kernel `6.12.87` and proved
all three on a live `vm_app_web` boot (CID 5) + GUI RUN. This closes the kernel
technical debt carried since the `make foundation` work.

- **Flags (all `=y`, monolithic — never `=m`):**
  - `CONFIG_HW_RANDOM_VIRTIO=y` — the guest already had `-device
    virtio-rng-device` but no driver, so `getrandom` could block at boot. Now
    paired: device + driver.
  - `CONFIG_SECURITY_LANDLOCK=y` — eliminates the Tracker landlock-ABI warning
    and gives the desired sandboxing primitive. `landlock` was already listed in
    `CONFIG_LSM=` but inert until the code was built in; `CONFIG_LSM` needed no
    edit.
  - `CONFIG_SND_ALOOP=y` — proactive, for the future audio path 3 (snd-aloop +
    thin C daemon → VSOCK 1026 → PipeWire host-side). Audio itself not built yet.
- **Live boot proof (dmesg on ttyS0):**
  - `random: crng init done` @ 10 ms — no getrandom block.
  - `LSM: initializing lsm=capability,landlock,selinux` + `landlock: Up and
    running.`
  - `ALSA device list: #0: Loopback 1` — snd-aloop registers.
  - Boot chain unchanged: `Run /sbin/init` → `[katmate-init] starting (pid 1)`
    → `vm-agent launched as uid 1000`.
- **Landlock user-space proof:** `ping-client run 5 nautilus` → `status=0x00
  (OK)`, nautilus rendered on host Hyprland, and — the key result — the Tracker
  landlock-ABI warning that used to print on ttyS0 is **gone** (absence = pass).
- **Version carries `-dirty`** (`6.12.87-dirty`): the rsync'd source tree is not
  a clean git checkout. Cosmetic; functionally correct. Clean up when the kernel
  source is set up as a proper git checkout on MINIS. Archive filename kept as
  `vmlinuz-katmate-microvm-amd64-6.12.87` (no `-dirty` in the name) but `uname
  -r` in the guest reports `-dirty`.
- **Build migrated to MINIS.** Source tree rsync'd Acer → MINIS
  (`~/src/kernel/linux-6.12.y/`); built with `make -j16` on the Ryzen after the
  Acer (N4200, passive) thermal-shut-down twice mid-build at ~34 °C ambient (LJ
  heatwave), corrupting object files. This is NOT a project migration — git +
  GPG signing + source-of-truth stay on Acer. New vmlinuz + config archived to
  `/home/host/katmate-kernels/` on MINIS.

## Proven this session (2026-06-29 evening) — `make foundation` from scratch

`build/foundation.sh` migrated from the pre-revision **qcow2/nbd** mechanism to
**LVM-thin**, matching `app-layer.sh`. The script now builds and freezes
`vg0/vm_tpl_foundation` from nothing and codifies the real procedure (no longer
diverges from live state — the old script still installed systemd + a vm-agent
systemd unit, which was the pre-06-27 plan, not reality).

- **Kernel as external vmlinuz, NOT `.deb`.** Dropped the `.deb`/dpkg/initrd
  detour (meaningless under monolithic `-kernel` boot with no `/lib/modules`).
  `config.sh`: `KERNEL_DEB` → `KERNEL_VMLINUZ`; `Makefile` copies the vmlinuz
  from `KERNEL_SRC_DIR` (hardcoded `/home/host/katmate-kernels`, MINIS is the
  only build host) into `out/`. Aligns with ARCHITECTURE.md update-flow §4
  (kernel rides as the external `-kernel`, not in-image).
- **systemd out, katmate-init in (in the RO base).** foundation.sh compiles
  `init/katmate-init.c` static and bakes it to `/sbin/init` (per the init header:
  "bake to /sbin/init; no init= cmdline needed"). This is what the Apr-13 image
  never did — its `/sbin/init` was still a systemd symlink, which is why every
  layer booted systemd until now.
- **waypipe 0.11 from source + purge build-deps** (carried over from old script,
  ADR-008). Validated live: `waypipe --version` → `lz4: true, zstd: true`.
- **user 1000 via direct passwd/group/shadow write** — `useradd`/`passwd` are
  NOT in the minbase image, so the first build silently skipped the account
  (`|| true` swallowed "command not found"). Now written directly to the account
  files (no tooling, smaller TCB; locked `!*` password; `/home/user` is the
  per-instance rw LV, not created here).
- **Mount ordering fix:** pseudo-fs (`/proc`/`/sys`/`/dev`) must mount AFTER
  debootstrap (a fresh ext4 has no such dirs yet). `lib.sh:mount_root` does both
  at once (correct for app-layer.sh, which mounts an already-bootstrapped snap);
  foundation.sh stages the mounts manually.
- **`lib.sh`** — added `lv_thin_create` (`lvcreate -T pool -V size`) beside
  `lv_snapshot_create`; reuses the same `SNAP_CREATED` rollback slot, so
  `cleanup()` is unchanged. Mid-build failure removes the half-built LV.

**Validated live:** `/sbin/init` = static ELF (not systemd symlink); waypipe
lz4+zstd true; vm-agent + waypipe at `/usr/local/bin`; `user:x:1000:1000:...` in
passwd. Boot log: `Run /sbin/init as init process` → `[katmate-init] starting
(pid 1)` → `[katmate-init] vm-agent launched as uid 1000 (pid 60)`. `ping-client
ping 5` → `status=0x00 (OK)`. **ROADMAP build-order step 2 closed.**

> NOTE: flaky `deb.debian.org` (fastly) timeouts hit `libicu76` mid-install
> twice during bring-up — retry cleared it. This is the standing argument for the
> deferred `snapshot.debian.org` pin (ADR-011) once `katmate-update` makes
> determinism matter.

## Proven this session (2026-06-29) — app-layer build pipeline on LVM-thin

Migrated `build/` pipeline + `Makefile` from the pre-revision qcow2/nbd
mechanism to the LVM-thin mechanism (ADR-010 rev 2026-06). The scripts now
codify the proven manual procedure instead of diverging from it.

- **`build/app-layer.sh`** — `qemu-img create -f qcow2 -b foundation.qcow2`
  + `nbd_connect` replaced by `lvcreate -s --name vm_app_<type>
  vg0/vm_tpl_foundation` → `lvchange -K -ay` → mount LV directly → chroot apt
  install → umount → `lvchange --permission r` freeze. Refuses to clobber an
  existing app-layer; `cleanup` trap removes a half-built snapshot on mid-build
  failure (`SNAP_CREATED`/`FREEZE_DONE` state).
- **`build/lib.sh`** — nbd helpers replaced by `lv_snapshot_create` /
  `lv_activate` (`-K -ay`) / `lv_freeze` (`-p r`) / `lv_deactivate`.
- **`build/config.sh`** — nbd/qcow2 paths dropped; `VG`/`POOL`/`FOUNDATION_LV`/
  `APP_LV_PREFIX` added. `SNAPSHOT` apt-pin retained but explicitly DEFERRED and
  unused (per ADR-011 build note).
- **`Makefile`** — `.qcow2` file targets → `.PHONY app-<type>` targets (LVs have
  no timestamp); vm-agent hook fixed from `gcc vm-agent.c` to Rust `cargo build`
  (foundation step only — app-layers need neither kernel nor agent).
- Scripts marked executable in git (`update-index --chmod=+x`) so rsync carries
  mode 755 (the `Permission denied` that bit once is fixed at source).

**Gate passed:** `make app-web` (rebuilt) and `make app-vault` (new) both
produce `Vri-a-tz-k` thin snapshots of `vm_tpl_foundation`. Two manifest axes
validated (web = network/ephemeral-capable; vault = offline/persistent). ADR-014
dual axes realized; **ROADMAP build-order step 1 closed.**

## Proven earlier (2026-06-27) — live on MINIS, CID 5

The whole app-layer hardening slice, validated against `ping-client`:

- **PING** → `status=0x00 OK` — VSOCK control channel (port 1025) live.
- **RUN nautilus** → `status=0x00 OK` — agent spawns waypipe; host-side
  `waypipe ... client-conn -c lz4` connection established (render path live;
  lz4 matches guest `lz4:true`). nautilus rendered without dbus-run-session.
- **SHUTDOWN** → `status=0x00 OK` → clean teardown observed on ttyS0:
  agent → init socket → init kills children → `/home` (vdb) unmounted →
  root (vda) re-mounted RO → `reboot(RB_AUTOBOOT)` → triple-fault →
  QEMU (`-no-reboot`) exits cleanly. No hard kill.

### Architecture decided 2026-06-27 (ADR-worthy, not yet written)

**systemd removed from the microvm guest.** The guest's only root process is a
custom statically-linked ANSI C `katmate-init` as PID 1. The earlier plan
(state.md ≤06-22) to ship vm-agent as a systemd **user** unit is abandoned —
building on systemd would be future regression work, since systemd is slated to
leave the appliance entirely.

`katmate-init` responsibilities (and nothing more): mount pseudo-fs + the
persistent `/home` rw LV (vdb, ext4); set up `XDG_RUNTIME_DIR` for uid 1000;
open an AF_UNIX SOCK_SEQPACKET control socket (`/run/katmate-init.sock`); launch
vm-agent dropped to uid 1000 (signalfd+poll supervision, zombie reaping); on
shutdown request, kill children → unmount `/home` → sync → remount root RO →
`reboot(RB_AUTOBOOT)`. Static ANSI C, baked to `/sbin/init`. No NSS lookups
(uid 1000 hardcoded; user 1000 baked into image).

**Shutdown authority lives in init, not a setuid helper.** vm-agent is uid 1000
and cannot call `reboot(2)`; it delegates. `handle_shutdown` now acks OK, then
`signal_init_shutdown()` connects `/run/katmate-init.sock` and sends `SHUTDOWN`.
init verifies the peer credential (uid 1000) before acting. **`vm-power-helper`
removed entirely** (the `POWER_HELPER` const + setuid binary are gone — one less
root binary, smaller TCB). This is the "B3" path chosen after ACPI was rejected.

**No ACPI in the microvm.** ACPI was considered for clean shutdown but rejected:
it would pull SeaBIOS instead of qboot, slower boot, larger firmware surface —
against the minimal-TCB philosophy. With no ACPI there is no clean power-off
path, so shutdown uses guest triple-fault + host `-no-reboot` (QEMU exits on the
reboot event). The next kernel is built without ACPI deliberately.

**File transfer goes through the agent, not 9p.** Each VM has its own rw LV
mounted as `/home` (persistent per-VM storage); host↔guest file exchange is the
agent's FILEGET/FILEPUT over the VSOCK control channel (Qubes-`qvm-copy` style,
not a shared folder). 9p hostshare is dev-only and deliberately **not** mounted
by init (isolated under `#ifdef DEV_HOSTSHARE` for later if ever needed).

### Files changed 2026-06-27 (committed to Codeberg)

- `init/katmate-init.c` — new. ~330 lines static ANSI C. Compiles clean
  (`-Wall -Wextra`), also under `-DUSE_DBUS_SESSION`.
- `agent/src/protocol.rs` — `POWER_HELPER` removed; added `INIT_SOCK`
  (`/run/katmate-init.sock`) + `SHUTDOWN_CMD` (`b"SHUTDOWN"`).
- `agent/src/main.rs` — `handle_shutdown` rewritten to delegate via
  `signal_init_shutdown()` (AF_UNIX SEQPACKET → init socket). `handle_run`
  untouched (bare waypipe). `.bak-pre-initsock` backups kept on MINIS.
- `ping-client/src/main.rs` — added `shutdown <cid> [port]` subcommand
  (`Cmd::Shutdown`, no args), updated usage.
- `app_web.con` — new parametrised fish launcher (details under Invariants).

## Live state (MINIS/UM870) — summary

- **Host** (Arch): Ryzen 7 8745H, AMD-Vi + vfio. `vg0`: `root` 100G, `swap`
  12G, `vm_pool` thin pool. Custom microvm kernel `6.12.87` at
  `/home/host/katmate-kernels/` (monolithic, `-kernel`, no initrd). nft input
  drop; SSH open (dev, Open problem #4). Host is on a SI IP in LJ, direct (the
  host's own apt/debootstrap traffic does NOT route through netVM/ProtonVPN).
- **foundation** (`vm_tpl_foundation`, thin RO): **rebuilt from scratch this
  session** via `make foundation` — clean, systemd-free, init/agent/waypipe/user
  baked in. The old Apr-13 hand-built systemd image is gone.
- **netVM** (CID 3, Debian trixie, q35): USB-NIC passthrough (r8152),
  WireGuard/ProtonVPN, inner-segment routing. Runs independently of app_web.
- **personalVM** (CID 4, Debian trixie, microvm): still on the **old**
  systemd-user model (pre-foundation linear root). Migration to the
  init+foundation model is pending (Next steps).
- **app_web** (CID 5): the proven appliance. Backing `vm_app_web` (thin snap
  RO) ← `/var/lib/katmate/instances/test_web.qcow2`. `/home` =
  `vm_app_web_home` (10G ext4 raw LV, created this session, `/home/user` owned
  1000:1000). init + Rust vm-agent + user 1000 baked in.
- **app_vault** (build-only): `vm_app_vault` thin snap RO of `vm_tpl_foundation`,
  built via `make app-vault` (2026-06-29; keepassxc/foot/nautilus). NOT yet
  instantiated — no qcow2 delta, no home LV, no CID, never booted. Gate for the
  app-layer pipeline (second manifest axis: offline/persistent), not a running
  appliance. keepassxc still off the vm-agent RUN whitelist (Faza 4 blocker).
- **Disk chain**: three-level LVM-thin chain proven live and now exercised
  through a full boot/render/shutdown cycle.

## Open problems

1. **Desktop migration Acer → MINIS** — CYBRland Hyprland config + Plymouth
   theme to port; greetd swap.
2. **hyprlock-after-suspend (host)** — recurring: after host suspend, tty1
   Hyprland locks and will not unlock (killing hyprlock from another tty shows
   an unhelpful screen; screen text not yet captured). Host DE issue, not
   Katmate, but it blocks visual inspection of guest render. Needs its own pass.
3. **Installer secrets** (v0.2 blocker): WireGuard key, WiFi PSK, credentials
   removed before release; rotate burned WG key. SECURITY-MODEL gap #1.
4. **SSH open on MINIS host** — dev convenience. Fix identified
   (`iif enp1s0 ip saddr 10.3.1.0/24`), not applied. SECURITY-MODEL gap #4.
5. **ext4 lazy-init warning on vda** — `EXT4-fs error (vda) ... bad block
   bitmap checksum` from `ext4lazyinit` during boot. Cosmetic on a disposable
   delta, but suggests the `vm_app_web` base may want a clean `e2fsck` (likely
   residue from a r/w bake cycle closed by hard-kill, not clean unmount).
6. Disk model + GUI chain + shutdown + **scripted foundation/app build** are
   **resolved** end-to-end. What remains is `katmate-update` + migration +
   installer, not the build mechanism.

## Next steps

- **ARCHITECTURE.md diagram set** — storage chain, VSOCK ports, CID domains,
  boot chain, trust boundary. Agreed as a good next artefact while the whole
  chain is fresh. (The foundation-migration rewrite — LVM-thin,
  kernel-as-vmlinuz, systemd-out, init-baked, direct-passwd — is now written up
  as **ADR-018**, so the docs-reconcile debt is closed.)
- **GUI RUN on the new kernel — DONE 2026-07-01.** `ping-client run 5 nautilus`
  rendered on host Hyprland with the three-flag `6.12.87` kernel; landlock
  warning gone. (Superseded the earlier hyprlock-deferred test.)
- **dbus-run-session decision:** nautilus rendered without it this session, so
  it stays off. The wrapper is prepared in `katmate-init.c` under
  `-DUSE_DBUS_SESSION` — enable ONLY if a future app shows Tracker/a11y timeouts.
- **Waypipe redesign — ADR-019 written (2026-07-02).** Waypipe becomes a
  project-maintained component: pinned upstream tag (`v0.11.0`) + KatMate
  patch queue (`third_party/waypipe/patches/`, strip & harden only), both
  host and guest binaries built from the same tree, host at
  `/opt/katmate/bin/waypipe` outside pacman. Drift impossible by
  construction; no pacman hook. Rationale: no wire-protocol stability
  between waypipe versions, trixie toolchain freeze makes buildability on
  trixie the binding constraint (host follows guest), ADR-012 forbids a
  distro dependency. ARCHITECTURE.md update-flow rewritten to match.
- **`katmate-update` tool (redefined by ADR-019):** a release-bump
  orchestrator, not a drift detector — bump pin → rebase patches → build
  host binary → `make foundation` → `make app-<type>` → recreate instance
  deltas → update `/var/lib/katmate/foundation.meta`. Open items, in
  dependency order:
    1. ✅ `foundation.meta` writing in `foundation.sh` — DONE (2026-07-02).
    2. ✅ **patch-queue scaffold** — DONE (2026-07-03).
       `third_party/waypipe/patches/` with `.gitkeep` + `README.md`
       (application order = ascending filename, `git apply`, "strip & harden
       only" scope). Empty, patch level 0.
    3. ✅ **host build script** `build/waypipe-host.sh` (bash) — DONE
       (2026-07-03). Built on MINIS: `waypipe 0.11.0`, `lz4/zstd true`,
       `gbm/dmabuf/video false`. Build-deps CHECK-only; missing host dep was
       `bindgen` (`rust-bindgen`).
    4. ✅ **launch preflight** in `app_web.con` (fish) — DONE (2026-07-03).
       Version lock placed BEFORE LVM activation (cheapest gate first).
       Negative test (forced `v0.10.0` → FATAL before activation) + positive
       test (match → boot) both pass.
  ADR-019 version-lock chain COMPLETE. `snapshot.debian.org` apt pin still
  deferred until the `katmate-update` orchestrator (rebuild pipeline) exists.
- **ADR-020 (2026-07-02) — release = pre-baked signed ISO.** Build-time /
  install-time boundary formalized: all pipeline scripts are developer-side;
  their output is a signed ISO; the user never builds. Cross-refs ADR-007/011
  (reproducibility), ADR-012 (distro independence), ADR-019 (build machinery
  scope). Open follow-up: whether the installer needs ANY network (offline
  install as target); how the Debian base is itself pinned/shipped so even the
  base is not fetched unaudited (ties to the deferred ADR-011 snapshot pin).
- **ISO bake pipeline** (new artefact, the output of the build chain per
  ADR-020): `download ISO → verify signature → bake USB → boot → installer
  provisions prebuilt foundation/app-layers/vmlinuz/both waypipe binaries onto
  disk`. Not yet designed; the terminal step of the developer pipeline.
- **Disposable-VM launch model** decision: unblocks `katmate-cid` `_is_alive` +
  reconcile (CID ≥100 dynamic pool).
- **Launch daemon / privilege split:** fold the launcher's `lvchange -K -ay`
  activation into a proper unit / katmate launch code (`ExecStartPre=+` as root,
  QEMU as `host`); shared `katmate-foundation.service` oneshot.
- **Migrate live AppVMs** (personal/net) off the old systemd-user / linear-root
  model onto the init+foundation chain.
- **systemd purge from foundation** (minimal-TCB): the binary still ships unused.
- **udisks2 check:** confirm nautilus works with udisks2 disabled, then bake
  `systemctl disable udisks2` into the app-layer build.
- **FILEPUT streaming** (currently buffers payload in memory); promote
  `protocol.rs` to a shared `katmate-protocol` crate (ping-client already
  symlinks it — the first step is done).
- **Installer:** secrets removal (v0.2 blocker); create `/var/lib/katmate/`.
  Per ADR-020 the installer is PROVISIONING only — partition/thin-pool, unpack
  signed images, bootloader, per-instance deltas — no build logic, no toolchain.
- **Desktop:** port CYBRland + Plymouth from Acer to MINIS.

## Invariants & gotchas (quick reminders — detail in git/ADRs)

- **Thin-LV activation:** an RO-frozen thin LV keeps the skip-activation `k`
  flag permanently; `lvchange -K -ay <lv>` is mandatory before every instance
  boot, on both the app-layer AND the foundation, or QEMU fails with "Could not
  open backing image". The `app_web.con` launcher does this in pre-flight.
- **Root device has no partition table:** debootstrap is directly on the LV, so
  `root=/dev/vda` (NOT `vda1`). `vda1` gives `VFS: Unable to mount root fs on
  unknown-block(253,1)`.
- **Serial console:** microvm + `-nographic` does NOT auto-wire the serial
  console (changed ~QEMU 10.x). Must add `-serial mon:stdio` explicitly or the
  kernel boots silently into a console nobody can see.
- **Shutdown without ACPI:** init calls `reboot(RB_AUTOBOOT)` (NOT
  `RB_POWER_OFF`, which only halts with no pm_power_off handler). Requires
  host-side `-no-reboot` (QEMU exits on the reboot event) + kernel cmdline
  `reboot=t` (go straight to triple-fault, skip the ~5s delay).
- **Agent PATH:** init launches vm-agent with `PATH=/usr/local/bin:/usr/bin:/bin`
  — waypipe is the source-built `/usr/local/bin/waypipe`, not apt. Omitting
  `/usr/local/bin` makes `RUN` return ERR (spawn: No such file or directory).
- **GUI launch:** GTK apps refuse to run as root; require user 1000 with
  `XDG_RUNTIME_DIR`. waypipe ≥0.11 self-resolves the host CID (no `2:` prefix).
- **VSOCK ports:** 1025 = vm-agent control, 1024 = waypipe GUI — two distinct
  purposeful ports. Host waypipe client must listen on 1024 before `RUN`.
- **`foundation.meta` (ADR-019):** host-side source of truth for the active
  foundation version at `/var/lib/katmate/foundation.meta`, flat `KEY=value`
  (`KATMATE_META_VERSION`, `WAYPIPE_TAG`, `WAYPIPE_PATCH_LEVEL`,
  `KERNEL_VERSION`, `BUILD_DATE`, `FOUNDATION_LV`). Written by `foundation.sh`
  at RO-freeze; read without booting/mounting. The launch preflight compares
  host `waypipe --version` (bare `x.y.z`) against `WAYPIPE_TAG` and refuses to
  start on mismatch. A rebuilt foundation overwrites it; an existing frozen
  foundation needs it hand-written once (done on MINIS).
- **Re-bake invalidates deltas:** changing `vm_app_web` under an existing
  `test_web.qcow2` makes the delta inconsistent — recreate it
  (`qemu-img create -f qcow2 -F raw -b /dev/vg0/vm_app_web <delta> 10G`). The
  create fails with "write lock" if a QEMU still holds the delta (kill the old
  VM first; do NOT kill the unrelated netVM/CID-3 QEMU).
- **Custom microvm kernel** is monolithic, passed via `-kernel` (no initrd, no
  `/lib/modules`); this is why the stock modular Debian kernel failed and
  6.12.87 (vsock builtin) succeeded. Delivered as an external vmlinuz (NOT a
  `.deb` in the image) — ARCHITECTURE.md update-flow §4.
- **Never rsync a kernel *build* tree with broad `--exclude` patterns.**
  `--exclude='vmlinux.*'` matches the SOURCE `vmlinux.lds.S` (and `.lds.h`), not
  just the `vmlinux.*` artefacts — dropping it makes the build fail with `No rule
  to make target 'arch/x86/kernel/vmlinux.lds'` even after `make mrproper` (the
  generator input is simply absent). Interrupted builds (e.g. thermal shutdown)
  also leave truncated `.o` files that pass make's timestamp check but fail at
  link with `ld: member ... is not an object`. Robust pattern for moving the
  tree to a build host: `git clone`/`git archive` a clean source + copy only
  `.config` — git knows source from artefact; broad rsync excludes do not.
- **Kernel build host is MINIS (Ryzen), not Acer.** The N4200 thermally shuts
  down under a full `-j` kernel build in summer ambient; use `-j16` on MINIS.
  Source tree at `~/src/kernel/linux-6.12.y/` on both; treat Acer's as the
  reference, MINIS's as a build copy (same source-of-truth rule as the agent).
- **foundation build (from scratch) gotchas:** (a) pseudo-fs mount AFTER
  debootstrap, never before (fresh ext4 has no `/proc` etc.); (b) ext4 label
  ≤16 chars (`katmate-found`); (c) no `useradd`/`passwd` in minbase — write the
  user directly to `/etc/passwd`+`group`+`shadow`; (d) `$(HOME)` under `sudo` is
  `/root`, so `KERNEL_SRC_DIR` is hardcoded to `/home/host/katmate-kernels`.
- **Abstract vs concrete naming:** ADRs use `foundation`/`app`/`instance`;
  concrete LVM names (`vm_tpl_foundation`, `vm_app_web`) only here and in live
  inspection.
- **Source of truth = Acer `~/katmate-os/` git repo.** MINIS
  `katmate-build/{agent,ping-client}/` are build copies — source is always
  synced FROM the repo (scp from Acer, or git pull), never edited on MINIS and
  left to diverge. (Today's "what is where" confusion came from editing on MINIS
  and hand-syncing back.) MINIS `katmate-build/trixie-build/` is the build
  chroot (compile the agent against trixie glibc); `katmate-kernels/` holds the
  live custom kernel on both machines. Git lives ONLY on Acer
  (`/home/winterbox/katmate-os/.git`); MINIS has no git.
