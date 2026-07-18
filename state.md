# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Last updated:** 2026-07-18 — **LIVE GATE PASSED: netVM graceful shutdown
via the agent. `ping-client shutdown 3 → OK` + clean poweroff; Open problem #10
CLOSED (ADR-024).** SHUTDOWN returns to `netvm-agent` as opcode 0x05: reply-OK
first, then `kill(1, SIGRTMIN+4)` so systemd (PID 1) runs `poweroff.target` —
byte-for-byte the `systemctl poweroff` stop, with no dbus, no logind, no acpid,
no `CAP_SYS_BOOT`. Delivered by a non-root agent holding `CAP_KILL` (unit
ambient+bounding). Empirically chosen over three dead candidates (E1-E8 in
ADR-024): QMP/logind inert (no dbus), non-root `systemctl` has no bus,
`/run/systemd/private` root-only, `CAP_SYS_BOOT`+`reboot(2)` not graceful under
systemd PID 1. Proven on the wire: `op=SHUTDOWN (0x05) → status=0x00 (OK)`, and
the netVM console ran the full stop (`EXT4-fs (vda): re-mounted … ro` →
`reboot: Power down`). The reply-first ordering is confirmed by the console
stopping `netvm-agent.service` mid-sequence — the OK reached the wire before the
agent died. Whole image rebuilt from `netvm.sh` (fresh binary + `CAP_KILL` unit,
KVER=6.12.95+deb13-amd64), which also erased the acpid + dev-root experiment
remnants — the manifest is clean (no acpid in the shutdown sequence).

**Prior live gate (2026-07-17):** first control path into netVM proven —
`ping-client ping 3 → OK`. Detail in SESSIONS.md (2026-07-17 entry).
**Milestone:** v0.2 (in development)

## Current focus

The RTL8125 passthrough backbone is COMPLETE and proven across a reboot cycle:
`vfio.conf` binds the NIC away from `r8169` at boot, `net-vfio.con` launches
netVM with `-device vfio-pci,host=0000:01:00.0`, the guest enumerates it as
`enp0s6`, and with `firmware-realtek` present + a MAC-matched networkd profile
the link is routable with a DHCP lease. Both the first and the critical second
boot succeeded. The uplink deltas now survive a rebuild: `build/netvm.sh`
reproduces them declaratively (proven 2026-07-09), and the netinst pet is retired
in principle. The remaining netVM work is **a control path into the guest** —
root is locked in the declarative image, so nothing inside it has ever been
verified. That is `netvm-agent`, whose workspace landed 2026-07-13 and whose
`main()` is the next code to write.

The **entire build chain remains scripted and proven from nothing** (unchanged
this session): `make foundation` builds the shared systemd-free base
(debootstrap → base → waypipe-from-source → bake init/agent/user → freeze),
`make app-web`/`make app-vault` snapshot it, and an instance boots end-to-end.
The release model is fixed (ADR-020): the build chain is developer-side; its
output is a signed ISO; the user installs by verify → bake → boot → provision,
never by building. `katmate-update` (ADR-019 version-lock backbone) is complete
— and, per this session, deliberately does NOT cover netVM.

Direction unchanged: IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only
frozen (ADR-015). MINIS is primary host and merge target.

## This session (2026-07-14) — network object model FINALIZED (design, no code)

Two ADRs written, no live work. The network layer gets an object model.

**ADR-022 — topology is a graph; the NIC is an assignable object.** Five object
classes (`Nic`, `Image`, `Vm`, `Link`, `Policy`). The whole topology is two
fields on `Vm`: `netvm: Option<VmRef>` + `provides_network: bool`. Consequences:
policy is a *netVM*, never a rule (differentiated access = attach to a different
netVM, each baking one immutable policy — ADR-021's static firewall survives
intact); `netvm: None` = first-class offline/air-gap AppVM (absence of an object,
not a deny rule); one physical NIC = one **q35 driver domain** (hardware, no
secrets); **proxy netVMs are microVMs** (no PCI → no q35) and may be chained, so
`appVM → netvm-vpn → netvm-driver → NIC` is cheap here in a way it is not in
Xen/Qubes. **v1 ships the simplest graph = the netVM running today.** Nothing
built so far is discarded.

**ADR-023 — NETCFG describes a link, never an AppVM.** Payload = one p2p link
(match, local/peer addr, `/32`, route, metric), ops `add`/`remove` only (no
`modify` — a mutable link is a boundary that moves in place). No VM name, no
role, no policy, no nft, no shell string. One opcode therefore serves an AppVM
downlink, a proxy uplink and a future sysVM↔sysVM edge; `netvm-agent` stays a
dumb executor with no representation of the graph. **In-guest mechanism left
open** (networkd fragment vs direct `rtnetlink`) — decided in the
`netvm-agent/main.rs` session, fragment path is the default.

### Consequences to act on

- **CID renumbering (breaking).** New map: `2` host / `3–19` sysVM (3 = primary
  netVM) / `20–99` fixed AppVM / `≥100` disposable. **personalVM 4 → 20,
  app_web 5 → 21.** Launchers, `.con` scripts and any hardcoded CID must follow.
