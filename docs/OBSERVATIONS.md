# Observations

Publicly available material that bears on decisions recorded in
`docs/DECISIONS.md`. Append-only, newest first.

## What this file is for

Decisions in this project are made at a point in time, on the
information available then. This file records what has been published
**since**, and what it says about those decisions — so that a decision
can be re-examined without re-doing the research.

## Conventions

- **The subject of every entry is one of our decisions**, not another
  project. An entry reads *"decision X was taken for reason R; here is
  what has since been published about R"* — never *"project Y got it
  wrong"*.
- **Our own stack is held to the same standard.** Material about QEMU,
  the Linux kernel and waypipe is recorded in the same tone and the same
  detail as material about anything else. An entry set that only
  documents other people's defects is not an observation log, it is an
  argument, and it will mislead the reader who wrote it.
- **No comparative judgement.** Where two projects have taken different
  paths, record both paths and the constraint that separates them. Do
  not rank them.
- **Provenance is mandatory.** Every claim carries its source and date.
- **Confidence markers:** `[V]` verified at a primary source ·
  `[S]` secondary source only · `[H]` hypothesis, unproven.
- Corrections to our own earlier statements belong in `docs/SESSIONS.md`
  (session record), not here. This file holds external material only.

---

# 2026-08-24

## 1. KatMate's network backend is one this tree exercises nowhere else — bearing on ADR-033

