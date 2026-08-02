# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**2026-07-23 (ADR-025 CLOSED — NETCFG live-gated; netvm-agent functionally
complete).** `handle_netcfg` was the last ERR stub in the agent; all three
opcodes (PING / NETCFG / SHUTDOWN) are now implemented and live-gated. Path B
(rtnetlink) carried out per the 07-21 E-gate.

**Method — golden fixtures.** Before any code, the bytes iproute2 sends over
`AF_NETLINK` were captured (`strace -e trace=sendmsg`, dummy iface, local
10.100.1.1 peer 10.100.1.2/32 metric 100). Five shapes: `RTM_NEWADDR` 40 B,
`RTM_NEWLINK` 32 B, `RTM_NEWROUTE` 52 B, `RTM_DELROUTE` 52 B, `RTM_DELADDR`
40 B. Each is pinned by a unit test comparing the encoder's output against the
capture. "Did I build the message correctly" is therefore PROVEN against a
reference implementation rather than remembered from a header — the ADR-024
method applied to code.

Two structural findings from the capture: `IFA_LOCAL` = local, `IFA_ADDRESS` =
**peer** (the p2p form matches the ADR-025 payload with no translation; the E5
`/24` form would install a connected route for the whole segment and break
"REMOVE → state gone"); and DEL uses a **wildcard body** (`RTPROT_UNSPEC` /
`RT_SCOPE_NOWHERE` / `RTN_UNSPEC`), it does not mirror ADD.

