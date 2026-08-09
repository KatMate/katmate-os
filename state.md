# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Milestone:** v0.2 (in development) · **Last updated:** 2026-08-09
(two sessions: ADR-032, then step 3a part 1 — the data layer).

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

## This session (2026-08-09, second of two) — 3a part 1: the data layer exists, and the schema tells the truth on its first day

Delegated implementation session on the Acer, whole tree visible. Five commits,
all signed. Split from the architecture session above because the work is
different in kind and because the tree is the subject — the chat context sees
about a third of it, and every wrong assertion this project has recorded today
came from that third.

### What exists now

- **`build/netvm.sh` writes T2 host-side.** `netvm.meta` had been written to
  `$NETVM_MNT/var/lib/katmate/netvm.meta`, inside the guest filesystem — the one
  place no launcher can read without mounting the guest root, which the launch
  path must never do. Payload and metadata now share `/var/lib/katmate/netvm/`
  per ADR-032 §5, because they share an author, a lifecycle and an upgrade
  owner. `out/netvm/` keeps its copy and stays a build tree. The meta carries
  what a unit needs and the four descriptive keys could not supply: the LV, the
  guest-side root device, the rootfstype, and the kernel and initrd paths.
- **`build/app-layer.sh` writes `app-web.meta`** with per-app-layer provenance.
  `foundation.meta` already recorded `FOUNDATION_LV`, so the gap was never the
  base LV's *name* — it was that nothing tied an app layer to the foundation
  *generation* it was snapshotted from.
- **`tools/validate-properties.fish` enumerates a directory** and enforces the
  class-dependent schema: required and forbidden sets per class, class-dependent
  `manifest` values, the `sys-proxy` error, and the cross-file duplicate-`nic`
  rule that was not implementable until T1 had a location.
- **Both `properties.toml` files exist**, on the Acer only, at their canonical
  paths mirrored under `~/katmate-t1/`. They are not in the repository and never
  will be (ADR-032 §1).

### The one behavioural proof part 1 could make

Five rejections verified with verbatim output: `persistence` on `class = sys`;
`nic` on `class = app`; `class = sys` without `nic` reported as the named
`sys-proxy` error rather than a bare missing key; the same `nic` label in two
files (G5); and `cid = "auto"` with `disposable = true` accepted, which is the
regression guard for the CID band. This is ADR-032 §3's whole claim — forbidden
keys are errors at parse, not ignored — and it holds.

### `app_web` has no network device, and the schema said so

The finding that reached furthest. `app_web.con` carries vsock, two block
devices and an RNG: no `-netdev`, no `virtio-net-device`, no tap. So its honest
T1 is `netvm = ""`, which derives **`app-offline`** — and ADR-030's gate G2,
which names `katmate-app-routed@` for `app_web`, is misnamed.

Declaring `netvm = "netvm"` instead was rejected: it would have made 3a **add**
a mechanism rather than transcribe one, and 3a's entire value is as ADR-030's
empirical gate. Recorded as a revision note on ADR-030 with four consequences,
including that **3a ships two templates, not three**, and that ADR-032's gate H2
needs an inverted pair since it cannot start a unit that does not ship.

**And the schema then earned its keep on day one.** ADR-015's semantic invariant
— a `web` manifest with no network is almost certainly wrong — survived the
removal of the `network` field, because the field changed and the invariant did
not. Re-expressed on `netvm`, it fires on `app_web` under `--strict`. It was not
silenced. The warning is true, and it is true *because* the AppVM network device
does not exist; it stops firing when link topology is settled. The cost is
recorded: `--strict` cannot be a pre-commit gate over the real T1 set today
without an expected-warning allowance.

### The `trap` had to move, and that is the one unverified change

The brief said to append a block "after `trap - EXIT`", on `foundation.sh`'s
pattern. In `netvm.sh` that disarm was the **second-to-last line**, guarding a
cleanup that `lvremove`s the image. Appending below it would have meant that a
`set -e` failure in the new block destroyed a complete, valid image — the exact
failure the ordering exists to prevent. The disarm now runs immediately after
the umount.

