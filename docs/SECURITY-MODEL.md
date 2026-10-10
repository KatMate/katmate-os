# Security Model

## Goal

Compromise containment: a compromised workload must not be able to compromise
other workloads or the host. The host is the trusted computing base; everything
else is assumed breachable.

## Threat model

### In scope

- Malicious websites and browser exploits
- Document exploits (PDF, office formats)
- Application compromise inside a VM
- Data theft between workloads
- Network tracking
- VPN failures / leaks

### Out of scope

- Physical access attacks (evil maid, DMA)
- Hardware implants
- Malicious firmware
- Side-channel attacks
- Nation-state hardware attacks

### Scope consequences

- Full-disk encryption (LUKS2) protects confidentiality of data at rest, e.g.
  on device theft. It does **not** defend against an attacker with repeated or
  runtime physical access — that is explicitly out of scope.
- Secure Boot / measured boot is intentionally absent at this stage. This is
  *consistent* with the exclusion of physical access attacks, not an oversight.
  Revisit at v1.0 if the scope changes.

## Trust boundaries

- The host controls VM lifecycle; VMs never control the host.
- Communication crosses only explicitly exposed AF_VSOCK channels.
- Each VM is its own trust domain; inter-VM communication does not exist by
  design (no guest-to-guest channel).
- **Boundaries move only from the more-trusted side.** Network configuration is
  mutated by netVM's *own* agent executing a *host* command
  ([ADR-021](adr/ADR-021.md)); a guest can never move its own boundary.
- **Where a boundary is enforced is part of the boundary.** AF_VSOCK limits are
  enforced by the host kernel; a userspace device model substitutes process
  correctness for that enforcement. This is a property to be stated in any ADR
  that moves a device model, never assumed neutral
  ([ADR-027](adr/ADR-027.md), [ADR-028](adr/ADR-028.md)).

## Principles

1. Default deny
2. Explicit whitelisting
3. Minimal services
4. Least privilege
5. Minimal dependencies
6. Small, auditable management layer
7. Separation of duties (system in base image, data in overlay)
8. **Absent, not disabled** — a capability that must not exist in a VM class is
   *not compiled into* the binary, or *not instantiated* on the command line,
   rather than gated at runtime ([ADR-021](adr/ADR-021.md)). This is the
   test for **existence** only; see *Three axes of capability control* below.
   Canonical instances: `netvm-agent` cannot decode `RUN`; an AppVM with
   `netvm: None` has no `Link` object; a VM class needing no control channel
   carries no `-device vhost-vsock-device`; netVM carries no `virtio-9p-pci`.
9. **Isolation by topology, not by rule** — network separation is expressed by
   which links exist, not by firewall rules discriminating between AppVMs
   ([ADR-022](adr/ADR-022.md))
10. **Relocation is not removal** — moving a capability across a privilege
    boundary (kernel → VMM, VMM → backend daemon) removes nothing. Its security
    value is *conditional* on the target being more confined than the source,
    and is zero until that is true ([ADR-027](adr/ADR-027.md)).

## Three axes of capability control

Three separate questions, three separate tests. Conflating them dilutes the
first into unfalsifiability ([ADR-027](adr/ADR-027.md)).

| # | Axis | Question | Test |
|---|---|---|---|
| 1 | **Existence** | Does the capability exist in this domain class at all? | Is it compiled / instantiated? |
| 2 | **Placement** | Where is it implemented, and how confined is that place? | Is the target more confined than the source? |
| 3 | **Enforcement** | Who holds the boundary? | Kernel-enforced, or dependent on userspace correctness? |

*Absent, not disabled* (principle 8) answers axis 1 and nothing else.

**Worked example — the vsock control channel.**

- *Axis 1, satisfied today:* a VM class that must have no control channel is
  launched without `-device vhost-vsock-device`. The device is absent.
- *Axis 2, open:* whether the virtio-vsock device model lives in the host
  kernel, the VMM process, or a separate backend daemon
  ([ADR-028](adr/ADR-028.md)). None of these options removes the channel.