**Empirical finding that corrects the ADR-025 gate.** A peer address installs
the kernel's own route to the peer (`10.100.1.2 proto kernel scope link src
10.100.1.1`, metric 0). Consequences: (a) in v1 the payload's route is
ADDITIVE, not what carries reachability — the kernel's lower metric always
wins; (b) the gate criterion "a route to the peer is visible" is TOO WEAK — it
would pass even if `RTM_NEWROUTE` had never been sent. The gate must assert the
line bearing `metric N`. (c) Teardown is complete without extra work:
`DELADDR` takes the kernel's route with it.

**Dependency call: hand-rolled, not a crate.** The first possible runtime
dependency in the only privileged agent (CAP_NET_ADMIN + CAP_KILL, sharing an
address space with r8169 + the Realtek blob + the v1 WG key). The deciding
inversion: the netlink UAPI is frozen by kernel contract, the crate APIs are
not (`netlink-packet-route` broke across 0.17/0.19/0.21, `neli` across
0.6/0.7, `rtnetlink` is async-only → a tokio runtime in a binary serving one
synchronous request at a time). A crate does not remove netlink semantics, it
relocates them and adds churn. Same conclusion as the non-serde wire. The
multipart `RTM_GETLINK` dump — the one genuinely hard part of netlink — drops
out: MAC→ifindex resolution goes through sysfs.

**Code.** `netlink.rs` (~350 lines, 5 `unsafe`: socket/sendto/recvfrom/close/
zeroed — the same class as `libc::kill`): five message builders, an `NlSocket`
owning its sequence counter, reply validation on two axes (`nl_pid == 0` =
from the kernel, sequence match), and an errno policy following the
convergence contract (`EEXIST` on ADD → OK, `ESRCH`/`ENOENT`/`EADDRNOTAVAIL`
on REMOVE → OK, `ENODEV` = retryable ERR). `netcfg.rs`: total validation per
the ADR-025 table, the record set under `RuntimeDirectory=`, convergent
ADD/REMOVE. `ping-client`: `netcfg-add` / `netcfg-remove`, plus repair of
stale comments claiming netVM does not implement SHUTDOWN (ADR-024 reversed
that on 07-18).

Byte order (implementation reading of ADR-025): LE governs GENUINE INTEGERS
(`link_id`, `metric`); addresses and the MAC are byte arrays in network order,
the same class of field as `match_mac`. Consequence: there is NO address
conversion anywhere in the privileged path — and therefore none to get wrong.

**Live gate — 7/7.** All five ADR-025 criteria plus two extra:

| criterion | result |
|---|---|
| ADD → address + route + UP | OK; `10.100.1.2 scope link metric 100` visible |
| identical re-ADD | OK |
| conflicting ADD (same id, different peer) | ERR |
| REMOVE of an absent id | OK |
| REMOVE → state gone | OK; `enp0s5` has no IPv4, record dir empty, iface still UP |
| RUN aimed at netVM | ERR (absent-not-disabled, on the fresh binary) |
| ADD naming the uplink's OUI MAC (`38:05:25:34:7c:47`) | ERR (structural fence, rejected in the parser) |

The last one is quiet but load-bearing: across seven operations — including one
that named the uplink's MAC explicitly — `enp0s4` never moved (DHCP lease
`10.3.1.110` untouched). The agent does not know which MAC the uplink has; one
bit test makes it unreachable.

**19 unit tests** (2 op + 7 netlink + 10 netcfg), all green.

**Rebuild.** `vm_sys_netvm` rebuilt from a clean `netvm.sh`, KVER
**6.12.96+deb13-amd64** (was 6.12.95). Boot clean: `landlock: Up and running`,
`crng init done` @ 0.010s, `PF_VSOCK registered`, `getty-static … because dbus
and logind are not available` (the manifest stays dbus-free). SHUTDOWN
regression passed on the new kernel. The agent binary in the image was
ultimately replaced BY HAND (mount + install), not by a rebuild — see debt #14
below.

Next architectural piece: the **launch daemon** (owns the graph; allocates CIDs
and `/32`s, orders `device_add` before NETCFG, refuses to tear down a VM with
live dependents). ADR-sized, thinking-on.

**2026-07-21 (E-gate — NETCFG mechanism RESOLVED, Path B).** ADR-025's
E1–E5 run live on `vm_sys_netvm` (root unlocked via offline chroot
`passwd`, dev-only, image otherwise untouched — `passwd -l root` still the
release state). Internal netdev confirmed: `enp0s5`, MAC
`52:54:0a:64:01:01`, **`unmanaged`** by networkd (only `20-uplink.network`
baked, matching `enp0s4` uplink) — the load-bearing fact for Path B.
**Result: Path A dead on all three trigger probes, Path B proven.** E1:
`networkctl reload` inert (`Failed to connect to system bus` — no dbus, the
ADR-021-class precondition failure). E2: the varlink surface
`/run/systemd/netif/io.systemd.Network` **exists** (introspected via
`varlinkctl`, world-writable `srw-rw-rw-`) but exposes **no config-mutation
method** — only `GetStates`/`GetLLDPNeighbors`/`GetNamespaceId`/
`SetPersistentStorage` (the last returns `StorageReadOnly` on the RO image).
Stronger than the predicted "absent": surface present, introspected,
provably no reload. E3: `Type=notify-reload` promised a signal path, but
`SIGRTMIN+1` to networkd **kills it** (`code=killed, status=35/RTMIN+1` →
systemd restart), not a reload — empirics overriding introspection, the
ADR-021 trap avoided. E5: a full Path-B dry run under the agent's exact
profile (`setpriv --reuid nobody --inh-caps +net_admin --ambient-caps
+net_admin` — the ADR-024 E8 both-sets pattern) drove `ip addr add
10.100.1.1/24` + `ip link set up` + `ip route add 10.100.1.2/32` on
`enp0s5`, all `=0`, `UP,LOWER_UP`, no bus/DAC/root. Decision rule (A iff
(E1∨E2) trigger ∧ E4): no trigger → **B**, exactly as ADR-025 predicted. E4
(DAC) moot, not tested. Next: `handle_netcfg` (thinking-on/Fable session —
includes the hand-rolled `RTM_*` vs netlink-crate dependency call, ADR-025
§ mechanism). Aside: `SIGRTMIN+1` to networkd is a config-plane DoS
(kill+restart) — noted, immaterial to the trust model (agent already holds
`CAP_NET_ADMIN`).

**2026-07-20 (design session — ADR-025 NETCFG payload):** the NETCFG wire
contract ADR-023 left abstract is now fixed. **Wire:** fixed binary layout,
opcode `0x06`, count-prefixed bounded route array (`route_count 1..=4`); no
version byte (new shape → new registry value); byte order deferred to
`katmate-protocol::frame`. Locally-administered MAC check = structural uplink
protection; `local_addr == 10.100.1.1`, `peer ∈ 10.100.1.0/24 /32`. **Semantics:**
idempotent per host `link_id`; **convergence, not rollback**; state is the
filesystem, boot-scoped under `/run`; **act-first / reply-second** (mirror of
ADR-024). **Mechanism deferred, E-gated** (Path A networkd-fragment vs Path B
rtnetlink; E1–E5 next session decide — ADR-024 method, since ADR-021's shutdown
died of an assumed mechanism precondition; predicted winner B, no dbus for
`networkctl reload`). Done: ADR-025 committed; ADR-021 status line repaired;
`net-sys.con` **committed for the first time** (`f5f8ef2` — was MINIS-only since
07-09, invariant breach now closed) with a static internal netdev (tap `tap-int0`
+ `virtio-net-pci`, MAC `52:54:0a:64:01:01`); host-side `tap-int0` persisted via
networkd. (Forensic aside: the retired pet netdev MAC `52:54:0A:64:11:01`
byte-encoded `10.100.17.1` — the wrong-subnet bug the pet's nftables carried,
preserved in the MAC; the new MAC encodes `10.100.1.1` correctly.) Next:
boot → confirm guest sees the netdev → E1–E5 → `handle_netcfg` +
`ping-client netcfg-*` → minimal live gate.

**2026-07-20 housekeeping:** vm_sys_netvm actually rebuilt from clean
netvm.sh today (dm-17 open-flag needed host reboot first); acpid/dev-root/
ffc08537 remnants gone only now, not 07-18. Stale vm_tpl_net_root +
vm_net_overlay.qcow2 removed. netvm.sh export-block dedupe (9149e17).

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

**As of 2026-07-28 the focus has moved to the host side of the TCB.** The netVM
control path is no longer the open question — `netvm-agent` is live-gated
through NETCFG and SHUTDOWN (ADR-024, ADR-025), and the paragraph above is kept
only as the historical framing of how the track was entered. What is open now
is the **VMM process itself**: ADR-027 defines a containment gate (C-gate) of
which C4 (tightened seccomp) and C5b (no host filesystem export into netVM)
passed the same day, leaving C1–C3, C5a and C6 attached to the launch daemon.
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

## This session (2026-08-02) — ADR-029: systemd owns the VMM process; four constraints re-examined and gone

Architecture session (thinking-on) plus four live gates on MINIS. Scope was
deliberately one question and nothing else: **who is the parent of the QEMU
process.** Everything downstream — privilege split, allocation, netns — was
treated as consequence, not as co-equal design surface.

### Decided

- **ADR-029 — the launch daemon orders units; systemd owns the VMM process.**
  The daemon never `fork`s or `exec`s a VMM. Each VM is a systemd unit; PID 1
  is the parent; the unit name and its cgroup are the durable identity. The
  daemon retains everything the five prior ADRs assign it (graph, CID
  allocation, NETCFG ordering and re-issue, CID→name, dependent-VM interlock)
  and may die at any moment without any running VM noticing.

### The four constraints, re-examined

The question was reached by counting 4:1 in favour of daemon-as-parent. The
count was not a weighing. Three of the four dissolve against the ADRs they were
drawn from; the fourth was a question about a device that does not exist.

| Constraint | Outcome |
|---|---|
| pid↔CID (ADR-026) | dissolves — `vsock_diag` resolves pid→CID in the kernel; the daemon's part is CID→name, persisted state |
| `_is_alive` (ADR-017) | dissolves — ADR-017 already offers "active vsock endpoints for those CIDs". A live control endpoint **is** liveness here |
| `child_ns_mode` write-once (C6) | measured, leaves the column — the write is in a *parent* namespace, children inherit at creation; produces a **named** namespace, not a descriptor |
| TAP as `fd=` (C2) | dissolved by inspection — `app_web.con` carries **no network device at all** |

### The argument that decided it, on neither list

Daemon-as-parent makes the identity of a running VM a process relationship. On
daemon death or update the QEMU processes survive (reparented) — that is not
the problem. The problem is that the new daemon is not their parent: `waitpid`
is gone, and reconstruction through a persisted pid + `pidfd_open` reintroduces
**pid reuse**, the exact race ADR-017's monotonic counter and full-cycle
`flock` exist to eliminate. Under C6 it is worse: identity is **(netns, CID)**
(ADR-028), and an anonymous namespace held as a descriptor from
`/proc/<child>/ns/net` dies with the daemon — the half that cannot be recovered
by name. This project ships security updates; a model where
`systemctl restart katmated` requires stopping every VM is a design defect.

systemd is PID 1. It does not restart.

### Gates passed (live, MINIS)

| # | Observation | Result |
|---|---|---|
| G0 | `/proc/sys/net/vsock/child_ns_mode` `rw`, `ns_mode` `r--r--r--`, both `global` at boot | PASSED |
| G1a | first write `rc=0`; second differing write → `EBUSY`. Write-once measured, not cited | PASSED |
| G1b | child of `local` parent reads `local`; **control:** child of `init_netns` reads `global` | PASSED |
| G1c | `nsenter --net=/run/netns/katmate-root` + `unshare --net` → child reads `local` — the daemon's actual sequence | PASSED |
| G3 | `SIGKILL` to `MainPID` under `User=nobody` → `STOPPOST result=signal status=KILL code=killed uid=0`; unit `Result=signal` | PASSED |
| G2 | tap is netns-scoped (`Device "tap-g2" does not exist`; control: only `lo`) | PASSED |
| G2b | `ip link set tap-g2 netns g2-test` succeeds — migration is an alternative to fd inheritance | PASSED |

`init_netns` `child_ns_mode` remains `global` — the host-wide write-once budget
was never spent.

### Measured, predicted by no ADR

- **`ip netns add` is not nestable.** Under `ip netns exec` the bind mount is
  made in a child mount namespace that immediately exits. What remains is a
  `----------` placeholder; `setns` → `EINVAL`, and `ip netns list` still lists
  it. Permission bits distinguish: live namespace `-r--r--r--` (nsfs inode under
  the bind mount) vs placeholder `----------`. **Consequence: namespace creation
  is daemon code** — `setns` → `unshare` → `mount --bind`, one process, alive
  until the bind mount lands.
- **`/proc` must be remounted to read per-netns sysctls.** After
  `unshare --net`, `/proc/sys/net` shows the *old* namespace until `/proc` is
  remounted. The failure mode is a **false negative** — a plausible wrong value,
  silently returned. Same class that killed ADR-021's shutdown model: a
  mechanism quietly consulting the wrong object. Applies to the daemon, not only
  to tests.
- **`ns_mode` is `r--r--r--`.** After a namespace exists there is no lever.
  Whoever creates it has fixed its mode permanently.
- **Tap migration clears `UP`, preserves MAC.** `ip link set … up` must run
  *after* migration, inside the target namespace. The surviving MAC matters to
  ADR-025's locally-administered-address check.

### Correction to an earlier internal statement

Mid-session it was asserted that AppVM links "probably need veth rather than tap
because AppVMs route through netVM, not the host". The reasoning was right and
the premise was wrong: it generalised from `net-sys.con`'s host-side `tap-int0`,
which sits on the host only because until now there was no other namespace to
put it in. Inspection of `app_web.con` settles it differently — **the AppVM
launcher has no network device of any kind.** No `-netdev`, no
`virtio-net-device`, no tap. AppVM networking does not exist yet, which is
consistent with NETCFG having been live-gated against netVM itself and never
through a live AppVM.

C2 is therefore recorded as **neither passed nor failed**: it was not a
constraint on parenthood. It returns as a link-topology question when the AppVM
acquires an endpoint, to be settled by measurement then.

### Refinement to ADR-028

ADR-028 records `child_ns_mode` as "a decision taken once at **daemon start**".
G1 refines: the write is in a *parent* namespace, children inherit at creation.
It is a one-time preparation on a dedicated `katmate-root` namespace, not a
daemon-start decision — so `init_netns` is never written and foreign namespaces
on the host keep `global`. ADR-028's substance stands and is now measured rather
than cited.

### Not measured, recorded as not measured

- **OOM-kill.** G3 used `SIGKILL`; systemd distinguishes `result=oom-kill`
  separately. `ExecStopPost=+` behaving identically is likely and unverified.
- **Tap ownership across migration** — whether `user <uid>` survives
  `ip link set … netns`. Blocks nothing until an AppVM has an endpoint.
- **AppVM link topology** — opened, not settled, by the C2 finding.
- **Unit shape** — `StartTransientUnit` vs a `katmate-vm@.service` template.
  Deliberately deferred; neither affects any ADR-029 decision.

### Housekeeping

`/etc/systemd/system/vhost-vsock-load.service:5` uses `ConditionKernelModule`,
which systemd does not know; the line is silently ignored (visible in `dmesg`).
The unit works — the condition does not exist. Drift, not a defect.

### Docs debt raised this session

The earlier 2026-08-02 session (CID renumbering `app_web` 5 → 21, personalVM
deletion) is threaded through this file's live sections but **has no session
heading**. It is therefore invisible as a session while its consequences are
visible as state. Give it its own heading, or fold it in here — not left as is.

## Previous session (2026-07-28) — C-gate defined and half-passed; vsock placement settled; indicator carriers closed

Architecture session (thinking-on) plus three live gates. Origin: a review of
alternative VMMs that turned into a correction of how this project applies
*absent, not disabled*.

### Decided

- **ADR-026 — domain indicator carriers.** Accepted, gate closed. Identity
  resolves in two host-side steps: the compositor gives a window `pid`, and
  that pid's AF_VSOCK connection gives the peer CID. `app_id` and window title
  are guest-controlled and excluded from the identity path at every level.
- **ADR-027 — VMM containment is a precondition, not an alternative.**
  Introduces three axes of capability control and scopes *absent, not disabled*
  to axis 1 (existence). Adds principle 10, *relocation is not removal*.
  Defines the C-gate; no axis-2 work is implemented until it passes.
- **ADR-028 — virtio-vsock transport placement.** v1 stays on `vhost_vsock`.
  Hybrid placement rejected with reasons recorded so it is not re-proposed.
  `vhost-user-vsock` with `--forward-cid` identified as the only viable
  alternative, gated behind the C-gate, with H1–H3 open.

### Gates passed (live, MINIS)

- **C4 — tightened seccomp filter.** `resourcecontrol=deny` added to both
  launchers. `app_web` (CID 5): `Seccomp: 2`, one filter, `dmesg` clean,
  `ping 5 → 0x00`. netVM (CID 3): `Seccomp: 2`, one filter, `ping 3 → 0x00`,
  and `vfio-pci 0000:01:00.0: resetting / reset done` twice — the `FLReset-`
  workaround is unaffected. The hypothesis that `resourcecontrol=deny` would
  collide with `-object iothread` is **refuted empirically on both machine
  types**, not reasoned about.
- **C5b — 9p removed from netVM** (SECURITY-MODEL gap #10 closed). `-fsdev` and
  `-device virtio-9p-pci` deleted from `net-sys.con`; `/proc/<pid>/cmdline` of
  the running VMM contains neither. Proof taken host-side deliberately — the
  device is absent from instantiation, which is an axis-1 proof and stronger
  than an in-guest `mount` check. See the operational note added to open
  problem #12.
- **ADR-026 gate.** `swaymsg -t get_tree` on a rendered `nautilus` window
  reported `app_id: org.gnome.Nautilus`, `name: Home`, and a `pid`. That pid
  resolved to `waypipe -s 1024 --vsock --threads 0 -c lz4 client-conn`, and
  `ss -f vsock -p` on it reported `v_str ESTAB 2:1024 ↔ 5:287463193` — peer
  CID 5. The gate as written asked only whether a pid resolves to the waypipe
  client; it resolved further, through the client to the CID. **Also
  verified:** the query needs no privilege — an unprivileged caller receives
  the same peer CID as root, so the resolver is not forced into a privileged
  process.

### Still open on ADR-026

Pid stability with **two concurrent windows from one domain** (a second
`client-conn`), and across close/reopen, is unverified. If per-connection pids
differ, the resolver must handle a set rather than a single value. A host
reboot between observations says nothing about this — a new boot means new pids
by definition.

### Corrections to earlier internal statements

Recorded so the error mode stays visible, in the spirit of the ADR-025 gate
correction.

1. **"`-sandbox` is not enabled / unused."** Wrong.
   `-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny` was already
   present in **both** launchers; only `resourcecontrol=deny` was missing. The
   claim was made without reading the launchers.
2. **"The VMM runs as root."** Over-generalised. True of `net-sys.con` only.
   `app_web.con` uses `sudo` solely for `lvchange`; QEMU runs as the invoking
   user, so C1 is already satisfied for AppVMs. The correction is in the
   project's favour and would have been lost.
3. **"The hybrid vsock model is an instance of absent-not-disabled."** Wrong,
   and the correction is the substance of ADR-027. It is relocation of
   privilege; the principle applies to existence, not placement.
4. **"`share=on` may be avoidable on the `--forward-cid` path."** Void — shared
   guest memory is required by vhost-user generally, in both backend modes.
   **What this does not settle:** `app_web.con` uses `share=on` on a hugetlbfs
   backing file with kernel `vhost-vsock` and *no* vhost-user. Whether it is
   needed there is still open and unmeasured.
5. **"Spectrum has no network design."** Wrong. Asserted from a design document
   of around 2020 without checking the repository or the lists. The failure was
   the one this project has a standing rule against: a claim made without
   capturing the reference fixture first.

### New file

`docs/OBSERVATIONS.md` — append-only, newest-first log of publicly available
material bearing on recorded decisions. Conventions live in the file header;
the central one is that **the subject of every entry is one of our decisions**,
and that our own stack is held to the same standard as anything else.

### Numbering note

The open-problems list in this file already ran to **15**, not 12. An earlier
draft of this session's additions assumed 12 and would have collided. Same rule
as for ADRs: count the list, never the memory of it.

## Session archive

Sessions older than the two above (2026-07-27 back to 2026-06-27) live in
[docs/SESSIONS.md](docs/SESSIONS.md), split out on 2026-07-14. That file is
append-only; CIDs in it are the pre-ADR-022 numbering and are deliberately not
rewritten. **This file carries the authoritative CID map** (see *Live state*).

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
  `6.12.95+deb13-amd64`). **PROVEN this session:** boots through full systemd,
  root on `/dev/vda`, `enp0s5` (MAC-matched) `Link is Up 1Gbps/Full`,
  firmware-realtek loaded, DHCP lease `10.3.1.110` confirmed by host ARP scan.
  The uplink deltas (`firmware-realtek`, `20-uplink.network`, cleaned
  `interfaces`) are now baked by the manifest, not hand-applied. NOT yet
  verified from inside (root locked, no `netvm-agent` — see 2026-07-09 session):
  `networkctl` state, WireGuard/ProtonVPN bring-up, inner-segment `enp0s4` p2p
  to personalVM. `memlock` via `LimitMEMLOCK=infinity` (unit) or `ulimit -l
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

