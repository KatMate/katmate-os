# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Milestone:** v0.2 (in development) · **Last updated:** 2026-08-24
(the link measurement arc, ADR-033 written as PROPOSED, and three new open
problems; the 2026-08-22 stop-path session is now *Previous session*, and the
G5/H3 session has rotated to `docs/SESSIONS.md`).

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

## This session (2026-08-24) — the link measurement arc: a socket-backed link starts with no peer, and the address is resolved per send

Two delegated measurement sessions on the Acer, reaching MINIS over ssh, against
two briefs. **No commits, and no tracked file edited by either** — both measured
and reported. Briefs: `~/link-m1-brief.md`, `~/link-m2-brief.md`; reports:
`~/link-m1-report.md` and `~/link-m2-report.md`. This entry was written by a
separate recording session (`~/adr033-writepass-brief.md`,
`~/adr033-writepass-report.md`), on the division 2026-08-19 established and the
sessions since have kept: the session that measures does not also rule, and
the session that rules does not also write the record.

**The operator has ruled the measurements**, and ADR-033 is written from them
and is **PROPOSED, not accepted** — `N` is not fixed until M2 is taken. Neither report writes a verdict;
both state what was observed and what was not.

### link-m1 (2026-08-24) — the backend exists, starts without a peer, and costs little

- **`dgram` is a netdev type in QEMU 11.1.0 on MINIS.** It appears in
  `-netdev help`. Per-type help does not exist in this version for any type, so
  every option name used came from QEMU's own `-help` synopsis and from its
  parse errors, not from expectation (§ 2a–§ 2c).
- **The printed synopsis and the runtime disagree, from one binary.** The
  synopsis brackets `remote` as optional —
  `local.type=unix,local.path=path[,remote.type=unix,remote.path=path]` — and
  the runtime refuses it: *"type=inet or type=unix requires remote parameter"*,
  exit 1, nothing started (§ 2c against § 10). The `local.type=fd` form is the
  only one the error does not name and was not tested.
- **A device whose `remote.path` does not exist starts silently.** Zero bytes on
  stderr, **+1 fd**, **+0 threads**, and **0 CPU ticks of the 6000 available**
  over a 60 s window — every reading identical to a no-device control run in the
  same script, except the one added socket fd (§ 9, § 11). A pair whose peer
  paths both exist reads the same on every count, `ss -xap` included (§ 12).
- **A stale `local.path` does not block a later bind.** A second QEMU bound the
  same path after the first was killed, with 0 bytes on stderr and **a new
  inode** (§ 19). *The mechanism is link-m2's, and carries link-m2's bound:* the
  `unlink()` before `bind()` was traced against a path that was **absent**, so it
  returned `ENOENT` and removed nothing. What is measured is that QEMU issues
  the unlink unconditionally at that point — **not** that it succeeded against a
  stale node (link-m2 § A.4).
- **`q35` refuses the 31st `virtio-net-pci` on the default root bus.**
  *"PCI: no slot/function available for virtio-net-pci, all in use or reserved"*,
  naming `netdev=n30`, byte-identical across all three repetitions, after
  `n0`–`n29` were placed (§ 20.1). It is a PCI topology limit and not a socket,
  fd or netdev limit: each failed run still created **all 32** of its
  `local.path` sockets, against `ulimit -n` 1024 and a peak of ~41 fds.
- **The cost of an empty slot, as the tables give it.** Three repetitions per
  point, reported individually; the first of each is quoted here and the three
  agree to within 12 kB at every point. Nothing is divided and nothing is
  extrapolated — the reports do neither (§ 25).

  | | `q35` + `virtio-net-pci` | `microvm` + `virtio-net-device` |
  |---|---|---|
  | VmRSS kB, `N`=0 | 38724 | 38068 |
  | VmRSS kB, `N`=1 | 39584 | 38620 |
  | VmRSS kB, `N`=8 | 43400 | not run |
  | VmSize kB, `N`=0 | 1430112 | 1425232 |
  | VmSize kB, `N`=1 | 1432588 | 1425392 |
  | VmSize kB, `N`=8 | 1462392 | not run |
  | threads | 3 at every `N` | 3 at every `N` |
  | CPU ticks / 60 s | 0 at every `N` | 0 at every `N` |

  `VmHWM` was taken as well and is the only figure in the set recording a
  transient peak: at `q35` `N`=8 it is ~58 MB against a settled RSS of ~43 MB.
  **All of it is a machine paused at reset under `-accel tcg`**, with no guest,
  no kernel and no disk. The zeros are properties of that state.

### link-m2 (2026-08-24) — no `connect()`, and the peer is found after the fact

- **The startup trace, outside dynamic linking, is three calls.**
  `unlink(local.path)` → `ENOENT`, `socket(AF_UNIX, SOCK_DGRAM|SOCK_CLOEXEC)` →
  9, `bind(9, …)` → 0. **There is no `connect()` at all** — not a failed one, not
  a deferred one — and **`remote.path` appears nowhere in the trace**: not
  `stat`-ed, not opened, not warned about (§ A.3). The trace filter was verified
  first against a purpose-written program known to issue `socket`, `bind`,
  `connect`, `sendto` and `unlink` on `AF_UNIX` `SOCK_DGRAM`, so the absence is
  an absence of the call and not of the filter (§ A.1).
- **The result: frames reach a peer that appears afterwards.** A guest emitted
  ten broadcast frames into an absent peer — `h.sock` sampled every second
  across the window and absent at each of the ten — the receiver then bound the
  peer path, and **the first datagram to arrive carried `seq=000010`**: the
  first frame emitted after the socket existed. `seq=000000`–`000009` appear
  nowhere in the receiver's log, checked by pattern over the whole of it. From
  `000010` the stream is contiguous to `000052`. Arrival was **0.605 s after
  bind** (§ B2.2–§ B2.4).
- **The reverse direction works, and is a separate result.** A 63-byte frame
  sent out of the socket bound at `h.sock` reached the guest, which printed it —
  into a QEMU started before the peer existed and never restarted (§ B2.5). It
  neither strengthens nor weakens the first result.
- **What the guest is not told.** Its `sendto` of an 18-byte payload returned
  **`rc=18, errno=0` identically in both windows**, peerless and peered. The
  failure, if QEMU sees one at all, is not reported upward (§ B2.2). The `[init]
  RX` lines in the peerless window are the guest hearing its own broadcast on a
  local socket, not evidence of anything crossing the backend, and the report
  says so where they appear.
- **QEMU wrote 0 bytes to stderr for the whole run** — peerless window, peered
  window and reverse direction alike. The only line it ever writes is the one it
  writes at exit (§ B2.6).
- **What QEMU does with a frame while the peer is absent was not observed.**
  Whether it issues a failing `sendto` per frame or discards without a syscall
  needs a trace of the *running* QEMU; Part A's trace covers startup on a machine
  paused at reset. Nothing is claimed about buffering either: nothing predating
  the bind arrived, which is a statement about what arrived (§ B.6).

### Every measurement was taken unprivileged, and that is a result about the design

**No `sudo` anywhere in either session**, and neither reports any step that
indicated needing it. An unprivileged user bound `AF_UNIX` datagram sockets,
started QEMU under TCG, traced its own processes, compiled a static `/init`, and
built a `cpio` carrying a `/dev/console` device node — the last via the kernel
tree's own `gen_init_cpio`, because `mknod` needs privilege and the brief did
not. Every failure observed in either session was a QEMU option refusal, a PCI
topology refusal or a guest-side `errno`; **no permission error occurred
anywhere.**