- *Axis 3, currently strong:* `vhost_vsock` boundaries are kernel-enforced, and
  since Linux 7.0 the CID space is namespace-aware. Moving the device model to
  userspace trades kernel enforcement for process correctness.

**Worked example — the 9p host share, closed 2026-07-28.** The proof that netVM
cannot reach the host filesystem is taken **host-side**: the running VMM's
`/proc/<pid>/cmdline` contains neither `fsdev` nor `virtio-9p-pci`. That is an
axis-1 proof — the device is absent from instantiation, so the guest cannot
mount what does not exist — and it is *stronger* than an in-guest
`mount | grep 9p`, which would only be an axis-3 observation.

**Ordering rule.** Axis-2 changes are gated on axis-2 hygiene: no relocation is
implemented before the target passes the C-gate
([ADR-027](adr/ADR-027.md)).

## Controls by component

### Host firewall (nftables)

Input policy `drop`; accepted: loopback, established/related, ICMP/ICMPv6.
Forward policy `drop`. SSH disabled by default (rule present but commented
in the installer-provisioned ruleset).
VSOCK does not traverse netfilter — host↔guest traffic never touches the
network stack.

### Boot chain

systemd-boot with `timeout 0` and `editor no` — no interactive kernel
command-line tampering at the boot menu. Kernel: `linux-hardened`
(out-of-the-box hardening for the TCB; operational consequences in
[ADR-004](adr/ADR-004.md)).

sysVMs boot **direct-kernel** with no in-guest bootloader: the boot chain of the
network-facing VM lives host-side, outside the guest image — there is no
in-guest GRUB to rewrite for persistence ([ADR-021](adr/ADR-021.md)).

### VM agents

Two binaries from one workspace, split by **absent-not-disabled**
([ADR-021](adr/ADR-021.md)). A forbidden opcode fails at decode
(`TryFrom<u8>`), not at a runtime gate.

**`vm-agent` (AppVM, uid 1000, unprivileged):**

- VSOCK connections accepted from the host only
- `RUN` restricted to an application whitelist (`firefox-esr`, `foot`, `pcmanfm`,
  `libreoffice`, `keepassxc`)
- No file-transfer surface: `FILEGET`/`FILEPUT` (`0x03`/`0x04`) were retired on
  2026-10-06. The values are reserved, never reused, and answered with ERR
- No arbitrary command execution path
- **Contains no network-configuration code** — the least-trusted guest cannot
  even *name* the NETCFG opcode

**`netvm-agent` (sysVM, `CAP_NET_ADMIN` + `CAP_KILL`, not root):**

- **Contains no `RUN`** and no file surface — no general execution path
  exists inside the process holding network privilege
- `NETCFG` is a **typed link description**, never a shell string and never a
  policy ([ADR-023](adr/ADR-023.md)): interface match, local/peer address,
  `/32` prefix, route, metric; `add` / `remove` only, no `modify`. It cannot
  deliver an nft rule and cannot alter the baked firewall. Validation is
  structural and total — malformed payloads are rejected, never sanitised.