**Primary (netVM sysVM — ADR-021 track, build now PROVEN):**

- **`handle_netcfg` — dependency call FIRST.** Hand-rolled `RTM_*` vs a
  netlink crate (`rtnetlink`/`neli`). Minimal-TCB leans hand-rolled — no
  dependency in a `CAP_NET_ADMIN` binary, mirroring the deliberately
  non-serde wire — but netlink subtlety (NLMSG alignment, attribute TLV,
  ACK handling) warrants a short explicit judgement at the top of the
  thinking-on/Fable session, before any code. Mechanism is settled (Path B,
  E-gate 2026-07-21); this is the one open design point left in the handler.

- **NETCFG payload — the next handler (ADR-023 impl).** `handle_netcfg` is the
  ONLY ERR-stub left in netvm-agent; it gates the AppVM internal /32 network
  (every AppVM launch needs a route installed). ADR-023 is written; open are the
  **payload shape** (typed p2p-link: match / local+peer / `/32` / route / metric,
  `add`/`remove` only, validation against a legitimate appVM CID) and the
  **in-guest mechanism** (networkd fragment default; `rtnetlink` alternative).
  Thinking-on session. **Tooling gap first:** `ping-client` has no `netcfg`
  subcommand (opcode 0x06 postdates it) — the live test needs the client
  extended once the payload shape is fixed.

