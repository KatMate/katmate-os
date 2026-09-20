# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Milestone:** v0.2 (in development) · **Last updated:** 2026-09-14
(the ADR-035 measuring arc of **2026-09-12 … 2026-09-14**, recorded under one
heading because write pass B transcribed the five gate sessions of 2026-09-12
into the living sections without a dated heading of their own, and one heading
above both arcs closes that gap rather than burying it deeper. The substantive
finding is a condition and not a new measurement: **every measured delivery
across a slot was into a receiver with `IFF_PROMISC` set**, and the same pair
was measured failing without it — so no frame has yet been shown to cross a
slot on its own destination address. ADR-035's revision note of 2026-09-14
carries it, with the six readings as one table. **One rotation was performed:**
the 2026-09-05 *second of two* entry to `docs/SESSIONS.md`, because the file
keeps two).

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

Direction unchanged: IOMMU-capable platforms only (VT-d/AMD-Vi).
MINIS is primary host and merge target.

## This session (2026-09-15) — the ACL mechanism is measured, and `RuntimeDirectory=` is measured to undo assignment-time ownership

**Documentation only.** No code was written, no unit was changed, no sysctl was
set, and no ADD or REMOVE was issued. The measurements this entry records were
taken on MINIS earlier the same day, in two passes, against systemd on Arch, on
the boot of 2026-09-05. **ADR-035's revision note of 2026-09-15 carries all
nine numbered items in full** — they are not duplicated here; what follows is
only what belongs to this file.

**Reports outside the repository:** `~/Claude.assistent/acl-report.md` and
`~/Claude.assistent/acl-report-b.md`. The second pass re-took three gates that
the first brief had written defectively.

**The five ACL gates, one line each.** POSIX ACLs are available where the tree
lives — `CONFIG_TMPFS_POSIX_ACL=y`, `/run` is `tmpfs` — and the same `setfacl`
is refused `Operation not supported` on `proc`, `sysfs`, `cgroup2` and `vfat`.
`bind()` applies the umask, and a default ACL does not override it. Removing a
named ACL entry reaches an already-running sender: the **same** process is
refused `EACCES` with no signal delivered and no restart of either side, and
delivers again once the entry is restored. The sticky bit refuses an unlink
that directory write permission allows, so a slot directory that grants an
AppVM write and does not carry `+t` lets that AppVM delete its own `owner` and
make an occupied slot read as FREE. `chmod` on an object carrying an access ACL
rewrites the ACL mask.

**`RuntimeDirectory=` returns the directory and the node bound inside it to
`root:root` at every start, restores the directory to `0755`, and leaves no
named entry, no `mask::` and no `default:` entry on either.** Both inodes
survive the restart; the ownership and the ACLs do not. The ownership rule of
the 2026-09-07 revision note — *"the launch daemon sets ownership at assignment
and returns it at release"* — therefore does not survive a netVM restart under
this directive, and no ACL placed beside it would either. **§5's creation
mechanism is consequently reopened, not settled.** The `ExecStartPre=` T4
helper §5 names as its fallback re-asserts nothing at start if it is written
idempotent and non-destructive, and a default ACL then survives a netVM
restart; keeping the directive instead obliges the launch daemon to re-apply
ownership and ACLs after every netVM start. **Neither was decided**, and the
choice is the operator's.

**`UMask=0007` is load-bearing on both QEMU templates, and its absence fails
silently.** Under `umask 0022` the bound node comes up `0755` with `mask::r-x`
and the named `rw` entry reads `#effective:r--`: `getfacl` shows a
correct-looking entry while the peer cannot send.

**Mode first, ACL second, `getfacl` read-back third.** Any `chmod` issued after
a `setfacl` rewrites the mask and can render every named entry ineffective.
Recorded in § *Invariants & gotchas* as well, because it binds every writer of
this tree and not only this session.

**The 2026-09-14 apparatus was not entered.** Nothing was read or written under
`/run/katmate/link/`, and no `katmate*` unit was started, stopped, restarted or
reloaded. Its figures stand as of the 2026-09-14 entry and were **not re-read
here**: `MainPID 3628111`, `NRestarts=0`, boot 2026-09-05 20:10:29.

**This file now carries three session sections, and rotation was not
performed.** § *Session archive* keeps two. The 2026-09-07 section is the one
due to rotate to [docs/SESSIONS.md](docs/SESSIONS.md); it was left in place,
with its heading untouched, because the brief for this pass reserved the
rotation to the operator.

## Previous session (2026-09-12 … 2026-09-14) — the ADR-035 gate arc and its close: every measured delivery across a slot was into a promiscuous receiver

**One heading covers two arcs, and the body below is the second of them.** The
five gate sessions of 2026-09-12 were transcribed into § *Live state*,
§ *Next steps* and § *Invariants & gotchas* by write pass B (`facf437`) and were
given no dated heading of their own; their material stands in those sections and
is not repeated here. This heading covers them, which is what closes the
archive's own gap — a session without a dated heading cannot later be rotated,
and the trim destroys it instead (§ *Session archive*, where the rotation this
entry arrived by is recorded).

**The 2026-09-14 arc is four delegated sessions** — the harvest, the promisc
discriminator, the multicast read pass, and write pass C. **One commit of
substance, `adecc5f`, and it is not pushed.** Reports outside the repository:
`harvest-report.md`, `promisc-report.md`, `mcast-read-report.md` and
`writec-report.md`. **ADR-035's revision note of 2026-09-14 carries the five
findings, the six-row table and the rewritten G5b clause** — it is not
duplicated here; what follows is only what belongs to this file.

**The condition every slot measurement has been taken under.** No frame has ever
been shown to cross a slot on its own destination address. **Every measured
delivery across a slot was into a receiver with `IFF_PROMISC` set, and the same
pair was measured failing without it** — both directions, both flag values, the
flag being the only difference in each pair. **Nothing here says the transport
does not carry: it carries, under promisc.** What is unshown is *addressed*
delivery — a frame accepted because it was addressed to the receiving interface
rather than because that interface was accepting everything. This line is in
`state.md` and not left to the ADR because `grep -i promisc` over this file
returned **nothing** until now: a cross-reference would have pointed at nothing,
and the next session to measure slot traffic without the condition will
re-derive it.

**The apparatus is still alive, and whoever picks this up next must not assume
otherwise.** All four sessions ran on one boot and it survived them: host
`uptime -s` **2026-09-05 20:10:29**, netVM **MainPID 3628111**, `NRestarts=0`,
unrestarted since 2026-09-12 09:59:37 CEST. **The dev console is at a live root
shell** — no login step, and no credential need be spent. **Slot 01 is left
released**, links **200** and **202** are installed, and the fixtures on slots
**01** and **02** are still bound. Exactly one state change was made across the
three read sessions — `IFF_PROMISC` on `km00`, set and cleared the same morning,
both halves confirmed by read-back — and no code, no unit, no sysctl and no ADD
or REMOVE. **The next netVM rebuild ends all of it**, so any reading that needs
this apparatus is taken before the code pass or not at all. Slot inodes, fixture
PIDs and the instruments left on MINIS are in the reports, not here.

**One precondition is recorded as unmeasured, because it governs a change
someone will want to make.** Whether `systemd-sysctl` runs **before or after**
udev renames the sixteen virtio devices to `km00`…`km0f` has never been read,
and the values available cannot settle it: `net.ipv4.conf.default.rp_filter` is
**2**, so an interface created after `systemd-sysctl` ran inherits 2 either way,
and the observed 2 on all sixteen slots discriminates neither order. That is a
reason the question is open, not a reason to treat it as answered.

## Session archive

Rotated sessions are enumerated in `docs/SESSIONS.md`, newest first; that
file is the record and this one keeps no copy of it. It was split out on
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

**Closed 2026-09-14.** The 2026-09-05 *second of two* entry (ADR-035 records what
G1 measured: two ceilings, and four places the ADR does not match them) rotated to
the archive as the 2026-09-12 … 2026-09-14 entry arrived, so the file never held
three at any point between the two commits — the 2026-08-22 rotation's condition,
applied again. Same mechanism, same check: the heading changed from *Previous
session* to *This session*, the body moved verbatim, verified by hashing it with
the heading line dropped before and after — **identical,
`8fb1d520ecefe2db…`** — and by re-extracting the block from `docs/SESSIONS.md` at
its new home and diffing it against the pre-move block, the diff being exactly one
line, its heading. `docs/SESSIONS.md` gained 50 lines and lost none. It was
inserted at the head of the entry list, **above** the 2026-09-05 *first of two*
entry — newest-first, and *second of two* above *first of two*, both conventions
applied again rather than newly taken. **No ordinal changed:** 2026-09-05 still
holds exactly two entries and they are still counted as two.

**The arriving entry's heading spans two dates, and that is what repairs this
section's own gap.** Write pass B (`facf437`) transcribed the five gate sessions
of 2026-09-12 into § *Live state*, § *Next steps* and § *Invariants & gotchas*
and wrote **no dated heading** — its brief did not ask for one. Under this
section's own rule that is not a tidy omission but the condition that destroys an
entry rather than archiving it: *a session without a dated heading cannot be
archived, and the trim that would otherwise remove it destroys it instead.* **The
operator ruled one heading above both arcs** rather than a retrospective entry
beneath the newer one — they are one measuring arc closed by two documentation
passes, and the 2026-09-12 material is already placed in the living sections.
**No content was invented for 2026-09-12:** the entry's body is the 2026-09-14
arc, and the heading is what a future rotation will move.

**Closed 2026-09-07, and it is one rotation for four sessions.** The 2026-09-05
*first of two* entry (ADR-035 G1b: the ceiling is 26, and the seventeenth device
is not refused) rotated to the archive as the 2026-09-07 entry arrived, so the
file never held three at any point between the two commits — the 2026-08-22
rotation's condition, applied again. Same mechanism, same check: the heading
changed from *Previous session* to *This session*, the body moved verbatim,
verified by hashing it with the heading line dropped before and after —
**identical, `f397d8e445590fd9…`** — and by re-extracting the block from
`docs/SESSIONS.md` at its new home and diffing it against the pre-move block,
the diff being exactly one line, its heading. `docs/SESSIONS.md` gained 69 lines
and lost none. It was inserted at the head of the entry list, **above** the
2026-09-04 entry — newest-first, the ruling of the 2026-09-04 rotation applied
again, not a new convention. **No ordinal changed:** *first of two* counts the
entries of 2026-09-05, and that day still has exactly two.

**One rotation, and four sessions arrived in the single entry it made room
for.** The netVM rebuild, the push, ADR-035 G5a and the consolidation of the
pool scaffolding ran between the evening of 2026-09-05 and 2026-09-07; the
operator ruled them **one arc with one outcome**, recorded under one dated
heading rather than four. The archive's own rule — a session without a dated
heading cannot later be archived — is satisfied by that heading, which is the
heading a future rotation moves. The five reports stay outside the repository
and are named in the entry.

**Closed 2026-09-05, and it is two rotations in one commit.** Both entries left
this file together — the 2026-09-04 entry (ADR-035 G1a: the sixteen-slot pool
boots, and the console procedure burns a credential) and the 2026-09-03 *third
of three* (ADR-035 §5 and the `remote` parameter) — because 2026-09-05 held two
sessions and the file keeps two. Same mechanism, same check: the bodies moved
verbatim, verified by hashing each body with its heading line dropped before and
after — **identical, `da1afd42d0a35fb3…` and `3b6a9bed4ee0992d…`** — and by
re-extracting each block from `docs/SESSIONS.md` at its new home and diffing it
against the pre-move block. `docs/SESSIONS.md` gained 122 lines and lost none.

**Only one heading changed, and that is the difference from every rotation
above.** The 2026-09-03 entry's *Previous session* became *This session*, the
archive's uniform convention; the 2026-09-04 entry was **already** *This
session*, so its block diffs clean including its heading rather than in one
line. The order is newest-first, inserted at the head of the entry list: the
2026-09-04 entry above the 2026-09-03 *third of three*, both above the *second
of three* already there — the 2026-09-04 rotation's ruling applied again, not a
new convention.

**Closed 2026-09-04, and it is two rotations in one commit.** Both 2026-09-03
entries left this file together — the *second of two* (the netVM rebuild and the
in-guest console) and the *first of two* (the ADR-035 G1 halt) — because two
entries arrived at once and the file keeps two. Same mechanism, same check: the
bodies moved verbatim, verified by diffing each extracted block against its
pre-move blob in `HEAD` and by hashing the bodies with the heading line dropped
— **identical, `3d3199e17efa55fe…` and `ae73a0cce49560b7…`** — with the diff of
each whole block being exactly one line, its heading. `docs/SESSIONS.md` gained
233 lines and lost none.

**The headings changed in two ways, and one of them is a correction of a
count.** *"of two"* became *"of three"* on both, because **2026-09-03 held three
sessions** — the G1 halt, the rebuild, and the ADR-035 §5 revision note — and
the third had no entry when the other two were written, so their counts were
wrong from the day they were published. The note session's own entry is written
in the same commit, below. And *Previous session* became *This session* on the
G1 entry, which is the archive's uniform convention and the same change every
rotation above has made. **Neither is a revision of a record:** one is an
arithmetic correction to a count that a later fact falsified, the other is the
form the archive keeps.

**The order they were inserted in is newest-first, and it was ruled rather than
assumed.** The rebuild sits above the G1 halt, both above the 2026-09-02 entry,
inserted at the head of the entry list — not appended at EOF. The brief said
*"appended in chronological order"*, which is ambiguous between the resulting
order and the order of the two operations, and *"appended"* is wrong under
either reading, since the entry list begins after a preamble and a rotation
inserts into it. The operator ruled the tree's convention governs: newest-first,
as the archive's own preamble states and as all three existing same-day pairs
(2026-09-01, 2026-08-19, 2026-08-09) already arrange themselves.

