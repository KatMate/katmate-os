# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Milestone:** v0.2 (in development) · **Last updated:** 2026-08-06
(two sessions: documentation hygiene, then ADR-030). Both closed 2026-08-09.

## Current focus

**The focus is the host side of the TCB — specifically the launch daemon.**
Everything below the daemon is proven: the RTL8125 passthrough backbone holds
across reboot cycles, `build/netvm.sh` reproduces the uplink declaratively
(proven 2026-07-09, netinst pet retired in principle), and `netvm-agent` is
live-gated through PING, NETCFG and SHUTDOWN — the control path into the guest,
open for most of July, is closed (ADR-024, ADR-025).

The **entire build chain remains scripted and proven from nothing**:
`make foundation` builds the shared systemd-free base
(debootstrap → base → waypipe-from-source → bake init/agent/user → freeze),
`make app-web`/`make app-vault` snapshot it, and an instance boots end-to-end.
The release model is fixed (ADR-020): the build chain is developer-side; its
output is a signed ISO; the user installs by verify → bake → boot → provision,
never by building. `katmate-update` (ADR-019 version-lock backbone) is complete
— and deliberately does NOT cover netVM (ADR-021).

What is open is the **VMM process itself**: ADR-027 defines a containment
gate (C-gate) of which C4 (tightened seccomp) and C5b (no host filesystem export into netVM)
passed on 2026-07-28, leaving C1–C3, C5a and C6 attached to the launch daemon.
ADR-028 settles that v1 stays on kernel `vhost_vsock` and records what would
have to be true before that changes. ADR-026 closes the domain indicator's
identity question, which unblocks the Sway indicator work. The next code to
write is the launch daemon. **ADR-029 (2026-08-02) settles its supervision
model: systemd owns the VMM process; the daemon orders units and holds no
process relationship to any QEMU.** The privilege split is therefore unit
configuration (C1, C3, C5a) rather than daemon code, and the daemon becomes
restartable — and so updatable — without touching running VMs.

Direction unchanged: IOMMU-capable platforms only (VT-d/AMD-Vi); VT-x-only
frozen (ADR-015). MINIS is primary host and merge target.

## This session (2026-08-06, second of two) — ADR-030: authorship is the tier boundary; the build order gains the step it was missing

Architecture session (thinking-on), the second of the day — the documentation
hygiene pass below cleared the ADR numbering collision that would otherwise have
blocked it. One ADR written, one superseded in part, one build-order step
created, four findings routed elsewhere. Gate E1 was measured the same day
(below).

The renumbering this ADR introduced (old 3/4/5 → 4/5/6) invalidated **six
build-order ordinals** across `DECISIONS.md`, `ROADMAP.md`, `HOST-CONFIG.md`
and this file. All six repaired here, in the session that created them; a
reference by number that still resolves, just not to what it meant, is the
project's characteristic failure class expressed in documentation.

### The reframing that made the ADR small

The session was scoped as "extend ADR-015's schema with the fields the `.con`
scripts carry". Two readings against ADR-022 changed the shape before any field
work started.

**ADR-030 does not invent an object.** ADR-022 already defines `Vm`, `Image`,
`Nic`, `Link` and `Policy`. The subject is the *on-disk serialisation* of those
objects such that an ADR-029 unit can be produced from it. `properties.toml` is
a partial, AppVM-only serialisation of `Vm` that predates the model.

