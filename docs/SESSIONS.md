# Session Archive — Katmate OS

> Historical session log, split out of `state.md` on 2026-07-14 (it had grown to
> 1090 lines / 68 KB, against its own "stays short" mandate). `state.md` keeps the
> header, the current focus, the **two most recent sessions**, and the living
> sections (live state, open problems, next steps, invariants). Everything older
> lands here, verbatim, newest first.
>
> **Entries are append-only and are never rewritten.** They are records of what
> was true on the day they were written, not statements about the current target.
> Two *insertions* have been made, both repairs of the ordering invariant rather
> than edits to any entry: on 2026-07-26 the 07-14 and 07-13 entries, and on
> 2026-08-06 the 07-23, 07-21 and 07-20 entries plus the first of the two
> 2026-08-02 sessions. The *second* 2026-08-02 session (ADR-029) arrived here
> normally on 2026-08-06 as `state.md` rotated it out, and therefore sits above
> the first — newest first, as everywhere in this file. In each case the material had been stranded in `state.md`
> while later sessions went straight to this file. The 2026-08-06 insertion
> carried two repairs inside a moved block, both marked where they occur: a
> dangling "see debt #14 below" cross-reference now pointing at `../state.md`,
> and the removal of the leading `**YYYY-MM-DD ...**` date stamps that only made
> sense in `state.md`'s flat preamble. The 2026-08-02 entry is explicitly
> reconstructed and says so in its own header.
>
> **Reading note — heading prefixes.** The `This session` / `Previous session`
> prefix is **not normative** in this file: the date in the heading is the
> identifier, a rotated entry keeps the heading it was published with, and a
> `This session (2026-09-15)` here is therefore not a claim about recency.
>
> **Reading note — CIDs.** [ADR-022](DECISIONS.md#adr-022) was written in the
> 2026-07-14 session. Entries dated **2026-07-13 and earlier** use the old
> single-sysVM map (`3` = netVM, `4` = personalVM, `5` = app_web). The current
> map is `2` host / `3–19` sysVM / `20–99` fixed AppVM / `≥100` disposable, under
> which **personalVM becomes 20 and app_web becomes 21** (netVM stays 3). Old
> numbers are left as written — they are what actually ran at the time.
> `state.md` carries the authoritative map.
>
> **Reading note — build-order ordinals.** `ROADMAP.md`'s build order is
> referenced by number from several entries. [ADR-030](DECISIONS.md#adr-030)
> (2026-08-06) inserted a step and renumbered the tail: old 3/4/5 became
> **4/5/6**, and a new step 3 (VM description as data → launch daemon) took
> their place. Entries written **before 2026-08-06** use the old numbers and
> are left as written. `ROADMAP.md` carries the authoritative list.
>
> **One exception, and it is not a defect.** The 2026-08-03 entry names
> `HOST-CONFIG.md` as an input to build-order **step 6**. It was written when
> that step was 5; the ordinal was corrected on 2026-08-06 while the entry still
> lived in `../state.md`, and the entry arrived here already carrying the new
> number. It is therefore correct as it stands and is left alone. The rule above
> describes what was *not* corrected before rotation, not a guarantee about
> every pre-08-06 entry.

---

## Previous session (2026-09-29, step 4a — s4a-impl A and B) — the host side of the first routed AppVM: implemented, installed, and first run on MINIS; R78–R84

Three sessions. `s4a-impl-A` wrote the code on the Acer, halted once at
its read pass (D1, D2), and after the operator's rulings made four
commits, unpushed. `s4a-impl-B` installed them on MINIS and ran
`katmate-app-routed@app_web` for the first time, 09:31–09:39 CEST, with
no commit, build or reboot. `wp-0929b` wrote the record on the Acer only.
Their reports are outside the repository:
`~/Claude.assistent/s4a-impl-A-report.md` (A),
`~/Claude.assistent/s4a-impl-B-report.md` (B) and
`~/Claude.assistent/wp-0929b-report.md`.

**A's four commits.** `bb6801d`: the generator emits `KM_MAC_INT` for an
attached AppVM only (#41). `1597445`: `katmate-sys-driver@`'s
`ExecStopPost=` unlinks the sixteen `netvm` nodes (R74). `d6feb9c`:
`app-routed` ships (R61). The guard is gone, the generator gains the
slot lookup, `KM_GUEST_ADDR` and the `REQ_ENV` arm, and the commit adds
`katmate-app-routed@.service` and extends SECURITY-MODEL gap 11 to AppVMs
(R64). `46f8a26`: `app_web.con`'s instance is `app_web` (R69).

**R78–R84 (index; the text is in ADR-037's note of 2026-09-29).** R78 is
the `owner` file's format and its checks. R79: `LINK_ID` is checked, not
projected. R80: `/home` is required for `app-routed`, and ephemeral is
refused as not shipped. R81: the AppVM's one-path `ExecStopPost=`. R82:
no dependency on the netVM unit. R83: the A/B split, the memory backend
carried over, and the console to the journal. R84 (A's D1): the
template's first `ExecStartPre=` removes the projection. A's D2 is
accepted: R80's refusal is reachable only by calling the generator
directly, because `katmate-activate-lvs` refuses ephemeral first.

**B, in summary.** The installed set now equals the tree at `46f8a26`, 10
of 10 by sha256. The delta is renamed `app_web.qcow2`, and `app_web`'s T1
is routed (`netvm = "netvm"`). With no `owner` the generator refused
before QEMU (P4). With an `owner` on slot 01 and link 201 added by hand
the unit started (P6). The projection carried `KM_SLOT=01`,
`KM_GUEST_ADDR=10.100.1.17` and `KM_MAC_INT=52:54:00:6f:19:35`, QEMU held
`…/01/appvm`, the guest kernel received the four ADR-038 tokens, and PING
answered after about 5 s. After SHUTDOWN, `appvm` was gone, attributed to
`ExecStopPost=` by inference (P7). A start refused at check-image left no
projection, and a sentinel at `appvm` survived: R84 observed by record
(P8). R80 refused by direct call (P9). Slot 01 was returned to FREE
(P10). netVM kept MainPID 49895 throughout. **No gate is taken:** the
guest has no address, because its image predates ADR-038.

**The operator's rulings on B (2026-09-29).** B § 4's additions are
accepted: the extra P0 reads, the in-script guards, root-installed
staged files, gated restores, the probe comment and the console copy. B
§ 5.1 (after a clean stop, `systemctl show` returns defaults) and § 5.2
(the unknown-parameter negative has no positive control) are accepted as
findings. B § 6's three observations are in § *Invariants & gotchas*.
**Deferred, not fixed in this pass:** the stale comments of the T1
`app_web.toml` on both machines (B N2), and
`katmate-app-routed@.service:149–152`'s *"UNVERIFIED … 4a-B observes
it"*. Both touch installed files, and the hash-first invariant wants the
tree to equal the installed set, so both are done at the next host install
(4b or later), in the same session as their reinstall. Open problems #19
and #41 are resolved.

**`wp-0929b`'s commits.** The previous-but-one entry rotated out (§
*Session archive*, *Closed 2026-09-29 (third rotation of that day)*;
`61a900e`). There are revision notes on ADR-035 (§5 implemented;
`d64d7c5`), ADR-037 (step 4a, R78–R84; `9fe6e8d`), ADR-038 (the host half
of §10; `2410e3d`) and ADR-030 (`app-routed` shipped; `23c80be`). In this
file: the header, § *Current focus*, § *Live state*, #19, #21, #23, #41,
step 4 in § *Next steps*, four § *Invariants & gotchas* items, and this
entry.

**Not done, and not claimed (B § 7).**
- netVM's `ExecStopPost=` has not executed, because netVM was not stopped.
- No guest networking was exercised: no address, and no ARP, ping,
  capture or route read. NETCFG ADD and REMOVE are claimed only as `OK`.
- ADR-038 G1–G3 and ADR-037 G5 are not taken.
- R84's refusal half, the same start without R84, was not run.
- R78's refusal paths and the absent-pool refusal were not exercised.
- The uid QEMU runs as was not read.
- There is no positive control for *"Unknown kernel command line
  parameters"*.
- `ExecStopPost=`'s execution at P7 has no record, and P7's exit status
  was read from the journal only.
- The validator's cross-file rules were not read from its source.
- `app_web.con` was not run.
- The delta's hash was not taken across P8's move aside and back.

## Previous session (2026-09-29, ADR-038) — AppVM guest addressing written as ADR-038, PROPOSED, and R77 recorded

One session, `wp-0929a`, on the Acer only, docs only. MINIS was not
contacted. Its report is outside the repository:
`~/Claude.assistent/wp-0929a-report.md`. The ADR text is the operator's
payload, `~/Claude.assistent/adr038-payload.md`, appended verbatim.

**ADR-038 is written, PROPOSED.** katmate-init applies an AppVM's `/32`,
its on-link default route and its resolver from typed `km.ip`, `km.gw`
and `km.dns` kernel parameters. The direction is R76. Nothing is
implemented and none of its gates G1–G3 is taken.

**R77 (index; the text is in ADR-038 and in ADR-037's note of
2026-09-29).** The operator's ruling of 2026-09-29 adopts ADR-038 as
written. It covers the parameter names, the one-non-loopback-NIC rule, the
rtnetlink mechanism, syntactic parsing, the error path through shutdown,
the `/run` resolver behind a relative symlink, `lo` on every boot, the
literal gateway and resolver in the template, and the gates.

**The first run's halt, D1, resolved by the operator (2026-09-29).** The
read pass found that the payload called the AppVM's MAC undecided by
ADR-035 §9, while ADR-035 §2 and §9 state it: the instance-derived
identity MAC. The operator ruled that the payload misstated ADR-035. It
was corrected in §4, the rejected alternative (b), *Carried* and *Revisit*
1. The one-NIC rule stands, now on the reason that the image does not know
its MAC. Every other citation the brief listed held at `14d6b10`.

**wp-0929a's commits.** The previous-but-one entry rotated out (§
*Session archive*, *Closed 2026-09-29 (second rotation of that day)*;
`81dfbac`). ADR-038 appended (`60ec98c`); ADR-037 gained a note on R65 and
R77 (`055048d`); ADR-035 a note on § *Dependencies surfaced* (`e6e652a`).
In this file: the header, § *Current focus*, step 4 in § *Next steps*,
#21, #24, and this entry.

**Not done, and not claimed.** No code, no gate, no build. katmate-init
has no network code, no image carries the resolver symlink, and no
template passes a `km.*` parameter. ADR-037 stays PROPOSED (G5).
ADR-038's claims about the kernel's handling of dotted parameters, and
that QEMU exits 0 when init refuses, are read from source or expected, not
observed. G1 reads them.

`wp-0929a` ran on the Acer only and observed nothing on MINIS.

## Previous session (2026-09-28, s4-m0 and rulings) — networking arc step 4.0: the first AppVM on a slot, measured with no code; R75's reading, and R76, ADR-038's direction

Two sessions and an operator reading. `s4-m0` ran from the Acer against
MINIS on 2026-09-28, 21:06–22:02 CEST. Its report is outside the
repository: `~/Claude.assistent/s4-m0-report.md` (cited as M). The
operator read M's captures with `tcpdump -v` at 22:11 CEST. `wp-0928d`
wrote the record on the Acer only, across midnight into 2026-09-29.

**Step 4.0, in summary (M).** `app_web`'s image and kernel ran on netVM's
slot 01 under a fixture launcher outside the repository: `app_web.con`'s
argv with a `-netdev dgram` on slot 01 and `virtio-net-device` on the
derived MAC `52:54:00:6f:19:35`, as a transient unit, with NETCFG link
201 (`10.100.1.17`) added by hand. Three boots, each with a different
kernel `ip=` tail: A with netmask `255.255.255.255`, B with
`255.255.255.0`, C as B plus `ipv6.disable=1`. **M1:** kernel `ip=` works
on the microVM kernel `b34026dd…`, three of three. **M2:** the `/32` was
replaced by a guessed `/8` (*"Guessing netmask 255.0.0.0"*), gateway
kept. **M3:** netVM learned the guest's MAC on `km01`. **M4:** eight SYNs
from `10.3.1.172` reached the LAN in B and C. **M5:** R49 read +0 on all
three boots; C's serial shows IPv6 administratively disabled. Boot A's
firefox step, and B's first, were taken on the Acer's firefox by mistake
(operator's correction), and are void; they became a positive control
that the capture sees port 8099. netVM was not restarted.

**The TTL reading (operator, 2026-09-28 22:11 CEST).** Every packet in
cap-B and cap-C is a SYN to `10.3.1.3.8099`. The Acer's three
(`10.3.1.170`, cap-B) carry **ttl 64**; the eight from `10.3.1.172` (four
in B, four in C) carry **ttl 63**. The table is in
`~/Claude.assistent/wp-0928d-brief.md`.

**The rulings (index; the text is in the notes).** Of 2026-09-28, in
ADR-035's note on step 4.0: **M4 settled** — the ttl-63 SYNs are the
guest's traffic, forwarded and NATed, the first AppVM traffic to leave
through `uplink0`; **M3 settled functionally**, `IFF_PROMISC` unread, an
inference that bears on finding 1 of 2026-09-14 and does not close it;
**boot C's window was the guest's** (firefox restored boot B's session
from the persistent `/home`, 1.3 s after RUN); **M5 not settled and not
needed**, with the R49 hypothesis recorded unverified. In ADR-035's note
on R75: **R75 supersedes the 2026-09-07 ruling's mechanism and keeps its
timing; `RuntimeDirectory=` stays**; how the ACL survives its reset is
C1's. In ADR-037's note on 4.0: **A' not run; M3 and M4 are settled
without it**; M4 is not G5; **R76**, ADR-038's direction, katmate-init
(candidate B), kernel `ip=` not taken. Of 2026-09-29, on `wp-0928d`'s
read-pass halt: M's off-by-four citation of `ping-client` is recorded in
the report, not a halt; *"a real AppVM"* in R71 means one started by
`katmate-app-routed@`, and the fixture launcher does not count (ADR-037's
note); the rotation of this pass is dated 2026-09-29.

**`wp-0928d`'s commits.** The previous-but-one entry rotated out (§
*Session archive*, *Closed 2026-09-29*). ADR-035 gained two notes (step
4.0; R75), ADR-037 one (step 4.0 and R76), and ADR-030 one (R61's
template order), and `ROADMAP.md` step 3a a dated note. In this file: §
*Current focus*, *THE FIRST APPVM ON A SLOT* in § *Live state*, #22,
#24, new #52, and three § *Invariants & gotchas* entries.

**Where M's brief was wrong (M § 8).** Its recall that kernel ipconfig
refuses a gateway outside the netmask did not hold: the mask was replaced
and the gateway kept. B was planned as R49's positive control and read
+0, so C's +0 has no control. Its after-read timing (*"~20 s"*) could not
hold a conntrack reading inside the `SYN_SENT` window; the operator steps
took minutes. It did not say that RUN opens the window on MINIS's screen,
so A's and B's first firefox steps were taken on the Acer.

**Not done, and not claimed.** G5 is untaken, and ADR-037 stays PROPOSED
(G5). ADR-038 is not written. From M § 5, still not read: a conntrack
entry inside its expiry window; `IFF_PROMISC` on `km01` or on the guest's
`eth0`; any capture on the slot, so the ARP exchange was not seen; a
positive control for R49; why ipconfig guessed `255.0.0.0`; the guest's
own view of its routes, neighbours, resolver or IPv6 state; a `/32` by
other means than `ip=`'s netmask field; `netconsole`'s targets (#52). The
fixture's refusal paths are **UNVERIFIED**. A' was not run, by ruling.

`wp-0928d` ran on the Acer only and observed nothing on MINIS.

## Previous session (2026-09-28, s4-readpass and rulings) — networking arc step 4 read against the tree, and the step-4 rulings R60–R75 recorded before any code

Two sessions, both on the Acer only. MINIS was not contacted.
`s4-readpass` read the tree against networking arc step 4, the AppVM side.
Its report is outside the repository:
`~/Claude.assistent/s4-readpass-report.md` (cited as S). `wp-0928c` wrote
the operator's rulings into `docs/DECISIONS.md` and this file.

**The read pass (S), in summary.** It found **nine divergences, D1–D9**
(S § 2), and posed **fourteen questions, Q-S4-1…Q-S4-14** (S § 4). S's
D-numbers are its own. D1: the only launcher that can start an AppVM is
`app_web.con`, which ADR-030's G3 deletes, and no AppVM unit template
exists in any commit. D2: `KM_HOME_DEV` is not a name mismatch; only
`KM_DELTA` is (`app_web.qcow2` against the live `test_web.qcow2`). D3: no
record of a 2026-09-15 ruling on per-slot ACLs was found. D4: ADR-033,
ADR-017 and ADR-035 give the slot allocation three shapes. D5: ADR-035's
*"configures its address by hand through the console"* has no mechanism.
D6: stale SHUTDOWN comments in `opcode.rs` and `vm-agent`'s `op.rs`. D7:
two step lists for the same work disagree. D8: G5 says an AppVM is
required, while F12b's PC-1 and PC-2 already matched its observable with
fixtures. D9 (minor): the ruleset header, already ruled. Also read:
katmate-init has no network code and reads no configuration; the Acer's
microVM config copy has `CONFIG_IP_PNP=y`; and the 63 `ip=dhcp` boots of
2026-09-14 ran the Debian netVM kernel, not the microVM kernel.

**The rulings, R60–R75 (index; the text is ADR-037's note of 2026-09-28).**
R60: step 4 splits into 4.0, ADR-038, 4a, 4b, G5 and 4c (§ *Next steps*).
R61: `katmate-app-routed@` only, with #19's guard removal and the `REQ_ENV`
arm in one commit; `app-offline@` ships with the vault instance; the `.con`
deletion is not in step 4. R62: the slot is ADR-035 §5's `owner` tree,
lowest free, and ADR-033's wording is superseded (notes on ADR-033 and
ADR-035). R63: `owner` written by hand until 3b; no T1 key carries a slot.
R64: the AppVM's QEMU runs as root at step 4, recorded as debt (gap #11 in
4a); C1 is its own step. R65: guest addressing is ADR-038, after 4.0. R66:
IPv6 is decided by 4.0's `ipv6.disable=1` reading. R67: the `netvm-agent`
items land in 4c, one rebuild. R68: the `netvm` cross-file check goes in the
validator. R69: the delta rename, in 4a. R70: NETCFG by hand; re-issue is
3b's. R71: G5 only with a real AppVM, "NATed" observed in a host capture,
and a refusal half. R72: D5 corrected by a note on ADR-035. R73: the
SHUTDOWN comments in 4c (#51). R74: `ExecStopPost=`, netVM side in 4a,
AppVM side in the template. **R75: the operator's ruling of 2026-09-15,
recorded now for the first time** — per-slot POSIX ACLs keyed to per-VM
local users, not plain `chown`; its implementation belongs to C1.
**Recorded, not ruled:** D2 and D9.

**Operator statement (2026-09-28):** the 2026-09-26 boot of `app_web` was
by `app_web.con`, run as `host` (§ *Live state*, `app_web`).

**wp-0928c's commits.** The previous-but-one entry rotated out (§ *Session
archive*, *Closed 2026-09-28 (third rotation of that day)*). ADR-037 gained
the rulings note, ADR-035 the step-4 reading note, and ADR-033 a note on
R62. In this file: § *Current focus*, the step-4 note in § *Next steps*,
#19, #23, #24, #41, #45, #49, new #51, and `app_web` in § *Live state*.

**Not done, and not claimed.** Nothing was implemented, built or run. G5 is
untaken, and ADR-037 stays PROPOSED (G5). S's **[recall, unverified]**
statements are still unverified. The MINIS readings S § 5 lists (the
image's kernel config, the image's packages, `app-web.meta`, the instances
directory, the `netvm` node modes, `cid-pool`) were not taken by these two
sessions. No ADR body was changed.

`s4-readpass` and `wp-0928c` ran on the Acer only and observed nothing on
MINIS.

## Previous session (2026-09-28, f12-impl A and B) — networking arc step 3a implemented, netVM rebuilt on it, and F12a and F12b taken

Two sessions, one step. `f12-impl-A` wrote the guard and the fixtures on the
Acer. `f12-impl-B` added R59, rebuilt netVM on MINIS and took the gates.
Both reports are outside the repository:
`~/Claude.assistent/f12-impl-A-report.md` (A) and
`~/Claude.assistent/f12-impl-B-report.md` (B). `wp-0928b` wrote the record.

**A: the halt, and its rulings.** A's read pass halted on A1–A3 (A § 0.2).
A1: F12b row 2 put `10.100.1.1` on rule 18, but R50's order drops it first.
A2: the brief gave the fixture peer netVM's own slot MAC. A3: the preflight's
mounts are `netvm.sh`'s own, not `lib.sh`'s. The operator ruled **R57**
(`30-netvm-forward.conf` carries the vendor's three `rp_filter` lines
verbatim, with no explicit `all = 0`) and **R58** (row 2 splits into 2a and
2b), and a fixture peer's own MAC is `52:54:01:00:01:kk` (ADR-037's note on
R57 and R58).

**A: five commits, all `G`, pushed (`4650abf..56b3c96`).** `c145a5c` is the
ADR-037 note with R57 and R58, and `5f17de0` the ADR-035 correction of row 2.
`629c92d` adds the chain `slot_guard` (R47–R50). `2ca851f` adopts
`rp_filter` (R51, R57). `56b3c96` adds the R48 read-back and the R52
preflight to `build/netvm.sh`. (A's report says *"six commits"*; its own `git
log -6` includes wp-0928a's `4650abf`.) **The fixtures**, outside the
repository in `~/Claude.assistent/f12/`: `f12peer.py` (a slot peer, with
`--rebind-stale`), `f12lan.py` (row 4, from the host) and `f12-steps.md`
(the procedure). **The Acer checks:** R48's extracted block against six
mutations, and the fixture offline. The `unshare -rn nft -c` syntax check
had no site: the Acer refuses the namespace unprivileged (now an
Invariant), so the ruleset stayed UNVERIFIED until MINIS.

**B: R59, and the classifier.** B's first repository write, the ADR-037
note, was refused by the classifier (*"Modify Shared Resources"*). The
operator allowed it, and it was retried once, verbatim: `a683c6f` carries
**R59** (row 2 becomes 2a, a non-pool segment source; 2b, TEST-NET; 2c,
`10.100.1.1` as an observation row with a two-witness rule), and `81e0736`
the ADR-035 second correction. Pushed `56b3c96..81e0736`. The first copy to
MINIS was refused (*"Remote Shell Writes"*). The operator switched the
session to **Manual**, and it was retried once, verbatim.

**B: on MINIS.** Phase 0 (18:53 CEST): no reboot since 2026-09-27;
hash-first 9 of 9; netVM MainPID `88010`; the 2026-09-27 console present.
**R51 before** (19:01, on `2026-09-27T18:34:22Z`): `all` 0, and 2 on the
other 19 of 20 conf dirs, so the precondition held. The operator rebooted
(boot 19:12:42). With suspend masked and no `jbd2/dm-9-8`, `lvremove` at
19:24:06; the dev build ran 19:24:14–19:38:12 CEST, `rc=0`,
**`NETVM_BUILT=2026-09-28T17:38:12Z`**. **R52's preflight and R48's
read-back executed for the first time**, both on their pass paths. netVM
started at 19:39:06 on the static T1, which **held across the reboot**
(`10.3.1.172` by host ARP scan; one observation).

**Gates (the operator's rulings of 2026-09-28; the table is ADR-035's note
of that date):**
- **F12a PASS:** `nftables v1.1.3`, `nft -c` rc 0, `active`, the chain with
  sixteen `return`s and three counted drops.
- **F12b PASS**, every row: PC-1 5 of 5 ×4; row 1 R50 +10; 2a R50 +5; 2b
  rule 18 +10; **2c on the kernel martian witness** (`in_martian_src` +5,
  five `log_martians` lines on `km05`, R50 +0); row 3 R49 +5; row 4 R50 +10,
  its control +0; PC-2 5 of 5 ×4 on re-bound sockets. Every refusal row
  `answered=0`.
- **R51 held** before and after the rebuild.
- **Networking arc step 3a is done.** It closes the IPv4 half of finding 12
  only; the ARP half (#34) must land before the second networked AppVM
  (R54). **ADR-037 stays PROPOSED** (G5).

**Observed, each on one run and one image:** loose `rp_filter` passed every
forged IPv4 source except netVM's own address to nft, a segment source on
`uplink0` included (F's D18 recall item); `10.100.1.1` is a martian before
nft (now an Invariant); QEMU delivers to a re-bound `appvm` socket.

**Left on MINIS (B § 6):** § *Live state*, *NETVM ON THE STEP-3A IMAGE*.
netVM MainPID `49895` on the static T1; the console in `/run`, logged out;
stale `appvm` nodes on slots 02 and 05; `jbd2/dm-9-8` holds the LV, so **a
reboot is due before the next `netvm.sh`**. Suspend is unmasked. Session
files are in `/home/host/katmate-dev/f12/`.

**Not executed, and therefore not claimed (B § 6):**
- the failure paths of R52's preflight and R48's read-back on a real image
  (#50);
- the optional conntrack-shaped repeat of row 1 (not in the gate);
- the ARP half of finding 12 (#34), and IPv6 on `uplink0`;
- whether a failed `nftables.service` leaves forwarding open (#48);
- G5;
- the `km02`/`km05` link state after REMOVE, and netVM's neighbour entries
  for `.18` and `.21`;
- whether the vendor file `50-default.conf` is present on the new image
  (R57's premise is recorded as held on the observed values only).

`wp-0928b` ran on the Acer only and observed nothing on MINIS.

## Previous session (2026-09-28, f12-readpass and rulings) — the finding-12 candidate read against the tree, and the step-3a rulings R47–R56 recorded before any code

Two sessions, both on the Acer only. MINIS was not contacted.
`f12-readpass` read the finding-12 candidate ruleset against the tree before
networking arc step 3a. Its report is outside the repository:
`~/Claude.assistent/f12-readpass-report.md` (cited as F). `wp-0928a` wrote
the operator's rulings into `docs/DECISIONS.md` and this file.

**The read pass (F), in summary.** It found **twenty divergences, D1–D20**
(F § 2), and posed **ten questions, Q-F12a–Q-F12j** (F § 4). F's D-numbers
are its own. The central findings: the candidate was written against the
pre-ADR-037 ruleset, and its policy lines revert R2, R3 and R19 (D5–D8).
After a guard-only step, `rp_filter = 2` would still be inherited silently
from the vendor file, which ADR-036 § 3 rule 2 forbids (D15). ADR-036 § 3
makes G2's refusal half in both forms, IPv4 and ARP, the conformance test,
and nothing recorded whether step 4 may start with the ARP half open (D16).
`input` accepts, and `forward` passes to `uplink0`, any source in
`10.100.1.0/24` whatever interface it arrives on, `uplink0` included, and the
candidate closes that for the `/28` only (D18). The candidate's rule 18 drops
IPv6 on the slots incidentally, and does not say so (D19). The agent accepts
any `/24` peer on any slot, so a wrong pair would be dropped by the guard
silently (D20). Also: ADR-035's note of 2026-09-12 has eleven findings, and
finding 12 is the audit's (D1); ADR-036 § *Open* is stale on the sysctl
ordering (D17).

**The rulings, R47–R56 (index; the text is ADR-037's note of 2026-09-28,
and the gates are defined in ADR-035's note of the same date).** R47: the
guard lands on the ruleset in the tree, and only the chain is taken from the
candidate. R48: sixteen literal pairs, and a build read-back of them. R49: an
explicit IPv6 drop on the slots, and R22's role narrows. R50: segment sources
off their slot, over the `/24`, `lo` excluded; and the chain order. R51:
`rp_filter` adopted explicitly, read before and after the rebuild. R52: gate
F12a, and an `nft -c` build preflight. R53: gate F12b. R54: #34, the ARP
half, must land before the second networked AppVM, not the first. R55: the
agent-side pairing check at step 4 (#49). R56: where it is recorded; ADR-036
is not touched.

**wp-0928a's commits.** The previous-but-one entry rotated out (§ *Session
archive*, *Closed 2026-09-28*). ADR-037 gained the rulings note, and ADR-035
the gates note. In this file: § *Current focus*, #33, #34, new #48 and #49,
and networking arc steps 3a and 4.

**Not done, and not claimed.** Nothing was implemented, built or run. F12a
and F12b are untaken, and ADR-037 stays PROPOSED (G5). `rp_filter` is unread
on the current image (F D4); the last reading is of 2026-09-14, on the
2026-09-05 image. F's **[recall, unverified]** statements are still
unverified: that a rule with no L3 match in an `inet` table applies to IPv6;
how conntrack classes ICMPv6 neighbour and router traffic; whether loose
`rp_filter` passes an off-slot segment source on `uplink0`; and what `nft -c`
in a chroot measures. No ADR body was changed.

`f12-readpass` and `wp-0928a` ran on the Acer only and observed nothing on
MINIS.

## Previous session (2026-09-27, r8-impl A and B) — networking arc step 3 implemented in eight commits, netVM rebuilt on it, and G6 and G3's static half taken

Two sessions, one step. `r8-impl-A` took the two pre-code readings and wrote
the code on the Acer. `r8-impl-B` added R45, installed the host side on
MINIS, rebuilt netVM and took the gates. Both reports are outside the
repository: `~/Claude.assistent/r8-impl-A-report.md` (A) and
`~/Claude.assistent/r8-impl-B-report.md` (B). `wp-0927g` wrote the record.

**Step 0, the two readings (A; ADR-037's note on R41–R44).** R34: the guest
PCI enumeration from the host journal, 24 lines of one guest boot. The root
is at `03.0`, the RTL8125 at `04.0`, the sixteen slot NICs at `05`–`14`, and
nothing sits at `00:15`…`00:1e`, so `0x15` is free. R38: the packaged dhcpcd,
read from the Debian `.deb`s of the exact installed version
(`1:10.1.0-11+deb13u4`), not from the guest. The unit is in `dhcpcd`, the
hooks are in `dhcpcd-base`, and the resolv.conf hook is `20-resolv.conf`.
A's H3 reading, that `-f` on a file in `/run` needs no widening of the
packaged sandbox, was a reading of the documentation until B observed it.

**A: six commits, all `G`, pushed (`78a9008..ba11679`).** `e659db3` is the
ADR-037 note with R41–R44 and both readings. `00bab3c` gives `katmate-lib.sh`
a path-taking flat reader, `km_flat_read`, with `km_t1_read` as its wrapper
(R37). `283b825` gives `km_run_subdir` an optional mode (R32). `30b1708` adds
the builder, `katmate-build-cfgdisk` (R32, R33, R35–R37, R42–R44). `0996b70`
attaches the disk: an `ExecStartPre=+` line, and the drive/device pair at
`addr=0x15`, `serial=kmcfg`, `readonly=on` (R34). `ba11679` adds the guest
consumer, its oneshot and the `dhcpcd.service` drop-in with `-f
/run/katmate-cfg/dhcpcd.conf`, and the `netvm.sh` read-backs (R38). A's
first repository write was refused by the classifier. It stopped, and the
operator ruled that repository files are written with Edit/Write, never with
heredocs or redirections.

**B: two commits, both `G`, pushed (`ba11679..5bc028a`).** `8f6ebd5`
implements **R45**: every address the builder accepts is unicast, outside
`0.0.0.0/8`, `127.0.0.0/8`, `224.0.0.0/4` and `240.0.0.0/4`, and the
gateway's check runs before its in-prefix check. `5bc028a` is the ADR-037
note with R45, A's four additions accepted as rulings, and **R46**: B alone
could write under `/etc/katmate/vm/netvm.d/`, for the refusal fixtures and
the operator's static T1. R46 does not amend R25 for the product.

**B: install, the absent path, the refusals.** Hash-first, then the three
changed host files installed (9 of 9 equal to the tree at `5bc028a` from
20:02:35 CEST). netVM was restarted on the **old** image with no T1, the
absent path, before the rebuild (r8 § 4's hard ordering). The builder named
the absent path, the image was `c9a4e5e4…d406`, **equal to A's on the
Acer** (both GNU tar 1.35), QEMU accepted the argv, the disk appeared at
`00:15.0` as `vdb`, and the root stayed `vda`. Then the host refusals on
that image: R-b, R45 (gateway `224.0.0.1`), R-c (`wg0`), R42 mode, R42 owner
and a symlink were each refused before QEMU, with a valid T1 between them as
the positive control.

**B: the rebuild.** Stopped by a classifier refusal (a Write of the
post-reboot script); after the operator's reboot and ruling, the Write was
retried once, verbatim. `lvremove` at 20:19:45 CEST after the preconditions
(no `jbd2/dm-9-8`, `Open count: 0`); the dev build ran 20:20:19–20:34:22 CEST
as the transient `km-netvm-build`, `rc=0`, image
`NETVM_BUILT=2026-09-27T18:34:22Z`. Every read-back printed its pass line,
including the two new ones for the consumer and the drop-in.

**Gates, all 2026-09-27; the table is ADR-037's note on the step-3 gates:**
- **G6 PASS**, pass half: the builder names `uplink`, image `e960fadc…ea1c`,
  and the guest consumer logs the same sha256; R-a (absent: DHCP lease), R-b,
  R-c and R-d (`ro=1`) PASS.
- **G3's static half PASS:** `10.3.1.172/24` on `uplink0`, the default route
  via `10.3.1.1`, `nameserver 10.3.1.1`, and the host's ARP scan finds it.
  Refusal: **0 DHCP packets** captured across the static boot, against a
  positive control of 1; no lease newer than boot; no soliciting dhcpcd line.
- Settled with them: r8 D13 (the static nameserver reaches `resolv.conf`)
  and A's H3 reading (dhcpcd runs with `-f` under the packaged sandbox).
- **ADR-037 stays PROPOSED.** G5 is untaken.

**B's two faults, as recorded.**
- **A command file opened a pager on the serial console.** `g5.cmd` ran
  `systemctl show` without `--no-pager`, `less` consumed the rest of the
  file as keystrokes, and recovery took `q`, `q` and a newline. B read the
  console journal for side effects before recovering: none on disk. Now an
  Invariant.
- **The host-dnsmasq watcher's `pgrep -af dnsmasq` fired on
  `systemctl enable dnsmasq`**, the build's own command line, not a daemon.
  The `/proc/*/comm` count read 0 and decided. Now an Invariant.

**Left on MINIS (B § 6).** netVM runs on the static T1, MainPID `88010`, and
`/etc/katmate/vm/netvm.d/uplink` **stays** (§ *Live state*, *NETVM ON THE
STEP-3 IMAGE*). The console is present in `/run` and logged out. The new LV
holds `jbd2/dm-9-8`, so **a reboot is due before the next `netvm.sh`**.
Suspend is unmasked. The installed set equals the tree at `5bc028a`. The
LAN's DHCP server may still hold `10.3.1.103`. Session scaffolding is in
`/home/host/katmate-dev/r8-impl-B/`.

**Not executed, and therefore not claimed (B § 6):**
- the builder's `trap` cleanup and stale-file sweep; the directory-level
  refusals, an unknown or missing key and a leading-zero octet, as installed;
  every failure path of the guest consumer on a real image (#46);
- `ExecStop=/usr/sbin/dhcpcd -x` without `-f` (QEMU is stopped by signal);
- whether the static T1 survives a host reboot;
- G5, networking arc steps 3a, 4 and 5, IPv6 and router solicitation on the
  uplink (`ipv4only`), and R29's premise;
- `EXT4-fs (vda): recovery complete` on the restarted old image, and the
  guest's partition-scan messages on `vdb`: recorded, not examined.

`wp-0927g` ran on the Acer only and observed nothing on MINIS.

## Previous session (2026-09-27, r8-readpass, wp-0927e and rulings) — the stale lines after the implementation corrected, the tree read against R7/R8, and the step-3 rulings R30–R40 recorded before any code

Three sessions, all on the Acer only. MINIS was not contacted. `wp-0927e`
corrected the lines the implementation left stale. `r8-readpass` read the
tree against ADR-037 R7 and R8 before arc step 3. Its report is outside the
repository: `~/Claude.assistent/r8-readpass-report.md` (cited as r8).
`wp-0927f` wrote the operator's rulings on both into `docs/DECISIONS.md`,
`docs/HOST-CONFIG.md`, `ROADMAP.md` and this file.

**wp-0927e, in one paragraph.** Four commits, `fb6be86`…`95acef4`, pushed.
`docs/ARCHITECTURE.md` § *Networking*'s uplink bullet now says the uplink is
`uplink0` by `Path=` on the pinned slot, held by dhcpcd (`fb6be86`). ADR-021
and ADR-025 gained notes recording the uplink retirements that landed
(`f9a8da1`). Dated notes went into this file (§ *Current focus*, the
WireGuard/DNS line in § *Live state*, and two § *Next steps* items;
`79f218b`) and into `ROADMAP.md` (`95acef4`). ADR-037 § *Status* was left
alone, and a note line for it was proposed.

**The read pass (r8), in summary.** It found **fourteen divergences, D1–D14**
(r8 § 2), and posed **nine questions, Q-R8a–Q-R8i**, that the implementation
cannot start without (r8 § 3). r8's D-numbers are its own and are not rp's.
The central findings: R8's `/etc/katmate/netvm/` is the per-VM-directory shape
ADR-032 § 1 rejects, and its key is unstated (D1, D2); nobody had said who
builds the disk, where, or in which tier (D3); G6's refusal half is a
fallback, and its pass half describes copy-through (D4, D5); "the disk
absent" cannot be expressed in the fixed argv (D7); the config disk does not
make G1 discriminate (D8); "step 3b" already names the launch daemon (D9);
and R30 contradicts R20's scheduling (D11). r8 § 4 proposed a commit
sequence.

**The rulings, R30–R40 (index; the text is ADR-037's note on the step-3
rulings).** R30: arc step 3 is the config disk and the static uplink, and VPN
mode is arc step 5 under its own ADR. R31: the T1 location is
`/etc/katmate/vm/<instance>.d/` (recorded in ADR-032's note of the same date).
R32: a T4 builder after `katmate-generate-env`, writing
`/run/katmate/cfgdisk/<instance>.img`. R33: a `ustar` image. R34: the argv,
and the PCI reading before code. R35: parse and re-emit. R36: absent versus
malformed. R37: the schema. R38: the guest consumer. R39: the gates. R40: G1
stays non-discriminating. The sequence is r8 § 4's, with one hard ordering
constraint (§ *Next steps*, arc step 3).

**The rulings on wp-0927e.** The ADR-037 § *Status* note line it proposed is
accepted, and is written in ADR-037's note on the step-3 rulings. The sshd
item in § *Next steps* stays: it is #4's while the dev host's sshd exists. The
extra bullet in the ADR-025 note stays.

**wp-0927f's commits.** The previous-but-one entry rotated out (§ *Session
archive*, the fifth closure of 2026-09-27). ADR-037 and ADR-032 gained notes,
HOST-CONFIG § 12 a dated note, and `ROADMAP.md` step 4 a dated note. In this
file: #40, arc step 3, a new arc step 5, the WireGuard item's "step 3", and
the § *Live state* `20-uplink.network` line.

**Not done, and not claimed.** Nothing was implemented, built or run. No
gate was taken, and ADR-037 stays PROPOSED. The two pre-code readings (R34's
PCI enumeration, R38's `dhcpcd.service` and hooks) are untaken. r8's
**[recall, unverified]** statements about QEMU slot placement, `ustar`
reproducibility and dhcpcd's static `resolv.conf` (D13) are still
unverified. `build/netvm.sh:207-208`'s *"ONLY author"* sentence (D10) is
unqualified, and waits for the consumer commit. No ADR body was changed.

## Previous session (2026-09-27, adr037-impl A and B) — ADR-037 implemented in nine commits, netVM rebuilt on it, and G1–G4 taken

Two sessions, one arc. `adr037-impl-A` wrote the code on the Acer, did not
build it and did not push it. `adr037-impl-B` installed the host side on MINIS,
rebuilt netVM, took G1–G4 and pushed A's commits. Both reports are outside the
repository: `~/Claude.assistent/adr037-impl-A-report.md` (A) and
`~/Claude.assistent/adr037-impl-B-report.md` (B). `wp-0927d` wrote the record.

**A: nine commits, all `G`.** `6827583` bakes the conf tree `root:root` and
reads the ownership back (#38). `a209ebf` sets `nftables.conf` to mode 0644
(R23). `098e868` makes the agent unit a tracked file in the conf tree (#27,
R24, R15). `8391bb3` pins `addr=0x4` on `vfio-pci` (R4, R10, R11). `0f304c9`
adds `60-katmate-uplink.link` on `Path=`, the 17-file `.link` build gate and
`UPLINK_PCI_ADDR` (R3, R12, R13). `bb1481a` replaces systemd-networkd with
dhcpcd on the uplink (R6, R14–R16, R29). `8f388d4` adds dnsmasq on the slots
only (R5, R17, R18, R29). `7550734` sends vanilla egress through `uplink0`,
with the return path by conntrack only (R2, R19, R22). `c37f9d1` retires the
ProtonVPN template (R20). A halted once before its first commit, on V1 and V2
(both ruled, below). Its build-time refusals ran against fixtures only.

**B: installation.** Hash-first before any change compared 8 files and found
2 expected differences (`katmate-generate-env`, the unit) and 0 others. **The
whole tracked host set was re-installed from the tree at `c37f9d1`**, 6
`/usr/lib/katmate/*` files and both units: 8 of 8 sha256-verified,
`root:root`, git modes. From 14:22:49 CEST hash-first is clean. netVM was
restarted on the new unit, and G1 was taken on the old image.

**B: the rebuild.** After the operator's reboot and with suspend masked,
`lvremove -y vg0/vm_sys_netvm` ran at 14:45:35 CEST. The dev build (R27) ran
14:47:06–15:01:13 CEST as the transient unit `km-netvm-build` (launch form
below), `netvm.sh rc=0`. Every build read-back printed its pass line, among
them `34 conf-tree paths … all owned 0:0`, `24 baked conf-tree files, none
names 'proton'` and `Build gate OK: 17 katmate .link files`. No host dnsmasq
appeared at either watcher probe. Image: `NETVM_BUILT=2026-09-27T13:01:13Z`,
kernel `6.12.107+deb13-amd64`. netVM was started on it at 15:03:39 CEST
(MainPID 50080) with a per-session console.

**Gates, all 2026-09-27; the full table is ADR-037's implementation note:**
- **G1 PASS:** argv `addr=0x4`, and the RTL8125 at guest `00:04.0`. It does
  not discriminate cause (R11).
- **G2 PASS:** `ID_NET_LINK_FILE=…/60-katmate-uplink.link`, exactly one
  `uplink0`, and 16 slots on 16 distinct `.link` files.
- **G3 DHCP half PASS:** dhcpcd active, no dbus daemon, `resolv.conf` written
  in place, lease `10.3.1.103`. **Refusal half PASS, as ruled** (scope below).
  The static half waits for arc step 3.
- **G4 PASS:** a fixture peer on slot 05 got 4 A records from `10.100.1.1`.
  **Refusal half PASS**, and it does not discriminate cause (the `input`
  chain drops the LAN query before dnsmasq is reached).
- Not a gate: an ICMP echo from the fixture to `1.1.1.1` was answered, so
  egress and masquerade out `uplink0` work for a pool-sourced packet. G5 still
  needs an AppVM.

**Operator rulings of 2026-09-27, recorded as rulings:**
- **R29** (A's V2): netVM's `/etc/resolv.conf` is baked as an empty
  `root:root 0644` file, and a tracked `/etc/default/dnsmasq` sets
  `DNSMASQ_EXCEPT="lo"`. The full text is in ADR-037's implementation note.
- **V1:** `libdbus-1-3` is an accepted cost, a library with no bus. The build
  refuses `enable-dbus`.
- **G3's refusal half is scoped to dhcpcd-originated state.** R14's wording,
  *"anything NETCFG did not program"*, was an overreach. The kernel's IPv6
  link-local on a raised slot is a separate finding, #45.
- **B § 0.1, items 1–7:** (1) the `katmate-generate-env` mismatch was
  expected, and the whole tracked set was re-installed, which closes
  *Installed vs tree, 2026-08-22*; (2) the silent `resolv.conf` read-back is
  settled by G3's in-guest `stat`; (3) the three host units to read are
  `katmate-sys-driver@netvm`, `katmate-publish-nics` and `km-console-holder`;
  (4) the host dnsmasq watch probes at the *Baking netVM config tree* line and
  at build exit, and a hit is recorded, not killed; (5) a root wrapper reads
  the dev root hash from a `0:0 0600` file into the environment, with no
  `set -x`; (6) G1 by the guest journal before the rebuild, plus sysfs after
  it; (7) G4's refusal half is recorded as not discriminating cause.
- **Launch form:** a netVM build runs as a transient `systemd-run` unit, so an
  ssh drop cannot kill it (§ *Live state*, *Dev access to MINIS*).
- **Permission mode, as done in B, not a new rule:** after a classifier
  refusal B was switched from auto to Manual for the rest of that session,
  and the refused call was retried once, verbatim, on the operator's
  instruction. **The standing rule stays auto plus stop-report-wait.**

**Left on MINIS (B § 6).** netVM is running (MainPID 50080). The console is
logged out, with its drop-in, FIFO and holder in `/run`. Slot 05 holds a dead
`appvm` socket node from the G4 fixture. `km02` and `km05` are UP with IPv6
link-locals only (#45). Suspend is unmasked. The new LV holds `jbd2/dm-8-8`,
so **a reboot is due before the next `netvm.sh`**, as always.

**Not executed, and therefore not claimed:**
- G5, G6, and G3's static half;
- the refusal half of the `NETVM_UPLINK_PCI_ADDR` preflight;
- dhcpcd without the empty `resolv.conf` (R29's premise);
- router solicitation on the uplink (`ipv4only`);
- whether the LAN DHCP server received netVM's hostname;
- whether the LV's live `jbd2` thread at boot affects the guest filesystem
  (no fsck was taken);
- the removal of the `/run` scaffolding by a reboot.

The agent binary was baked as-is (mtime 2026-07-23), consistent with its
source by mtime only (#14). `wp-0927d` ran on the Acer only and observed
nothing on MINIS.

## Previous session (2026-09-27, adr037-readpass and rulings) — the tree read against ADR-037, and the operator's rulings R10–R28 recorded before any code

Two sessions, both on the Acer only. MINIS was not contacted. `adr037-readpass`
read the tree against ADR-037 before the netVM rebuild. Its report is outside
the repository: `~/Claude.assistent/adr037-readpass-report.md` (cited as rp).
`wp-0927c` wrote the rulings on it into `docs/DECISIONS.md` and this file.

**The read pass (rp), in summary.** It mapped every file that R2–R7, #38 and
#27 touch (rp § 1) and found **fourteen divergences, D1–D14**, none of them
resolved by the pass (rp § 2). The pool unit named in ADR-037 § *Carried* is
already folded (D1). R3 reverses statements its cross-reference does not name
(D2). Nothing keeps dhcpcd off the slots (D3). ADR-037's Status points at
`state.md` for rulings that live in `docs/SESSIONS.md` (D4). G3's static half
cannot be taken on the step-2 build (D6). G1 cannot tell the pin from today's
auto-placement (D7). ADR-035's rename build gate does not exist in the tree
(D8). ADR-021's write grant and `MODULES=dep` are stale (D10, D13). Two
published statements say WireGuard terminates in netVM, and net-up read none
(D11). The pass also asked the questions the implementation cannot start
without (rp § 3), stated the readiness of gates G1–G4 with a proposed refusal
half for each (rp § 4), and proposed a commit sequence (rp § 5). Every
component behaviour it states from general knowledge is marked **[recall,
unverified]** there, and none of those statements was measured.

**Operator rulings of 2026-09-27 on the read pass, R10–R28.** The full text,
with each ruling's rp reference, is ADR-037's revision note of 2026-09-27. This
list is the index, not a second copy:

- **R10:** `vfio-pci` gets `addr=0x4`, and the unit gets comment (6).
- **R11:** G1 is accepted as not discriminating cause. Every new device in the
  netVM unit carries an explicit `addr=`.
- **R12:** the uplink `.link` is `60-katmate-uplink.link`, and ADR-035's rename
  build gate lands in this rebuild as a file check on 17 `.link` files.
- **R13:** `netvm.meta` records `UPLINK_PCI_ADDR`. The preflight that compares
  it with the unit is open problem #44.
- **R14:** dhcpcd gets `allowinterfaces uplink0`, `noipv4ll` and `ipv4only`,
  and G3 gains a refusal half on `km*`.
- **R15:** systemd-networkd is disabled in netVM. The agent unit drops its
  `Wants=`/`After=` on it.
- **R16:** the dhcpcd package form is whichever pulls in no dbus, measured in
  the chroot and after the build.
- **R17:** dnsmasq runs in its default wildcard mode, with `interface=km*`,
  `except-interface=uplink0`, and DNS only.
- **R18:** `/etc/resolv.conf` never points at loopback. Clear-text upstream DNS
  is accepted for vanilla.
- **R19:** there is no explicit reverse forward rule, and `udp dport 51820` is
  removed.
- **R20:** `wireguard-tools` stays and `proton.conf.template` goes. Nothing
  baked in this rebuild references `proton`.
- **R21:** the finding-12 slot guard is not in this rebuild. It lands before arc
  step 4, as its own step.
- **R22:** no `icmpv6` accept is added. Its absence is load-bearing for #24
  (*Invariants*).
- **R23:** `nftables.conf` becomes `0644` in its own commit, and `root:root` is
  fixed in `netvm.sh` step 5 (#38).
- **R24:** the agent unit moves into `manifests/netvm.conf.d/`, and step 7's
  heredoc goes (#27).
- **R25:** G3 is split. The DHCP half is taken at step 2 and the static half at
  step 3. There is no fixture path for T1.
- **R26:** G4 is taken with a fixture peer in `~/katmate-dev/`, and gains a LAN
  refusal half.
- **R27:** the rebuild is a dev build.
- **R28:** the rulings are recorded before code. D5 and D8–D14, apart from D13,
  wait for the write pass after the rebuild.

**Carried rulings (operator, 2026-09-27; rp § 6):**

- The token that was in `~/code_auth_token.txt` was rotated several times, so
  it is **obsolete**. No revocation is needed. The notes are on the
  host-cleanup entry below and on #42.
- `/home/host/hcb-d.sh` was **deleted by the operator**. #42 closes.
- SECURITY-MODEL **gap 3 stands for the product**. The host's `proton` link is
  **dev scaffolding**, on the pre-release removal list beside the dev sshd
  (#4). The gap's note of 2026-09-27 records it.

**Permission mode (operator ruling, 2026-09-27):** sessions run in **auto
mode**. When the classifier refuses a command, the agent stops, reports the
exact command, and waits for the operator to allow it. It never retries the
same thing in another command form. This supersedes the Manual-mode rule of
2026-09-26 (§ *Live state*, *Dev access to MINIS*).

**Ruled in-session (wp-0927c):** rp D2 also lists `docs/ARCHITECTURE.md:76`
(*"Core stack: systemd, systemd-networkd/-resolved, …"*) as reversed by R3.
That line is under `## Host`, so it describes the host's stack, and R3/R6
change only netVM. The operator ruled that ADR-037's note omits it.

**Written (wp-0927c):** the pool-fold entry rotated to `docs/SESSIONS.md`.
ADR-037 has a revision note (R10–R28, D1, D4, and D2's extended
cross-reference), and ADR-021 has one (D2, D10, D13). In this file: this entry,
the permission-mode note, #42 closed, #44 added, the arc step-2 note and the
finding-12 step, and two invariant notes. SECURITY-MODEL gap 3 has a note.

**Not done, and not claimed.** Nothing was implemented, built or run.
`netvm.sh`, the units and the manifests are unchanged. Every gate of ADR-037
is untaken. rp's **[recall, unverified]** statements about dhcpcd, dnsmasq and
QEMU are still unverified, and R14, R16 and R17 are rulings on them, not
measurements of them. `docs/ARCHITECTURE.md` still says WireGuard terminates in
netVM (D11). It waits with D5, D8, D9, D11, D12 and D14.

## Previous session (2026-09-27, host-cleanup) — MINIS dev leftovers retired, networkd now manages no link, and HOST-CONFIG §1 re-measured

One session, on MINIS and the Acer. Report outside the repository:
`~/Claude.assistent/hostclean-0927-report.md` (cited as hc). It halted once
before contacting MINIS, because it was not in Manual mode. The operator switched
modes and resumed it.

**Operator rulings of 2026-09-27**, recorded as rulings:

- **MINIS is a dev machine.** Leftovers from the early project and from
  personalVM go. The operator confirms from memory that `tap-outer` and `tap0`
  were his early experiments.
- **Anything found beyond the authorised list is reported, never touched.**
  The operator decides it in chat. The list is open problem #42.
- **HOST-CONFIG §1 is rewritten once**, from the measurement taken after the
  clean-up, and not before.
- **R5 reference (ruled in-session):** the pf scripts' Acer copies are the
  files fetched back from MINIS into `~/Claude.assistent/pool-fold/`, verified
  against the sha256 values `pool-fold-report.md` records. All four matched. The
  report's listing of `pf-c3.sh` differs from the executed file by one trailing
  space (hc § 2). The old report is not edited.

**Removed, 11:39:12–11:39:27 CEST, by one script** (`hc-r.sh`, `f39e648c…`).
Before the first mutation it re-checked every identity pinned by the read-only
inventory at 11:36:56: file hashes, netVM MainPID and invocation, the
waypipe-client PID, and `vm_tpl_foundation_pre0926` = `dm-8`. It re-checked the
pins again after each phase. **Moved** to `~/katmate-dev/removed-0927b/` on
MINIS, each `cmp`- or `diff -r`-identical to a pre-move copy:

- the ten networkd files of `br-personal`, `tap0`, `tap-outer`,
  `tap-personal` and `tap-work`;
- the user units `personal-vm.service` and `work-vm.service`, and
  `netVM.service.d/` (holding only `memlock.conf`). No `*.wants/` symlink pointed
  at any of them;
- `/var/lib/katmate/foundation.meta.pre0926`, `/var/lib/katmate/kernels.pre0926/`
  and `~/katmate-build/out/vm-agent.pre0926`.

`networkctl reload` exited 0. `ip link delete` exited 0 on the four taps and then on
`br-personal`, and all five now answer *Device "…" does not exist.* After
`systemctl --user daemon-reload` all three units are `not-found`. **Deleted:**
`instances/test_web.qcow2.pre0926`; the LVs `vm_app_web_pre0926`,
`vm_app_vault_pre0926` (both inactive, with no dm device) and then
`vm_tpl_foundation_pre0926` (open 0, no `jbd2/dm-8-*`, no origin-user left),
each `lvremove` exiting 0 without `-f`; `instances/scratch.qcow2` (#26); and the
six dev scripts `pf-a.sh`, `pf-c2.sh`, `pf-c3.sh`, `pf-c4b.sh`, `pm-m1.sh` and
`pm-m23.sh`, each hash-matched first. `vm_pool` data went from 0.96 % to
0.42 %.

**scratch.qcow2, as it was** (the only record): qcow2, virtual 20 GiB, 844 MiB
on disk, `backing file: /dev/vg0/vm_app_web`, format raw, `corrupt: false`,
mtime 2026-07-29 19:30:11, `host:host`, `e32466b9…`. No process held it.
**Its backing name resolved to the `vm_app_web` rebuilt on 2026-09-26**, two
months after the delta's mtime, so the layer it named was no longer the one it
was written on. A 4 GiB `scratch_home.img` beside it (2026-07-30) was not
authorised and remains (#42).

**Undisturbed, observed after every phase:** netVM
`katmate-sys-driver@netvm.service` `active`, MainPID **11761**, invocation
**`f1a996dd…`**, `NRestarts=0`; `ping-client ping 3` → `status=0x00 (OK)`;
`waypipe-client` `active`, MainPID **1592** before and after.

**HOST-CONFIG §1 re-measured (11:39:39, read-only):** `networkctl list` shows
three links, all `unmanaged`: `lo`, `enp195s0f3u1u1` (routable) and `proton`
(wireguard, routable). **networkd manages no link.** `/etc/systemd/network/` is
empty. `networkctl status`: `State: routable`, `Online state: unknown`.
`network-online.target` and `systemd-networkd-wait-online.service` (enabled)
are both `inactive (dead)`. **A direct probe,
`/usr/lib/systemd/systemd-networkd-wait-online --timeout=15`, printed *"Timeout
occurred while waiting for network connectivity."* and exited 1 after 15.2 s.**

**Neither unit has run this boot (10:30:08).** Every Active/Inactive
timestamp is empty, and `journalctl -b` for both units has no entries. The only
reverse dependency of `network-online.target` is
`archlinux-keyring-wkd-sync.service`. So this boot says nothing about how
wait-online behaved with the taps present. **No pre-removal probe was taken**,
so the probe's timeout cannot be attributed to the removal (hc § 5).

**Not executed, therefore not claimed.** What wait-online does as a *unit* at
the next boot or the next `archlinux-keyring-wkd-sync` run is **UNVERIFIED**. It
is settled by `systemctl show -p ActiveState,Result,ActiveEnterTimestamp
network-online.target systemd-networkd-wait-online.service` and `journalctl -b
-u systemd-networkd-wait-online` after something has pulled the target in.
`vm-agent.pre0926` was pinned by size and mtime, not by hash, because Phase I
listed `out/` by name only. Nothing in `removed-0927b/` has been used for a
restore.

**Continuation, the same day — the #42 queue deleted, as ruled
(`hostclean-0927b`).** The report is outside the repository:
`~/Claude.assistent/hostclean-0927b-report.md` (cited as hcb). **It halted twice
on H1.** The first halt was before any MINIS contact, because the mode was
unconfirmed. The second came between the read-only Phase P and the deletion,
when a system notice said auto mode was active. The operator re-confirmed
Manual both times.

**Operator rulings of 2026-09-27**, recorded as rulings:

- **The #42 queue was reviewed by the operator, and the listed items go.
  They are deleted, not archived.** The record of what was deleted is hcb
  Appendix D: path, size and sha256 for each file, and `du -sb` and file count
  for each directory.
- **`/etc/udev/rules.d/99-vm-lvm.rules` stays for now.** It is a security
  finding and not a leftover: SECURITY-MODEL gap 16 and open problem #43.
- **`~/.katmate-netvm-pass` holds a credential that was already rotated.** It
  is deleted.
- **`~/code_auth_token.txt` is unknown to the operator.** It is deleted, after
  its issuer was identified (below). Deleting the file does not revoke the
  token. **[Note 2026-09-27 (operator ruling): the token was rotated several
  times and is obsolete. No revocation is needed.]**
- **`host_lan_up.sh` and `proton-wg-up.sh` are KEPT.** They bring up the host
  uplink and the `proton` link, and may be the operator's manual post-boot step
  that HOST-CONFIG §2 (`[OPEN]`) implies. They retire when §2 lands, not before.
- **Pins:** a hash wherever a record had one: hc Appendix A;
  `adr034-pregate-report.md` § 5 for the `.bak`; the Acer copies of
  `hc-r.sh`, `hc-s.sh` and `hc-s2.sh`. Otherwise size, owner and mtime.
  `hcb-p.sh`, the Phase P script, was added to the list, pinned by its Acer
  hash.
- **This session continues this entry.** There is no new heading and no
  rotation.

**Phase P (12:11:40–12:11:50, read-only).** The pins were unchanged: netVM
MainPID 11761, invocation `f1a996dd…`, `NRestarts=0`, and waypipe-client
MainPID 1592. No process held any listed path. Compared with the Acer pins, all
39 Appendix A hashes and all 4 other-record hashes matched. The 50 unhashed
files matched in size and owner (hcb § 0 execution log).

- **P1, `vm-lvs.service`:** `disabled`, `inactive (dead)`, `Type=oneshot`. It
  has no `ExecMainStartTimestamp`, no journal entry this boot, and no
  `*.wants/` symlink. It runs `lvchange -ay -K` on `vg0/vm_personal_rw` and
  `vg0/vm_personal_home`, then `dmsetup mknodes` and `udevadm settle`. **Neither
  LV exists.** `~/vm-lvs.service` was an earlier draft that differs in one line
  (`vm_personal` instead of `vm_personal_rw`). The unit is **ruled out** as the
  cause of `vm_tpl_foundation` being active without `k` (*Invariants*,
  thin-LV activation).
- **P2, `~/katmate-os/`:** **no `.git`.** It held `agent/`, `app_web.con`
  (2026-07-23) and `init/`: 5 files, 945278 B. It was not a clone, so H3 could
  not arise.
- **P3, `~/code_auth_token.txt`:** 109 bytes, one line of 108 characters. The
  prefix is Anthropic's `sk-ant-o…`, the OAuth form, and the length fits a
  Claude Code `setup-token` token. **The issuer is identified by prefix and
  length only.** Revocation is the operator's step, at the issuing claude.ai
  account. mtime 2026-06-15 18:09. **[Note 2026-09-27 (operator ruling): the
  token was rotated several times and is obsolete. No revocation is
  needed.]**
- **The kept scripts, verbatim.** `host_lan_up.sh` (140 B, 2026-07-06):

  ```
  # run as root
  ip link set enp195s0f3u1u1 up
  ip addr add 10.3.1.3/24 dev enp195s0f3u1u1
  ip route add default via 10.3.1.1 dev enp195s0f3u1u1
  ```

  `proton-wg-up.sh` (206 B, 2026-03-07) runs `wg-quick up proton`, after a
  vestigial `ip link add dev tun.proton type wireguard` (full text in hcb). The
  only reference to either name is `~/.local/share/fish/fish_history`.
- **Read and kept, as the brief listed:**
  - `vms/` holds only `ovmf/personal_VARS.fd` (540672 B), a personalVM UEFI
    vars file.
  - `iso/` holds only `debian-13.3.0-amd64-netinst.iso`.
  - `acer/` holds four files, 2961 B.
  - `arch-cache/` holds 425 files, 637 MB of `.pkg.tar.zst`.

**Deleted, 12:37:26–12:37:40 CEST, by one script** (`hcb-d.sh`, `5d783a98…`).
It re-checked every pin before the first deletion and the netVM and
waypipe-client pins after each group. No `rm -f` was used, and no glob in any
deletion path. Nothing mismatched and nothing was left in place.

- **92 files:**
  - the #42 dev scripts, prototypes, logs, captures and personalVM launchers
    at `~`;
  - `config-katmate-3flags.bak`;
  - `.katmate-netvm-pass` and `code_auth_token.txt`;
  - `hc-i.sh`, `hc-r.sh`, `hc-s.sh`, `hc-s2.sh` and `hcb-p.sh`;
  - `~/vm-lvs.service` and `/etc/systemd/system/vm-lvs.service`. That unit
    was not enabled, so no `disable` was issued. `daemon-reload` exit 0, and
    the unit is now `not-found`;
  - `/var/lib/katmate/instances/scratch_home.img` (4 GiB, `681f4b58…`);
  - `~/.config/systemd/user/waypipe-client.socket`.
- **2 symlinks:** the two dangling `waypipe-client@1024.service`, followed by
  `systemctl --user daemon-reload` (exit 0).
- **4 directories:**
  - `gate-stage/`;
  - `personal_boot/` (49 MB);
  - `katmate-os/`;
  - `src/kernel/linux-6.12.94/` (2278703639 B, 97751 files).

**After:** netVM `active`, MainPID 11761, invocation `f1a996dd…`,
`NRestarts=0`. waypipe-client `active`, MainPID 1592. `ping-client ping 3`
returned `status=0x00 (OK)`. `list-unit-files 'waypipe*'` shows only
`waypipe-client.service enabled`, and its `default.target.wants` symlink
remains. `src/kernel/` now holds only `linux-6.12.y`. `instances/` holds only
`test_web.qcow2`.

**Left, and why:**
- `host_lan_up.sh` and `proton-wg-up.sh` (ruling, above).
- `99-vm-lvm.rules` (gap 16, #43).
- `~/katmate-dev/` and `~/katmate-build/out/netvm/` (keep-listed).
- `~/hcb-d.sh` itself (18524 B). It was not on the list and goes at the next
  clean-up.

**Not executed, therefore not claimed.** No revocation of the token was
attempted. Whether anything reads `~/vm-lvs.service` or the deleted launchers at
the next boot was not traced beyond the grep for the two kept scripts. The
closing line of `hcb-d.sh` lists the four directories as *"SKIPPED"*. That line
is **wrong**, a defect in the script's pin table (hcb, execution log). The
check above it found none of them present.

## Previous session (2026-09-27, pool-fold) — the slot pool folded into the shipped sys-driver unit, netVM started under it with no console, and host-side `tap-int0` retired

Two sessions. `pool-fold` ran on the Acer and MINIS, and `wp-0927` retired
`tap-int0` on MINIS and wrote this up on the Acer. Reports outside the
repository: `~/Claude.assistent/pool-fold-report.md` (cited as pf) and
`~/Claude.assistent/wp-0927-report.md`.

**Two halts, both resolved by the operator.** (1) Before any MINIS contact the
session was in auto mode; the operator switched to Manual. (2) At A6, the diff
of the repository unit against the pool unit held one hunk outside the
expected transplant: the generator argument, `%p` against the pool's literal
`katmate-sys-driver`. **Ruling:** the unit keeps
`katmate-generate-env %p %i`. G1 of 2026-08-19 had already observed that line
pass the generator's profile assertion, and the pool's literal was needed only
because `%p` expands to `katmate-pool` there. The same ruling fixed the reboot
time at 10:30:45 (pf, top and § 2.3).

**The fold (option (b) of #39).** C1 `a36bdb2` transplants the ADR-035 slot
pool into `katmate-sys-driver@.service`: sixteen `dgram` netdevs and
`virtio-net-pci` devices replace the `int0` tap, and `RuntimeDirectory=` names
the sixteen slot directories, with `RuntimeDirectoryPreserve=yes`. C2
`70b08c7` adds the R9 comment on the per-session dev drop-in (pf § 1).
Installed on MINIS as `a378f875…`, 14463 B. The pool unit
(`1d727b25…`) and the pre-fold sys-driver unit (`813f27c8…`) were saved to
`~/katmate-dev/removed-0927/`, `root:root`, and `katmate-pool@netvm` is now
`not-found` (pf § 2.5).

**netVM started under the shipped unit** at **10:50:33 CEST**: MainPID
**11761**, invocation **`f1a996dd…d943`**, `NRestarts=0`, all three
`ExecStartPre=` `status=0` — which re-observes the `%p` line —
`StandardInput=null`, and empty `DropInPaths=` (pf § 2.6).

**Both halves of the `208/STDIN` UNVERIFIED are settled.** For the boot half,
after the 10:30:45 boot neither unit carried a drop-in and both read
`StandardInput=null` (pf § 2.1, A2). For the start half, the folded unit
started with `/run/katmate-dev/` absent and no drop-in anywhere (pf § 2.6, C3).

**C4 readings** (pf § 2.8): 16 `dgram` netdevs and 16 `virtio-net-pci`
devices in the argv, 0 `tap,`, 0 `tap-int0`. 16 slot directories, all
`drwxr-xr-x root:root`. `ping-client ping 3` answered `status=0x00 (OK)` on
attempt 3. 16 renames to `km00`…`km0f`, 16 distinct, 0 duplicates. **The
binding reading first said 0/16, then 16/16.** `Type=simple` returns from
`start` when QEMU forks, and the first script snapshotted QEMU's fds before
QEMU had bound its netdevs. A re-take 26 s later read 16/16: socket inodes
40491–40506 held by fds 15–30 of 11761, with the same inodes for 08–0f as the
first reading (pf §§ 2.6, 2.7). This is now an *Invariants* entry.

**Phase M — host-side `tap-int0` retired (wp-0927, authorised).** Before
(11:02:19): MainPID 11761, invocation `f1a996dd…`, `NRestarts=0`. `tap-int0`
was `NO-CARRIER`, `tun type tap … persist on`. The argv held 0 `tap-int0` and
0 `tap,`. The host had 0 `/dev/net/tun` fds open, so nothing held it. The
script (11:07:10) re-checked the pinned MainPID, invocation and file hashes,
then moved `tap-int0.netdev` (`e0ff450d…`) and `tap-int0.network`
(`1d8f66a0…`) to `~/katmate-dev/removed-0927/`, `cmp`-identical to pre-move
copies. It then ran `networkctl reload` (exit 0) and `ip link delete tap-int0`
(exit 0). After: `ip link show tap-int0` gave *Device "tap-int0" does not
exist.* (exit 1), `networkctl list` no longer lists it, the unit is still
`active` with **the same MainPID and invocation** and `NRestarts=0`, and
`ping-client ping 3` answered `status=0x00 (OK)`. The auto-mode classifier
refused this session's first attempt before execution. It ran in Manual
mode, as the rule in § *Live state*, *Dev access to MINIS*, requires.

**Finding, not a change — host-side networkd config left over from
personalVM / the pre-sysVM layout, not removed.** The operator ruled the
other links out of scope. A read-only listing of `/etc/systemd/network/`
after Phase M:

| File | Size | mtime | sha256 (prefix) |
|---|---|---|---|
| `br-personal.netdev` | 38 B | 2026-03-12 15:13:59 | `7cc41284…` |
| `br-personal.network` | 104 B | 2026-08-02 17:41:19 | `2dacd33a…` |
| `tap0.netdev` | 45 B | 2026-03-08 13:35:27 | `77ad9900…` |
| `tap0.network` | 77 B | 2026-08-02 17:41:19 | `9ad82940…` |
| `tap-outer.netdev` | 50 B | 2026-03-08 13:39:29 | `c99c91db…` |
| `tap-outer.network` | 102 B | 2026-08-02 17:41:19 | `3b1be5aa…` |
| `tap-personal.netdev` | 53 B | 2026-03-08 13:38:33 | `046c3261…` |
| `tap-personal.network` | 85 B | 2026-08-02 17:41:19 | `6ec5f763…` |
| `tap-work.netdev` | 49 B | 2026-03-08 13:39:16 | `1e1099a3…` |
| `tap-work.network` | 101 B | 2026-08-02 17:41:19 | `55e218e0…` |

`br-personal` is a bridge with no L3. `tap0` and `tap-personal` are enslaved
to it (`Bridge=br-personal`). `tap-outer` and `tap-work` are standalone taps
with `LinkLocalAddressing=no`. Every `.netdev` tap carries `User=host`, and
every `.network` carries `RequiredForOnline=no`. `networkctl list` shows all
five as `no-carrier configured`. Full hashes and contents are in
`wp-0927-report.md`. No KatMate unit is known to use any of them. That is
not verified: they were not traced, only listed.

**Operator rulings of 2026-09-27**, recorded as rulings:

- **R9 — ruled: yes.** The dev console drop-in is per-session only, in
  `/run/systemd/system/<unit>.d/90-dev-monitor.conf`, and never in `/etc`.
- **#39 — option (b), applied.** The pool is folded into
  `katmate-sys-driver@.service` (`a36bdb2`, `70b08c7`). One unit now starts
  netVM.
- **H4:** the unit keeps `katmate-generate-env %p %i` (above).
- **ADR-035 revision note:** accepted as proposed in pf § 6 item 9. Written
  as ADR-035's 2026-09-27 note.
- **`tap-int0` host files:** removed now (Phase M, above).
- **`KM_MAC_INT` in the generator:** the orphaned `sys` branch is removed in
  its own commit at networking arc step 4, alongside #19. The `app` branch
  stays (ADR-035 §9). Open problem #41.

**Not executed, therefore not claimed.** The C5 rollback is **UNVERIFIED**. It
first executes on the next failed start of the folded unit, and it is settled
by `katmate-pool@netvm` `LoadState=loaded` after a restore and
`daemon-reload`, then that unit `active` with 16/16 bindings (pf § 6). No stop
was issued, so `RuntimeDirectoryPreserve=yes` under the folded unit is not
re-measured. No traffic crossed any slot. The guest's link state and addresses
were not read. `/run/katmate/vm/netvm.env` was not read, so the claim that the
projection still carries `KM_MAC_INT` is inferred from the generator source.
`net-sys.con` still names `tap-int0` (`:26`), which is a finding and was not
changed.

## Previous session (2026-09-26, net-up and net-m1) — netVM running again on a per-session console, its network baseline read, and the vanilla network stack ruled

**The heading names sessions, not an ordinal:** the day already has a range
entry below, so *first of two* would miscount. Two sessions ran on MINIS, and a
third wrote them up. Reports outside the repository:
`~/Claude.assistent/net-up-report.md`, `~/Claude.assistent/net-m1-report.md`;
the write pass is `~/Claude.assistent/wp-0926b-report.md`, on the Acer, MINIS
not contacted, nothing measured.

**R1 applied — the `208/STDIN` trap is removed, not worked around.** Both
`/etc` `90-dev-monitor.conf` drop-ins, the pool unit's and the sys-driver's,
were saved to `~/katmate-dev/removed-0926/` on MINIS, `cmp`-identical to their
originals, and removed with their empty `.d/` directories. After
`daemon-reload` both units read `StandardInput=null` and an empty
`DropInPaths=` (net-up § 14). Console input is now installed **per session
only**: a `/run` drop-in carrying the saved pool content, the FIFO and the
transient holder, all on tmpfs, the holder in the six-line form of
`netvm-rebuild-3-report.md:267–272` run verbatim (net-up §§ 11, 15).

**netVM was started through the pool unit** — `katmate-pool@netvm.service`,
exit 0 in 0.65 s, MainPID **605841**, `NRestarts=0`, all three `ExecStartPre=`
successful; the sys-driver unit was never started. Holder and QEMU rendezvoused
on the FIFO at the start, observed on both ends; the slot tree is 16 of 16 by
path and by binding; `ping-client ping 3` answered `status=0x00 (OK)`
(net-up §§ 16.1–16.4). Details in § *Live state*, netVM.

**The baseline, read in-guest after the operator's login** (net-up § 19.3),
stated as readings: netVM's `nft` is **1.1.3**; every egress rule names
`oifname "proton"` and no `proton` interface exists, so by the ruleset text a
pool-sourced packet to the uplink meets policy drop; `rp_filter` is unchanged
from 2026-09-14; IPv6 `accept_ra=1` on `all` and `default`; the slots are DOWN
without `IFF_UP`; lease `10.3.1.103`; **no resolver** (`/etc/resolv.conf`
absent, `resolved` inactive); `ip neigh` empty; `/etc/nftables.conf` is
`1000:1000`, mode **0755**, and no uid-1000 user exists; `netvm-agent` active.

**Open problem #33 confirmed a second time**, on a different boot: all 17
stage-one renames before `systemd-sysctl` finished, all 16 stage-two renames
after it (net-up § 16.5).

**net-m1 answered what the rulings needed** (net-m1 § 9): `addr=` is pinned
nowhere, and the uplink sits at guest `0000:00:04.0` with `vfio-pci` 4th in the
argv — consistent with placement by argv order, not shown to be caused by it;
`ID_PATH=pci-0000:00:04.0`, the uplink falling through to `99-default.link`;
without `resolved`, networkd writes the DHCP DNS only to
`/run/systemd/netif/leases/<n>`, headed *"Do not parse"*, and the value is
`DNS=1.1.1.1`; `networkctl status` fails without a bus; `dnsmasq` is absent.

**A permission-mode incident, and it is now a rule.** In Claude Code's auto
mode the classifier denied `scp` + `sudo -n bash` ("Production Reads") and,
with the operator's allow rules for ssh/scp in place, the console FIFO write
("Remote Shell Writes"); both calls were refused before execution, so nothing
reached MINIS. The session resumed in **Manual** mode (net-m1 §§ 3, 4, 6, 7).
The rule is in § *Live state*, *Dev access to MINIS*.

**The operator's rulings of 2026-09-26**, recorded as rulings:

- **R1 — `208/STDIN`.** Both `/etc` dev drop-ins are removed, and the shipped
  `StandardInput=null` is restored. Console input is installed per session
  only. Applied by net-up § 14.
- **R2 — Vanilla egress.** netVM egress in a vanilla KatMate is direct through
  the uplink, with no VPN. VPN is a post-install option that the user enables
  by supplying a WireGuard config file.
- **R3 — Uplink name.** `uplink0`, through a `.link` matched on `Path=` (the
  PCI path inside the guest), not on the MAC. The ruleset targets
  `oifname "uplink0"`.
- **R4 — Pinned address.** The `vfio-pci` device carries `addr=` in the unit,
  so `Path=` is stable by construction.
- **R5 — AppVM DNS.** `dnsmasq` in netVM, listening on `10.100.1.1`,
  forwarding to the DNS server the uplink receives.
- **R6 — Uplink DHCP client.** `dhcpcd` replaces systemd-networkd on the
  uplink.
- **R7 — Static addressing.** The uplink may be configured statically. That is
  per-installation configuration (T1), never baked into the image.
- **R8 — Config channel.** Per-installation netVM configuration (static IP,
  the WireGuard config, and anything later) reaches netVM through a read-only
  config disk. The host assembles it from `/etc/katmate/netvm/`, and netVM
  attaches it as an extra `virtio-blk`.
- **R9 — the `/run` placement of the per-session console drop-in** (net-up
  § 18 item 1). **Applied, awaiting the operator's ruling.** Not decided.

R2–R8 are written as [ADR-037](docs/DECISIONS.md#adr-037), **PROPOSED**:
the decisions are ruled, and acceptance waits on its six gates.

## Previous session (2026-09-24 … 2026-09-26) — the first web AppVM: foundation reduced to the shared GUI runtime, rebuilt, and booted

**One heading covers the arc**, as the 2026-09-12 … 2026-09-14 entry did: a read
pass, three measuring sessions on MINIS, an implementation pass, a rebuild, and
the operator's first boot. Reports are outside the repository under
`~/Claude.assistent/`, named below, and carry everything this entry leaves out.

**The read pass found the foundation carrying applications.**
`build/foundation.sh` installed `dbus`, `libgtk-3-0`, `foot` and `nautilus`
into the foundation, against ADR-007 and ADR-014's "deliberately carries no
applications" — so a `web.list` swap of nautilus for pcmanfm could not remove
either, because both arrived one layer down (`appweb-readpass-report.md` § 2.5,
D1).

**The first measurement halted on the host, not the guest.** `linux-hardened`
had been upgraded 7.2.5 → 7.2.6 at 2026-09-19 20:49 without a reboot, which
removed the running kernel's module tree: `overlay` is `=m`, so no module that
was not already loaded could load until a reboot (`appweb-m1-report.md` § 3.1).
The operator rebooted on 2026-09-25 (14:00:27, kernel
`7.2.7-hardened1-1-hardened`). The re-run then halted again at the same guard
for a different cause — the module was present but not yet loaded, and the
guard could not tell the two apart — and passed once the guard was rewritten
to `modinfo -n` and one `modprobe overlay` was authorised
(`appweb-m1-rerun-report.md` §§ RB.1, R5.4 W1, S2–S4). Its A13 reading found
the host's PATH `waypipe` at distro `0.11.2` against the lock's `0.11.0`.

**The new foundation set was measured in a tmpfs overlay: 204 packages, 85
manual**, down from 415 and 88; the web layer then adds 21. udev, udisks2 and
gvfs leave. **systemd and systemd-sysv stay, with two independent keepers:**
`systemd-sysv` is `Protected: yes`, and GTK3 pulls
dconf → `dbus-user-session` → `libpam-systemd` → `systemd-sysv`
(`appweb-m2-report.md` §§ 6.1, 7.3, 11 W1).

**Implementation** (`appweb-impl-report.md` § 1): `13a509d` reduces the
foundation to the shared GUI runtime, diverts `/usr/sbin/init` to
`init.systemd` before katmate-init lands there, and makes the comments stop
claiming systemd is absent; `adc217f` replaces nautilus with pcmanfm in the
manifests and the vm-agent RUN whitelist. **The rebuild**
(`appweb-rebuild-report.md`) added `1d53c77` (the ADR-014 revision note,
amended from `dd3df01`) and `5d32dd0` (a read-back of the diversion before
katmate-init is baked), then ran `make foundation` and `make app-web`:
**foundation 209 packages / 85 manual, `vm_app_web` 230, and the 21 it adds
are exactly m2's T4 list**; the divert landed; `KERNEL_PROVENANCE=recorded` is
in `foundation.meta` for the first time; no hold was left (§§ 5.1–5.3). The
old LVs, delta, meta, kernels and agent were set aside as `_pre0926` (see
*Live state*).

**First boot, by the operator, 2026-09-26:** pcmanfm, foot and firefox-esr
render through waypipe; `run nautilus` is refused; firefox has no internet,
which is expected — `app_web` has no network device and derives
`app-offline`. Before it, the operator repointed the host's waypipe listener at
`/opt/katmate/bin/waypipe` and disabled a socket unit that turned out to be a
TCP `[::]:1024` listener; see *Live state*, *Host GUI ingress* (operator,
2026-09-26).

**Rulings of 2026-09-26 (operator):** the guest's IP is set by katmate-init at
boot, and vm-agent may also set IP configuration at runtime — a direction, the
mechanism not chosen; the `208/STDIN` repair choice stays open; the foundation's
dependency debt (#35) is deferred past the alpha.

## Previous session (2026-09-20, second of two) — the rest of the day under one heading: `auditfix-liveread`, which found the apparatus destroyed and answered open problem #33 from the host journal; `b1-docwrite` and `b1b-rulings`, the two passes that wrote the day into this file and committed it; and `c1-adr035-note`, the ADR-035 §8 ruling

**One heading covers four sessions, and the body below is the first of them** —
the project's own device, as the 2026-09-12 … 2026-09-14 entry uses it. The
second is **`b1-docwrite`**, the pass that wrote this file and performed the
rotation to `docs/SESSIONS.md`: it ran **on the Acer**, **MINIS was not
contacted**, and **nothing was measured** — every fact it wrote is cited to one
of the two reports of the sessions that took the readings. What it wrote is the
dateline, the reboot record in § *Live state*, open problem #33's answer block,
the two entries here and the two rotated entries there; what it deliberately did
not write are three revision notes, which stay proposed in its report. Report
outside the repository: `~/Claude.assistent/b1-docwrite-report.md`. It gets no
heading of its own because § *Session archive*'s arithmetic stays at two, and a
covering heading is what keeps a session from being destroyed by a later trim
rather than archived.

**The third is `b1b-rulings`, and it is the pass that committed the day.** It
ran **on the Acer**, **MINIS was not contacted**, and **nothing was measured**:
it took `b1-docwrite`'s uncommitted working tree as it stood and applied the
operator's rulings to it — the reading note in `docs/SESSIONS.md` that a
`This session` prefix is not a claim about recency, the covering heading above
in the form it carried until this pass reworded it, and its paragraph, open
problem #33's close, the ruling that the liveread
continuation stands, and one new dated instance under § *Invariants &
gotchas*' memory-assertion bullet. **Three signed commits**, all `%G?` = `G` and
none pushed: `a6e3fba` (the rotation and the reading note), `2c665e0` (#33
closes), `70c03f8` (the day's entries and the continuation ruling). One edit it
made was outside its brief and is named in its own report: the dateline's *"the
two sessions of 2026-09-20"* became *"the first two"*, because its § 1.2 had
made that count false in the same file. Report outside the repository:
`~/Claude.assistent/b1b-rulings-report.md`.

**The fourth is this pass, `c1-adr035-note`, and it writes a ruling rather than
taking a reading.** It ran **on the Acer**, **MINIS was not contacted**,
**nothing was measured**, and **no manifest and no code changed**. It appended
the operator's ruling on [ADR-035](docs/DECISIONS.md#adr-035) §8 to that ADR
verbatim, as a revision note: §8 may no longer be read as forbidding a
per-slot binding in nft, because `km00`…`km0f` are pool constants in T4 and **a
per-slot rule is not a per-AppVM rule**; §8's citation of
`docs/ARCHITECTURE.md` § *Networking* is corrected, that document being
unchanged and uncontradicted; and the cost is stated rather than absorbed —
**the interface name is now load-bearing**, and §8's sentence that it is not no
longer holds. It opened **open problem #34** for the half the ruling does not
cover, the pool's ARP surface, and wrote this entry. **The candidate ruleset
stays outside the repository** at `~/Claude.assistent/nftables-f12-candidate.conf`
and is **ungated**: its two gates — `nft -c -f` as root on the host **and**
inside netVM, and a live refusal measurement against the loaded ruleset — are
untaken, and netVM is down. **Its first attempt halted** on two divergences, the
fixture the ruling names being absent from the machine and the day's session
count being falsified by `b1b-rulings`; the operator placed the fixture and ruled
the arithmetic, which is why both headings of 2026-09-20 read *of two* — the
ordinal counts entries, not sessions, per the 2026-09-04 precedent § *Session
archive* already carries. Reports outside the repository:
`~/Claude.assistent/c1-adr035-note-report.md`, and the halt it replaces at
`~/Claude.assistent/c1-adr035-note-report.halted.md`.

**It halted on its first remote probe, and the halt is the finding.** Four of
the brief's five halt conditions fired at once: MINIS had rebooted on
**2026-09-19**, and the netVM that brief was written around — with every fixture
§ *Live state* rested on — no longer exists. **Nothing was started, stopped,
restarted, reloaded, repaired or written:** no `nft -f`, no `sysctl -w`, no `ip`
state command, no unit operation, no rsync, no write under any tier directory,
and the console FIFO was **not** recreated. Report outside the repository:
`~/Claude.assistent/auditfix-liveread-report.md`. **What the reboot destroyed,
what survived it and what it costs are written into § *Live state*, and the
ordering it recovered into open problem #33**; what follows is what belongs to
this entry.

**It continued past the halt for four items, and that was its own decision.**
The brief's § 4.7 host half, § 4.8's unit-file half, § 5's two `nft -c` probes
and § 4.2 read installed unit files, a persistent host journal and syntax checks
that load nothing — none of them depends on anything that halted, and all four
would read the same if netVM had never existed. The alternative it rejected was
taking the in-guest readings by **starting** netVM, which is the workaround the
brief forbids and is host-reboot-class. **The continuation stands — ruled by the
operator on 2026-09-20.** The four items depended on nothing that had halted and
changed nothing, and one of them answered open problem #33 out of a host journal
that a `vacuum` would eventually have taken
(`auditfix-liveread-report.md` § 4.1).

**Finding 8 changed shape: the audit's netVM half describes a path that does not
run.** The live launch path is `katmate-pool@netvm.service`, whose `ExecStart`
carries **`-monitor none`** — no QEMU monitor at all, HMP or QMP — and
**`-chardev stdio,id=console0,signal=off -serial chardev:console0`**, the guest
serial line bound to a plain stdio chardev and **not** multiplexed with a
monitor. **`-serial mon:stdio` is nowhere on it.** It exists only in the `.con`
launchers, and **no `.con` launcher has started netVM since the pool unit took
over**, so `net-sys.con` is superseded **as the starter, not as a file** — it is
still present, still carries `-serial mon:stdio` at `:16`, and would still work
if run by hand. **No AppVM unit is installed and nothing on MINIS can start an
AppVM today**; the AppVM peers of the 2026-09-12 arc were ad-hoc `systemd-run`
transients and they are gone. What actually crosses the boundary is therefore
the **input** half — the console drop-in — plus the guest's unrestricted,
unrated write into the **host** journal through `StandardOutput=journal`, in raw
form, ANSI escapes included. A `docs/SECURITY-MODEL.md` gap-15 wording and the
shape of a containment (a `SyslogIdentifier=`, a rate limit, a separate journal
namespace) are **proposed in `~/Claude.assistent/b1-docwrite-report.md` and
deliberately not written**: that path is load-bearing for observation
(§ *Invariants & gotchas*) and must be constrained rather than removed.
(`auditfix-liveread-report.md` § 2.3.)

**Finding 10 now has its bound, and there is no memory ceiling at any of four
cgroup levels.** The unit, its per-template slice, `system.slice` and `-.slice`
all report `MemoryMax=infinity` and `MemoryHigh=infinity`; `LimitAS=infinity` on
both units; `system.slice/memory.max` reads `max` in cgroup v2 directly. **The
only resource directive in either unit file is `LimitMEMLOCK=infinity`** —
`katmate-pool@.service:190` and `katmate-sys-driver@.service:157` — which is the
one directive that *lifts* a limit, for VFIO's full-RAM pinning, and neither
drop-in carries any. **Verified twice and deliberately:** by `systemctl show`,
and by a `grep` over both unit files and both drop-ins as a control against
`show` reporting a default that the file does not set. **An unbounded allocation
in either process is bounded only by MemTotal ≈ 30.1 GiB and by swap**, with no
cgroup ceiling between it and the machine; for calibration, the last full
six-day netVM run peaked at **1G**, roughly 3 % of what the absence of a ceiling
permits. (`auditfix-liveread-report.md` § 2.2.)

**Finding 12 — P1 settles the mechanism the fix rests on; P2 did not settle its
question, and its probe was defective.** `iifname "nosuchdev0"` → `nft -c` exit
**0**; `iif nosuchdev0` → exit **1**, *"Interface does not exist"*, naming the
token and its column span; **both `lo` controls → exit 0**, which is what makes
the rejection mean **resolution** rather than unsupported syntax — 4 of 4 runs
behaving as the hypothesis predicts. So an `iifname`-shaped per-slot binding
**loads against an absent or unrenamed interface and is independent of open
problem #33**, degrading to an inert rule on a slot whose rename never fired,
while an `iif`-shaped one **fails the entire load** if a single slot is missing.
**Version caveat, and it binds:** measured under `nftables v1.1.7` on the MINIS
**host**, and **the guest's version is unread** because netVM is down — so the
result **does not carry into netVM until it is read**. **P2:** `nft -c` accepted
a `table netdev` ingress chain on an absent device **and accepted the `lo`
control too**, so it does not discriminate — `-c` never reaches the kernel and
cannot observe a load-time binding of any kind. **What is recorded is the defect
in the probe, not a result about nftables**; settling it needs a real `nft -f`
load, which is a state change. (`auditfix-liveread-report.md` §§ 2.5, 5.4.) **All
of this is finding 12's IPv4 half; its ARP half is open problem #34.**

**The rename to `km00`…`km0f` fires — 16 of 16 — and this is the first
measurement of it.** Every name present exactly once, no gaps and no duplicates,
on the boot of 2026-09-12. **The name↔MAC pairing is NOT measured and is not
claimed:** the rename records carry the virtio device index, not the address,
and the guest is gone. The renames complete out of index order, which is udev
worker concurrency and is load-bearing nowhere. The ordering half of the same
reading is what answers open problem #33, and it is written there rather than
here. (`auditfix-liveread-report.md` § 2.6.)

## Previous session (2026-09-20, first of two) — `auditfix-readpass`: finding 10's absence measured with its control, and both accept loops read as serial

**It halted before its first remote command**, on a fixture its brief names and
the tree does not contain — the § 4 candidate ruleset — so **MINIS was never
contacted and nothing live was read**. Report outside the repository:
`~/Claude.assistent/auditfix-readpass-report.md`. Every reading below is a tree
read at `e736528`, and the entry above is the same day's second session.

**Finding 10's load-bearing half is an explicit and complete absence.**
**Fifteen patterns over eighteen tracked files, zero hits:** no timeout, no
deadline, no non-blocking mode and no readiness multiplexing anywhere in the
agent workspace — not in the codec, not in either agent, not in the client, and
no dependency supplies one, the crates being `std` + `libc` only. **The control
fires on 18 of 18 files and returns 120 hits**, run in the same command form
over the same file set, which is what separates this absence from a search that
could not fire. Every socket in the workspace is blocking with no `SO_RCVTIMEO`,
and every read is a `read_exact` loop that exits only on data, EOF, or an error
that is not `EINTR`. (`auditfix-readpass-report.md` § 2.8.)

**Both accept loops are serial.** `handle_connection` is called directly on the
accepting thread in `netvm-agent` and in `vm-agent` — no `fork`, no thread, no
`spawn` and no runtime in either dispatch path, `vm-agent`'s `posix_spawn` being
waypipe for a `RUN` opcode and not dispatch. **One stalled connection therefore
blocks every subsequent one**, because the next `accept()` is not reached until
`handle_connection` returns; combined with the absence above, a peer that
declares a large `payload_len` and then sends nothing holds the agent in
`read_exact` **indefinitely**, and during that time no other client is served.
**`read_request`, which runs inside every agent, has the identical shape** as
the `read_response` the audit names: read a declared `u64`, bound it against
`MAX_FILE_SIZE`, allocate `vec![0u8; payload_len]` **before a byte of content
arrives**, then `read_exact`. The shape of a fix differs by answer — a read
deadline fixes the stall, concurrency fixes the blocking, neither alone fixes
both — and **that session chose nothing**, the choice being the operator's.
(`auditfix-readpass-report.md` §§ 2.7, 2.9.)

**One divergence that session raised is still open and unruled, and this
documentation pass did not touch it:** ADR-035 § 8 cites
`docs/ARCHITECTURE.md` § *Networking* for a sentence that document does not
contain. **Neither document was changed, by that session or by this one**
(`auditfix-readpass-report.md` § 5, divergence 2). It is the operator's.

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

## Previous session (2026-09-07) — the netVM is rebuilt, ADR-035 §8 lands, and G5a settles who creates the slot tree

**One arc, four delegated sessions**, from the evening of 2026-09-05 through
2026-09-07: the netVM rebuild, the push, ADR-035 G5a, and the consolidation of
the pool scaffolding. Two commits of substance, `22a1f17` and `5e2d95f`, both
pushed, plus this entry. Reports outside the repository:
`netvm-rebuild-3-report.md`, `push-report.md`, `adr035-g5a-report.md`,
`pool-consolidate-report.md`, `adr035-g5a-note-report.md`.

**The rebuild carried four changes and they were read separately**, which was
the point of running them in one pass: different carriers, independent
readings, and neither able to mask the other.

1. **The credential is rotated.** Proved by a login, not by the build — step 6b
   proves a hash reached `/etc/shadow`, only a login proves it opens. **Open
   problem #29 closes here**, and nothing was vacuumed: the old value is retired
   by the rebuild, not by deletion.
2. **ADR-035 §8 landed**, as **sixteen exact-match `.link` files** in
   `/usr/lib/systemd/network/` — tracked in `manifests/netvm.conf.d/`, needing
   no edit to `netvm.sh` because step 5 bakes the config tree with `cp -a`.
   Sixteen names `km00`…`km0f`, no gap, no duplicate; ordering confirmed in the
   guest as `70- < 73- < 80- < 99-`, so `99-default.link`'s `NamePolicy=` never
   gets the chance. The uplink was untouched — exact `MACAddress=` cannot glob
   onto it, which is the property that made one rebuild safe for two changes.
3. **The kernel did not move**, `6.12.107+deb13-amd64`, `vmlinuz` identical in
   size. A result, not a non-event: it was the change nobody asked for.
4. **The initrd compressor moved gzip → zstd**, and it boots. Attribution is
   clean: the same early cpio in both, both decompressing to exactly
   34,780,160 B, only the compressed segment differing.

**Both halves of #29's guard are now measured.** It proceeded on a login prompt
and **refused on a shell** — the case that leaked the credential twice that
week — and the refusal direction had never been exercised before. **A guard
placed as a separate step is not a guard**: the two leaks happened because it
was skippable, and the fix is that it lives inside the same call.

**And the guard's first act must be a bare newline, for a measured reason.**
`localhost login:` is written **without a trailing newline**, and journald
splits on newlines, so the prompt appears in no record at any window size. It
was ever visible only because a `Link is Up` line landed on the same line and
completed it. **Checking for a login prompt without writing a newline first is
unsound in the refusing direction** — a variant that drops the write to save a
round trip would fail silently and look like caution.

**The blocker G5a was written for.** After the host reboot of 2026-09-05,
**nothing created `/run/katmate/link/<i>/<kk>/`** and the first pool start
failed at its first `-netdev`. Measured four ways that no mechanism existed. The
tree had only ever been hand-made `tmpfs` scaffolding from a brief, and no
reboot would reproduce it.

**G5a took both halves and the mechanism claim holds.** `RuntimeDirectory=`
naming the sixteen slot directories created the tree from a confirmed-absent
`/run/katmate/link` **three times**, including two parent levels the directive
does not name and systemd creates anyway.

`RuntimeDirectoryPreserve=yes` is load-bearing, and the refusal half says so
from the other side — with a fixture bound on `…/00/appvm`:

```
                     preserve=yes            preserve absent
appvm across stop    4830 → 4830             5000 → absent
netvm across stop    4771 survived → 4875    removed at stop → 5060
slot directory       4748 throughout         4955 → 5038, changed
fixture fd           live throughout         live throughout
```

Without `Preserve=yes` a netVM restart **unlinks a live AppVM's socket**, and
the AppVM keeps a live fd on an inode with no path — worse than a clean failure,
because from inside it still looks like a working socket. The damage is bounded:
the stop removed **exactly the sixteen slot directories**, while
`/run/katmate/link` and its instance level survived, and the sibling `nics/` and
`vm/` trees were never at risk.

**A non-root `bind()` into a slot is refused** — `EACCES`, as the invoking user,
on `…/01/appvm`. The directory is `0755 root:root`, systemd's default
`RuntimeDirectoryMode=`, and a datagram `bind()` needs write permission on the
containing directory. **An AppVM's QEMU runs as that user.**

**The operator ruled it:** `RuntimeDirectory=` creates the directories
root-owned, and **the launch daemon sets ownership at assignment and returns it
at release** — the same moment the `owner` file is written and removed, so
occupancy and permission are one act. Loosening the mode was **rejected**: a
group-writable tree would let any member bind into an unassigned slot, making
*"absence is freedom"* unenforceable. **Not decided:** whether the slot
directory needs the sticky bit, without which an AppVM that may write into its
own slot may also unlink the netVM's node there. **None of this is implemented**
— no `chown`, no mode change, and the launch daemon does not exist.

**G5's *"no `netvm` file exists between stop and start"* is untested, not
false.** It presupposes §5's own `ExecStopPost=`, which the measuring unit
deliberately lacks; none was added. Read with the three earlier observations
that QEMU does not unlink its sockets at exit, this **strengthens** §5:
`ExecStopPost=` is necessary rather than tidy, and it is unimplemented.

**Traffic was not taken** — G5's *"a re-issued ADD restores traffic in both
directions"* needs a peer speaking Ethernet frames, since a `-netdev dgram`
backend carries frames and not IP. That is **G5b**, and the operator's ruling is
that its peer should be a second QEMU rather than hand-built framing.

**The pool scaffolding is consolidated to one unit.**
`katmate-pool-rd@.service` and `katmate-pool-rd-nopreserve@.service` are gone;
`katmate-pool@.service` carries the two directives folded in, with its
`90-dev-monitor.conf` drop-in intact — which was the reason to fold rather than
delete, since the `-rd` variant had no console and G5b would have found out as a
`208/STDIN` mid-gate. Creation from nothing was re-proved on the folded unit.

**`katmate-pool@.service` now hashes `1d727b25…`, 13021 bytes.** The value
`873c4320…` is historical from 2026-09-07 14:49 and is still named in several
briefs and reports.

**ADR-035 status is unchanged: PROPOSED.** G2, G3, G4, G5b and G6 are untaken,
and both `ExecStopPost=` and assignment-time ownership are unimplemented.

## This session (2026-09-05, second of two) — ADR-035 records what G1 measured: two ceilings, and four places the ADR does not match them

Delegated session on the Acer, plus an amendment session. One commit,
`0dd54c4` — `079e72f` was amended and never existed on `main` in its first
form. Reports outside the repository:
`~/Claude.assistent/adr035-g1-note-report.md` and `…-amend-report.md`.

**One note carrying five findings**, held back across two gate sessions on the
operator's ruling so the ADR is amended once rather than five times: the two
ceilings and that their difference of four carries **no assigned cause**; that
G1's refusal half guesses a seventeenth device and the number is 26; that §8's
`kmkk` names are not in the image; that §5's `sun_path` headroom is 80
characters and not *"roughly seventy"*; and that G1's RSS reading against
ADR-033's table **is not performable as worded**, because the two subjects are a
paused guestless QEMU and a booted Debian with a `vfio-pci` device pinning its
RAM.

**A sixth finding arrived from the previous session and was added by amendment.**
`docs/DECISIONS.md:5039–5042`, § *Consequences* § *Harder*, carries the same
misdirection a second time and is the more misleading of the two: it does not
merely name twenty devices, it says *"G1 measures it at twenty or reports the
refusal."* The delegated session found it, **correctly did not act on it** — a
session may neither edit an ADR nor propose wording — and it was ruled into the
same note.

**That paragraph's other half was verified and holds exactly.** It attributes to
ADR-033 a refusal at the thirty-first device; ADR-033 states the figure three
times (`:3995–4001`, `:4150–4158`, `:4184–4185`) and every one names the
**default q35 root bus**, measured on QEMU 11.1.0 under TCG and reproduced under
KVM. G1b measured 30 accepted and 31 refused on a bare `-machine q35,accel=kvm`.
**Same configuration, two QEMU versions, two sessions, the same boundary** — an
independent agreement across two ADRs, and the reason the note may assert it
rather than paraphrase it.

**Nothing was corrected in place.** § *Gates*' lead-in and G1's refusal half are
unedited, and `:5039–5042` was verified byte-identical against `git show HEAD~1`
rather than inferred from a hunk header. Append-only means the reader gets both:
what the ADR expected, and what was measured.

**Status is unchanged: PROPOSED**, for a reason independent of G1 — **G2 through
G6 are untaken**. What changed is that § *Gates*' lead-in, *"none taken"*, no
longer describes G1.

**One trap worth carrying.** `grep -F` for the note's insertion anchor returned
**nothing**, because the phrase wraps across two lines. The anchor was present;
the check was not able to see it. The session spliced the file to find it rather
than reporting an absence — the same class as the `$`-in-a-BRE trap in
`CLAUDE.md`, and the sixth instance in four days of a check that returns a
well-formed wrong answer.

## This session (2026-09-05, first of two) — ADR-035 G1b: the ceiling is 26, and the seventeenth device is not refused

Delegated session, Acer authoring and MINIS running. **No commit** — nothing
entered the tree. Report outside the repository:
`~/Claude.assistent/adr035-g1b-report.md`; transcripts in
`~/Claude.assistent/g1b-transcripts/`.

**Two numbers, because only one of them is the one ADR-035 needs.** The bare q35
root bus with nothing else on it accepts **30** `virtio-net-pci`;
`katmate-pool@netvm`, with its four other PCI devices present, accepts **26**
slots. Both refusals carry the identical message,
`PCI: no slot/function available for virtio-net-pci, all in use or reserved`.
QEMU 11.1.1.

**The difference of four is a subtraction of two measurements and no cause is
assigned to it.** It is *not* a claim that each of `virtio-rng-pci`,
`vhost-vsock-pci`, `virtio-blk-pci` and `vfio-pci` costs one slot.
`memory-backend-memfd` is an `-object` and costs none. A prediction of 30 − 4
was stated before the unit ran and agreed with it; **an agreeing prediction is
still not a result.**

**Both by bisection to adjacency, and `N` = 17 through 25 were never run.** The
unit's ceiling rests on an acceptance at 26 beside a refusal at 27 — not on a
scan. Phase 1 ran beside the live pool and stopped nothing; phase 2 needed
**two** starts to find the ceiling, though the session performed four in total
counting the hand-back restart and the restore.

**The guest enumerates 26** at `N`=26 — all DOWN, MACs `…:00`…`:19`, 28
interfaces total, seven readings agreeing. **The 26-slot addressing is a probe
artefact and proposes nothing**; ADR-035's scheme is sixteen and this session
did not touch it. Sixteen slots therefore sit **ten below the unit's measured
ceiling** on this hardware — headroom, not licence, since every PCI device the
netVM gains later spends it.

**QEMU does not unlink its `netvm` sockets at exit — on a clean stop or after a
failed start.** Four exits, leaving 16 / 26 / 27 / 26 nodes. The 27-node case is
the informative one: a start refused at its twenty-seventh **device** had
already bound all twenty-seven **backends**, because netdevs are created before
devices. **So the pre-start sweep is load-bearing, not precautionary** — without
it the next start meets `EADDRINUSE`, which names a syscall and would classify
as an entirely different failure. This is an input to G5 and **not** a claim
about the `ExecStopPost=` ADR-035 proposes: no fixture was bound, no inode
compared, no `RuntimeDirectory=` variant run, and the observation is bounded to
`SIGTERM` and to a QEMU that exited cleanly or refused at start.

**Open problem #29 happened a second time, at 10:16**, into a shell prompt, same
value as 2026-09-04. Two new locations: this unit's journal on MINIS and the
operator's terminal scrollback. **Nothing was vacuumed**, on his instruction —
`--vacuum` is time-granular and would take the gate's own transcript. **The
guard works and its placement does not**: its first successful use was earlier
the same morning, when a bare newline into the FIFO came back with a login
prompt and the credential was safe to send; the failure came from a retry form
in which the guard was a separate, skippable step. **A guard that can be skipped
is the defect, not the person who skipped it.**

**Interface names moved three times in three boots of the same unit** — the
uplink was `eth25`, `eth26`, `eth16`, always renamed to `enp0s4`. Three
orderings disagreed with each other, with no cause assigned. **The MAC is the
identity and the name never is**, which is §7's premise measured rather than
argued.

**Restored and hash-confirmed.** The sixteen-slot unit is back at
`873c4320…`; `katmate-pool@netvm` runs as MainPID **3952302**, active since
**2026-09-05 10:22:22 CEST**; `katmate-sys-driver@netvm` is `inactive`.
The eleven extra slot directories `10`…`1a` under `/run/katmate/link/netvm/`
were **removed by the operator** after the session closed — his report, not a
measurement in any session's. The probe tree `/run/katmate-dev/g1bprobe/`
remains and is scratch.

## This session (2026-09-04) — ADR-035 G1a: a netVM boots from a sixteen-slot pool, and the console procedure burns a credential

Delegated session, Acer authoring and MINIS running. **No commit of substance —
nothing entered the tree.** Report outside the repository:
`~/Claude.assistent/adr035-g1a-report.md`. **No gate is claimed passed**; a
gate's verdict is not a session's to give.

**What was measured.** A netVM starts from a sixteen-slot pool template and the
guest sees sixteen interfaces carrying `52:54:01:00:00:00`…`0f`, **all DOWN and
all networkd-unmanaged**. The interface count is **18** — `lo`, the vfio uplink
and the sixteen slots — which is the arithmetic of §5's design measured rather
than argued: the pool **replaces** the internal segment (two argv lines out,
thirty-two in), so `KM_MAC_INT`'s device is gone. 19 would have meant a
different architecture from the one §5 published.

Read three ways that had to agree: the template diff, the running process's
`/proc/<pid>/cmdline`, and the guest's own `ip -br link`, cross-checked against
`/sys/class/net/*/address` — **the file `ifindex_by_mac` reads**, which is why
that cross-check and not another.

**G1 is NOT taken.** Its refusal half was not run, no seventeenth device was
added, and **netVM's PCI ceiling remains unmeasured** exactly as it was. That is
G1b. What this session establishes is the confirmation half only.

**Two of the four start-failure classes were eliminated before the running netVM
was touched**, which is the shape worth keeping. Sixteen `-netdev dgram`
backends bound under `-machine none` with no sandbox (P1) and again with the
shipped `-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny`
line (P2): **the sandbox changed nothing observable**. Sixteen
`virtio-net-pci` then built on a q35 root bus with no message at all. Only then
was anything stopped. A refusal at either probe would have cost nothing; a
refusal after the swap costs the operator's console session.

**Seventeen network devices run concurrently today** — sixteen slots plus the
`r8169` uplink — beside `virtio-blk-pci`, `vhost-vsock-pci` and
`virtio-rng-pci`. **So the ceiling is above seventeen**, and G1b must ramp from
well above it or it will report "seventeen works" and measure nothing, which is
what the original G1 brief's *"a seventeenth is refused"* hypothesis would have
produced.

**Scaffolding now on MINIS, untracked and never for the tree:**
`/etc/systemd/system/katmate-pool@.service` (the shipped template plus exactly
two hunks — `%p` replaced by the literal `katmate-sys-driver`, and the two
network lines replaced by thirty-two) and
`/etc/systemd/system/katmate-pool@.service.d/90-dev-monitor.conf`. The pool unit
carries a profile its **name does not assert**, which ADR-030 §2 forbids in the
tree; it is a measuring device and dies with the gate.

**The `208/STDIN` trap now applies to two units.** Both point at the same FIFO,
`/run/katmate-dev/netvm-console.in`. The drop-ins are in `/etc` and survive a
reboot; the FIFO is on tmpfs and `km-console-holder` is transient, and neither
does. After a host reboot **neither unit starts at all** until both are
recreated.

**The two must never run at once** — same instance name, same LV, same CID, same
VFIO device. `katmate-pool@netvm` is left **running** on the operator's ruling,
for G1b; `katmate-sys-driver@netvm` is `inactive`.

**Three findings the ADR does not hold, all deferred to one revision note after
G1b rather than two notes now:**

1. **§8's `kmkk` names are not in this image.** No udev rule exists; the names
   are the kernel's `enp0s5`…`enp0s20`. G1's own wording admits *"neither
   mechanism"* as an answer, so this is a fact about §8 and not a failure of G1.
2. **`sun_path` headroom is 80 characters of instance name, not §5's "roughly
   seventy".** The fixed part of the path is 27 bytes. Agrees with open
   problem #28, which is that nothing enforces it.
3. **G1's RSS reading against ADR-033's table is not performable as written.**
   The subjects differ in three recorded ways — ADR-033 measured a paused,
   guestless QEMU; this one runs a booted Debian with `-m 1G` through
   `memory-backend-memfd` and holds a vfio device that pins the guest's RAM.
   Numbers are in the report; no comparison was computed. This is a finding
   about the gate's design.

**Three orderings appeared and no two agreed** — the kernel's rename order
(`eth12` before `eth11`), the `ip -br link` name order, and `networkctl`'s
ifindex order. This is no longer an argument for §7; it is an observed condition
on a live image at the first pool boot, which makes it the normal case for
sixteen devices rather than an edge. **No cause was assigned.** The gate's table
was therefore read line by line and never by position.

**The projection still emits `KM_MAC_INT`** and the pool argv no longer consumes
it. G6's subject, untouched here.

## This session (2026-09-03, third of three) — ADR-035 §5 records that a slot's netVM device names the AppVM path, and that QEMU requires it

Delegated session on the Acer. One commit, `14f96e9`, GPG-signed and since
pushed. Reports outside the repository:
`~/Claude.assistent/adr035-remote-path-note-report.md` (a halt) and
`…-report-v2.md` (the commit).

**The first attempt halted, correctly, on a false sentence in the authored
payload.** The note's opening claimed §5 *"says nothing about a `remote`
parameter"*. §5 carries the token once — inside the em-dash clause of the very
sentence the payload went on to quote, and which the payload's quotation **cut
off one clause early**. The claim was falsifiable by one `grep` of the section
the note was about.

**The rewrite is a sharper finding than the false one.** §5 names `remote.path`
**only as a property of QEMU's sending behaviour** — ADR-033's measurement that
it is resolved per send and never `stat`-ed — used as the argument that a netVM
may safely name a socket no AppVM has bound. It never says the option parser
**demands** the parameter at start. So §5 recorded why the naming is safe and
omitted that it is compulsory.

**What the note records:** the `remote.path` of slot `k` in the netVM template is
`/run/katmate/link/%i/kk/appvm` — the node §5 already assigns to the AppVM to
bind — and the naming is **forced by the parser, not chosen by the layout**. The
netVM template therefore carries **thirty-two** literal paths, not sixteen;
*"zero values cross"* and *"identity crosses, not a path"* are both unaffected,
since the crossing rule governs the AppVM side where `KM_NETVM` and `KM_SLOT`
are typed scalars.

**ADR-035's status is unchanged: PROPOSED.** The note carries a property the
tree already held in ADR-033 § *Costs accepted* into the ADR that needed it. It
is not a gate result and advances no gate.

**Socket permissions were explicitly left open.** The netVM's QEMU is root and
an AppVM's is the invoking non-root user; now that the netVM device names
`…/kk/appvm` on its own face, that asymmetry is visible in the template. G5's,
and nothing was claimed.

## This session (2026-09-03, second of three) — the netVM root credential leaves the repository, and netVM gets an in-guest observation path

Delegated session on the Acer; the operator ran the build on MINIS. One commit
of substance, `23e4268`, plus this entry. Report outside the repository:
`~/Claude.assistent/netvm-rebuild-report.md`. **No ADR-035 content was baked and
no gate was taken.**

**What landed (`23e4268`).** `build/netvm.sh` step 6 carried a literal
`$6$katmate$…` SHA-512 crypt string and applied it **unconditionally**, so every
image this pipeline ever produced shipped with root unlocked — release builds
included, because there was no way to ask for a locked one — and the credential
was tracked, signed and pushed. It is gone. `passwd -l root` is now the default
and costs nothing to reach; a dev build asks for the unlock by passing
`KATMATE_DEV_ROOT_HASH`, a **hash and never a plaintext**, validated as a
well-formed `crypt(3)` string before it is baked. ADR-021 already required this
in the general case (*"no per-install secret lives inside it"*).

**The commit gained a read-back before it was made, and the operator is why.**
As first written, the change validated the *opt-in* branch and trusted the
branch that *ships*: `passwd -l root || true` was the release path's only
security action, and `|| true` says its failure does not count — a failed lock
would have produced a successful build, a log line reading *"release-safe
default"*, and a meta key claiming the same, with nothing disagreeing. **Step 6b
now reads root's `/etc/shadow` field back and dies on a mismatch**, in
`katmate-generate-env`'s idiom (ADR-030 §8: read back what you published before
you exit). Only the `!` marker or the three-character crypt id is ever logged.
`|| true` is retained because the read-back — not the exit status — is the
evidence.

**`netvm.meta` gains `NETVM_ROOT_UNLOCKED=yes|no`, host-side copy only, at
`KATMATE_META_VERSION=1` unchanged.** The schema question was answered from the
tree rather than referred up: `km_meta_open()` refuses any version but 1 and
readers take keys individually, so an *addition* is invisible and a *bump* would
break every shipped T4 executable — and ADR-034's `KERNEL_PROVENANCE` joined
`foundation.meta` the same way on 2026-09-01. **Measured, not argued:** all three
`ExecStartPre=` exited `0/SUCCESS` against the new eleven-key meta.

**THE GUEST KERNEL MOVED: `6.12.101+deb13-amd64` → `6.12.107+deb13-amd64`**
(Debian `6.12.107-1`, 2026-08-29), confirmed by `uname -a` from inside the
running guest against the meta's claim from outside. **Any measurement recorded
against 6.12.101 does not describe this image** — that covers the 2026-08-19
G1/G4 run, the 2026-08-21 G5/H3 run, the 2026-08-22 stop-path/G6 run and every
uplink observation taken between 2026-08-11 and today. trixie moving under a
declarative manifest is the manifest working, as at 6.12.96 → 6.12.101 before
it; but a kernel version is a premise and the premise changed.

**IN-GUEST OBSERVATION NOW EXISTS.** This is what the rebuild was for: ADR-035's
gates G1–G4 need a reading from inside netVM and there was no path to one. The
mechanism is `/etc/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf`
— the exact file the shipped unit's own comment nominates — adding **one**
directive, `StandardInput=file:/run/katmate-dev/netvm-console.in`, so stdin
becomes a FIFO instead of `/dev/null` while output stays in the journal.
Untracked, per-machine, dev scaffolding, on the removal list beside #4, #11 and
#12. That systemd delivers FIFO bytes to a service's stdin was proven on a
throwaway `/bin/cat` unit **before** the drop-in was written.

**Two traps in that console, both measured, both of which cost this session
real time.**

1. **`journalctl -o cat` is a correctness requirement, not a convenience.**
   journald renders any record containing non-printable bytes as
   `[NNNB blob data]`, and `login(1)`'s *timeout* path emits `Password: ` glued
   to `login: timed out after 60 seconds` and a run of terminal-reset escapes —
   so the prompt is **stored but invisible** in the default format. Counted over
   one unit's history: 6 `Password` lines in the default format, all of them
   systemd unit names from boot; **10** under `-o cat`. The operator read the
   default format and correctly saw no prompt; the session read `-o cat` and
   correctly saw one. Both readings were honest and the format explains the gap.
2. **A single write carrying both fields loses the password.**
   `printf 'root\n<pw>\n' > <fifo>` delivers the username and the password is
   gone before `login` prompts; two writes ~3 s apart work. Measured as a gated
   A/B — PROBE A: `localhost login: root` and nothing else; PROBE B:
   `localhost login: root` → `Password:` → `Login incorrect` in 5.8 s. **The
   session had recommended the single-write form**, which is why two of the
   operator's login attempts timed out and why his password was never actually
   tested. *Why* the single write loses it — agetty buffering across the `exec`,
   or `login` flushing terminal input before prompting — is **not measured**.

**The old hash matched no password, and here is the measurement so nobody
repeats it.** Three candidate passwords were tested against the removed
`$6$katmate$…` field on 2026-09-03 with **`openssl passwd -6 -salt katmate`**
(salt `katmate`, sha512crypt) and **none matched**. *That test is the operator's;
this session did not re-run it and does not hold the candidates.* What this
session did measure is that the field was **well-formed rather than truncated**:
97 characters total, four `$`-separated fields, algorithm marker `$6$`, salt
`katmate`, body **86** characters — the canonical sha512crypt length — matching
`[./A-Za-z0-9]+` in full. **A credential that does not work is what let it
survive four months of review. It is still a credential in git.**

**Readings taken from inside the new image**, all read-only, all through the
FIFO: `uname -a`; `ip -br link` / `ip -br addr` — uplink **`enp0s4`** UP with
`38:05:25:34:7c:47` and lease **`10.3.1.103/24` metric 100** (the same lease
recorded 2026-08-19, taken from inside this time instead of by host ARP scan),
internal segment **`enp0s5`** DOWN with the derived `52:54:00:21:b2:08` and no
address, which is correct with no AppVM and no NETCFG; `netvm-agent` **active**,
though no opcode was exercised. **The interface names moved again and the MACs
did not** — the uplink has now been `enp0s6`, `enp0s4` and `enp0s5` across
sessions. Read the MACs.

**The root account, read from the LIVE image**: `locked=no`, `cryptid=$6$`,
field length 106 — **classification only, the body was never printed and is not
known to this session**. It agrees with `NETVM_ROOT_UNLOCKED=yes` and with 6b's
in-build read-back. This recovers the brief's *"read `/etc/shadow` before it is
unmounted"* step, which **was missed** — the build had finished before the
session resumed — from a better vantage: what actually shipped and booted.

**The two `netvm.meta` copies now differ by one key, BY DESIGN.** Step 9's
in-guest copy has **four** keys and no `KATMATE_META_VERSION`; step 11's
host-side copy has **eleven**, including `NETVM_ROOT_UNLOCKED`. Measured from
the built image, not read off the script. The operator's reason: anyone who can
read an in-guest meta has already mounted the image and can read `/etc/shadow`,
which is the original and cannot drift — and a second copy of a fact the
original carries is how metadata drifts from its payload. **These two files had
identical key sets from the day they were written until 2026-09-03; anyone who
learned that before today will be wrong.**

**OBSERVATION, no verdict attached — `initramfs-tools` fell back to gzip.** The
build logged *"No zstd in /usr/bin:/sbin:/bin, using gzip"* twice, and `zstd` is
**genuinely not installed**: `dpkg-query` reports `unknown ok not-installed` and
the binary is at none of `/usr/bin`, `/bin`, `/usr/sbin`. So the shipped
`initrd.img` is gzip-compressed. **This is the `cpio` shape with a quieter
failure mode** — the manifest lists `cpio` explicitly so that a tool
`initramfs-tools` needs *"cannot fail on a missing tool"*, and a missing `cpio`
**fails the build** while a missing `zstd` **changes the artefact silently**,
recorded nowhere. **Ruled the same day:** `zstd` is added to
`manifests/netvm.list` explicitly, in `cpio`'s style and for `cpio`'s reason.
The property is not gzip or zstd but that the compressor is **chosen rather
than inherited from whatever happens to be installed** — absence is a fragile
way to choose, and the first package that ever pulls `zstd` in would flip the
initrd's compression silently. Own commit, own rebuild: **the tree declares
`zstd` and the image on MINIS is still gzip**, and stays gzip until a rebuild.

**A harness of this session's printed two confident false verdicts**, and the
class is already in *Invariants & gotchas*. An intermediate console probe gated
on the Debian banner appearing in the last three journal records — but the
banner sits *above* the prompt, so it is present both after a reset **and**
mid-attempt. Its two probes overlapped and each verdict was computed over a
window still holding the previous probe's `Login incorrect`. **It reported that
the single-write form works, which is the exact opposite of the truth**, and
nothing from it is quoted anywhere in the report. The tell was in the timeline,
not the verdict: the string appeared as an *echoed* record, and a password
prompt does not echo.

**Deliberately not done.** `ReadWritePaths=/etc/systemd/network` in the baked
`netvm-agent` unit is **untouched**, per #27's standing ruling that it falls in
the slot-pool commit. **So the image built today carries the dead Path A grant
and this rebuild schedules one more.** Nothing was pushed. No `lvremove` was run
by this session — the LV removal the rebuild required was the operator's, and
the post-build `Open count: 1` + `[jbd2/dm-9-8]` residue recurred exactly as the
*Invariants* entry describes it for a **successful** run: it says *"do not
`lvremove`"* and nothing about the image, and it did not stop QEMU opening the
device.

## This session (2026-09-03, first of three) — ADR-035 G1: the pool template is refused by QEMU for want of a `remote` parameter, and netVM has no way to be observed from inside

Delegated session on the Acer, reaching MINIS. **It halted before the first
change and that was the outcome.** No commit, no tracked file touched, no gate
taken. Report: `~/Claude.assistent/adr035-g1-report.md`. **Recorded here on
2026-09-03 by the day's second session**, which is why it appears below an entry
written after it; it had no heading of its own at the time and the archive's
rule is that a session without a heading cannot later be rotated.

**Always write "ADR-035 G1", never bare "G1".** Two gate numbering schemes
coexist: `katmate-sys-driver@.service:101` says *"Gate G4"* and means
**ADR-030's**, four lines above the `ExecStart=` a pool template would rewrite.

**Halt 1, the load-bearing one — the brief's `-netdev dgram` spelling is refused
by the QEMU on MINIS.** The line
`-netdev dgram,id=link00,local.type=unix,local.path=…` draws, on **QEMU
11.1.1**:

> `qemu-system-x86_64: … : type=inet or type=unix requires remote parameter`

`man` is not installed on MINIS and `-netdev dgram,help` answers *"Help is not
available for this option"*, so the schema was read **out of the parser** —
seven deliberately-malformed invocations under `-machine none`, each eliciting
the key it rejected. That bounded the defect to exactly one thing: `local.type`
and `local.path` are the right keys in the right dotted form (a bogus key is
named as `zzz`; a dropped `local.path` is named; `local=unix:<path>` is refused
as *"expected: object"*), and **only `remote` was missing**.

**The correction was already published in this repository and the brief did not
carry it.** ADR-033 § *Costs accepted* (`docs/DECISIONS.md:4023`): *"QEMU 11.1.0
brackets `remote` as optional and then refuses it as mandatory for `unix` and
`inet` … KatMate treats the runtime refusal as authoritative and every slot
names a peer path whether or not the peer exists."* This is a brief that
contradicted an accepted ADR, not a measurement overturning one.

**One sentence of the brief splits in two under the measurement.** It said the
AppVM-side path *"is not created and not used in G1. No peer exists"*. The path
is indeed never created, never `stat`-ed and never connected to — but it must
still be **named**, because the option parser demands the parameter before any
of that. **Not-created and not-named are different claims and only the first is
true.** The candidate consistent with ADR-035 §5 is
`remote.type=unix,remote.path=/run/katmate/link/%i/kk/appvm`; **which path
`remote.path` names is a T4 content question and the session did not decide
it.**

**Halt 2, independent — there is no in-guest observation path, and this is the
finding the day's second session existed to fix.** The brief asserted that
`state.md` records a dev sshd inside netVM. It does not. Open problem #4 is the
**host's** sshd; `manifests/netvm.list` installs **no `openssh-server`**; the
only `ssh` string in `build/netvm.sh` was a comment; no
`katmate-sys-driver@.service.d/` drop-in existed on MINIS; the unit sets
`StandardInput=null`; `netvm-agent` has **no RUN**; and #12 records that the
baked console password matched nothing. So ADR-035 G1 items 1–6, G2's in-guest
half and **G3 entirely** had no mechanism. The second session of the day built
one.

**A document/tree disagreement this session found and did not resolve.**
`docs/SECURITY-MODEL.md:307` (§ *Known gaps*, row 4) reads *"sshd also runs
inside netVM (CID 3)"*. That is true of the **retired netinst pet** and false of
`vm_sys_netvm`, the declarative image the unit boots. **The row's mitigation is
therefore partly inert** — *"remove both before release"*, where there is one —
and the gap is smaller than stated. Recorded for a ruling; nothing was edited.

**Free observations, none of them a gate.** QEMU on MINIS is **11.1.1**, not the
11.1.0 ADR-033 measured against, and `dgram` is in its `-netdev` type list. A
`dgram` netdev whose `remote.path` **does not exist** starts on 11.1.1 — the
probe ran to its timeout with the local socket bound and the remote path absent,
reproducing link-m1 § 11 / link-m2 § A.3 on a newer QEMU. The three installed
copies of `katmate-sys-driver@.service` hashed identically
(`813f27c8fd1e5e58…`), so the gate would not have measured an unknown template.
`/run/katmate/` was absent **because MINIS rebooted 2026-08-28 23:06**, after the
2026-08-25 stop — it says nothing about surviving a stop, which is G5's question.

**ADR-035 G1 is NOT taken.** netVM has never been started with sixteen
`virtio-net-pci` devices. Nothing is known about the device count, the
enumeration order `ifindex_by_mac` walks, the RSS against ADR-033's table, the
socket modes, or the ceiling — **netVM's own PCI ceiling remains unrun**, exactly
as ADR-033's acceptance note leaves it. No conclusion is drawn about ADR-035 §3,
§6 or §7.

## This session (2026-09-02) — the ADR-035 arc: a splice removed, five questions answered, and the netVM link pool decided as PROPOSED

Three delegated sessions on the Acer, one arc, ADR-035 from nothing to PROPOSED.
**None of the three reached MINIS, measured any behaviour, or took any gate.**
Reports outside the repository: `~/adr035-readpass-report.md`,
`~/d1-splice-repair-report.md`, `~/adr035-write-report.md`.

**Run 1 — the read pass (no commits).** Read the tree against ADR-033's open
items and produced the divergence list the other two runs worked from. Two of
its findings shaped everything after. **It found the splice:** a whole copy of
ADR-025, pasted by `8837e12` (2026-07-20) into the middle of a word in ADR-024's
consequences list, with its heading at **column 71** — so `grep '^## ADR-'` had
never shown it, and every section map drawn of that file since July had been
drawn over a document containing two ADR-025s and had reported one. And it found
the **first-match rule**: `netlink::ifindex_by_mac`
(`agent/crates/netvm-agent/src/netlink.rs:473–496`) walks `/sys/class/net`,
compares each `address`, **returns the first match** (`:493`), rejects on none
(`:496`), and neither counts nor sorts. With one internal interface that is
invisible; with sixteen it is a correctness precondition nothing enforces, and it
is why ADR-035 has a §7 at all.

**Run 2 — the splice repair (`ab50241`, `a4dab42`).** Removed the pasted
duplicate and restored the sentence it broke — the bullet *"Open problem #10
closes on the live gate; the QMP-wiring Next-step items drop from `state.md`"*
had been severed between `i` and `tems` with 229 lines in the gap. Not an edit to
a decision: the region was a faithful duplicate at birth, and every present-day
difference was a later canonical-side edit the copy never received.
**`grep '^## ADR-'` is a complete section map of `docs/DECISIONS.md` again, for
the first time since 2026-07-20.** `a4dab42` opened #27 and moved #13's citation.
**Every line number past ADR-024 shifted by −229**, which a later session
measures rather than carries.

**Run 3 — the write pass (`1d3f22c`, `cdbf714`, and this entry).** Answered the
five questions ADR-035's draft carried to the tree, appended the ADR verbatim as
PROPOSED, and recorded its supersessions in ADR-025, ADR-030 and ADR-033. It
opened on a halt — the brief named the draft at `~/ADR-035-DRAFT.md` and the file
is at `~/Claude.assistent/ADR-035-DRAFT.md` — and the operator ruled before any
read of it went further.

**The five answers, which exist nowhere else in the repository.** Every one is a
reading of source or configuration. **None is an observation of a running
system.**

1. **Today's NETCFG REMOVE deletes the payload's routes and the address, and
   nothing else** (`agent/crates/netvm-agent/src/netcfg.rs:338–346`). `IFF_UP` is
   **deliberately** not cleared, and the comment at `:331–333` gives the reason —
   *"a shared netdev would be broken by it"*. There is **no neighbour delete and
   no conntrack flush anywhere in the binary**: `netlink.rs` defines five `RTM_*`
   constants (`NEWLINK`, `NEWADDR`, `DELADDR`, `NEWROUTE`, `DELROUTE`) and there
   is no `link_down`. ADR-035 §6 requires all three.
2. **ADD converges on `EEXIST`, and distinguishes it from every other errno**
   (`netlink.rs:407`, `settle(e, &[libc::EEXIST], "addr add")`; one tolerance
   list per direction, and `link_up` at `:390` tolerates nothing). The request
   carries `NLM_F_EXCL` (`:400`), so the kernel is asked to refuse and the list
   converts that refusal into OK. **Bound:** `settle` receives an errno and not
   an interface, so what the kernel returns when the same address is added on a
   *second* interface is ADR-035's G2 and is not readable from this tree.
3. **Nothing bounds an instance name's length.** `km_check_instance`
   (`host/usr/lib/katmate/katmate-lib.sh:64–69`, the only check
   `katmate-generate-env:48` applies) is `^[a-z][a-z0-9_]*$` — a character class,
   unbounded — and `tools/validate-properties.fish` never examines the filename
   stem at all. **Open problem #28.**
4. **The netVM's and an AppVM's QEMU do not share a uid.**
   `katmate-sys-driver@.service` sets no `User=`, `Group=` or `DynamicUser=`, so
   it is root; **there is no AppVM unit at all**, and `app_web.con:113` invokes
   QEMU with no `sudo` (its three `sudo` calls are `lvchange`, at `:83,86,90`),
   so an AppVM's QEMU is the invoking non-root user. ADR-035 §5 has an AppVM's
   QEMU binding a socket inside a directory the netVM's QEMU owns, which is that
   ADR's own open *Socket permissions* dependency.
5. **`CONFIG_IP_PNP=y`**, with `_DHCP`, `_BOOTP` and `_RARP` all `=y`, in
   `~/katmate-kernels/config-katmate-microvm-amd64-6.12.87` — header line checked
   first, `Linux/x86 6.12.87`, per the invariant below. `CONFIG_IKCONFIG` is
   **not set**, so this is a reading of the config file and **not** of the image.
   Two bounds, neither resolved: the config's mtime is about six weeks *newer*
   than the vmlinuz beside it, and **no `.provenance` sidecar exists for that
   image on the Acer** — the unwitnessed pairing ADR-034 was written to close,
   and it is not closed here.

**No answer contradicted the draft**, so no halt was taken on one. The single
numeric discrepancy is ADR-035 §5's *"roughly seventy"* characters of headroom
against a measured **80**; it is named in the write report and in #28, the draft
was **not** edited to fit the measurement, and whether the sentence changes is
the operator's ruling.

**Deliberately not done.** No change to `ARCHITECTURE.md` or
`SECURITY-MODEL.md` — ADR-035 says both must change, and both change at
acceptance, not at PROPOSED, because writing them now would describe a pool that
does not exist. No implementation of any kind: no template, no unit, no agent
code, no generator change. Nothing pushed.

**One check worth keeping.** The write pass verified its append by comparing
`grep -c -F '## ADR-'` against `grep -c '^## ADR-'` and requiring them equal —
34 and 34. That is the check that would have caught the July splice on the day it
landed, it costs one command, and it is now taken on every ADR append.

## This session (2026-09-01, second of two) — the sidecar travels, and the path it travels from does not resolve as root

Delegated session on the Acer, gating on MINIS. Implements what ADR-034's
acceptance note left outstanding: *"the sidecar does not travel"* and *"no image
metadata records provenance"*. Report: `~/adr034-travel-report.md`.

**What landed.** `kernel_provenance_check()` in `build/lib.sh`, called from
`foundation.sh`'s preflight; `KERNEL_PROVENANCE` in the step-10 metadata block;
the step-11 sidecar install; and the sidecar riding the `Makefile`'s kernel-copy
hop. A function rather than an inline block, deliberately: a sourced function can
be gated without running a build, and `make foundation` is not available as a
gate — it would drop the frozen foundation and every app layer below it to test a
preflight.

**What was gated, and what was not.** Eight arms against the real `lib.sh`,
sourced, with the fixture produced by running the committed tool rather than
hand-written: absent, matching, hash-mismatch, missing `KERNEL_SHA256`,
unreadable, `AUTOCONF_MATCH=no`, `IMAGE_MATCH=no`, and a record filed under a
different name. Plus the Makefile hop twice. **Step 10's field and step 11's
install are UNVERIFIED** — only a real `make foundation` exercises them.

**The session's most valuable result is a defect it did not go looking for.**
`KERNEL_SRC_DIR` derives from `$HOME`, and both scripts that read it require
root, so as root it resolves to a directory that does not exist. That is open
problem **#25**. It cost this session two rulings: the proposed source-side
asymmetry check was **deferred entirely** rather than written somewhere it could
not fire, and ADR-034 § A.3's orchestrator presence check is **blocked, not
deferred** — the ruling stands and is simply not implementable yet.

**The shape of that mistake is the lesson**, and it is in *Invariants & gotchas*:
a check that cannot fire reads exactly like a check that found nothing.

## This session (2026-09-01, first of two) — kernel provenance: the witness held, the tool was gated, and the gate found the defect

Five delegated sessions on the Acer, reaching MINIS over ssh, closing ADR-034
from DRAFT to Accepted. Reports outside the repository:
`~/adr034-pregate-report.md`, `~/adr034-tool-gate-report.md`,
`~/adr034-gate2-report.md`, `~/adr034-g8-report.md`,
`~/adr034-acceptance-report.md`.

**The witness held.** The MINIS kernel tree still carries
`include/config/auto.conf` from the 2026-07-01 build, unchanged in the 65 days
since, and it pairs to the archived config symbol-for-symbol. That is what the
whole ADR was racing: the evidence lives in the build tree and the next
reconfigure deletes it.

**The comparison had to be specified before it could be implemented.** The two
files disagree on order (3434 differing lines over the same 1718 symbols) and on
quoting (21 symbols, 86 lines), and on neither does any symbol carry a different
value. A tool implementing the draft schema line literally would have written
`AUTOCONF_MATCH=no` for a pairing recorded as identical three times. The ADR now
carries the comparison; the code does not define it alone.

**The gate found a defect a smoke test could not.** An early-exiting pipeline
consumer raced its producer and aborted with no diagnostic — 49/200 on MINIS,
1/40 on the Acer. The Acer smoke test had roughly a 97.5% chance of missing it
and did; the gate caught it because a gate runs the thing more than once. Fixed
by reading to end of input, 200/200 clean after, extracted value byte-identical
either side of the fix.

**Refutation was measured, not only confirmation.** A config differing in exactly
one symbol of 1718 produces `no` with exactly two fields moving, and the
symbol-set claim was closed in both directions against a control that yields
`yes`. That control matters: without it a `no` from the rig cannot be told from a
`no` caused by the rig.

**What was committed:** ADR-034 accepted with `tools/capture-kernel-provenance`
(sha256 `5b1f16c3823cf72defc1cca37d014d700a2681e04a3fc350dd4266a0e4c1df22`), the
ROADMAP and ARCHITECTURE reconciliation, and this entry. **What was not:** the
sidecar does not travel with the kernel and no image metadata records it. That is
the next commit and a separate session.

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

**Superseded 2026-08-28: ADR-033 is Accepted, and `N` is 16.** M2 was taken by
link-m3 and the operator has accepted the ADR; its status line now reads
`Accepted (2026-08-28)`. The paragraph above is left as written because it is
what this section published at the time, and because the condition it names —
*"`N` is not fixed until M2 is taken"* — was met rather than abandoned.

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

### link-m3 (2026-08-28) — no knee: the loop is saturated at one link and shared from there

**This subsection is dated four days after the heading above it.** The parent
heading reads *2026-08-24* because that is when link-m1 and link-m2 ran; link-m3
ran on **2026-08-28** and is filed here because it is the same arc's third
session, not because it shares their date. Read the measurement date off this
line, not off the section heading.

Brief `~/link-m3-brief.md`, report `~/link-m3-report.md`. **No commits by that
session and no tracked file edited** — it measured and reported; this entry is
the record, written separately, on the division the arc has kept throughout.

**M2 is measured, and the result is not the one ADR-033 anticipated.** The ADR
asks where one event loop stops keeping up as active links are added. It does not
stop anywhere in the range that starts: it is **already saturated with one link**,
and every further link is served out of the same, already-full core.

- **There is no knee, because the loop is at its ceiling from `N`=1.** The event
  loop thread sits at **99.6 %** of one core with a single active link and at
  **98.7–99.6 %** across all eighteen 60 s windows, while delivered load rises
  from ~174 000 to ~316 000 frames/s as `N` goes 1 → 30. Individually, and never
  averaged: `N`=1 → 176 646 · 173 671 · 173 668 frames/s; `N`=2 → 222 899 ·
  223 798 · 226 366; `N`=4 → 261 670 · 258 731 · 259 001; `N`=8 → 280 687 ·
  279 936 · 283 463; `N`=16 → 302 994 · 302 921 · 295 716; `N`=30 → 317 385 ·
  315 851 · 313 888. **The loop does not break down under link count — it is
  shared, and the degradation is continuous.** What stops scaling is throughput
  *per link*: ~174 000 frames/s on one, about 10 600 each on thirty.
- **Zero loss, in all eighteen runs.** `gen_ok` equals `guest_pkts` as identical
  integers, link by link and repetition by repetition; guest `rx_bytes` equals
  generator `bytes_ok` exactly (`N`=2: `20350147882` against `20350147882`).
  `rx_errs=0` and `rx_fifo=0` throughout, and `tx_pkts=0` — the guest transmitted
  nothing.
- **The refusal reaches the sender as `EAGAIN`**, one errno wide, on every socket
  of every run — never as a frame accepted and then dropped. **It falls
  monotonically with `N`**, 69.3 M → 31.9 M in absolute count and ≈87 % → ≈63 %
  of attempts, consistent across all three repetitions at every point. That is
  the opposite of a rise, and it follows from the line above: as `N` grows the
  loop delivers more frames per second in total, so more of the generator's
  attempts find room.
- **Per-interface counts do not diverge.** At `N`=30 the thirty links span
  **7 frames in 634 765** (repetition 1); repetitions 2 and 3 span **2** and
  **1**. The worst relative spread anywhere in the sweep is **0.054 %**, at
  `N`=4. **The bound, which is the report's own:** the generator is strictly
  round-robin, so offered load is exactly equal per link by construction — what
  is measured is the loop's evenness *given equal offering*, and not its
  behaviour when one link offers far more than another, which was not measured.
- **`N`=30 starts and 31 refuses**, *"PCI: no slot/function available for
  virtio-net-pci"* naming `netdev=n30`, byte-identical across five observations,
  under KVM with a booting guest that enumerated all thirty interfaces. So the
  ceiling is **PCI topology** — not the accelerator, not the guest. This
  reproduces link-m1 § 20.1 on a different footing; that session found it under
  TCG on a machine paused at reset. **It is not netVM's ceiling** (see
  § *Next steps*).
- **Thread count is 4 at every `N`, idle and under load alike**, sampled at
  t+5 s, t+30 s and t+55 s inside every window and never varying. link-m1
  measured **3** at every idle `N`; that was TCG on a machine paused at reset,
  and the fourth thread here is the vCPU. **A `dgram` backend adds no thread**,
  which is link-m1 § 11's idle finding holding under load.

**Whether these are the subject's numbers or the generator's, and why it is the
subject.** The criterion was fixed in Part 1 before the data existed: well under
the generator's proven ceiling of 431 046 frames/s means the subject, approaching
it means the generator. The highest aggregate, 317 385 frames/s, is **73.6 %** of
that ceiling — *not* comfortably clear of it, and the report does not pretend
otherwise. It concludes **the subject**, on three grounds worth carrying rather
than just the conclusion: 31.9 M refusals mean the subject's socket queues were
**full**, which a generator-limited run cannot produce — the ceiling run itself
had **zero** errors; the loop is at ~99 % of one core, and no extra offered load
makes a thread already at 100 % drain faster; and where the ceiling run had its
sink at 67 % of a core with no refusals, this has the loop at 99 % with refusals
in the tens of millions. The residual is named as a limit of the apparatus: a
measurement wanting to push *past* this point needs more offered load than one
generator core can produce.

**The instrument is not the one the ADR names, and that must be visible to
anyone reading the gate as discharged.** ADR-033's *Remaining gate* sentence
specifies **netVM's own `utime`** watched for the knee. This session measured a
**standalone QEMU of the same shape** — `-machine q35,accel=kvm -cpu host -smp 1`,
read out of `net-sys.con` rather than invented — because netVM carries no `dgram`
device today and giving it one would *be* the pool that `N` was not yet fixed
for. The substitution was the brief's, stated openly in it.

**Conditions, which differ from link-m1's and link-m2's and are not
interchangeable with them:**

- **netVM was DOWN for the whole session.** MINIS had rebooted on 2026-08-25 and
  netVM had not been started since; the session found it so, raised it as a
  blocking divergence and halted, and the operator ruled that it not be started —
  it is not the subject, and an idle machine is a cleaner laboratory. The
  subsection above (*"Every measurement was taken unprivileged"*) says netVM was
  **up and untouched throughout both**; that statement is true of link-m1 and
  link-m2 and is **not** extended to link-m3. What link-m3 can evidence instead:
  no KatMate unit was started, stopped or reconfigured, the unit's state was read
  and not changed, and nothing under `/etc/katmate/`, `/var/lib/katmate/` or
  `/run/katmate/` was read or written.
- **The MINIS host kernel had moved**, `7.1.8-hardened1-2-hardened` →
  `7.1.9-hardened1-1-hardened`. The AF_UNIX datagram path is kernel code, so
  **these figures are this kernel's and are not directly comparable with
  link-m1's or link-m2's.**
- **The accelerator was KVM**, on the operator's ruling and against link-m1's and
  link-m2's TCG: netVM runs on KVM, the subject is netVM's shape, and under TCG a
  knee could have been the guest's ceiling rather than the loop's — measuring the
  wrong thing without showing it. `/dev/kvm` opened unprivileged; a silent TCG
  fallback was forbidden and was not needed.
- **No `sudo` anywhere**, as in both earlier sessions. An unprivileged user opened
  `/dev/kvm`, ran eighteen 60 s KVM guests, bound up to thirty AF_UNIX datagram
  sockets per run, and built a `cpio` carrying a `/dev/console` node via the
  kernel tree's own `gen_init_cpio`.

**What the session did not measure, and therefore does not claim:** Part 3 was
skipped, there being no knee to control against, so nothing is claimed about what
idle backends cost alongside an active one; nothing above `N`=30 or between the
points run; no per-link cost and no recommended value; nothing at other frame
sizes, the sweep being 1514-byte frames only; and **whether QEMU-as-sender retries
or discards on `EAGAIN`**, which ADR-033 already carries as open and which no
`strace` in this session touched.

## This session (2026-08-22) — the stop path's first execution, H1 and G6, and every part-2 gate measured

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

## This session (2026-08-21) — G5 and H3: the validator reports a duplicate `nic` label and a forbidden key as errors, not warnings

Delegated measurement session on the Acer, reaching MINIS over ssh. **No commits,
and no tracked file edited** — the session observed and reported. Brief:
`~/3a2-g5h3-brief.md`; report: `~/3a2-g5h3-report.md`. This entry was written by a
separate recording session (`~/3a2-g5h3-record-brief.md`,
`~/3a2-g5h3-record-report.md`), on the same division as 2026-08-19: the session
that measures does not also rule, and the session that rules does not also write
the record.

**The operator has ruled G5 and H3 PASSED**, on the row-by-row observations in
`~/3a2-g5h3-report.md` § 4. That report writes no verdict; it states which of
S3.5's named observations were seen and which were not.

Neither gate starts a VM, reads `/sys` or needs root. The subject is
`tools/validate-properties.fish` and its exit status, and nothing else was
touched.

### The fixtures are the real T1 files, and that is measured rather than assumed

Both gates ran against fixtures built from the live `netvm.toml` and
`app_web.toml`, not from TOML composed for the occasion, so the only thing
differing between a fixture and a valid file is the thing under test. **Hash
identity was confirmed across three copies** — the Acer tree's
`local/etc/katmate/vm/`, the MINIS build copy, and the installed
`/etc/katmate/vm/` — and the validator that ran on MINIS is byte-identical to the
one in the repository (`f05e111a…`). That is the rsync-then-cargo trap checked by
hash instead of by mtime.

Delivered by `scp` to **`/tmp/g5h3/` on MINIS, a tmpfs**, never under
`/etc/katmate/`: a fixture written there would be a claim about tier. **One
directory per gate**, because G5's rule is cross-file and H3's `class = app`
fixture would otherwise trip it as well, leaving the two gates measuring one error
between them. Each gate was run **twice, in two shells** — the exit status read
once as bash `$?` and once as fish `$status`, in separate ssh invocations —
identical output and identical status every time.

### G5, in one run

`NAPAKA: podvojena 'nic' oznaka 'uplink0': isto oznako zahteva že …/netvm2.toml`
— the severity word is the validator's own `NAPAKA` (*error*), not `opozorilo`
(*warning*), and the tally is **`skupaj: 1 napak, 0 opozoril`**. The cross-file
branch printed affirmatively — **`pravila čez datoteke: ovrednotena nad 2
datotekami`** — so the rule was evaluated over a set the validator knew to be
complete, which is the whole reason ADR-032 §4 requires the directory form. Exit
**1, not 2**: a 2 would have measured nothing about the rule and meant only that
the validator had been called wrongly.

### H3, in one run

Two `NAPAKA` lines, one per fixture — `prepovedan ključ pri class=app: 'nic'` and
`prepovedan ključ pri class=sys: 'persistence'` — tally **`skupaj: 2 napak`**,
exit **1**. **Neither forbidden key was reported as a warning**, which is the
failure mode the row is built around. The `persistence` value used is a *valid*
enum member, so what fired is the forbidden-key rule alone and not a type error
wearing its name.

### The control run is what makes H3's single warning unambiguous

An unauthorised addition by the measuring session (its report § 6.1): a third
directory holding both real T1 files **unmodified**, validated in the same run.
It exits **0** with `0 napak, 1 opozoril`.

That one warning is the `app_web` *web*-manifest-without-network line this file
already records under *Next steps* as true and deliberately not silenced — and
because it appears **identically over the unmodified pair**, it is demonstrably a
property of the base file rather than of H3's injected `nic` key. Without the
control, H3's tally `2 napak, 1 opozoril` would have left that warning's owner
open, and *"a forbidden key fails validation, not warns"* is exactly the row a
loose warning would have muddied.

### netVM was not touched

PID **706658**, `PPID 1`, `NRestarts=0`, the same `ExecMainStartTimestamp` at the
start and at the end of the session — the process the 2026-08-19 gate run left
behind, at 2 d 8 h. No unit was started or stopped, no LV activated, nothing
written under `/etc/katmate/`, `/var/lib/katmate/`, `/usr/lib/katmate/` or
`/run/katmate/`; the installed T1 pair still carries its 2026-08-11 mtimes.
**The stop-path measurement G6 and H1 are waiting for is unconsumed.** Sleep
targets remain unmasked.

**Consumed 2026-08-22, and the sentence above is superseded** — appended rather
than rewritten, because it records what was true when this session ended. The
stop was executed on 2026-08-22 at 08:26, H1 at 08:29 and G6 at 08:51, and
netVM was restarted at 08:51:56 as `MainPID 2114876`. Sleep targets are still
unmasked. See the 2026-08-22 entry above.

## This session (2026-08-19, second of two) — the gate run: G1 and G4 pass, and a VM starts from a unit for the first time

Delegated measurement session on the Acer, reaching MINIS over ssh; phase 3 of
the day. **No commits, and no tracked file edited** — the session measured and
reported, nothing else. Brief: `~/3a2-g1-brief.md`; report: `~/3a2-g1-report.md`.
This entry was written by a separate recording session
(`~/3a2-g1-record-brief.md`, `~/3a2-g1-record-report.md`), on the 2026-08-17
reasoning applied one turn further: the session that measures does not also rule,
and the session that rules does not also write the record.

**The operator has ruled G1 and G4 PASSED**, on the observations in
`~/3a2-g1-report.md` §§ 3–6. The report itself writes no verdict; it states which
of S3.5's named observations were seen and which were not, and leaves the ruling
where it belongs.

### The first VM started from a unit in this project

`systemctl start katmate-sys-driver@netvm.service`, 15:26:19 CEST. QEMU is
**PID 706658**, **`PPID 1`**, in its own process group and session, named by
`Main PID:`, and the unit's cgroup holds it **and nothing else** — parented by
the unit rather than by a shell, read four independent ways (`systemd-cgls`, the
cgroup's `cgroup.procs`, `/proc/706658/cgroup`, `ps`). The three
`ExecStartPre=` ran in the template's order — `katmate-check-image`,
`katmate-activate-lvs`, `katmate-generate-env` — each `0/SUCCESS` and each naming
itself in its own diagnostic, and **`ExecStart=` was reached after them**. The
guest booted through to `graphical.target`; the passed-through RTL8125 came up
**`Link is Up - 1Gbps/Full`** at t+7.46 s, and MAC **`38:05:25:34:7C:47`**
answered an ARP scan at lease `10.3.1.103`, `REACHABLE`. No ping was issued, per
the invariant.

This closes the 2026-08-17 entry's *"**No VM has been started from a unit**"*,
which was that entry's one thing not yet true.

**`net-sys.con` was not invoked** — and that is **derived, not observed**: the
report's §7 records the session's complete set of state-changing commands (two
`systemctl start`, one no-op `reset-failed`, one `nmap -sn`), no launcher
invocation is among them, and a `bash net-sys.con` could not have produced
`PPID 1` inside the unit's cgroup. The distinction is kept because the report
never names the file.

### The read-back's first execution

`6ef40ac` gave `katmate-generate-env` a read-back that had never executed as part
of the executable. It executed here, and this is the line:

> `[katmate-generate-env] projection written: /run/katmate/vm/netvm.env (profile sys-driver asserted and derived, 12 keys)`

**N = 12**, and the twelve `KM_*` assignments were **counted independently on
disk** by the session rather than read off that line — the read-back's own
equality check is the executable checking its own arithmetic, so a count made by
a different tool is what turns N into a measurement. `ExecStart=` was reached
afterwards. *"asserted and derived"* is the rest of the same line: the profile
the unit name asserts and the profile `f(class, netvm, nic)` derives are equal,
so ADR-032 §6's mismatch refusal did not fire either.

**The read-back is half-settled, and it is said in those words.** Observation 1 —
a start whose projection is complete reaches `ExecStart=` — is now measured.
**Observation 2 — a projection missing a required key refused by name, with exit
1 and not 2 — remains unmeasured.** It is an injection, it belongs to G6/H1, and
nothing was injected in this run.

### G4, in the same start

Not a second start: every G4 observation comes from PID 706658, the process G1's
observations come from. `-nodefaults` (argv 3), `-no-user-config` (argv 4) and
`-monitor none` (argv 19–20) read from `/proc/706658/cmdline`. Two design claims
measured live for the first time beside them: **`-append` survived as one argv
element** (`root=/dev/vda rw console=ttyS0`, which the guest read back as its
whole command line), so the braced `${}` interpolation at a fixed position
behaved as ADR-030 §3 requires and no value became additional arguments; and
**`-sandbox on,…` is the last argv element**, so nothing was appended after it
that could have overridden it. Under those flags the guest kept its console, its
disk (`vm_sys_netvm` went `-wi-a-----` → `-wi-ao----`) and its uplink, and the
RTC — the other candidate `-nodefaults` might have removed — produced no
complaint anywhere in the boot.

### What the run did not exercise, and is therefore not claimed

- **`katmate-activate-lvs` never ran against an inactive LV.** `vm_sys_netvm` is
  **linear**, carries no skip-activation `k` flag and was already active at host
  boot, so the second preflight was measured succeeding and being idempotent on
  an already-active LV. The template's comment about an RO-frozen thin LV keeping
  `k` permanently is true of the AppVM thin volumes, not of this one.
- **No in-guest observation at all.** That `netvm-agent.service` started is a line
  the guest's own systemd printed to the console; that the agent **answers** on
  vsock port 1025 is untested. WireGuard/ProtonVPN bring-up, the DNS-leak policy
  and the internal-segment peer are unchanged and unverified.
- **No stop.** The unit's stop behaviour (`KillMode=control-group`,
  `TimeoutStopSec=30s`, SIGTERM with no graceful guest shutdown) is
  **UNVERIFIED**; it first executes at the next `systemctl stop`.
- **`User=` is empty and QEMU runs as uid 0.** Nothing about the C-gate remainder
  moved (open problem #17). A passing G1 is not evidence for C1.

### H1's recipe is broken by this state

S3.5's H1 injection — `lvchange -an vg0/vm_sys_netvm` — **cannot run** while
706658 holds the LV open, and stopping CID 3 is an ask-first action. The order is
therefore: ask, stop the unit, confirm the LV drops to `-wi-a-----`, then inject.
**The alternative injection is unaffected:** pointing T2's `NETVM_LV` at a
nonexistent LV changes no LV state at all, and is the cheaper route.

### Two MACs for one segment, until the `.con` files go

`net-sys.con:27` still hands QEMU the authored `52:54:0a:64:01:01`, while the
unit path derives and emits `52:54:00:21:b2:08`. **The same internal p2p segment
now has two MACs, depending on which launcher starts netVM.** Nothing is due
before G3 — the `.con` deletion is 3a's last commit and this dies with it — but
it is recorded so that deletion is not the first time anyone notices.

### Three published statements this run contradicted, corrected in the same pass

The internal MAC (three sites: the *Live state* value, the *Invariants* body
sentence, and the *Pending (2026-08-09)* note, which is no longer pending), the
memlock invariant's *"the only path"*, and the getty prediction under
*Next steps*. Each is corrected in place and dated, and the superseded wording is
kept where the file's habit is to record that something was published before it
was true.

### The machine is left with netVM running

706658 is alive, `NRestarts=0`, holding `/dev/vg0/vm_sys_netvm` and the RTL8125
at `0000:01:00.0`; **killing it takes the host's guests off the network.**
`/run/katmate/` holds exactly two files — `nics/uplink0` and `vm/netvm.env`, both
`root:root 0644` in `root:root 0755` directories. **Sleep targets are not
masked** and were not masked by that session: no build is running, so the `jbd2`
hazard is absent, but a host suspend now would suspend a running netVM.

## This session (2026-08-19, first of two) — the A′ correction: the projection becomes optional to systemd and the refusal moves into the generator

Delegated implementation session on the Acer, phase 2 of the day. Six commits,
all signed. Brief: `~/3a2-phase2-brief.md`; report: `~/3a2-phase2-report.md`.
Phase 1 of the same day ran E1c on MINIS and is reported separately in
`~/3a2-e1c-report.md`. **No gate was run and no VM was started** — deliberately,
on the 2026-08-17 reasoning that the session writing a fix is the wrong one to
judge it.

### What E1c settled

E1c measured on MINIS, systemd 261, `Type=simple`, on a `/run` where
`/run/katmate` did not yet exist: one start of a probe carrying no KatMate
content produced `PRE_SEES=[]` at the `ExecStartPre=` read and
`PROBE_RESULT=[42]` at the `ExecStart=` read, `Result=success`,
`ExecMainStatus=0`. The two reads share a journal timestamp and are separable
only by PID. The first is the state E1a could not observe — the environment file
absent at the first read, absorbed by a leading `-` rather than fatal; the second
is the same re-read E1a did measure, now on a file that did not exist when the
unit started.

**The ruling is A′:** candidate A kept, its transcription corrected. Candidate B
is rejected, with its reasons on the record in ADR-030's 2026-08-19 revision
note. E1's `Type=oneshot` caveat is retired with the same measurement.

### What changed

- **ADR-030 gained the 2026-08-19 revision note** (`71e85b9`), committed first,
  because the unit comment and the generator header both cite it by date. The
  2026-08-17 note stands untouched: append-only.
- **`katmate-sys-driver@.service`** — `EnvironmentFile=` is now
  `EnvironmentFile=-/run/katmate/vm/%i.env` (`c19cfec`), and the comment above it
  no longer cites E1 for a property E1 did not measure (`64b345e`). Two commits,
  because one is behaviour and one is a wrong statement.
- **`katmate-generate-env`** — its header carried the same over-reading
  (`5fc510b`), and it now **reads back its own published output before exiting**
  (`6ef40ac`): the file must exist and be non-empty, the count of `KM_*`
  assignments on disk must equal the number of keys the run emitted, and every
  key the derived profile requires must be present. Read as text, never sourced.

**The `-` is not a fail-open, and this is the part to carry forward.** It removes
an enforcement point from systemd's environment loader; the enforcement moves to
the executable that owns the input (ADR-032 §2). The only path that can now reach
`ExecStart=` with no projection is the generator exiting 0 without having
published one, and the read-back is what closes it.

### The read-back is UNVERIFIED

It has never run as part of the executable. What was run on the Acer:
`shellcheck -x` clean, `bash -n` clean, `git diff --summary` showing no mode
change — all three static, none of them evidence of behaviour — plus an
isolated scratchpad harness over a copy of the block, which is not the
executable either. It first executes at the next `katmate-generate-env` run,
which is the next session's G1. The pair of observations that would settle it:
a start whose projection is complete reaches `ExecStart=`, and a projection
missing one required key is refused by name, with exit 1 and not 2.

### G1 was executed and FAILED; the template is still UNVERIFIED in full

**Superseded 2026-08-19 by the gate run** (the entry above): G1 was re-run after
the A′ correction and passed, and *Next steps* item 3 now withdraws *"UNVERIFIED
in full"*. This heading is what that session recorded and is kept as such.

Both halves were true when written and they were not in tension, which is why
*Next steps* item 3 stated them together. G1 ran on 2026-08-17 and failed **above**
`ExecStart=` — the environment-file load, before the generator was spawned — so
nothing in the transcription of `net-sys.con` was exercised. The gate criteria
stay in `~/3a2-report.md` § S3.5 and are deliberately not copied here.

### The operator's own commits of the same day

Four, and they are his, not this session's: `7fcba02` recorded *Dev access to
MINIS* in *Live state* (the `host` account, the fish login shell, and why a bash
snippet has to arrive on stdin); `26cecf0` routed delegated sessions to that
entry from `CLAUDE.md` before the first remote command; `5967a05` normalised the
2026-08-17 revision note's heading to the parenthesis form; `62b17d6` made
en_US explicit for a delegated session's chat and report, not only for the
repository.

## This session (2026-08-17) — 3a part 2, second half: the control layer exists as code, and nothing has started a VM yet

Delegated implementation session on the Acer, reaching MINIS over ssh. Six
commits, all signed (`98a6ff2`, `a83c2f5`, `2a23473`, `5265b62`, `b786e4a`,
`80f5f5c`). Report: `~/3a2-report.md`, session-2 part. **Closed before the gates,
deliberately** — see the end of this entry.

### What exists now

- **Five T4 executables at `host/usr/lib/katmate/`**, installed to
  `/usr/lib/katmate/` on MINIS: `katmate-check-waypipe`, `katmate-check-image`,
  `katmate-activate-lvs`, `katmate-generate-env`, `katmate-publish-nics`. One
  executable per check, none taking a mode argument, all `katmate-<verb>-<noun>`.
  Two exit codes: **1 = the check failed, 2 = it was called wrongly** — a caller
  must not read non-zero as uniformly invalid.
- **`katmate-lib.sh`**, sourced and not executed, holding the canonical paths, the
  diagnostic style and the T1/T2 readers. It carries **no policy**: the profile
  function lives only in `katmate-generate-env`, because ADR-032 §2 allows exactly
  one path to a profile.
- **Two units at `host/usr/lib/systemd/system/`**, installed on MINIS and
  **neither enabled**: `katmate-publish-nics.service` (oneshot,
  `RemainAfterExit`, empty capability bounding set, only `/run` writable) and
  `katmate-sys-driver@.service`.
- **`/run/katmate/nics/uplink0` is published by its own unit**, not by hand:
  `uplink0 -> 0000:01:00.0 (0x10ec:0x8125)`, claimed by `netvm`.

### The one thing that is not yet true

**No VM has been started from a unit.** `katmate-sys-driver@.service` is
**UNVERIFIED in full**; `systemd-analyze verify` passes on it, and that is a
parse, not a start. Everything in the ExecStartPre chain has been run by hand and
observed — the projection, the LV activation from a genuinely inactive LV, the
profile-mismatch and stale-label refusals — but the chain has never run *as* a
chain, under systemd, with QEMU after it.

### The label mapping is answered by counting, not by a scheme

`katmate-publish-nics` takes labels from **T1** and devices from
`/sys/bus/pci/drivers/vfio-pci/`, and publishes **only where the pairing is
forced: one label in use, one device bound.** Anything else refuses and names the
deferred question. A hardcoded mapping was rejected twice over: it would put a
host inventory fact into a release-owned file, and it would settle the durable
descriptor by accident in the one place `HOST-CONFIG.md` §3 says it must be
**measured, not chosen**.

### Two defects found in this session's own code, both by checks rather than by review

- **`shellcheck` SC2318.** In bash 5.3 every right-hand side of a single
  `local a=… b="$a"` is expanded before any assignment takes effect, so the
  projection would have been written to `/run/katmate/` instead of
  `/run/katmate/vm/` — a plausible file at the wrong path, which no exit-code test
  would have caught.
- **A refusal left the previous projection standing.** Measured, not reasoned.
  Harmless to systemd, which never reaches `ExecStart=` when an `ExecStartPre=`
  fails, but a complete and readable *wrong* file in `/run`: ADR-030 §8's "nothing
  stale survives" is a property of every exit path. Moving the removal to the top
  then exposed a second hazard — composing the path before validating `%i` would
  have made an `rm -f` as uid 0 on an attacker-supplied name — closed in the same
  edit and both re-measured.

### The schema now has two implementations, and that is a standing risk

`tools/validate-properties.fish` (fish, developer-side, not installed on any host)
and `katmate-generate-env` (bash, on the start path) both enforce the T1 schema.
The second exists because ADR-032 §3 requires a forbidden key to be rejected *at
parse*, and parse-at-start happens on the host. The split is **structural rules in
the executable, semantic warnings in the validator** — but they must not disagree,
which is the discipline ADR-015 states about itself. Nothing yet measures that
they agree; a fixture both must reject is the obvious check and belongs with
G5/H3.

### Why this session stopped before the gates

Not budget alone. A gate is passed by observation quoted verbatim, so the six are
output-heavy by contract; G1 is the first unit start of a VM on this host and its
failure modes (`LimitMEMLOCK`, the serial chardev, `-nodefaults` removing
something the guest needs) each carry a diagnosis cycle. And the session that
wrote the template is the wrong one to judge it — the risk is not running out
mid-gate but reading one's own output generously. The per-gate preconditions, what
to observe and what counts as failing are in the report, § S3.5.

## This session (2026-08-11) — 3a part 2, first half: the `trap` relocation is verified in both directions, and the host has T1

Delegated implementation session on the Acer, reaching MINIS over ssh — one
session, two machines, so *never edit on MINIS* follows from the topology rather
than from discipline: the session had no editor there. **Closed at the §2.3 / §3
boundary by operator decision**, because §2.3 is a complete measurement and §3
is new work with its own risk. Three commits, all signed (`6fd9821`, `d4224fb`,
`703befe`). Report: `~/3a2-report.md`.

The read pass **halted with ten divergences** before any file was modified; an
eleventh was found during the work. All were ruled on, and two of them changed
what part 2 will ship (see *the privilege boundary*, below, and G1's split).

### What exists now

- **`/etc/katmate/vm/` is live** — both T1 files, `root:root 0644`, flat, one
  per VM (ADR-032 §7). **Copied, never authored**, verified by `cmp` and
  `sha256sum` against the staging tree, because a second authored copy is the
  drift ADR-032 exists to prevent. The validator passes over the directory with
  cross-file rules evaluated over a guaranteed-complete set of two.
- **The T1 staging tree is `local/etc/katmate/vm/` in the repository**, ignored
  via `.gitignore`, mirroring install paths inside itself so the install step
  stays a copy. It is **not** under `host/`: in `host/` the path asserts what
  ships, and T1 is user-authored by definition. `docs/HOST-CONFIG.md` records
  the requirement, both paths, and that build-order step 6 replaces the
  hand-copy with installer provisioning.
- **`/var/lib/katmate/netvm/` is live** with `vmlinuz`, `initrd.img` and
  `netvm.meta`, written by `netvm.sh` step 11 on a real build. This was the
  precondition G1 was waiting on.
- **`/var/lib/katmate/kernels/` exists** and holds the shared microVM kernel —
  **placed by hand.** `build/foundation.sh` gained the step that installs it
  (`d4224fb`, with `KATMATE_KERNELS_DIR` in `config.sh` so the path is stated
  once), and **the script was not run.** That step is **UNVERIFIED** and first
  executes at the next foundation rebuild; the hand-placed file is not evidence
  for it.

### The one thing this session was convened to measure

**The `netvm.sh` `trap - EXIT` relocation is VERIFIED, in both directions** —
part 1 carried it as the single unverified change. Injected from outside the
script, never by editing it: run 1 an invalid `DEBIAN_MIRROR` (fails in step 2,
`netvm_cleanup` **removed** the LV), run 2 `chattr +i /var/lib/katmate` (step 11
`install -d` returns EPERM even as root, the LV **stood**, and the rollback was
provably silent). Run 3 was clean, so **step 11 is verified in the writing
direction too**, its payload hash-identical to the `out/netvm/` export. Three
host reboots, each an operator gate.

**The reading rule made the measurement legible, and was ruled before run 2's
result was known:** an absent LV is not by itself evidence against the
relocation. A steps-1–10 failure and a step-11 failure produce the same `lvs`
output and are told apart only by *where the run failed*, so a repeat after a
mirror flake is not retrying for a desired result — no measurement was produced.
A repeat after a step-11 result would be, and was refused in advance.

Consequence for the brief: **"reboot before each run" is conditional, not
unconditional.** The condition is a held device — open count, or a `jbd2`
kthread on this LV's `dm-N` — and it was measured **absent** before run 2 and
**present** before run 3. A remedy with no condition to remedy is habit, not
caution; where the condition is present the reboot stands, and it stays an
operator gate because the root volume is LUKS and the passphrase is entered at
the machine.

### The privilege boundary in the `ExecStartPre=` chain became visible

ADR-032 §2 gives `katmate-check-image` "backing-chain and payload existence"
while also arguing for a cheapest-gate-first chain that runs before anything is
activated. Measured on MINIS as uid 1000: `lvs vg0` exits 5 on
`/dev/mapper/control` and the `vg0` lock, and membership of group `disk` does
not help. Both halves cannot hold. Ruled: `check-image` narrows to plain files
(kernel, initrd, `<image>.meta`) and **LV existence moves to
`katmate-activate-lvs`**, already `ExecStartPre=+`, where `lvchange -K -ay`
*is* the existence check. No third executable, no widened privileged set.
Written into ADR-032 as a revision note in the following session (`98a6ff2`).

### Corrections this session forced on documents

- **The netVM guest kernel is `6.12.101+deb13-amd64`**, not `6.12.96`. Runs 2
  and 3 took what trixie offers — the build is declarative, so this is the
  mechanism working, not a defect. Applied below; `docs/SESSIONS.md:1032` still
  names 6.12.96 and is deliberately **not** corrected, because dated session
  records are not rewritten.
- **`vm_personal_home` is present on MINIS**, against this file's claim that it
  was deleted 2026-08-02. Recorded where the claim is made, and **unresolved in
  either direction** — a session does not silently reconcile a document with the
  tree.
- **The T1 location moved** from `~/katmate-t1/` to `local/etc/katmate/vm/`, and
  the files are now also installed on MINIS.
- **The stuck-`jbd2` symptom became a test.** This file already described the
  symptom correctly twice, inside historical entries — but neither was a test,
  and nothing said that `mount` is not the condition. Run 2 produced an LV
  **unmounted yet open**, and run 3 produced a *successful* build whose
  filesystem came out `clean` while the device was *still* held. The test is now
  in *Invariants & gotchas* with both measurements behind it.

### What this session is evidence for

A destructive property was measured by injecting failure from **outside** the
script under test — no sabotage in the history, and no file edited on the
machine that would revert it. And the ADR was tested by trying to *implement*
it: a sentence in ADR-032 §2 that reads as one requirement turned out to be two,
which is the same finding class as G1 measuring two properties under one name.

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

## This session (2026-08-09, first of two) — step 3a ran as a gate and returned five holes; ADR-032 answers them

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

---

## This session (2026-08-06, first of two) — documentation hygiene before ADR-030; the archive boundary repaired

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

---

## This session (2026-08-03) — `network-online.target` never fires; HOST-CONFIG.md created; next session set

Short documentation session. One finding, one new document, one decision about
where the work goes next.

### The finding — a prediction wrong in kind, not degree

`tap-int0` host-side persistence was recorded 2026-07-20 as resolved, with a
note predicting that the `RequiredForOnline=yes` default would at worst *"slow
boot"*. Measured on MINIS 2026-08-02: it does not slow boot. It prevents
`network-online.target` from **ever** firing, silently.

`networkctl` reports `State: routable` alongside `Online state: offline` —
a pair that reads as healthy unless both lines are read together. The cause is
that every networkd-*managed* link is a carrier-less tap, while both actually
routable links are *unmanaged*. `systemd-timesyncd` consequently never polled
and logged nothing about it. Fixed in `/etc` with `[Link] RequiredForOnline=no`
on all six tap/bridge definitions — per-machine, not a repo artefact.

This is the same failure class as the `/proc`-remount finding from 08-02 and as
the assumed precondition that killed ADR-021: **a mechanism that quietly
consults the wrong object and returns a plausible answer.** Three instances in
two sessions is no longer a coincidence; it is the shape of this system's
characteristic bug.

### Constraint added to ADR-029

**VM units must not depend on `network-online.target`.** An AppVM's
connectivity arrives through netVM and NETCFG (ADR-023, ADR-025), never through
the host's networkd — and on this host that dependency is unsatisfiable in a
way that produces no diagnostic. A unit ordered `After=network-online.target`
would simply never start, with no error and no log line. Recorded here rather
than as an ADR-029 amendment; fold it into ADR-030's unit-shape section when
that is written.

### New document: `docs/HOST-CONFIG.md`

The finding did not fit anywhere. `OBSERVATIONS.md` routes it away explicitly —
its conventions state that the file holds external material only, and that
corrections to our own statements belong in the session record. But the
substance is not a session narrative either: it is a fact about host
configuration that lives in `/etc`, outside git, and that a fresh install would
not reproduce.

Six existing items share that shape — the uplink profile, the vfio binding,
mkinitcpio HOOKS, the greetd session entries, `outputs.conf`, the rofi
checkout. Enough to be a category, not noise.

The category's real name is **installer requirements discovered by running the
system**. `docs/HOST-CONFIG.md` is therefore an *input to ROADMAP build order
step 6*, not a log. Its governing convention: **every entry states its failure
mode**, and where the failure is silent, says so explicitly. An entry that only
says what to set is a note; an entry that says what breaks without it is a
requirement.

Four entries ship marked `[?]` — mkinitcpio HOOKS/MODULES, hugepages backing,
the greetd session path, the `sway-quiet` wrapper name. Under this project's own
evidentiary standard a `[?]` entry is not yet a requirement; it is a thing to
verify before it becomes one. They stay `[?]` deliberately.

### Next session decided: ADR-030 — what the daemon reads

ADR-029 settled the daemon's supervision model. What is missing next is not
more architecture about *what the daemon does*, but a specification of its
**input**, which does not exist anywhere:

1. **No `properties.toml` → QEMU argv mapping.** ADR-015 names this as its own
   justification ("not typed enough to map deterministically to QEMU
   arguments") and then does not specify the mapping. The `.con` scripts are
   the de facto specification: hand-written, one per VM.
2. **The schema lacks fields for most of what a launcher needs.** ADR-015 has
   `manifest`, `network`, `persistence`, `identity`, `disposable`, `cid`,
   `reset_on_shutdown`. `app_web.con` additionally requires the kernel path,
   `MEM`, `SMP`, three LV names, the delta path, sandbox flags, the waypipe
   version gate, the `lvchange -K -ay` ordering and the `-append` line. None of
   it is described as data anywhere.
3. **sysVMs have no schema, and the daemon must launch them.** ADR-015 covers
   AppVMs only and defers this by name: a `class` field (ADR-022 `Vm.class`)
   would be needed, and *"that is the launch daemon's business, not this
   ADR's"*. The deferral has arrived.

### ROADMAP gap, surfaced not fixed

**The launch daemon is not a numbered step in the build order.** Steps 1–5 run
foundation pipeline → `katmate-update` → netVM installer integration → default
AppVMs → installer integration. The daemon is implied by step 4 and named
nowhere. Either it is genuinely next and the build order does not say so, or
ADR-029 settled a decision ahead of its turn. ADR-030 should open by placing it.

---

## This session (2026-08-02, second of two) — ADR-029: systemd owns the VMM process; four constraints re-examined and gone

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

### Docs debt raised this session — CLOSED 2026-08-06

The earlier 2026-08-02 session (CID renumbering `app_web` 5 → 21, personalVM
deletion) is threaded through this file's live sections but **has no session
heading**. It is therefore invisible as a session while its consequences are
visible as state. Give it its own heading, or fold it in here — not left as is.

> **Closed 2026-08-06.** Written up as its own entry —
> *2026-08-02, first of two* — at the top of [docs/SESSIONS.md](docs/SESSIONS.md),
> explicitly marked as reconstructed rather than same-day.

---

## This session (2026-08-02, first of two) — CID renumbering applied; personalVM artefacts removed

> **Reconstructed 2026-08-06; not written on the day.** This session's
> consequences were threaded into `../state.md`'s living sections while the
> session itself never received a heading — it was therefore invisible as a
> session while fully visible as state. Flagged as docs debt in the second
> 2026-08-02 entry and closed here. The entry below is assembled from those
> sections and from `../ROADMAP.md`; it is not a same-day record and asserts
> nothing that was not already written down elsewhere.

### CID renumbering to the ADR-022 map — done

The renumbering carried from the 2026-07-14 session was applied:

- `app_web` **5 → 21** in `app_web.con` (line 25, with the band named in the
  comment).
- The normative band **4–8 → 20–99** in [ADR-015](DECISIONS.md#adr-015),
  [ADR-017](DECISIONS.md#adr-017) and `tools/validate-properties.fish`.
- `properties.toml` restricted to the **AppVM class**: a CID in 3–19 is a hard
  error, not a warning. sysVMs are not described by that schema.

**personalVM was not renumbered — it was deleted instead** (below). `20` is
therefore simply the lowest free fixed AppVM CID, reserved for nothing in
particular. netVM (3) is unchanged by the new map.

**The agents needed no change.** They know only host CID 2 and the peer CID
returned by `accept`; the map is host-side throughout. No instantiated
`properties.toml` existed at the time, so no instance file was touched.

### personalVM artefacts removed

`vm_personal_home` (40 G thin) deleted. The launcher and the qcow2 overlay had
already gone in the 2026-07-25 housekeeping pass, so this removed the last
pre-foundation artefact on MINIS.

Migration was considered and rejected: the old personalVM ran the
pre-foundation systemd-user / linear-root model, which nothing will boot again.
Migrating would have meant renumbering it and then rebuilding an artefact that
the v0.3 AppVM work regenerates from foundation + the `web` manifest anyway.

**The artefact is gone; the `personal` archetype
([ADR-014](DECISIONS.md#adr-014)) is not.** It returns as one of the default
AppVMs, with a CID allocated from 20–99 at that point.

---

## This session (2026-07-28) — C-gate defined and half-passed; vsock placement settled; indicator carriers closed

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

## This session (2026-07-27) — Sway deployed to MINIS, greetd swap done

Mechanical session. The Sway profile built on the Acer on 07-26 is now live on
MINIS, and greetd offers a session picker instead of one pinned command. No new
code; three empirical findings, all of which feed ADR-016 and ADR-026.

Sway 1.12 was purged and reinstalled clean — the machine carried a 1408-byte
generic skeleton config from March, unrelated to CYBRland. `pacman -Rs --print`
confirmed only `wlroots0.20` and `gnu-free-fonts` came with it; Hyprland uses
`aquamarine`, not wlroots, so the live session on tty1 was never at risk.

### Portability fixes to `desktop/`

The profile was written against the Acer and would not have started on MINIS:

| was | now |
|---|---|
| `/home/winterbox/…` ×6 | `$HOME/…` |
| `output eDP-1 { … }` | no output block; `include outputs.conf` |
| `"output": "eDP-1"` (waybar) | removed — bar draws on all outputs |
| `"eDP-1": [1,2,3,4]` (modules) | `"*": [1,2,3,4]` |
| `$rofi_scripts/screenshot/…` | `$HOME/.local/bin/km-shot` |
| `restartAudio` bind | removed — script exists on neither machine |

**Absence of an `output` block is a decision, not a debt.** A hardcoded output
name that does not match is *silently ignored* by sway, which is worse than no
block at all: it looks configured. Sway's default lays outputs out horizontally
in discovery order, which on MINIS came out correct (left/right as cabled).
This is the same failure shape as matching a NIC by interface name instead of
MAC (cf. `20-uplink.network`) — third instance of this pattern in the
project.
Per-machine geometry belongs in an installer-generated file.

### Findings

- **`include` tolerates a missing file.** `outputs.conf` did not exist and sway
  started without complaint. The installer therefore writes the file only when
  it has something to write; no empty placeholder is needed.
- **`$HOME` works in `set`.** Sway leaves undefined `$vars` as literal text and
  the shell expands them at `exec` time. Valid only in `exec` context — it
  would NOT work in `output … bg`, but that line is gone.
- **`--sessions <dir>` replaces the default, it does not merge.** Verified
  live: `hyprland-uwsm.desktop` did not leak in from
  `/usr/share/wayland-sessions/`. The anti-injection pattern holds against
  package upgrades.
- `$mod+Tab` (`focus next sibling`) parses and works — last `VERIFY` in the
  config closed.
- Neither `hyprctl`, `swaymsg` nor `sway --validate` works over SSH: no seat.
  `--validate` fails in the backend before it ever parses the config. Desktop
  work needs a physical console or a running session, full stop.

### greetd

`--cmd hyprland-quiet` removed; `/etc/greetd/sessions/` holds two entries,
`Exec=` pointing at wrappers under `/usr/local/bin` so no entry reaches the
compositor without `sway-session`'s Qt/GTK/XDG environment. `sway-quiet`
mirrors the existing `hyprland-quiet` (ANSI clear before handing over). The
`hyprland-uwsm` entry was deliberately not carried: uwsm wraps the session in
its own systemd-user scope and bypasses the wrapper by construction.

Picker verified live (F3). **Open problem #1 is closed.**

### Deployment shape

User files are symlinks out of `~/katmate-build/desktop/`; `/etc` and
`/usr/local/bin` files are copies, with reference copies committed back into
`desktop/greetd/` and `desktop/bin/`. `~/.config/sway/outputs.conf` is local
and ungitted by design — the wallpaper line lives there.

### Carried

- `desktop/` still needs a licence decision (derived from CYBRland, GPL-3.0).
- swayidle/swaylock still absent — `hypridle.conf` was never supplied.
- `~/.config/rofi/` on MINIS is a separate CYBRland checkout with its own
  `.git`. Two sources of truth for the rofi layer; not reconciled.
- MINIS `~/katmate-build/` carried a nested stale `katmate-os/` with a live
  `.git` whose work tree was the parent — removed. It was the reason
  `--exclude='katmate-os/'` sat in the standard rsync line; that exclude is
  now unnecessary and was dropped.

## This session (2026-07-26) — Sway profile built and live on Acer

First desktop-layer session. Hyprland/CYBRland ported to Sway from scratch on
the Acer; the profile now lives in git under `desktop/` where nothing of the
DE ever was. Sway is running as the default session via greetd/tuigreet.

No decision was recorded. ADR-016 revision and the indicator ADR are held back
deliberately — see "Gated on empirics" below.

### What was built

`desktop/` tree, new:

| file | note |
|---|---|
| `sway/config` | full port; `VERIFY` comments mark three uncertain points |
| `waybar/config-sway.jsonc` | parallel to `config.jsonc`; Hyprland untouched |
| `waybar/modules-sway.jsonc` | `sway/{workspaces,window,language}` |
| `waybar/style-sway.css` | `@import "style.css"` + `.focused` (sway) vs `.active` (hyprland) |
| `bin/sway-session` | env wrapper — sway config has no `env =` directive |
| `bin/km-shot` | grim/slurp + notification actions; replaces hyprshot |
| `bin/km-scratch` | sway scratchpad toggle; replaces pyprland and `toggle_scratchpad.sh` |
| `greetd/` | reference copies of `config.toml` + two `.desktop` entries |

User files are symlinked out of the repo (same anti-drift pattern as
`~/net-sys.con`); system files under `/etc` are copies, deployed by hand.

greetd was already tuigreet, pinned to one command by `--cmd hyprland-quiet`.
Removing that flag restored the session picker; the two `.desktop` entries were
moved from `/usr/share/wayland-sessions/` to `/etc/greetd/sessions/` so a
package upgrade cannot inject an entry that bypasses `sway-session`.

Three shared rofi scripts were made compositor-neutral rather than forked:
`powermenu` → `loginctl terminate-session`, `keybindings` → class at launch.
`wallpaper` was left alone: it targets `DP-2`, which exists on neither machine,
so it has never worked under Hyprland either.

### What the port cost

Dropped, because Sway has none of them: coloured glow (`shadow range 30,
render_power 5`), bevelled corners (`rounding 28, rounding_power 1.0` — a 45°
chamfer, not a radius), background blur (`size 6, passes 4`). Borders, gaps,
palette, fonts and terminal transparency transferred exactly. Animations were
already off upstream.

SwayFX evaluated and rejected: a fork needing a manual rebase per Sway release
(0.5 on 1.10.1, upstream at 1.12), and `scenefx` replaces the wlroots scene
graph rather than adding a render pass. Wrong shape for a TCB component.

The GUI is visibly faster. On the N4200 that is expected rather than
surprising — Hyprland was doing four blur passes over what was effectively the
whole desktop (kitty runs `background_opacity 0`), plus a shadow and a
non-rectangular window shape that defeats occlusion culling.

### Findings worth keeping

- **Sway has no per-window border colour.** `client.focused` is global. This
  does *not* block the domain indicator: inactive windows carry no visible
  border, so only the focused window's colour matters, and one global value
  set over IPC on each focus change is sufficient. Cost per frame: zero. The
  layer-shell overlay considered earlier is unnecessary.
- **Marks are host-set and unspoofable.** Settable only via IPC, drawn by the
  compositor. The strongest candidate carrier for a text-shaped indicator.
- **Per-window channels that a guest cannot reach**, all keyed on PID: border
  width, opacity, mark, workspace. `app_id` and window title are not among
  them and must never be used.
- **The transparency was never Hyprland's.** `active_opacity = 1` in
  `vars.conf`; the effect comes from kitty's `background_opacity 0`. It ports
  unchanged. What does not port is the blur *behind* it — which matters only
  over busy content, since both wallpapers measure near-black (mean RGB
  (11,14,20) and (10,8,10)).
- **Qubes solves the same problem by writing its own GUI daemon**
  (`qubes-gui-daemon` draws per-VM borders under X11). The Sway + IPC route is
  cheaper because Wayland already provides the input isolation Qubes had to
  build.

### Gated on empirics

Two facts remained untested at the time, and both fed the indicator decision:

1. does Sway accept `#RRGGBBAA` in `client.*`? (Hyprland's
   `col.inactive_border` was `#29BECC00`; the port approximates with opaque
   near-black)
2. does `show_marks` draw anything under `border pixel`, which has no
   titlebar? If not, marks need `default_border normal`.

ADR-016 revision and ADR-026 (indicator carriers) were deliberately not written
until these were gated. Writing them first would repeat the ADR-021 and
ADR-025 Path A failure mode: mechanism accepted, then found not to exist.

**Both were gated on 2026-07-27** — see *Next steps*.

### Carried

- `desktop/` needs a licence decision before it is useful to anyone else: the
  Sway config and `style-sway.css` are derived from CYBRland (GPL-3.0) and
  `README.md` declares no project licence.
- MINIS: no output block — resolved 2026-07-27 as a decision, not a debt.
- swayidle/swaylock deliberately absent — `hypridle.conf` was never supplied.
- `~/.config/rofi/scripts/wallpaper/wallpaper` still Hyprland-only.

## This session (2026-07-25) — doc drift sweep, ADR-004/024 propagation, MINIS housekeeping

Found that ADR-024 never reached `SECURITY-MODEL.md` or `ARCHITECTURE.md`: both
still claimed netVM had no SHUTDOWN opcode and no shutdown privilege, six days
after the opcode went live. Corrected, and `CAP_KILL` added to the agent's
recorded capability set. Recorded the underlying cause as a first-class
invariant — netVM is dbus-free by manifest, so bus-dependent systemd mechanisms
are *inert*, not merely unconfigured; this had already invalidated ADR-021's
shutdown path and ADR-025's Path A, and is the open precondition under the
DNS-leak policy. Rule now written down: gate the mechanism empirically before
accepting an ADR that depends on one.

Also: yesterday's `netvm.sh` cleanup fix existed only in the working tree while
`state.md` already called it resolved (committed, `47ece34`). `aio=threads`
landed in both launchers per ADR-004 — empirically `kernel.io_uring_disabled=1`,
not `2`, so only unprivileged QEMU was affected, which is why `app_web.con` broke
and root-launched `net-sys.con` did not. MINIS `~/` and `vg0` cleared of
pre-sysVM remnants.

Commits: `47ece34`, `894d7e3`, `c31dff7`, `e4afc40`.

## This session (2026-07-24) — netVM housekeeping closed; host boot pipeline recorded

Short mechanical session, deliberately cut before the Sway work so the netVM
track closes clean.

### `netvm.sh` — three fixes, one commit

- **Cleanup ordering.** `netvm_cleanup` ran `sync` before `umount_root`; a sync
  on a still-open mount does not settle jbd2. Reordered to umount → `sync` →
  `udevadm settle`.
- **`netvm_umount` added.** `lib.sh:umount_root` swallows failure
  (`2>/dev/null || true`), which is wrong here: a failed umount *is* the
  hot-jbd2 case the loud warning exists for. The local helper returns non-zero
  and says so. Step 10 uses it too, so under `set -e` an incompletely unmounted
  image no longer reports as built.
- **Unit aligned with ADR-025 Path B.** `ReadWritePaths=/etc/systemd/network /run`
  → `/run`. The agent programs rtnetlink directly; `networkctl reload` is inert
  without dbus (E1–E3), so the networkd fragment directory is never written and
  the E4 `tmpfiles.d` DAC line was never needed. The `CAP_NET_ADMIN` comment,
  which still described the dead Path A, was rewritten.
- **Executable bit restored** — `git update-index --chmod=+x build/netvm.sh`
  (`micro` strips it; commit `d6d9267`). Open problem #15 closed.

### What the review actually found

The "Harden `netvm.sh` cleanup" item had been carrying a prescription that could
not have worked (`sync` + `settle` + `sleep` *before* return — on failure the
script never reaches its unmount). The trap itself had existed since the ADR-021
build. The real defect was ordering, and it was three lines. Recorded because the
next stale next-steps entry will look just as authoritative as this one did.

### Documentation corrections

- **Open problem #12 re-aimed.** It read "the password hash in `netvm.sh` is
  invalid" and prescribed substituting a valid one. The debt is that the
  `usermod -p` line exists at all: step 6 locks root and then unlocks it in the
  next breath. Deliberate — the console is the only in-guest observation path
  while the agent has no RUN — but it is a release blocker beside #3 and #4, not
  a hash to correct. (#11 already recorded this correctly; #12 did not.)
- **Interface-name inconsistency resolved in favour of the MAC.** The uplink has
  been written up as `enp0s6`, `enp0s4` and `enp0s5` in different entries. The
  match is and always was on `MACAddress=38:05:25:34:7c:47`; the name is
  incidental and the `10-personal.network` / `Name=enp0s4` convention is void
  (it described the retired pet).
- **DNS-leak entry narrowed.** Override with `Domains=~.` is the stronger
  candidate, but `systemd-resolved` is deliberately not enabled and the image is
  dbus-free — so whether `.network` DNS settings do anything at all is an
  unverified mechanism precondition, the same class that killed ADR-021 shutdown
  and ADR-025 Path A. Probe before deciding; probing needs the console.

### Host boot pipeline (MINIS) — recorded, not decided

`minis_dela.md` documents work already carried out on the host: `linux` →
`linux-hardened` (ADR-004) and GRUB → systemd-boot (ADR-006) — implementation of
decisions already accepted and already ticked in `ROADMAP.md` — plus a UKI at
`/boot/efi/EFI/Linux/arch-linux-hardened.efi`, a `katmate` Plymouth theme
(graphical LUKS unlock + spinner) and a `splash-katmate.bmp` from `katmate-a.png`.
`mkinitcpio` HOOKS put `plymouth` before `encrypt` (otherwise the LUKS prompt is
not graphical) and add `kms`; MODULES carries `amdgpu vfio_pci vfio
vfio_iommu_type1`.

Two notes worth keeping. The `kms` hook is not only cosmetic — `ROADMAP.md` build
step 5 already lists it as a prerequisite for the Sway/installer desktop
integration. And the boot ends in Hyprland, not Sway: consistent with ADR-016's
build state (Sway is target and reference, only the Hyprland profile exists
today) and with the ARCHITECTURE.md release target (greetd + tuigreet → Sway,
Plymouth). Not a defect.

This covers Open problem #1 except the **greetd swap**, which remains open.

### Not done, deliberately

The "next steps" listed at the end of `minis_dela.md` — TPM2 auto-unlock,
Secure Boot, Measured Boot, PCR sealing, `systemd-cryptenroll`, signed UKI,
removal of the GRUB EFI entry, "zero console" boot — are that document's own
horizon, not this session's agenda. They are not in `ROADMAP.md`; they are
backlog candidates.

---

## This session (2026-07-23) — ADR-025 CLOSED: NETCFG live-gated; netvm-agent functionally complete

`handle_netcfg` was the last ERR stub in the agent; all three opcodes
(PING / NETCFG / SHUTDOWN) are now implemented and live-gated. Path B
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
ultimately replaced BY HAND (mount + install), not by a rebuild — see `../state.md`
debt #14.

Next architectural piece: the **launch daemon** (owns the graph; allocates CIDs
and `/32`s, orders `device_add` before NETCFG, refuses to tear down a VM with
live dependents). ADR-sized, thinking-on.

---

## This session (2026-07-21) — E-gate: NETCFG mechanism resolved, Path B

ADR-025's E1–E5 run live on `vm_sys_netvm` (root unlocked via offline chroot
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

---

## This session (2026-07-20) — ADR-025 NETCFG payload fixed (design); `net-sys.con` committed

The NETCFG wire contract ADR-023 left abstract is now fixed. **Wire:** fixed
binary layout, opcode `0x06`, count-prefixed bounded route array
(`route_count 1..=4`); no version byte (new shape → new registry value); byte
order deferred to `katmate-protocol::frame`. Locally-administered MAC check = structural uplink
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

### Housekeeping

`vm_sys_netvm` actually rebuilt from a clean `netvm.sh` today (dm-17
open-flag needed a host reboot first); acpid / dev-root / `ffc08537` remnants
gone only now, not 07-18. Stale `vm_tpl_net_root` + `vm_net_overlay.qcow2`
removed. `netvm.sh` export-block dedupe (`9149e17`).

---

## This session (2026-07-18) — netVM SHUTDOWN via agent; #10 closed (ADR-024)
Code + live session, split model: empirical + mechanical parts thinking-off,
ADR-024 authoring thinking-on. Closed Open problem #10 (netVM graceful shutdown)
— not by shipping dbus, but by returning SHUTDOWN to `netvm-agent`.
### The contradiction, not an oversight
The QMP `system_powerdown` path ADR-021 assumed was proven inert last session:
logind needs dbus, and the manifest deliberately omits it — ADR-021's OWN
exclusion. So ADR-021 rejected the dependency and kept the design that stands on
it: a contradiction, not a patchable gap. Fix = replace the shutdown model, not
add dbus.
### Empirical, not guessed (E1-E8, tabulated in ADR-024)
Eight live probes on the running `vm_sys_netvm` settled the mechanism: QMP/logind
inert; non-root `systemctl` has no bus; `/run/systemd/private` root-only; a
negative control (`nobody`, no CAP_KILL → EPERM) bounded the claim; and both root
`kill` and a `setpriv` non-root+CAP_KILL run gave the full graceful poweroff.
Winner: `kill(1, SIGRTMIN+4)` — systemd's documented signal for `poweroff.target`
— under one added capability, `CAP_KILL`. `CAP_SYS_BOOT` stayed rejected (not
graceful under systemd PID 1; also unlocks kexec); dbus/polkit/acpid stayed out.
Symmetry with vm-agent deepened rather than broke: both agents ask their own
PID 1 (vm-agent → INIT_SOCK → katmate-init; netvm-agent → SIGRTMIN+4 → systemd),
transport differing only by init system.
### Code + bake
`Op` gained `Shutdown` (0x05 now decodes; RUN/FILE* stay absent — boundary test
narrowed); `handle_shutdown` is reply-first then best-effort
`libc::kill(1, libc::SIGRTMIN()+4)` (SIGRTMIN is a runtime function under glibc,
not a constant); unit gained `CAP_KILL` (ambient+bounding); vm-agent's doc
comment (claimed netVM carries no SHUTDOWN) corrected. Committed `d609ada`
(code) + ADR-024/unit; ADR-021 status now points to ADR-024. Bake was a FULL
`netvm.sh` rebuild (unit changed — hand-bake would miss `CAP_KILL`), which also
erased the acpid + unlocked-root experiment remnants; root re-locked, manifest
clean. New stock kernel pulled in passing (KVER 6.12.95+deb13-amd64).
### Live gate — PASSED
`ping-client ping 3 → OK` (regression clean), then `ping-client shutdown 3 →
status=0x00 (OK)` with the console running the full stop to `EXT4-fs (vda):
re-mounted … ro` → `reboot: Power down`. Reply-first confirmed by the console
stopping `netvm-agent.service` mid-sequence — OK reached the wire before the
agent died. #10 closed.
### Snags worth remembering
- The `CAP_KILL` unit edit was first made in a non-authoritative tree, missing
  both the commit and MINIS — caught by `grep CAP_KILL` coming back empty on both
  machines; re-done on Acer. (Same class as last session's MINIS drift: edit only
  on Acer source-of-truth.)
- An `--amend` landed on the wrong HEAD (docs commit, not code commit); left as
  is since nothing was pushed. `netvm.sh` thus sits in the ADR-024 docs commit.
- A stale `/mnt/netvm-build` mount (pseudo-fs included) from an interrupted build
  held `vm_sys_netvm` open and blocked `lvremove`; `umount -R` cleared it.
- `netvm.sh` has a duplicated vmlinuz/initrd export block (harmless; cleanup).
### Next
NETCFG payload (ADR-023 impl) is now the only ERR-stub handler and gates the
AppVM internal network — live test first needs a `netcfg` subcommand in
`ping-client` (opcode 0x06 postdates the client).

---

## This session (2026-07-17) — netvm-agent LIVE-GATED; shutdown gap found

Code + live session, thinking off. Took `netvm-agent` from "compiles on Acer"
to "answers on the wire inside a booted netVM". The listener gate passed; a real
shutdown gap surfaced and was diagnosed to root cause.

Also: a long detour reconciling MINIS, which had drifted. `~/katmate-build/`
carried a stale git (behind origin by several sessions) whose "modified" flags
were an artifact of the old commit it compared against, not local edits — every
tracked file was either identical to Acer or older, never newer, so nothing was
orphaned (the "never edit on MINIS" invariant held). Resolved by rsync
(Acer→MINIS, `--delete` with explicit excludes: `.git/`, `target/`, `out/`,
`trixie-build/`, `katmate-os/`). MINIS git is henceforth ignored as authority;
MINIS realigns by rsync only (Path A).

### Build + bake (all on MINIS)

- **Build is host-toolchain, NOT chroot.** Fish history + `foundation.sh:56`
  settled the open question from the 2026-07-10 memory note: the agent is built
  with MINIS host `cargo build --release`, not inside the trixie chroot. It works
  because the host binary links a low-enough glibc: `objdump -T … | grep GLIBC`
  → max `GLIBC_2.34` < trixie 2.41. Same check, same result as vm-agent.
- **`netvm.sh` is monolithic (no `--bake-only`).** Running it overwrites the
  whole `vm_sys_netvm` LV (debootstrap → apt → config → step-7 agent bake →
  kernel/initrd export). So for a first iteration the agent was **hand-baked**
  into the existing image instead: `vm_sys_netvm` is a standalone linear RW LV
  (not thin, not frozen — no `-K -ay`), so mount RW → `install -D -m 0755
  netvm-agent /usr/local/bin/` → write `netvm-agent.service` verbatim from step 7
  (`CAP_NET_ADMIN`, `NoNewPrivileges`, `ProtectSystem=strict`) → chroot
  `systemctl enable` → sync + udevadm settle + umount (the anti-jbd2 pattern; the
  umount was clean). The `systemctl enable` `/proc not mounted` warning is
  harmless — enable is a pure symlink op.

### Live gate — PASSED

Booted via `~/net-sys.con` (q35, CID 3, RTL8125 vfio, stock Debian kernel
`6.12.95+deb13-amd64` + initramfs). Boot reached `multi-user.target` /
`graphical.target`; `netvm-agent.service` started; `PF_VSOCK` registered. From
the host:

- `ping-client ping 3` → `connected: cid=3 port=1025 op=PING (0x01)` →
  `status=0x00 (OK)`. **First live control path into netVM.** Closes "nothing
  inside the declarative image has ever been verified".
- `ping-client shutdown 3` → `status=0x01 (ERR)`. **"absent, not disabled"**
  proven on the wire: SHUTDOWN (0x05) has no variant in netvm-agent's `Op`, so it
  dies at `Op::try_from` (log + ERR + connection kept alive), not at a runtime
  gate. The unit-test assertion, now confirmed live.
- NETCFG could **not** be live-tested: `ping-client` has no `netcfg` subcommand
  (it predates opcode 0x06 and only knows ping/run/shutdown). NETCFG live test
  waits on a client that can encode it — which waits on the ADR-023 payload.

### Shutdown gap — found and diagnosed (NEW open problem #10)

Attempting a clean stop, `system_powerdown` in the qemu monitor did **nothing**
(sent twice; VM stayed up). This matters because ADR-021's netVM shutdown model
IS `system_powerdown` → logind → clean stop. Diagnosed, not left as a mystery:

- Boot log already said it: `getty-static.service … dbus and logind are not
  available`.
- `netvm.list` ships neither `dbus` nor `libpam-systemd`.
- Mount-inspect of the image: `systemd-logind` binary (309768 B) **and**
  `systemd-logind.service` unit are **present** — but `dbus-daemon` is **absent**.

So logind cannot register on the system bus → never runs → the registered ACPI
power button (`Power Button [PWRF]`) has no handler → `system_powerdown` is
inert. **ADR-021 is NOT disproven** — its precondition (a running logind) was
simply missing from the image. One-line fix: add `dbus` (+`libpam-systemd`) to
`netvm.list`, rebuild, re-test. Worth weighing first (thinking-on): dbus in the
most-exposed VM is added attack surface; a narrow `acpid` power-button path is a
lower-surface alternative — ADR-worthy. Dev shutdown meanwhile was `quit` in the
monitor (ungraceful; LV confirmed healthy after, `-wi-a-----`, clean, unmounted).

### Next

1. Add `dbus` (+`libpam-systemd`) to `netvm.list` (or decide the `acpid`
   alternative first); rebuild via `netvm.sh`; re-test `system_powerdown` → clean
   poweroff. This also makes the manual bake reproducible declaratively.
2. Then wire QMP (`-qmp …` in `net-sys.con` + host tool) — pointless before
   logind can act on it.
3. ADR-023 NETCFG payload (thinking-on) + a client subcommand to live-test it.

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