**Closed 2026-09-03, and this is the second rotation of that day.** The
2026-09-02 entry (the ADR-035 arc) rotated to the archive as the 2026-09-03
*first of two* entry was written up, because the file keeps two and that day
turned out to have two sessions rather than one. Same mechanism, same check: the
heading changed from *Previous session* to *This session*, the body moved
verbatim, and the moved copy was verified by re-extracting it from
`docs/SESSIONS.md` and hashing it against the pre-move body — **identical,
`932a23a35c910d40…`**. Two rotations on 2026-09-03 is not a defect; it is what
keeping two sessions costs when a day holds two and the second is written up
after the first. **The ADR-035 G1 session is recorded retrospectively**, by the
day's second session, and sits *below* it: newest-first, and it had no heading
of its own until then — which is precisely the condition this section warns
destroys an entry rather than archiving it.

**Closed 2026-09-03.** The 2026-09-01 *second of two* entry (the sidecar
travels, and the path it travels from does not resolve as root) rotated to the
archive as the 2026-09-03 entry arrived, so the file never held three at any
point between the two commits — the 2026-08-22 rotation's condition, applied
again. Same mechanism, same check: the heading changed from *Previous session*
to *This session*, the body moved verbatim, and the moved copy was verified by
re-extracting it from `docs/SESSIONS.md` at its new home and hashing it against
the pre-move body — **identical, `09539119cbf583a6…`**. It sits **above** the
2026-09-01 *first of two* entry, because newest-first puts *second of two*
first; that is the 2026-08-19 pair's arrangement applied again, not a new
convention. No ordinal changed.

**Closed 2026-09-02.** The 2026-09-01 *first of two* entry (kernel provenance —
the witness, the tool gate and the defect it found) rotated to the archive as the
2026-09-02 entry arrived, so the file never held three at any point between the
two commits — the 2026-08-22 rotation's condition, applied again. Same mechanism,
same check: the heading changed from *Previous session* to *This session*, the
body moved verbatim, and the moved copy was verified three ways rather than one —
the extracted block diffs against the pre-move blob in exactly one line, the
heading; the bodies hash identically (`243d3209…`); and the copy re-extracted
from `docs/SESSIONS.md` at its new home diffs clean against what was written,
with the pre-move block diffing clean against `HEAD` as the control. No ordinal
changed: the entry keeps *first of two*, because the day it belongs to is still
2026-09-01 and its pair is still above it here.

**Today's other two runs have no heading of their own, deliberately.** The read
pass and the splice repair are recorded inside the 2026-09-02 entry as runs 1 and
2 of one arc, with their commits, rather than as two more dated headings. The
operator ruled it: they are one continuous piece of work on ADR-035, and the
*first of two* / *second of two* convention exists for a day's genuinely separate
sessions. Recorded here because the archive's own rule is that a session without
a dated heading cannot later be archived — these three are covered by one
heading, and that is the heading a future rotation moves.

**The list sentence at the head of this section was NOT updated, and is stale.**
It reads *"Sessions older than the two above (2026-08-21 — G5 and H3, rotated
there 2026-08-24 — then …)"*, and it already omitted the 2026-08-22 and
2026-08-24 entries before this rotation; it now also omits 2026-09-01 *first of
two*. It is left as written rather than repaired in passing, on the same
reasoning as the two stranded cross-references below: a navigational sentence
that is known stale is cheaper than one silently rewritten by a session that was
not asked to. It is work for whoever next has a reason to touch it.

**Closed 2026-09-01 (second of two).** The 2026-08-24 entry (the link
measurement arc) rotated to the archive as the second 2026-09-01 entry arrived,
heading changed from *Previous session* to *This session* and the body moved
verbatim — the same mechanism as the rotations above. Verified by diffing the
extracted block against the pre-move blob. Two sessions on one day are recorded
*first of two* / *second of two*, as the 2026-08-19 and 2026-08-09 pairs already
are.

