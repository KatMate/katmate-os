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
  ([ADR-021](DECISIONS.md#adr-021)); a guest can never move its own boundary.
- **Where a boundary is enforced is part of the boundary.** AF_VSOCK limits are
  enforced by the host kernel; a userspace device model substitutes process
  correctness for that enforcement. This is a property to be stated in any ADR
  that moves a device model, never assumed neutral
  ([ADR-027](DECISIONS.md#adr-027), [ADR-028](DECISIONS.md#adr-028)).

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
   rather than gated at runtime ([ADR-021](DECISIONS.md#adr-021)). This is the
   test for **existence** only; see *Three axes of capability control* below.
   Canonical instances: `netvm-agent` cannot decode `RUN`; an AppVM with
   `netvm: None` has no `Link` object; a VM class needing no control channel
   carries no `-device vhost-vsock-device`; netVM carries no `virtio-9p-pci`.
9. **Isolation by topology, not by rule** — network separation is expressed by
   which links exist, not by firewall rules discriminating between AppVMs
   ([ADR-022](DECISIONS.md#adr-022))
10. **Relocation is not removal** — moving a capability across a privilege
    boundary (kernel → VMM, VMM → backend daemon) removes nothing. Its security
    value is *conditional* on the target being more confined than the source,
    and is zero until that is true ([ADR-027](DECISIONS.md#adr-027)).

## Three axes of capability control

Three separate questions, three separate tests. Conflating them dilutes the
first into unfalsifiability ([ADR-027](DECISIONS.md#adr-027)).

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
  ([ADR-028](DECISIONS.md#adr-028)). None of these options removes the channel.
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
([ADR-027](DECISIONS.md#adr-027)).

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
[ADR-004](DECISIONS.md#adr-004)).

sysVMs boot **direct-kernel** with no in-guest bootloader: the boot chain of the
network-facing VM lives host-side, outside the guest image — there is no
in-guest GRUB to rewrite for persistence ([ADR-021](DECISIONS.md#adr-021)).

### VM agents

Two binaries from one workspace, split by **absent-not-disabled**
([ADR-021](DECISIONS.md#adr-021)). A forbidden opcode fails at decode
(`TryFrom<u8>`), not at a runtime gate.

**`vm-agent` (AppVM, uid 1000, unprivileged):**

- VSOCK connections accepted from the host only
- `RUN` restricted to an application whitelist (`firefox-esr`, `foot`, `nautilus`)
- `FILEGET`/`FILEPUT` restricted by path whitelist and transfer size limits
- No arbitrary command execution path
- **Contains no network-configuration code** — the least-trusted guest cannot
  even *name* the NETCFG opcode

**`netvm-agent` (sysVM, `CAP_NET_ADMIN` + `CAP_KILL`, not root):**

- **Contains no `RUN`, no `FILEPUT`/`FILEGET`** — no general execution path
  exists inside the process holding network privilege
- `NETCFG` is a **typed link description**, never a shell string and never a
  policy ([ADR-023](DECISIONS.md#adr-023)): interface match, local/peer address,
  `/32` prefix, route, metric; `add` / `remove` only, no `modify`. It cannot
  deliver an nft rule and cannot alter the baked firewall. Validation is
  structural and total — malformed payloads are rejected, never sanitised.
- **`SHUTDOWN` (0x05) IS present, and carries `CAP_KILL`** — corrected
  2026-07-18 ([ADR-024](DECISIONS.md#adr-024)); the earlier "no SHUTDOWN, no
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
  come and go ([ADR-021](DECISIONS.md#adr-021)).
- Differentiated network access is expressed as **attachment to a different
  netVM** (each netVM image bakes one immutable policy), never as a per-AppVM
  rule ([ADR-022](DECISIONS.md#adr-022)).
- An AppVM with `netvm: None` has **no link at all** — air-gap is the absence of
  an object, not a rule denying traffic.
- The netVM image bakes **no internal topology**: on a clean boot it has no
  internal route. Routes exist only for running AppVMs.

### GUI forwarding

Waypipe over VSOCK — no network listener, no X11 surface. Host side is a
socket-activated systemd *user* service (unprivileged).

### Desktop compositor

The host compositor is **inside the TCB**: it draws the domain indicator that
visually separates domains. The indicator must be keyed on **waypipe CID
identity**, i.e. host-side trusted state — never on guest-controlled properties
(`app_id`, window title are spoofable). This is why a single audited profile
(Sway) ships, rather than two ([ADR-016](DECISIONS.md#adr-016)).

The identity path is **two host-side steps and no guest input**
([ADR-026](DECISIONS.md#adr-026)): the compositor supplies the window's `pid`,
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
either machine type ([ADR-027](DECISIONS.md#adr-027) C4).

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
  invoking user. Gap #11; C-gate in [ADR-027](DECISIONS.md#adr-027).

Until the second is closed for netVM, "minimal TCB" describes the intent of
this design and only partly its current state. **netVM does not require a root
VMM** — the three privileged steps (vfio node, TAP creation, LVM activation)
are launcher-side and drop before `exec qemu`; the only real obstacle is
`RLIMIT_MEMLOCK`, which is configuration.

The domain indicator adds one host-kernel dependency: AF_VSOCK socket
diagnostics (`vsock_diag`), used to resolve a window's pid to a guest CID
([ADR-026](DECISIONS.md#adr-026)). Without it the indicator has no trustworthy
identity source.

## Known gaps (tracked)

| # | Gap | Status / remediation |
|---|---|---|
| 1 | **Secrets committed in installer scripts** — WireGuard private key, WiFi SSID+PSK, default user credentials | Critical hygiene gap. The committed WG key is considered burned and must be rotated. Replace with install-time prompts / `wg genkey` generation. v0.2 blocker. |
| 2 | Hidden SSID + AutoConnect forces clients into active probing — the machine broadcasts the network name everywhere | Switch to a visible SSID; drop `Hidden=true`. |
| 3 | ~~VPN terminates on the host, contradicting the NetVM target architecture~~ | **Resolved (live on MINIS):** WireGuard/ProtonVPN now terminates in NetVM per [ADR-009](DECISIONS.md#adr-009). Host carries no VPN. |
| 4 | **SSH open on development host** — `tcp dport 22 accept` active on MINIS (dev convenience, not installer default). sshd also runs inside netVM (CID 3). | Both are dev-only. Restrict the host rule to LAN (`iif enp195s0f3u1u1 ip saddr 10.3.1.0/24`) and remove both before release. Not present in the installer-provisioned ruleset. |
| 5 | No base image signing / integrity verification | [ADR-013](DECISIONS.md#adr-013) (Proposed). |
| 6 | No Secure Boot chain | Consistent with threat model (see above); revisit at v1.0. |
| 7 | **VPN key co-located with the NIC driver** — in v1 the WireGuard private key and the `r8169` driver + non-free Realtek firmware blob share one address space. Compromise of the most exposed code in the system (hardware-facing driver) is compromise of the VPN credentials. | Accepted for v1; the model already permits the fix. Post-v1: split into a **driver domain** (q35, hardware, no secrets) and a **proxy netVM** (microVM, secrets, no hardware) — [ADR-022](DECISIONS.md#adr-022). |
| 8 | **Proxy sysVMs will add `CONFIG_WIREGUARD` + netfilter to the shared MicroVM kernel**, which all AppVMs also run. The code is unreachable from an AppVM (uid 1000, no `CAP_NET_ADMIN`) but is *present* — a departure from absent-not-disabled at the kernel level. | Accepted consciously ([ADR-021](DECISIONS.md#adr-021) rejected a second kernel: doubled config maintenance, firmware-licensing issues for ISO distribution). Revisit if a second kernel becomes cheap. |
| 9 | **IOMMU-group quality is a hard requirement, unverified at install time.** A driver domain is only safe where the NIC is cleanly isolable; a bad grouping silently weakens passthrough isolation. | HCL + installer preflight check ([ADR-022](DECISIONS.md#adr-022)); on the ROADMAP, not a v1 code blocker. |
| 10 | ~~**9p hostshare into netVM** — `net-sys.con` carried `virtio-9p-pci` with `security_model=none` sharing `/home/host` into the most network-exposed VM~~ | **Resolved (2026-07-28):** `-fsdev` and `-device virtio-9p-pci` removed from `net-sys.con`. Verified host-side: the running VMM's `/proc/<pid>/cmdline` contains neither. C5b in [ADR-027](DECISIONS.md#adr-027). If a dev file path is ever needed again it must be a narrow subtree with `security_model=mapped-xattr`, in a **separate dev launcher**. |
| 11 | **netVM VMM runs as root, unconfined.** `net-sys.con` is invoked with `sudo`; the QEMU process has no chroot or Landlock ruleset, sits in `init_netns`, and receives `memlock` from an interactive `ulimit -l unlimited` rather than a unit. Compromise of this process is, in practice, compromise of the host. Does **not** apply to `app_web.con`, where QEMU runs as the invoking user and `sudo` covers only `lvchange`. | Largest remaining privilege item in the TCB. C-gate in [ADR-027](DECISIONS.md#adr-027): C4 and C5b passed 2026-07-28; C1–C3 are the launch daemon's privilege split; C5a is a `setpriv`-style Landlock wrapper (no QEMU patch needed — Landlock rulesets are inherited across `execve`); C6 is per-VM netns. **Blocks all axis-2 work.** |
| 12 | **vsock CID space is global on the host.** Any host process can reach any VM's agent on port 1025; the waypipe host user service can reach netVM's agent although it has no reason to. | Linux 7.0 makes vsock namespace-aware (`vhost-vsock` + `vsock_loopback`); available on the current MINIS host kernel. Per-VM netns with `child_ns_mode=local`. Note `child_ns_mode` is **write-once** and `ns_mode` immutable after namespace creation — a daemon-start decision, not a runtime toggle. Couples to [ADR-026](DECISIONS.md#adr-026): with CID reuse, indicator identity becomes **(netns, CID)**, not CID. C6 in [ADR-027](DECISIONS.md#adr-027); mechanism in [ADR-028](DECISIONS.md#adr-028). |
| 13 | **Passwordless root on the development host** — `/etc/sudoers.d/katmate-dev` grants `host ALL=(ALL) NOPASSWD: ALL` on MINIS. | Dev-only, added 2026-08-11 so delegated agent sessions can run root steps over ssh, where an interactive `sudo` prompt is not a prompt the session can see but a silent hang. Compounds gap 4 — ssh plus NOPASSWD collapses network reach and root into one step — and removes the last interactive checkpoint in front of gap 11's root-unconfined VMM. Remove the file before release. Not present in the installer-provisioned ruleset. |
| 14 | **A datagram-backed link cannot represent an absent peer.** Under [ADR-033](DECISIONS.md#adr-033) a link is a pair of AF_UNIX datagram sockets, and a datagram socket has no carrier: the guest's interface shows link-up whether or not anything is on the other end, and its `sendto` succeeds identically either way — measured 2026-08-24 on MINIS (`~/link-m2-report.md` § B2.2), where the same guest returned `rc=18, errno=0` on every frame across a peerless window and a peered one, with QEMU writing zero bytes to stderr throughout. A tap backend can signal link-down; this cannot. | **A property of the decision, not a defect in it** — the alternative that carries link state is the tap and bridge topology ADR-033 rejects on other grounds, and the property is recorded there under costs accepted. The consequence is a requirement on the host: **start ordering is the launch daemon's responsibility alone, and the guest cannot assist** — a guest cannot detect that its netVM is absent, so nothing in the guest may be relied on to notice. Revisit only if the backend changes. |