- **`SHUTDOWN` (0x05) IS present, and carries `CAP_KILL`** — corrected
  2026-07-18 ([ADR-024](adr/ADR-024.md)); the earlier "no SHUTDOWN, no
  shutdown privilege" claim in this document was stale. The QMP
  `system_powerdown` path is **inert**: `logind` requires dbus and the manifest
  omits it. Rather than ship dbus into the most-exposed VM, the agent signals
  PID 1 with `SIGRTMIN+4` (systemd's documented poweroff signal) under
  `CAP_KILL`. `CAP_SYS_BOOT` was explicitly rejected — it unlocks
  `kexec_load(2)` and is not graceful under systemd as PID 1. **Honest
  privilege delta:** `CAP_KILL` lets the agent signal any process in the guest.
  Bounded by absent `RUN` and a compile-time-constant signal target, but it is
  a real widening over `CAP_NET_ADMIN` alone and belongs in the ledger.

### Network isolation

- Per-AppVM `/32` p2p links; the netVM firewall is **static and AppVM-agnostic**,
  referencing only the aggregate internal segment. It never changes as AppVMs
  come and go ([ADR-021](adr/ADR-021.md)).
- Differentiated network access is expressed as **attachment to a different
  netVM** (each netVM image bakes one immutable policy), never as a per-AppVM
  rule ([ADR-022](adr/ADR-022.md)).
- An AppVM with `netvm: None` has **no link at all** — air-gap is the absence of
  an object, not a rule denying traffic.
- The netVM image bakes **no internal topology**: on a clean boot it has no
  internal route. Routes exist only for running AppVMs.

### GUI forwarding

Waypipe over VSOCK — no network listener, no X11 surface. Host side is a
socket-activated systemd *user* service (unprivileged).

**Correction (2026-09-26).** Until 2026-09-26, MINIS carried a
`waypipe-client.socket` that opened a **TCP `[::]:1024`** listener, not a vsock
one — a network listener on the host, which the sentence above says does not
exist. The operator disabled it on 2026-09-26; the host end is now the
`waypipe-client` user service alone, and **the ingress is vsock only**
([`../state.md` § *Live state*, *Host GUI ingress*](DEV-ENV.md); `HOST-CONFIG.md` § 11).

### Desktop compositor

The host compositor is **inside the TCB**: it draws the domain indicator that
visually separates domains. The indicator must be keyed on **waypipe CID
identity**, i.e. host-side trusted state — never on guest-controlled properties
(`app_id`, window title are spoofable). This is why a single audited profile
(Sway) ships, rather than two ([ADR-016](adr/ADR-016.md)).

The identity path is **two host-side steps and no guest input**
([ADR-026](adr/ADR-026.md)): the compositor supplies the window's `pid`,
and that pid's AF_VSOCK connection supplies the peer CID. `app_id` and window
title are excluded from the identity path at every level. Verified live
2026-07-28: a rendered guest window reporting `app_id: org.gnome.Nautilus`
resolved via its pid to the host waypipe client, whose vsock connection
reported peer CID 5 — the domain. The resolving query does **not** require
privilege (verified 2026-07-28: an unprivileged caller receives the same peer
CID as root), so the resolver may run in the user session; the launch daemon
remains the preferred owner of the map for other reasons.

### Guests

Minimal Debian userspace, minimal services, direct kernel boot, custom
MicroVM kernel with a reduced config surface. Nothing persists outside the
per-AppVM overlay.

### VMM process

Both launchers run QEMU with
`-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny`.
Verified live 2026-07-28 on both machine types: `Seccomp: 2` with one filter
loaded, no `SCMP_ACT_KILL` in `dmesg`, control path returning `0x00`, and the
netVM vfio reset cycle (`FLReset-` workaround) unaffected.

`resourcecontrol=deny` blocks the `sched_setscheduler` / `sched_setaffinity` /
`setpriority` family. The concern that this would collide with
`-object iothread` was tested rather than assumed, and did not materialise on
either machine type ([ADR-027](adr/ADR-027.md) C4).

Privilege differs by launcher and is **not** yet uniform: `app_web.con` runs
QEMU as the invoking user (`sudo` covers only `lvchange`); `net-sys.con` runs
it as root. Gap #11.

### Host block I/O

`aio=threads`, not `aio=io_uring`. The immediate cause is the hardened kernel
(`kernel.io_uring_disabled = 2`), but the choice is independently justified:
io_uring is among the most defect-dense kernel subsystems, and this path runs
host-side driven by guest I/O patterns. Public material bearing on this choice
— including material about QEMU's own device models — is recorded in
`docs/OBSERVATIONS.md` §1.

## Trusted computing base

Host kernel (`linux-hardened`) + QEMU/KVM + systemd + host side of vm-agent +
waypipe client + **host compositor (Sway — draws the domain indicator)** +
**launch daemon (owns the topology graph)** + installer-provisioned
configuration.

Kept deliberately small — but TCB size is measured in *privilege*, not only in
installed bytes. Two reductions are tracked separately:

- **Binary surface:** `qemu-full` → `qemu-base` (the MicroVM machine type needs
  no GUI frontends). Under evaluation.
- **Process privilege:** partially closed. Both launchers now run QEMU under a
  tightened seccomp filter (live-gated 2026-07-28), and no host filesystem is
  exported into any guest. Outstanding: the **netVM VMM still runs as root**,
  unconfined by chroot or Landlock, in `init_netns`, with `memlock` granted by
  an interactive `ulimit` rather than a unit. The AppVM VMM already runs as the
  invoking user. Gap #11; C-gate in [ADR-027](adr/ADR-027.md).

Until the second is closed for netVM, "minimal TCB" describes the intent of
this design and only partly its current state. **netVM does not require a root
VMM** — the privileged steps are launcher-side and drop before `exec qemu`; the
only real obstacle is `RLIMIT_MEMLOCK`, which is configuration.

**[ADR-033](adr/ADR-033.md) removes one of them, and the two claims that
follow are separate.** This sentence listed **three** privileged steps — vfio
node, TAP creation, LVM activation. The TAP was `tap-int0`, netVM's internal
segment, and that device is the one the slot pool replaces: a link is a pair of
AF_UNIX datagram sockets opened by each QEMU by path. **netVM's launcher is
therefore down to two privileged steps — the vfio node and LVM activation —
and both remain.**

**Separately, and this is the stronger of the two: an AppVM's start path needs
no privileged network step at all.** No `CAP_NET_ADMIN`, no tap, no bridge, no
network namespace, no descriptor handed in by a privileged parent. The QEMU
process opens its own end of the link, by path, as the invoking user.

The evidence is a startup trace of that QEMU, taken 2026-08-24 on MINIS
(`~/link-m2-report.md` § A.3). Outside dynamic linking it issues exactly
`unlink(local.path)` → `ENOENT`, `socket(AF_UNIX, SOCK_DGRAM|SOCK_CLOEXEC)`,
`bind()`. There is **no `connect()` at all**, and `remote.path` appears nowhere
in the trace — not `stat`-ed, not opened, not warned about. The trace filter was
verified first against a purpose-written program known to issue `socket`,
`bind`, `connect`, `sendto` and `unlink` on `AF_UNIX SOCK_DGRAM`, so the absence
is an absence of the call and not of the filter (§ A.1). Beyond the trace, the
whole three-session measurement arc — link-m1 and link-m2 (2026-08-24) and
link-m3 (2026-08-28) — **ran unprivileged from end to end, and no step in any of
them indicated needing `sudo`**: an unprivileged user bound the sockets, booted
guests on them, and drove frames across in both directions. That is a result
about the design and not only about how the sessions were run.

**The bound, stated with the same clarity as the claim.** What leaves is a
privileged step in the **AppVM start path**. It is not a general reduction of
the host's TCB: netVM's own privileged steps are untouched — **the vfio NIC
above all**, which pins the entire guest RAM and needs a device node, a group
and a lifted `RLIMIT_MEMLOCK` — and the netVM VMM still runs as root (gap #11).
Nothing here changes what netVM is trusted with.

The domain indicator adds one host-kernel dependency: AF_VSOCK socket
diagnostics (`vsock_diag`), used to resolve a window's pid to a guest CID
([ADR-026](adr/ADR-026.md)). Without it the indicator has no trustworthy
identity source.

## Known gaps (tracked)

| # | Gap | Status / remediation |
|---|---|---|
| 1 | ~~**Secrets committed in installer scripts** — WireGuard private key, WiFi SSID+PSK, default user credentials~~ | **Resolved:** since 2026-10-04 the installer carries no secret (hostname, user and password are prompted; `docs/INSTALL.md`), and the committed WireGuard key and Wi-Fi passphrase were rotated and are burned, left in git history (R162, R18). |
| 2 | Hidden SSID + AutoConnect forces clients into active probing — the machine broadcasts the network name everywhere | Switch to a visible SSID; drop `Hidden=true`. |
| 3 | ~~VPN terminates on the host, contradicting the NetVM target architecture~~ | **Resolved (live on MINIS):** WireGuard/ProtonVPN now terminates in NetVM per [ADR-009](adr/ADR-009.md). Host carries no VPN. **[2026-09-27 (operator ruling): the gap stands closed for the product, and the text above is left as written.** The *"live on MINIS"* wording is contradicted on both halves. netVM carries no WireGuard: the 2026-09-26 net-up reading found no WireGuard link and an empty `wg show` ([ADR-037](adr/ADR-037.md) § *Context*), and under ADR-037 vanilla egress is direct, with VPN a post-install option. The MINIS host does carry a `proton` WireGuard link. That link is **dev scaffolding**, and it is on the pre-release removal list beside the dev sshd (gap 4; [`state.md` open problem #4](OPEN-PROBLEMS.md)). Source: `adr037-readpass-report.md` D11 and § 6, outside the repository.**]** |
| 4 | **SSH open on development host** — `tcp dport 22 accept` active on MINIS (dev convenience, not installer default). ~~sshd also runs inside netVM (CID 3).~~ **The struck clause was wrong and is withdrawn (2026-09-03).** It described the retired hand-installed **netinst pet**, not the declarative `vm_sys_netvm` that `katmate-sys-driver@netvm.service` boots: `manifests/netvm.list` installs no `openssh-server`, `build/netvm.sh` carries no ssh step, and the running guest was checked from its own console on 2026-09-03 (`dpkg`/`command -v`). **netVM has no sshd.** | **One thing, not two.** This row read *"remove **both** before release"*; there is one. Restrict the host rule to LAN (`iif enp195s0f3u1u1 ip saddr 10.3.1.0/24`), or bind sshd to `10.3.1.3` so it is not reachable through the ProtonVPN tunnel, and remove it before release. Not present in the installer-provisioned ruleset. **The severity is lower than this row stated:** one sshd, on the host, not a second one inside the most network-exposed VM in the system. **The error had a measurable cost.** On 2026-09-03 this row was taken as authority for a dev sshd inside netVM; a delegated session's brief was written on that assertion and the session halted on it. netVM's in-guest access path is **gap 15**, and it is not ssh. **[2026-10-03 (operator ruling, R163): the alpha release has no dev access — the host is isolated. The dev sshd and `/etc/sudoers.d/katmate-dev` (gap 13) exist on the dev host only and are removed before release. The optional management NIC on a separate internal LAN stays a direction (`ROADMAP.md` § *Direction — managed deployment profile*, 2026-09-24); its setup instructions are written only after it is measured on hardware.]** |
| 5 | No base image signing / integrity verification | [ADR-013](adr/ADR-013.md) (Proposed). |
| 6 | No Secure Boot chain | Consistent with threat model (see above); revisit at v1.0. |
| 7 | **VPN key co-located with the NIC driver** — in v1 the WireGuard private key and the `r8169` driver + non-free Realtek firmware blob share one address space. Compromise of the most exposed code in the system (hardware-facing driver) is compromise of the VPN credentials. | Accepted for v1; the model already permits the fix. Post-v1: split into a **driver domain** (q35, hardware, no secrets) and a **proxy netVM** (microVM, secrets, no hardware) — [ADR-022](adr/ADR-022.md). |
| 8 | **Proxy sysVMs will add `CONFIG_WIREGUARD` + netfilter to the shared MicroVM kernel**, which all AppVMs also run. The code is unreachable from an AppVM (uid 1000, no `CAP_NET_ADMIN`) but is *present* — a departure from absent-not-disabled at the kernel level. | Accepted consciously ([ADR-021](adr/ADR-021.md) rejected a second kernel: doubled config maintenance, firmware-licensing issues for ISO distribution). Revisit if a second kernel becomes cheap. |
| 9 | **IOMMU-group quality is a hard requirement, unverified at install time.** A driver domain is only safe where the NIC is cleanly isolable; a bad grouping silently weakens passthrough isolation. | HCL + installer preflight check ([ADR-022](adr/ADR-022.md)); on the ROADMAP, not a v1 code blocker. |
| 10 | ~~**9p hostshare into netVM** — `net-sys.con` carried `virtio-9p-pci` with `security_model=none` sharing `/home/host` into the most network-exposed VM~~ | **Resolved (2026-07-28):** `-fsdev` and `-device virtio-9p-pci` removed from `net-sys.con`. Verified host-side: the running VMM's `/proc/<pid>/cmdline` contains neither. C5b in [ADR-027](adr/ADR-027.md). If a dev file path is ever needed again it must be a narrow subtree with `security_model=mapped-xattr`, in a **separate dev launcher**. |
| 11 | **netVM VMM runs as root, unconfined.** `net-sys.con` is invoked with `sudo`; the QEMU process has no chroot or Landlock ruleset, sits in `init_netns`, and receives `memlock` from an interactive `ulimit -l unlimited` rather than a unit. Compromise of this process is, in practice, compromise of the host. Does **not** apply to `app_web.con`, where QEMU runs as the invoking user and `sudo` covers only `lvchange`. **[2026-09-29, networking arc step 4a ([ADR-037](adr/ADR-037.md) R64): extended to AppVMs.** From the commit that adds `katmate-app-routed@.service`, that unit runs the AppVM's QEMU **as root** too, deliberately, as `katmate-sys-driver@.service` does for netVM: neither sets `User=`. The sentence above stays true of `app_web.con` itself, and it does not describe an AppVM started by the unit. The debt is paid in **C1**, for all units together: per-VM uids, R75's per-slot ACLs, and [`../state.md` open problem **#43**](OPEN-PROBLEMS.md).**]** **[2026-10-02, `ai4`: `katmate-app-offline@.service` (R135) also runs its AppVM's QEMU as root and sets no `User=`, like the routed template it is derived from, so this item covers all three shipped units until C1.]** | Largest remaining privilege item in the TCB. C-gate in [ADR-027](adr/ADR-027.md): C4 and C5b passed 2026-07-28; C1–C3 are the launch daemon's privilege split; C5a is a `setpriv`-style Landlock wrapper (no QEMU patch needed — Landlock rulesets are inherited across `execve`); C6 is per-VM netns. **Blocks all axis-2 work.** |
| 12 | **vsock CID space is global on the host.** Any host process can reach any VM's agent on port 1025; the waypipe host user service can reach netVM's agent although it has no reason to. | Linux 7.0 makes vsock namespace-aware (`vhost-vsock` + `vsock_loopback`); available on the current MINIS host kernel. Per-VM netns with `child_ns_mode=local`. Note `child_ns_mode` is **write-once** and `ns_mode` immutable after namespace creation — a daemon-start decision, not a runtime toggle. Couples to [ADR-026](adr/ADR-026.md): with CID reuse, indicator identity becomes **(netns, CID)**, not CID. C6 in [ADR-027](adr/ADR-027.md); mechanism in [ADR-028](adr/ADR-028.md). |
| 13 | **Passwordless root on the development host** — `/etc/sudoers.d/katmate-dev` grants `host ALL=(ALL) NOPASSWD: ALL` on MINIS. | Dev-only, added 2026-08-11 so delegated agent sessions can run root steps over ssh, where an interactive `sudo` prompt is not a prompt the session can see but a silent hang. Compounds gap 4 — ssh plus NOPASSWD collapses network reach and root into one step — and removes the last interactive checkpoint in front of gap 11's root-unconfined VMM. Remove the file before release. Not present in the installer-provisioned ruleset. **[2026-10-03 (operator ruling, R163): dev-host-only, removed before release; the alpha release has no dev access. See gap 4's note.]** |
| 14 | **A datagram-backed link cannot represent an absent peer.** A link is a pair of AF_UNIX datagram sockets ([ADR-033](adr/ADR-033.md), accepted 2026-08-28), and a datagram socket has no carrier: the guest's interface shows link-up whether or not anything is on the other end, and its `sendto` succeeds identically either way — measured 2026-08-24 on MINIS (`~/link-m2-report.md` § B2.2), where the same guest returned `rc=18, errno=0` on every frame across a peerless window and a peered one, with QEMU writing zero bytes to stderr throughout. A tap backend can signal link-down; this cannot. | **A property of the architecture, not a defect in it.** It was a property of a proposal until 2026-08-28 and is now a property of the mechanism of record; the measurement behind it is unchanged and so is its standing under ADR-033's costs accepted. The alternative that carries link state is the tap and bridge topology ADR-033 rejects on other grounds. The consequence is a requirement on the host and is undiminished by acceptance: **start ordering is the launch daemon's responsibility alone, and the guest cannot assist** — a guest cannot detect that its netVM is absent, so nothing in the guest may be relied on to notice. Revisit only if the backend changes. |
| 15 | **Dev console into netVM — three untracked pieces, and nothing in git will remind anyone they exist.** Added 2026-09-03 because ADR-035's gates need a reading from inside netVM and there was no path to one (see gap 4, whose withdrawn clause had implied there was). The three parts: **(a)** `/etc/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf` — a drop-in replacing the shipped `StandardInput=null` with `StandardInput=file:/run/katmate-dev/netvm-console.in`, so **anything that can write that FIFO can type at the console of the most network-exposed VM**; **(b)** `km-console-holder.service` — a transient unit holding a writer open on the FIFO, without which systemd's read-open blocks at unit start and QEMU's stdin would see EOF; **(c)** `/run/katmate-dev/netvm-console.in` — the FIFO itself, `0600 root:root` on tmpfs. Beside the host sshd (gap 4) and netVM's unlocked root ([`state.md` open problem **#11**](OPEN-PROBLEMS.md), recorded in the image as `NETVM_ROOT_UNLOCKED=yes`), this is the **third** piece of dev scaffolding that must go before release — and the only one of the three that is invisible to `git`, since no part of it is a tracked file. | Remove all three before release; removing **(a)** alone restores `StandardInput=null` and closes the input path. **A logged-in root console session persists for as long as netVM runs** — it is bounded by no ssh connection and no tty hangup, because nothing is attached to it. **Close it by sending `exit` through the FIFO**, which returns the guest to a login prompt; **do not kill anything** — killing the holder gives QEMU EOF on stdin, and killing the unit stops the VM. **The three do not survive a host reboot alike, and the asymmetry is a trap:** (b) is transient and (c) is on tmpfs, so both vanish, while **(a) is in `/etc` and does not**. `StandardInput=file:` on an absent path fails the unit at **`208/STDIN`**, *before any `ExecStartPre`* — measured 2026-09-03 on a throwaway unit: *"Failed to set up standard input: No such file or directory"*. **So after a reboot netVM will not start at all until the FIFO and its holder are recreated or the drop-in is removed.** **Update (2026-09-26).** Part (a) was **two** `/etc` drop-ins, not one — the pool unit's (`katmate-pool@.service.d/90-dev-monitor.conf`) and the sys-driver's — and both were removed on 2026-09-26 (operator ruling R1, [`../state.md`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md)), restoring `StandardInput=null` on both units. Console input is now installed **per session**, and **all three parts are on tmpfs** — a `/run` drop-in (`/run/systemd/system/katmate-pool@.service.d/90-dev-monitor.conf`), the FIFO, and the transient holder — so a reboot removes them together and the `208/STDIN` asymmetry above no longer arises; that absence after a reboot is unverified until the next host boot. **The `/run` placement is awaiting the operator's ruling (R9).** **[2026-09-27: the unit is now `katmate-sys-driver@`. The slot pool was folded into it, and `katmate-pool@.service` is no longer installed, so a per-session drop-in goes in `/run/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf`. Absence after a reboot is **verified**: after the host boot of 2026-09-27, both units read `StandardInput=null` with no drop-in, and the unit started with no `/run/katmate-dev/`. R9 is **ruled**: per-session only, in `/run`, never in `/etc` ([`../state.md`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md), 2026-09-27 entry).]** |
| 16 | **A blanket udev rule gives uid 1000 read-write on every `vm_*` block device, the thin pool's own data and metadata included — untracked, and until 2026-09-27 in no document.** `/etc/udev/rules.d/99-vm-lvm.rules` on MINIS, `root:root 0644`, dated **2026-02-09**, reads in full: `# AppVM LVM volumes - allow host user access` / `SUBSYSTEM=="block", ENV{DM_VG_NAME}=="vg0", ENV{DM_LV_NAME}=="vm_*", RUN+="/bin/chown host:host /dev/%k", RUN+="/bin/chmod 0660 /dev/%k"`. **Observed on 2026-09-27** (`hostclean-0927b-report.md`, Phase P, read-only): `brw-rw---- host:host` on `vm_sys_netvm` (dm-9), `vm_tpl_foundation` (dm-10), `vm_app_web_home` (dm-7), **and on `vm_pool` (dm-6), `vm_pool-tpool` (dm-5), `vm_pool_tdata` (dm-4) and `vm_pool_tmeta` (dm-3)**; `root`, `swap` and `cryptroot` stay `root:disk`. So uid 1000 has read-write access to the rootfs of the most network-exposed VM, to the template every AppVM is snapshotted from, and — through `vm_pool_tdata` and `vm_pool_tmeta` — to the thin pool's raw data and its metadata, **i.e. underneath every thin LV, active or not**. A compromise of uid 1000 on the host is therefore a write primitive on netVM's disk and on the shared foundation. The rule is untracked: no file in the repository names it, and it was found only by enumeration ([`state.md` #42](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md), 2026-09-27). **Its likely consumer is `app_web.con`**, launched as `host`, whose QEMU opens `/dev/vg0/…` directly after a `sudo lvchange`. **That is inferred from the launcher's text, not measured.** | **Kept for now, by operator ruling (2026-09-27)**, recorded here so it is not forgotten again. **The fix belongs to C1** (`User=` in the units, [ADR-027](adr/ADR-027.md) / [ADR-029](adr/ADR-029.md)): discretionary access granted **per LV and per instance** by the unit's privileged `ExecStartPre=+`, for exactly the devices that instance uses, and revoked with it — **never a blanket udev rule**. What removing it would break before C1 lands is not measured. No tracked file installs or names it (`git grep`, 2026-09-27). [`../state.md` open problem **#43**](OPEN-PROBLEMS.md), cross-referenced from **#17**. |
| 17 | **The desktop user can run the alpha launcher as root, without a password** — `/etc/sudoers.d/katmate-launch` grants `host ALL=(root) NOPASSWD: /usr/lib/katmate/katmate-launch`, with any arguments (R151, 2026-10-03). The waybar menu calls it that way. So any process running as the desktop user can start and stop AppVMs, write slot owners, issue NETCFG ADD and REMOVE to netVM, and RUN a whitelisted app in any alpha AppVM. That is the menu's whole capability, with no confirmation and no per-action policy. **Bounded, not removed:** the launcher refuses any uid but 0, takes no path, environment or binary from the caller (`PATH=/usr/bin`, and `ping-client` only as `/usr/lib/katmate/ping-client`, never a build tree, R155), accepts only the four alpha instance names and, per instance, only the apps its layer carries, and reads T1 through `katmate-lib.sh`. Root-owned code then runs on caller-chosen arguments from that small set. | **A dev/alpha shortcut**, beside gap 13. The launch daemon replaces it: a root daemon that orders units, with an unprivileged request interface, so the desktop holds no sudo rule at all (ADR-029, and its note of 2026-10-03). **While gap 13's `katmate-dev` exists, this rule adds no capability on MINIS.** `host` already has `NOPASSWD: ALL`, so the menu working does not show that this rule alone is sufficient, and that is **UNVERIFIED** until `katmate-dev` is removed (R158). Remove it with the launcher. Not present in the installer-provisioned configuration. Staged in the ignored `local/etc/sudoers.d/`, [HOST-CONFIG.md](HOST-CONFIG.md) § 13. **[2026-10-05 (operator ruling R12): superseded. The installer now writes the rule for the user it creates (not `host`), `root:root 0440`, and checks it with `visudo -c`, because the alpha's menu needs it. An installed alpha host has no `katmate-dev` rule (gap 13), so there the rule is the menu's only grant, and the UNVERIFIED sufficiency above is settled by the first menu launch on the Cubi. It is still removed with the launcher. Left as written.]** |