**Closed 2026-09-01.** The 2026-08-22 entry (the stop path, H1 and G6) rotated to
the archive as the 2026-09-01 entry arrived, heading changed from *Previous
session* to *This session* and the body moved verbatim — the same mechanism as
the rotations above. Verified by diffing the extracted block against the pre-move
blob: 155 lines, identical apart from that one heading word. Recorded here
because a rotation that is not recorded is indistinguishable from an entry that
was lost.

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
  **6.12.107+deb13-amd64**, last rebuilt **2026-09-05 20:40:32Z** — was
  `6.12.101+deb13-amd64` on 2026-08-11 and `6.12.96+deb13-amd64` from the
  2026-07-23 build, and the change is trixie moving under a declarative
  manifest, not a defect; the 2026-09-05 build did **not** move it, `vmlinuz`
  being 12,142,528 B, identical in size to the 2026-09-03 export). **That build
  also landed ADR-035 §8**: sixteen exact-match `.link` files at
  `/usr/lib/systemd/network/70-katmate-slot-<kk>.link`, baked by step 5's
  `cp -a` from `manifests/netvm.conf.d/` and needing no edit to `netvm.sh`; the
  slots come up `km00`…`km0f` and the uplink is untouched, an exact
  `MACAddress=` being unable to glob onto it. The initrd's compressor moved
  **gzip → zstd** on the same build and it boots. Boots through full
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
  deliberately unlocked for console observation (open problems #11/#12) — from
  a **rotated** `KATMATE_DEV_ROOT_HASH` as of the 2026-09-05 build, proved by a
  login and not by the build's read-back (#29, now closed). Still
  unverified from inside: **WireGuard/ProtonVPN bring-up** and the DNS-leak
  policy. The peer end of the internal segment does not exist — personalVM was
  deleted and no AppVM carries a network device yet (ADR-029 C2).
  `memlock` via `LimitMEMLOCK=infinity` (unit) or `ulimit -l
  unlimited` (manual launch). Runs independently of app_web.
  **WHAT IS RUNNING TODAY IS NOT THIS UNIT (2026-09-05; unit corrected
  2026-09-07).** netVM is started by `katmate-pool@netvm.service`, the ADR-035
  G1 scaffolding template — **consolidated on 2026-09-07 to carry
  `RuntimeDirectory=` naming the sixteen slot directories and
  `RuntimeDirectoryPreserve=yes` folded in**, and hash-confirmed
  `1d727b2542633a5135d5c266c074961df5cf558dc29713a06db82dea12b0201d`, 13021
  bytes. **The value
  `873c4320658c74aec4919f0dbd64e0f1883becd8871aa797057c2332720288b5` is
  historical from 2026-09-07 14:49 and is still named in several briefs and
  reports.** The two variants the G5a gate ran on, `katmate-pool-rd@.service`
  and `katmate-pool-rd-nopreserve@.service`, are **gone** — removed from disk
  and `not-found` to systemd; folding rather than deleting kept the
  `90-dev-monitor.conf` drop-in, which the `-rd` variants lacked, so G5b will
  not meet a `208/STDIN` mid-gate. **It is running: MainPID 3628111,
  invocation ID `795c97e533c54b7a8eb16cf5b95d3c50`, `NRestarts=0`, active
  since 2026-09-12 09:59:37 CEST.** The prior MainPID 943031 died in a
  `systemctl restart` deliberately run with no sweep and no `ExecStopPost=`:
  all sixteen `netvm` nodes rebound at new inodes and no `EADDRINUSE`
  occurred (source: `g5b-restart-report.md`) — while
  `katmate-sys-driver@netvm.service` is **inactive**. The two must never run
  at once: same instance name, same LV, same CID, same VFIO device. The pool
  unit replaces the single `tap-int0` device with sixteen `dgram` slots, so
  the guest carries **no internal-segment interface and eighteen links, not
  nineteen**; host-side `tap-int0` and its networkd `.netdev`/`.network` are
  untouched and still exist. Two untracked, per-machine files carry it, both
  under `/etc` and both surviving a host reboot that the FIFO does not:
  `/etc/systemd/system/katmate-pool@.service` and
  `/etc/systemd/system/katmate-pool@.service.d/90-dev-monitor.conf`
  (`71b3b5db…`, unchanged). **The one-shot first-stop observation has been
  spent** — G1b took it, and it is the finding that QEMU does not unlink its
  `netvm` sockets at exit. **Every MainPID recorded before 943031 is dead**,
  including all four of 2026-09-05 — the pool was stopped and started four
  times that day, the last of them 3952302, and the 2026-09-07 consolidation
  superseded every one of them. **943031 itself is now dead too**, superseded
  by 3628111 at the 2026-09-12 09:59:37 CEST restart recorded above. Eleven
  empty slot directories `10`…`1a` that
  G1b left under `/run/katmate/link/netvm/` were removed by the operator after
  it closed; `/run/katmate-dev/g1bprobe/` went with the reboot of 2026-09-05
  20:10:29, which took the whole of `/run/katmate-dev/`. **The slot tree is no
  longer hand-made**: since 2026-09-07 `/run/katmate/link/netvm/00`…`0f` are
  created by the unit's own `RuntimeDirectory=`, `0755 root:root`, under two
  parent levels systemd makes itself. See the 2026-09-07 session entry and the
  two 2026-09-05 entries — the *first of two* of which moved to
  `docs/SESSIONS.md` in this commit.

  **Slot bindings, as left at the close of the 2026-09-12 gate arc, because
  the next measuring session inherits them.** Slot **00** — `appvm` inode
  **7528**, held by `g5br-restartpeer.service` (MainPID **3627150**), started
  09:58:06 CEST and **alive across the 09:59:37 CEST restart** — the only
  restart-survived AppVM binding in the tree — with link **200** installed
  (`g5b-restart-report.md`, `g2-add-report.md`). Slot **01** — `appvm` inode
  **7855**, `g2fix-01.service` (**3689344**), **left RELEASED**; re-install
  with `ping-client netcfg-add 3 201 52:54:01:00:00:01 10.100.1.17 100`
  (`g3-g4-console-report.md`). Slot **02** — `appvm` inode **7857**,
  `g2fix-02.service` (**3689348**), link **202** installed, untouched control
  (same source). **The dev console is at a live root shell**; the next
  session needs no login step (`g3-g4-console-report.md`).

  **Instruments left on MINIS from that arc, so they are not rewritten:**
  `/tmp/g2fix.py` (ARP request), `/tmp/g2icmp.py` (IPv4 ICMP echo),
  `/tmp/g34arp.py` (ARP reply — gratuitous and solicited), `/tmp/g34resp.py`
  (solicited ARP responder), `/tmp/g34-conrun.sh` (console runner). Client:
  `/home/host/katmate-build/agent/target/release/ping-client`, vsock CID 3
  port 1025, ops `netcfg-add <cid> <link_id> <mac> <peer> <metric>` and
  `netcfg-remove <cid> <link_id>`; `local_addr=10.100.1.1`, prefix 32 compiled
  in. **Addressing convention as measured:** slot `k` carries MAC
  `52:54:01:00:00:kk`, peer `10.100.1.(16+k)`, gateway `10.100.1.1/32` on
  every active slot.
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

   **Scope narrowed 2026-09-03 (`23e4268`), and the residue named.** The
   credential itself is **out of the repository**: step 6 no longer carries a
   literal hash and no longer unlocks unconditionally. Root is locked by
   default and unlocks only when a build is handed `KATMATE_DEV_ROOT_HASH` from
   outside, and the image records which it is
   (`NETVM_ROOT_UNLOCKED=yes|no` in the host-side `netvm.meta`). **What remains
   open is exactly this problem's own subject:** the image on MINIS today was
   built with the variable set, so root **is** unlocked in it and it is still
   not release-clean. The release-side work is now a *build without the
   variable*, not an edit to a tracked file. The sshd half of this entry's
   "(sshd class)" framing was never true of the declarative image — `manifests/
   netvm.list` installs no `openssh-server`; that half belongs to #4, on the
   host.

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

   **DISCHARGED 2026-09-03 in the form stated, and the entry says which half.**
   The line's *existence* was the debt, and the line is gone (`23e4268`): step 6
   locks, and an unlock happens only when the build is handed a hash it
   validates. **The practical note above is retired** — *"the baked hash matches
   no password, so a rebuild still needs `mount` + `chroot chpasswd`"* described
   a hash that no longer exists, and the measurement that retired it is in the
   2026-09-03 session entry (three candidates, `openssl passwd -6 -salt
   katmate`, none matched; the field was well-formed, 86-character body).
   **What is NOT discharged is the closing paragraph's real point:** the fix
   *"is not a valid hash but a structured in-guest observation path in
   `netvm-agent` — a RUN opcode or an equivalent"*. There is still **no RUN
   opcode**. What 2026-09-03 added is a *console* — a dev drop-in putting a FIFO
   on the VM's stdin — which is scaffolding on the removal list, not the
   structured path this entry asks for. In-guest observation now costs a
   console instead of costing nothing; it no longer costs a drift.

13. **The comment at `netvm.sh` line 228 is wrong.** (Cited as line 210 until
   2026-08-09 and as line 224 until 2026-09-02; the file has moved under it
   twice, and the citation has now been corrected twice. Only the line number
   changes here; the finding is unaltered.) It claims the manifest lacks
   `chpasswd(8)`. Both `chpasswd` and `usermod` ARE in the image (under
   `/usr/sbin`, confirmed by mount on 07-23). The actual cause of the original
   failure is that `chroot_run`'s PATH does not carry `/usr/sbin` — hence the
   absolute path. Cosmetic.

   **RETIRED 2026-09-03 — not closed, and the distinction is the operator's
   ruling.** This entry is retired because **its subject no longer exists**, not
   because anything was fixed: `23e4268` rewrote step 6's comment block for an
   unrelated reason and the false `chpasswd(8)` sentence went with it. Nothing
   was investigated and no defect was repaired.

   **Its substance was carried forward deliberately, because it is still
   load-bearing.** The new block still calls `/usr/sbin/usermod` by absolute
   path, and still for this reason: `chroot_run` (`build/lib.sh:97–100`) sets no
   `PATH` of its own — it runs `chroot <mnt> /usr/bin/env
   DEBIAN_FRONTEND=noninteractive "$@"` — so the chroot inherits the build
   host's `PATH`, which does not carry `/usr/sbin` where the Debian image keeps
   `usermod` (measured 2026-07-23). The comment now names the failure mode too:
   a bare `usermod` fails *command not found* and the account **silently stays
   locked**. Had the fact not been carried, it would have vanished with the
   comment that held it.

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

22. **Kernel provenance is unverifiable — no image can be tied to a config.**
   Added 2026-08-24, from link-m1 § 3c–§ 3d and link-m2 § B0.1, § B0.4.
   `~/katmate-kernels/` holds **different bytes under one filename on the two
   machines**:

   | | sha256 | size | banner |
   |---|---|---|---|
   | Acer | `a7581389…` | 14115840 | `6.12.87 (winterbox@cyberdome) … Wed May 13 20:33:23 CEST 2026` |
   | MINIS | `b34026dd…` | 14156800 | `6.12.87-dirty (host@archlinux) … Wed Jul 1 08:10:48 CEST 2026` |

   The two stored `.config` files differ too, in toolchain-detection symbols and
   `SECURITY_PATH`; **none of the differing symbols is a networking symbol**, so
   the `CONFIG_VIRTIO_NET=y` answer is the same whichever copy is read. That is
   the only thing the difference does *not* affect.

   **`CONFIG_IKCONFIG` is unset in both configs** (Acer line 165, MINIS line
   166) and `scripts/extract-ikconfig` against the MINIS image returns rc=1,
   `Cannot find kernel config.`, zero bytes out. So neither image carries an
   embedded config and **no image can be checked against any config** — only
   dated. The MINIS config was written four minutes after the MINIS image's
   build banner; the Acer config postdates the Acer image's banner by six weeks.
   That is consistency, not proof, and neither report claims the pairing.

   **The kernel AppVMs boot on MINIS is the `-dirty` build.** `app_web.con:29`
   sets `KERNEL /home/host/katmate-kernels/vmlinuz-katmate-microvm-amd64-6.12.87`
   and `-dirty` is what `CONFIG_LOCALVERSION_AUTO=y` produces from an unclean
   source tree — so the image every AppVM runs **corresponds to no commit**, and
   the filename says `6.12.87` as though it did.

   **The proposed fix, named and not taken:** sha256 of the image *and* of the
   config recorded in T2 meta, verified by `katmate-check-image`, which already
   reads `<image>.meta` and already runs as uid 1000 on plain files (ADR-032's
   2026-08-11 revision note). **Not `CONFIG_IKCONFIG`** — setting it would make
   the config readable from inside the guest, which buys provenance on the host
   by widening what a compromised guest can read.

   **Release-blocker candidate**, beside the dev sshd (#4) and the installer
   secrets (#3). What makes it one is not the `-dirty` suffix: it is that a
   filename asserts an identity that does not hold, which is this project's
   recurring failure class rather than a new one. Others on the record: the
   stale BDF (*Invariants*); the documented `~/katmate-build/katmate-os/` path
   that never existed and misled a delegated session (*Invariants*, corrected
   2026-08-09); and the runtime projection that describes the last start and was
   read as describing a running VM (ADR-032, 2026-08-22 revision note). No count
   is given here, because the count is not measurable and the pattern is.

   **Revision note 2026-08-28 — the entry is too broad: one image is tied to a
   config, one is not.** From two read-only investigations of 2026-08-28, one on
   the MINIS kernel tree and one on the Acer's. **Neither produced a report
   file; both reported in chat**, so there is no 2026-08-28 session entry to
   look for. Every MINIS figure below is therefore chat-only and marked as such;
   every Acer figure was re-derived from the tree in the same pass that wrote
   this note.

   **MINIS: the chain exists.** *(Chat-only — measured on MINIS 2026-08-28, not
   re-derivable on the Acer.)* At `/home/host/src/kernel/linux-6.12.y`,
   `arch/x86/boot/bzImage` is byte-identical to the archived vmlinuz
   (`b34026dd…`), and `include/config/auto.conf` — what Kbuild wrote at the
   start of that build — is symbol-for-symbol identical to the archived
   `config-katmate-microvm-amd64-6.12.87` once shell quoting is normalised:
   1718 lines against 1718, zero differing. That image *is* tied to that config,
   through the build tree.

   **Acer: the chain is broken.** *(Re-derived on the Acer 2026-08-28.)* The
   tree at `~/src/kernel/linux-6.12.y` is clean at HEAD `8bf2f55ef`, tag
   `v6.12.87`, and its `arch/x86/boot/bzImage` is byte-identical to the archived
   vmlinuz (`a7581389…`) — and is the only `bzImage` under `$HOME`. But
   `include/config/auto.conf` was overwritten 2026-06-30, **47 days** after the
   image was linked (banner `Wed May 13 20:33:23 CEST 2026`), and now differs
   from the archived config by six lines. `.config.old` is byte-identical to the
   archived config (`4e30950b…`) — but both are June-30 artefacts, and they
   establish the tree's *pre-reconfigure* state, **not** its state at build
   time.

   **Which half of this entry's own sentence that changes.** *"That is
   consistency, not proof"* closes a compound sentence covering both machines.
   Its **MINIS half is superseded** — that config is tied to that build by
   `auto.conf`, not merely written four minutes after it. Its **Acer half
   stands, confirmed**: the 2026-08-28 read went looking for something that
   would upgrade it to proof and found nothing.

   **So what is wrong here is the scope, not the content.** It is not that no
   image can be tied to a config. One can and one cannot, for a reason that is
   neither about the image nor about the config: **the evidence of provenance
   lives in the build tree, and the next reconfigure deletes it silently.** It
   survived on MINIS by accident; it did not survive on the Acer. Nothing in the
   distributed artefact carries it — `CONFIG_IKCONFIG` is unset, Acer line 165
   as recorded above — so the tree is the only witness, and it is a witness that
   any `make menuconfig` overwrites.

   **The consequence, named and not decided:** a fingerprint taken where the
   kernel enters the pipeline would capture the chain while the witness still
   exists. In the tree that boundary is `Makefile:44–47` — target
   `$(KERNEL_VMLINUZ)`, copying from `$KERNEL_SRC_DIR` into `$(OUT)` — and
   `build/foundation.sh:268–274`, step 11, installing into
   `$KATMATE_KERNELS_DIR`. Where such a hash would live, and what would refuse
   what on a mismatch, is not decided here. **#22 stays open.**

   **Revision note 2026-08-28 — what the `-dirty` suffix on MINIS actually is:
   ten deleted files, and no patch.** From the same two read-only
   investigations of 2026-08-28; **neither produced a report file, both reported
   in chat.** The working hypothesis this tested — that the MINIS kernel carried
   a patch existing nowhere but that directory — did not hold. Every MINIS
   figure here is chat-only; the Acer figures were re-derived from the tree.

   **`-dirty` comes from ten deleted tracked files and nothing else.**
   *(Chat-only — MINIS, 2026-08-28.)* Measured by counting rather than by
   reading the diff: 431 diff lines, **371 deletions, zero added and zero
   modified lines**, ten `deleted file mode` hunks, zero `new file mode`, zero
   mode changes. No surviving file is modified. Nothing is staged, and
   `git status --porcelain -uall` reports no untracked file.

   **No patch exists anywhere beside it.** *(Chat-only — MINIS, 2026-08-28.)* No
   `*.patch` or `*.diff` under the tree or in its parent, no `patches/`
   directory, no quilt `series`, empty stash, one local branch tracking
   `origin/linux-6.12.y` at the same commit, HEAD at annotated tag `v6.12.87`,
   remote is upstream stable
   (`git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git`).

   **The ten are `mips`, `nios2`, `openrisc`, `parisc`, `sh`, a perf bpf
   skeleton and one bpf selftest. None of them compiles into an x86 kernel.** So
   the suffix is accurate about the tree and says nothing about the code that
   was built.

   **All ten are present on the Acer, and that is the whole difference between
   the machines.** *(Re-derived on the Acer 2026-08-28: each of the ten checked
   individually and found present, and the class enumerated — **53 of 53**
   tracked `*vmlinux*` paths present, zero missing.)* On MINIS the same
   enumeration gave 43 present and 10 missing.

   **The shape of the deleted set, with no cause assigned.** The ten basenames
   are `vmlinux.its.S`, `vmlinux.scr`, `vmlinux.h`, `vmlinux.c` and the contents
   of a directory *named* `vmlinux/`. Of the 53 tracked `*vmlinux*` paths,
   **36 contain `lds`** and all 36 survive on MINIS; the survivor total there is
   **43**, which is those 36 plus 7 non-`lds` paths (`scripts/extract-vmlinux`,
   `scripts/link-vmlinux.sh`, `scripts/Makefile.vmlinux`, and so on). Those are
   two counts and not one. `.gitignore` does not account for the set: five of
   the ten match no rule, and two of the apparent matches are **negation**
   rules, which mean the opposite of a match *(chat-only — MINIS)*. The
   `--exclude='vmlinux.*'` gotcha in `CLAUDE.md` predicts a wider casualty list
   than this one — every `vmlinux.lds.S` would be gone, and none is. That is an
   observation about this tree, not a correction to the gotcha.

   **What was built is not lost.** *(Chat-only — MINIS, 2026-08-28.)* The MINIS
   tree still holds the byte-identical `bzImage`, and `vmlinux`, `System.map`
   and `Module.symvers` from the same link. The earlier formulation in this
   entry — that the image *"corresponds to no commit"* — is right about the
   commit and wrong if read as saying the build is unrecoverable.

   **The reading discipline this produced.** A `-dirty` banner carries **one
   bit**: the tree was unclean, with no manifest of what the dirt was. So the
   ten deletions visible today cannot be shown to be the build-time state — they
   are consistent with it, and that is all. A bare `6.12.87` carries **two
   facts**, because `scripts/setlocalversion` emits no suffix only when HEAD is
   at an annotated tag *and* the tree is clean *(re-derived on the Acer: the
   `scm_version()` comment, "If we are at the tagged commit, we ignore it
   because the version is well-defined")*. **Neither form carries a commit
   SHA.**

   **Revision note 2026-08-28 — two smaller divergences from the same two
   reads,** neither of which produced a report file; both reported in chat.

   - **`Module.symvers` is present in the MINIS kernel tree and absent from the
     Acer's.** *(MINIS: chat-only, 2026-08-28. Acer: re-derived the same day.)*
     Recorded because it is an asymmetry between two trees at the same commit;
     **no cause is assigned.**
   - **Neither read re-tested `scripts/extract-ikconfig` against either image.**
     This entry's finding that no image carries an embedded config — rc=1,
     `Cannot find kernel config.`, zero bytes out — therefore **stands untested
     by the 2026-08-28 reads** and is not re-asserted by them. What they did
     re-derive is that `CONFIG_IKCONFIG` is unset in the Acer archived config,
     line 165, exactly as recorded above.

   **Note 2026-08-28 — the first provenance capture: a sidecar exists on MINIS,
   written before the ADR that defines it.** From the capture session of
   2026-08-28 on MINIS; like the two reads above it **produced no report file
   and reported in chat**, so every figure here is chat-only unless marked
   otherwise. Recorded because the file is now a fact about that machine and
   nothing else in the tree says so.

   **What was written** *(chat-only — MINIS, 2026-08-28)*:
   `~/katmate-kernels/vmlinuz-katmate-microvm-amd64-6.12.87.provenance`, beside
   the image it describes. 851 bytes, 10 keys, mode `0644`, owner `host:host`,
   sha256 `bfed14af7ae10df630fec00865203f725e654607ae6ff7fd3ee2b9a9e014def3`.
   It records `KERNEL_SHA256=b34026dd…`, `CONFIG_SHA256=7720cf22…`,
   `AUTOCONF_MATCH=yes`, `SRC_COMMIT=8bf2f55e…`, `SRC_TAG=v6.12.87`, the banner
   read out of the image, and `CAPTURED_BY=manual capture, tools/ implementation
   pending`. Written the way the pipeline writes payload files — dotted
   `mktemp` in the target directory, `chmod 0644`, `mv -f` — as
   `build/foundation.sh` step 11 and `netvm.sh` step 11 do *(re-derived: those
   two are `build/foundation.sh:268–274` and `build/netvm.sh:345–347`)*.

   **`AUTOCONF_MATCH=yes` was measured in that session, not carried forward.**
   `include/config/auto.conf` against the archived config, quoting normalised:
   **1718 symbol lines against 1718, empty diff**, run twice — once in the
   measurement pass and once again at write time. The earlier reading of
   2026-08-28 was deliberately not reused, so the field stands on its own.

   **The byte-identity gate was re-confirmed three times**, the last immediately
   before the `mv`, so **the file cannot outlive the identity it asserts**. Had
   the tree changed between the measurement and the write, the capture would
   have halted rather than recorded a stale pairing.

   **`SRC_DIRTY_PATHS` carries the ten deleted paths** — the manifest
   `scripts/setlocalversion`'s single bit does not provide, and the field this
   whole question turned on.

   **It was written before ADR-034 was accepted, and that is the reasoning, not
   an oversight.** The witness is `include/config/auto.conf` in that tree, and
   the next `make menuconfig` or `make clean` there destroys it. Waiting for
   acceptance would have meant accepting an ADR about a pairing that no longer
   existed. The ADR records the same asymmetry as a decision; this note records
   that the capture preceded it.

   **The Acer is deliberately without one.** *(Re-derived on the Acer.)* Its
   `auto.conf` was overwritten 47 days after that image was linked, so a sidecar
   there could only fill `SRC_COMMIT` and `SRC_TAG` from today's tree and
   present them in the same fields that are true on MINIS — a record that reads
   as equivalent while being something else. An absent record is the honest one.
   ADR-034 records the decision; this note is the instance.

   **Revision note 2026-08-28 — for the MINIS kernel the chain now exists
   outside the build tree. #22 is not closed.** From the capture session of the
   same date, recorded in the note above; no report file, chat-only.

   **What has changed** is only the perishability. The 2026-08-28 note above
   identified the real problem as the witness living in the build tree, where
   any `make menuconfig` overwrites it. For **this one image on MINIS** that is
   no longer in force: `AUTOCONF_MATCH=yes`, the two `sha256` values and the ten
   `SRC_DIRTY_PATHS` now exist in a file beside the kernel, and destroying
   `include/config/auto.conf` no longer destroys the record of what it said.

   **What has not changed** is this entry's substance. The image still carries
   no embedded config; `CONFIG_IKCONFIG` is still unset; `extract-ikconfig`
   remains **untested by any of these three sessions**, exactly as the note
   above records. The sidecar is unsigned, sits beside the file it describes,
   and defends against drift and forgetting rather than against anyone who can
   write to that directory. It is a record, not integrity.

   **The Acer's half of #22 stands unchanged, and deliberately so.** No witness
   survives there, no sidecar was written, and none will be. ADR-034 is the
   mechanism; the note above is the instance. **#22 stays open** — it will close
   when the pipeline carries and checks the sidecar, which is ADR-034's
   acceptance and not this pass.

   **Note 2026-08-28 — two items ADR-034 hands forward to its acceptance,**
   recorded here so they are not lost between the draft and the pipeline work.

   - **The sidecar is not sourceable, by decision, and no consumer exists yet.**
     `BANNER` carries spaces and unescaped parentheses, so `. file` fails on it;
     ADR-034 keeps `foundation.meta`'s shape and gives up its POSIX-sourceable
     property rather than inventing a quoting convention that file does not use.
     Any reader parses `^KEY=` and takes the rest of the line verbatim. Whether
     that is `sed`, as `build/app-layer.sh:101`'s `meta_get()` does, or something
     else, is settled by the first implementation to read it — *(re-derived:
     `meta_get()` is at `build/app-layer.sh:101`, with its stated reason at
     lines 99–100)*.
   - **The `tools/` capture script does not exist.** The MINIS sidecar carries
     `CAPTURED_BY=manual capture, tools/ implementation pending` *(chat-only)*,
     and whether the tool re-takes that capture once it lands, or leaves it
     standing as the record it already is, is open in ADR-034's own list.

   **Note 2026-09-01 — the tool exists, is committed, and is gated; #22 does not
   close.** ADR-034 is Accepted (2026-09-01) and
   `tools/capture-kernel-provenance` is committed, sha256
   `5b1f16c3823cf72defc1cca37d014d700a2681e04a3fc350dd4266a0e4c1df22`. Four
   sessions of 2026-09-01 gated it, reports at `~/adr034-pregate-report.md`,
   `~/adr034-tool-gate-report.md`, `~/adr034-gate2-report.md` and
   `~/adr034-g8-report.md`.

   **What the gate established** *(all on MINIS unless noted)*: the tool's output
   against the hand-captured sidecar — 10 keys standing against 12 produced,
   **8 pairing identically**, `CAPTURED` and `CAPTURED_BY` differing by
   construction, 2 new; `BANNER` byte for byte with `cmp` exit 0, 84 bytes each
   side; a config differing in exactly one symbol of 1718 producing
   `AUTOCONF_MATCH=no` with exactly two fields moving; and the symbol-set claim
   measured in both directions (1718/1718 → `yes`, 1717/1718 → `no`,
   1718/1717 → `no`) against a control built from the same bytes as the real
   pair. `SRC_DIRTY_STAT`'s first value is `10 files changed, 371 deletions(-)`.

   **#22 is not closed by this.** The tool removes the *cause* going forward — a
   kernel built from now on can carry a record of its pairing. It does nothing
   for the two images that already exist: the Acer's pairing is unrecoverable,
   and the sidecar does not yet travel with the kernel through the build hops, so
   nothing downstream reads one. #22 closes when the pipeline carries and checks
   it, which is the next commit and not this one.

   **Note 2026-09-01 — a second kernel image on MINIS that nothing describes.**
   *(Found by enumeration during the pre-gate read, `~/adr034-pregate-report.md`
   § 3.2 and § 6.5.)* Beside the 6.12.87 tree there is a second source directory
   at a different version carrying its own built `arch/x86/boot/bzImage`
   (14238720 bytes, dated 2026-07-06) and **no `.git` directory**. It fails two
   of the three criteria the pre-gate used to identify the build tree, so it
   created no ambiguity about which tree was read. No sidecar describes it, and
   no artefact in the repository refers to it. **No cause is assigned** — this
   entry records that the file exists and that nothing accounts for it.

   **Note 2026-09-01 — the spare config and the archived config are different
   objects, and differ in exactly one symbol.** *(Measured in the pre-gate read
   § 5 and re-derived on MINIS during the gate.)* A `.bak` config written ten
   minutes before the archived one differs from it by two bytes, in one line:
   `CONFIG_PAHOLE_VERSION=131` against `CONFIG_PAHOLE_VERSION=0`. Same line
   count, different sha256 — `499a53a2…` against `7720cf22…`. The archived one is
   what `CONFIG_SHA256` names, so the two are not two copies of one object and a
   future capture must hash the archived file and not the spare.

   It also means **a kernel config is not reproducible independently of the
   environment that generated it**: that symbol records whether a tool was
   detected at configure time, so the same source and the same answers yield
   different configs on machines that differ in what is installed. Recorded as a
   fact. **No cause is assigned** to why the two files differ in that symbol.

   **Note 2026-09-01 — all ten dirty paths in the kernel tree are `vmlinux*`
   files.** The ten paths `SRC_DIRTY_PATHS` records are deletions, and every one
   of them has `vmlinux` in its basename or in a parent directory name — across
   `mips`, `nios2`, `openrisc`, `parisc`, `sh`, a perf bpf skeleton and one bpf
   selftest. The pattern is uniform.

   **This is consistent with the `--exclude='vmlinux.*'` incident recorded under
   *Invariants & gotchas*, and is not offered as a finding.** **No cause is
   assigned, and none can be:** no command and no date exist for it. The earlier
   2026-08-28 revision note above already records the arithmetic that cuts
   against the simple reading — 36 of the 53 tracked `*vmlinux*` paths contain
   `lds` and all 36 survive — so the observation here is the uniformity of the
   pattern and nothing more. It is written down because a uniform pattern with no
   recorded cause is the kind of thing a later session will otherwise rediscover
   and over-read.

   **Note 2026-09-01 (second of two) — the sidecar now travels on the build
   path, and #22 still does not close.** `kernel_provenance_check()` is in
   `build/lib.sh` and runs in `foundation.sh`'s preflight; `KERNEL_PROVENANCE`
   is written into `foundation.meta` at step 10; the sidecar is installed beside
   the kernel at step 11 and copied into `out/` by the `Makefile`. Gated by
   sourcing the real function — eight arms, fixture produced by the committed
   tool — and by running the kernel-copy target twice. **Step 10's field and
   step 11's install are UNVERIFIED**: only a real `make foundation` exercises
   them, and this session was forbidden from running one.

   **What still does not close #22.** The record now survives the hops for a
   kernel captured from here on. It does nothing for the two images that already
   exist, nothing reads a sidecar at install or launch, and the orchestrator's
   presence check (ADR-034 § A.3) is **blocked by #25**. #22 closes when the
   pipeline both carries and checks the record.

23. **A link's socket outlives its process, including on a failed start.**
   Added 2026-08-24, from link-m1 § 13.1, § 20.1 and § 23, and link-m2 § A.3.
   QEMU creates its `local.path` at start and **does not unlink it at exit** —
   not on a clean `SIGTERM`, and not when the process dies before it is ever
   usable. The startup trace carries the `unlink()` before `bind()` and **no
   `unlink` at exit at all**, which is the mechanism behind the observation.

   **The sharp case is the failed start.** Three `N`=32 runs left **96 socket
   files** — 3 × 32, every path each run bound. Those processes executed: the
   netdev backends were created and all 32 sockets bound, and the failure came
   later, at **device realisation** (`PCI: no slot/function available`, naming
   `netdev=n30`). So a socket file on disk is not even evidence that the VM it
   belongs to reached a usable state, let alone that it is running.

   **Consequence for the launch daemon: `ExecStopPost=` must unlink the slot's
   socket**, and **presence of the file is not authority for liveness** —
   systemd's unit state is. This is the **second instance of that rule**, and it
   is the same rule: ADR-032's 2026-08-22 revision note establishes it for the
   runtime projection under `/run/katmate/`, which survives both a clean stop and
   a failed start. The difference worth keeping: the projection is deliberately
   **not** removed at stop, because a failed start's projection is the evidence
   worth inspecting. A stale socket path is not evidence of anything — it is
   rebound under a new inode by the next process to want it (#22's sibling
   finding, link-m1 § 19) — so here the cleanup is wanted and there it is not.

24. **AppVM guests emit IPv6 router solicitations unprompted.** Added
   2026-08-24, from link-m2 § B2.4. Two 70-byte frames to `33:33:00:00:00:02`
   (IPv6 all-routers multicast), ICMPv6 type `0x85`, at t+5.661 s and t+23.070 s
   of a 30 s window, from the guest's link-local address. **Nothing configured
   them.** The guest was a single static `/init` that sets one IPv4 address by
   ioctl and sends UDP; it has no shell, no network manager and no `accept_ra`
   handling of its own. The kernel sent them because `CONFIG_IPV6=y` and nothing
   said not to.

   **The risk is not the solicitation, it is an answer.** If netVM ever replies
   with an RA on an internal link, the AppVM acquires addressing by **SLAAC,
   outside NETCFG** — a second source of one truth, which is the failure class
   this project spends most of its discipline on. NETCFG describes a link and is
   the only thing that should (ADR-023, ADR-025).

   **Proposed and not taken:** `accept_ra=0` in AppVM images, and no RA from
   netVM on internal links. Both are one-line changes in places this session did
   not touch — the AppVM image manifest and the netVM manifest — and either alone
   would close it, which is a reason to take both rather than to choose. Nothing
   has measured what netVM currently does when an RS arrives on an internal link;
   **no AppVM has ever had a network device**, so the case has never occurred.

25. **`KERNEL_SRC_DIR` derives from `$HOME`, and both scripts that read it
   require root — so as root it resolves to a directory that does not exist.**
   Added 2026-09-01 (second of two), measured on MINIS while establishing
   whether a proposed check could fire.

   `build/config.sh:33` reads
   `KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-$HOME/katmate-kernels}"`. The measurement,
   verbatim, both uids, against the synced copy on MINIS:

   ```
   line 33: KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-$HOME/katmate-kernels}"

   as uid 1000 (host):   $HOME=/home/host
     ( cd build; source config.sh; echo "$KERNEL_SRC_DIR" )
     /home/host/katmate-kernels

   as root, which is how both scripts actually run:
     sudo -n bash -c 'cd build; source config.sh; echo "$KERNEL_SRC_DIR"'
     /root/katmate-kernels
     [exit=0]

     sudo -n bash -c 'echo "$HOME"'
     /root

   resolved: /root/katmate-kernels
   directory DOES NOT EXIST

   what katmate-update.sh:114 tests as root:
   result: FALSE — the existing check would die as root
   ```

   **The blast radius, from every use in the tree.** `Makefile:23,45,47` is
   **unaffected** — it carries its own hardcoded `/home/host/katmate-kernels`.
   `build/foundation.sh:52,53,132` uses the variable only in diagnostic text and
   a comment, so it prints a wrong path in an error message and nothing more.
   `build/katmate-update.sh:114` is a hard `die` and **fires as root**, with
   `115` naming the wrong cause: *"missing kernel vmlinuz for 6.12.87 in
   /root/katmate-kernels"*, when the kernel is present and the path is not.
   `121` logs the same wrong path.

   **The Makefile's hardcoding is a workaround whose motivating condition is
   still live.** *Invariants & gotchas* already records why it exists — `$(HOME)`
   under `sudo` is `/root`. What is new is that the condition has been displaced
   into `config.sh`, where a **second** consumer now depends on it and breaks:
   the Makefile carries its own value and survives, `katmate-update.sh` reads
   `config.sh` and does not.

   **It fails safe.** Line 114 sits before every `run`-wrapped mutation, so a
   real release dies before touching anything. The fault is the misleading
   message and the blocked check, not a destructive action.

   **ADR-034 § A.3's presence check is blocked on this**, and `ROADMAP.md`
   carries the pointer in both directions. **No cause is assigned**, and nothing
   was fixed here: a fix touches the existing check at `114`, which is a separate
   concern from the commit that found it.

26. **An instance delta on MINIS that `katmate-update.sh` refuses.** Added
   2026-09-01 (second of two). Observed while running `--dry-run` as uid 1000
   for an unrelated gate; **unrelated to the provenance work, and its only claim
   is that it exists.**

   ```
   [katmate-update] found 2 instance delta(s):
              /var/lib/katmate/instances/scratch.qcow2
              /var/lib/katmate/instances/test_web.qcow2
   [katmate-update] all deltas free (no qemu holds them)
   [katmate-update] FATAL: delta '/var/lib/katmate/instances/scratch.qcow2' maps
                    to unknown app type 'scratch' — expected one of: web vault
   ```

   The script derives an app type from the delta's filename suffix and refuses
   one it does not recognise. `scratch.qcow2` yields `scratch`, which is not in
   `APP_TYPES`. **`katmate-update.sh --dry-run` therefore cannot currently
   complete on that machine, even as uid 1000** — a second blocker in the same
   script as #25 and independent of it.

   **No cause is assigned.** Nothing in the repository records where
   `scratch.qcow2` came from or what it is for, and this session did not
   investigate, delete or rename it. Whether the delta should go or the script
   should tolerate an unknown type is not decided here.

27. **The `netvm-agent` unit baked into the netVM image still names the Path A
   mechanism ADR-025 rejected.** Added 2026-09-02, from the ADR-035 read pass
   (`~/adr035-readpass-report.md` § 8 D3). **Read from the tree only** — nothing
   was run, no image was mounted, and this says nothing about the installed
   image on MINIS.

   `build/netvm.sh` writes the unit into the guest at step 7 (heredoc, lines
   242–263). Two of its lines describe a mechanism that was measured dead the
   day after they were written:

   ```
   252	# CAP_NET_ADMIN: /etc/systemd/network/ writes + networkctl reload + nft (NETCFG).
   258	ReadWritePaths=/etc/systemd/network /run
   ```

   ADR-025 § *Mechanism resolved (2026-07-21): Path B* records that no
   dbus-less `networkctl reload` trigger exists — the classical bus call inert
   (E1), the varlink surface carrying no config-mutation method (E2), and
   `SIGRTMIN+1` terminating networkd rather than reloading it (E3) — and that
   the agent programs `AF_NETLINK` directly, so *"the E4 `tmpfiles.d` DAC line
   is not needed"*.

   **The agent carries no code that writes there.**
   `git grep -F 'systemd/network' -- agent/` returns nothing, and `netlink.rs`'s
   own header states the design: the MAC→ifindex step is read-only sysfs and
   the rest is rtnetlink, with no dump parsing and no state.

   **What this is, stated narrowly.** The comment at 252 is a wrong statement of
   *why* `CAP_NET_ADMIN` is held; `ReadWritePaths=` at 258 grants write access
   to a directory nothing writes to. Neither is a defect in behaviour — the
   agent works by the path ADR-025 chose — and neither has been observed on a
   running system by this record.

   **Ruled 2026-09-02: the fix lands in the netVM slot-pool commit, where the
   unit is rewritten anyway — not before.** That is § *Next steps* step 1. A
   passing edit would buy an image rebuild for a comment.

   *One thing a later session should not have to rediscover:* this is the
   **guest-side** unit, baked into the image by `netvm.sh`, so changing it costs
   a `netvm.sh` run. It is **not**
   `host/usr/lib/systemd/system/katmate-sys-driver@.service`, the host-side unit
   that § *Next steps* step 1 also names. Two units, one step.

28. **No bound on an instance name's length, in the generator or in the
   validator.** Added 2026-09-02, from the ADR-035 write pass
   (`~/adr035-write-report.md` § 1.3). **Read from the tree only** — nothing was
   run, and no socket was created.

   `km_check_instance` is the only check `katmate-generate-env` applies to the
   name it is handed (`katmate-generate-env:48`), and it is a character class:

   ```
   host/usr/lib/katmate/katmate-lib.sh:67
       [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] \
   ```

   `[a-z0-9_]*` is unbounded. **`tools/validate-properties.fish` does not
   examine the instance name at all** — it validates file *contents*, and the
   instance name is the `.toml` filename stem, which it never reads as a name.
   `grep -F 'string length'` over `tools/` and `host/` returns nothing, and every
   `${#…}` in `host/` is an array element count, not a string length.

   **Why this is a problem only now.** Until ADR-035 the instance name reached a
   filename under `/etc/katmate/vm/`, an LV name and a projection key — all
   places where a long name is ugly and nothing more. Under
   [ADR-035](docs/DECISIONS.md#adr-035) §5 it reaches an **`AF_UNIX` socket
   path**, `/run/katmate/link/<netvm>/<kk>/netvm`, and `sun_path` is 108 bytes.
   The layout's fixed part is **27** (`/run/katmate/link/` = 18, `/kk/netvm` =
   9), so the bound the layout leaves for the netVM instance name is **80**
   characters under the NUL-terminated reading of `sun_path`, 81 without. A
   longer name fails at `bind()` — at netVM's start, and ADR-033 measured that a
   `dgram` device's startup is silent, so nothing tells the guest.

   **ADR-035 §5 states the headroom as *"roughly seventy"*.** The measured figure
   is 80. **The discrepancy is recorded and not resolved:** the write pass did
   not edit the draft to fit a measurement, and whether the sentence is amended
   or the finding stands beside it is the operator's ruling.

   **Not fixed, and deliberately.** No bound was added anywhere. Where one
   belongs — `km_check_instance`, the validator, or both — is a decision, and a
   bound invented in passing by the session that found the gap is the kind of
   silently-widened rule this project does not take. What this entry records is
   that neither place has one today.

29. ~~**The netVM dev root password is in three places on MINIS, and the console
   procedure has no guard that would have prevented it.**~~ —
   **Closed 2026-09-05 by rotation, and the guard is measured in both
   directions.** The value was retired by the `build/netvm.sh` run of
   2026-09-05 20:40:32Z with a fresh `KATMATE_DEV_ROOT_HASH`, and **proved by a
   login** — step 6b proves a hash reached `/etc/shadow`, only `login(1)`
   accepting the plaintext proves it opens. **Nothing was vacuumed**, per the
   ruling below: the value is retired by the rebuild, not by deletion, and every
   location it was burned into keeps a dead credential. **Both halves of the
   guard are measured**, on the same evening: it proceeded on a login prompt and
   **refused on a shell** — `REFUSING: console is not at a login prompt`, sending
   nothing — which is the case that leaked the value twice and the direction that
   had never been exercised. **And the guard now lives inside the login call**,
   not beside it: a guard placed as a separate step is skippable, which is what
   both leaks were. Source: `~/Claude.assistent/netvm-rebuild-3-report.md`
   §§ 26.1, 26.2. The text below is left as written, as the record of what the
   problem was. Kept as a closed marker so the number is not reused.

   On 2026-09-04 the operator's two-write console login landed on a console
   that was **already at a shell prompt**, not a login prompt. `login(1)` never
   saw either field; `bash` did, and echoed both into the host journal as
   `command not found`. The value is additionally in the operator's fish
   history on MINIS (the `printf … | sudo tee` form puts it there) and in that
   terminal's scrollback (`tee` writes it back to the screen). Extent: three
   locations, of which the delegated session observed one.

   **Ruled: the credential is burned, not scrubbed.** No journal is vacuumed —
   `--vacuum` is time-granular and would take this gate's own transcript, which
   is the only record of the measurement. The value is retired instead, and
   rotated at the next `build/netvm.sh` run with a fresh
   `KATMATE_DEV_ROOT_HASH`. That run stops the pool, so it follows G1b.

   **The mechanism, which is what makes this a problem and not an incident.**
   The measured procedure — two writes at least 3 s apart, both inside
   `agetty`'s 60 s window — is correct for a console **at a login prompt** and
   has no guard for one **at a shell**, where the same two writes are two
   commands. The freshness gate answers *"has an in-flight attempt timed out"*
   and read CLEAN, correctly; it does not answer *"is this a login prompt or a
   shell."* **Those are different questions and only the first was ever asked.**

   **The guard, not yet implemented:** write a bare newline into the FIFO first
   and read what comes back. `localhost login:` is a login prompt;
   `root@localhost:~#` is a shell and no credential may follow. It costs one
   write and carries no value.

   This is dev scaffolding and dies with it — it belongs beside the dev sshd
   (SECURITY-MODEL gap 4), the netVM dev-root unlock (#11) and the console
   drop-in itself, all of which go before release.

   **Second instance, 2026-09-05 10:16.** Same value, so no new secret — two
   new locations: `katmate-pool@netvm`'s journal on MINIS and the operator's
   terminal scrollback. The guard **worked** earlier the same morning (its first
   successful use) and was **skipped** in a retry form that placed it as a
   separate optional step. **A guard that can be skipped is not a guard**, which
   makes the fix a small dev helper that reads the FIFO's answer and refuses to
   send unless it sees a login prompt — not an instruction. Retirement is
   unchanged: rotate at the next `build/netvm.sh` run with a fresh
   `KATMATE_DEV_ROOT_HASH`.

30. **The host kernel's required-symbol set is recorded nowhere, and the host
   ran outside ADR-004 for an interval no artefact recorded.** Added 2026-09-18,
   from [ADR-036](docs/DECISIONS.md#adr-036) § 7 and § *Gates* G4. **Read from
   the tree only** — nothing was run on MINIS and no kernel config was read on
   either machine.

   The host kernel is load-bearing **by configuration**, and no artefact carries
   the set of symbols the project depends on. `grep -F` over this file returns
   nothing for `vsock_diag` and nothing for `config.gz`; `TMPFS_POSIX_ACL`
   occurs once (`state.md:68`), as a fact about `/run` inside a session entry,
   not as a recorded dependency. The symbols the accepted ADRs have already made
   load-bearing, each named by the ADR that needs it:

   - `vsock_diag` — [ADR-026](docs/DECISIONS.md#adr-026) E4/E6, a *stated
     requirement*. ADR-026 writes its own warning: a future host kernel
     configuration change that drops it silently disables the indicator's
     identity path.
   - the vsock namespace symbols — [ADR-028](docs/DECISIONS.md#adr-028) C6 and
     ADR-029 G0/G1, which together fix a host kernel floor of Linux ≥ 7.0.
   - `TMPFS_POSIX_ACL` — the ADR-035 revision note of 2026-09-15.
   - KVM, VFIO and the IOMMU driver — every netVM boot.
   - whatever the boot-hardening backlog adds.

   **The consequence has already been measured once, and was noticed by
   accident.** The reference host reported `7.0.12-arch1-1` — a stock Arch
   kernel, **not** `linux-hardened` — when ADR-028/029's netns gates were taken
   on 2026-08-02, and `7.1.9-hardened1-1-hardened` on 2026-08-28. For at least
   part of that interval the machine [ADR-004](docs/DECISIONS.md#adr-004)
   governs was not on the decided kernel. No artefact recorded either
   transition, and the return was seen only because a `uname` was read for
   another reason.

   **A sub-question is open and decides where any such check can run:** whether
   the host's kernel config is readable on the running system (`/proc/config.gz`)
   or only from the package. Unread on both machines. #22 already records
   `Cannot find kernel config.`, zero bytes out (`state.md:1118`, `:1269`) — that
   is the **guest** microVM image and does not answer this.

   **Distinct from #22**, which is about tying a guest image to the config it
   was built from. This entry is the *host* kernel, and it is a dependency set
   with no artefact rather than an image with no provenance.

31. **The GUI ingress — the host end of the only channel a guest may draw
   through — cannot be located in version control.** Added 2026-09-18, from
   [ADR-036](docs/DECISIONS.md#adr-036) § 2 and § *Revisit when* 8, which makes
   locating it a **precondition** and not a reopening.

   **The tree half was run, on the Acer, over the whole tree.** ADR-036 asks for
   `git ls-files` across the entire repository rather than the three subtrees the
   2026-09-18 audit covered (`host/`, `desktop/`, `manifests/`):

   ```
   $ git ls-files | grep -E '\.(service|socket|target|mount|path|timer)$'
   host/usr/lib/systemd/system/katmate-publish-nics.service
   host/usr/lib/systemd/system/katmate-sys-driver@.service

   $ git grep -Fn 'waypipe-client' -- .
   docs/DECISIONS.md:903:  `waypipe-client` systemd user unit points there. The distro waypipe
   ```

   Two systemd units are tracked in the entire repository and neither is the
   waypipe listener. The string `waypipe-client` occurs in exactly one tracked
   file — [ADR-019](docs/DECISIONS.md#adr-019), the document that *names* the
   unit as pointing at `/opt/katmate/bin/waypipe`. Widening the search from
   three subtrees to the whole tree therefore **confirms** the audit's finding
   rather than correcting it: the unit is tracked nowhere.

   **The MINIS half was not run and is not claimed.** `systemctl --user cat` of
   the socket and service units on the reference host, compared byte for byte
   against the tree, is the remaining half. This session did not touch MINIS.

   **Until both halves are read, one of two documents is wrong, and which one is
   unsettled.** Either the unit is tracked somewhere neither search reached and
   `SECURITY-MODEL.md` § *GUI forwarding* stands as written, or it exists only on
   the reference host's disk — in which case `docs/HOST-CONFIG.md` is missing an
   entry whose failure mode is that **a fresh install has no GUI path at all**.

   **Location is what is open here, not classification.** ADR-036 § 2 rules that
   the ingress belongs to the system rather than to the desktop user's session,
   whatever its location turns out to be — but **ADR-036 is PROPOSED**, that
   ruling is not in force, and nothing in this entry acts on it.

32. **Whether user theming reaches the two domain-indicator carriers has never
   been measured.** Added 2026-09-18, from
   [ADR-036](docs/DECISIONS.md#adr-036) § *Open, and named as open rather than
   decided*. **Nothing was run** — this entry records the absence of a
   measurement, not its result.

   [ADR-026](docs/DECISIONS.md#adr-026) names two carriers for the domain
   indicator: the bar module and the focused border colour. Both are values a
   user theme can set. No measurement on either machine shows that a
   user-supplied theme cannot reach them, and `grep -F 'theming'` over this file
   returns nothing.

   The question stands independently of ADR-036's status: ADR-026's carriers are
   **accepted**, and if a theme can repaint either of them then the identity path
   is user-modifiable today. What ADR-036 adds is only the rule that the answer
   be **measured** rather than assumed.

33. **RESOLVED 2026-09-20 — the `systemd-sysctl`/udev ordering inside netVM.**
   Kept as a closed marker so the number is not reused. The published title
   sentence is left exactly as written: **The `systemd-sysctl`/udev ordering
   inside netVM is unmeasured, and it is a precondition of any per-slot value.**
   **[THE ORDERING IS ANSWERED as of 2026-09-20 — `systemd-sysctl` runs BEFORE
   the rename.]** Promoted 2026-09-18 out of the
   2026-09-12 … 2026-09-14 session entry, which rotates to `docs/SESSIONS.md` and
   would take the question out of the living document with it. **Nothing was
   run** — this entry moves a record into the section that keeps it, and adds no
   reading.

   **ANSWERED 2026-09-20. `systemd-sysctl` runs BEFORE the rename.**
   `systemd-sysctl.service` **finished between guest monotonic 3.135120 and
   3.392187**, and **all 16 of 16** renames to `km00`…`km0f` fall after it
   (3.392187 … 3.989274). Measured on the **netVM boot of 2026-09-12** and read
   from the **host** journal on 2026-09-20, with netVM down and MINIS never
   entered by the session that wrote this line: the guest's serial console lands
   in the host journal, which is the observation path that made the reading
   possible at all (§ *Invariants & gotchas*, the entry on console durability).
   Source: `auditfix-liveread-report.md` § 2.6.

   **The controls, because the load-bearing half of this is a negative.**
   *Positive control:* the same cut applied to the **first-stage** renames puts
   **17 of 17** on the *other* side (`eth`→`enp0sN`, monotonic 1.517076 …
   1.607757, all before) — the cut point can demonstrably place a rename on
   either side, so the 0/16 is the phenomenon and not the instrument.
   *Cardinality:* sixteen rename records, every name `km00`…`km0f` exactly once,
   no gaps and no duplicates — **which is also the first measurement that the
   rename fires at all**. *Negative control with its own positive:* **0** lines
   of the guest boot console name `rp_filter` against **3** naming `sysctl`, so
   the grep fires and the zero is a real absence.

   **The rename happens in two stages, and no document recorded that.** Stage
   one at ~1.5 s renames all seventeen NICs `ethN`→`enp0sN` — kernel/udev
   default policy, the uplink included (`eth16`→`enp0s4`). Stage two at
   ~3.4–4.0 s renames the sixteen virtio slots `enp0sN`→`kmNN`, after
   `systemd-udev-trigger.service` coldplugs them against the real root's rules.
   **`systemd-sysctl` runs between the two stages.**

   **The consequence, which is the half that binds: a per-`kmkk` sysctl cannot
   take effect at boot**, because no interface carries that name when
   `systemd-sysctl` runs — the sixteen exist at that moment under their
   stage-one names. The reasoning below supplied the conditional; this
   measurement supplies the ordering, and the ordering is the unfavourable one.
   [ADR-036](docs/DECISIONS.md#adr-036) § 3's named precondition now has an
   answer rather than a gap. **A revision note is proposed in
   `~/Claude.assistent/b1-docwrite-report.md` and is deliberately not written
   into the ADR.**

   **Two mechanism sentences reconcile this ordering with the 2026-09-14
   `rp_filter` values, and NEITHER WAS MEASURED.** They are written here as
   unmeasured so that no later reading of this entry promotes them: (a) that the
   vendor glob `net.ipv4.conf.*.rp_filter = 2` fires at `systemd-sysctl` time
   against the **stage-one** names and therefore still reaches all sixteen,
   because a glob matches whatever exists; and (b) that a netdev's sysctl values
   **survive** the second rename, the directory being renamed with the device
   rather than reset. Both are consistent with the observed 2 on every `kmkk`,
   and neither was observed. Both are readable at the next netVM boot, when both
   names are visible in one guest.

   **What remains is not an open question but an undecided one** — how a
   per-slot value is to be set given this ordering — and it belongs to
   [ADR-036](docs/DECISIONS.md#adr-036) § 3 and the tier model rather than to
   this list, the second confirmation of the ordering at the next netVM boot
   being worth taking but not a condition of this close.

   **Everything below this point is the record of the question while it was
   open, and is left exactly as written.**

   **What is unmeasured:** whether `systemd-sysctl` runs **before or after** udev
   renames the sixteen virtio devices to `km00`…`km0f`.

   **Why the readings in hand cannot settle it**, which is why it is open rather
   than answered: `net.ipv4.conf.default.rp_filter` is **2**, so an interface
   created after `systemd-sysctl` ran inherits 2 either way, and the observed 2
   on all sixteen slots discriminates neither order.

   **Why it is load-bearing.** Per-device and glob `sysctl` entries take effect
   only on interfaces that exist when they are applied, while `default` governs
   interfaces created afterwards — so the ordering decides whether a per-slot
   value can be set by the obvious mechanism at all.
   [ADR-036](docs/DECISIONS.md#adr-036) § 3 rules that the binding of a peer
   address to its own slot is **T4 and a function of the slot index**, and its
   § *Open, and named as open rather than decided* names this ordering as a
   precondition of any per-slot value, citing `state.md` — which, from this
   session on, is this entry. ADR-036 is **PROPOSED**; the citation is recorded,
   not acted on.

   **What would settle it.** A reading taken at the next netVM boot.
   [ADR-035](docs/DECISIONS.md#adr-035) § 8's rename landed as sixteen
   exact-match `.link` files in the netVM build of 2026-09-05, so the ordering is
   between two systemd components and is readable without new apparatus — unlike
   the fixtures of the 2026-09-12 … 2026-09-14 arc, which the next netVM rebuild
   ends.

   **One copy of the measurement, one pointer to it.** ADR-035's revision note of
   2026-09-14 § 3 is the full record — provenance of `rp_filter` as a systemd
   vendor default, the `max(all, iface)` arithmetic, the glob-override property
   and `enp0s4` inside the same glob — and it is **not restated here**. The
   session entry that carried this file's own register of it is **left exactly as
   written**, per § *Session archive*: *rotation is the only way material leaves
   this file*, and a session body moves verbatim. This entry cites both rather
   than duplicating either.

## Next steps

**ADR numbering.** `ADR-030` = *what the launch daemon reads* (2026-08-06).
`ADR-031` = the licence declaration (GPL-3.0 attribution for the
CYBRland-derived `desktop/` subtree) — **decision taken, document not written**;
the number stays reserved and the gap in the sequence is an honest record of
that. `ADR-032` = *where each tier lives* (2026-08-09).

**Debt carried to ADR-033's acceptance, and it is not part of that ADR's own
open list.** ADR-033's *Costs accepted* section asserts that `-netdev tap` with
`vhost` is the most exercised network path in QEMU/KVM and that `dgram` is not.
**That claim appears in neither link report, and no external source was gathered
for it.** At acceptance it must be either **sourced** or **restated as judgement
rather than fact**. An unsourced superlative about someone else's code is what
`OBSERVATIONS.md`'s own conventions forbid — *"Provenance is mandatory"* and
*"No comparative judgement"* — and a rule this project enforces in one file and
suspends in another is not a rule. **`OBSERVATIONS.md` is clean of it**: the
2026-08-24 entry was written without the clause, deliberately, and it must stay
clean.

*Ruled 2026-08-24:* the clause **stays in the ADR meanwhile**. A revision note
spent on a PROPOSED ADR that will be revisited at acceptance buys nothing, and
removing a sentence from an ADR is not a delegated session's to do.

*Found and flagged by the write pass* (`~/adr033-writepass-report.md` § 5), not
by the session that wrote the clause — which is the reason it is written here at
all. A debt whose only trace is the conversation that created it lasts exactly
as long as that conversation.

**DISCHARGED 2026-08-28, by restatement and not by sourcing.** Acceptance
arrived and no external source had been gathered, so the clause is **restated as
judgement** in a revision note appended to ADR-033 (*"the tap/vhost comparison is
judgement, not a sourced fact"*). The note names the belief as KatMate's, held
without a source, and sets beside it the checkable fact that is about this tree:
every `-netdev` here is `tap`, `app_web.con` carries no network device, so our
own gate history covers `tap` and does not cover `dgram`. **The clause itself is
not edited** — the ADR body is append-only and it stands as written, qualified by
the note. `OBSERVATIONS.md` was clean of the superlative and stays clean; nothing
was added to it.

**`N` is ruled: 16 (2026-08-28), and what still bounds the pool.** ADR-033 held
`N` behind gate M2. M2 is measured (see the `link-m3` entry above) and **`N` is
no longer gated by saturation**: there is no knee, so there is no count of active
links to stay below. The loop is at its ceiling from one link and is shared
continuously from there, and thirty links cost it no more than one does. The
operator has ruled **`N` = 16**, and the reasoning is the record — the number
alone would not survive the first question about it:

- **It sits well below netVM's ceiling, with margin.** The measured ceiling is
  **30** `virtio-net-pci` on the default q35 root bus. netVM carries four other
  PCI devices — the vfio NIC, `virtio-blk-pci`, `vhost-vsock-pci` and
  `virtio-rng-pci` — so roughly **26** slots would remain for link devices.
  **That ~26 is ARITHMETIC, not measurement: netVM's own ceiling has never been
  run.** It is also a subtraction taken on this session's subject, which carried
  network devices and nothing else; netVM's launcher does not use `-nodefaults`,
  so its real figure can only be lower. 16 leaves margin for devices netVM has
  not acquired yet.
- **The subtraction is four and not five, and that is deliberate.**
  `net-sys.con:27` carries a **fifth** PCI device,
  `-device virtio-net-pci,netdev=int0` — the internal p2p segment. It is not
  subtracted because **it is the device the pool replaces**: the slot pool *is*
  the internal segment, generalised from one peer to `N`. Without this clause the
  30 − 4 arithmetic reads as an arithmetic error rather than as a choice.
- **An empty slot is measured cheap.** link-m1 §§ 20–21: a device whose peer path
  does not exist adds one fd, **no thread** and **zero CPU ticks** over a 60 s
  window, at a few hundred kB of RSS. link-m3 confirms the no-thread half under
  load — 4 threads at every `N` from 1 to 30, idle and loaded alike. Slots that
  are never filled cost close to nothing, so a generous pool is not paid for
  until it is used.
- **Growth beyond the pool costs a netVM restart**, and with it every AppVM's
  connectivity (ADR-033, *Costs accepted*). That is what argues against a small
  `N`. It is also why 16 is generous rather than maximal: the cost of guessing
  low is a restart, and the cost of guessing high is nearly nothing — but a value
  at the arithmetic ceiling would leave netVM no room to acquire a device.

**What still bounds the pool, and it is not M2.** `N` is now bounded by **netVM's
own PCI slot ceiling, which is unmeasured.** Raising it means added PCIe root
ports — a topology change, and a separate decision that ADR-033 already names as
one. Measuring netVM's actual ceiling is the outstanding work here; the ~26 above
must not be cited as though it had been.

**ADR-033 is Accepted (2026-08-28), and what follows it is three sessions, in
this order.** Acceptance is a decision; none of the work below was done by it,
and the order is a dependency order rather than a preference.

1. **The pool in netVM.** Sixteen `dgram` slots on fixed socket paths, in
   `net-sys.con` and in `katmate-sys-driver@.service`, replacing the `tap-int0`
   device that is netVM's internal segment today. Nothing downstream can be
   tested against a pool that does not exist, which is why it is first. It also
   settles by construction two of ADR-033's own open items — the socket path
   convention under `/run/katmate/link/` and the slot-to-interface naming — and
   **that naming is the one the ADR flags as unresolved**: NETCFG programs a
   `/32`, and a mapping that is not stable and legible programs the right address
   on the wrong interface. `ExecStopPost=` must unlink the slot's socket, since a
   socket file outlives its process including on a failed start (open problem
   #23).
2. **The `app-routed` template.** An AppVM taking a free slot at launch and
   releasing it at teardown, with slot allocation carried as a field on ADR-017's
   existing CID allocation rather than as a new subsystem.
3. **The guard and the `REQ_ENV` arm, together in one commit.** This is open
   problem **#19**, and its requirement is unchanged by acceptance: the
   unconditional refusal of profile `app-routed` in `katmate-generate-env` and
   the `REQ_ENV` arm behind it fall **in the same commit**, in that order, or the
   profile becomes startable while its environment contract is unenforced.
   **#19 stays open until then** — this pass did not close it and did not touch
   `katmate-generate-env`.

**Further, 2026-09-02 — step 1 now has an ADR, and an acceptance path.**
[ADR-035](docs/DECISIONS.md#adr-035) is appended as **PROPOSED** and decides the
pool's identity: a slot is an index `k ∈ 0…15`, and its MAC
(`52:54:01:00:00:kk`, a T4 constant written literally and never projected), its
peer address (`10.100.1.(16 + k)`, the pool's peer block being `10.100.1.16/28`),
its socket paths (`/run/katmate/link/<netvm>/<kk>/{netvm,appvm,owner}`) and its
in-guest name (`kmkk`) are all **views of that index**, none derived from
another. Step 1 above says it *"settles by construction two of ADR-033's own open
items"*; those two — the path convention and the slot-to-interface naming — are
now settled **on paper**, by ADR-035 §5 and §8, and step 1 becomes the
implementation of a written decision rather than the place the decision gets
taken. Four of ADR-033's six deliberately-open items are closed the same way;
the revision note on that ADR lists all six with their state.

**The acceptance path is ADR-035's six gates, and NONE has been taken.** G1 the
pool exists — sixteen slots start under `-nodefaults`, all DOWN and
networkd-unmanaged, with a seventeenth device's refusal as the measured ceiling
netVM's own has never had. G2 one address on many links. G3 duplicate MACs
refuse. G4 release leaves nothing. G5 the link tree survives a netVM restart.
G6 the boundary holds. **Each has a refusal half**, and a gate is passed by
observation quoted verbatim or it is not passed.

**Further, 2026-09-12 — five of the six gates were taken or attempted in one
day, across five delegated sessions, and ADR-035 still cannot move PROPOSED →
ACCEPTED.** Status, matching ADR-035's 2026-09-12 revision note (finding 8)
and not re-derived here: **G1, G2 (both halves), G5a and G6a taken; G5b not
taken** — the missing clause is restoration *after* the restart, and the
guest → netVM direction of slot 00 is unmeasured (`tx` stood at 17
throughout), so no ADD has yet been shown to carry both directions of one
slot; **G3 not performable** until decision 7 (`ifindex_by_mac` counting)
lands; **G4** three of six rows, its refusal half failing in the redesigned
form; **G6b blocked** on decision 9 (the AppVM template and its two
scalars). See [ADR-035](docs/DECISIONS.md#adr-035)'s 2026-09-12 revision note
for the full table and the eleven findings behind it — not duplicated here.
**Two facts a reader needs before touching the machine:** slot **01** is left
**RELEASED** (re-install with `ping-client netcfg-add 3 201
52:54:01:00:00:01 10.100.1.17 100`), and **the dev console is already at a
live root shell** — no login step is needed. **Outstanding before the next
measuring session:** the `PEER:` fixture line carries no timestamp and needs
one (see *Invariants & gotchas*); without it a reading cannot be placed
against the events around it.

**Three things step 1 inherits that were not visible before it had an ADR.**
(a) The agent gains a duplicate-MAC check (§7), a neighbour delete, a conntrack
flush, and a DOWN on REMOVE — **none of which exists today**; the 2026-09-02
session entry quotes the code for each absence. (b) The netVM instance name
reaches a `sun_path` for the first time, and nothing bounds its length — open
problem **#28**. (c) `ARCHITECTURE.md` § *Networking*, its `Link` row, and
`SECURITY-MODEL.md` § *Known gaps* 14 must change **at acceptance and not
before**: at PROPOSED they would describe a pool that does not exist.

**#27 is still where it was put.** Its fix lands in this step, where the
guest-side `netvm-agent` unit is rewritten anyway — and ADR-035 says so in its
own § *Context*, so the two records agree.

Two consequences ride along and belong to whoever does step 1: ADR-015's
`web`-manifest-without-network warning stops firing on `app_web` once its T1
names a netVM, and `--strict` becomes usable over the real T1 set.

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
- **`chmod` after `setfacl` rewrites the ACL mask, and can leave every named
  entry ineffective.** Measured 2026-09-15 as an accident: a `chmod 1710`
  issued after the `setfacl` left `mask::--x` and a named `rwx` entry reading
  `#effective:--x`, so a gate meant to read the sticky bit was decided by the
  mask before the sticky bit was reached. **The order is mode first, ACL
  second, `getfacl` read-back third** — for every writer of this tree, the
  launch daemon's own reconcile included. And `getfacl` showing a named entry
  is not evidence that the entry is effective: the `#effective:` comment is,
  and its absence is what a correct-looking, non-functioning grant looks like.
- **A code path that only ever runs in its convenient mode is untested in the
  mode that matters — and "convenient" usually means "without root".** A script
  with a `--dry-run`, a `--check`, a `--no-act` or any other unprivileged mode
  will be exercised in that mode, because that is the mode a person can run
  safely and repeatedly. Everything the privileged path does differently is then
  covered by nothing. **Environment is the usual difference and the easiest to
  miss:** `sudo` resets `HOME`, `PATH`, and the whole environment under
  `env_reset`, so any default of the form `${VAR:-$HOME/...}` resolves to one
  place when a person tests it and another when the tool runs for real.
  Measured 2026-09-01 as open problem **#25**, where a dry-run that requires no
  root had passed a check hundreds of times that dies as root — but the shape is
  not specific to that script.

  **The general rule: when a script has a privileged mode and an unprivileged
  one, any value it derives from the environment must be measured in BOTH.** One
  command settles it — `sudo -n bash -c 'source <config>; echo "$VAR"'` beside
  the same line without `sudo`. And the reason this class hides so well is worth
  stating on its own: **a check that cannot fire is indistinguishable from a
  check that found nothing.** Both are silent. Neither appears in a log. The
  only way to tell them apart is to make the condition true on purpose and
  confirm the check notices.
- **A refusal list is also an execution order, and a check behind a refusal is
  untested until that refusal is relaxed.** Measured 2026-09-01 on
  `tools/capture-kernel-provenance`. Relaxing one refusal — a missing git tag
  stopped being fatal and became an empty field — made a *later* check reachable
  for the first time: on a tagless tree the earlier refusal had always fired
  first, so the whitespace-in-paths check had never executed on that input at
  all. Nothing about the later check changed. **The general lesson:** a gate that
  exercises a refusal proves only that the refusal fires, never that anything
  behind it works, and relaxing a refusal can expose untested code without any
  edit to that code. When a refusal is removed or softened, the checks downstream
  of it are new code as far as evidence is concerned.
- **netVM refuses to start after a host reboot, with `208/STDIN` and no cause
  named: the dev console drop-in survived and the FIFO it points at did not.**
  The three parts of the dev console (SECURITY-MODEL gap 15) do **not** persist
  alike. `/run/katmate-dev/netvm-console.in` is on **tmpfs** and
  `km-console-holder.service` is **transient**, so both vanish on reboot;
  `/etc/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf` is in
  `/etc` and **does not**. The drop-in then points `StandardInput=file:` at a
  path that no longer exists, and

  ```
  ... Failed to set up standard input: No such file or directory
  ... Failed at step STDIN spawning <binary>: No such file or directory
  ... Main process exited, code=exited, status=208/STDIN
  ... Failed with result 'exit-code'.
  ```

  **The failure is ABOVE `ExecStart=`, in execution-environment setup, so not
  one `ExecStartPre=` runs** — no `katmate-check-image`, no
  `katmate-activate-lvs`, no `katmate-generate-env` — and none of the T4
  diagnostics this project put there fires. **The journal names the directive's
  category and not the artefact:** it says *standard input* and *No such file or
  directory*, but **not the path, and not the drop-in**, so someone who does not
  already know the scaffolding exists has no thread to pull, and nothing in
  `git` will tell them (no part of the console is tracked). The fix is either
  recreate the FIFO and its holder, or delete the drop-in — which restores the
  shipped `StandardInput=null`.

  **This is the second time this project has been bitten above `ExecStart=`**,
  and the shape is the invariant. On 2026-08-17 gate G1 failed because
  `EnvironmentFile=` without a leading `-` is loaded before every `Exec*`, so an
  absent projection failed the execution-environment setup **before the
  `ExecStartPre=` that creates it was spawned** — and nothing in the unit's own
  transcription was exercised. Same class, different directive: **a unit
  directive that opens a file opens it before the unit's own preflight can say
  anything about it, so the preflight's diagnostics are unreachable exactly when
  the file is the problem.** Measured 2026-09-03 — **on a throwaway
  `systemd-run` unit with an absent path, not on the netVM unit itself**, so the
  status code and the message shape are measured and the netVM instance of it is
  inferred from the same directive.

- **Reading the netVM console: `journalctl -o cat`, never the default format.**
  journald renders any record containing non-printable bytes as
  `[NNNB blob data]`. `login(1)`'s **timeout** path emits `Password: ` glued to
  `login: timed out after 60 seconds` and a run of terminal-reset escapes, all
  on one line — so the password prompt is **stored but invisible** by default.
  Measured 2026-09-03 over one unit's history: **6** lines matching `Password`
  in the default format, every one of them a systemd unit name from boot, against
  **10** under `-o cat`. Two people read the same journal that day and disagreed
  about whether a prompt had ever appeared; the format was the whole of the
  difference. **Absence of a prompt in the default format is not evidence.** The
  same applies to the echoed command line: it carries cursor movements and wraps,
  so an `awk` invocation came back with an extra `)` and a doubled slash while
  executing correctly. **Read the output, never the echo.**

- **Driving a login through a FIFO: two writes, three seconds apart — one write
  loses the password.** With `StandardInput=file:<fifo>` on the VM unit,
  `printf 'root\n<pw>\n' > <fifo>` delivers the username and the password is
  **gone** before `login` prompts; `agetty` then times out after ~62 s and the
  failure reads exactly like a wrong password. Two separate writes about 3 s
  apart work: `localhost login: root` → `Password:` → evaluated, in under six
  seconds. Measured 2026-09-03 as a gated A/B, where the gate is *"the last
  `localhost login:` record is older than 65 s"* — a gate that merely looks for
  the Debian banner in the last few records is **unsound**, because the banner
  sits above the prompt and is present mid-attempt as well as after a reset;
  that mistake made an earlier probe report the single-write form working, which
  is the opposite of the truth. **Why** the single write loses it (agetty
  buffering across the `exec`, or `login` flushing terminal input before
  prompting) is **not measured**. Also: the password must be typed *before* the
  first write, or typing time eats the 60 s window.

- **A command form written into a brief is untested code, and its wrong answer
  can be well-formed.** `ip -o link | awk '{print $2, $(NF-2)}'` returns the
  **broadcast** address for every ethernet interface and the right value only for
  `lo`. As G1a's sole MAC reading it would have reported sixteen identical MACs —
  plausible, structured and false. Caught only because a second independent
  reading (`/sys/class/net/*/address`) had to agree. Same class as the
  `nv-diag3.sh` harness of 2026-09-03. In the same three days a brief also
  carried `pgrep -a qemu-system-x86_64`, which cannot match — `comm` is capped at
  15 characters and the name is 18 — leaving a halt condition unanswerable as
  written. **Briefs assert command behaviour as freely as they assert tree state,
  and the same rule applies: measure, or write it as a question.**
- **The dev console procedure, in full, because no part of it is guessable.**
  Two writes into `/run/katmate-dev/netvm-console.in`, **at least 3 s apart** and
  both inside `agetty`'s 60 s window: a single write carrying both fields loses
  the password, which is in the FIFO before `login(1)` prompts and is discarded.
  **Read back with `journalctl -o cat`** — the default format replaces any record
  containing non-printable bytes with `[NNNB blob data]`, and the guest's
  `Password:` arrives glued to terminal escapes, which hid it for an entire
  session on 2026-09-03. **Send a bare newline first** and read what comes back:
  a login prompt takes the credential, a shell prompt must not (2026-09-04).
  A logged-in session lasts as long as the VM; close it with `exit` through the
  FIFO — killing the holder gives QEMU EOF on stdin, killing the unit stops the
  VM.
- **`katmate-sys-driver@netvm` and `katmate-pool@netvm` must never run at
  once** — same instance name, same LV, same CID, same VFIO device — and both
  point at the same FIFO, so the `208/STDIN` failure after a host reboot now
  applies to both.
- **QEMU does not unlink its `netvm` nodes at exit, but it does `unlink()`
  before `bind()` — the earlier claim that a sweep is load-bearing against
  `EADDRINUSE` was wrong, and is corrected here.** Measured 2026-09-12: a
  `katmate-pool@netvm.service` restart ran with no sweep, no `ExecStopPost=`
  and sixteen surviving `netvm` nodes, and it **succeeded** — all sixteen
  rebound at new inodes, no `EADDRINUSE`, nothing naming a syscall anywhere in
  the journal across the stop and the start (source: `g5b-restart-report.md`;
  carried in ADR-035's 2026-09-12 revision note, finding 7). **Every
  `EADDRINUSE` in the g1b report was counterfactual**: that session's sweep
  always ran first, so the branch was never taken and a hypothesis about an
  untaken branch was published as a measured invariant. What is unchanged:
  QEMU still does not unlink `netvm` nodes at exit — not on a clean `SIGTERM`
  stop, not after a start refused at a device (2026-09-05, four exits,
  16/26/27/26 nodes surviving), a refused start having already bound **all**
  its backends because netdevs are created before devices. Only the
  consequence drawn from that observation was wrong.
- **`ExecStopPost=` stays — operator ruling of 2026-09-12 — with its
  motivation rewritten: not `EADDRINUSE`, which does not occur, but a hijack
  window.** Between a `stop` and a `start`, an **unheld** `netvm` node stands
  in the slot directory, and any process with write access there can bind it
  and receive AppVM frames in the gateway's place. **A pre-start sweep runs
  too late to close that window** — only an unlink at stop does. §5's
  `ExecStopPost=` unlinking the sixteen `netvm` files remains
  **unimplemented** (ADR-035's 2026-09-12 revision note, finding 7).
- **`RuntimeDirectoryPreserve=yes` is load-bearing, reconfirmed under a live
  peer.** A second, independent restart of `katmate-pool@netvm.service`
  (2026-09-12) left `appvm` inode 7528, its bound `/proc/net/unix` socket
  7079435 and the peer's fd 11 all unchanged across the restart (source:
  `g5b-restart-report.md`; the first such observation was
  `adr035-g5a-report.md`, 2026-09-07).
- **`pgrep -x qemu-system-x86_64` never matches, and the trap bit twice.**
  `comm` is capped at 15 characters and the name is 18. After the `-a` form
  was recorded below, a step-0 probe used `-x` and read **0** against a
  `pgrep -f` / `/proc/*/comm` reading of **2**, on 2026-09-12
  (`g2-refusal-g6-report.md` finding 6; `g3-g4-console-report.md`). **Neither
  form of the bare process name works — use `pgrep -f` or read
  `/proc/*/comm`.**
- **A guard placed as a separate step is not a guard.** The FIFO login guard —
  a bare newline, and refuse to send unless the answer is a login prompt —
  worked the first time it was used and was skipped an hour later in a retry
  form that made it optional. Guards belong inside the thing they guard.
- **`grep -F` on a phrase that wraps across a line returns a false negative.**
  Splice the file before concluding a string is absent. Same class as the
  `$`-in-a-BRE trap: the check does not fail, it answers wrongly.

- **Documentation vocabulary: abstract in ADR prose, machine names where they
  identify a measurement site.** Ruled 2026-09-01. A machine named in design
  prose is concreteness that belongs here in `state.md`, not in an ADR — write
  *"the build machine"*, *"the kernel build tree"*. But a machine named beside a
  measurement is **provenance**, and a measurement without a site is a weaker
  measurement: ADR-033's *"(2026-08-24, MINIS)"* is the precedent, and ADR-034's
  acceptance note names sites for the same reason. Session reports live outside
  the repository, so the ADR is often the only thing that will still know where a
  figure was taken. Repository-relative paths and measured numbers are always
  fine.
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
- **netVM `netvm.sh` cleanup — hardened 2026-07-24; the rule it left behind is
  stated once, in the entry below.** The symptom (build finishes, yet
  `Open count: 1` + live `jbd2/dm-<n>` while `mount`/`lsof`/`fuser` are clean)
  came from ORDERING: `sync` ran before `umount_root`, and a sync on a
  still-open mount does not settle jbd2. Now umount → `sync` → `udevadm
  settle`, via `netvm_umount`, which surfaces umount failure instead of
  swallowing it the way `lib.sh:umount_root` does. The prescription this entry
  used to carry (`umount -R`+`sync`+`settle`+`sleep` before return) could not
  have worked — on failure the script never reached its unmount at all.
  **What to do about a hot jbd2 is the next entry's, and is not restated
  here.**
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

  **Twice more since, on two different builds, and both succeeded.** The build
  of **2026-09-03** left the device held on a host up since 2026-08-28 — the
  hold that cost the reboot of 2026-09-05 20:10:29 — and the build of
  **2026-09-05**, run after that reboot, left it held again: `Open count: 1`
  with `jbd2/dm-9-8` (PID 16127) started 20:38:04, before the build published
  its image at 20:40:32. **The hold follows *any* `build/netvm.sh` run,
  successful or failed.** It is not a symptom of failure and never was a test of
  one.

  **So the operational rule is a reboot BEFORE each `build/netvm.sh`, not a
  reboot after a failure.** The script's own preflight (`build/netvm.sh:122`)
  refuses to clobber an existing `$DEV` and names `lvremove -f` as the way past
  it — which is the one thing a held device makes unsafe. Rebooting first costs
  a boot; meeting the hold at the preflight costs the boot anyway, plus the
  build. Source for the 2026-09-05 reading:
  `~/Claude.assistent/netvm-rebuild-3-report.md` § 13.
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

- **The running kernel on MINIS is a hardened Arch kernel,
  `7.1.9-hardened1-1-hardened`, NOT a 6.12.y microvm kernel.**
  `~/src/kernel/linux-6.12.y/` (and any 6.12.94 tree) is the GUEST microvm
  kernel source, unrelated to the host. Do not build host modules against it
  (vermagic mismatch) and do not reason about host USB/driver behaviour from
  6.12.y. The custom `6.12.87`/`6.12.94` kernels are `-kernel` payloads for
  guests only. **Corrected 2026-08-28:** this entry read `7.0.12-arch1-1` until
  then; `uname -r` on MINIS reports `7.1.9-hardened1-1-hardened` *(chat-only —
  read on MINIS 2026-08-28, no report file)*. The machine has moved to a
  **hardened** kernel, which the entry did not anticipate, so a host-side
  measurement taken before that date may not reproduce.

- **Check a config's header line before reading symbols out of it.** Line 3 of a
  Kconfig-generated file names the version it was generated for
  (`# Linux/x86 6.12.87 Kernel Configuration`). The MINIS kernel tree's
  `.config` is an unrelated **Arch 7.0.12 host config**, written five days after
  the 6.12.87 build; reading `CONFIG_LOCALVERSION*` out of it returned the right
  answers from the wrong file, and only the header caught it *(chat-only —
  MINIS, 2026-08-28)*. A `.config` sitting in a kernel tree is not evidence that
  it belongs to that tree's last build.

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

- **A parsing harness is code, and needs the same behavioural proof as the thing
  it measures.** A `bash -n` and a clean `gcc` are parses; so is a driver script
  that has never been run against real output. link-m3's Part 2 harness was
  **wrong three times** before the sweep ran, and each defect would have produced
  a confident wrong number rather than an error:

  1. `printf "t=%9.3f"` emits `t=` and the padded number as **two** `awk` fields,
     so `$3` was the timestamp and the interface name was in `$4`. Every
     per-interface guest count read **zero** while the guest's own total read
     13 370 101 — the sweep would have reported **100 % loss at every `N`**, the
     most dramatic possible result and entirely an artefact.
  2. Process-level CPU (`/proc/<pid>/stat`) reads ~199 % of a core under
     `-accel kvm` because it **conflates the event loop with the vCPU thread**.
     The gate's subject is one thread, so the process figure would have made a
     saturated single loop look like a process with headroom on a 16-core box.
  3. The vCPU thread's `comm` is `CPU 0/KVM` — it **contains a space** — so its
     columns shifted and it read as zero.

  A fourth was caught only because the harness had been given a line whose job
  was to catch it: per-thread ticks summed to **9042** against a process total of
  **11930**. Measured rather than explained away: process `utime` includes
  guest-mode time (process `gtime` rose 33 → 822 over the window) while the
  per-thread rows do not. So the **event-loop row is sound** — that thread runs
  no guest code and its `gtime` is 0 at both ends — the **vCPU row is a floor,
  not a total**, and the two are not claimed to sum.

  **One throwaway repetition before a sweep costs minutes, and it is the
  difference between a measurement and a fiction.** Add a reconciliation line
  that must hold, so the harness can fail loudly instead of quietly. This is
  again a reading in the link arc carried by a behavioural check rather than by a
  clean compile — link-m2 § A.1 verified an `strace` filter against a program
  known to issue the calls, § B1.2 proved a receiver printed before its silence
  was trusted, and link-m3 § P1.2a caught a `timeout` that fired while `/init`
  was still in its device-poll, so the check ran, printed, looked like a pass and
  never reached the code under test. (link-m3, 2026-08-28.)
- **`systemd-run --unit` reporting `active` is not proof the process is doing
  its job.** The console holder read `active` while blocked in `open()` on the
  FIFO with fd 3 absent — the pre-rendezvous state. `is-active` cannot
  distinguish it; the main PID's `comm` can (`bash` = unparked, `sleep` = held),
  and `fd 3` being `l-wx` on the FIFO is the rendezvous itself rather than an
  inference from a process name.
- **`ss -xl` is not a path check.** Between a stop and a start it printed
  `…/00/appvm` while that path did not exist — it reports the path recorded in
  the bound socket, not presence in the filesystem. Split path from fd: `ls -i`
  answers the path, `/proc/<pid>/fd` answers the binding.
- **After a push, reading back `origin/main` is not server confirmation.** The
  push writes that remote-tracking ref itself as bookkeeping, and a following
  `fetch` has nothing to fetch. `git ls-remote origin refs/heads/main` asks the
  server. Same shape as the "grep, not `git log`" rule.
- **`StandardInput=file:<path>` is not readable from `systemctl show`.** It
  reports `StandardInput=file` with no path and no `StandardInputPath` beside
  it, so a check asserting the path fails against a correctly configured unit.
  Verify the console by the drop-in's presence and by the unit actually
  starting.
- **`cp -a` in `netvm.sh` step 5 bakes the builder's ownership into the image.**
  The build tree on MINIS is `host:host` and `host` is uid 1000, so every file
  from `netvm.conf.d` lands owned by uid 1000 inside netVM — including
  `nftables.conf`. Nothing is broken at mode 0644 and udev does not care, but if
  a uid-1000 user exists inside netVM it owns the firewall ruleset. **Whether
  one exists has not been read.**

- **A negative that coincides with a natural expiry window is not a
  measurement.** A conntrack read 39 s after the last flow came back empty,
  inside the default 30 s ICMP expiry — indistinguishable from a successful
  flush. Every later read was timed inside the window, on both sides of the
  event that mattered, and the entry was then seen to **age** (ttl 27 → 23)
  rather than vanish. Source: `g3-g4-console-report.md` § 5.3 (2026-09-12);
  carried in ADR-035's 2026-09-12 revision note, finding 2.
- **A console guard's window must require a prompt newer than its own
  probe.** A 25-record window was satisfied by a `localhost login:` record
  **five hours old**, so the guard passed on evidence that predated the thing
  it was checking. Source: `g3-g4-console-report.md` (2026-09-12).
- **A guard watches the echo, not the prompt.** `Password:` and
  `localhost login:` carry no trailing newline, so neither ever flushes a
  journal record on its own and a guard keyed on them can never fire — send a
  bare newline first and key on the **echoed input** (`localhost login:
  root`). **A check that cannot fire is indistinguishable from a check that
  found nothing.** Source: `g3-g4-console-report.md` (2026-09-12).
- **A quotation that wraps across a line is not a search string.** Two of
  write pass A's brief quotations returned zero under `grep -F` because the
  tree wraps at ~76 characters; the text was present in both cases. **Reading
  the line range is the correct response to a `grep -F` miss on quoted tree
  text; halting is not.** When a brief quotes the tree's own text, quote a
  fragment that cannot wrap, or say to search with whitespace normalised.
  Source: `adr035-writepass-a-report.md`.
- **The clock is evidence, and an instrument that omits it destroys a
  reading.** Whether the slot-00 ADD of 12:47:42 CEST fell before or after
  the 09:59:37 CEST restart decided what its reading measured at all. **The
  fixtures' `PEER: seq=` line carries no timestamp** (`g2-add-report.md`), so
  elapsed time is not recoverable from a capture on its own and a reading
  cannot be placed against the events around it without an external clock.
  **Required instrument change, not yet made:** add a timestamp to the
  `PEER:` line before the next measuring session.
- **A counter that has never been non-zero, rising for the first time,
  measures first traffic — not restoration.** The positive-control rule
  inverted, and what kept a slot-00 restoration reading honest: the guest's
  `eth0 rx` rising 0 → 6 → 11, after 2034 consecutive zero readings over that
  peer's whole life, is first traffic from a peer that only started after the
  restart — not evidence of anything surviving it. Source: ADR-035's
  2026-09-12 revision note, finding 8.
- **Claude does not assert machine state from memory — a brief says *read
  this and report*, never *it is X*.** The confirmed instance in this arc is
  the console guard above, written so that it could not fire at all on the
  no-trailing-newline case. (Two further instances — an interface assumed UP after a restart, and an uploaded file assumed to be pasted content — occurred in the 2026-09-12 briefing sessions and have no repository artefact: no agent report can carry them, because they were never on the machine. Briefing-side errors leave no trace in the tree, which is itself the reason this rule is written here.)
- **A comparison must report its cardinality — how many elements it compared —
  beside its verdict. A verdict without the count is not a measurement.** An ANSI
  strip written for `m`-terminated CSI sequences alone met journald's
  bracketed-paste marker `ESC[?2004l`, which survived it, glued itself to the
  **first** value line of each block and defeated the anchor — so one key, and
  only that key, vanished from each of three extractions. The diff then reported
  **IDENTICAL over 60 keys instead of 61, and would have reported it even if that
  key had differed.** It was caught only because the key count disagreed with the
  visible output; had the counts happened to match, the drop would have gone
  unnoticed. **Same family as this section's first bullet and *"A guard watches
  the echo, not the prompt"*: a check that cannot fire is indistinguishable from
  a check that found nothing** — and the cardinality is what separates them,
  being the one number a silently reduced set cannot fake. Source:
  `mcast-read-report.md` § 8 (2026-09-14).
- **A claim about what a repository document says is verified by reading the
  section the claim is about. A grep for your own phrasing is a null control.**
  The document may state the same fact in other words, and the empty result then
  reads as confirmation of the claim. A brief asserted that QEMU-to-QEMU over
  `-netdev dgram` had never been measured in this project, while ADR-035's own
  gate row published both deliveries by name and by report section; `grep -F` for
  *"QEMU-to-QEMU"* returned **nothing**, because the ADR states the fact in other
  words, and the false sentence was caught only by reading the section the
  brief's own item was about. **The third face of the family this section already
  carries twice** — the first a command form (*"a command form written into a
  brief is untested code, and its wrong answer can be well-formed"*), the second
  machine state (*"Claude does not assert machine state from memory"*) — and the
  most deceptive of the three, because a sentence about what an ADR says is
  checkable in one second and reads exactly like a sentence about what an ADR
  says. **A check that cannot fire is indistinguishable from a check that found
  nothing, and a grep for your own wording is such a check.** Source:
  `writec-report.md` § 5.3 (2026-09-14).
