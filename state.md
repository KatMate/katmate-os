# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Last updated:** 2026-06-27 (app-layer hardening proven end-to-end: custom init + Rust agent shutdown + render, live on MINIS)
**Milestone:** v0.2 (in development)

## Current focus

App-layer appliance vertical slice is now **proven end-to-end on live MINIS
hardware** (2026-06-27): boot → render → shutdown, all three phases validated
with the new stack. Remaining work shifts to generalising the app-layer pattern
to other domain types and migrating the live AppVMs onto the foundation chain.

The full slice as proven today on `vm_app_web` (CID 5):
`foundation (thin RO) ← vm_app_web (thin snap RO) ← qcow2 delta` → custom
microvm kernel `6.12.87` → **katmate-init (PID 1)** → **vm-agent (uid 1000)** →
waypipe-over-VSOCK → host Hyprland. systemd is gone from the guest entirely.

Direction unchanged: IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only
frozen (ADR-015). MINIS is primary host and merge target.

## Proven this session (2026-06-27) — live on MINIS, CID 5

The whole app-layer hardening slice, validated against `ping-client`:

- **PING** → `status=0x00 OK` — VSOCK control channel (port 1025) live.
- **RUN nautilus** → `status=0x00 OK` — agent spawns waypipe; host-side
  `waypipe ... client-conn -c lz4` connection established (render path live;
  lz4 matches guest `lz4:true`). nautilus rendered without dbus-run-session.
- **SHUTDOWN** → `status=0x00 OK` → clean teardown observed on ttyS0:
  agent → init socket → init kills children → `/home` (vdb) unmounted →
  root (vda) re-mounted RO → `reboot(RB_AUTOBOOT)` → triple-fault →
  QEMU (`-no-reboot`) exits cleanly. No hard kill.

### Architecture decided + implemented this session (ADR-worthy, not yet written)

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

### Files changed this session (live on MINIS; commit on Acer pending)

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
  drop; SSH open (dev, Open problem #4).
- **netVM** (CID 3, Debian trixie, q35): USB-NIC passthrough (r8152),
  WireGuard/ProtonVPN, inner-segment routing. Runs independently of app_web.
- **personalVM** (CID 4, Debian trixie, microvm): still on the **old**
  systemd-user model (pre-foundation linear root). Migration to the
  init+foundation model is pending (Next steps).
- **app_web** (CID 5): the proven appliance. Backing `vm_app_web` (thin snap
  RO) ← `/var/lib/katmate/instances/test_web.qcow2`. `/home` =
  `vm_app_web_home` (10G ext4 raw LV, created this session, `/home/user` owned
  1000:1000). init + Rust vm-agent + user 1000 baked in.
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
6. Disk model + GUI chain + shutdown are **resolved** end-to-end. What remains
   is generalisation + migration, not the mechanism.

## Next steps

- **Commit this session's work on Acer** (MINIS has no git): the four changed
  files + new `katmate-init.c`. GPG-signed (`commit.gpgsign` not global — set
  it). Write the ADR for "systemd out of guest / custom init / init-socket
  shutdown / vm-power-helper removed" (next number after the last committed
  ADR — verify with `grep -n '^## ADR-' DECISIONS.md`; snapshot shows ADR-017,
  but ADR-018 (Rust rewrite) may already be on Codeberg).
- **Generalise the app-layer pattern:** `app-<type>` thin snapshot from
  `vm_tpl_foundation` — `vm_app_web` is done; next is templating other domains.
- **dbus-run-session decision:** nautilus rendered without it this session, so
  it stays off. The wrapper is prepared in `katmate-init.c` under
  `-DUSE_DBUS_SESSION` (agent launched under one session bus) — enable ONLY if
  a future app shows Tracker/a11y timeouts.
- **Kernel rebuild (6.12.87 → next):** add `CONFIG_HW_RANDOM_VIRTIO=y` (guest
  has `virtio-rng-device`; without the driver `getrandom` may block at boot)
  and `CONFIG_SECURITY_LANDLOCK=y`. Keep confirmed builtins (`VIRTIO_VSOCKETS`,
  `VIRTIO_MMIO`, `NET_9P_VIRTIO`, `EXT4_FS`); no ACPI by design.
- **Launch daemon / privilege split:** fold the launcher's `lvchange -K -ay`
  activation into a proper unit / katmate launch code (`ExecStartPre=+` as root,
  QEMU as `host`); shared `katmate-foundation.service` oneshot.
- **`katmate-cid` allocator:** reconcile the stub + `_is_alive` await with the
  disposable-VM launch model (CID ≥100 dynamic pool).
- **Migrate live AppVMs** (personal/net) off the old systemd-user / linear-root
  model onto the init+foundation chain.
- **udisks2 check:** confirm nautilus works with udisks2 disabled, then bake
  `systemctl disable udisks2` into the app-layer build.
- **FILEPUT streaming** (currently buffers payload in memory); promote
  `protocol.rs` to a shared `katmate-protocol` crate (ping-client already
  symlinks it — the first step is done).
- **Installer:** secrets removal (v0.2 blocker); create `/var/lib/katmate/`.
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
- **Re-bake invalidates deltas:** changing `vm_app_web` under an existing
  `test_web.qcow2` makes the delta inconsistent — recreate it
  (`qemu-img create -f qcow2 -F raw -b /dev/vg0/vm_app_web <delta> 10G`). The
  create fails with "write lock" if a QEMU still holds the delta (kill the old
  VM first; do NOT kill the unrelated netVM/CID-3 QEMU).
- **Custom microvm kernel** is monolithic, passed via `-kernel` (no initrd, no
  `/lib/modules`); this is why the stock modular Debian kernel failed and
  6.12.87 (vsock builtin) succeeded.
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