- **`netvm-agent` — FUNCTIONALLY COMPLETE.** PING (07-17), SHUTDOWN (07-18,
  ADR-024), NETCFG (07-23, ADR-025) — all live-gated. The opcode model is
  final: PING + NETCFG + SHUTDOWN; RUN / FILEGET / FILEPUT stay absent
  (boundary test in `op.rs`, confirmed live against the fresh binary). Further
  work on this agent answers launch-daemon needs, not missing handlers.

- **In-guest verification via a dev-only console password** (out-of-band; remove
  before release, sshd class): `networkctl status` routable, WireGuard/ProtonVPN
  up, inner-segment `enp0s4` p2p to personalVM. Only link-up + DHCP lease
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
  no L3 — pure L2 conduit into netVM). Minor: inherits `RequiredForOnline=yes` from
  defaults → `networkd-wait-online` may wait on it at boot; add
  `[Link] RequiredForOnline=no` if it ever slows boot.

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

- **Docs hygiene (deferred) — reconcile the state.md session section.** It
  holds 07-14 + 07-13 while SESSIONS.md already has 07-18/07-17/07-15/07-10; the
  two do not overlap and the dates are inverted vs the "two most recent" mandate.
  07-13 is NOT yet in SESSIONS (would be lost if naively dropped). Sanitize
  deliberately: copy 07-14 + 07-13 into SESSIONS (newest-first), then trim
  state.md to the two most recent. Not done this session (minimal-move choice).

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