**netVM was up and untouched throughout both.** PID `2114876`, argv read and
compared byte-for-byte before and after every launch in every part of both
sessions. No `systemctl`, no unit operation, no LV, and no `-enable-kvm` process
started by either session.

**Nothing under `/etc/katmate/`, `/var/lib/katmate/` or `/run/katmate/` was read
or written.** Those names appear in both sessions only inside the netVM argv
string that `pgrep` printed out of `/proc`.

That set of three is not only a statement about how the sessions behaved. The
mechanism ADR-033 proposes was exercised end to end — socket creation, bind,
a booting guest, frames in both directions — by uid 1000, on a host whose live
state was never touched. **An AppVM's start path needing no privileged network
step is the property the ADR claims, and this is the first evidence for it.**

## Previous session (2026-08-22) — the stop path's first execution, H1 and G6, and every part-2 gate measured

Delegated measurement session on the Acer, reaching MINIS over ssh, in two runs
against one brief. **No commits, and no tracked file edited** — the session
measured and reported. Brief: `~/3a2-g6h1-brief.md`; report:
`~/3a2-g6h1-report.md`, whose CONTINUATION sections carry the second run; the
restarted guest's complete console is `~/3a2-g6h1-restart-console.txt`. This
entry was written by a separate recording session (`~/3a2-writepass-brief.md`,
`~/3a2-writepass-report.md`), on the same division as 2026-08-19 and 2026-08-21:
the session that measures does not also rule, and the session that rules does not
also write the record.

**The operator has ruled H1 and G6 PASSED**, and the **stop path** an execution
of its intended path, on the observations in `~/3a2-g6h1-report.md` §§ 2–3 and
CONTINUATION part B. That report writes no verdict; it states which of S3.5's
named observations were seen and which were not. Open problem **#20** is closed
by the same run and by the operator's ruling — see § *Open problems*.

**Every unit operation went through `sudo -n`.** The brief's literal
`systemctl stop …` was refused by polkit at the D-Bus layer in 0.022 s, before
the unit was reached — a refusal that measures nothing about the unit and cost
the measurement nothing. The privilege is the one § *Live state* / *Dev access to
MINIS* documents, and that entry now says so in the terms a unit operation needs.

### The stop, 08:26 — SIGTERM from PID 1, 0.441 s, and a guest that said nothing

**The first execution of the stop path in this project.** QEMU named the signal
itself — `qemu-system-x86_64: terminating on signal 15 from pid 1 (/sbin/init)`
at **08:26:05.619666** — and systemd recorded `Deactivated successfully.` at
**08:26:06.061060**, **0.441 s** later, against a `TimeoutStopUSec=30s` read from
the *running* unit rather than from the template. **No timeout, no `SIGKILL`, no
escalation:** the journal was searched across the window for
`state 'stop-sigterm' timed out` and `Killing process` and carries neither. The
unit ended `inactive (dead)` with **`Result=success`** — not `failed` —
`MainPID=0`, `NRestarts=0`, and its cgroup gone.

**The guest emitted no console output at all** between the SIGTERM and the
deactivation: no shutdown sequence, no unmount, **no `EXT4-fs (vda): re-mounted
… ro`**. It was **terminated, not shut down**, which is what the template's own
comment says a stop here does. The consequence was predicted in the same report
and measured later that morning — see § *The restart*.

**The stop deactivated no LV and removed no file.** `vm_sys_netvm` went
`-wi-ao----` → `-wi-a-----` — still active, `dmsetup` open count `1` → `0` —
while `vm_tpl_foundation`, `vm_app_web`, `vm_app_web_home` and `vm_pool` read
identically either side. `/run/katmate/vm/netvm.env` **survived byte-for-byte**:
same 552 B, same 12 keys, same `Aug 19 15:26` mtime; so did `nics/uplink0`. There
is no teardown step at all, and the new open problem below carries what that will
mean once disposable AppVMs have a qcow2 delta to destroy.

The matched pair either side of the stop came from **one read-only script run
twice**, so *"the same commands at both moments"* is a property of the method
rather than an assertion.

### H1, 08:29 — the second preflight refuses and the third never spawns

The injection is the cheaper of S3.5's two recipes, and the one the rotated
2026-08-19 entry named as unaffected by a running QEMU: **T2's `NETVM_LV` pointed
at a nonexistent LV**, `vg0/vm_sys_netvm_absent`, written from outside the
executable. The target was **proven absent** rather than assumed — `lvs` exit 5,
*"Failed to find logical volume"* — and the value is deliberately a
syntactically valid `vg/lv`, so that it survives the first preflight's shape
check and reaches the second.

- **Preflight 1 passed, and named the injected value on its way through.**
  `katmate-check-image` logged `rootfs LV (existence checked by
  katmate-activate-lvs): vg0/vm_sys_netvm_absent`, then `payload OK`, exit
  `0/SUCCESS`. The division of labour the ADR-032 §2 revision note describes did
  exactly what it says.
- **Preflight 2 refused, with exit 1.** `katmate-activate-lvs`: `FATAL: rootfs
  LV: cannot activate vg0/vm_sys_netvm_absent`. **`km_die`, not `km_usage`** —
  `katmate-lib.sh:52–53` gives the first exit 1 and the second exit 2, so the
  executable **decided**; it was not called wrongly. systemd recorded
  `status=1/FAILURE`.
- **Preflight 3 never spawned, and this is shown two ways.** No
  `katmate-generate-env` line exists anywhere in the start window, and
  `systemctl show -p ExecStartPre` records the third entry as
  `start_time=[n/a] … pid=0 code=(null)` — never started, not merely silent.
- **No VM.** Unit `failed` / `Result=exit-code`, `MainPID=0`,
  `(no qemu process)`, and `systemd-cgls` → *"Unit … not found"*: no cgroup was
  created for the invocation at all.

**The injection was undone and the undo verified by read-back**, not asserted:
the T2 file was read out in full and hashed back to `bb2a5086…`, byte-identical
to its pre-injection state.

### G6, 08:51 — the third preflight refuses a falsified label

`NIC_VENDOR` in the published label `/run/katmate/nics/uplink0` was edited
`0x10ec` → `0x8086` (Realtek → Intel) and read back **before** the start, with
`/sys` unchanged at `0x10ec`. `/run/katmate/nics/` is under `/run` and is not a
tier directory, so the injection needed no separate authorisation.

**Preflights 1 and 2 passed; the third, `katmate-generate-env`, refused with exit
1** — again `km_die` and not `km_usage`. Its message quotes **both**
vendor:device pairs and **cites gate G6 by name**, beside ADR-030 §5. The unit
reached `failed` under a **new** `InvocationID` (`492d09a5…`, distinct from H1's
`0c0637dc…`), so the failure is unambiguously that start's, and **no QEMU process
and no cgroup ever existed**.

`katmate-activate-lvs` ran against the real LV on the way through, which H1's
injection had prevented — and met an **already-active** LV again, so **activation
from inactive is still unexercised**, exactly as § *Next steps* item 3 already
records.