- **Kernel:** proxy sysVMs will need `CONFIG_WIREGUARD` + nft/netfilter in the
  shared microvm kernel — which all AppVMs also run. The code is unreachable from
  an AppVM (uid 1000, no `CAP_NET_ADMIN`) but *present*: a conscious departure
  from absent-not-disabled at the kernel level, accepted because ADR-021 already
  rejected a second kernel (doubled config maintenance, firmware-licensing issues
  for ISO distribution). Taken up when the first proxy is built, not before.
  (Note: there is NO pending rebuild — `HW_RANDOM_VIRTIO` and
  `SECURITY_LANDLOCK` went in on 2026-07-01 and are live.)
- **Proxy init model is open:** ADR-021 binds netVM to systemd for *uplink* DHCP;
  a proxy has no uplink DHCP (static p2p link via NETCFG) and `wg`+`nft` need no
  networkd → a proxy may be a `katmate-init` sysVM. Separate decision, when the
  first proxy is built.
- **Known gap #7 (new):** in v1 the WireGuard key and the `r8169` driver + Realtek
  blob share one address space. Accepted for v1; the model already permits the
  split.
- **Known gap #9 (new):** IOMMU-group quality is now a *hard* requirement →
  HCL + installer preflight. Product blocker, not a v1 code blocker.
- **DE decided (→ ADR-016 revision, next session):** the host compositor is in the
  TCB (it draws the domain indicator). **Sway ships alone**, no installer choice,
  no dual install. Hyprland/CYBRland stays a dev/demo profile until its indicator
  implementation is separately verified. DE profile contract documented in
  ARCHITECTURE.md.

**Next session unchanged:** `netvm-agent/main.rs` listener (mechanical, thinking
off). Live gate: `ping-client ping 3 → OK`.

## This session (2026-07-13) — agent Cargo workspace split

Mechanical migration of the existing Rust agent into the workspace skeleton
designed in the 2026-07-10 architecture session. No behaviour change intended in
`vm-agent`; the split had to be provably transparent on the wire before
`netvm-agent` could be written against it.

### What moved where

| from | to | change |
|---|---|---|
| `agent/src/protocol.rs` (codec) | `katmate-protocol/src/frame.rs` | `Cmd` + `from_u8`/`to_u8` **removed, no replacement**; `Request` → `RawRequest{opcode: u8}`; `encode_request(op: u8, …)` |
| `agent/src/protocol.rs` (policy consts) | `vm-agent/src/main.rs` | `WHITELIST`, `HOME_PREFIX`, `INIT_SOCK`, `SHUTDOWN_CMD`, `DEFAULT_HOST_CID`, `DEFAULT_WAYPIPE_PORT` |
| `agent/src/error.rs` | `katmate-protocol/src/error.rs` | verbatim; only `UnknownCommand`'s doc + `Display` reworded |
| `agent/src/config.rs` | `vm-agent/src/config.rs` | fallbacks re-pointed |
| `agent/src/main.rs` | `vm-agent/src/main.rs` | `match req.cmd` → `Op::try_from(req.opcode)?` |
| `bin/ping-client/` | `crates/ping-client/` | symlinks into `agent/src/` gone; encodes raw `opcode::OP_*`, has no `Op` of its own |
| `agent/vm-agent.c` | — | legacy C agent deleted |

The constant split is the whole point and is worth restating: `frame.rs` keeps
only what is genuinely shared wire (`PROTOCOL_VERSION`, `STATUS_*`, `MAX_*`,
`DEFAULT_CONTROL_PORT`). Everything else was never protocol — it was appVM
policy, and `netvm-agent` must not inherit it.

### One judgement call worth recording

An unmapped opcode no longer closes the connection. Previously `Cmd::from_u8`
lived *inside* `read_request`, so a bad opcode surfaced as a decode error and
`handle_connection` dropped the peer. Now decode and mapping are separate steps,
so this had to be chosen rather than inherited: `Op::try_from` failure → log +
ERR + **`continue`**. Rationale: the peer did not corrupt the stream, it asked
for something this binary does not implement. Keep serving. (Reverting to
drop-the-connection is a one-line change if that turns out wrong.)

### Regression gate — PASSED

Deliberately run against the **pre-split guest image** (`vm_app_web` still
carries the old monolithic `vm-agent`), because that is the one thing this test
can prove and the new image cannot: **the wire did not change.** New workspace
`ping-client` → old in-guest agent:

- `ping-client ping 5` → `status=0x00 (OK)`
- `ping-client run 5 nautilus` → `OK`, nautilus renders on host Hyprland

If the split had broken the codec, this fails. It did not. Any future failure
against a *new* image is therefore in `vm-agent`, not in `katmate-protocol` —
which is exactly the isolation the two-stage gate buys.

Baking the new `vm-agent` into an app layer is a separate step (app-layer
rebuild), not done this session.

### Housekeeping

- **Binary path changed:** `agent/target/release/ping-client`
  (was `bin/ping-client/target/release/ping-client`). Anything on MINIS that
  invokes it — and the rsync exclude set — needs the update.