**UNVERIFIED, and it executes first on MINIS.** The observation pair that
settles it: a netVM build failing in steps 1–10 must still remove the LV; one
failing in step 11 must leave it standing.

### Corrections this session forced on documents

- **ADR-015 gained the revision note it should have had on 2026-08-06.**
  ADR-032 §3 changes the schema ADR-015 owns, and ADR-015 states its own
  discipline twice: the specification and the tool enforcing it must not
  disagree. The note also **restates the CID bands in full**, because the
  ADR-030 note had already been misread once — as restricting `class = app` to
  20–99, which deletes ADR-014's disposable archetype at parse time. `class =
  app` keeps all three forms: 20–99 static, `"auto"`, and numeric ≥ 100.
- **`D13` is decided: everything in the repository is en_US.** The validator and
  `bin/katmate-cid` are Slovenian in comments and diagnostics. Translating them
  is now an open item — mechanical, verifiable, its own commit.

### What this session is evidence for

The delegated session made no wrong assertion about the tree across two reading
passes and five commits. It also caught two things the brief got wrong — the
CID band compression, and the `trap` — either of which would have cost a boot
cycle or an LV. **Where the tree is the subject, the tree has to be readable**,
and the split between architecture here and implementation there is not a
convenience.

Second: the schema found a defect in a *published gate* within hours of the
first two T1 files existing. That is the ADR-024 method arriving at its
cheapest possible moment — not in a template being debugged, but in a file
being written.

## Previous session (2026-08-09, first of two) — step 3a ran as a gate and returned five holes; ADR-032 answers them

Two sessions in one day, kept separate as the discipline requires: mechanical
housekeeping first (thinking-off), then architecture (thinking-on) once step 3a
reported back. Recorded as one entry because the second could not have been
predicted from the first — 3a was expected to write files, not to halt.

### Housekeeping (commit `d971006`)

- **The two 2026-08-06 sessions closed.** The hygiene pass had never been given
  a heading; its consequences were visible in this file and in the
  `SESSIONS.md` header while the session itself was invisible — the exact
  defect it had been convened to repair. Written up as *first of two*; ADR-030
  became *second of two*. The 2026-08-03 entry rotated to the archive in the
  same pass, because rotation **is** how a session closes.
- **Ordering was established from the session record, not inferred from
  content.** The first attempt placed the hygiene pass *after* ADR-030, on the
  reasoning that documentation cleanup follows architecture. It was before —
  its own working title was *"pred ADR-030"* — and it was a precondition: the
  ADR could not have been written against an unresolved ADR-030/031 numbering
  collision. Two attributions moved with it: the six repaired build-order
  ordinals belong to the ADR-030 session that created them by renumbering, and
  `HOST-CONFIG.md:199` splits — the *claim* to have corrected it belongs to the
  hygiene pass, the correction itself to ADR-030.
- **`zoxide` guard applied on both machines** (`config.fish:81`), open since
  07-03. It had stopped being cosmetic: every `ssh` to MINIS ran `config.fish`
  and printed the error, twice during this session's own rsync.

### Step 3a, delegated and halted

3a was handed to a Claude Code session on the Acer with the whole tree
visible — the chat context sees roughly a third of it, and three claims made
from that partial view during the morning were wrong (session ordering, the
existence of `netvm.meta`, an invented `ssh` alias). The brief was explicit
that it was written from a partial view and that the repository wins.

The session read eleven files and **halted before modifying any of them**,
reporting fourteen divergences. Four blocking. That is the gate working:
3a's whole purpose was to test ADR-030's schema by placing every line of both
`.con` launchers, on the principle that a line with nowhere to go is a hole.
The answer arrived before a single file was touched, which is the cheapest
place it could have arrived.

**The five holes, all of them one omission** — ADR-030 said *what* the daemon
reads and *who wrote it*, and never said **where any of it lies**:

1. **T1 had no location.** "Config tree" appears exactly once in the
   repository: in that table row. No `/etc/katmate`, no example
   `properties.toml`, nothing created by the installer. Work order step 2 could
   not be executed without inventing a path.
2. **The ADR-019 waypipe version lock had no tier.** ~38 lines of host control
   flow that must run before QEMU, normative by ADR-019 and recorded as such in
   this file. Not T1, not T2 (it *consumes* T2), not a directive that can
   appear in a unit.
3. **The required key set for `class = sys` was undefined.** ADR-030 lifts
   ADR-015's AppVM-only restriction and calls the rest "unchanged"; applied to
   netVM the rest does not survive contact.
4. **The duplicate-`nic` rule needed a validator that enumerates.** It is
   cross-file; the validator is strictly per-file and erases its accumulator
   after each one.
5. **T2 had to record a payload path and no runtime home existed.** `out/` is
   `.gitignore`d and is a build tree.

**Nine further findings**, of which the ones that changed a decision: the MAC
`52:54:0a:64:01:01` is not an unnoticed anti-pattern but an explicit ADR-025
decision that ADR-030 overturned without recording it; the brief's `-append`
argument cited ADR-018 for a claim ADR-018 does not make (the conclusion
survives on `init=`, which *bypasses* PID 1 rather than weakening it);
`foundation.meta` already records `FOUNDATION_LV`, so the gap is per-app-layer
provenance rather than the base LV name.

### ADR-032 (commit `774db9c`)

The five holes did not fit a revision note — they came to a directory
convention, a widened tier definition, a class-dependent schema and a validator
contract. That is an ADR by size. `ADR-031` stays reserved for the GPL-3.0
declaration; the gap in numbering is honest, because that decision is taken and
only the document is missing.

- **The path is the tier.** `/etc/` user · `/var/lib/` pipeline · `/usr/lib/`
  release · `/run/` derived. A reader establishes a file's tier with `ls`.
- **Authorship is made operative as *who wins on upgrade*.** ADR-030's
  principle was sound and unfalsifiable as stated — a file's author is not
  visible in the file. It follows that **T1 is never in the repository**: a
  committed `properties.toml` was authored by the project, which by ADR-030's
  own boundary makes it T3/T4. The installer seeds T1 and does not own it
  (`/etc/skel` → `$HOME`), which is the pattern already used for
  `outputs.conf` and the generated greetd sessions.
- **T4 is the template plus the executables it references**, at
  `/usr/lib/katmate/`, under an authority limit: reads T1 and T2, writes only
  `/run/katmate/`, decides binarily, derives the profile only from
  `(class, netvm, nic)`. Without the limit, widening T4 opens a second route to
  the profile and containment becomes negotiable. ADR-030 §8's projection
  generator was already such an executable; the ADR relied on the category
  without naming it.
- **Required keys are a function of `class`**, with forbidden keys rejected at
  parse. A `persistence` line on a netVM that is silently discarded is the
  *silent wrong-object* class this project keeps finding.
- **Payload follows the producer**, and the AppVM kernel is T2 with one value
  for every image.

Revision notes on ADR-030 (the five findings) and ADR-025 (the MAC
supersession). Gates **H1–H3** open, attached to 3a.

### Corrections this session forced on this file

Four claims here were wrong, and one of them misled the delegated session
directly — it inferred a path mismatch from `~/katmate-build/katmate-os/`,
which does not exist. See *Invariants* and *Open problems*: the MINIS build-copy
path, the `--delete` claim, two stale line references, and open problem #15,
which is **resolved**.

### What this session is evidence for

The gate cost one reading pass and produced five schema defects. The
alternative — writing the templates first and discovering that the waypipe
preflight has no tier while debugging a unit — is the expensive version of the
same finding. **ADR-024's method transfers from mechanisms to schemas.**

Second, less comfortable: three of the morning's errors came from asserting
repository facts without opening the files, against this project's own standing
rule. The delegated session, with the whole tree visible, produced no such
error in eleven files. Where the tree is the subject, the tree has to be
readable.

## Session archive

Sessions older than the two above (the 2026-08-06 pair, then 2026-08-03, then
2026-08-02 *second of two*, then *first of two*, then 2026-07-28 back to
2026-06-27) live in
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

**The 2026-08-06 pair was briefly split across the two files** and is whole
again in the archive as of the second 2026-08-09 session, *second* above
*first*. The split lasted one session and is recorded only so the intermediate
state is not mistaken for a defect.

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

13. **The comment at `netvm.sh` line 224 is wrong.** (Cited as line 210 until
   2026-08-09; the file has moved under it.) It claims the manifest
   lacks `chpasswd(8)`. Both `chpasswd` and `usermod` ARE in the image (under
   `/usr/sbin`, confirmed by mount on 07-23). The actual cause of the original
   failure is that `chroot_run`'s PATH does not carry `/usr/sbin` — hence the
   absolute path. Cosmetic.

14. **`netvm.sh` does not verify agent binary freshness.** A missing
   `NETVM_AGENT_BIN` only produces a `NOTICE` and the build continues (line
   263; cited as 247 until 2026-08-09); a stale one produces nothing at all. On 07-23 this baked an agent
   carrying the old NETCFG stub and the gate failed on `NETCFG not yet
   implemented` — costing one boot cycle to diagnose. Fix: `die` if the binary
   is absent, plus a `sha256sum` in `netvm.meta` so the failure class is
   visible immediately.

   **Update 2026-08-09:** `netvm.meta` now exists **host-side** at
   `/var/lib/katmate/netvm/netvm.meta`, so the natural home for the checksum
   exists. Deliberately not added in 3a part 1 — out of that brief's scope.

15. ~~**Executable bit on `build/netvm.sh` flipped** `100755 → 100644`~~ —
   **Resolved.** `git ls-files -s` reports `100755` (verified 2026-08-09). The
   entry had outlived the defect; `sudo bash build/netvm.sh` is habit, not
   necessity. The underlying `micro` hazard is unchanged and lives in
   *Invariants*.

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

**ADR numbering.** `ADR-030` = *what the launch daemon reads* (2026-08-06).
`ADR-031` = the licence declaration (GPL-3.0 attribution for the
CYBRland-derived `desktop/` subtree) — **decision taken, document not written**;
the number stays reserved and the gap in the sequence is an honest record of
that. `ADR-032` = *where each tier lives* (2026-08-09).

**Next session: 3a part 2 — templates, T4 executables, gates.** Part 1 closed
2026-08-09 in five signed commits (`3a482d8`, `12a7ce0`, `578e5d3`, `cf1dac5`,
`54b26d0`): T2 is host-side, the validator enumerates a directory and enforces
the class-dependent schema, and both `properties.toml` exist. Part 2 is
delegated the same way, to a session with the whole tree visible.

1. The four T4 executables at `/usr/lib/katmate/` (ADR-032 §2):
   `katmate-check-waypipe`, `katmate-check-image`, `katmate-activate-lvs`
   (`ExecStartPre=+`, needs uid 0), `katmate-generate-env`. Authority limit:
   reads T1 and T2, writes only `/run/katmate/`, decides binarily, derives the
   profile only from `(class, netvm, nic)`.
2. **Two** unit templates — `katmate-sys-driver@` and `katmate-app-offline@`.
   Not three: `app_web` has no network device, so nothing derives `app-routed`
   and no gate can exercise it (ADR-030 revision note, 2026-08-09).
   `sys-driver` first.
3. The `nic` binding step that publishes `/run/katmate/nics/uplink0` → current
   BDF, plus the `vendor`/`device` check at VM start (ADR-030 §5, gate G6).
4. Gates G1–G6 and H1–H3, then delete both `.con` files. Deletion is the last
   commit and only if every line is placed. It creates dangling references in
   `SECURITY-MODEL.md` (#11 is open and describes `net-sys.con` as the thing
   running QEMU as root), `HOST-CONFIG.md` §3 and §6, `DECISIONS.md` and this
   file — repaired in the **same** commit, because that drift is created by it
   rather than inherited, and G3 is *"nothing was lost"*.

Implementation session, thinking-off. Carry in: VM units must not depend on
`network-online.target`; no monitor in any shipped template; a pty or a
separate dev launcher is needed for netVM bring-up once the console goes to the
journal; the live delta is named `test_web.qcow2` and follows the instance to
`app_web` (ADR-032 §7).

**Three things part 2 must resolve before a gate can run.**

- **Both T1 files exist only on the Acer**, under `~/katmate-t1/`, and are in no
  repository by design. They must be installed at `/etc/katmate/vm/` on MINIS
  before any G-gate.
- **`/var/lib/katmate/kernels/` does not exist and nothing populates it.**
  `app-web.meta` records *which* kernel (`KERNEL_VERSION=6.12.87`) per ADR-032
  §5, but a unit's `-kernel` needs a path. The AppVM kernel lives in
  `$KERNEL_SRC_DIR` today and is copied into `out/` by the Makefile, and
  `app_web.con` reads it from `$KERNEL_SRC_DIR` directly — three locations, none
  of them the ADR-032 one.
- **The `trap - EXIT` relocation in `netvm.sh` is UNVERIFIED** and executes on
  the first netVM rebuild. A failure in steps 1–10 must still remove the LV; a
  failure in step 11 must leave it standing. That pair is the whole point of the
  move.

**Also carried in:** the validator's exit codes are three-valued (0 valid, 1
schema error, 2 usage / nothing validated), so a gate script must not treat
non-zero as uniformly invalid. `validate-properties.fish --strict` cannot serve
as a pre-commit gate over the real T1 set until AppVM link topology is settled —
the `web`-manifest-without-network warning it raises on `app_web` is true, and
was deliberately not silenced.

**Deferred, own sessions (architecture, thinking-on):** memory backing —
hugepages vs memfd, whether `share=on` has any consumer, C3 `LimitMEMLOCK` under
C1. The `/home` storage mechanism (ADR-010/011). AppVM link topology, which
ADR-029 leaves *"opened, not settled"* and which gates `app-routed`. And the
durable NIC descriptor: `HOST-CONFIG.md` §3 requires it to be **measured, not
chosen** — `vendor:device` is not unique on a two-port card, the MAC is readable
only before `vfio-pci` binds, the slot path survives reseating but not a
firmware change. Same problem as the USB-NIC profile: one durable-descriptor
question at two sites.

**Open, mechanical:** translate `tools/validate-properties.fish` and
`bin/katmate-cid` to en_US. Both are Slovenian in comments and diagnostics;
the repository rule is en_US throughout (decided 2026-08-09). Own commit.

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
  from 07-09, never committed. The file lands in `~/katmate-build/` and is
  copied to live `~/net-sys.con` by hand. **The "sync wart" framing was wrong**
  (corrected 2026-08-09): `~/katmate-build/` is not an exclusion artefact, it
  is where the repository contents belong on MINIS. The exclusion of
  `katmate-os/` describes a layout that does not exist. Moot from the moment
  3a deletes the launcher.

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
  **Pending (2026-08-09):** ADR-025's revision note replaces authored MACs with
  `52:54:00` + `sha256(instance)[0:3]`. This value is stale from the moment the
  projection generator lands; no image rebuild is implied, because the guest
  bakes no internal-segment `.network` unit.
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

- **Source of truth = Acer `~/katmate-os/` git repo.** MINIS `~/katmate-build/`
  **is** the build copy — the repository contents land directly in it, synced
  FROM the repo, never edited on MINIS. Git lives ONLY on Acer.
  **Corrected 2026-08-09:** this entry claimed the copy lived one level deeper,
  at `~/katmate-build/katmate-os/`. That directory does not exist
  (`ls` on MINIS), and the claim misled the delegated 3a session into reporting
  a launcher/build path mismatch that is not real — `net-sys.con` reads
  `/home/host/katmate-build/out/netvm/` correctly. It also claimed the rsync
  runs **without** `--delete`; it was run **with** `--delete` on 2026-08-09 and
  removed nothing. Neither claim had been true for some time. Stale documented
  layout is the same failure class as a stale BDF: a reference that still
  resolves, just not to what it meant.

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