**ADR-015's `network` field is wrong in type.** The enum `none | via-netvm`
cannot name *which* netVM, and under ADR-022 an AppVM's access *is* which netVM
it attaches to. ADR-022 displaced the field when it was accepted and nobody
recorded it. This is the third time a supersession has been found by reading
rather than by being written down (CID band, ADR-021's shutdown pointer, this).

### The decision, in one line

**The tier boundary is authorship, not content.** The question is not which
fields the schema needs but **which fields may be data at all** — because
`-sandbox …,resourcecontrol=deny` (C4, live-gated 2026-07-28) is a `.con` line,
and a schema field is a thing a user can edit.

Four artefacts, one per writer:

| Tier | Author | Where |
|---|---|---|
| T1 instance properties | user | `properties.toml` |
| T2 image metadata | build pipeline | `<image>.meta` (`foundation.meta` pattern) |
| T3+T4 profile + TCB constants | the release | **the unit template** |
| — | derived at start | `/run/katmate/vm/<i>.env`, a projection |

The unit template *is* the serialisation of T3/T4 — no separate profile format,
because it would be a second record of one fact and PID 1 does not read it. The
profile goes in the **unit name** (`katmate-app-routed@personal.service`), so
ADR-029's durable identity carries its own containment profile. And the profile
is a **function** of `(class, netvm, nic)`, not a field: the user declares
topology, containment follows, and no user can select a weaker profile. That is
the only reason T3 may be derived from T1 at all.

`sys-proxy` (ADR-022's chained proxy netVM) is named by the function and
returns an explicit error. Shipping an untested template for a VM class that
has never been built would invert the method.

### What crosses the daemon→unit boundary

**Named kernel objects, two typed scalars, no free argv.** The ADR-029
argument — *names that outlive whoever created them* — applied one layer down.
netns by `NetworkNamespacePath=`, tap by derived name owned by the per-VM uid,
MAC derived and never byte-encoding an address (the pet launcher's MAC
preserved a wrong-subnet bug). Only `KM_CID` and `KM_VFIO_BDF` cross, as
`${}`-braced interpolations at fixed positions — braces because `${}` does not
word-split, so a value cannot become extra arguments.

An argv blob was rejected on the ground that whoever writes it can inject a
second `-drive` or a later `-sandbox`, making all of T4 optional.

### `Nic`: a BDF is not an identity

Firmware assigns it; a reseat or an added NVMe moves it. The failure is not a
VM that will not start — `vfio-pci` binds to an **address**, so a stale record
detaches *some other* device and hands it to the most exposed VM, silently,
with a plausible result.

So the `Vm` carries a **label** (`nic = "uplink0"`), the boot-time binding step
publishes `/run/katmate/nics/<label>` → current BDF, and VM start checks
`vendor`/`device` at the resolved address. What the kernel publishes is not
copied into a file.

**Fourth instance of the characteristic bug** — a mechanism that quietly
consults the wrong object and returns a believable answer. After ADR-021's
shutdown precondition, `/proc` in the wrong netns, and `Online state: offline`
beside `routable`. It is no longer a pattern worth noting; it is the thing to
look for first.

### No monitor

`-nographic` alone multiplexes console *and* monitor. T4 becomes
`-display none -monitor none -serial <chardev>`, `-nographic` removed from both
launchers. A dev monitor is a drop-in under
`/etc/systemd/system/…@.service.d/`, never a field — Gap #10's precedent, "a
separate dev launcher" — and joins the pre-release removal list.

**Consequence to carry:** with the console in the journal the path is one-way,
and interactive console login disappears. That is the correct end state — open
problem #12 becomes *unreachable* rather than merely fixed — but during 3a
bring-up a pty or a separate dev launcher is needed, and it must not be the
same unit.

### Build order: the step that was invisible

`ROADMAP.md` lists artefacts to *build*. Launching already exists in a
degenerate form, so it never appeared — and for the same reason the schema was
never written: **the `.con` scripts are the schema, expressed as code.** The
missing step is their **removal**.

Neither horn of the dilemma this file posed on 08-02 was right: ADR-029 did not
run ahead of its turn, and the build order was not silently wrong.

New step 3, split; old 3/4/5 renumbered to 4/5/6.

- **3a** description + unit templates; **gate: both `.con` deleted and nothing
  lost** — which is simultaneously the empirical gate on ADR-030's schema. If a
  `.con` line has nowhere to go, the schema is incomplete. ADR-024 method
  applied to a schema: a demonstration instead of a review.
- **3b** the daemon.

### Gate E1 — measured same day, prediction wrong

Whether `EnvironmentFile=` is read late enough to see a file created by
`ExecStartPre=` **in the same unit**. The ADR predicted it probably is not —
the assumed-precondition shape that killed ADR-021's shutdown and ADR-025's
Path A. **Both candidates passed:** A (`ExecStartPre=` in the same unit) →
`[42]`, B (separate generator unit, `Requires=`/`After=`) → `[42]`.

**A selected.** One unit per VM, generator as `ExecStartPre=+`; no second unit
class, no ordering edge, and the projection is produced and consumed inside one
unit's lifetime, so a half-started VM cannot leave a live env file for the next
start to inherit. **B recorded as also working** — available later without a
second measurement.

Not covered by the probe, and therefore not citable: `Type=oneshot` rather than
`notify`/`simple`; `ExecStartPre=` without `+`; one key rather than two.

Cheap to be wrong here rather than in a template. The method held even though
the guess did not — which is the whole point of gating before committing, not
of guessing well.

**Defect in the probe itself, worth the line:** v1 installed `trap cleanup EXIT`
*above* the root check, so a non-root run fired `systemctl stop` on units that
had never been created and produced four polkit prompts while measuring
nothing. A gate that fails open is worse than no gate; it was fixed before the
real run.

### Findings routed, not decided

- **Memory backing is divided the wrong way round.** `app_web` (no vfio) takes
  hugepages, `net-sys` (vfio) takes memfd. The vfio VM is the one that
  benefits. Three axes, none of them performance: DAC on `/dev/hugepages` under
  `User=` vs memfd needing none; whether `share=on` has any consumer at all
  (vhost-vsock is in-kernel, no vhost-user process exists); loud vs silent
  failure on an undersized pool. → `HOST-CONFIG.md` §6, own session, with C3.
- **netVM has neither `-nodefaults` nor `-no-user-config`.** Less containment
  in the most exposed VM than in an AppVM. Closed by construction in 3a
  (gate G4). → C-gate.
- **`-overcommit mem-lock=off` on netVM is probably inert.** vfio pins the whole
  guest regardless; under C1 `LimitMEMLOCK=infinity` becomes a start condition,
  not an optimisation. → folds into the memory session and C3.
- **`/home` is named per app layer, not per instance.** Two instances of
  `app_web` would mount one ext4 rw and corrupt it; it has not happened because
  one instance exists. ADR-030 fixes the **tier** (per instance, derived from
  the instance name); the storage mechanism — thin snapshot of a frozen
  `vm_home_skel` vs qcow2 branch — is ADR-010/011 and deliberately left open.
  Recorded for that session: qcow2 would add a second COW layer to the most
  write-heavy device, grow monotonically with `discard` needing to traverse two
  layers, and create a backing chain whose semantics are the opposite of the
  app-layer chain `katmate-update` rebases.

### Documentation drift found

`state.md` Next steps (08-06) claims `HOST-CONFIG.md:199` was corrected from
ADR-030 to ADR-031. **It was not** — line 199 still reads ADR-030. Corrected in
this session's patch set. A drift note that itself drifted.

## Previous session (2026-08-06, first of two) — documentation hygiene before ADR-030; the archive boundary repaired

Documentation session, no code and no gates. Deliberately placed *before* the
ADR-030 session of the same day: writing an ADR into documentation that carried
a live numbering collision and three unrecoverable session records would have
compounded both.

### The defect: a mandate that had become destructive

This file carried roughly 160 lines of un-headed session narrative *above*
*Current focus* — material that had accumulated in the preamble instead of
being given headings and rotated. Three of those sessions — **2026-07-23,
07-21 and 07-20** — existed in no other file; `SESSIONS.md` jumped straight
from 07-24 to 07-18.

Trimming this file to "the two most recent sessions" would therefore have
deleted three sessions rather than archiving them. The mandate was not wrong;
it had simply stopped being safe to apply, because the invariant it depends on
— *every session has a heading* — had been silently broken for weeks.

### Archive work

- **Three stranded sessions inserted** into `docs/SESSIONS.md` in their
  chronological slot (07-23, 07-21, 07-20). The second such insertion the
  archive has taken; its header now records both.
- **The 2026-08-02 *first of two* session reconstructed** and written up as its
  own entry, explicitly marked as reconstructed rather than same-day. Its
  consequences (CID renumbering applied, personalVM artefacts removed) had been
  threaded into this file's living sections while the session itself was
  invisible. Assembled from those sections and from `ROADMAP.md`; it asserts
  nothing that was not already written down.
- **The 2026-08-02 *second of two* session (ADR-029) rotated normally** as this
  file was trimmed, and therefore sits *above* the reconstructed first — newest
  first, as everywhere in the archive.
- **Duplicates dropped, not moved.** The 07-18 and 07-17 material in the
  preamble duplicated entries already archived.
- **Two repairs inside moved blocks, marked where they occur:** a dangling
  *"see debt #14 below"* cross-reference, now pointing at `../state.md`; and
  removal of the leading `**YYYY-MM-DD …**` date stamps, which only meant
  anything in this file's flat preamble.

### ADR numbering collision resolved

`HOST-CONFIG.md` and this file both claimed **ADR-030** for different subjects.
Resolved by weight of existing reference: `ADR-030` = the launch daemon input
schema (four references); `ADR-031` = the GPL-3.0 licence declaration for the
CYBRland-derived `desktop/` subtree, not yet written. Blocking — the ADR-030
session later that day could not have started against an ambiguous number.

Same rule as for the open-problems list: count the list, never the memory of it.

### Internal contradictions corrected

This file trimmed 1116 → 974 lines, with: `handle_netcfg` still listed as open
work (live-gated 2026-07-23); an outdated netVM live-state block carrying the
wrong kernel version, wrong agent status and wrong interface names; a `tap-int0`
bullet still carrying the prediction the 08-03 session had already refuted; and
two items naming `personalVM` as a live peer, an artefact deleted on 2026-08-02.

Two signed commits, separated by concern.

### One claim this session made and did not deliver

`HOST-CONFIG.md:199` was recorded as corrected from ADR-030 to ADR-031. It was
not — the line still read `ADR-030`. Found and actually corrected in the
ADR-030 session the same evening (see its *Documentation drift found*). A
hygiene pass that itself drifted, inside the one session whose entire subject
was drift.

### The rule this session leaves behind

**A session gets a dated heading at write time, or it is lost.** The project
already held this as an invariant; what it did not hold was the consequence —
that a *trimming* rule and a *heading* rule are one mechanism, and that
applying either alone destroys records. Rotation is now the only sanctioned way
material leaves this file, and rotation requires a heading to rotate.

## Session archive

Sessions older than the two above (2026-08-03, then 2026-08-02 *second of two*,
then *first of two*, then 2026-07-28 back to 2026-06-27) live in
[docs/SESSIONS.md](docs/SESSIONS.md), split out on
2026-07-14. That file is append-only; CIDs in entries dated 2026-07-13 and
earlier are the pre-ADR-022 numbering and are deliberately not rewritten.
**This file carries the authoritative CID map** (see *Live state*).

**The boundary was repaired 2026-08-06**, written up as the *first of two*
entry above. What belongs here is the rule it left behind: **rotation is the
only way material leaves this file, and rotation requires a heading to rotate.**
A session without a dated heading cannot be archived, and the trim that would
otherwise remove it destroys it instead. The two rules — keep two sessions,
give every session a heading — are one mechanism.

**Closed 2026-08-09.** The 2026-08-06 hygiene session received the entry it had
never been given; the 2026-08-03 entry rotated to the archive in the same pass.
The *Pending* note that stood here is retired, including its stale prediction
that the 2026-08-02 *second of two* entry had yet to move — it had already
rotated on 2026-08-06.

**Ordering note.** Both 2026-08-06 entries are same-day. *First of two* is the
hygiene pass (midday); *second of two* is ADR-030 (evening). The hygiene pass
was a precondition for the ADR, not cleanup after it — its own working title
was *"pred ADR-030"*.

## Live state (MINIS/UM870) — summary

**CID map (authoritative, ADR-022).** `2` = host · `3–19` = sysVMs (3 = primary
netVM) · `20–99` = fixed persistent AppVMs · `≥100` = dynamic disposable pool.
The renumbering was **applied 2026-08-02**: `app_web` 5 → **21** in
`app_web.con`, and the normative band 4–8 → 20–99 in ADR-015 / ADR-017 /
`tools/validate-properties.fish`. personalVM was **not** renumbered — it was
deleted instead (see below), so 20 is now simply the lowest free fixed AppVM
CID, reserved for nothing in particular. netVM (3) is unchanged by the new map.
No instantiated `properties.toml` existed at the time, so no instance file was
touched.

- **MINIS `~/` housekeeping, 2026-07-25.** Removed the pre-sysVM launcher set
  (`net.con`, `net_dev.con`, `net-vfio.con`, `personal*.con`, `work.con`,
  `new_qemu-kvm.con`), the dead `~/.config/systemd/user/netVM.service`, the
  orphaned `vm_personal_overlay.qcow2` / `vm_work_overlay.qcow2`, and the
  pre-sysVM LVs (`vm_tpl_all_root`, `vm_tpl_all_root_golden`, `vm_tpl_debian`,
  `vm_tpl_work_root`, `vm_tpl_personal_root`, `vm_work_home`) — ~131 G
  reclaimed. Kept at the time: `vm_personal_home` (40 G thin) and
  `vm_app_vault` (frozen app-layer, `Data%` empty). `~/net-sys.con` is now
  a symlink into `~/katmate-build/`, so rsync updates the live launcher and
  that duplicate cannot drift again.

- **personalVM artefacts removed, 2026-08-02.** `vm_personal_home` (40 G thin)
  deleted; the launcher and overlay had already gone in the 2026-07-25 pass.
  The old personalVM ran the **pre-foundation** systemd-user / linear-root
  model, which nothing will boot again — migrating it would have meant
  renumbering and then rebuilding an artefact that the v0.3 AppVM work
  regenerates from foundation + `web` manifest anyway. **The artefact is gone;
  the `personal` archetype (ADR-014) is not.** It returns as one of the four
  default AppVMs, with a CID allocated from 20–99 at that point.

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
  **6.12.96+deb13-amd64**, rebuilt clean on 2026-07-23). Boots through full
  systemd, root on `/dev/vda`; the uplink comes up MAC-matched
  (`38:05:25:34:7c:47`, `Link is Up 1Gbps/Full`, `firmware-realtek` loaded,
  DHCP lease `10.3.1.110` confirmed by host ARP scan) and the internal p2p
  segment on its locally-administered MAC `52:54:0a:64:01:01`. **Interface
  names are not normative and have moved across sessions** (`enp0s6` on the
  retired pet, `enp0s4`/`enp0s5` on the declarative build) — read the MACs, not
  the names (see *Invariants*). The uplink deltas (`firmware-realtek`,
  `20-uplink.network`, cleaned `interfaces`) are baked by the manifest, not
  hand-applied.
  **In-guest status:** `netvm-agent` is live-gated on PING / NETCFG / SHUTDOWN
  (ADR-024, ADR-025), so the control path is no longer the gap; root is
  deliberately unlocked for console observation (open problems #11/#12). Still
  unverified from inside: **WireGuard/ProtonVPN bring-up** and the DNS-leak
  policy. The peer end of the internal segment does not exist — personalVM was
  deleted and no AppVM carries a network device yet (ADR-029 C2).
  `memlock` via `LimitMEMLOCK=infinity` (unit) or `ulimit -l
  unlimited` (manual launch). Runs independently of app_web.
- **personalVM** — **gone (2026-08-02).** Launcher, overlay and
  `vm_personal_home` all removed; it was the last pre-foundation artefact.
  Returns as a domain, not as this VM.
- **app_web** (CID **21**, renumbered from 5 on 2026-08-02): the proven
  appliance. Backing `vm_app_web` (thin snap
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

1. ~~**Desktop migration Acer → MINIS**~~ — **Resolved (2026-07-27):** Sway
   profile deployed to MINIS, greetd session picker live and verified. Plymouth
   theme was already done (ADR-004/006).
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

11. **Dev-root open (2026-07-23).** `vm_sys_netvm` carries a dev console
      password for NETCFG observation — the agent has no RUN and NETCFG replies
      OK/ERR only, so the console is the only route to `journalctl`. This now
      lives **in `netvm.sh` and in git** rather than as a hand-applied chroot
      step outside the source of truth (an improvement over 07-21): it is removed
      in one place. The image is NOT release-clean; do not ship it.

12. **The `usermod -p` line in `netvm.sh` is the debt — not its hash.**
   Earlier wording framed this as "the hash is invalid" and proposed
   substituting a real one. That measures the wrong thing: the release problem
   is that step 6 locks root (`passwd -l root`) and then immediately unlocks it
   again, so the line's *existence* is the debt, not its correctness. It is
   there deliberately — `netvm-agent` has no RUN and NETCFG replies OK/ERR
   only, so the serial console is the sole route to in-guest observation
   (ADR-025 live gate; see #11). Removed together with the dev sshd (#4) and
   the installer secrets (#3), not "fixed" by a valid hash. Practical note
   while it stands: the baked hash matches no password, so a rebuild still
   needs `mount` + `chroot chpasswd` to make the console usable.
   **Operational cost demonstrated 2026-07-28.** During the ADR-027 C5b gate the
   in-guest confirmation (`mount | grep 9p`) could not be run at all: the baked
   hash matches no password, so the console was unusable. The only alternative
   would have been to unlock root on a declaratively built LV — reintroducing
   exactly the pet-drift that #6 closed. The gate was satisfied host-side
   instead, which turned out to be the *stronger* proof (the device is absent
   from instantiation, an axis-1 fact), but the general point stands: **this
   debt is not only a release blocker, it taxes every verification.** The real
   fix is not a valid hash but a structured in-guest observation path in
   `netvm-agent` — a RUN opcode or an equivalent — without which every internal
   check costs either a console or a drift.

13. **The comment at `netvm.sh` line 210 is wrong.** It claims the manifest
   lacks `chpasswd(8)`. Both `chpasswd` and `usermod` ARE in the image (under
   `/usr/sbin`, confirmed by mount on 07-23). The actual cause of the original
   failure is that `chroot_run`'s PATH does not carry `/usr/sbin` — hence the
   absolute path. Cosmetic.

14. **`netvm.sh` does not verify agent binary freshness.** A missing
   `NETVM_AGENT_BIN` only produces a `NOTICE` and the build continues (line
   247); a stale one produces nothing at all. On 07-23 this baked an agent
   carrying the old NETCFG stub and the gate failed on `NETCFG not yet
   implemented` — costing one boot cycle to diagnose. Fix: `die` if the binary
   is absent, plus a `sha256sum` in `netvm.meta` so the failure class is
   visible immediately.

15. **Executable bit on `build/netvm.sh` flipped** `100755 → 100644` (`micro`
   strips it; commit `d6d9267`). Hence `sudo bash build/netvm.sh`. Fix on
   Acer: `git update-index --chmod=+x build/netvm.sh`.

16. **`path_is_allowed` may not resolve symlinks (`vm-agent`) — HYPOTHESIS,
   unproven, unrefuted.** The path check is believed to be lexical:
   `starts_with(HOME_PREFIX)` plus rejection of `..` components. If so, a
   symlink at `/home/user/x` → `/etc/passwd` would pass, permitting FILEGET
   exfiltration. **Not verified against the source tree** — an earlier draft
   cited specific line numbers that were never checked and are deliberately not
   reproduced here. Kept in `state.md` rather than as a SECURITY-MODEL gap
   precisely because it is unverified: gaps there carry claims about the
   system. *Raised prior:* the same class was reported in Spectrum on
   2026-07-22 (`/run/vm/by-id/${VM}` writable by the VMM, not secure against
   symlink attacks) — `docs/OBSERVATIONS.md` §5. That raises the prior; it does
   not confirm our instance. *Gate:* read `path_is_allowed`; if lexical, place
   the symlink, call FILEGET, observe. *Two candidate fixes, not exclusive:*
   resolve in the agent (`openat2(RESOLVE_BENEATH)` or canonicalise-then-check),
   **and** a `nosymfollow` mount on the exposed subtree. Blocks nothing
   currently scheduled.

17. **C-gate remainder — netVM VMM privilege (C1, C2, C3, C5a).**
   `net-sys.con` still runs QEMU as root under `sudo`, without chroot or
   Landlock, in `init_netns`, with `memlock` from an interactive
   `ulimit -l unlimited` and no unit. C4 and C5b passed 2026-07-28. The three
   privileged preparation steps (vfio node, TAP creation, LVM activation) are
   all launcher-side and can drop before `exec qemu`; `RLIMIT_MEMLOCK` is the
   only real obstacle and it is configuration, not architecture. **Blocks all
   axis-2 work** (ADR-027). **Re-scoped by ADR-029 (2026-08-02):** C1, C3 and
   C5a are no longer daemon implementation — they are unit directives (`User=`,
   `LimitMEMLOCK=infinity`, a `setpriv`-style Landlock wrapper in `ExecStart=`),
   with privileged preparation in `ExecStartPre=+` and cleanup in
   `ExecStopPost=+` (measured to run as uid 0 after `SIGKILL`). C3 closes on
   configuration exactly as ADR-027 predicted. C5a note stands: Landlock
   rulesets are inherited across `execve`, so a small `setpriv`-style wrapper
   suffices — no QEMU patch required. **C2 is under review as a C-gate item in
   its present form:** `app_web.con` carries no network device, so there is no
   AppVM tap to hand over, and netVM's `tap-int0` can be pre-created with
   `ip tuntap add … user <uid>`. C2 returns as a link-topology question when the
   AppVM acquires an endpoint. SECURITY-MODEL gap #11.

18. **vsock CID space is global on the host (C6).** Any host process can reach
   any VM's agent on port 1025. Linux 7.0 makes vsock namespace-aware for
   `vhost-vsock` and `vsock_loopback`, and the MINIS host kernel
   (7.0.12-arch1-1) already has it. Per-VM netns with `child_ns_mode=local`
   fixes it. *Measured 2026-08-02 (ADR-029 G0/G1):* `child_ns_mode` is
   **write-once** (`EBUSY` on a differing second write) and `ns_mode` is
   `r--r--r--` — immutable after namespace creation. The write happens in a
   **parent** namespace and children inherit at creation, so this is a one-time
   preparation on a dedicated `katmate-root` namespace, **not** a daemon-start
   decision as ADR-028 states; `init_netns` is never written. `ip netns add` is
   **not nestable** — under `ip netns exec` it leaves a `----------` placeholder
   that `setns` rejects with `EINVAL` — so the daemon creates namespaces itself
   (`setns` → `unshare` → `mount --bind /proc/self/ns/net`) and hands the
   **named** result to the unit via `NetworkNamespacePath=`. Reading per-netns
   sysctls requires remounting `/proc`, or the value returned is the old
   namespace's — a false-negative class, not a robustness detail. Still open:
   the daemon must reach every VM, so `setns` on demand vs per-namespace
   sockets is a socket-lifetime question. *Coupling that must not be discovered
   late:*
   with CID reuse across namespaces the domain indicator's identity becomes
   **(netns, CID)**, not CID (ADR-026). C6 and ADR-026 are revisited together.
   SECURITY-MODEL gap #12; mechanism in ADR-028.

## Next steps

**ADR numbering.** `ADR-030` = *what the launch daemon reads* — **written
2026-08-06**. `ADR-031` = the licence declaration (GPL-3.0 attribution for the
CYBRland-derived `desktop/` subtree), not written. The `HOST-CONFIG.md:199`
correction claimed on 2026-08-06 had **not** in fact been applied — line 199
still read `ADR-030`; it has now been corrected. A drift note that itself
drifted.

**Next session: 3a.** Gate E1 passed on MINIS 2026-08-06 (candidate A; B also
passing and kept as a recorded fallback), so unit templates are unblocked.
Order:

1. `properties.toml` for netVM and app_web, per the ADR-030 schema, plus the
   two new validator error rules and the `class`-dependent CID band.
2. `<image>.meta` for the netVM image and the app_web layer, on the
   `foundation.meta` pattern.
3. The three unit templates. `sys-driver` first — netVM is the harder case
   (q35, vfio, initrd) and will find the schema's gaps faster than app_web.
4. Gates G1–G6, then delete both `.con` files.

Implementation session, thinking-off. Carry in: VM units must not depend on
`network-online.target` (2026-08-03 session); no monitor in any shipped
template; a pty or a separate dev launcher is needed for netVM bring-up once
the console goes to the journal.

**Deferred, own session (architecture, thinking-on):** memory backing —
hugepages vs memfd, whether `share=on` has any consumer, C3 `LimitMEMLOCK`
under C1. And the `/home` storage mechanism (ADR-010/011): thin snapshot of a
frozen `vm_home_skel` vs qcow2 branch.

**Primary (netVM sysVM — ADR-021 track, build now PROVEN):**

- **`netvm-agent` — FUNCTIONALLY COMPLETE.** PING (07-17), SHUTDOWN (07-18,
  ADR-024), NETCFG (07-23, ADR-025) — all live-gated. The opcode model is
  final: PING + NETCFG + SHUTDOWN; RUN / FILEGET / FILEPUT stay absent
  (boundary test in `op.rs`, confirmed live against the fresh binary). Further
  work on this agent answers launch-daemon needs, not missing handlers.

- **In-guest verification via a dev-only console password** (out-of-band; remove
  before release, sshd class): `networkctl status` routable, WireGuard/ProtonVPN
  up, the inner-segment p2p link. **Note:** this item was written when the peer
  was personalVM, which no longer exists (2026-08-02) and whose replacement
  AppVM has no network device yet (ADR-029 C2 finding). The netVM half is
  verifiable now; the peer half is not, and waits on the launch daemon. Only
  link-up + DHCP lease
  confirmed so far (from the host). The agent is NOT the verification path (no
  RUN).

- **DNS-leak policy in the manifest** — the uplink DHCP offers `DNS=1.1.1.1`
  (LAN router). netVM must push DNS through ProtonVPN (`10.2.0.1`). Decide:
  override with `DNS=10.2.0.1` + `Domains=~.` in `20-uplink.network`, or drop
  the uplink DNS entirely. Security-relevant; fold into the manifest. Of the
  two, override is the stronger candidate, and `Domains=~.` is the load-bearing
  half: without it the resolver is merely *one* among several and per-link DHCP
  DNS can still leak. Dropping DNS outright is weaker than it looks — fail-closed
  belongs in the baked nftables killswitch, not in the absence of a resolver.
  **Verify the mechanism before deciding.** `netvm.sh` step 5 deliberately does
  NOT enable `systemd-resolved`, and the image is dbus-free by manifest while
  `resolved` is dbus-oriented. If `resolved` does not run, `DNS=`/`Domains=` in
  a `.network` file buy nothing and the real path is `/etc/resolv.conf` in the
  conf tree. This is the same class of unverified mechanism precondition that
  killed the ADR-021 shutdown model and ADR-025 Path A — probe it, do not assume
  it. Probing needs the console (#11, #12).

- **WireGuard key provisioning automation** (ADR-021 open item) — keys are
  deploy-time (placeholders in the image, per image/state separation). Needs a
  provisioning step; do NOT bake keys.

- **`netvm.sh` cleanup — RESOLVED 2026-07-24.** The trap already existed
  (`netvm_cleanup` + `trap … EXIT`, its own linear-LV model, deliberately not
  `lib.sh`'s thin one); what was missing was **ordering**. `sync` ran *before*
  `umount_root`, and a sync on a still-open mount does not settle jbd2. Now:
  umount first, then `sync` + `udevadm settle`. Added `netvm_umount`, a local
  helper that surfaces umount failure instead of swallowing it the way
  `lib.sh:umount_root` does (`2>/dev/null || true`) — a failed umount is
  exactly the hot-jbd2 case the loud warning exists for. Step 10 uses the same
  helper, so under `set -e` an incompletely unmounted image no longer counts as
  built. Supersedes the earlier prescription (`sync` + `settle` + `sleep`
  *before* return), which could not have worked: on failure the script never
  reached its unmount at all.

- **`tap-int0` host-side persistence — RESOLVED 2026-07-20.** Was manual-only
  (`ip tuntap add`) → gone on host reboot. Now declared via networkd
  `/etc/systemd/network/tap-int0.{netdev,network}` (tap-work pattern, `User=host`,
  no L3 — pure L2 conduit into netVM). **The `RequiredForOnline` note this entry
  used to carry was wrong** — it predicted the default would at worst *"slow
  boot"*. Measured 2026-08-02: `network-online.target` never fires at all, with
  no diagnostic. `[Link] RequiredForOnline=no` is not optional and is not a
  boot-speed matter; it is a requirement, recorded in
  [docs/HOST-CONFIG.md](docs/HOST-CONFIG.md) §1 with its failure mode.

- **`net-sys.con` under git — RESOLVED 2026-07-20** (`f5f8ef2`). Was MINIS-only
  from 07-09, never committed. Sync wart persists: the standing rsync excludes
  `katmate-os/`, so the file lands in `~/katmate-build/`, not the repo path —
  copied to live `~/net-sys.con` by hand.

- **`sync.fish` wrapper — now with a second reason.** Besides the `--exclude`
  set that suppresses `Permission denied` noise: rsync preserves mtime from
  Acer, so cargo on MINIS skips compilation and `cargo build` reports
  `Finished in 0.05s` while leaving the OLD binary in place. This misled twice
  on 07-23 (`ping-client`, `netvm-agent`), both diagnosed only via
  `strings | grep`. The wrapper should `touch agent/crates/**/*.rs` after a
  sync, or run rsync with `--no-times` for that subtree.

- **Post-sync verification: `grep`, not `git log`.** MINIS git is
  non-authoritative under Path A; `git log -1` there shows an old commit even
  when rsync has already updated the files, and vice versa. The only valid
  test is file content.

- **`Harden netvm.sh cleanup` — sharper diagnosis.** The jbd2 lock is now
  empirically characterised: `lsof` and `fuser` show NOTHING (a kthread has no
  fds), while `ps aux | grep jbd2` shows `[jbd2/dm-N-8]` for exactly that
  `dm-N`. Additional `sync`/`udevadm settle` AFTER the die therefore cannot
  help — on failure the script never reaches its unmount at all. The real fix
  is a trap that unmounts before exit. Bit three times on 07-23, costing two
  host reboots.

- **ERR reason codes (ADR-025, deferred).** The gate showed the practical
  cost: `netcfg-add` against a live record returns a bare ERR and the reason
  is only in the guest journal — reachable only through the console. That is
  expensive for development. Revisit once the launch daemon demonstrates a
  need to branch on failure class.

- ~~**Docs hygiene (deferred) — reconcile the state.md session section.**~~
  **Done 2026-08-06**, and the same failure had recurred: after the 07-26 pass
  moved 07-14 + 07-13 into `SESSIONS.md`, three later sessions (07-23, 07-21,
  07-20) accumulated in this file's un-headed preamble and were again the only
  copy. Both the preamble and the missing 2026-08-02 heading are now cleared —
  see *Session archive*. **The recurrence is the finding, not the backlog
  item:** an entry written straight into `state.md`'s preamble instead of into
  a dated session heading is invisible to the trim rule, so the rule silently
  destroys it. Sessions get a heading at the time they are written, or they are
  not written down.

**Carried from 2026-07-14 (ADR-022/023 consequences):**

- ~~**CID renumbering**~~ — **done 2026-08-02.** `app_web` 5 → 21; normative
  band 4–8 → 20–99 in ADR-015 / ADR-017 / `tools/validate-properties.fish`;
  `properties.toml` restricted to the AppVM class, with 3–19 a hard error.
  personalVM was deleted rather than renumbered. The agents needed no change —
  they know only host CID 2 and the peer CID from `accept`.
- **ADR-016 revision + ADR-026 (indicator carriers)** — both now empirically
  grounded except one gate. ADR-016: the two-profile DE model becomes
  single-profile, **Sway ships alone** (the host compositor is in the TCB — it
  draws the domain indicator); Hyprland/CYBRland stays a dev/demo profile until
  its indicator implementation is separately verified. The DE profile *contract*
  (waypipe client per domain · host-side domain-identity hook keyed on **waypipe
  CID**, never on spoofable `app_id`/title · bar module reading launch-daemon
  state · keybindings → katmate CLI) is now documented in ARCHITECTURE.md.
  ADR-026, settled 2026-07-27: `#RRGGBBAA` is parsed *and rendered*, so alpha is
  a usable dimension; `show_marks` draws only in a titlebar, so marks are
  rejected under `border pixel`. Carrier set is the waybar module (authoritative,
  host-fed — **never** `sway/window`, which shows guest-controlled titles) plus
  focused border colour (hue + alpha). **Remaining gate:** confirm
  `swaymsg -t get_tree` exposes a `pid` resolving to the waypipe client process.
  Requires a live `app_web` instance — now possible, since Sway runs on MINIS.
- **Launch daemon** — ADR-022 graph ownership, ADR-017 CID allocation, ADR-025
  NETCFG ordering and re-issue, ADR-026 CID→name; refuses to tear down a
  `provides_network` VM with live dependents. This is where `netvm`/
  `provides_network` become real. **Supervision model settled (ADR-029):
  systemd is the parent, the daemon orders units.** Next design points, in
  order: (1) unit shape — `StartTransientUnit` vs a `katmate-vm@.service`
  template with per-instance `EnvironmentFile`; (2) namespace creation as
  daemon code (`setns` → `unshare` → bind mount), since `ip netns add` is not
  nestable; (3) how the daemon reaches every VM's namespace — `setns` on demand
  vs per-namespace sockets.
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
- ~~**Migrate live AppVMs** (personal) off the old systemd-user / linear-root
  model~~ — **void 2026-08-02.** The only such VM was personalVM and it was
  deleted, not migrated. No pre-foundation AppVM remains. (netVM was never in
  scope — it is a sysVM and stays systemd.)
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
- **netVM is `dbus`-free by manifest — bus-dependent mechanisms are INERT, not
  merely unconfigured.** `netvm.sh` ships neither `dbus` nor `libpam-systemd`
  (ADR-021's own exclusion, reaffirmed by ADR-024). Consequence: `logind`,
  `systemd-resolved`, `networkctl reload`, `polkit` and any non-root
  `systemctl` fail **at the bus** (`Failed to connect to system bus`), not at
  their own logic. This has now invalidated the mechanism of three accepted
  decisions after the fact: ADR-021's QMP→ACPI→logind shutdown (ADR-024 E1),
  ADR-025's networkd-fragment Path A (E1–E3), and it is the open precondition
  under the DNS-leak policy (`resolved` is dbus-oriented). **Rule: an ADR whose
  mechanism is a systemd component that talks over the system bus must gate the
  mechanism empirically BEFORE acceptance.** The design layer may be decided
  first only where it is mechanism-independent (the ADR-023 → ADR-025 split).
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
- **netVM `netvm.sh` cleanup — hardened 2026-07-24; the residual rule is
  `reboot`, not `lvremove`.** The symptom (build finishes, yet `Open count: 1`
  + live `jbd2/dm-<n>` while `mount`/`lsof`/`fuser` are clean) came from
  ORDERING: `sync` ran before `umount_root`, and a sync on a still-open mount
  does not settle jbd2. Now umount → `sync` → `udevadm settle`, via
  `netvm_umount`, which surfaces umount failure instead of swallowing it the
  way `lib.sh:umount_root` does. The prescription this entry used to carry
  (`umount -R`+`sync`+`settle`+`sleep` before return) could not have worked —
  on failure the script never reached its unmount at all. If a hot jbd2 still
  appears: reboot, do NOT force `lvremove`.
- **netVM root is DELIBERATELY UNLOCKED in dev — this invariant inverted.**
    `netvm.sh` step 6 locks root (`passwd -l`) and unlocks it in the next breath
    (`usermod -p`). Intentional: `netvm-agent` has no `RUN` and `NETCFG` replies
    bare `OK`/`ERR`, so the serial console is the only in-guest observation path
    (open problems #11/#12). The console password is a **release blocker** beside
    the dev sshd (#4) and installer secrets (#3), not a bug to correct. Host-side
    verification (ARP scan for the uplink MAC, LAN reachability) stays the
    preferred route and is unaffected.
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

- **netVM uplink netconf is MAC-matched, not name-matched — the interface name
  is NOT normative.** `/etc/systemd/network/20-uplink.network` matches
  `MACAddress=38:05:25:34:7c:47` (the RTL8125 as seen in the guest), DHCP,
  `RouteMetric=100`. MAC match is deliberate so a PCI slot / interface-name
  change does not break it — and it has already paid off: this file has been
  written up as `enp0s6` (netinst pet), `enp0s4` and `enp0s5` (declarative
  build) across sessions, because the name moved with the machine type and slot
  layout while the MAC did not. **When these disagree, the MAC is authoritative
  and the name is incidental.** The internal p2p segment is likewise matched on
  its locally-administered MAC `52:54:0a:64:01:01` (ADR-025), not on a name; the
  older `10-personal.network` / `Name=enp0s4` convention described the retired
  pet launcher and is void.

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
  `sudo bash net-sys.con` inherits the SHELL's `ulimit -l` (default 8192 KB) →
  QEMU dies with "cannot allocate memory" at `VFIO_MAP_DMA`, NOT a real OOM.
  `ulimit -l unlimited` before launch is therefore **mandatory, and today it is
  the only path: there is no `netVM.service`.** This entry used to name one as
  "the production path" with a `LimitMEMLOCK=infinity` drop-in — the only unit
  that ever existed was a March *user* unit pointing at the retired `net.con`,
  long disabled and removed 2026-07-25. A real unit, or the launch daemon, will
  need `LimitMEMLOCK=infinity`; until then the manual `ulimit` is not a
  workaround, it is the mechanism.

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