**The undo was the publisher regenerating its own output**, not a hand edit:
`systemctl restart katmate-publish-nics.service`, after which the label read back
byte-identical to the pre-state hash `66e91857…`, with only its mtime moved. The
`start`-versus-`restart` distinction that fell out of that undo is in
§ *Invariants & gotchas*.

### The restart, 08:51:56 — the predicted journal replay on its first observation

`reset-failed`, then start. **The prediction the stop had made was measured on
its first observation:**

> `[    1.797848] EXT4-fs (vda): recovery complete`

and **corroborated independently, by a different subsystem** — the guest's own
journald reporting `File …/system.journal corrupted or uncleanly shut down,
renaming and replacing`. The guest noticed what the host had done to it.

The rest of the boot is unremarkable, and that is the point: all three
`ExecStartPre=` `0/SUCCESS`, the projection regenerated with the **same 12 keys**
and **content identical** to the pre-stop one (diffed line by line; only the mtime
moved — so the two injections left nothing behind in it), and the uplink up at
**t+7.457 s** on MAC `38:05:25:34:7c:47`, against **t+7.458 s** on the 2026-08-19
boot. **No ARP scan was run**, so the DHCP lease is not claimed for this boot.
netVM is up as **`MainPID 2114876`** and holds the uplink again.

### The installed set was hashed against the tree, and what that does not cover

The first action of the second run, before anything else: **six executables under
`/usr/lib/katmate/` and both units are byte-identical across three legs** — the
installed copy, the MINIS build copy `~/katmate-build/host/`, and the Acer
repository — with no file present in one location and absent from another.

**This establishes identity at 2026-08-22 08:49 and at no other moment.** It does
not reach backwards: nobody hashed them during G1/G4, G5/H3, the stop, H1 or G6.
What supports those runs is the installed files' mtimes, all `Aug 19 14:52` —
before every gate since, with no rsync or re-install in between — **and that is
evidence, not proof.** This project's own `sync.fish` invariant is that mtime is
exactly what cannot be trusted after an rsync. That gap is why the hash is now
the first action of a gate session rather than an afterthought
(§ *Invariants & gotchas*).

### Every gate in scope for step 3a part 2 is now measured

**G1 and G4** (2026-08-19), **G5 and H3** (2026-08-21), the **stop path**, **H1**
and **G6** (2026-08-22). **G2, G3 and H2 stay out of scope** — part 3, and the
`.con` deletion. *"The list is now G6 and H1"* is superseded at all three sites
that state it — the 2026-08-21 entry below, and two under § *Next steps* — and
each is appended to rather than rewritten, because each records the carry-in a
session was actually given.

## Session archive

