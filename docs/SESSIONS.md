# Session Archive — Katmate OS

> Historical session log, split out of `state.md` on 2026-07-14 (it had grown to
> 1090 lines / 68 KB, against its own "stays short" mandate). `state.md` keeps the
> header, the current focus, the **two most recent sessions**, and the living
> sections (live state, open problems, next steps, invariants). Everything older
> lands here, verbatim, newest first.
>
> **This file is append-only and is never rewritten.** Entries are records of what
> was true on the day they were written, not statements about the current target.
>
> **Reading note — CIDs.** Every CID in this archive predates
> [ADR-022](DECISIONS.md#adr-022) and uses the old single-sysVM map
> (`3` = netVM, `4` = personalVM, `5` = app_web). The current map is
> `2` host / `3–19` sysVM / `20–99` fixed AppVM / `≥100` disposable, under which
> **personalVM becomes 20 and app_web becomes 21** (netVM stays 3). The old numbers
> are left as written — they are what actually ran at the time. `state.md` carries
> the authoritative map.

---

## This session (2026-07-15) — netvm-agent listener + per-connection loop (code)

Code session, thinking off. Wrote the mechanical half of `netvm-agent` — the
one designed on 2026-07-10 and unblocked by the 2026-07-13 workspace split. No
live boot: this landed the transport, not the network operation. NETCFG's real
handler (ADR-023 payload) is still a separate session.

### What was written

`agent/crates/netvm-agent/src/main.rs` — a deliberate SUBTRACTION from
`vm-agent/src/main.rs`, keeping only the skeleton both agents genuinely share:

- **Kept:** `AF_VSOCK` socket, `bind(VMADDR_CID_ANY, DEFAULT_CONTROL_PORT)`,
  `listen`, the accept loop with its `peer.svm_cid != VMADDR_CID_HOST` reject +
  close, and the synchronous single-client per-connection loop (`read_request`
  → `Op::try_from` → dispatch → per-request ERR on handler error, EOF ends the
  loop quietly).
- **Dropped (all appVM policy, none of it protocol):** `config.rs` (no config
  surface), `posix_spawn` + `environ` (no child — there is no `spawn()` in this
  binary at all), `signal_init_shutdown` (no SHUTDOWN), `path_is_allowed` (no
  file surface), the `WHITELIST`/`HOME_PREFIX`/`INIT_SOCK`/`SHUTDOWN_CMD`
  constants, and the `SIGCHLD` `SIG_IGN` (nothing forks here, so there is
  nothing to reap).
- **Dispatch is two branches:** `Op::Ping → frame::write_ok`;
  `Op::Netcfg → handle_netcfg`.

### Two judgement calls worth recording

1. **NETCFG is an ERR stub, not `todo!()`.** NETCFG *decodes* here — it is a
   genuine capability of this binary (unlike RUN/FILEGET/FILEPUT/SHUTDOWN, which
   have no variant in `netvm-agent`'s `Op` and die at `Op::try_from`). But its
   real handler (the ADR-023 payload) is a separate session, so the handler
   currently logs and returns ERR with `Rejected("NETCFG not yet implemented")`.
   `todo!()` was rejected on purpose: a panic would crash the agent and drop the
   connection the first time the host sent NETCFG. An honest "I decode this, I
   just don't do it yet" is the right seam to leave.

2. **Port is the shared default, no env override.** `netvm-agent` uses
   `frame::DEFAULT_CONTROL_PORT` directly, with no `CONTROL_PORT` env read. This
   is not an omission — it follows the note already written in
   `vm-agent/config.rs`: *"netvm-agent has NO config.rs … its control port is
   the shared default. If it ever needs one, it gets its own."* Same port,
   different CID, exactly as the wire intends. `vm-agent` keeps its env override
   because it also carries a waypipe target; netVM carries neither.

### Verification (Acer only — host toolchain)

- `cargo build -p netvm-agent` → clean (dev + release).
- `cargo test -p netvm-agent` → `2 passed` (`forbidden_opcodes_fail_at_decode`,
  `handled_opcodes_map`) — the security-boundary assertions in `op.rs` still
  hold through this `main`.
- clippy: no new warnings from `main.rs` (the 8 `overindented` notes are
  pre-existing, from `op.rs` doc comments).
- Committed + GPG-signed on Acer as `4538e29` ("netvm-agent: implement listener
  + per-connection loop").

### What this does NOT close

The **live gate is not reached.** Acer is a host-toolchain syntax/type check
only; the shipped binary must come from the **trixie chroot on MINIS**
(`cargo build --release -p netvm-agent`), then bake into `$OUT/netvm-agent`
(netvm.sh step 7) and boot netVM for `ping-client ping 3 → OK`. Until that
runs, "nothing inside the declarative netVM image has ever been verified" still
stands — the listener exists in source, not yet on the wire.

## This session (2026-07-10) — netvm-agent architecture + QMP shutdown (design)

Design/thinking session, no live boot. Turned "netvm-agent is the unblocking
next step" into a finished, buildable design and revised ADR-021. Read the
actual sources (`agent/src/{main,protocol,error,config}.rs`, `bin/ping-client/`)
and `build/netvm.sh` before deciding — resolutions follow the code, not memory.

### Decisions (all confirmed)

1. **Cargo workspace, one shared crate.** `agent/` is the workspace root; ONE
   shared `katmate-protocol` (framing + VSOCK transport + `error` module +
   shared opcode value registry). Two guest bins: `vm-agent` (uid 1000) and
   `netvm-agent` (`CAP_NET_ADMIN`). `ping-client` moves `bin/ping-client →
   agent/crates/ping-client` as a member; symlinks dropped. Per-package guest
   builds (`cargo build --release -p vm-agent -p netvm-agent` in the trixie
   chroot); host builds `-p ping-client`. One `[profile.release]` at root.
2. **Opcode values shared, enums + handlers per-bin.** Shared `read_request`
   returns a RAW `u8` opcode (`RawRequest`), not `Cmd`; length validation stays
   shared, opcode→handler is per-bin `TryFrom<u8>`. Forbidden opcode fails at
   decode. Registry exists so `ping-client` can encode any opcode (drives both).
3. **netVM shutdown = host QMP, not an agent opcode.** q35 → ACPI. Host sends
   `system_powerdown` → logind `HandlePowerKey=poweroff` → clean networkd/wg/nft
   stop, releasing the RTL8125 for FLReset-. So `netvm-agent` = **NETCFG + PING
   only**; no SHUTDOWN, no `CAP_SYS_BOOT`, no dbus/polkit. appVM `vm-agent` KEEPS
   SHUTDOWN (→ katmate-init; microvm has no ACPI). ("graceful ⟹ root" was wrong —
   graceful = ask PID 1 / the host, not privilege the agent.)
4. **In-guest verification uses a dev-only console password** (decision B),
   out-of-band, same "remove before release" class as sshd. The agent has no
   RUN, so it is NOT the verification path.

### ADR-021 revised (committed, GPG-signed, pushed)

Four blocks: opcode table + registry/absent-not-disabled wording; QMP shutdown
bullet (replaces old "SHUTDOWN … graceful teardown"); `CAP_NET_ADMIN` scope (now
one job, NETCFG); rejected alternative (in-agent SHUTDOWN via `CAP_SYS_BOOT` or
logind/polkit — q35 ACPI makes host QMP graceful without guest privilege).

### Next (CODE session, thinking off)

Ordered, each with a gate: (a) `katmate-protocol` (codec split, raw-opcode
`read_request`); (b) `vm-agent` onto it, UNCHANGED behaviour — regression gate
`ping-client ping 5 → OK` before touching netVM; (c) `netvm-agent` (PING +
NETCFG); (d) `ping-client` moved in. Then bake `$OUT/netvm-agent` (netvm.sh step
7, already scaffolded), boot-test `ping-client ping 3 → OK` as first live
control-path proof.

## This session (2026-07-09) — netVM sysVM declarative build PROVEN

The ADR-021 declarative build (`build/netvm.sh`, from the 2026-07-08 session)
was taken from "builds cleanly" to "boots and reaches the network" on MINIS.
Objective: prove the built `vm_sys_netvm` image boots unaided and reproduces the
uplink that previously lived only in the hand-installed netinst pet. Done — with
two real bugs fixed along the way and a host-side motiliec (suspend) neutralised.

### Two build-blocking bugs fixed (both in `netvm.sh`, committed + pushed)

1. **initrd `MODULES=dep` → `MODULES=most`.** The first sysVM boot dropped to an
   initramfs shell: `ALERT! /dev/vda does not exist`. Root cause: `MODULES=dep`
   resolves needed modules against the BUILD-time root (ext4-on-dm in the chroot),
   so `virtio_blk`/`virtio_pci` were omitted — but the guest boots as a virtio
   device with root on `/dev/vda`. `virtio-pci` transport was present (device
   enumerated as `virtio2`), but without `virtio_blk` no `/dev/vda` node. Fix:
   `MODULES=most` includes the full virtio + common-storage set regardless of
   build context. Proof: initrd grew 11MB → 36MB; second boot showed
   `virtio_blk virtio2: [vda] ... 4.00 GiB` and `EXT4-fs (vda): mounted`.
   (`dep` was originally chosen for a trimmed initrd + to avoid the jbd2-inducing
   post-apt `update-initramfs` — `most` keeps the "postinst generates it" path,
   only widens the module set.)
2. **conf.d seed `printf >` → `install -D`.** After the `most` edit, the build
   aborted mid-write: `.../initramfs-tools/conf.d/modules-most: No such file or
   directory`. Cause: `printf > path` does NOT create parent dirs, and
   `/etc/initramfs-tools/conf.d/` does not exist yet on a fresh debootstrap. The
   original `dep` code used `install -D` (creates dir + mode + content in one).
   Fix: restore `install -D -m 0644 /dev/stdin ... <<< 'MODULES=most'`. (A stray
   deleted `)` on the adjacent `mapfile` line was caught by `git diff` + `bash -n`
   before commit — the reason to always `bash -n` a build script after editing.)

Conf renamed `modules-dep` → `modules-most` to match. Both fixes GPG-signed and
pushed (commits `bd96a21`, `37c3fb0`).

### Host suspend masked (the real time-sink this session)

hypridle put MINIS to sleep TWICE mid-build while attention was elsewhere,
each time killing the build and leaving a stuck `jbd2` kthread on the new LV
(the documented "build failure mid-`/boot` write" pattern → host reboot the only
cure). Neutralised for good:
`systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
— a hard, reboot-surviving block independent of any idle daemon. UNMASK after
the build sessions are over. General rule now: mask suspend before any netVM
build run; the build host must stay awake through debootstrap + `/boot` write.

### Boot + uplink gate — PASSED

Built via `sudo bash -c 'DEBIAN_MIRROR=http://ftp.ch.debian.org/debian bash
netvm.sh'` (CH mirror because MINIS's ProtonVPN exit is in Switzerland; the
Ljubljana `deb.debian.org` fastly timeouts do not apply from a CH exit, and an
SI mirror over a CH tunnel would be worse). Build ran clean to `Exporting
vmlinuz + initrd` + `netvm.meta` + `Unmounting`. Boot via a fresh minimal
`~/net-sys.con` (uplink only — internal TAP dropped for this gate):

- `virtio_blk virtio2: [vda] 8388608 512-byte logical blocks (4.00 GiB)` — the
  `most` fix working; `/dev/vda` present.
- `EXT4-fs (vda): mounted filesystem ... r/w` — root mounted (was the failure
  point).
- Full systemd to `multi-user.target` / `graphical.target` — sysVM, not
  katmate-init (correct for netVM).
- `r8169 ... enp0s5: RTL8125B, 38:05:25:34:7c:47` — firmware loaded (no `-2`;
  `firmware-realtek` from the manifest), then
  `enp0s5: Link is Up - 1Gbps/Full`.
- **DHCP lease confirmed from the host:** `nmap -sn 10.3.1.0/24` shows
  `10.3.1.110` up with MAC `38:05:25:34:7c:47`. (ICMP ping did NOT answer —
  netVM nftables drops it — but the ARP scan proves L2 presence + lease. This is
  the correct security posture, not a fault.)

Interface is `enp0s5` here, not `enp0s6` — this minimal launcher omits the
internal TAP NIC, so the RTL8125 lands on a different PCI slot / name. Irrelevant
by design: `20-uplink.network` matches by MAC, not `Name=`, which is the whole
reason for the MAC match. `Open count: 0` after `QEMU: Terminated` — clean
teardown, no jbd2.

### What this closes, what it does not

- **Closes:** the netVM pet-drift class (Open problem #6). The uplink is now
  reproduced from `netvm.sh`, not from a hand-installed instance. ADR-021's
  central claim (declarative sysVM build) is proven end-to-end for the uplink.
- **Does NOT close yet:** there is no way INTO the guest — `netvm.sh` locks root
  ("dev sets a console password out-of-band", which was never done), so console
  login fails and there is no `netvm-agent` yet. `networkctl status` /
  WireGuard bring-up / inner-segment (personalVM p2p) are all unverified from
  inside because of this. The `netvm-agent` is now the unblocking next step, not
  a nicety.

### Follow-ups noticed this session

- **`netvm.sh` cleanup leaves a hot jbd2 even on SUCCESS.** The successful build
  ended with `Open count: 1` + live `jbd2/dm-17` despite `mount` empty and
  `lsof`/`fuser` clean — the umount returned before jbd2 committed. Harden
  cleanup: `umount -R "$NETVM_MNT"` → `sync` → `udevadm settle` → short `sleep`
  before the script returns, so a successful build does not force a reboot.
- **`W: No zstd ... using gzip`** during initramfs generation — the image lacks
  `zstd`, so initrd is gzip-compressed (larger, works). Add `zstd` to the netVM
  manifest if a smaller/faster initrd is wanted. Cosmetic.
- **`net-sys.con` vs `net-vfio.con` naming + location.** The new sysVM launcher
  is `~/net-sys.con` (host-local, not in git); the retired pet used
  `~/net-vfio.con`. `netvm.sh` comment still says `net-vfio.con`. Settle the
  canonical launcher name + location when the pet is formally retired.

## This session (2026-07-08) — netVM uplink complete; netVM = sysVM decision

Live work on MINIS console + serial into netVM (CID 3). Objective: point the
guest at the passed-through RTL8125 (`enp0s6`), then run the critical
second-boot FLReset- test. Both done; a firmware gap surfaced and was closed;
and the session produced an architectural decision about how netVM is built.

### netVM in-guest netconf (`enp0s6`) — DONE

- **Diagnosis of the first-boot `[FAILED] Raise network interfaces`:** the guest
  had TWO stacks active — `systemd-networkd` (enabled, running) AND `networking`
  (ifupdown, enabled but **failed**). `/etc/network/interfaces` carried a stale
  static block for `enx00e04c3961b8` — the HOST's USB-NIC MAC, wrong VM entirely
  — almost certainly written by the original netinst installer back when the
  USB-NIC was passed into netVM. That is the source of the recurring boot
  failure, not `enp0s6` itself.
- **Fix (ifupdown side):** reduced `/etc/network/interfaces` to `lo` +
  `source interfaces.d/*` only. The primary-interface job now belongs entirely
  to networkd.
- **New `/etc/systemd/network/20-uplink.network`** — MAC-match (stable across
  PCI topology), DHCP:
  ```ini
  [Match]
  MACAddress=38:05:25:34:7c:47

  [Network]
  DHCP=ipv4

  [DHCP]
  RouteMetric=100
  ```
  (`38:05:25:34:7c:47` = the RTL8125's MAC as seen in the guest. Matches by MAC,
  not `Name=enp0s6`, so a slot/name change does not break it — the whole reason
  for the exercise. `10-personal.network` stays `Name=`-matched on `enp0s4`, the
  internal p2p segment to personalVM at `10.100.1.2`.)

### Firmware gap (the real last blocker) — closed

- **Symptom:** after networkd matched and brought the link UP, it stayed
  `no-carrier`: `r8169 0000:00:06.0: Unable to load firmware
  rtl_nic/rtl8125b-2.fw (-2)`. `-2` = ENOENT: `/lib/firmware/rtl_nic/` was empty.
- **Root cause:** vfio hands the RTL8125 to the guest as a plain PCI device, and
  the guest's own `r8169` needs the Realtek firmware blob to bring the PHY up.
  The netinst netVM image never had `firmware-realtek` (the USB-NIC r8152 the
  guest used before does not need a separate blob).
- **Fix:** `apt install firmware-realtek` (already had `non-free-firmware` in
  `sources.list`; apt reached the mirror over the internal segment).
  `ip link set enp0s6 down; up` reloaded the driver with the blob present.
- **Result:** `Gained carrier` → `DHCPv4 address 10.3.1.110/24, gateway
  10.3.1.1`. `networkctl status enp0s6`: `State: routable (configured)`,
  `Online state: online`, `Speed: 1Gbps` full duplex.

### Second-boot FLReset- test — PASSED (the critical gate)

Clean shutdown of netVM → fresh `net-vfio.con` launch. On the second boot the
guest reached the console with no ENOMEM and no VFIO reset error, firmware
loaded at boot (no `-2` this time), and `enp0s6` came back `routable` with the
same DHCP lease `10.3.1.110/24`, 1Gbps full duplex, fresh `systemd-networkd`
PID. This proves `disable_idle_d3=1` survives a guest reboot cycle for the
FLR-less RTL8125 — the first boot succeeding was never sufficient; this is the
result that makes the passthrough usable. The earlier one-off `Link DOWN /
Lost carrier` blip did NOT recur (was a switch/cable renegotiation, not the
device).

### Architectural decision — netVM is a sysVM (→ ADR-021, pending)

netVM is deliberately a **separate component class**, not an appVM, and will
NOT be folded into foundation/app-layer or `katmate-update`. Rationale:
- **Different machine model:** the ONLY VM with `-machine q35` (needs PCI for
  vfio passthrough), not microvm. Needs ACPI/initramfs/firmware and full
  systemd (networkd, wg-quick, DHCP client) — the exact opposite of the
  systemd-free, katmate-init foundation.
- **Different lifecycle:** appVM rebuilds are driven by waypipe bumps (ADR-019);
  netVM has no waypipe at all. netVM rebuilds are driven by Debian security
  updates + network config. `katmate-update` must never touch it.
- **In Qubes terms:** this is a sysVM, a different class from appVMs.

BUT "separate" must mean "separately declarative", NOT "hand-maintained forever".
The current netVM is a netinst pet (`deb cdrom:` line, GRUB+initrd in-guest,
installer-written configs) — and that pet just leaked the stale-`interfaces`
bug into the most security-exposed VM (raw network, VPN keys). ADR-020 (release
= pre-baked ISO, user never builds) and ROADMAP step 3 (NetVM installer
integration) both REQUIRE netVM to be provisioned declaratively by the
installer, which is impossible while it is a hand-installed pet. So the decision
is: **a dedicated `build/netvm.sh` (debootstrap-based, its own package + config
manifest), a separate `netvm-update` track, and ADR-021 to record it.** Full
design + the script belong to a dedicated Opus/thinking session, not this one.

### netVM manual deltas PENDING pipeline (must not be lost)

These fixes exist ONLY in the running netVM instance and will vanish on any
rebuild until `build/netvm.sh` exists:
1. `firmware-realtek` installed (for `rtl8125b-2.fw`).
2. `/etc/systemd/network/20-uplink.network` (MAC-matched DHCP for `enp0s6`).
3. `/etc/network/interfaces` reduced to `lo` + `source` (stale
   `enx00e04c3961b8` static block removed).
Also to check at pipeline time: where the stale `enx00e04c3961b8` block came
from (netinst installer artefact) so it is not re-baked.

### Open follow-up noticed this session

- **DNS leak risk:** the DHCP lease on `enp0s6` set `DNS: 1.1.1.1` (LAN-router
  supplied). netVM is meant to push DNS through ProtonVPN (`10.2.0.1`); a
  LAN-supplied resolver on the uplink can leak queries outside the tunnel.
  Decide whether to override with `DNS=10.2.0.1` + `Domains=~.` in
  `20-uplink.network`, or ignore the uplink's DNS entirely. Security-relevant;
  fold into the netvm manifest.

## Archived — completed threads (2026-07-05 / 2026-07-06)

Both the RTL8125 passthrough and the USB-NIC host recovery threads are now
CLOSED (the uplink completion above supersedes them). One-line each; full
detail in git history and the invariants below.

- **2026-07-05 — RTL8125 PCIe passthrough achieved.** `memlock` drop-in
  (`netVM.service.d/memlock.conf` → `LimitMEMLOCK=infinity`),
  `/etc/modprobe.d/vfio.conf` (`ids=10ec:8125 disable_idle_d3=1` +
  `softdep r8169 pre: vfio-pci`), vfio modules in mkinitcpio, `/dev/vfio/12`
  via a `vfio` group + udev rule. Post-reboot bind confirmed
  (`Kernel driver in use: vfio-pci`); `net-vfio.con` first boot reached
  `enp0s6`. (See invariants: memlock, FLReset-, vfio device permission.)
- **2026-07-06 — USB-NIC (r8152, `0bda:8153`) host recovery SOLVED (#7).** Root
  cause was OUR OWN leftover udev rule `/etc/udev/rules.d/30-usb-nic-qemu.rules`
  running `r8152/unbind` on every plug → `driver=[none]` after clean
  enumeration, on every port/bus. Fix: `rm` the rule + `udevadm` reload. NIC
  came up as `enp195s0f3u1u1` (MAC `00:e0:4c:39:61:b8`). A full `linux-6.12.94`
  build that session was wasted effort (MINIS runs Arch `7.0.12`, not 6.12.y;
  r8152 was present all along). Diagnostic lesson promoted to an invariant
  (check `udev/rules.d` before kernel hypotheses).

## This session (2026-07-04) — katmate-update MVP orchestrator

`build/katmate-update.sh` written and dry-run-validated on MINIS. Closes
ROADMAP build-order step 2 (the orchestrator that chains a waypipe bump end to
end).

- **`build/katmate-update.sh` (bash, committed):** sources `build/config.sh`,
  then chains the proven steps in dependency order — build host waypipe
  (`waypipe-host.sh`) → `make foundation` (writes `foundation.meta`) →
  `make app-web` + `make app-vault` → recreate instance deltas. Home LVs
  untouched. Realizes ADR-019 / ARCHITECTURE.md update-flow §1.
  - **MVP scope, deliberately narrow:** instances assumed STOPPED — no
    teardown (that is launch-daemon policy: disposable vs persistent, must not
    kill netVM/CID 3). Preflight aborts loudly (via `fuser`) if any qemu holds
    an instance delta, BEFORE the destructive foundation rebuild.
  - `WAYPIPE_VERSION` edited by hand in `config.sh`; the script only reads it.
    App types hardcoded `web vault` (matches Makefile `APP_TYPES`).
  - vm-agent + kernel vmlinuz are NOT built here; their presence is checked so
    a missing artefact fails before rebuild, not mid-`make`.
  - Delta → app-type mapping by `<instance>_<type>.qcow2` convention, validated
    in the preflight (type = last `_` segment).
  - `--dry-run`: runs all checks, prints the plan, performs no build/make/
    recreate (root not required). Used to validate this session — no live
    rebuild was run (would needlessly destroy the working frozen foundation).
- **Dry-run result:** config read (`v0.11.0`), all paths resolved, single delta
  `test_web.qcow2` found + free, mapping `test_web → web → /dev/vg0/vm_app_web`
  OK, full chain printed. Clean.
- **`out/vm-agent` staged on MINIS:** the Makefile foundation target requires
  `out/vm-agent`, but the binary was only ever built to
  `agent/target/release/vm-agent` (never copied to `out/`). Copied into place.
  Verified: dynamically linked, max symbol `GLIBC_2.34` (well under trixie's
  2.41 — safe for the guest). `out/` is a build artefact, gitignored.

### Notes / cosmetics observed 2026-07-04

- **Naming wart (`WAYPIPE_VERSION` vs `WAYPIPE_TAG`):** `config.sh` exports the
  variable as `WAYPIPE_VERSION`; the `foundation.meta` KEY written by
  `foundation.sh` is `WAYPIPE_TAG`. Same value, two names — a trap. Worth
  unifying, or at least cross-referencing in an ADR comment.
- **Stale Makefile header comment:** still lists `out/linux-image-...deb` as a
  foundation prerequisite, though the kernel path is now `KERNEL_VMLINUZ`
  (external vmlinuz, not `.deb`). Cosmetic; clean up on next Makefile touch.

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

### Notes / cosmetics observed 2026-07-03

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
ping 5` → `status=0x00 (OK)`. **Foundation pipeline complete (part of
ROADMAP build-order step 1).**

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