**Decision under review:** [ADR-033](DECISIONS.md#adr-033) — a link is a pair
of AF_UNIX datagram sockets, carried by QEMU's `-netdev dgram`.

**`[V]` `dgram` is the only network backend in this project that no other
component uses.** Every `-netdev` in the repository is `tap`: `net-sys.con:26`
and `host/usr/lib/systemd/system/katmate-sys-driver@.service:137`, both netVM's
internal segment. `app_web.con` carries no network device of any kind — the
finding that renamed ADR-030's gate G2. So every gate this project has run
against a network backend has run against `tap`, and ADR-033 selects one with
no gate history here at all.

**`[V]` The backend is reachable from the guest's virtqueue.** Measured
2026-08-24 on MINIS, QEMU 11.1.0 (`~/link-m2-report.md` § B2.4): a guest wrote
to its `virtio-net-device` and the bytes arrived on the host's socket as a
complete ethernet frame — broadcast destination, the `mac=` given to the
frontend as source, IPv4, UDP 4242 → 4242, payload intact. Guest-controlled
bytes reach this code path by design; that is what a network backend is.

**`[V]` The choice was made for stated properties, not by default.** ADR-033
records them and the measurements behind them: a slot with no peer starts
silently and costs one fd and no thread, the address is resolved per send so a
peer may appear afterwards, and an AppVM's start path needs no privileged
network step. The alternatives were weighed in the ADR against the model, not
discovered to be unavailable.

**What this says about our decisions.** Nothing here is a claim about how well
exercised `dgram` is in QEMU generally — this project has no source for that and
none was gathered, so no such claim is made. What is checkable and is recorded
is narrower and is the part that bears on us: **our own gate history covers
`tap` and does not cover this backend**, on a code path guest bytes reach.
ADR-033's M2 is a saturation measurement and not a robustness one, so it does
not close this either.

## 2. QEMU 11.1.0's printed synopsis and its runtime disagree, from one binary — bearing on ADR-033

**Decision under review:** [ADR-033](DECISIONS.md#adr-033) — every link slot
names a peer path whether or not the peer exists.

**`[V]` The synopsis brackets `remote` as optional.** From
`qemu-system-x86_64 -help` on MINIS, verbatim
(`~/link-m1-report.md` § 2c, 2026-08-24):

```
-netdev dgram,id=str,local.type=unix,local.path=path[,remote.type=unix,remote.path=path]
```

**`[V]` The same binary refuses it as mandatory.** A `local`-only invocation
exits 1 with nothing started (§ 10):

```
qemu-system-x86_64: -netdev dgram,id=n0,local.type=unix,local.path=…: type=inet or type=unix requires remote parameter
```

**`[V]` Per-type help does not exist in this version**, for `dgram` or for
`stream`: `-netdev dgram,help` returns *"Help is not available for this
option"*, rc=1 (§ 2b). So the printed synopsis and the parse errors are the
only option documentation the binary offers, and they do not agree with each
other.

**`[V]` The `local.type=fd` form is the one the error does not name**, and is
therefore the only `local` form for which the optional bracket may hold. It was
not run and nothing is claimed about it (§ 10).

**What this says about our decisions.** **KatMate treats the runtime refusal as
authoritative over the printed synopsis** — a document describes and a runtime
decides, and where they disagree only one of them is what will happen. ADR-033's
slot therefore always names a peer path, which costs nothing since the path need
not exist. The general form is the rule this project already applies to its own
documents: where an ADR and the tree disagree, the disagreement is the finding
and neither side is automatically right. Worth reporting upstream; not reported
by this session.

---

# 2026-07-28

## 1. Asynchronous block I/O — bearing on the `aio=threads` choice

**Decision under review:** VM launchers use `aio=threads`
([ADR-004](DECISIONS.md#adr-004), live on MINIS since 2026-07-23). The
immediate cause was `kernel.io_uring_disabled = 2` on `linux-hardened`,
with the secondary reasoning that io_uring is defect-dense and this path
runs host-side driven by guest I/O patterns.

**`[V]` The hardening default is common enough to be designed around.**
Cloud Hypervisor's v52.0 release notes (2026-05-14) describe fixing an
AIO-backend regression specifically for "hosts with io_uring disabled
(e.g. RHEL 9 / CentOS Stream 9, where `kernel.io_uring_disabled=2` is a
common hardening default)". This is useful independent of anything else:
the configuration this project arrived at through `linux-hardened` is
a recognised hardening posture that upstreams accommodate deliberately.

**`[V]` Async block completion paths have produced escape-class defects.**
CVE-2026-45782 (Cloud Hypervisor 21.0 to before 51.2, CVSS 8.9,
published 2026-06-09): a guest submits two virtio-block descriptor
chains reusing the same `head_index` while asynchronous block I/O is
enabled (io_uring or aio); when the kernel completes the duplicate
before the original, the completion path frees a bounce buffer the
kernel is still reading from or writing to. Patched in 51.2 and 52.0.

**`[V]` A second defect in the same component in the same year.**
CVE-2026-27211 (Cloud Hypervisor 34.0 through 50.0, fixed in 50.1):
virtio-block devices backed by raw images could be induced to expose
arbitrary host files to the guest, bounded by process privileges.

**`[V]` A downstream consumer went further than the upstream fix.**
A Spectrum patch (2026-05-21, Demi Marie Obenour) adds `disable_io_uring`
and `disable_aio` to its `DiskConfig` — fully synchronous I/O — with the
rationale that the async block path's attack surface remains higher than
the synchronous code even after the upstream fix. Merge status
**unconfirmed** from public archives.

**`[V]` Our own stack has an escape-class device-model defect on record
in the same window.** A published exploit write-up (osec.io, 2026-03-17)
develops an uncontrolled heap overflow in QEMU's **virtio-snd** device
into a reliable guest-to-host escape, targeting QEMU commit
`ece408818d27` (2026-02-13) against glibc 2.43. No CVE identifier
captured; the write-up is the primary source.

**What this says about the decision.**

1. `aio=threads` is not merely a constraint inherited from
   `linux-hardened`. QEMU's `threads` backend is a distinct and older
   code path from both io_uring and Linux AIO, and the material above is
   consistent with async completion paths being the harder ones to get
   right. The choice stands on its own reasoning.
2. **It says nothing about QEMU being safer in general.** The virtio-snd
   write-up is the counterweight and belongs in the same paragraph: our
   VMM's device models have produced guest-to-host escapes in the same
   period. What follows is not "we chose the safe VMM" but "device
   models are the escape surface, ours included" — which is the argument
   for [ADR-027](DECISIONS.md#adr-027), not against it.
3. **It independently supports a decision we had already parked for
   other reasons.** The audio design (VSOCK port 1026, `snd-aloop` plus a
   thin daemon feeding PipeWire on the host) means **no `virtio-snd` in
   the device set**. That was chosen for architectural cleanliness. It
   also happens to remove the exact device implicated above. Worth
   stating explicitly, because it is the cheapest kind of confirmation:
   a device that is absent cannot be exploited.

---

## 2. Host-side vsock API differs by VMM — bearing on ADR-003 and ADR-028

**Decision under review:** [ADR-003](DECISIONS.md#adr-003) fixes
`AF_VSOCK` as the exclusive host↔guest channel. The question raised was
whether that decision constrains the choice of VMM.

**`[V]` It does, and the constraint is not visible in feature
comparisons.** Two host-side models exist for virtio-vsock:

- **Kernel `vhost-vsock`** — host applications use `AF_VSOCK` directly.
  Used by QEMU and crosvm. crosvm's documentation notes that its
  in-tree virtio-vsock device is Windows-only; on Linux it uses
  vhost-vsock and delegates to the kernel, assuming `/dev/vhost-vsock`
  (overridable via `--vhost-vsock-device` / `--vhost-vsock-fd`).
- **Hybrid** — the host side is `AF_UNIX` with in-band text framing.
  Used by Firecracker and Cloud Hypervisor.

**`[V]` The hybrid protocol, from Cloud Hypervisor's `docs/vsock.md`:**
its `virtio-vsock` is explicitly based on the Firecracker
implementation. Host → guest: connect to the launch-time Unix socket and
prefix the stream with `CONNECT <port>`, sent once per connection.
Guest → host: the host listens on a Unix socket whose path is the
launch-time path with `_` and the port number appended (`/tmp/ch.vsock`
→ `/tmp/ch.vsock_1234`); the guest dials the well-known CID 2.

**`[V]` One documentation inconsistency, worth knowing before any
trial.** The same document lists `CONFIG_VHOST_VSOCK` under host kernel
requirements, which does not follow from the hybrid model it then
describes. rust-vmm states the opposite for the same design — no need to
load the `vhost-vsock` kernel module, which *is* required for standard
vsock in QEMU. The requirements line is most likely stale.

**`[V]` Provenance of the "no host vsock support needed" claim.**
rust-vmm frames this as a convenience — testing vsock applications
without host vsock support, and Firecracker protocol compatibility — not
as a security property. Any security reading of it is an inference, not
a citation.

**What this says about the decision.** ADR-003 is a real constraint on
VMM choice and the deciding factor is `waypipe`, not device support:
waypipe speaks `AF_VSOCK` on the host, so a hybrid-model VMM requires
either a proxy inside the TCB on the GUI channel or a behavioural fork
of waypipe. This is recorded in [ADR-028](DECISIONS.md#adr-028) as the
criterion to apply if the VMM question is ever reopened. It is not a
quality judgement about any VMM: hybrid vsock is a reasonable design for
its intended context, which is not this one.

---

## 3. vsock network namespaces — Linux 7.0

**Decision under review:** none yet; this is new capability bearing on
`SECURITY-MODEL.md` gap #12 and on
[ADR-026](DECISIONS.md#adr-026)'s identity model.

Primary source: Stefano Garzarella (co-author), 2026-02-11, updated
2026-04-17. Series: *vsock: add namespace support to vhost-vsock and
loopback*, v16, Bobby Eshleman (Meta), sixteen revisions.

**`[V]` Mechanism.** Two modes, per network namespace:

- `global` — CIDs shared across namespaces. **Default**, matching pre-7.0
  behaviour. `init_netns` is always `global`.
- `local` — full isolation; sockets communicate only within the same
  namespace.

Two sysctls:

- `/proc/sys/net/vsock/child_ns_mode` — mode inherited by *new child*
  namespaces, `global` | `local`. **Write-once**: the first write locks
  the value, and a differing subsequent write returns `-EBUSY`. The
  stated rationale is to prevent two administrator processes racing and
  leaving a namespace in the wrong mode.
- `/proc/sys/net/vsock/ns_mode` — read-only; mode of the current
  namespace, immutable after creation.

**`[V]` Covered transports:** `vhost-vsock` (H2G) **and**
`vsock_loopback` (local). This is what makes
[ADR-028](DECISIONS.md#adr-028) H1 plausible.

**`[V]` Not covered:** G2H transports (virtio, hyperv, vmci). These run
in the guest as device drivers and there is no way yet to assign a vsock
device to a namespace. They operate in `global` mode: a `local`
namespace *inside a guest* cannot reach the host.

**`[V]` Worked QEMU behaviour**, from the same source: a VM launched with
`ip netns exec <ns> qemu-system-x86_64 … -device vhost-vsock-pci,guest-cid=42`
in a `local` namespace is unreachable from `init_netns` (connection
reset) and reachable from within the namespace. Two VMs may hold **the
same CID** in different `local` namespaces; under `global` the second
fails to start.

**What this says about our decisions.** It offers a kernel-enforced fix
for gap #12, on the host kernel already running (7.0.12-arch1-1). It
also introduces a coupling that must not be discovered late: **if CIDs
may repeat, the domain indicator's identity is (netns, CID), not CID**
([ADR-026](DECISIONS.md#adr-026)). Both are tracked as C6 in
[ADR-027](DECISIONS.md#adr-027).

---

## 4. `vhost-user-vsock` availability in QEMU

**Decision under review:** [ADR-028](DECISIONS.md#adr-028) placement 3.

**`[V]` The device exists in QEMU** and has since v5.1
(`vhost-user-vsock-pci`, `-chardev socket,…`), with the rust-vmm
`vhost-device-vsock` crate as the backend.

**`[V]` The mmio variant exists**, per QEMU's vhost-user documentation:
each device has both a `virtio-mmio` and a `virtio-pci` variant.

**`[V]` The combination has shipped on a microvm-derived machine type.**
QEMU's `nitro-enclave` machine type — based on `microvm` — instantiates
`vhost-user-vsock` over `virtio-mmio` in mainline (`hw/i386/nitro_enclave.c`
includes both `hw/virtio/virtio-mmio.h` and `hw/virtio/vhost-user-vsock.h`
and walks the mmio bus via `find_free_virtio_mmio_bus()`). This removes
"does the mmio variant work on a microvm-class machine" from the
hypothesis list; H2 (instantiation on *our* machine type and guest
kernel) remains open.

**`[V]` Backend modes.** `vhost-device-vsock` supports two host-side
backends: UDS (Firecracker-compatible hybrid) and `--forward-cid`
(feature `backend_vsock`, enabled by default), which does direct
`AF_VSOCK` ↔ `AF_VSOCK` — guest connections are forwarded to a given CID
on the host, and the host application listens over `AF_VSOCK`.

**`[V]` Generic vhost-user properties.** The backend runs as a separate
process connected to the VMM over a Unix socket. This allows a narrower
seccomp filter than the VMM's, and permits a privileged device process
while the VMM itself stays unprivileged. It requires **shared guest
memory**: the backend maps the guest address space to read virtqueue
descriptors. Not vsock-specific — the entry price for any vhost-user
backend.

**What this says about our decisions.** Placement 3 is reachable without
changing VMM, and `--forward-cid` preserves ADR-003. It is gated behind
the C-gate, because a backend daemon that is not confined is a lateral
move rather than an improvement ([ADR-027](DECISIONS.md#adr-027)).

---

## 5. Cross-project material — Spectrum

Recorded where it bears on our open questions. Both projects are
building compartmentalised desktops on Linux with different constraints;
nothing here is a comparison.

**`[V]` Lexical path validation without symlink resolution, 2026-07-22.**
Demi Marie Obenour reported on the Spectrum devel list that
`/run/vm/by-id/${VM}` is writable by the VMM, that code operating in that
directory is not secure against symlink attacks, and proposed either
withdrawing write access or mounting a subdirectory `nosymfollow`.

*Bearing on us:* the same class as our open question about
`path_is_allowed` in `vm-agent` (`state.md` Open problem #13). It gives us
a second candidate remedy — a `nosymfollow` mount on the exposed subtree
— alongside in-code resolution with `openat2(RESOLVE_BENEATH)` or
canonicalise-then-check. Our own instance remains **unverified**; the
external report raises its prior, it does not confirm it.

**`[V]` dm-verity for sub-VM roots, 2026-07-03.** A Spectrum series boots
app VM and net VM roots through dm-verity over EROFS and enables the IPE
(Integrity Policy Enforcement) LSM.

*Bearing on us:* a concrete reference implementation for the problem
[ADR-013](DECISIONS.md#adr-013) (base image signing and integrity
verification) leaves Proposed, and for gap #5. Worth reading before that
ADR is promoted.

**`[V]` Router placement.** Spectrum forwards packets from a network
driver VM via XDP into a host userspace router (`spectrum-router`), with
the stated intention of moving routing into a VM later. We terminate
routing, nftables and WireGuard inside netVM, with the host holding only
topology (`Link`, TAP, `/32`).

*Bearing on us:* none directly — recorded because it is a different
point on the same design path, and because the stated direction of
travel matches ours.

**`[V]` A shared unsolved problem: USB NICs.** Same list, 2026-05-21:
many current laptops have no RJ45, Ethernet arrives via USB adapters, and
Linux USB core and the xHCI driver are not hardened against malicious
input, so a userspace driver on the router is not currently a safe
option.

*Bearing on us:* we have the same exposure — the MINIS host uplink is a
USB NIC (`enp195s0f3u1u1`, r8152) — and no better answer. Recorded as an
open problem shared by the field rather than as a defect of either
project.