Sessions older than the two above (2026-08-21 — G5 and H3, rotated there
2026-08-24 — then 2026-08-19 *second of two* — the gate run,
rotated there 2026-08-22 — then *first of two*, the A′
correction, rotated there 2026-08-21 — then 2026-08-17, then 2026-08-11, then
2026-08-09 *second of two*,
then *first of two*, then the
2026-08-06 pair, then 2026-08-03, then
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

**Closed 2026-08-11** (written up 2026-08-17). The 2026-08-09 *first of two*
entry — step 3a as a gate, and ADR-032 — rotated to the archive as the 2026-08-11
entry arrived, because rotation is how a session closes and the file keeps two.
Its heading changed from *Previous session* to *This session*, which is the
archive's uniform convention; the body moved verbatim, verified by diffing the
extracted block against the pre-move blob.

**Closed 2026-08-17.** Same pass, same mechanism, one entry later: the 2026-08-09
*second of two* entry (3a part 1) rotated out as the 2026-08-17 entry arrived. Two
rotations in one day is not a defect — it is what keeping two sessions costs when
two sessions close on the same day.

**Closed 2026-08-19.** The 2026-08-11 entry (3a part 2, first half) rotated to
the archive as the 2026-08-19 entry arrived, heading changed from *Previous
session* to *This session* and the body moved verbatim — the same mechanism as
the two rotations above. Recorded here because a rotation that is not recorded
is indistinguishable from an entry that was lost.

**Closed 2026-08-19, and this is the second rotation of that day.** The
2026-08-17 entry (3a part 2, second half) rotated out as the gate-run entry
arrived — same mechanism, same check: the heading changed from *Previous
session* to *This session*, the body moved verbatim, and the moved copy was
verified by hashing it against the pre-move block in `HEAD` rather than by
reading it. Two rotations on 2026-08-19 for the reason 2026-08-17 already
recorded: the file keeps two sessions, and here two closed on one day.

**Closed 2026-08-22.** The 2026-08-19 gate-run entry (G1 and G4) rotated to the
archive ahead of the 2026-08-22 entry, so that the file never held three at any
point between the two commits. Same mechanism, same check: the body moved
verbatim and the moved copy was verified by diffing the extracted block against
the pre-move blob in `HEAD` — the diff is one line, the heading, and the bodies
hash identically (`08a906cc…`). **The heading gained an ordinal it did not carry
here:** *Previous session (2026-08-19)* became *This session (2026-08-19, second
of two)*, because the A′ correction already sits in the archive as *first of two*
and newest-first puts the gate run above it. That is the 2026-08-02 pair's
arrangement applied to this day, not a new convention. The write pass this
rotation belongs to deliberately wrote **no** arc summary into
`docs/SESSIONS.md`: the 2026-08-21 entry is still live in this file, and a
summary there would be a second description of material that is still current.

**Closed 2026-08-24.** The 2026-08-21 entry (G5 and H3) rotated to the archive
ahead of the 2026-08-24 entry, so that the file never held three at any point
between the two commits — the 2026-08-22 rotation's condition, applied again.
Same mechanism, same check: the body moved verbatim and the moved copy was
verified by diffing the extracted block against the pre-move blob, the diff
being one line, the heading (*Previous session (2026-08-21)* → *This session
(2026-08-21)*), with the bodies hashing identically (`6d54bae7…`). No ordinal
was added: 2026-08-21 is the only session of its day.

**Two cross-references now point across the file boundary, and neither was
repaired.** The rotated entry's closing line reads *"See the 2026-08-22 entry
above"*, and no 2026-08-22 entry exists in `docs/SESSIONS.md`; the retained
2026-08-22 entry names *"the 2026-08-21 entry below"*, which is no longer below
it. Both are recorded here rather than edited, because the archive's rule is
that a moved entry moves verbatim and a retained entry is not rewritten to suit
a later move. The 2026-08-06 insertion did repair a dangling reference by
pointing it at `../state.md` — that was an insertion repairing an ordering
defect, not a rotation, and it marked the repair where it occurred. The
distinction is kept deliberately: this is the first rotation to strand a
reference in both directions, and it is cheaper to know that than to have the
entries silently agree.

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

  **Correction, and then its resolution.** On **2026-08-11** `sudo lvs` on MINIS
  reported `vm_personal_home vg0 Vwi-a-tz-- 40.00g vm_pool 4.47` — the LV was
  still there, so this entry's deletion claim had been wrong for nine days, and
  it was marked rather than rewritten because nothing in the tree said whether
  the deletion had failed or the LV had been recreated. On **2026-08-17** the LV
  is **absent** from `lvs` and `vm_pool` has dropped from 0.79 % to 0.53 % data,
  which is the ~1.8 G that 4.47 % of 40 G occupied. The entry is now true; what
  is recorded here is that it was published before it was true. **`ROADMAP.md:31`
  repeats the claim** and needs no correction for the same reason.

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
- **Dev access to MINIS (dev-only; goes out with Open problem #4).** The account
  is **`host`**, not `winterbox`: `ssh host@10.3.1.3`. Publickey only; the Acer
  (`winterbox`, `10.3.1.100`) holds the key. `sudo -n` is passwordless on MINIS
  via `/etc/sudoers.d/katmate-dev`. **Every `systemctl` operation on a KatMate
  unit from a delegated session goes through `sudo -n` — `start`, `stop`,
  `restart` and `reset-failed` alike, not only `lvs` and root-owned file reads.**
  Without it polkit refuses at the D-Bus layer *before the unit is reached*
  (*"Access denied … requires interactive authentication"*), and that refusal
  measures nothing about the unit: it cost the 2026-08-22 session one issued stop
  that never ran. **The login shell on MINIS is fish**, so an
  sh or bash snippet cannot be passed as `ssh host@10.3.1.3 '…'` — fish rejects
  `$?` and the line dies before it runs anything. **Two delivery forms, and which
  one depends on who is typing.** From the operator's own shell, feed the snippet
  on stdin: `ssh host@10.3.1.3 bash -s <<'EOF' … EOF`. **A delegated agent cannot
  use that form** — piping arbitrary content into a remote shell over stdin is
  shape-identical to `curl | sh`, and the agent's tooling refuses it on the
  Acer regardless of what the content is. bash is present on MINIS; installing
  anything changes nothing, because the block is on the calling side and is about
  the form, not the interpreter. The agent writes the script to a file, `scp`s it
  to MINIS and runs it there — which is the better record anyway, since what
  executed is a file the report can quote and hash, and a heredoc leaves nothing
  behind. Measured 2026-08-19: the E1c session lost two rediscoveries to the ssh
  target and the shell, and the phase-2 session hit the classifier on the stdin
  form. This entry is the source of truth for reaching MINIS;
  `.claude/settings.local.json` carries the target as configuration, not as
  documentation. rsync stays Acer→MINIS into `~/katmate-build/`. `10.3.1.3` is
  stable on the home LAN; that it is not a persistent networkd profile is the
  Host entry above, and the two are not in conflict.
- **Installed vs tree, 2026-08-22 — one file, deliberately.** The installed
  `/usr/lib/katmate/katmate-generate-env` on MINIS now **differs from the
  repository**, and only in the stale-label refusal's wording (*"it was created
  for …"* → *"`$NIC_FILE` claims …"*). Behaviour is unchanged; nothing else in
  the set moved. It stands until the next rsync + re-install, and it is recorded
  here so the **hash-first check** the *Invariants* section now requires expects
  the mismatch, finds it in one named file, and does not read it as drift.
  *Consequence, so the two records do not appear to contradict each other:*
  **G6's transcript in `~/3a2-g6h1-report.md` § B.4 quotes the pre-reword
  wording**, because the gate ran against the installed copy before this commit
  existed. The gate result stands as measured; the sentence it quotes is the one
  the executable printed that morning.
- **foundation** (`vm_tpl_foundation`, thin RO): clean, systemd-free,
  init/agent/waypipe/user baked in.
- **netVM** (CID 3 — unchanged by the new map; Debian trixie, q35, **sysVM class
  — ADR-021; driver domain — ADR-022**): two
  artefacts now exist. (a) The old hand-installed **netinst pet**
  (`net-vfio.con`, `vm_net_overlay.qcow2`, guest `enp0s6`) — retired in
  principle, superseded. (b) The **declarative build** `vm_sys_netvm` (linear RW
  4G) from `build/netvm.sh`, booted via `~/net-sys.con` (RTL8125 via
  `-device vfio-pci,host=0000:01:00.0`, `-kernel`/`-initrd` direct boot, kernel
  **6.12.101+deb13-amd64**, rebuilt clean on 2026-08-11 — was
  `6.12.96+deb13-amd64` from the 2026-07-23 build, and the change is trixie
  moving under a declarative manifest, not a defect). Boots through full
  systemd, root on `/dev/vda`; the uplink comes up MAC-matched
  (`38:05:25:34:7c:47`, `Link is Up 1Gbps/Full`, `firmware-realtek` loaded,
  DHCP lease **`10.3.1.103`** confirmed by host ARP scan on 2026-08-19 — it was
  **`10.3.1.104`** on 2026-08-11, and the lease moving is the rule holding, not
  a drift: the lease is volatile and only the MAC identifies the guest) and the
  internal p2p segment on its **derived** MAC **`52:54:00:21:b2:08`**, measured
  live 2026-08-19 — emitted as `KM_MAC_INT` and carried into QEMU's argv as
  `-device virtio-net-pci,netdev=int0,mac=…`. **This entry published the
  authored `52:54:0a:64:01:01` until that run**; the *Invariants* entry below
  carries why it changed and what still uses the old value. **Interface
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
- **personalVM** — **gone.** Launcher and overlay removed 2026-08-02;
  `vm_personal_home` outlived that claim and was measured present on 2026-08-11,
  absent on 2026-08-17 (see the correction on the housekeeping entry above). It
  was the last pre-foundation artefact. Returns as a domain, not as this VM.
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

19. **`katmate-generate-env`'s read-back has no required-key set for
   `app-routed`.** Added 2026-08-19 with the read-back itself. The executable
   accepts three profiles — `in_list "$ASSERTED" sys-driver app-offline
   app-routed` — but the read-back's `case "$DERIVED"` carries arms for only two.
   An `app-routed` instance therefore derives correctly, emits correctly, and
   then dies on the `*)` arm with *"internal: no required-key set for profile
   'app-routed'"*. That refusal is loud, named and correctly diagnosed as a
   defect in this file rather than in any input, so it is not a hazard — it is a
   mine for part 3, where `katmate-app-routed@` first exists. **Closing it is
   writing one `REQ_ENV` arm**, and it belongs to the part-3 commit that creates
   the template, not to a passing edit.

   *The standing risk underneath it, which does not go away when the arm is
   written:* the required-key sets are a **second place where per-profile
   knowledge lives**, the unconditional emissions above them being the first, and
   nothing measures that the two agree. This is not an ADR-032 §2 violation — §2
   governs profile **derivation**, and `f(class, netvm, nic)` still has exactly
   one implementation — but it is the same shape as the
   `validate-properties.fish` / `katmate-generate-env` schema split already
   recorded above: two statements of one truth, kept in step by discipline alone.
   The alternative was measured and rejected in the same session — checking the
   read-back against `emitted` alone is a round-trip of the writing and passes on
   a projection missing a key the profile needs, because the key is then absent
   from both sides of the comparison. A fixture that both must accept and one
   that both must refuse is the obvious check, and belongs with G5/H3.

   **Half of it is now measured, and the entry is otherwise unchanged
   (2026-08-21).** G5 and H3 ran that check against **one** implementation: the
   validator refused two forbidden keys (`persistence` on `class = sys`, `nic`
   on `class = app`) and one duplicate `nic` label, each as an error, each exit
   1. **`katmate-generate-env` was not run against the same fixtures**, so the
   two implementations still have nothing measuring their agreement and the
   drift risk above is exactly as it was.

   *The reason belongs on the record with the fact:* running
   `katmate-generate-env` against a fixture is a **start-path** action, and the
   host it would run on has netVM deliberately running — the G5/H3 brief scoped
   the session to the validator and its exit status for that reason, not by
   oversight. The fixtures survive at `/tmp/g5h3/` on MINIS and are the ready
   input for the generator half, but **`/tmp` there is a tmpfs**: they do not
   outlive a MINIS reboot. `~/3a2-g5h3-report.md` § 5 reproduces every one of
   them in full, so they are rebuildable from the report alone.

   **The read-back exists; the failure mode quoted above does not
   (2026-08-22).** A read-only verification pass on HEAD `d15e707` opened the
   question of whether this entry describes code that was ever written. It was
   written: `6ef40ac` (2026-08-19 14:43, +62 lines, one file) added it, which
   makes *"Added 2026-08-19 with the read-back itself"* accurate as to both date
   and provenance — `fe2b30f` added this entry 26 minutes later. Nothing was
   removed either: `git log -S 'no required-key set' --all` and `git log -S
   'REQ_ENV' --all` each return exactly those two commits, and no removal exists
   on any ref. That pass produced no report file; it was reported in chat.

   **What is wrong is the mechanism, and it has been wrong since two days before
   the read-back was written.** `katmate-generate-env:253` refuses `app-routed`
   unconditionally, above the emit block and far above the `case`:

   ```
   if [[ "$DERIVED" == app-routed ]]; then
       km_die "profile app-routed is derived and asserted, but AppVM link topology is not settled (ADR-029 C2) and no app-routed template ships. Nothing in this projection describes a link."
   fi
   ```

   `git log -S 'no app-routed template ships' --all` returns only `2a23473`
   (2026-08-17), and the guard is present in `6ef40ac` itself. An `app-routed`
   instance dies there — before the projection is written, before the `case` is
   reached. The `*)` arm is therefore **dead code for every reachable input**,
   and the diagnostic this entry quotes cannot be produced by any input.
   *"derives correctly, emits correctly, and then dies on the `*)` arm"*
   describes behaviour the file does not have.

   **The conclusion survives but grows, and the order is now part of it: closing
   this is two changes in one commit** — removing the guard at 253 *and* writing
   the `REQ_ENV` arm. Either alone is wrong. The guard removed alone produces
   exactly the failure this entry predicted, live. The arm written alone sets a
   second piece of dead code beside the first and changes nothing observable, so
   no gate could tell it had happened. **The mine is the guard, not the arm** —
   which inverts *"Closing it is writing one `REQ_ENV` arm"* above.

   *Readability, as its own observation:* line 109 admits `app-routed` as one of
   three valid profiles, and its `km_die` at 110 names all three again; line 253
   refuses it outright, 144 lines below, with nothing in between saying so. A
   reader who has read 109–110 does not learn that one of the three is
   unstartable.

   *Consequence for the fixture pair above:* until part 3, the
   cross-implementation fixtures must be built from `class = sys` and
   `app-offline` **only**. An `app-routed`-deriving fixture dies at 253 and
   measures the guard, not the rule under test.

20. ~~**`validate-properties.fish --strict` has never been executed.**~~ —
   **Closed 2026-08-22 by measurement, and accepted.** The gate this entry
   specifies at the end of its own text was run exactly as written: the same
   G5/H3 fixtures, hash-confirmed identical to the ones the plain-mode readings
   were taken on, run twice — once plain, once `--strict`. Source:
   `~/3a2-g6h1-report.md` part 1. What was measured:

   - **The `✓ veljavno` line is withheld** under `--strict` from a file whose
     only diagnostic is a warning. On the control pair, `app_web.toml` prints its
     `opozorilo:` line and **no** `✓`; the clean `netvm.toml` beside it keeps its
     `✓` in both modes.
   - **The tally counts the promoted warning, and says so in its own output** —
     control `skupaj: 0 napak, 1 opozoril` → `skupaj: 1 napak, 1 opozoril
     (--strict: opozorila štejejo kot napake)`; the H3 set `2 napak` → **`3
     napak`**. The G5 set reads identically in both modes, having no warning to
     promote, and that null result is recorded as one.
   - **Exit status 0 → 1** on the control pair, read twice in two shells — once
     as bash `$?`, once as fish `$status`, in separate invocations.
   - **The object this entry was built around — a `✓` printed beside a promoted
     warning — did not occur.**

   **Not measured, and therefore not claimed:** `--strict` in the no-argument
   form over the live `/etc/katmate/vm/`, and its interaction with an exit 2,
   which nothing in that run produced.

   **Two things survive this closure, and are put here because they will be read
   again.**

   1. ***This file's published claim is now evidenced rather than asserted — for
      one pair, and not for the live directory.*** The *Next steps* paragraph
      beginning *"Also carried in"* states that `--strict` *"cannot serve as a
      pre-commit gate over the real T1 set until AppVM link topology is
      settled"*; under `--strict` that pair exits **1** on the `app_web` warning
      alone, so what was a claim about an unrun mode is now its measured
      behaviour. **The provenance is stated exactly, because it bounds the
      claim:** the control fixtures are the pair G5/H3 built from the
      repository's `properties.toml` files, and **nothing in either session read
      the live `/etc/katmate/vm/`**. The statement is evidenced for that pair. It
      is **not** evidenced for the live directory, and that difference is the
      difference between a measurement and a generalisation of one.
   2. ***Under `--strict` the per-file severity word does not change.***
      `opozorilo:` stays `opozorilo:`, and **no `NAPAKA:` line appears** for the
      promoted file. The promotion lives in exactly three places — the **tally**,
      the **absence of the `✓`**, and the **exit status**. So a reader scanning
      per-file severities sees one warning and no error, while the tally and the
      status say one error; the two are reconciled only by the mode note on the
      tally line. This is consistent with the source, where `warn` increments the
      error count under `--strict` while still printing its own word, and nothing
      here calls it a defect. **Its consequence for anyone reading strict output:
      the tally and the exit status are the accounting; the per-file severity
      words are not.** That is also the shape of the sharp edge #20 existed to
      look for — it is simply not where the entry expected to find it.

   **The entry as it stood is kept below, because the gate it specifies is the
   gate that ran.**

   *As published 2026-08-21:* Added
   2026-08-21 with the G5/H3 run, which did not exercise it: S3.5 names neither
   row against it, so both gates were measured in the default mode and the flag
   stayed untouched. **What is unknown is the warning-versus-error accounting
   under it** — the flag's stated job is to make warnings count as errors, and
   nothing has observed it doing so.

   *Why this is not idle.* The G5/H3 control run measured the non-strict
   behaviour precisely: a file that raises a warning still prints **`✓
   veljavno`** and the directory exits **0**, because the per-file success line
   compares **error** counts and warnings do not touch them. Under the default
   mode that is arguably correct. Under `--strict` it is the one line whose
   meaning must change, and whether it does is unmeasured — a `✓` printed beside
   a promoted warning would be the *"silently wrong object"* this project keeps
   finding, in the tool built to catch it.

   *And this file already leans on the mode.* The *Next steps* paragraph
   beginning *"Also carried in"* states that `--strict` **"cannot serve as a
   pre-commit gate over the real T1 set until AppVM link topology is settled"**
   — a claim about the behaviour of a mode no gate has ever run. The claim may
   well be right; it is not evidence. *Gate, when it is worth one:* the same
   fixtures, run twice — once plain, once `--strict` — with the `✓ veljavno`
   line, the tally and the exit status compared across the pair. The `app_web`
   *web*-manifest-without-network warning is the ready-made input, being the one
   warning the real T1 set raises today.

21. **Every stop is a hard termination — the clean shutdown path exists and is
   not wired to the unit.** Added 2026-08-22, when the stop path first executed.
   **This is an unwired mechanism, not an open architectural question.** The
   clean path is decided, implemented and live-gated: `netvm-agent`'s SHUTDOWN
   opcode `0x05` signals netVM's own PID 1 with `SIGRTMIN+4` under `CAP_KILL`
   (ADR-024) — no bus, no `logind`, no polkit, so none of the dbus-free
   invariant applies to it. What is missing is one directive:
   **`katmate-sys-driver@.service` carries no `ExecStop=` or `ExecStopPost=` that
   invokes it**, so `systemctl stop` is SIGTERM to QEMU and the guest is killed
   where it stands. The template says as much in its own comment, and places the
   ordering in step 3b as the launch daemon's job — including refusing to tear
   down a `provides_network` VM with live dependents.

   **The measured consequence.** The 2026-08-22 stop produced no guest output at
   all, and the boot that followed it replayed the filesystem journal:
   `EXT4-fs (vda): recovery complete`, corroborated by the guest's own journald
   reporting its log *"corrupted or uncleanly shut down"*. Measured once, on one
   stop and the one boot after it — the general form, *a journal replay on
   `vm_sys_netvm` at every boot following a stop*, is what the mechanism implies
   and not what was measured.

   **The initrd carries no `fsck`** — `Warning: fsck not present, so skipping
   root file system`, from the same boot. So the repair is the **kernel's ext4
   journal replay alone**: journalled metadata is made consistent, and the
   filesystem is **never consistency-checked**. Nothing has measured whether it
   is otherwise sound. **This stays true after `ExecStop=` lands**, because a
   guest that misses `TimeoutStopSec` falls back to SIGTERM — a clean path
   reduces how often the replay happens, and does not remove the case.

   **The precondition on the wiring, and the order it forces.** The host has
   **never observed `netvm-agent` answering on vsock 1025** — only starting, as a
   line the guest's own systemd printed to a one-way console. So the order is:
   **(a)** gate PING and SHUTDOWN from the host, **(b)** then add `ExecStop=`,
   **(c)** then re-measure the stop path. Wiring before (a) would put an assumed
   mechanism precondition on the start path, and this project has buried two
   already: **ADR-021's QMP→ACPI→logind shutdown** and **ADR-025's Path A**, both
   accepted and both killed afterwards by a mechanism that was not there. This
   would be the third.

   *Carried with it, smaller:* **the stop deactivates no LV.** There is no
   teardown step today, and netVM does not need one — its rootfs is linear, stays
   active, and the open count simply drops to 0. **Disposable AppVMs will need
   one**, because their qcow2 delta must be destroyed; that is where the absence
   becomes a defect rather than a fact.

   *And the condition on what the 2026-08-22 measurement retires:* **the stop
   path was measured with QEMU running as root.** Once the `User=`/privilege
   split lands — it is in § *Next steps* as *Launch daemon / privilege split*,
   and is C1/C3/C5a of ADR-027's C-gate — SIGTERM goes to an unprivileged process
   in the cgroup. `KillMode=control-group` should still cover it, but *should*
   is the word, and **the measurement must be retaken**. This is a pass with a
   stated condition, not a new gate.

## Next steps

**ADR numbering.** `ADR-030` = *what the launch daemon reads* (2026-08-06).
`ADR-031` = the licence declaration (GPL-3.0 attribution for the
CYBRland-derived `desktop/` subtree) — **decision taken, document not written**;
the number stays reserved and the gap in the sequence is an honest record of
that. `ADR-032` = *where each tier lives* (2026-08-09).

**Next session: 3a part 2, the gates — G6 and H1.** G1 and G4 passed
2026-08-19 and G5 and H3 passed 2026-08-21; the two that remain are the two that
need netVM stopped. The code they
measure is written, installed and signed. The
**per-gate preconditions, what to observe and what counts as failing are in
`~/3a2-report.md` § S3.5**, written by the session that built the subject and
deliberately not summarised here — a second copy of a gate criterion is how a
gate ends up measured against the wrong wording, which is what happened to G1.

**Superseded in part, 2026-08-19 — read this block against the session entry at
the top of the file.** G1 and G4 have since run and the operator has ruled them
**passed**. Two statements here are contradicted by that run: *"nothing has
started a VM"*, and item 3's *"`katmate-sys-driver@.service` is still UNVERIFIED
in full"* — the template has now executed past `ExecStartPre=` and through
`ExecStart=`, while its stop path remains UNVERIFIED and the entry lists what
else the run did not exercise. **Gates still outstanding: G5, G6, H1, H3.** The
block is left as written rather than rewritten, because it is the carry-in the
gate session was actually given; how much of *"UNVERIFIED in full"* G1 retires
is a ruling and not a note's to make.

**Further, 2026-08-21.** G5 and H3 have since run and the operator has ruled them
**passed**; *"Gates still outstanding: G5, G6, H1, H3"* above is superseded and
**the list is now G6 and H1**. Appended rather than edited, for the same reason
the block itself was: it records the carry-in a session was actually given.

**Further, 2026-08-22, and this closes the list.** The stop path was executed,
and H1 and G6 have run and been ruled **passed**; *"the list is now G6 and H1"*
is superseded and **the list for step 3a part 2 is empty**. Every gate in scope
is measured: G1 and G4 (2026-08-19), G5 and H3 (2026-08-21), the stop path, H1
and G6 (2026-08-22). **G2, G3 and H2 are out of scope**, not outstanding — G2 and
G3 belong to the `.con` deletion and H2 to part 3, and none of the three has been
measured. Appended, on the same reasoning as the two notes above.

**Ruled 2026-08-19, and item 3 below carries it:** the pass retires the **start
path**; the **stop path** stays UNVERIFIED, and `katmate-activate-lvs` met an
already-active LV so activation from inactive is not claimed.

What the gate session must carry in, and what is *not* in the report:

1. **Preconditions in order.** rsync; **re-install** `/usr/lib/katmate/*` and
   both units from `~/katmate-build/host/` (a stale install is the
   rsync-then-cargo trap in another form); `systemctl daemon-reload`;
   `systemctl start katmate-publish-nics.service`, which is **not enabled**, so
   after a reboot nothing is published and `katmate-generate-env` refuses.
2. **netVM is DOWN and must stay down until the unit starts it.** A hand-started
   QEMU holding `vm_sys_netvm` would make G1 measure the workaround instead of
   the mechanism.
3. **G1 was executed on 2026-08-17 and FAILED, and
   `katmate-sys-driver@.service` was UNVERIFIED in full.** Both, because the
   failure was **above** `ExecStart=`: `EnvironmentFile=` without a leading `-`
   is loaded before every `Exec*`, so the absent projection failed the
   execution-environment setup before the `ExecStartPre=` that creates it was
   spawned. Nothing in the transcription of `net-sys.con` was exercised, and
   `systemd-analyze verify` still passes — which is a parse, not a start. The
   correction is committed (ADR-030 revision note 2026-08-19: the directive is
   now `EnvironmentFile=-`, and the refusal it carried moved into
   `katmate-generate-env`'s read-back, itself UNVERIFIED). G1 was re-run on
   2026-08-19 after that correction and reached `ExecStart=`, with QEMU running
   under the unit; G4 was the observation about the same start.
   **"UNVERIFIED in full" is withdrawn as of 2026-08-19 and kept above as what was
   published.** What the pass retires is the start path — the three
   `ExecStartPre=`, the `EnvironmentFile=` load, the argv, and the VMM as a child
   of the unit. What it does not touch is the stop path —
   `KillMode=control-group`, `TimeoutStopSec=30s`, SIGTERM with no graceful guest
   shutdown — which first executes at the next `systemctl stop` and is settled by
   a stop ending QEMU within 30 s against a guest journal showing whether the
   filesystem was remounted read-only first. One preflight also ran without work
   to do: `katmate-activate-lvs` met an already-active linear LV, so activation
   from inactive under systemd is not claimed. Gate criteria stay in
   `~/3a2-report.md` § S3.5; the outstanding gates are G6 and H1 (G5 and H3
   passed 2026-08-21, on fixtures and the validator alone — neither touches this
   template).

   **The stop path executed 2026-08-22, and the pair this item names as settling
   it was observed in full.** A stop ending QEMU within 30 s: **0.441 s**, with
   no `SIGKILL` and no escalation. A guest journal showing whether the filesystem
   was remounted read-only first: it shows **nothing at all** — the guest emitted
   no console output between the SIGTERM and the deactivation, which is the
   answer *"it was not"*, arrived at by absence rather than by a line. **The stop
   path is therefore no longer UNVERIFIED**, and the outstanding-gate sentence
   above is superseded: nothing in scope for part 2 remains. Two conditions ride
   with that, and neither is a new gate: the measurement was taken with **QEMU
   running as root** (see open problem #21 for what the `User=` split obliges),
   and `katmate-activate-lvs` met an already-active LV again at both the H1 and
   the G6 start, so **activation from inactive is still not claimed**.
4. **What is still not shippable:** `katmate-app-offline@` (part 3, and its gates
   need an `app-web.meta` that does not exist), and the deletion of both `.con`
   files, which is 3a's last commit and only if every line is placed. Deletion
   creates dangling references in `SECURITY-MODEL.md` (#11 describes
   `net-sys.con` as the thing running QEMU as root), `HOST-CONFIG.md` §3 and §6,
   `DECISIONS.md` and this file — repaired in the **same** commit, because that
   drift is created by it rather than inherited, and G3 is *"nothing was lost"*.

Implementation session, thinking-off. Carry in: the validator's exit codes are
three-valued; and the live delta is still named `test_web.qcow2` while
`katmate-check-image` looks for `app_web.qcow2` (ADR-032 §7 — the rename is
outstanding).

**The getty prediction this paragraph carried was wrong, and G1 measured it
wrong (2026-08-19).** It read *"the guest's `serial-getty@ttyS0` may
restart-loop on the one-way console's EOF stdin, which the journal will show
plainly and which is a manifest question, not a template one"*, and it was the
last live copy of a prediction that also stands in `~/3a2-report.md` § S3.5.
**Measured:** four getty-related lines in the whole guest boot — the slice, the
`Started serial-getty@ttyS0.service`, `getty.target`, and one
`localhost login:` prompt — with no repetition, nothing rate-limited, and no
console output at all in a window of nearly two minutes past `Link is Up`. The
journal would have shown a loop plainly, as the prediction itself said. It
showed none.

**One reading taken outside any delegated session.** On MINIS at 15:47 on
2026-08-19, with 706658 still alive, the operator read:

```
$ sudo ls -l /proc/706658/fd/0
lr-x------ 1 root root 64 Aug 19 15:26 /proc/706658/fd/0 -> /dev/null
```

That settles one half, and one half only: **QEMU's chardev input is at EOF from
the start**, so the premise the prediction rested on was true — and twenty
minutes past the boot the process was still alive on that same descriptor, with
the login prompt still standing. It does not say why the one did not produce
the other.

**HYPOTHESIS (unproven, unrefuted) — why the EOF does not reach the guest.**
Reasoning, not measurement: an emulated 16550 UART has no end-of-stream
condition, so the guest's `read()` on `/dev/ttyS0` blocks rather than returning
0. The EOF is a property of the **host** file descriptor and does not cross into
the emulated device. It would cross on a transport that carries link state —
`virtio-console` propagates a host-side port close as a hangup — which is why
the prediction was plausible and still wrong. *Gate:* in-guest,
`serial-getty@ttyS0`'s agetty in state `S`, `/proc/<pid>/fd/0 -> /dev/ttyS0`,
and a blocked read. **Not reachable today:** the console is one-way into the
host journal and `netvm-agent` has no RUN opcode, so no `ps` or `/proc` read
inside netVM is possible at all. That the gate is unreachable is part of this
record, not a step toward anything.

**The prediction class, and this project already has a family of it: host-side
descriptor semantics assumed to propagate into an emulated device.** Same shape
as the ADR-021 trap where `SIGRTMIN+1` had to mean reload because
`Type=notify-reload` implied it, and killed `networkd` instead. The **class** is
on the record; the mechanism above stays a hypothesis.

**Three things part 2 had to resolve before a gate could run — all three settled
by the 2026-08-11 session; kept with their outcomes because each one is a
precondition a later gate is still read against.**

- **~~Both T1 files exist only on the Acer~~ — done 2026-08-11.** The staging
  tree is `local/etc/katmate/vm/` in the repository (ignored via `.gitignore`),
  it travels with the ordinary rsync, and both files are installed on MINIS at
  `/etc/katmate/vm/`, `root:root 0644`, verified by `cmp` and hash against the
  source. `~/katmate-t1/` no longer exists. Still a hand-copy: installer
  provisioning is build-order step 6 (`docs/HOST-CONFIG.md`).
- **~~`/var/lib/katmate/kernels/` does not exist~~ — the directory now exists
  and holds the kernel, but only because it was placed there by hand.**
  `build/foundation.sh` installs it as of `d4224fb` and **has not been run**, so
  that path is UNVERIFIED and first executes at the next foundation rebuild. The
  three-locations problem below is unchanged for `app_web.con`, which still
  reads `$KERNEL_SRC_DIR` directly:
  `app-web.meta` records *which* kernel (`KERNEL_VERSION=6.12.87`) per ADR-032
  §5, but a unit's `-kernel` needs a path. The AppVM kernel lives in
  `$KERNEL_SRC_DIR` today and is copied into `out/` by the Makefile, and
  `app_web.con` reads it from `$KERNEL_SRC_DIR` directly — three locations, none
  of them the ADR-032 one.
- **~~The `trap - EXIT` relocation in `netvm.sh` is UNVERIFIED~~ — VERIFIED
  2026-08-11, in both directions**, by injecting failure from outside the script
  (invalid mirror → LV removed; `chattr +i` on the parent of the step-11 target →
  LV standing, rollback provably silent). A clean third run verified step 11 in
  the writing direction. The pair, as it was stated and as it was measured: a
  failure in steps 1–10 must still remove the LV; a failure in step 11 must
  leave it standing. That pair is the whole point of the move.

**Also carried in:** the validator's exit codes are three-valued (0 valid, 1
schema error, 2 usage / nothing validated), so a gate script must not treat
non-zero as uniformly invalid. `validate-properties.fish --strict` cannot serve
as a pre-commit gate over the real T1 set until AppVM link topology is settled —
the `web`-manifest-without-network warning it raises on `app_web` is true, and
was deliberately not silenced.

**Measured 2026-08-22, with its bound.** That second sentence was a claim about a
mode nothing had run. It now is not: under `--strict` the real T1 pair exits **1**
on the `app_web` warning alone. **Evidenced for that pair only** — the fixtures
are built from the repository's `properties.toml` files, and nothing has run the
validator over the live `/etc/katmate/vm/`. Closed open problem #20 carries the
measurement and the rest of the bound.

**New as of 2026-08-17, and unmeasured: the T1 schema has two implementations.**
`tools/validate-properties.fish` (fish, developer-side, installed on no host) and
`katmate-generate-env` (bash, on the start path) both enforce it — the second
because ADR-032 §3 requires a forbidden key to be rejected *at parse*, and
parse-at-start happens on the host. Structural rules in the executable, semantic
warnings in the validator. **They must not disagree** (ADR-015 states that
discipline about itself), and nothing yet measures that they don't: a fixture both
must reject is the check, and it belongs with G5/H3. This is a standing drift risk
of exactly the class this project keeps finding, recorded here rather than in a
commit message so it is read before the next schema change, not after.

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
the repository rule is en_US throughout (decided 2026-08-09). Own commit. The
item is also stated in `CLAUDE.md` § *Language*; that is a routing pointer, not
a second source, and the two do not need reconciling.

**Pair the `LC_ALL=C` pin with that translation — same commit, decided
2026-08-21.** G5 measured that the validator's duplicate-`nic` diagnostic
accuses a **locale-dependent** file: it enumerates with `find … | sort` and
raises the error on whichever file is processed **second**, so `LANG=en_US.UTF-8`
and `LC_ALL=C` swap which of the two filenames the message names. **The rule is
unaffected** — the pair is rejected either way, one error, exit 1 — but the
diagnostic reads as an accusation of one specific file, and on an installation
target the locale is not known. Both changes touch every `err` and `opozorilo`
site, both are about what the validator tells a human, and doing them separately
opens the file twice for one concern. Neither was done in the session that found
it: no file under `tools/` was edited there.

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
- **`systemctl start` on a `RemainAfterExit=yes` oneshot is a silent no-op —
  `restart` is the verb.** `katmate-publish-nics.service` is re-run with
  **`restart`**, never `start`: the unit is already `active (exited)`, so `start`
  returns **0**, does nothing, and leaves the stale output standing. Measured
  2026-08-22 at G6's undo, where the label kept the injected `NIC_VENDOR` and its
  injected hash across a `start` that reported success. Anyone writing *"re-run
  `katmate-publish-nics`"* into a procedure has to write `restart`. **The
  bounding property, so this is not read as worse than it is:** a stale label
  cannot reach a VM, because refusing exactly that is what gate G6 measures — the
  start dies at `katmate-generate-env` before QEMU. The hazard is a silent no-op
  during *repair*, not a stale label in production.
- **Hash the installed set as the first action of every gate session.**
  `/usr/lib/katmate/*` and both units, against the Acer repository, **before any
  gate runs**. A gate measures the *installed* copy; without the hash the result
  rests on an unstated assumption that the install equals the tree. That is the
  gap `~/3a2-g6h1-report.md` § 3.1 had to name after the fact — the check was
  taken later the same day and matched across three legs, but a check taken after
  the measurement cannot support it. mtime is not a substitute: the `sync.fish`
  invariant below is precisely that rsync preserves mtime, so an old file can
  look current.
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
- **The stuck-`jbd2` test answers "may I `lvremove` now?", not "is the image
  sound?".** The entry above and the one under *Next steps* describe this
  symptom correctly, but both describe a past incident — neither is a test, and
  at the decision point there was no named check. Before any `lvremove` on a
  build LV, run both:

  ```
  sudo dmsetup info /dev/<vg>/<lv> | grep 'Open count'
  ps aux | grep "[j]bd2"            # look for [jbd2/dm-N-8] with N = this LV's dm
  ```

  Open count `0` **and** no matching `jbd2` kthread → safe to `lvremove`.
  Anything else → **reboot; do not force `lvremove`.**

  **`mount` is not the condition.** An LV can be cleanly unmounted and still
  open with a live journal thread — measured 2026-08-11. **`lsof` and `fuser`
  cannot see it either**, because a kthread holds no fds; `fuser` returns exit 1
  on exactly the device that is stuck. Map the LV to its `dm-N` with
  `dmsetup ls` or `ls -l /dev/<vg>/` before reading the `ps` output — the number
  is not stable across boots.

  **This says nothing about image integrity.** A *successful* `netvm.sh` run
  leaves the device held too: measured 2026-08-11 run 3, where `dumpe2fs -h`
  reported `Filesystem state: clean` while `Open count: 1` and `[jbd2/dm-10-8]`
  persisted. The device being held is a fact about `lvremove`, not about the
  filesystem.
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
  its locally-administered MAC (ADR-025), not on a name; the older
  `10-personal.network` / `Name=enp0s4` convention described the retired pet
  launcher and is void.
  **The *Pending (2026-08-09)* note that stood here is closed 2026-08-19, and
  the value is `52:54:00:21:b2:08`.** The note said ADR-025's revision note
  replaces authored MACs with `52:54:00` + `sha256(instance)[0:3]`, and that the
  authored `52:54:0a:64:01:01` this entry named would be stale from the moment
  the projection generator landed. **It has landed and run.** G1 measured
  `katmate-generate-env` emitting `KM_MAC_INT=52:54:00:21:b2:08` and QEMU
  running with it, so the note recorded a prediction that came true rather than
  one outstanding. Its second half held as well: no image rebuild was implied —
  the guest bakes no internal-segment `.network` unit — and the guest booted on
  the derived MAC without complaint. **`net-sys.con:27` still hands QEMU the
  authored value**, so until the `.con` deletion (G3) the segment's MAC depends
  on which launcher starts netVM.

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
  `ulimit -l unlimited` before launch is therefore **mandatory on the manual
  path** — which, until 2026-08-19, was the only path there was.
  **A unit is now a path too (measured 2026-08-19, G1).**
  `katmate-sys-driver@.service` carries `LimitMEMLOCK=infinity`, and the QEMU it
  started holds `Max locked memory unlimited` with vfio's full-RAM pinning
  succeeding at 1 G resident. This entry read *"mandatory, and today it is the
  only path: there is no `netVM.service`"* until that run, and the sentence was
  true when written — the only unit that had ever existed was a March *user*
  unit pointing at the retired `net.con`, long disabled and removed 2026-07-25,
  which is why an earlier version of this entry naming one as "the production
  path" was wrong. **The invariant underneath is untouched:** VFIO pins the
  entire guest RAM, so the limit has to be lifted somewhere. What changed is
  only where — a directive rather than an interactive shell — and for a manual
  `sudo bash net-sys.con` the `ulimit` is still not a workaround but the
  mechanism.

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