- Stale `agent/src/`, `agent/vm-agent.c`, `bin/ping-client/` removed from the
  MINIS build copy by hand before rsync (the sync runs without `--delete`).
- Boot log re-confirms the 2026-07-01 kernel flags are live: `landlock: Up and
  running`, `ALSA #0: Loopback 1`, `crng init done` @ 0.010s. No kernel rebuild
  pending.


## Session archive

Sessions older than the two above (2026-07-10 back to 2026-06-27) live in
[docs/SESSIONS.md](docs/SESSIONS.md), split out on 2026-07-14. That file is
append-only; CIDs in it are the pre-ADR-022 numbering and are deliberately not
rewritten. **This file carries the authoritative CID map** (see *Live state*).

## Live state (MINIS/UM870) — summary

**CID map (authoritative, ADR-022).** `2` = host · `3–19` = sysVMs (3 = primary
netVM) · `20–99` = fixed persistent AppVMs · `≥100` = dynamic disposable pool.
The renumbering (**personalVM 4 → 20, app_web 5 → 21**) is decided but **NOT yet
applied** — the live VMs below still run the old numbers, and launchers/`.con`
scripts still hardcode them. Fixing that is a Next step.

- **Host** (Arch): Ryzen 7 8745H, AMD-Vi + vfio. `vg0`: `root` 100G, `swap`
  12G, `vm_pool` thin pool. Custom microvm kernel `6.12.87` at
  `/home/host/katmate-kernels/` (monolithic, `-kernel`, no initrd). nft input
  drop; SSH open (dev, Open problem #4). Host is on a SI IP in LJ, direct (the
  host's own apt/debootstrap traffic does NOT route through netVM/ProtonVPN).
  **RTL8125 (`01:00.0`) now bound to `vfio-pci` at boot** (was `r8169`) — host
  no longer has this NIC; it belongs to netVM. `vfio` group + udev rule added;
  `host` is a member. **Host uplink is now the USB-NIC r8152**
  (`enp195s0f3u1u1`, MAC `00:e0:4c:39:61:b8`, IP `10.3.1.3` — #7 resolved
  2026-07-06); MINIS is on ProtonVPN with DNS `10.2.0.1`. The uplink config is
  volatile (`ip addr`), not yet a persistent profile.
- **foundation** (`vm_tpl_foundation`, thin RO): clean, systemd-free,
  init/agent/waypipe/user baked in.
- **netVM** (CID 3 — unchanged by the new map; Debian trixie, q35, **sysVM class
  — ADR-021; driver domain — ADR-022**): two
  artefacts now exist. (a) The old hand-installed **netinst pet**
  (`net-vfio.con`, `vm_net_overlay.qcow2`, guest `enp0s6`) — retired in
  principle, superseded. (b) The **declarative build** `vm_sys_netvm` (linear RW
  4G) from `build/netvm.sh`, booted via `~/net-sys.con` (RTL8125 via
  `-device vfio-pci,host=0000:01:00.0`, `-kernel`/`-initrd` direct boot, kernel
  `6.12.95+deb13-amd64`). **PROVEN this session:** boots through full systemd,
  root on `/dev/vda`, `enp0s5` (MAC-matched) `Link is Up 1Gbps/Full`,
  firmware-realtek loaded, DHCP lease `10.3.1.110` confirmed by host ARP scan.
  The uplink deltas (`firmware-realtek`, `20-uplink.network`, cleaned
  `interfaces`) are now baked by the manifest, not hand-applied. NOT yet
  verified from inside (root locked, no `netvm-agent` — see 2026-07-09 session):
  `networkctl` state, WireGuard/ProtonVPN bring-up, inner-segment `enp0s4` p2p
  to personalVM. `memlock` via `LimitMEMLOCK=infinity` (unit) or `ulimit -l
  unlimited` (manual launch). Runs independently of app_web.
- **personalVM** (CID 4 → **renumber to 20**; Debian trixie, microvm): still on
  the **old** systemd-user model (pre-foundation linear root). Migration to the
  init+foundation model is pending (Next steps).
- **app_web** (CID 5 → **renumber to 21**): the proven appliance. Backing `vm_app_web` (thin snap
  RO) ← `/var/lib/katmate/instances/test_web.qcow2`. `/home` =
  `vm_app_web_home` (10G ext4 raw LV, `/home/user` owned 1000:1000). init +
  Rust vm-agent + user 1000 baked in.
- **app_vault** (build-only): `vm_app_vault` thin snap RO of `vm_tpl_foundation`,
  built via `make app-vault` (2026-06-29; keepassxc/foot/nautilus). NOT yet
  instantiated — no qcow2 delta, no home LV, no CID (will be allocated from 20+),
  never booted. keepassxc
  still off the vm-agent RUN whitelist (Faza 4 blocker).
- **Disk chain**: three-level LVM-thin chain proven live through a full
  boot/render/shutdown cycle.

## Open problems

1. **Desktop migration Acer → MINIS** — CYBRland Hyprland config + Plymouth
   theme to port; greetd swap.
2. **hyprlock-after-suspend (host)** — recurring: after host suspend, tty1
   Hyprland locks and will not unlock. Host DE issue, not Katmate, but it blocks
   visual inspection of guest render. Needs its own pass.
3. **Installer secrets** (v0.2 blocker): WireGuard key, WiFi PSK, credentials
   removed before release; rotate burned WG key. SECURITY-MODEL gap #1.
4. **SSH open on MINIS host** — dev convenience. Fix identified
   (`iif <uplink> ip saddr 10.3.1.0/24`), not applied. SECURITY-MODEL gap #4.
   NOTE: `enp1s0` no longer exists on the host now that RTL8125 is in vfio; the
   host uplink is the USB-NIC **`enp195s0f3u1u1`**, so the nft rule should
   target that (LAN-only). Additional caveat now that MINIS is on ProtonVPN:
   ensure sshd listens on the LAN address `10.3.1.3` only, not on the VPN
   interface — either `ListenAddress 10.3.1.3` or the nft `iif` restriction, so
   SSH is not exposed through the tunnel.
5. **ext4 lazy-init warning on vda** — `EXT4-fs error (vda) ... bad block
   bitmap checksum` from `ext4lazyinit` during boot. Cosmetic on a disposable
   delta, but suggests `vm_app_web` may want a clean `e2fsck`.
6. **RESOLVED 2026-07-09 — netVM pet-drift.** `build/netvm.sh` + netVM manifest
   (ADR-021) now build the sysVM declaratively, and the image was PROVEN to boot
   and reproduce the uplink (DHCP `10.3.1.110`, firmware, MAC-matched networkd)
   from the manifest alone — no hand-applied deltas. The netinst pet is retired
   in principle (kept only until `netvm-agent` provides a control path). Residual
   work is NOT the pet: (a) `netvm-agent` for a way into the guest, (b)
   in-guest verification of WireGuard + inner segment, (c) DNS-leak policy in the
   manifest. Kept as a closed marker so the number is not reused.
7. **RESOLVED 2026-07-06 — USB-NIC (r8152, `0bda:8153`) host recovery.** (See
   SESSIONS.md + invariants.) Kept as a closed marker so the number is not
   reused.
8. **VPN key co-located with the NIC driver (v1, accepted).** In the shipped v1
   graph the WireGuard private key and the `r8169` driver + non-free Realtek
   firmware blob live in one address space — compromise of the most exposed code
   in the system is compromise of the VPN credentials. ADR-022 already permits the
   fix (driver domain q35 = hardware, no secrets; proxy netVM microvm = secrets,
   no hardware); it is deliberately post-v1. SECURITY-MODEL gap #7.
9. **IOMMU-group quality is unverified at install time.** A driver domain assumes
   the NIC is cleanly isolable; a bad grouping silently weakens passthrough
   isolation. On MINIS group 12 is clean, but that is luck, not a guarantee for a
   product installed on unknown hardware. Needs an HCL + an installer preflight
   check. SECURITY-MODEL gap #9.

10. **RESOLVED 2026-07-18 (ADR-024) — netVM graceful shutdown.** The QMP
   `system_powerdown` path was inert (logind needs dbus, which the manifest
   deliberately omits — ADR-021's own exclusion). Rather than ship dbus into the
   most-exposed VM, SHUTDOWN returned to `netvm-agent` as opcode 0x05: the agent
   signals PID 1 (systemd) with `SIGRTMIN+4` under `CAP_KILL`, giving the same
   clean stop as `systemctl poweroff` with no dbus/logind/acpid/`CAP_SYS_BOOT`.
   Live-gated: `ping-client shutdown 3 → OK` + full graceful poweroff
   (`EXT4-fs (vda): re-mounted … ro`). See ADR-024 (E1-E8 evidence table). Kept
   as a closed marker so the number is not reused.

## Next steps

**Primary (netVM sysVM — ADR-021 track, build now PROVEN):**

- **NETCFG payload — the next handler (ADR-023 impl).** `handle_netcfg` is the
  ONLY ERR-stub left in netvm-agent; it gates the AppVM internal /32 network
  (every AppVM launch needs a route installed). ADR-023 is written; open are the
  **payload shape** (typed p2p-link: match / local+peer / `/32` / route / metric,
  `add`/`remove` only, validation against a legitimate appVM CID) and the
  **in-guest mechanism** (networkd fragment default; `rtnetlink` alternative).
  Thinking-on session. **Tooling gap first:** `ping-client` has no `netcfg`
  subcommand (opcode 0x06 postdates it) — the live test needs the client
  extended once the payload shape is fixed.

- **`netvm-agent` — PING + SHUTDOWN DONE + LIVE-GATED.** PING gated 2026-07-17;
  SHUTDOWN gated 2026-07-18 (ADR-024): `ping-client shutdown 3 → OK` + clean
  poweroff via `kill(1, SIGRTMIN+4)` under `CAP_KILL`. Deterministic bake solved
  too — the image is now a full `netvm.sh` rebuild (fresh binary + `CAP_KILL`
  unit), not a hand-bake. Opcode model is **PING + NETCFG + SHUTDOWN**; RUN /
  FILEGET / FILEPUT stay absent (boundary test in op.rs). The ONE remaining
  handler on this track is NETCFG — see Primary below.
- **In-guest verification via a dev-only console password** (out-of-band; remove
  before release, sshd class): `networkctl status` routable, WireGuard/ProtonVPN
  up, inner-segment `enp0s4` p2p to personalVM. Only link-up + DHCP lease
  confirmed so far (from the host). The agent is NOT the verification path (no
  RUN).
- **DNS-leak policy in the manifest** — the uplink DHCP offers `DNS=1.1.1.1`
  (LAN router). netVM must push DNS through ProtonVPN (`10.2.0.1`). Decide:
  override with `DNS=10.2.0.1` + `Domains=~.` in `20-uplink.network`, or drop
  the uplink DNS entirely. Security-relevant; fold into the manifest.
- **WireGuard key provisioning automation** (ADR-021 open item) — keys are
  deploy-time (placeholders in the image, per image/state separation). Needs a
  provisioning step; do NOT bake keys.
- **Harden `netvm.sh` cleanup** — `umount -R` + `sync` + `udevadm settle` +
  `sleep` before return, so a successful build does not leave a hot jbd2 forcing
  a reboot (bit twice this session).

- **Docs hygiene (deferred) — reconcile the state.md session section.** It
  holds 07-14 + 07-13 while SESSIONS.md already has 07-18/07-17/07-15/07-10; the
  two do not overlap and the dates are inverted vs the "two most recent" mandate.
  07-13 is NOT yet in SESSIONS (would be lost if naively dropped). Sanitize
  deliberately: copy 07-14 + 07-13 into SESSIONS (newest-first), then trim
  state.md to the two most recent. Not done this session (minimal-move choice).

**Carried from 2026-07-14 (ADR-022/023 consequences):**

- **CID renumbering** — apply the new map: personalVM `4 → 20`, app_web `5 → 21`.
  Touches the `.con` launchers, `katmate-cid`, and any hardcoded CID. netVM (3)
  is unaffected. Do this BEFORE the AppVM domain model lands, not after.
- **ADR-016 revision** — the two-profile DE model becomes single-profile: **Sway
  ships alone** (the host compositor is in the TCB — it draws the domain
  indicator). Hyprland/CYBRland stays a dev/demo profile until its indicator
  implementation is separately verified. The DE profile *contract* (waypipe
  client per domain · host-side domain-identity hook keyed on **waypipe CID**,
  never on spoofable `app_id`/title · bar module reading launch-daemon state ·
  keybindings → katmate CLI) is now documented in ARCHITECTURE.md.
- **Launch daemon owns the graph** (ADR pending) — allocates CIDs and `/32`s,
  creates/destroys `Link`s, calls NETCFG along the path, refuses to tear down a
  `provides_network` VM with live dependents. This is where `netvm`/
  `provides_network` become real.
- **HCL + installer IOMMU preflight** — a driver domain is only safe where the
  NIC sits in a cleanly isolable IOMMU group. Product requirement, not a v1 code
  blocker (SECURITY-MODEL gap #9).

**Secondary / carried:**

- **ARCHITECTURE.md diagram set** — storage chain, VSOCK ports, CID domains,
  boot chain, trust boundary. (Foundation-migration rewrite already written up
  as ADR-018.)
- **Disposable-VM launch model** decision: unblocks `katmate-cid` `_is_alive` +
  reconcile (CID ≥100 dynamic pool).
- **Launch daemon / privilege split:** fold the launcher's `lvchange -K -ay`
  activation into a proper unit (`ExecStartPre=+` as root, QEMU as `host`);
  shared `katmate-foundation.service` oneshot. NOTE: the netVM `memlock`
  drop-in + `vfio` group model are the template for how the launch daemon must
  grant memlock + vfio access to a non-root QEMU.
- **Migrate live AppVMs** (personal) off the old systemd-user / linear-root
  model onto the init+foundation chain. (netVM is NOT migrated — it is a sysVM,
  stays systemd.)
- **systemd purge from foundation** (minimal-TCB): the binary still ships unused.
- **udisks2 check:** confirm nautilus works with udisks2 disabled, then bake
  `systemctl disable udisks2` into the app-layer build.
- **FILEPUT streaming** — still buffers the whole payload in memory
  (`read_request` fills `RawRequest::payload`); the streaming helpers
  (`write_response_header`/`write_raw`/`read_raw`) exist in `frame.rs` but
  FILEPUT does not use them. FILEGET already streams.
- **ISO bake pipeline** (ADR-020): download → verify → bake USB → boot →
  provision. Not yet designed; terminal step of the developer pipeline.
- **Installer:** secrets removal (v0.2 blocker); create `/var/lib/katmate/`.
  PROVISIONING only — no build logic, no toolchain.
- **Desktop:** port CYBRland + Plymouth from Acer to MINIS.
- **Host uplink persistence** (dev-only, low priority): USB-NIC
  `enp195s0f3u1u1` / `10.3.1.3` is volatile (`ip addr`). If it should survive a
  reboot, add a persistent profile matched on MAC (`00:e0:4c:39:61:b8`), not the
  USB-path name.
- **sshd exposure with ProtonVPN active** (ties into #4): bind sshd to
  `10.3.1.3` / restrict nft so SSH is not reachable over the VPN tunnel.

## Invariants & gotchas (quick reminders — detail in git/ADRs)

- **netVM initrd needs `MODULES=most`, NOT `dep`.** `netvm.sh` builds in a chroot
  on a mounted LV (root = ext4-on-dm), but the guest BOOTS as a virtio device
  (root = `/dev/vda` on virtio-blk). `MODULES=dep` resolves modules against the
  BUILD root and omits `virtio_blk`/`virtio_pci` → guest drops to an initramfs
  shell with `ALERT! /dev/vda does not exist` (the virtio-pci transport is
  present and enumerates the device as `virtio2`, but with no `virtio_blk` there
  is no `/dev/vda` node). `most` includes the full virtio + storage set
  regardless of build context (initrd ~11MB → ~36MB). This is the general trap
  for ANY image built in a context whose root differs from its runtime root.
  (Proven 2026-07-09.)
- **Seed image config files with `install -D`, not `printf >`/`cat >`.** On a
  fresh debootstrap the target dir often does not exist yet (e.g.
  `/etc/initramfs-tools/conf.d/`); a bare redirect fails with "No such file or
  directory" and aborts the build mid-write (→ stuck jbd2 → reboot). `install -D`
  creates parent dir + mode + content atomically. Always `bash -n` a build
  script after editing — a stray deleted `)` will only surface at runtime
  otherwise.
- **Mask suspend before a netVM build.** hypridle/logind can put the build host
  to sleep mid-build (twice on 2026-07-09), killing the build and leaving a stuck
  jbd2 (→ reboot). `systemctl mask sleep.target suspend.target hibernate.target
  hybrid-sleep.target` is a hard, reboot-surviving block; UNMASK when done.
  Disabling hypridle alone is NOT enough (it can be re-launched).
- **netVM `netvm.sh` cleanup can leave a hot jbd2 even on a SUCCESSFUL build.**
  Symptom: build finishes (`netVM image built`), yet `Open count: 1` + live
  `jbd2/dm-<n>` while `mount`/`lsof`/`fuser` are all clean — the umount returned
  before jbd2 committed. Until cleanup is hardened (`umount -R`+`sync`+`settle`+
  `sleep`), a reboot clears it before the boot-test. Do NOT force `lvremove`;
  reboot.
- **netVM declarative image locks root — no console login.** `netvm.sh` locks the
  root account ("dev sets a console password out-of-band"); a `localhost login:`
  attempt fails. This is intended (control goes via `netvm-agent`/VSOCK, not the
  console). Until the agent exists, verify the guest FROM THE HOST (ARP scan for
  the uplink MAC, LAN reachability), not by logging in.
- **netVM uplink verifies by ARP scan, not ping.** netVM nftables drops inbound
  ICMP, so `ping <lease>` from the host stays silent even when the uplink is up.
  `nmap -sn 10.3.1.0/24` (ARP at L2) shows the guest by its uplink MAC
  (`38:05:25:34:7c:47`) + DHCP lease. Silent ping is correct posture, not a fault.
- **netVM build mirror: pick by VPN exit, not by home geography.** MINIS's
  ProtonVPN exit is in CH; use `DEBIAN_MIRROR=http://ftp.ch.debian.org/debian`
  (via `sudo bash -c 'DEBIAN_MIRROR=... bash netvm.sh'` — `sudo` env_reset drops
  a bare `VAR=... sudo` prefix). An SI mirror over a CH tunnel is worse, and the
  Ljubljana `deb.debian.org` fastly timeout does not apply from a CH exit.

- **netVM needs `firmware-realtek` for the passed-through RTL8125.** vfio hands
  the card to the guest as a plain PCI device; the guest's own `r8169` needs
  `rtl_nic/rtl8125b-2.fw` or the PHY stays down (`Unable to load firmware ...
  (-2)`, then `no-carrier`). `non-free-firmware` is already in the netVM
  `sources.list`. This MUST be in the netVM manifest (`build/netvm.sh`), or a
  rebuild loses the uplink. (The old USB-NIC r8152 did not need a separate blob,
  which is why the netinst image never had it.)
- **netVM `enp0s6` netconf is MAC-matched, not name-matched.**
  `/etc/systemd/network/20-uplink.network` matches `MACAddress=38:05:25:34:7c:47`
  (the RTL8125 as seen in the guest), DHCP, `RouteMetric=100`. MAC match is
  deliberate so a PCI slot / interface-name change does not break it. The
  internal p2p segment `10-personal.network` stays `Name=enp0s4`-matched.
- **A netinst netVM writes stale installer configs.** The recurring first-boot
  `[FAILED] Raise network interfaces` came from a leftover static block for the
  HOST's USB-NIC MAC (`enx00e04c3961b8`) in `/etc/network/interfaces`, written
  by the original netinst installer. General lesson: the hand-installed netVM
  drifts; do not trust its configs — this is why it must become a declarative
  build (ADR-021).
- **Thin-LV activation:** an RO-frozen thin LV keeps the skip-activation `k`
  flag permanently; `lvchange -K -ay <lv>` is mandatory before every instance
  boot, on both the app-layer AND the foundation, or QEMU fails with "Could not
  open backing image". The `app_web.con` launcher does this in pre-flight.
- **vfio passthrough — memlock (RTL8125):** VFIO pins the ENTIRE guest RAM
  regardless of `-overcommit mem-lock=off` or hugepages. A manual
  `bash net-vfio.con` inherits the SHELL's `ulimit -l` (default 8192 KB) → QEMU
  dies with "cannot allocate memory" at `VFIO_MAP_DMA`, NOT a real OOM. Fixes:
  either `ulimit -l unlimited` in the shell before a manual launch, OR launch
  via `netVM.service` (which carries `LimitMEMLOCK=infinity` via the
  `netVM.service.d/memlock.conf` drop-in). The unit path is the production one;
  the manual `ulimit` is a dev-only workaround. A plain user cannot raise
  `ulimit -l` above the hard cap — but here the user manager did not cap it, so
  the drop-in alone sufficed (no `/etc/security/limits.d/` needed).
- **vfio passthrough — FLReset- (RTL8125):** the RTL8125 reports `FLReset-` (no
  function-level reset) with small BARs (~80K, so NOT a large-BAR/memory-hole
  problem — that earlier diagnosis was a myth). Without a workaround, vfio's
  reset on teardown leaves the device half-initialised and the NEXT
  `VFIO_MAP_DMA` returns ENOMEM (this was the real Feb/Mar "out of memory").
  Workaround baked into `/etc/modprobe.d/vfio.conf`:
  `options vfio-pci ids=10ec:8125 disable_idle_d3=1` + `softdep r8169 pre:
  vfio-pci`. **Both first AND second boot now PROVEN (2026-07-08)** — the reset
  workaround holds across a guest reboot cycle.
- **vfio device node permission:** `/dev/vfio/<group>` is root-only by default;
  QEMU as user `host` gets `permission denied`. Production fix = `vfio` group +
  udev rule (`SUBSYSTEM=="vfio", GROUP="vfio", MODE="0660"`) + user in the
  group (login-scoped). This is the template for the future launch daemon's
  non-root QEMU.
- **USB-NIC (r8152) is DEV-ONLY churn, not a product concern.** The whole
  "device did not come back" class exists only because the dev workflow shuffles
  one NIC between host and netVM live. In production devices do not migrate —
  each VM has a fixed declarative assignment — so this class vanishes. Universal
  NIC passthrough is a build/provision-time job (read IOMMU groups, resolve BDF,
  generate vfio bind once), NOT per-boot runtime recovery.
- **`driver=[none]` AFTER a clean enumeration → check `/etc/udev/rules.d/`
  FIRST, not the kernel.** This is the #7 lesson, learned the hard way. When a
  USB device enumerates fine (strings, product, serial all read) and then ends
  up with no driver on every port and every bus, the cause is almost always a
  userspace `unbind`/`driver_override`/vfio claim, not a missing or broken
  kernel driver. The actual culprit was our own
  `30-usb-nic-qemu.rules` running `r8152/unbind` on plug. Grep
  `udev/rules.d` + `modprobe.d` for the VID/PID before touching kernel config.
- **`r8152-cfgselector` is NOT a separable module and NOT the enemy.** It is
  built into `r8152.ko` (registers two drivers from one module: the cfgselector
  interposer for the USB *device*, `r8152` for the *interface*). It cannot be
  blacklisted, and on the working Cubi it is present in the chain too
  (`2-3` → cfgselector, `2-3:1.0` → r8152). Any note about "blacklist the
  cfgselector" (a prior #7 hypothesis) is void.
- **Do NOT blacklist `cdc_ether`/`r8153_ecm` for the RTL8153 USB-NIC.** Removing
  them has no effect on the bind path and only removes the ECM fallback. An
  earlier session blacklisted them; removed.
- **USB fallback NIC: prefer a native port, avoid a USB4/TB hub.** On the TB hub
  the RTL8153 throws `error -71` (EPROTO) on SuperSpeed setup-address. On MINIS
  the device is happiest on a rear/native SuperSpeed port (bus 002, 5000M); the
  front panel and the VIA USB2.0 hub path drop it to 480M. (This mattered less
  than we thought — the real bug was the udev rule — but the topology note holds.)
- **The running kernel on MINIS is Arch stock `7.0.12-arch1-1`, NOT a 6.12.y
  microvm kernel.** `~/src/kernel/linux-6.12.y/` (and any 6.12.94 tree) is the
  GUEST microvm kernel source, unrelated to the host. Do not build host modules
  against it (vermagic mismatch) and do not reason about host USB/driver
  behaviour from 6.12.y. The custom `6.12.87`/`6.12.94` kernels are `-kernel`
  payloads for guests only.
- **Root device has no partition table:** debootstrap is directly on the LV, so
  `root=/dev/vda` (NOT `vda1`).
- **Serial console:** microvm + `-nographic` does NOT auto-wire the serial
  console (changed ~QEMU 10.x). Must add `-serial mon:stdio` explicitly.
- **Shutdown without ACPI:** init calls `reboot(RB_AUTOBOOT)` (NOT
  `RB_POWER_OFF`). Requires host-side `-no-reboot` + kernel cmdline `reboot=t`.
- **Agent PATH:** init launches vm-agent with `PATH=/usr/local/bin:/usr/bin:/bin`
  — waypipe is the source-built `/usr/local/bin/waypipe`, not apt.
- **GUI launch:** GTK apps refuse to run as root; require user 1000 with
  `XDG_RUNTIME_DIR`. waypipe ≥0.11 self-resolves the host CID (no `2:` prefix).
- **VSOCK ports:** 1025 = vm-agent control, 1024 = waypipe GUI, 1026 = audio
  (planned).
- **CID map is now range-based (ADR-022), because there can be more than one
  sysVM.** `2` host · `3–19` sysVM · `20–99` fixed AppVM · `≥100` disposable.
  The old flat scheme (3 = netVM, 4–8 = fixed AppVM) assumed a single sysVM and
  cannot hold a chained topology (`appVM → netvm-vpn → netvm-driver → NIC`).
  Anything reading a CID — launcher, launch daemon, domain indicator — reads this
  map. Numbers in SESSIONS.md are pre-ADR-022 and are not rewritten.
- **`amd_iommu=on` is a DEAD cmdline param** (kernel prints `AMD-Vi: Unknown
  option` and ignores it). IOMMU actually runs via `iommu=pt` + IVHD/IVRS. The
  MINIS cmdline still carries the dead `amd_iommu=on`; harmless, clean up
  someday. IOMMU group 12 (RTL8125) is clean/isolated — passthrough-safe.
- **`foundation.meta` (ADR-019):** host-side source of truth at
  `/var/lib/katmate/foundation.meta`, flat `KEY=value`. Read without
  booting/mounting. Launch preflight compares host `waypipe --version` (bare
  `x.y.z`) against `WAYPIPE_TAG` and refuses to start on mismatch. config.sh
  variable is `WAYPIPE_VERSION`; meta KEY is `WAYPIPE_TAG` — same value, two
  names.
- **Re-bake invalidates deltas:** recreate with `qemu-img create -f qcow2 -F raw
  -b /dev/vg0/vm_app_web <delta> 10G`. Fails with "write lock" if a QEMU still
  holds the delta (kill the old VM first; do NOT kill netVM/CID-3).
- **Custom microvm kernel** is monolithic, passed via `-kernel` (no initrd, no
  `/lib/modules`); delivered as an external vmlinuz (NOT a `.deb`).
- **Never rsync a kernel *build* tree with broad `--exclude` patterns.**
  `--exclude='vmlinux.*'` matches the SOURCE `vmlinux.lds.S` too. Use `git
  clone`/`git archive` + copy only `.config`. Interrupted builds leave truncated
  `.o` files that pass make's timestamp check but fail at link.
- **Kernel build host is MINIS (Ryzen), not Acer** (N4200 thermally shuts down
  under a full build in summer). `-j16` on MINIS. Source at
  `~/src/kernel/linux-6.12.y/` on both; Acer is reference, MINIS is build copy.
- **foundation build gotchas:** (a) pseudo-fs mount AFTER debootstrap; (b) ext4
  label ≤16 chars (`katmate-found`); (c) no `useradd`/`passwd` in minbase —
  write the user directly; (d) `$(HOME)` under `sudo` is `/root`, so
  `KERNEL_SRC_DIR` hardcoded to `/home/host/katmate-kernels`.
- **Abstract vs concrete naming:** ADRs use `foundation`/`app`/`instance`;
  concrete LVM names (`vm_tpl_foundation`, `vm_app_web`) only here and in live
  inspection.
- **Source of truth = Acer `~/katmate-os/` git repo.** MINIS
  `~/katmate-build/katmate-os/` is a build copy — synced FROM the repo, never
  edited on MINIS and left to diverge. Git lives ONLY on Acer. The rsync runs
  WITHOUT `--delete`, so a restructuring that REMOVES files needs a manual `rm`
  on MINIS first, or stale files linger (bit us at the workspace split: leftover
  `agent/src/` beside the new `agent/crates/`).
- **`git rm`, never `rm`, when restructuring a tracked tree.** `git rm -r <path>`
  removes from index AND worktree, but the content stays safely in `HEAD`; a bare
  `rm -rf` has bitten this project before. Corollary: check `git ls-files`, not
  `find`, to see what is actually TRACKED. During the workspace split the skeleton
  `agent/crates/` turned out to be already committed, so the naive
  `git rm -r agent` would have destroyed it — `git ls-files agent` caught that
  before any damage.
- **Two-stage gate for a refactor: OLD artefact first, new artefact second.**
  Testing the new client against the OLD guest image proves the wire is intact,
  and nothing else. Testing against a NEW image proves the new agent works. The
  second does not subsume the first: if only the second is run and it fails, you
  cannot tell whether the codec, the dispatch, or the build broke. The first test
  costs seconds and buys that separation. (Workspace split, 2026-07-13.)
