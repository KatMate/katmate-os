# Session State — Katmate OS

> Volatile working document for cross-session continuity. Permanent facts
> graduate to `docs/`; this file stays short and is regenerated at the end of
> each working session. Detailed proofs and command sequences live in git
> history and the ADRs — this file references them rather than repeating them.

**Milestone:** v0.2 (in development) · **Last updated:** 2026-10-03
(`ai6`, alpha integration step 6, on the Acer and MINIS: `katmate-launch`
and the waybar menu (R150–R158). All four AppVMs launched from the menu,
and the parameter table is complete, so **the engineering of the alpha is
done** (R153). What remains is the Cubi reproducibility gate and the launch
daemon).

## Current focus

**The focus is the host side of the TCB — specifically the launch daemon.**
Everything below the daemon is proven: the RTL8125 passthrough backbone holds
across reboot cycles, `build/netvm.sh` reproduces the uplink declaratively
(proven 2026-07-09, netinst pet retired in principle), and `netvm-agent` is
live-gated through PING, NETCFG and SHUTDOWN — the control path into the guest,
open for most of July, is closed (ADR-024, ADR-025).
**[Note 2026-09-27: the focus is now the networking arc** (§ *Next steps*,
*Networking arc (2026-09-26)*; ADR-037). Step 2 is done. Next are step 3
(R8, G6 and G3's static half), 3a (the finding-12 guard) and 4 (the AppVM
side). The launch daemon follows the arc. The text of this section is left
as written.**]** **[Note 2026-09-27, later: step 3 is done and gated (G6 and
G3's static half PASS; r8-impl A and B). Next is 3a, the finding-12 guard,
then step 4, then step 5.]** **[Note 2026-09-28: next is still 3a. It is
ruled (R47–R56, ADR-037's note of 2026-09-28) and not implemented.]**
**[Note 2026-09-28, later: step 3a is done — implemented, built and gated
(F12a and F12b PASS; f12-impl A and B). Next is step 4, the AppVM side,
then step 5.]**
**[Note 2026-09-28, s4-readpass and rulings: step 4 is split (R60). Next
is 4.0, a measurement with no code, then ADR-038 (guest addressing), then
4a, 4b, G5 and 4c.]**
**[Note 2026-09-28, s4-m0 and rulings: step 4.0 is done. Next is ADR-038,
in its own session, in the direction R76 gives (katmate-init applies the
guest's address from typed command-line parameters), then 4a.]**
**[Note 2026-09-29, ADR-038: ADR-038 is written and PROPOSED (R77).** Next
is **4a**, the host side: `katmate-app-routed@`, the generator's
`app-routed` arm and `KM_GUEST_ADDR`, the guard of #19, `ExecStopPost=`,
and the delta rename. Then **4b**: katmate-init per ADR-038, the resolver
symlink with its read-back in `foundation.sh` and `app-layer.sh`, and the
rebuild chain. Then ADR-038's G1–G3 and ADR-037's G5.**]**
**[Note 2026-09-29, step 4a: 4a is done** — implemented on the Acer
(s4a-impl A, four commits) and installed and first run on MINIS (s4a-impl
B); no gate taken. Next is **4b**: katmate-init per ADR-038, the resolver
symlink with its read-back in `foundation.sh` and `app-layer.sh`, and the
rebuild chain. Then ADR-038's G1–G3 and ADR-037's G5.**]**
**[Note 2026-09-29, step 4b: 4b is done** — implemented and tested on the
Acer (s4b-impl A, four commits), and on MINIS the chain rebuilt and the
first AppVM configured itself from `km.*` (s4b-impl B). **ADR-038's G1
(positive half) and G3 are passed** (R89, R90). Next: a ruling on the
vehicle for an altered `-append` (G1's refusal half, G2, and ADR-037 G5's
refusal half); the `init/tests/run.sh` route-verdict fix with its re-run of
`--apply` on MINIS; and the guest umask (#53).**]**
**[Note 2026-09-29, `wp-0929d`: networking arc step 4 is closed, and
ADR-037 and ADR-038 are Accepted** (R96). R91 is in the image and has been
observed in a guest. ADR-038's G1 refusal half and G2, and ADR-037's G5 in
both halves, passed (R95). **Next is 4c**, `netvm-agent`, in one netVM
rebuild before a second networked AppVM. It carries R67's items (R55's
pairing check #49, ADR-035 §7's count and §6, and DOWN on REMOVE #45) and
#34's ARP half. R73's SHUTDOWN comments (#51) go in their own commit. Two
items are the operator's: the IPv6 change to `proton` on MINIS (#54), and
removing the `_pre0929` and `_pre0929b` sets.**]**
**[Note 2026-09-30, `s4c-a`: 4c's part A is done** — its code and
configuration are committed on the Acer and pushed, and nothing is built
or gated. **Next is 4c B:** one netVM rebuild (reboot before `netvm.sh`,
suspend masked), the host unit reinstalled, and the gates, with
`f12peer.py`'s ARP and TCP modes (R109). See § *This session*.**]**
**[Note 2026-09-30, `s4c-b`: 4c's part B is done.** netVM is rebuilt on
4c's code and running on it, and every row of 4c's gate list except G6b
and #48's fail-closed half was observed and quoted. Verdicts, and closing
#34, #45, #48 and #49, are the operator's. See § *This session*.**]**
**[Note 2026-09-30, `wp-0930`: networking arc step 4 is done.** 4c's verdict
is PASS (R117). #34, #45, #49 and #51 are closed, and #48 is open for its
fail-closed half only (R118). ADR-035 stays PROPOSED until G6b is taken or
deferred (R119). **Next is the alpha integration** (`ROADMAP.md` § *Build
order*, *Alpha integration*): the remaining AppVMs on netVM's slots, one at
a time, with `docs/PARAMETERS.md` filled as they land. See § *This
session*.**]**
**[Note 2026-10-02, `ai1`: alpha integration step 1 is done.** Two AppVMs,
`app_web` and the new `app_personal`, ran at the same time on one netVM,
each on its own slot, with both GUIs on MINIS's screen through the one
`waypipe-client`. `docs/PARAMETERS.md` exists. **Next is the next alpha
AppVM** (office or vault), after a decision on the hugepage pool. See §
*This session*.**]**
**[Note 2026-10-02, `ai2`: alpha integration step 2 is done.** Every
routed AppVM now names itself from `km.name=%i` (R125): the operator read
`user@app_web` and `user@app_personal`. The pool is 6144 × 2 MiB (R126),
which answers ai1's pool question. **Next is the next alpha AppVM**
(office or vault). Vault needs an offline template that carries
`km.name=%i`. See § *This session*.**]**
**[Note 2026-10-02, `ai3`: alpha integration step 3 is done.** `app_work`
(CID 23, slot 03, manifest `office`) ran beside `app_web` and
`app_personal` on one netVM, the operator saved and reopened a Writer
document in it, and a flow from `.19` carried `mark=4`. **Next is the vault
AppVM**, the last of the alpha. It needs an offline template that carries
`km.name=%i`. keepassxc is already whitelisted (R130). See § *This
session*.**]**
**[Note 2026-10-02, `ai4`: alpha integration step 4 is done, with one
open item.** `app_vault` (CID 24, no slot) runs under the new
`katmate-app-offline@` (R135) beside the three routed AppVMs. The operator
read `user@app_vault:~$`, and both connect attempts failed at once with
*Network is unreachable*. ADR-032 H2 refused before QEMU. **KeePassXC is
the first Qt application in an AppVM.** It needs `qtwayland5` (added to
`vault.list`) and `QT_QPA_PLATFORM=wayland`, which vm-agent does not set,
so a RUN of `keepassxc` opens nothing. Started from foot with the
variable, it worked (R140, the operator's *"JA"*). **Next:** the menu
step that ends the alpha (ai4 report § 6), and vm-agent's platform
selection for a RUN child. See § *This session*.**]**
**[Note 2026-10-03, `ai5`: alpha integration step 5 is done.** vm-agent
sets `QT_QPA_PLATFORM=wayland`, `XDG_SESSION_TYPE=wayland` and
`LANG=C.UTF-8` for a RUN child (R146), and every layer carries `ip`
(R147). After one foundation rebuild, **RUN `keepassxc` opened a window
and the operator's `~/test.kdbx` opened**. foot no longer warns about the
locale, and firefox-esr and LibreOffice still open. The three variables
were read in the app's own environment. ai4's verdicts are recorded
(R148), and `katmate-update`'s mapping is open problem #57 (R149).
**Next:** the menu step that ends the alpha (ai6). See § *This
session*.**]**
**[Note 2026-10-03, `ai6`: alpha integration step 6 is done, and with it
the alpha's engineering** (R153). `katmate-launch` (T4, the launch daemon's
alpha precursor) writes the owner, issues NETCFG, starts the unit, waits for
PING and RUNs the app, and reverses all of it at stop. A waybar menu calls
it through one sudoers rule (SECURITY-MODEL gap 17). The operator launched
all four AppVMs from the menu, cold, each window 4–6 s after the click, and
then *Stop all AppVMs*. `docs/PARAMETERS.md` has no empty cell. **Next:**
the MSI Cubi as the reproducibility gate, and the launch daemon (build order
step 3b), whose output specification is PARAMETERS.md with
`katmate-launch`'s tables. See § *This session*.**]**

The **entire build chain remains scripted and proven from nothing**:
`make foundation` builds the shared systemd-free base
(debootstrap → base → waypipe-from-source → bake init/agent/user → freeze),
**[corrected 2026-09-26: not systemd-free — `systemd`, `systemd-sysv`, `dbus`
and `dbus-daemon` are installed as dependency debt, and katmate-init, not
systemd, is PID 1; see *Live state*, foundation, and open problem #35]**
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

## This session (2026-10-03, alpha integration step 6 — ai6) — `katmate-launch` and the waybar menu (R150–R158); four AppVMs launched from the menu; the alpha's engineering is done (R153)

One session, `ai6`, on the Acer and MINIS, in auto mode. It halted once,
at its read pass, on four divergences, and the operator ruled them
(R154–R158). **D1:** the brief said to reuse the generator's profile
derivation. No reusable form exists: it is inline in `katmate-generate-env`,
and `katmate-lib.sh` excludes it by name. **D2:** `ping-client` had no
installed path, and its only copy was in a build tree that uid 1000 can
write. **D3:** NETCFG ADD needs netVM's slot MAC and the peer address, which
the brief's table did not carry, and the address is computed only in the
generator. **D4:** the operator's running waybar config is the tracked
`desktop/waybar/config-sway.jsonc` (a symlink into the synced tree), and an
include alone shows nothing. No commit on MINIS. No reboot. The report is
outside the repository: `~/Claude.assistent/ai6-report.md`, with every
script and output in `~/Claude.assistent/ai6/` and
`/home/host/katmate-dev/ai6/`.

**The operator's rulings.** Brief (2026-10-02): **R150** `katmate-launch
<instance> <app>`, `--stop`, `--stop-all`, bash, T4. **R151** one
`NOPASSWD` sudoers rule for exactly that path, a dev/alpha shortcut.
**R152** the waybar `custom/katmate` menu. **R153** the alpha's end
condition. Read pass (2026-10-03):
- **R154 (D1):** the launcher *selects* the unit from T1's `netvm`, and the
  generator's ADR-032 §6 check *verifies* it. The generator stays the
  profile's one authority.
- **R155 (D2):** `ping-client` is installed as the T4 binary
  `/usr/lib/katmate/ping-client`, and the launcher calls only that path.
- **R156 (D3):** a static table of slot, LINK_ID, slot MAC and peer, as
  literals from PARAMETERS.md, with no arithmetic. The order is owner, ADD,
  start, PING, RUN. After the start, the generator's `KM_GUEST_ADDR` is read
  back, and a mismatch stops the instance.
- **R157 (D4):** two lines in the tracked `config-sway.jsonc` (the include,
  and `custom/katmate` first in `modules-left`), two new tracked files in
  `desktop/waybar/`, and two symlinks in `~/.config/waybar/`.
- **R158:** R151's sufficiency is UNVERIFIED while `katmate-dev` exists.
  The new gap is SECURITY-MODEL **#17**.

**What ran (CEST).**
- **Part A (Acer):** `27500cf` `katmate-launch`; `321753c`
  `tools/check-run-whitelist` (AGREE, 5 entries; two negative controls
  refused); `ee287c6` the menu; `10a95e5` gap 17; `1e91476` ADR-029's note;
  `894c940` HOST-CONFIG §§ 13–14. A fixture extract of the launcher (stubbed
  systemctl, ping-client and logger, the real library and T1 reader, and the
  staged T1 files) gave **41 of 41**: every argument, whitelist, layer and T1
  refusal, the cold, warm and offline paths, the read-back mismatch, a start
  failure, a PING timeout, and the stop and stop-all paths. Pushed;
  `ls-remote` equal to HEAD.
- **P0 (19:42):** no reboot since 2026-10-02 14:03:24; netVM 22405;
  installed = tree, 11 of 11; **waybar 0.15.0**, started by sway with
  `config-sway.jsonc`.
- **B2 (20:00):** rsync (21 items, no deletions). Installed: `katmate-launch`
  `7938f47a…`; `ping-client` `bbeeddf2…`, the 2026-07-23 build every session
  used, whose sources have changed since only in comments; and
  `/etc/sudoers.d/katmate-launch` `ebfb91fe…`, `root:root 0440`, after
  `visudo -c -f`. `sudo -l -U host` lists the rule. Two symlinks; waybar
  SIGUSR2 (same PID 1420). The installed set is 13 of 13 equal to its
  sources. The operator saw the *KatMate* label.
- **B3 (20:02–20:04), from the shell:** `app_vault keepassxc`, `--stop
  app_vault`, `app_web foot`, `--stop app_web`, each exit 0. KeePassXC and
  foot opened. PING OK on try 5 at about 4.0 s (1 s poll).
- **B4 (20:06–20:13), the operator from the menu:** cold web Firefox,
  personal Terminal, work LibreOffice and vault KeePassXC, then nine warm
  RUNs, all `RUN … OK`. **Windows, click to window:** vault KeePassXC ~4 s,
  personal Terminal ~4 s, work LibreOffice ~5 s, web Firefox ~6 s; warm
  under 1 s, Firefox ~1 s (the operator). All four AppVMs ran at once.
  *Stop all AppVMs* (20:13:27–20:13:31): four SHUTDOWNs, REMOVE 201–203,
  owners removed, every window closed.
- **End state:** netVM 22405 running, `NRestarts=0`; all four AppVM units
  inactive; no owner; 6144 of 6144 hugepages free.

**Found, recorded and not designed for (report §§ 5, 6).**
- **A RUN of an app the layer lacks:** ADR-021's note of 2026-10-02 (R130)
  says the RUN *"fails, which is already loud"*, while `ai5-report.md` § 6,
  from reading `handle_run`, says it answers OK and opens nothing.
  `katmate-launch` refuses such a pair either way. Neither claim has been
  observed.
- `desktop/README.md`'s deploy lines point at `~/katmate-os/`, while MINIS's
  symlinks point at `~/katmate-build/`. This predates ai6, which follows the
  README's pattern.

**Not done, and not claimed.**
- That R151's rule alone is sufficient (R158).
- The launcher's refusal paths on MINIS (they ran only in the Acer extract),
  NETCFG's effect inside netVM, and the MSI Cubi.
- The `ip -br addr` line in the B3 foot window (asked, not answered).

## Previous session (2026-10-03, alpha integration step 5 — ai5) — the RUN child's environment (R146); `iproute2` after the build-dependency purge, with a residue read-back (R147); one foundation rebuild; RUN `keepassxc` opens; ai4's verdicts (R148); `katmate-update`'s mapping is #57 (R149)

One session, `ai5`, on the Acer and MINIS, in auto mode. It halted four
times, and each halt was ruled through the orchestrator by the operator.
**D1 (read pass):** the brief said vm-agent's RUN child already had
`WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` from vm-agent. It had neither from
vm-agent: `spawn()` passed the agent's inherited environment, which is
katmate-init's five constants. Ruled option (a), below. **D2:** the brief's
R142–R145 were already taken by cd1/cd2's rulings, so they were renumbered
**R146–R149** in order. **B3-HALT:** the first foundation build with
`iproute2` in step 3 had 235 packages. `iproute2` Suggests python3, so step
5's autoremove kept the waypipe build residue (python3.13, binutils): 72
removed against ai3's 91. Ruled (b), install after the purge, plus a
read-back. **B3-HALT-2:** the ruled read-back pattern `gcc*` matched
`gcc-14-base`, which is in every known-good layer. Ruled: exclude exactly
`^gcc-[0-9]+-base$`. The classifier refused `git pull` once (*Untrusted
Code Integration*). It was moot, because HEAD already held the four new
commits, and it was not retried. **GitHub SSH is not available to this
session**, so every push is left to the operator. No commit on MINIS. No
reboot. The report is outside the repository:
`~/Claude.assistent/ai5-report.md`, with every script and output in
`~/Claude.assistent/ai5/` and `/home/host/katmate-dev/ai5/`.

**The operator's rulings (2026-10-02 brief, renumbered 2026-10-03).**
- **R146 — vm-agent's RUN child environment** (D1 option (a)): the agent's
  own environment (katmate-init's five, their single source), with
  `QT_QPA_PLATFORM=wayland`, `XDG_SESSION_TYPE=wayland` and
  `LANG=C.UTF-8` set by vm-agent, replacing any inherited value. Nothing
  else is added or removed. A unit test pins the composition.
  Rejected: (b), because katmate-init's five would live in two binaries;
  (c), because platform and locale are vm-agent's policy.
- **R147 — `iproute2` in the foundation**, installed after step 5's purge
  (step 5b). A read-back (step 5c) kills the build on any installed
  `python3*`, `libpython3*`, `binutils*`, `libbinutils`, `gcc*` (but
  `gcc-N-base`), `cpp*`, `meson` or `ninja-build`.
- **R148 — ai4's verdicts:** H2 PASS, G2 (re-pointed) PASS, R139 PASS,
  R140 partial. ai5 closes R140.
- **R149 — `katmate-update`'s delta-to-type mapping** is an open problem
  (#57), not fixed here.

**What ran (CEST).**
- **Part A (Acer):** `2a9e638` vm-agent (`RUN_ENV`, `run_child_env`,
  `spawn(argv, envp)`, and the stale *"systemd unit"* comments in
  `main.rs` and `config.rs`). `cargo test -p vm-agent` gave 5 of 5. A
  negative control (the filter disabled) failed the new test.
  `f5ed9d6`, superseded by `77f1b72`: `iproute2` (step 5b) and the
  read-back (step 5c), with an Acer extract of nine cases, all as
  expected, two of them synthesised from the real package lists (ai3's
  209 pass; ai5's first build refuses with 11 names). Notes: `7f40e33`
  ADR-021 (R146), `9c8fee0` and `cbe49b0` ADR-014 (R147), `6e50358`
  ADR-030 (R148). `710bc77` and `9125aa1` brackets in ai4's entry (now in
  `docs/SESSIONS.md`).
- **P0 (16:17):** no reboot since 2026-10-02 14:03:24; netVM MainPID
  22405; all AppVM units inactive; no layer jbd2; 6144 of 6144 pages
  free. The installed set equalled the tree, 11 of 11.
- **B2 (16:18):** rsync; vm-agent built on MINIS (`cargo test` 5 of 5).
  **`out/vm-agent` `5d35567f…`**, with the three names in `strings`. The
  old `87ebdcaa…` had none.
- **B3 (16:19–16:40):** `_preai5` set aside (all four layers, four deltas
  rebased `-u`, four metas). First `make foundation` exit 0, 235 packages:
  halted, removed under R132's guards. **Second `make foundation` exit 0
  (16:33:46–16:37:01): 216 packages = 209 + 7**, autoremove 91, and
  `Read-back: no build residue installed among 216 dpkg records`. `make
  app-web` 237, `make app-office` 368, `make app-vault` 292, each exit 0
  with every error pattern 0. Every layer bakes `/sbin/init` `8163e103…`
  and vm-agent `5d35567f…`, and has `/usr/bin/ip`, with `locale -a`
  listing `C.utf8`. Four deltas recreated.
- **B4 (16:40):** owners 01–03, NETCFG ADD 201–203 OK; all four AppVMs,
  **PING OK on try 3 each, 4.38–4.56 s from `systemctl start`**;
  `hostname:`/`net:` lines as before; app_vault's argv 0/0/0/0.
  `HugePages_Free` 6026 → 5960 → 5893 → 5826.
- **The operator at MINIS (17:06–17:19):** **RUN `keepassxc` (app_vault):
  the window opened, and `~/test.kdbx` opened with the entry** (*"it's
  there. and database opens"*). RUN `foot` (app_vault): **no locale
  warning**; `env` showed `XDG_SESSION_TYPE=wayland`, `LANG=C.UTF-8`,
  `WAYLAND_DISPLAY=wayland-1GxsdmpBTw`, `QT_QPA_PLATFORM=wayland`;
  `ip -br link` `lo UNKNOWN … <LOOPBACK,UP,LOWER_UP>`, `sit0@NONE DOWN`;
  `ip -br addr` `lo 127.0.0.1/8` only; `ip route` empty. RUN `foot`
  (app_web): `eth0 UP 10.100.1.17/32`. RUN `firefox-esr` (app_web) and
  `libreoffice` (app_work): both opened normally.
- **End (17:19):** four SHUTDOWNs (*"Deactivated successfully"*), REMOVE
  201–203, owners removed. **`_preai5` removed** (three app layers, then
  the foundation origin, four deltas, four metas; every guard held).
  netVM left running.

**Found, recorded and not designed for (report §§ 5, 6).**
- **An installed package's Suggests keep an auto-installed package alive
  through `apt-get autoremove`**, so the order of installs decides what a
  purge leaves behind. Measured 91 against 72. The apt option that does
  it (`SuggestsImportant`) is recalled, not read.
- ai5's vm-agent change moved line numbers cited elsewhere:
  `main.rs:475` (`Op::try_from`) is now `:513`, and `:288`/`:310`
  (SHUTDOWN) are now `:300`/`:322`. Cited by #56 and ADR-039's note of
  2026-10-03. `:87` is unchanged.

**Not done, and not claimed.**
- Verdicts on R146 and R147: the operator's.
- The read-back's refusal path on MINIS (it ran only as the Acer extract).
- netVM conntrack during the vault test (not asked this time).
- `init/tests/run.sh --apply`; G6b; #48's fail-closed half.

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

**Closed 2026-09-30 (second rotation of that day).** The 2026-09-29 *step
4b2 and the gates* entry (R91 in the image, ADR-038's G1 refusal half and G2
and ADR-037's G5 taken, both ADRs Accepted, R91–R96, with its `wp-0929e`
addendum) rotated to the archive in `wp-0930`, one session later than the
2026-09-30 *step 4c B* entry arrived: `s4c-b`'s brief allowed one commit, so
it marked the entry *Earlier session, not yet rotated* instead. **The body
moved verbatim; the heading did not.** The heading's prefix went back from
*Earlier session, not yet rotated* to *Previous session*, the prefix it
carried before `s4c-b` marked it, because the mark describes this file and
is false in the archive. Verified by hash. The 147-line body below the
heading hashed `57aada2b9c012f7c…` from the `HEAD` blob before the move, and
the same 147 lines re-extracted from `docs/SESSIONS.md` at the new home
hashed the same. The block was inserted at the head of the entry list,
above the 2026-09-29 *step 4b* entry, newest first. **No ordinal changed.**
After this rotation the file holds the two step-4c entries. `wp-0930`'s own
entry arrives in the next commit, so the file then holds three again, with
*step 4c A* marked *Earlier session, not yet rotated*, as `s4c-b` did.

**Closed 2026-09-30.** The 2026-09-29 *step 4b* entry (the guest side:
katmate-init configures the AppVM from `km.*`, G1's positive half and G3,
R85–R90) rotated to the archive as the 2026-09-30 *step 4c A* entry
arrived. **The block moved verbatim, heading included**, and *Previous
session* stays *Previous session*. Verified three ways. The 94-line block,
heading line included, hashed `128e1871b14c7e47…` before the move. The
pre-move block `cmp`-matched the `HEAD` blob. The block re-extracted from
`docs/SESSIONS.md` at its new home `cmp`-matched the pre-move block.
`docs/SESSIONS.md` gained 95 lines, the block and one blank separator, and
lost none. The block was inserted at the head of the entry list, above the
2026-09-29 *step 4a* entry, newest first. The 2026-09-29 *step 4b2 and the
gates* entry's prefix changed from *This session* to *Previous session*,
and its body is untouched. **No ordinal changed.** The rotation and the
new entry are separate commits, so between them this file held one
session, never three.

**Closed 2026-09-29 (fifth rotation of that day).** The 2026-09-29
*step 4a* entry (the host side of the first routed AppVM implemented,
installed and first run on MINIS, and R78–R84) rotated to the archive as
the 2026-09-29 *step 4b2 and the gates* entry arrived. **The block moved
verbatim, heading included**, and *Previous session* stays *Previous
session*. Verified three ways. The whole block, heading line included,
hashed **identical before and after, `619353857d66f0f0…`**. The pre-move
block diffed clean against the `HEAD` blob. The block re-extracted from
`docs/SESSIONS.md` at its new home diffed clean against the pre-move
block. `docs/SESSIONS.md` gained 83 lines, the 82-line block and one blank
separator, and lost none. The block was inserted at the head of the entry
list, above the 2026-09-29 *ADR-038* entry, newest first. The 2026-09-29
*step 4b* entry's prefix changed from *This session* to *Previous
session*, and its body is untouched. **No ordinal changed.** The rotation
and the new entry are separate commits, so between them this file held
one session, never three.

**Closed 2026-09-29 (fourth rotation of that day).** The 2026-09-29
*ADR-038* entry (AppVM guest addressing written as ADR-038, PROPOSED, and
R77 recorded) rotated to the archive as the 2026-09-29 *step 4b* entry
arrived. **The block moved verbatim, heading included**, and *Previous
session* stays *Previous session*. Verified three ways. The whole block,
heading line included, hashed **identical before and after,
`fdf3a49d2615fd13…`**. The pre-move block diffed clean against the `HEAD`
blob. The block re-extracted from `docs/SESSIONS.md` at its new home
diffed clean against the pre-move block. `docs/SESSIONS.md` gained 43
lines, the 42-line block and one blank separator, and lost none. The block
was inserted at the head of the entry list, above the 2026-09-28 *s4-m0
and rulings* entry, newest first. The 2026-09-29 *step 4a* entry's prefix
changed from *This session* to *Previous session*, and its body is
untouched. **No ordinal changed.** The rotation and the new entry are
separate commits, so between them this file held one session, never
three.

**Closed 2026-09-29 (third rotation of that day).** The 2026-09-28
*s4-m0 and rulings* entry (networking arc step 4.0, the first AppVM on a
slot measured with no code, R75's reading, and R76) rotated to the
archive as the 2026-09-29 *step 4a* entry arrived. **The block moved
verbatim, heading included**, and *Previous session* stays *Previous
session*. Verified three ways. The whole block, heading line included,
hashed **identical before and after, `bd0303df117a62ce…`**. The pre-move
block diffed clean against the `HEAD` blob. The block re-extracted from
`docs/SESSIONS.md` at its new home diffed clean against the pre-move
block. `docs/SESSIONS.md` gained 74 lines, the 73-line block and one blank
separator, and lost none. The block was inserted at the head of the entry
list, above the 2026-09-28 *s4-readpass and rulings* entry, newest first.
The 2026-09-29 *ADR-038* entry's prefix changed from *This session* to
*Previous session*, and its body is untouched. **No ordinal changed.**
The rotation and the new entry are separate commits, so between them this
file held one session, never three.

**Closed 2026-09-29 (second rotation of that day).** The 2026-09-28
*s4-readpass and rulings* entry (networking arc step 4 read against the
tree, and the step-4 rulings R60–R75 recorded before any code) rotated to
the archive as the 2026-09-29 *ADR-038* entry arrived. **The block moved
verbatim, heading included**, and *Previous session* stays *Previous
session*. Verified three ways. The whole block, heading line included,
hashed **identical before and after, `65fb66182fdc970f…`**. The pre-move
block diffed clean against the `HEAD` blob. The block re-extracted from
`docs/SESSIONS.md` at its new home diffed clean against the pre-move
block. `docs/SESSIONS.md` gained 64 lines, the 63-line block and one blank
separator, and lost none. The block was inserted at the head of the entry
list, above the 2026-09-28 *f12-impl A and B* entry, newest first. The
2026-09-28 *s4-m0 and rulings* entry's prefix changed from *This session*
to *Previous session*, and its body is untouched. **No ordinal changed.**
The rotation and the new entry are separate commits, so between them this
file held one session, never three.

**Closed 2026-09-29.** The 2026-09-28 *f12-impl A and B* entry (networking
arc step 3a implemented, netVM rebuilt on it, and F12a and F12b taken)
rotated to the archive as the 2026-09-28 *s4-m0 and rulings* entry
arrived. **The block moved verbatim, heading included**, and *Previous
session* stays *Previous session*. Verified three ways. The whole block,
heading line included, hashed **identical before and after,
`f3f84f68dbf547a8…`**. The pre-move block diffed clean against the `HEAD`
blob. The block re-extracted from `docs/SESSIONS.md` at its new home
diffed clean against the pre-move block. `docs/SESSIONS.md` gained 89
lines, the 88-line block and one blank separator, and lost none. The block
was inserted at the head of the entry list, above the 2026-09-28
*f12-readpass and rulings* entry, newest first. The 2026-09-28
*s4-readpass and rulings* entry's prefix changed from *This session* to
*Previous session*, and its body is untouched. **No ordinal changed.** The
rotation was made after midnight, so it is dated 2026-09-29 and carries no
ordinal (operator ruling, 2026-09-29); the entries it moves between are
both of 2026-09-28. The rotation and the new entry are separate commits,
so between them this file held one session, never three.

**Closed 2026-09-28 (third rotation of that day).** The 2026-09-28
*f12-readpass and rulings* entry (the finding-12 candidate read against the
tree, and the step-3a rulings R47–R56 recorded before any code) rotated to
the archive as the 2026-09-28 *s4-readpass and rulings* entry arrived. **The
block moved verbatim, heading included**, and *Previous session* stays
*Previous session*. Verified three ways. The whole block, heading line
included, hashed **identical before and after, `ef2339a05f45e95a…`**. The
pre-move block diffed clean against the `HEAD` blob. The block re-extracted
from `docs/SESSIONS.md` at its new home diffed clean against the pre-move
block. `docs/SESSIONS.md` gained 54 lines, the 53-line block and one blank
separator, and lost none. The block was inserted at the head of the entry
list, above the 2026-09-27 *r8-impl A and B* entry, newest first. The
2026-09-28 *f12-impl A and B* entry's prefix changed from *This session* to
*Previous session*, and its body is untouched. **No ordinal changed.** The
rotation and the new entry are separate commits, so between them this file
held one session, never three.

**Closed 2026-09-28 (second rotation of that day).** The 2026-09-27
*r8-impl A and B* entry (networking arc step 3 implemented in eight commits,
netVM rebuilt on it, and G6 and G3's static half taken) rotated to the
archive as the 2026-09-28 *f12-impl A and B* entry arrived. **The block
moved verbatim, heading included**, and *Previous session* stays *Previous
session*. Verified three ways. The whole block, heading line included,
hashed **identical before and after, `abba2c8c6cb9311f…`**. The pre-move
block diffed clean against the `HEAD` blob. The block re-extracted from
`docs/SESSIONS.md` at its new home diffed clean against the pre-move block.
`docs/SESSIONS.md` gained 101 lines, the 100-line block and one blank
separator, and lost none. The block was inserted at the head of the entry
list, above the 2026-09-27 *r8-readpass, wp-0927e and rulings* entry, newest
first. The 2026-09-28 *f12-readpass and rulings* entry's prefix changed from
*This session* to *Previous session*, and its body is untouched. **No
ordinal changed.** The rotation and the new entry are separate commits, so
between them this file held one session, never three.

**Closed 2026-09-28.** The 2026-09-27 *r8-readpass, wp-0927e and rulings*
entry (the stale lines after the implementation corrected, the tree read
against R7/R8, and the step-3 rulings R30–R40 recorded before any code)
rotated to the archive as the 2026-09-28 *f12-readpass and rulings* entry
arrived. **The block moved verbatim, heading included**, and *Previous
session* stays *Previous session*. Verified three ways. The whole block,
heading line included, hashed **identical before and after,
`3421bcdc0edd4484…`**. The pre-move block diffed clean against the `HEAD`
blob. The block re-extracted from `docs/SESSIONS.md` at its new home diffed
clean against the pre-move block. `docs/SESSIONS.md` gained 60 lines, the
59-line block and one blank separator, and lost none. The block was inserted
at the head of the entry list, above the 2026-09-27 *adr037-impl A and B*
entry, newest first. The 2026-09-27 *r8-impl A and B* entry's prefix changed
from *This session* to *Previous session*, and its body is untouched. **No
ordinal changed.** The rotation and the new entry are separate commits, so
between them this file held one session, never three.

**Closed 2026-09-27 (sixth rotation of that day).** The 2026-09-27
*adr037-impl A and B* entry (ADR-037 implemented in nine commits, netVM
rebuilt on it, and G1–G4 taken) rotated to the archive as the 2026-09-27
*r8-impl A and B* entry arrived. **The block moved verbatim, heading
included**, and *Previous session* stays *Previous session*. Verified three
ways. The whole block, heading line included, hashed **identical before and
after, `2096a9adc13f8e58…`**. The pre-move block diffed clean against the
`HEAD` blob. The block re-extracted from `docs/SESSIONS.md` at its new home
diffed clean against the pre-move block. `docs/SESSIONS.md` gained 98 lines,
the 97-line block and one blank separator, and lost none. The block was
inserted at the head of the entry list, above the 2026-09-27 *adr037-readpass
and rulings* entry, newest first. The 2026-09-27 *r8-readpass, wp-0927e and
rulings* entry's prefix changed from *This session* to *Previous session*,
and its body is untouched. **No ordinal changed.** The rotation and the new
entry are separate commits, so between them this file held one session,
never three.

**Closed 2026-09-27 (fifth rotation of that day).** The 2026-09-27
*adr037-readpass and rulings* entry (the tree read against ADR-037, and the
operator's rulings R10–R28 recorded before any code) rotated to the archive as
the 2026-09-27 *r8-readpass, wp-0927e and rulings* entry arrived. **The block
moved verbatim, heading included**, and *Previous session* stays *Previous
session*. Verified three ways. The whole block, heading line included, hashed
**identical before and after, `c195f9f17ddf0753…`**. The pre-move block diffed
clean against the `HEAD` blob. The block re-extracted from `docs/SESSIONS.md`
at its new home diffed clean against the pre-move block. `docs/SESSIONS.md`
gained 98 lines, the 97-line block and one blank separator, and lost none. The
block was inserted at the head of the entry list, above the 2026-09-27
*host-cleanup* entry, newest first. The 2026-09-27 *adr037-impl A and B*
entry's prefix changed from *This session* to *Previous session*, and its body
is untouched. **No ordinal changed.** The rotation and the new entry are
separate commits, so between them this file held one session, never three.

**Closed 2026-09-27 (fourth rotation of that day).** The 2026-09-27
*host-cleanup* entry (MINIS dev leftovers retired, networkd managing no link,
and HOST-CONFIG §1 re-measured) rotated to the archive as the 2026-09-27
*adr037-impl A and B* entry arrived. **The block moved verbatim, heading
included**, and *Previous session* stays *Previous session*. Verified three
ways. The whole block, heading line included, hashed **identical before and
after, `77926c799489d1a5…`**. The pre-move block diffed clean against the
`HEAD` blob. The block re-extracted from `docs/SESSIONS.md` at its new home
diffed clean against the pre-move block. `docs/SESSIONS.md` gained 207 lines,
the 206-line block and one blank separator, and lost none. The block was
inserted at the head of the entry list, above the 2026-09-27 *pool-fold*
entry, newest first. The 2026-09-27 *adr037-readpass and rulings* entry's
prefix changed from *This session* to *Previous session*, and its body is
untouched. **No ordinal changed.** The rotation and the new entry are separate
commits, so between them this file held one session, never three.

**Closed 2026-09-27 (third rotation of that day).** The 2026-09-27
*pool-fold* entry (the slot pool folded into the shipped sys-driver unit,
netVM started under it with no console, and host-side `tap-int0` retired)
rotated to the archive as the 2026-09-27 *adr037-readpass and rulings* entry
arrived. **The block moved verbatim, heading included**, and *Previous
session* stays *Previous session*. Verified three ways. The whole block,
heading line included, hashed **identical before and after,
`268e2998c6078b13…`**. The pre-move block diffed clean against the `HEAD`
blob. The block re-extracted from `docs/SESSIONS.md` at its new home diffed
clean against the pre-move block. `docs/SESSIONS.md` gained 114 lines, the
113-line block and one blank separator, and lost none. The block was inserted
at the head of the entry list, above the 2026-09-26 *net-up and net-m1* entry,
newest first. The 2026-09-27 *host-cleanup* entry's prefix changed from *This
session* to *Previous session*, and its body is untouched. **No ordinal
changed.** The rotation and the new entry are separate commits, so between
them this file held one session, never three.

**Closed 2026-09-27 (second rotation of that day).** The 2026-09-26 *net-up
and net-m1* entry (netVM running again on a per-session console, its network
baseline read, and the vanilla network stack ruled) rotated to the archive as
the 2026-09-27 *host-cleanup* entry arrived. **The block moved verbatim,
heading included** — *Previous session* stays *Previous session*. Verified by
hashing the whole block, heading line included, before and after —
**identical, `9e60d8bbca49693c…`** — by diffing the pre-move block against the
`HEAD` blob (clean), and by re-extracting it from `docs/SESSIONS.md` at its new
home and diffing it against the pre-move block (clean). `docs/SESSIONS.md`
gained 83 lines — the 82-line block and one blank separator — and lost none;
it was inserted at the head of the entry list, above the 2026-09-24 …
2026-09-26 entry, newest-first. The 2026-09-27 *pool-fold* entry's prefix
changed from *This session* to *Previous session*, its body untouched. **No
ordinal changed.** The rotation and the new entry are separate commits, so
between them this file held one session, never three.

**Closed 2026-09-27.** The 2026-09-24 … 2026-09-26 entry (the first web AppVM:
foundation reduced to the shared GUI runtime, rebuilt, and booted) rotated to
the archive as the 2026-09-27 *pool-fold* entry arrived. **The block moved
verbatim, heading included** — *Previous session* stays *Previous session* —
under the `a6e3fba` reading note. Verified by hashing the whole block, heading
line included, before and after — **identical, `06fb083fdc918f87…`** — by
diffing the pre-move block against the `HEAD` blob (clean), and by
re-extracting it from `docs/SESSIONS.md` at its new home and diffing it against
the pre-move block (clean). `docs/SESSIONS.md` gained 60 lines — the 59-line
block and one blank separator — and lost none; it was inserted at the head of
the entry list, above the 2026-09-20 *second of two* entry, newest-first. The
2026-09-26 *net-up and net-m1* entry's prefix changed from *This session* to
*Previous session*, its body untouched. **No ordinal changed.** The rotation
and the new entry are separate commits, so between them this file held one
session, never three.

**Closed 2026-09-26 (second rotation of that day).** The 2026-09-20 *second of
two* entry (`auditfix-liveread`, `b1-docwrite`, `b1b-rulings` and
`c1-adr035-note` under one heading) rotated to the archive as the 2026-09-26
*net-up and net-m1* entry arrived. **The block moved verbatim, heading
included** — *Previous session* stays *Previous session* — under the same
reading note as the rotation below. Verified by hashing the whole block,
heading line included, before and after — **identical, `41a15bea36570e26…`**
— by diffing the pre-move block against the `HEAD` blob (clean), and by
re-extracting it from `docs/SESSIONS.md` at its new home and diffing it against
the pre-move block (clean). `docs/SESSIONS.md` gained 144 lines — the 143-line
block and one blank separator — and lost none; it was inserted at the head of
the entry list, above the 2026-09-20 *first of two* entry: newest-first, and
*second of two* above *first of two*. The 2026-09-24 … 2026-09-26 entry's
prefix changed from *This session* to *Previous session*, its body untouched.
**No ordinal changed.** The rotation and the new entry are separate commits, so
between them this file held one session, never three.

**Closed 2026-09-26.** The 2026-09-20 *first of two* entry (`auditfix-readpass`:
finding 10's absence measured with its control, and both accept loops read as
serial) rotated to the archive as the 2026-09-24 … 2026-09-26 entry arrived, so
the file never held three at any point between the two commits. **The block
moved verbatim, heading included** — *Previous session* stays *Previous
session* — because `docs/SESSIONS.md`'s reading note on heading prefixes, since
`a6e3fba`, makes the date the identifier and has a rotated entry keep the
heading it was published with; the *Previous* → *This* change recorded by the
paragraphs below is the convention before that note, not this one. Verified by
hashing the whole block, heading line included, before and after —
**identical, `0560ecff4bfa2ce7…`** — by diffing the pre-move block against the
`HEAD` blob (clean), and by re-extracting it from `docs/SESSIONS.md` at its new
home and diffing it against the pre-move block (clean). `docs/SESSIONS.md`
gained 41 lines and lost none; it was inserted at the head of the entry list,
above the 2026-09-15 entry, newest-first. No ordinal changed. **The 2026-09-15
and 2026-09-20 rotations have no *Closed* paragraph here**; they are recorded in
`009c353`, `a6e3fba` and the `docs/SESSIONS.md` reading note, and are not
written up retroactively.

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
  **[Note 2026-09-29 (operator's reading, `wp-0929c`): *"the host's own
  apt/debootstrap traffic does NOT route through netVM/ProtonVPN"* is false
  for both families.** `ip route get 151.101.2.132` → `dev proton table
  51820 src 10.2.0.2`: wg-quick's policy routing sends the host's traffic,
  IPv4 and IPv6, into `proton`; the main table's `default via 10.3.1.1` is
  not what is used. IPv4 through `proton` works; IPv6 through it is a black
  hole. See #54. It does not route through netVM. The text above is left as
  written.**]**
  **[Note 2026-09-29, later (the operator's ruling on s4b2-impl-B's H1;
  `wp-0929d`): *"a black hole"* in the note above is corrected to
  intermittent.** Over the day, one IPv6 request through `proton` got HTTP
  200, and five timed out after 20 s (#54). The note is left as
  written.**]**
  **[Note 2026-09-29, 17:36 (R97; `wp-0929e`): host IPv6 is off
  permanently, by decision.** `proton.conf`'s `PostUp` installs `ip -6 rule
  add pref 100 unreachable` and its `PreDown` removes it. `wg-quick@proton`
  is `enabled` and `active` and is the tunnel's one owner (read at 18:25).
  #54 is resolved. The `gai.conf` line was still present at 18:25, and its
  removal is the operator's. **Dev packages on this host are allowed**
  (R112): `conntrack-tools`, `strace`, as needed for golden fixtures. The
  notes above are left as written.**]**
  **[Note 2026-09-30 (`s4c-m0`, `s4c-a`): installed on the host:
  `conntrack-tools 1.4.9-1`** (with `libnetfilter_cthelper`,
  `libnetfilter_cttimeout` and `libnetfilter_queue`, installed by `s4c-m0`)
  **and `strace 7.2-1`** (already present). `s4c-a`'s W0 used both, in
  throwaway namespaces only.**]**
  **[Note 2026-09-30 (`s4c-b`, P0 at 16:14): `nf_conntrack_netlink` is
  loaded on this host (refcount 0), cause unknown.** No earlier reading
  exists, so whether `s4c-a`'s W0 loaded it is not settled.**]**
  **Kernel and boot, 2026-09-26:** running `7.2.7-hardened1-1-hardened`, booted
  **2026-09-25 14:00:27**; the stock `linux 7.2.6.arch2-1` is installed beside
  `linux-hardened` (`appweb-m1-rerun-report.md` § RA, items 6 and A12).
  **Hugepages, read 2026-09-26:** `HugePages_Total` 4096, `Free` 4096 at 2048 kB;
  `/dev/hugepages` is `root:hugepages` mode `1770`; `host` is in `kvm`, `disk`,
  `hugepages` and `vfio`; `/dev/dm-7` (`vm_app_web_home`) is `host:host`
  (operator, 2026-09-26).
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
  **Permission mode (2026-09-26): delegated sessions that reach MINIS must run
  in Claude Code's Manual permission mode.** In auto mode the classifier denied
  the delivery form above — `scp` + `sudo -n bash` ("Production Reads") — and,
  with the operator's allow rules for ssh/scp in place, the console FIFO write
  ("Remote Shell Writes"). Both calls were refused before execution, so nothing
  reached MINIS and nothing needed undoing; the same calls ran in Manual mode
  (`net-m1-report.md` §§ 3, 4, 6, 7).
  **[Note 2026-09-27 (operator ruling), which supersedes the rule above. The
  rule is left as written.]** Sessions run in **auto mode**. When the
  classifier refuses a command, the agent **stops, reports the exact command
  that was refused, and waits** for the operator to allow it. It **never**
  retries the same thing through a different command form.
  **[Note 2026-09-28, as fact, f12-impl-B.** In auto mode the classifier
  refused an Edit to `docs/DECISIONS.md` (*"Modify Shared Resources"*) and
  an ssh/scp call to MINIS (*"Remote Shell Writes"*). The operator allowed
  the first, and it was retried once, verbatim. For the second, the
  operator switched the session to **Manual** permission mode, and it
  completed in Manual. No new rule.**]**
  **The rsync form of record (2026-09-27)**, as `pool-fold-report.md` § 2.5
  used it, dry run (`-an --itemize-changes`) first:
  `rsync -a --delete --exclude=.git/ --exclude=trixie-build/ --exclude=out/
  --exclude=agent/target/ --exclude=git-cli.txt ~/katmate-os/
  host@10.3.1.3:/home/host/katmate-build/`. With `--delete`, a form without
  these excludes removes the build outputs on MINIS.
  **[Note 2026-09-27 (operator ruling, the launch form for builds).** A netVM
  build runs as a **transient `systemd-run` unit**, started through `sudo -n
  bash`, so that an ssh drop cannot kill `netvm.sh` mid-build. It is followed
  through its journal and its log file. First used by `adr037-impl-B`
  (`km-netvm-build`, 14:47:06–15:01:13 CEST). Such a unit has no `HOME` (see
  *Invariants*, the transient-unit entry).**]**
- **[CLOSED 2026-09-27: from 14:22:49 CEST the installed set equals the tree
  at `c37f9d1`.** `adr037-impl-B` re-installed all 8 tracked files (six
  `/usr/lib/katmate/*` and both units) from the tree, sha256-verified each, and
  `katmate-generate-env` went `ed55ce55…` → `27899269…` (B, Phase 1; ruling
  § 0.1 item 1). Hash-first now expects no difference. The entry is left as
  published.**]**
  **Installed vs tree, 2026-08-22 — one file, deliberately.** The installed
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
  **[corrected 2026-09-26: not systemd-free.]** **Rebuilt 2026-09-26** from
  `5d32dd0`: **209 packages, 85 manual**, the shared GUI runtime only (no
  applications). `systemd`, `systemd-sysv`, `dbus` and `dbus-daemon` are
  installed as **dependency debt, not PID 1** (#35); `/usr/sbin/init` is
  katmate-init, with systemd's binary **diverted to `/usr/sbin/init.systemd`**
  (#36); `foundation.meta` carries **`KERNEL_PROVENANCE=recorded`**
  (`appweb-rebuild-report.md` §§ 5.1, 5.2).
  **[2026-09-29, s4b-impl-B: rebuilt again, from the tree at `647a380`,
  `BUILD_DATE=2026-09-29T09:47:21Z`; it carries the resolver link and the
  step-4b katmate-init. The package count was not read. The 2026-09-26
  layer is set aside as `vm_tpl_foundation_pre0929`. See *THE FIRST
  SELF-CONFIGURED APPVM* below. The text above is left as written.]**
- **netVM** (CID 3 — unchanged by the new map; Debian trixie, q35, **sysVM class
  — ADR-021; driver domain — ADR-022**): two
  artefacts now exist. (a) The old hand-installed **netinst pet**
  (`net-vfio.con`, `vm_net_overlay.qcow2`, guest `enp0s6`) — retired in
  principle, superseded. (b) The **declarative build** `vm_sys_netvm` (linear RW
  4G) from `build/netvm.sh`, booted via `~/net-sys.con` (RTL8125 via
  `-device vfio-pci,host=0000:01:00.0`, `-kernel`/`-initrd` direct boot, kernel
  **6.12.107+deb13-amd64**, last rebuilt **2026-09-05 20:40:32Z**
  **[2026-09-27: superseded. Last rebuilt `2026-09-27T13:01:13Z`, on the
  ADR-037 image, and the kernel is unchanged; see the block *NETVM ON THE
  ADR-037 IMAGE (2026-09-27)* below.]** — was
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
  **[2026-09-27: false on the ADR-037 image. The uplink is named `uplink0` by
  `60-katmate-uplink.link` on `Path=pci-0000:00:04.0`, and dhcpcd holds it;
  `20-uplink.network` is gone (R3, R6; G2). The MAC is unchanged.]**
  (`38:05:25:34:7c:47`, `Link is Up 1Gbps/Full`, `firmware-realtek` loaded,
  DHCP lease **`10.3.1.103`** confirmed by host ARP scan on 2026-08-19 — it was
  **`10.3.1.104`** on 2026-08-11, and the lease moving is the rule holding, not
  a drift: the lease is volatile and only the MAC identifies the guest) and the
  internal p2p segment on its **derived** MAC **`52:54:00:21:b2:08`**, measured
  live 2026-08-19 — emitted as `KM_MAC_INT` and carried into QEMU's argv as
  `-device virtio-net-pci,netdev=int0,mac=…`. **[2026-09-27: the argv half of
  that sentence is no longer true. The shipped `katmate-sys-driver@.service`
  (`a36bdb2`) carries no `int0` device and never reads `KM_MAC_INT`; its argv
  has 0 `tap,` netdevs and 16 `dgram,` (`pool-fold-report.md` § 2.6). The
  generator still emits the key for `sys`, with no consumer (open problem
  #41).]** **This entry published the
  authored `52:54:0a:64:01:01` until that run**; the *Invariants* entry below
  carries why it changed and what still uses the old value. **Interface
  names are not normative and have moved across sessions** **[2026-09-27:
  false for the uplink on the ADR-037 image. `uplink0` is load-bearing, because
  dhcpcd's `allowinterfaces` and the ruleset's `oifname` use it (R3). The slot
  names `km00`…`km0f` were already load-bearing (ADR-035's 2026-09-20
  note).]** (`enp0s6` on the
  retired pet, `enp0s4`/`enp0s5` on the declarative build) — read the MACs, not
  the names (see *Invariants*). The uplink deltas (`firmware-realtek`,
  `20-uplink.network`, cleaned `interfaces`) are baked by the manifest, not
  hand-applied. **[2026-09-27: on the ADR-037 image the uplink is `uplink0`,
  held by dhcpcd, and `20-uplink.network` is gone (R3, R6; G2). The text is
  left as written.]**
  **In-guest status:** `netvm-agent` is live-gated on PING / NETCFG / SHUTDOWN
  (ADR-024, ADR-025), so the control path is no longer the gap; root is
  deliberately unlocked for console observation (open problems #11/#12) — from
  a **rotated** `KATMATE_DEV_ROOT_HASH` as of the 2026-09-05 build, proved by a
  login and not by the build's read-back (#29, now closed). Still
  unverified from inside: **WireGuard/ProtonVPN bring-up** and the DNS-leak
  policy. **[Note 2026-09-27: the ADR-037 image carries no WireGuard config**
  (R20, `proton.conf.template` removed), so there is no bring-up to verify.
  A VPN is a post-install option through the config disk (R8), not
  implemented. **The DNS policy is ADR-037's** (R5, with R17 and R18), and G4
  measured it on 2026-09-27: a fixture peer on slot 05 was answered by
  `10.100.1.1`, and the uplink lease gave no answer.**]** The peer end of the
  internal segment does not exist — personalVM was deleted and no AppVM carries a network device yet (ADR-029 C2).
  `memlock` via `LimitMEMLOCK=infinity` (unit) or `ulimit -l
  unlimited` (manual launch). Runs independently of app_web.
  **WHAT IS RUNNING TODAY IS NOT THIS UNIT (2026-09-05; unit corrected
  2026-09-07).** **[2026-09-27: no longer true — netVM now runs under the
  shipped `katmate-sys-driver@netvm.service`, into which the pool was folded;
  see the block *NETVM RUNS UNDER THE SHIPPED UNIT (2026-09-27)* below.]**
  netVM is started by `katmate-pool@netvm.service`, the ADR-035
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
  since 2026-09-12 09:59:37 CEST.** **THAT SENTENCE STOPPED BEING TRUE ON
  2026-09-19 02:26:54 CEST** — it is left as published, and what ended it is
  the block *The apparatus described above and below is destroyed* below. The prior MainPID 943031 died in a
  `systemctl restart` deliberately run with no sweep and no `ExecStopPost=`:
  all sixteen `netvm` nodes rebound at new inodes and no `EADDRINUSE`
  occurred (source: `g5b-restart-report.md`) — while
  `katmate-sys-driver@netvm.service` is **inactive**. The two must never run
  at once: same instance name, same LV, same CID, same VFIO device.
  **[2026-09-27: there is now one unit. `katmate-pool@.service` has left
  `/etc` and `katmate-pool@netvm` is `not-found` (`pool-fold-report.md`
  § 2.5).]** The pool
  unit replaces the single `tap-int0` device with sixteen `dgram` slots, so
  the guest carries **no internal-segment interface and eighteen links, not
  nineteen**; host-side `tap-int0` and its networkd `.netdev`/`.network` are
  untouched and still exist. **[2026-09-27: no longer true — both files were
  moved to `~/katmate-dev/removed-0927/` and the link deleted; see the
  2026-09-27 block below.]** Two untracked, per-machine files carry it, both
  under `/etc` and both surviving a host reboot that the FIFO does not:
  `/etc/systemd/system/katmate-pool@.service` and
  `/etc/systemd/system/katmate-pool@.service.d/90-dev-monitor.conf`
  (`71b3b5db…`, unchanged). **[2026-09-27: neither is in `/etc` any more. The
  drop-in went on 2026-09-26 (R1). The pool unit was moved to
  `~/katmate-dev/removed-0927/` when it was folded into the tracked
  `katmate-sys-driver@.service` (`pool-fold-report.md` § 2.5).]**
  **The one-shot first-stop observation has been spent** — G1b took it, and it is the finding that QEMU does not unlink its
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

  **THE APPARATUS DESCRIBED ABOVE AND BELOW IS DESTROYED (read 2026-09-20,
  from the Acer; MINIS was not contacted by the session that wrote this).**
  MINIS rebooted on **2026-09-19 07:20:46 CEST** — the journal's boot list opens
  boot 0 there, while `uptime -s` reports **07:19:55**, and both figures are in
  the evidence. The previous boot ended **02:26:54** that day, when netVM's QEMU
  took **SIGTERM from pid 1** and `katmate-pool@netvm.service` deactivated
  cleanly after **6 d 16 h 27 min 16.821 s** of wall clock. That closes on the
  2026-09-12 09:59:37 start **to the second**, so **MainPID 3628111 held
  `NRestarts=0` for its entire life and died with the host — not killed, not
  crashed**. The same line carries two numbers nothing else records: 1 h 10 min
  6.551 s of CPU and a **1G memory peak** over the full six-day run. **Cause:
  the operator ran `pacman -Syu` on MINIS and rebooted** — ordinary maintenance,
  not a fault (`auditfix-liveread-report.md` §§ 2.0, 2.1, 6.1). Both *"has any
  katmate unit run since this boot?"* queries returned **empty with `journalctl`
  exit 0**, so the absence is a real absence and not a failed query: **no
  KatMate unit has run at all since 07:20:46**, and both templates are `static`,
  so nothing starts netVM at boot (liveread §§ 2.1, 2.3).

  **Gone:** the netVM process; `/run/katmate/link/netvm/` and the entire slot
  tree; `/run/katmate-dev/` and its console FIFO; the transient holder; slot
  **00**'s restart-survived binding; slot **01**'s release; slot **02**'s link
  **202**; all three fixtures; and all five `/tmp` instruments (`g2fix.py`,
  `g2icmp.py`, `g34arp.py`, `g34resp.py`, `g34-conrun.sh`), each confirmed
  absent by name (liveread §§ 2.0, 6.1).

  **Survived, and what survived is the configuration rather than the state:**
  `/etc/systemd/system/katmate-pool@.service` at `1d727b25…`, **13021 B**, and
  its drop-in at `71b3b5db…` — **both bit-identical to the values this section
  already publishes**, which is what makes them a check and not a note; the
  RTL8125 `0000:01:00.0` still bound to `vfio-pci`, so the host has not taken
  the uplink NIC back; `vm_sys_netvm` present, **`Open count: 0`**, no `jbd2`
  thread; `tap-int0` present and DOWN (liveread §§ 2.1, 2.4).

  **The consequence, and it is what the next session inherits: every ADR-035
  gate reading taken against a live fixture is historical and cannot be
  extended, only re-taken.** That covers **G2, G3, G4 and G5b** of the
  2026-09-12 … 2026-09-14 arc and **G5a**'s `RuntimeDirectoryPreserve=`
  readings — every one of which named a bound fixture, a slot inode or a peer
  PID. **Nothing in ADR-035's substantive findings is contradicted; what is gone
  is the apparatus, not the measurements.** Starting netVM now would restore a
  guest, sixteen slots and — only after the FIFO is dealt with — a console; it
  would restore no fixture, no binding and no counter epoch (liveread §§ 6.1,
  6.4).

  **The cross-slot neighbour entry is neither present nor gone, and recording it
  as either would be false.** `10.100.1.17 dev km02` lived in the guest kernel's
  neighbour table and died with the process on 2026-09-19 02:26:54. It was last
  read on **2026-09-14 at 43 h 29 m of age**. **Only a bound can be stated:** it
  existed at most **6 d 13 h 37 m 18 s** after the planting frame of 2026-09-12
  12:49:36 CEST, and the **4 d 16 h 8 m** between the last reading and the
  shutdown is **unwitnessed and now unwitnessable** — no instrument was watching
  and the table went with the process. It is **not expired** and it **did not
  persist**; both readings are unavailable. Re-opening the durability question
  needs the frame replanted on a fresh netVM (liveread § 2.7).

  **The `208/STDIN` trap is armed on both units.** Both `90-dev-monitor.conf`
  drop-ins survived in `/etc` — pool at `:31`, sys-driver at `:28`, both setting
  `StandardInput=file:/run/katmate-dev/netvm-console.in`, which `systemctl show`
  resolves to a bare `StandardInput=file` with **no path visible** — while the
  tmpfs FIFO and the transient holder did not. **The next `systemctl start` of
  *either* unit fails above `ExecStart=`, no `ExecStartPre=` runs, and the
  journal names the directive's category but neither the path nor the drop-in.**
  § *Invariants & gotchas* predicted this exactly and now carries it as a live,
  confirmed precondition; the repair is the operator's and is unmade (liveread
  §§ 2.0, 2.3, 6.2).
  **Re-armed again by the boot of 2026-09-25 (14:00:27):** both drop-ins
  present, same sizes and dates, `/run/katmate-dev/` absent, both units
  `inactive` (`appweb-m1-rerun-report.md` § RA, item 7). **The repair choice is
  still open** (operator, 2026-09-26).
  **Ruled and applied 2026-09-26 (R1):** both `/etc` drop-ins removed,
  `StandardInput=null` restored on both units (`net-up-report.md` § 14).

  **NETVM IS RUNNING AGAIN (2026-09-26).** The blocks above are left as
  published. `katmate-pool@netvm.service` was started at **15:40:36 CEST**:
  MainPID **605841**, invocation **`0fccdf5e59d04b03b977ed2373957e8f`**,
  `NRestarts=0`; `katmate-sys-driver@netvm` inactive throughout
  (`net-up-report.md` §§ 16.1, 20). **The console is per-session and lives
  entirely on tmpfs:** the drop-in is
  `/run/systemd/system/katmate-pool@.service.d/90-dev-monitor.conf` only —
  the saved pool content, `71b3b5db…`, installed unedited, so its own comment
  still speaks of `/etc` — with the FIFO `/run/katmate-dev/netvm-console.in`
  and the transient holder `km-console-holder`, MainPID **605265**, `comm=sleep`
  with fd 3 on the FIFO since the rendezvous (§§ 15, 16.2). **Both `/etc`
  drop-ins are removed**; copies are at `~/katmate-dev/removed-0926/` on MINIS,
  `host:host 0644` (§ 14). The guest holds lease **`10.3.1.103`**; the uplink
  is `enp0s4` **[2026-09-27: `uplink0` on the ADR-037 image]** ↔
  **`38:05:25:34:7c:47`** at guest `00:04.0`, settled at
  **100 Mbps/Full (downshifted)** after two 1 Gbps up/down cycles (§§ 16.5,
  17.1, 19.2). The console was left at the login prompt (§ 20). **That a reboot
  now leaves no `208/STDIN` trap is UNVERIFIED** until the next host boot; it is
  settled by `systemctl show -p StandardInput,DropInPaths` on both units after
  that boot (`null`, empty) and a successful start with no `/run/katmate-dev/`
  (§ 23). **[Settled 2026-09-27: after the 10:30:45 boot both units read
  `StandardInput=null` with empty `DropInPaths=`, and the folded unit started
  successfully with no `/run/katmate-dev/` (`pool-fold-report.md` §§ 2.1,
  2.6).]** A stop or a reboot removes the console entirely, and the `/run`
  placement awaits the operator's ruling (R9; § 24). **[Ruled 2026-09-27
  (R9): per-session only, in
  `/run/systemd/system/<unit>.d/90-dev-monitor.conf`, never in `/etc`.]**

  **NETVM RUNS UNDER THE SHIPPED UNIT (2026-09-27).** The blocks above are left
  as published. netVM was started at **10:50:33 CEST** by
  **`katmate-sys-driver@netvm.service`**, the tracked unit with the ADR-035
  slot pool folded in (`a36bdb2`, with the R9 comment `70b08c7`), installed at
  `/usr/lib/systemd/system/katmate-sys-driver@.service`, `a378f875…`,
  14463 B: MainPID **11761**, invocation
  **`f1a996dd5ecc4868b6620f72c451d943`**, `NRestarts=0`, all three
  `ExecStartPre=` `status=0` (`pool-fold-report.md` §§ 2.5, 2.6).
  **[2026-09-27: MainPID 11761 is dead. It was restarted on the new unit as
  123155, and then started on the ADR-037 image as 50080; see the block
  below.]** **There is
  no console:** `StandardInput=null`, empty `DropInPaths=`, and no
  `/run/katmate-dev/`. **[2026-09-27: no longer true until the next host
  reboot. A per-session console is present in `/run`; see the block
  below.]** **`katmate-pool@netvm.service` is `not-found`.** Two
  files are saved, not deleted, in `~/katmate-dev/removed-0927/` on MINIS,
  **`root:root`** because a root script created them (the parent
  `katmate-dev/` is `host:host`): the pool unit `katmate-pool@.service`
  (`1d727b25…`, 13021 B) and the pre-fold `katmate-sys-driver@.service`
  (`813f27c8…`, 9403 B) (§ 2.5). **Host-side `tap-int0` is gone** (Phase M
  of `wp-0927`, 11:07:10 CEST). Its `.netdev` (`e0ff450d…`) and `.network`
  (`1d8f66a0…`) are in the same directory, `cmp`-identical to their originals.
  `ip link show tap-int0` answers *Device "tap-int0" does not exist.*, and
  netVM's MainPID and invocation did not change. The other five networkd
  links on the host are untouched (see the 2026-09-27 entry's finding).
  **[2026-09-27, host-cleanup: those five are gone too. Their files are in
  `~/katmate-dev/removed-0927b/networkd/`, the links are deleted, and networkd
  now manages no link. MainPID and invocation are again unchanged (hc).]**

  **NETVM ON THE ADR-037 IMAGE (2026-09-27).** The blocks above are left as
  published. `vm_sys_netvm` was removed and rebuilt by `build/netvm.sh` as a dev
  build (R27): **`NETVM_BUILT=2026-09-27T13:01:13Z`**, kernel
  **`6.12.107+deb13-amd64`**, and the meta carries
  `UPLINK_PCI_ADDR=0000:00:04.0`. `katmate-sys-driver@netvm.service` (installed
  copy `737d7ad9…`, equal to the tree at `c37f9d1`, argv
  `vfio-pci,host=0000:01:00.0,addr=0x4`) was started on it at 15:03:39 CEST:
  MainPID **50080**, invocation **`caa8c62c1cf742d0a989a6e04601c0dc`**,
  `NRestarts=0`, 16 of 16 slot bindings, PING OK (B, step 10).
  **[2026-09-27, r8-impl-B: superseded. The image is now
  `NETVM_BUILT=2026-09-27T18:34:22Z`, MainPID `88010`, and the installed unit
  equals the tree at `5bc028a`; see *NETVM ON THE STEP-3 IMAGE* below.]**
  - **The uplink is `uplink0`** (`ID_NET_LINK_FILE=…/60-katmate-uplink.link`,
    G2), `38:05:25:34:7c:47` at guest `0000:00:04.0`, lease **`10.3.1.103`**
    (confirmed by host ARP scan). **[2026-09-27, r8-impl-B: the uplink is now
    static, `10.3.1.172/24`, from the T1; no lease is taken.]**
  - **dhcpcd** holds the uplink (`allowinterfaces uplink0`). **dnsmasq**
    answers DNS on the slots (wildcard bind, `-I lo`). **systemd-networkd, its
    socket and wait-online are disabled** (`inactive / disabled`).
    `nftables` is active, with `oifname "uplink0"` in `forward` and `nat`.
  - **`libdbus-1-3 1.16.2-2` is installed (V1); the dbus daemon is absent**
    (`dbus` `un`, no `dbus-daemon`, no `/run/dbus`).
  - **A console is present in `/run` until the next reboot.** The drop-in
    `/run/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf`
    (the saved sys-driver copy `b44de3a9…`, installed unedited), the FIFO
    `/run/katmate-dev/netvm-console.in`, and the holder `km-console-holder`
    (MainPID 49840, `comm=sleep`). The console is logged out. **[2026-09-27,
    r8-impl-B: this console went with the reboot before the rebuild. A new
    one is present, per session, in the same `/run` form; see the block
    below.]**
  - **A dead `appvm` socket node in slot 05**
    (`/run/katmate/link/netvm/05/appvm`, inode 4485), left by the G4 fixture
    under its no-unlink rule. A reboot removes it. **[2026-09-27, r8-impl-B:
    gone with the reboot before the rebuild.]**
  - **`km02` and `km05` are UP with IPv6 link-local addresses only**, and
    carry no IPv4 address or route, after NETCFG ADD/REMOVE by G3 and G4 (open
    problem #45).
  - The new LV holds `jbd2/dm-8-8`. **A reboot is due before the next
    `netvm.sh`.** **[2026-09-27, r8-impl-B: that LV was removed after a
    reboot and rebuilt; the new one holds `jbd2/dm-9-8`.]**

  **NETVM ON THE STEP-3 IMAGE (2026-09-27).** The block above is left as
  published, with dated notes. Networking arc step 3 (the config disk and the
  static uplink) is installed and gated (r8-impl-B, cited as B; ADR-037's note
  on the step-3 gates). After the operator's reboot and with suspend masked,
  `vm_sys_netvm` was removed at 20:19:45 CEST and rebuilt by `build/netvm.sh`
  as a dev build (R27), 20:20:19–20:34:22 CEST, `rc=0`:
  **`NETVM_BUILT=2026-09-27T18:34:22Z`**, kernel `6.12.107+deb13-amd64`,
  `UPLINK_PCI_ADDR=0000:00:04.0`. The installed host set equals the tree at
  `5bc028a` (9 of 9 by sha256, re-verified after the reboot).
  **[2026-09-28, f12-impl-B: this image was removed after a reboot and
  rebuilt as `2026-09-28T17:38:12Z`; see *NETVM ON THE STEP-3A IMAGE*
  below.]**
  - **`katmate-sys-driver@netvm.service`: MainPID `88010`**, invocation
    `02a2b425ebce4dfab4c9fbf823ee6160`, `NRestarts=0`, since 22:20:12 CEST.
    **[2026-09-28: superseded, MainPID `49895`; see below.]**
  - **The uplink is static: `10.3.1.172/24`** on `uplink0`, gateway and
    resolver `10.3.1.1`, from the operator's T1
    `/etc/katmate/vm/netvm.d/uplink` (`root:root 0644`, 72 B, `6cf06c02…`).
    **It stays.** Every netVM start now takes the static path; removing the
    file (or `netvm.d/`) and restarting returns netVM to DHCP.
  - **The config disk is attached at `0x15`** (`virtio-blk-pci,drive=cfg0,
    addr=0x15,serial=kmcfg`, `readonly=on`; guest `vdb`, `ro=1`). Its image
    is `/run/katmate/cfgdisk/netvm.img`, `0:0 600`, **`e960fadc…ea1c`**.
  - **A console is present in `/run` until the next reboot**, per session:
    the drop-in `90-dev-monitor.conf` (`b44de3a9…`, unedited), the FIFO
    `/run/katmate-dev/netvm-console.in` and `km-console-holder` (MainPID
    46385). **The console is logged out.** **[2026-09-28: that console went
    with the reboot of 19:12:42; a new one is in place, holder MainPID
    `49601`; see below.]**
  - **The new LV holds `jbd2/dm-9-8`** (`Open count: 1`). **A reboot is due
    before the next `netvm.sh`.** Suspend is unmasked. **[2026-09-28: that
    reboot was taken and the LV rebuilt; the rebuilt LV holds `jbd2/dm-9-8`
    again, so a reboot is due again; see below.]**
  - **The LAN's DHCP server may still hold a lease for `10.3.1.103`** on the
    uplink MAC. It was never released: dhcpcd's `ExecStop` never ran, because
    QEMU is stopped by signal.

  **NETVM ON THE STEP-3A IMAGE (2026-09-28).** The block above is left as
  published, with dated notes. Networking arc step 3a (the finding-12 slot
  guard) is built and gated (f12-impl-B, `f12-impl-B-report.md`, outside the
  repository; ADR-035's and ADR-037's notes of 2026-09-28). After the
  operator's reboot (boot 2026-09-28 19:12:42) and with suspend masked,
  `vm_sys_netvm` was removed at 19:24:06 CEST and rebuilt by `build/netvm.sh`
  as a dev build, 19:24:14–19:38:12 CEST, `rc=0`:
  **`NETVM_BUILT=2026-09-28T17:38:12Z`**, kernel `6.12.107+deb13-amd64`,
  `UPLINK_PCI_ADDR=0000:00:04.0`. The installed host set equals the tree at
  `81e0736` (9 of 9 by sha256, before and after the reboot).
  **[2026-09-29, s4a-impl-B: the installed set now equals the tree at
  `46f8a26`, 10 of 10 by sha256. See *THE FIRST ROUTED APPVM UNIT* below.
  The sentence is left as written.]**
  - **`katmate-sys-driver@netvm.service`: MainPID `49895`**, invocation
    `1d1b5f667cb34f958e7ce6f682968db5`, `NRestarts=0`, since 19:39:06 CEST.
  - **The guard is in the ruleset:** chain `slot_guard` in `table inet
    filter`, sixteen `return`s and three counted drops (R49, R50, rule 18),
    jumped as rule 1 of `input` and `forward` (F12a). `log_martians` on
    `km05`, enabled for row 2c only, is back to 0 (read back).
  - **`rp_filter` is adopted explicitly** (R51 in R57's form, in
    `30-netvm-forward.conf`): `all` 0, and 2 on the other 19 of 20 conf dirs,
    read after the rebuild.
  - **The uplink is static, `10.3.1.172`**, from the unchanged T1
    (`6cf06c02…`). **It held across the host reboot**, read by the host's
    ARP scan: one observation (HOST-CONFIG § 12, note of 2026-09-28). The
    config disk image is `e960fadc…ea1c`, as on 2026-09-27.
  - **A console is present in `/run` until the next reboot**: the drop-in
    `b44de3a9…` (unedited), the FIFO, and `km-console-holder` (MainPID
    `49601`). **The console is logged out.**
  - **Stale `appvm` socket nodes on slots 02 and 05** (inodes 4647 and
    4655), left by F12b's fixture peers after NETCFG REMOVE, as planned. A
    reboot removes them. The `km02`/`km05` link state after REMOVE, and
    netVM's neighbour entries for `.18` and `.21`, were not read.
  - **The new LV holds `jbd2/dm-9-8`. A reboot is due before the next
    `netvm.sh`.** Suspend is unmasked.

  **THE FIRST APPVM ON A SLOT (2026-09-28, fixture).** The block above is
  left as published. Networking arc step 4.0 ran `app_web`'s image and
  kernel on slot 01 under a fixture launcher outside the repository
  (s4-m0, `s4-m0-report.md`, outside the repository; ADR-035's and
  ADR-037's notes of 2026-09-28). As left at 22:01:59 CEST (M § 3, end
  state):
  - **netVM unchanged:** MainPID `49895`, invocation `1d1b5f66…`,
    `NRestarts=0`, throughout. Its `slot_guard` counters stand at R49 5,
    R50 25 and rule 18 10, all F12b's.
  - **Slot 01 is clean:** link 201 removed by NETCFG REMOVE, the fixture's
    `appvm` node unlinked; slot 01 holds `netvm` only. The stale `appvm`
    nodes on slots 02 and 05 from F12b are untouched.
  - **`vm_app_web`, `vm_tpl_foundation` and `vm_app_web_home` are left
    active.** Of the three, only `vm_app_web` was activated by the fixture;
    the other two were already active before it (M § 1).
  - The console is logged out; holder `49601`, drop-in and FIFO in `/run`
    until the next reboot. Suspend was never masked.
  - **Session files**, the fixture (`km-appweb-net.sh`, `d367b488…`), the
    drivers, three pcaps `cap-{A,B,C}.pcap` and three serial dumps
    `serial-{A,B,C}.txt` (`root:root`) are in
    `/home/host/katmate-dev/s4m0/`. All are fixtures, not live
    configuration. The pcaps and dumps were not copied to the Acer.
  - **A reboot is still due before the next `netvm.sh`** (`jbd2/dm-9-8`,
    not re-read by s4-m0).

  **THE FIRST ROUTED APPVM UNIT (2026-09-29, 4a-B).** The blocks above are
  left as published. Networking arc step 4a is installed, and
  `katmate-app-routed@app_web` ran for the first time
  (`s4a-impl-B-report.md`, outside the repository, § 6; ADR-037's note of
  2026-09-29). As left at 09:39 CEST:
  - **netVM unchanged:** `katmate-sys-driver@netvm`, MainPID `49895`,
    invocation `1d1b5f66…`, `NRestarts=0`, since 2026-09-28 19:39:06, not
    restarted. **Its loaded unit carries the new sixteen-path
    `ExecStopPost=`** (`systemctl show` lists it for the running
    instance). It first runs at netVM's next stop.
  - **The installed set equals the tree at `46f8a26`, 10 of 10 by
    sha256**: the seven `/usr/lib/katmate/*` and three units, including
    the new `katmate-app-routed@.service`. The hash-first check expects
    these values, not `81e0736`'s.
  - **`app_web`:** T1 **routed** (`netvm = "netvm"`, `be542506…`); the
    previous T1 is saved as `/home/host/katmate-dev/s4a/app_web.toml.pre`.
    Delta **`app_web.qcow2`** (`test_web.qcow2` no longer exists), backing
    `/dev/vg0/vm_app_web`, written by the unit's boot of 09:35–09:36
    (`0e42839e…`). The unit is `inactive` and its projection is absent. A
    new `start` refuses at the generator until an `owner` naming `app_web`
    is written again.
  - **`app_web.con`** now names `app_web` and finds its delta. It must not
    run beside `katmate-app-routed@app_web` (R61), and with this T1 the two
    no longer boot the same machine: the `.con`'s argv has no network
    device.
  - **Slot 01 is FREE:** `netvm` only, no `owner`, no `appvm`, link 201
    removed.
  - **The stale `appvm` nodes on slots 02 and 05** (inodes 4647, 4655)
    are still there.
  - LVs as at the start of B. B did not touch the console holder or the
    `/run` drop-in. Session files (ten scripts, their outputs, four
    journal copies) are in `/home/host/katmate-dev/s4a/`.
  - **A reboot is still due before the next `netvm.sh`**. `jbd2` was not
    re-read.

  **THE FIRST SELF-CONFIGURED APPVM (2026-09-29, 4b-B).** The blocks above
  are left as published; the 4a-B block's `app_web` delta, its hash and
  *"LVs as at the start of B"* are superseded by this one. Networking arc
  step 4b ran on MINIS (`s4b-impl-B-report.md`, outside the repository, §§
  1, 6, 8; ADR-038's and ADR-037's notes of 2026-09-29, step 4b). As left
  at 12:09 CEST:
  - **The new chain:** `vm_tpl_foundation`
    (`BUILD_DATE=2026-09-29T09:47:21Z`, from `647a380`; `foundation.meta`
    `8d90e0f5…`) → `vm_app_web` (`APP_BUILT=2026-09-29T09:50:44Z`;
    `app-web.meta` `54f2f1d6…`) → `instances/app_web.qcow2` (new,
    `host:host 0644`, 10 GiB virtual, written by one boot). Both layers
    carry `/etc/resolv.conf -> ../run/resolv.conf` and no `run/resolv.conf`
    (G3), and `/sbin/init` equal to `out/katmate-init` (`172a28ee…`). Both
    new LVs stay active after their builds (#37); open counts 0.
  - **Set aside, standing, the operator's to remove:**
    `vm_tpl_foundation_pre0929`, `vm_app_web_pre0929`,
    `instances/app_web.qcow2.pre0929` (rebased `-u` onto
    `/dev/vg0/vm_app_web_pre0929`), `foundation.meta.pre0929`,
    `app-web.meta.pre0929`.
  - **`vm_app_web_home`** holds the operator's `user/g1.txt` (mode `0666`,
    #53); unmounted, active.
  - **netVM unchanged:** MainPID `49895`, invocation `1d1b5f66…`,
    `NRestarts=0`, since 2026-09-28 19:39:06. Link 201 was added and
    removed.
  - **Slot 01 is FREE:** `netvm` only, no `owner`, no `appvm`.
    `katmate-app-routed@app_web` is inactive, on the new chain.
  - **The stale `appvm` nodes on slots 02 and 05** (inodes 4647, 4655)
    are still there.
  - The installed host set still equals the tree at `46f8a26`, 10 of 10
    (4b changes no host file). Sleep targets unmasked. The host's
    `/run/resolv.conf` is absent.
  - **`/etc/gai.conf` carries `precedence ::ffff:0:0/96  100`**, appended
    by the operator at 11:42 (#54).
  - **Session files** (scripts, outputs, journals, `g1.txt`, and the
    203 MB foundation build log `p3-foundation.log`) are in
    `/home/host/katmate-dev/s4b/`. Fixtures, not live configuration.
  - **A reboot is still due before the next `netvm.sh`.**

  **THE GATED APPVM (2026-09-29, s4-gates).** The blocks above are left as
  published. This block supersedes the 4b-B block's chain, its hashes and
  its `/sbin/init`, which are now the `_pre0929b` set. s4b2-impl-B rebuilt
  the chain, and s4-gates took the gates on it (`s4b2-impl-B-report.md`
  §§ 1, 6, 8 and `s4-gates-report.md` §§ 1, 8, outside the repository;
  ADR-038's and ADR-037's acceptance notes). As left at 16:01 CEST:
  - **The chain:** `vm_tpl_foundation` (`BUILD_DATE=2026-09-29T13:07:13Z`,
    from `a64c13d`; `foundation.meta` `c0755a04…`) → `vm_app_web`
    (`APP_BUILT=2026-09-29T13:09:27Z`; `app-web.meta` `3b14af60…`) →
    `instances/app_web.qcow2` (`host:host 0644`, 983040 bytes, written by
    s4b2-impl-B's boot and the five gate boots). Both layers carry
    `/sbin/init` equal to `out/katmate-init` (`c3ad714a…`, R91), the
    relative resolver link, and no `run/resolv.conf`. Both new LVs stay
    active after their builds (#37).
  - **Set aside, standing, both the operator's to remove.** `_pre0929` is
    the 2026-09-26 layers: `vm_tpl_foundation_pre0929`,
    `vm_app_web_pre0929`, `instances/app_web.qcow2.pre0929`,
    `foundation.meta.pre0929` and `app-web.meta.pre0929`. `_pre0929b` is
    4b-B's layers: `vm_tpl_foundation_pre0929b`, `vm_app_web_pre0929b`,
    `instances/app_web.qcow2.pre0929b` (rebased `-u` onto
    `/dev/vg0/vm_app_web_pre0929b`), `foundation.meta.pre0929b` and
    `app-web.meta.pre0929b`.
  - **`vm_app_web_home`** holds `user/g1.txt` (`0666`, written before
    R91), the gate files `g2p.txt`, `g5p.txt`, `g5n.txt` and `umask-probe`
    (all `0644`), and `.bash_history`. It is unmounted and active.
  - **netVM unchanged:** MainPID `49895`, invocation `1d1b5f66…`,
    `NRestarts=0`, since 2026-09-28 19:39:06. **The dev console is logged
    out** (`localhost login:`, R94 (2)). The `/run` drop-in
    `90-dev-monitor.conf`, the FIFO and the holder (MainPID 49601) stay
    until the next reboot.
  - **Slot 01 is FREE:** `netvm` only, no `owner`, no `appvm`, and link
    201 removed. `katmate-app-routed@app_web` is inactive with no drop-in,
    and no `90-gate.conf` exists under `/run/systemd` or `/etc/systemd`.
  - **The stale `appvm` nodes on slots 02 and 05** (inodes 4647, 4655)
    are still there.
  - The installed host set equals the tree at `a64c13d`, 10 of 10. 4b2
    changes no host file, so these are the same hashes as at `46f8a26`.
    The sleep targets are unmasked. `ip -6 rule list` carries no pref-100
    rule: R93's rule was added for the builds and removed. The host's
    `/run/resolv.conf` is absent. `/etc/gai.conf` still carries the
    operator's line (#54).
  - **The host's input chain rejects**, as `wp-0929d`'s P-check read at
    16:22. The only `reject` in the live ruleset is `inet filter input`'s
    `meta pkttype host limit rate 5/second … reject with icmpx
    admin-prohibited` (`/etc/nftables.conf:18`). Its counter read 14
    packets at that reading.
  - **Session files:**
    - `/home/host/katmate-dev/s4b2/`: scripts, outputs, and both build
      logs (foundation, 2270 lines, `3c23c20d…`; app-web, 194 lines,
      `ae836703…`);
    - `/home/host/katmate-dev/s4g/`: scripts, the four drop-in sources,
      journal copies, the three guest files, and the pcaps `cap-g5p.pcap`
      (`1a383fac…`) and `cap-g5n.pcap` (`704e5e5b…`);
    - `/home/host/katmate-dev/wp0929d/pcheck.sh`.

    They are fixtures, not live configuration.
  - **A reboot is still due before the next `netvm.sh`.**

  **NETVM ON THE STEP-4C IMAGE (2026-09-30, s4c-b).** The blocks above are
  left as published. This block supersedes their netVM MainPID, image,
  console holder, stale `appvm` nodes and installed-set hashes. As left at
  17:03:36 CEST (`s4c-b-report.md`, outside the repository):
  - **Host boot 2026-09-30 16:16:21.** The `/run` state of every block above
    is gone with it.
  - **Installed host set equals the tree at `6023a86`, 10 of 10**:
    `katmate-sys-driver@.service` is `0aa40135…` (with `ipv6.disable=1`),
    and the other nine are unchanged.
  - **`vm_sys_netvm`: `NETVM_BUILT=2026-09-30T14:37:22Z`, guest kernel
    `6.12.111+deb13-amd64`**, `UPLINK_PCI_ADDR=0000:00:04.0`, dev build
    (root unlocked). It bakes `out/netvm-agent` `4a4e0715…` (335168 B,
    built on MINIS from `6023a86`).
  - **`katmate-sys-driver@netvm.service`: MainPID `46612`**, invocation
    `b9475ec3051142ff9200a16b42b912d7`, `NRestarts=0`, since 16:40:17. Static
    uplink `10.3.1.172/24` from the unchanged T1 (`6cf06c02…`), config disk
    `e960fadc…`. The link came up `1Gbps/Full` at boot; a later downshift
    was not read.
  - **The console is logged out** (`localhost login:`). The drop-in
    `b44de3a9…`, the FIFO and `km-console-holder` (MainPID 46330) stay in
    `/run` until the next reboot.
  - **The pool:** 16 `netvm` nodes, and one stale `appvm` on slot 02
    (inode 5354, this session's ARP fixture; a reboot removes it). Slot 01
    holds `netvm` only, with no owner. `/run/netvm-agent/` is empty, and
    every `km*` is DOWN.
  - `katmate-app-routed@app_web` is inactive, on the unchanged chain
    (`app_web.qcow2` written by one more boot).
  - **`jbd2/dm-9-8` is held** (Open count 2 with netVM running). **A reboot
    is due before the next `netvm.sh`.** Suspend is unmasked.
  - **Session files:** `/home/host/katmate-dev/s4cb/` (scripts, the build
    log `3c0a1ab4…`, and fixture logs). They are fixtures, not live
    configuration. `out/netvm-agent` was replaced, and the 2026-07-23
    binary (`0a155800…`) is not kept.

  **TWO APPVMS ON ONE NETVM (2026-10-02, ai1).** The block above is left as
  published. Its stale `appvm` on slot 02 (inode 5354) is gone. Otherwise
  it still holds, and was re-read at 08:27 and 12:29 CEST
  (`ai1-report.md`, outside the repository):
  - **No host reboot since 2026-09-30 16:16:21.** netVM is MainPID `46612`,
    invocation `b9475ec3…`, `NRestarts=0`, throughout. The installed set
    equals the tree at `f9c98a7`, 10 of 10 (the same hashes as `6023a86`).
  - **The pool:** 16 `netvm` nodes and nothing else. No owner, no `appvm`,
    every `km*` DOWN, `/run/netvm-agent/` empty.
  - **Both AppVM units inactive.** `/run/katmate/vm/` keeps both projections
    (`app_web.env`, `app_personal.env`), as a projection survives a stop.
  - **The console is logged out**, and the holder (46330), FIFO and `/run`
    drop-in stay until the next reboot.
  - **Hugepages:** 4096 × 2 MiB, set by `/etc/sysctl.d/hugepages.conf`
    (`vm.nr_hugepages = 4096`), all free at the end. It holds `app_web`
    (4G) and `app_personal` (2G) at once.
  - **`jbd2/dm-9-8` is held** (`vm_sys_netvm`, Open count 2). **A reboot is
    still due before the next `netvm.sh`.** Suspend was not masked.
  - **The `waypipe-client` user unit** (`3ddc65b0…`, untracked, #31) ran
    as PID 1409 since 2026-09-30 16:20:37, with `NRestarts` 0, and carried
    both AppVMs' windows. **`vsock_diag` is not loaded** on this host, so
    `ss --vsock` shows no vsock socket at all. That is a check that cannot
    fire, not an absent listener.
  - **Session files:** `/home/host/katmate-dev/ai1/`. Fixtures, not live
    configuration.

  **NAMED APPVMS ON NEW LAYERS (2026-10-02, ai2).** The blocks above are
  left as published. This block supersedes their host boot, netVM MainPID,
  chain, deltas, hugepage figure and installed-set hashes. As left at
  14:30:49 CEST (`ai2-report.md`, outside the repository):
  - **Host boot 2026-10-02 14:03:24** (`uptime -s`; the journal's boot
    starts at 14:11:31, after the LUKS passphrase), kernel
    **`7.2.8-hardened1-1-hardened`**. The `/run` state of every block above
    is gone with it.
  - **Hugepages: 6144 × 2 MiB = 12 GiB** (R126), from
    `/etc/sysctl.d/hugepages.conf` `vm.nr_hugepages = 6144` (`cf13b418…`).
    All free at the end. `MemTotal` 31611736 kB, so the host keeps
    18.15 GiB. The previous file is kept as
    `/home/host/katmate-dev/ai2/hugepages.conf.pre-ai2`.
  - **The chain:** `vm_tpl_foundation` (`BUILD_DATE=2026-10-02T12:17:17Z`,
    from `db1d153`; `foundation.meta` `ced078d4…`; 209 packages) →
    `vm_app_web` (`APP_BUILT=2026-10-02T12:19:05Z`; `app-web.meta`
    `d8ced397…`; 230 packages) → `instances/app_web.qcow2` and
    `instances/app_personal.qcow2` (new, `host:host 0644`, 10 GiB virtual,
    each written by one boot). Both layers carry `/sbin/init` equal to
    `out/katmate-init` `8163e103…` (R125 in it), the relative resolver
    link, and no `run/resolv.conf`.
  - **Set aside, ai2's rollback (`_pre1002`):** `vm_tpl_foundation_pre1002`,
    `vm_app_web_pre1002`, `instances/app_web.qcow2.pre1002` and
    `app_personal.qcow2.pre1002` (both rebased `-u` onto
    `/dev/vg0/vm_app_web_pre1002`), `foundation.meta.pre1002` and
    `app-web.meta.pre1002`. **A rollback is a rename back.** These are
    removed after the operator's verdict on ai2.
  - **Still standing: the `_pre0929` and `_pre0929b` sets**, as in *THE
    GATED APPVM* above. ai2's guarded removal (ruling 1(b)) left all four
    LVs, because `app_web.qcow2.pre0929` and `.pre0929b` name the app
    layers.
  - **netVM** `katmate-sys-driver@netvm`: **MainPID `22405`**, invocation
    `ca5f364ef5814b8bafe61a6481d9c657`, `NRestarts=0`, since 14:19:30, on
    the unchanged image (`NETVM_BUILT=2026-09-30T14:37:22Z`) and T1
    (`6cf06c02…`). The console is at `localhost login:`, and nobody logged
    in. The drop-in `b44de3a9…`, the FIFO and `km-console-holder` (MainPID
    22121) stay in `/run` until the next reboot. **No `jbd2` hold on
    `vm_sys_netvm`** (dm-11; no netVM build this boot), so no reboot is due
    before the next `netvm.sh` unless something mounts it.
  - **The pool:** 16 `netvm` nodes, no owner, no `appvm`. Links 201/202
    removed.
  - **Both AppVM units inactive.** Each was booted once on the new chain
    (14:19:58 and 14:20:07), named itself, and was shut down by SHUTDOWN.
  - **Installed host set:** 9 of 10 equal the tree at `8acd433`.
    `katmate-app-routed@.service` is `365ffa22…` (with `km.name=%i`).
    **`katmate-lib.sh` is `8c221ae0…`, not the tree's `c5c2db32…`**: `8cb5fb9`
    is not installed. The hash-first check should expect exactly that one
    difference.
  - **Sleep targets unmasked** (`static`). `ip -6 rule` 100 present (R98).
  - **Session files:** `/home/host/katmate-dev/ai2/` (scripts, both build
    logs `189ae05a…` and `cf7bd5a2…`, and the package lists). Fixtures, not
    live configuration.

  **THREE APPVMS ON ONE NETVM, AND A CLEAN VG0 (2026-10-02, ai3).** The
  blocks above are left as published. This block supersedes their chain,
  deltas, set-aside sets, installed-set hashes and `out/vm-agent`. As left
  at 15:32:38 CEST (`ai3-report.md`, outside the repository):
  - **Host boot unchanged** (2026-10-02 14:03:24, kernel 7.2.8-hardened).
    No reboot in ai3.
  - **The chain:** `vm_tpl_foundation` (`BUILD_DATE=2026-10-02T13:03:41Z`,
    from `431ab9e`; `foundation.meta` `81f052e8…`; 209 packages) →
    `vm_app_web` (`APP_BUILT=2026-10-02T13:04:41Z`; `app-web.meta`
    `abb8e780…`; 230 packages) and
    **`vm_app_office`** (`APP_BUILT=2026-10-02T13:06:15Z`; `app-office.meta`
    `b4cfc9ac…`; 356 packages, no JRE) → `instances/app_web.qcow2`,
    `app_personal.qcow2` (on `vm_app_web`) and **`app_work.qcow2`** (on
    `vm_app_office`), each written by one boot. Every layer carries
    `/sbin/init` `8163e103…` and `/usr/local/bin/vm-agent` **`87ebdcaa…`**
    (R130's whitelist), the relative resolver link, and no
    `run/resolv.conf`.
  - **vg0 holds nothing set aside.** Every `_pre0929`, `_pre0929b`,
    `_pre1002` and `_preai3` LV, delta and meta is removed (R132, and
    ai3's own rollback after the run). LVs: `root`, `swap`,
    `vm_tpl_foundation`, `vm_app_web`, `vm_app_office`, `vm_app_web_home`
    (linear), `vm_app_personal_home`, `vm_app_work_home` (both thin),
    `vm_sys_netvm`, and `vm_pool` (0.63 % data, 10.80 % meta).
  - **`out/vm-agent` is `87ebdcaa…`** (built on MINIS from `431ab9e`). The
    2026-09-26 binary is kept as `/home/host/katmate-dev/ai3/vm-agent.pre-ai3`
    (`432c4d17…`), a fixture.
  - **Installed host set equals the tree at `431ab9e`, 10 of 10.**
    `katmate-lib.sh` `c5c2db32…` (R133) and `katmate-generate-env`
    `e96f0382…` (accepts `office`). The hash-first check expects no
    difference.
  - **T1 files:** `netvm.toml`, `app_web.toml`, `app_personal.toml` and
    **`app_work.toml`** (`bd7f7acc…`, cid 23).
  - **netVM unchanged:** MainPID `22405`, invocation `ca5f364e…`,
    `NRestarts=0`. The console is logged out (`localhost login:`). No `jbd2`
    hold on `vm_sys_netvm`.
  - **The pool:** 16 `netvm` nodes, no owner, no `appvm`. Links 201–203
    removed. **All three AppVM units inactive.**
  - Hugepages 6144, all free. Sleep targets unmasked (`static`).
  - **Session files:** `/home/host/katmate-dev/ai3/` (scripts, the three
    build logs, package lists, journal copies). Fixtures, not live
    configuration. The untracked brief `ai3-brief.md` reached
    `~/katmate-build/` with the rsync, and the next `--delete` sync removes
    it once it has left the Acer's tree.

  **FOUR APPVMS ON ONE NETVM, ONE OF THEM OFFLINE (2026-10-02, ai4).** The
  blocks above are left as published. This block supersedes their app
  layers, deltas, T1 list and installed-set hashes. As left at 20:31:45
  CEST (`ai4-report.md`, outside the repository):
  - **Host boot unchanged** (2026-10-02 14:03:24, kernel 7.2.8-hardened).
    No reboot in ai4.
  - **The chain:** `vm_tpl_foundation` unchanged (ai3's,
    `BUILD_DATE=2026-10-02T13:03:41Z`, 209 packages) → `vm_app_web`
    unchanged (230) → `app_web.qcow2`, `app_personal.qcow2`;
    **`vm_app_office`** rebuilt (`APP_BUILT=2026-10-02T17:05:00Z`,
    `app-office.meta` `8b111225…`, 362 packages, with `fonts-liberation`,
    `hunspell-en-us` and `hunspell-sl`) → **`app_work.qcow2`** (recreated);
    **`vm_app_vault`** new (`APP_BUILT=2026-10-02T18:04:47Z`, `app-vault.meta`
    `63cd4d40…`, 285 packages, with `keepassxc` and `qtwayland5`) →
    **`app_vault.qcow2`** (new). Every layer carries `/sbin/init`
    `8163e103…` and vm-agent `87ebdcaa…`. `vm_app_vault` has
    `libpcre2-8-0` deb13u3 against the foundation's deb13u2.
  - **vg0 holds nothing set aside.** `_preai4` (`vm_app_office_preai4`,
    `vm_app_vault_preai4`, and both deltas and metas) is removed. LVs:
    `root`, `swap`, `vm_tpl_foundation`, `vm_app_web`, `vm_app_office`,
    `vm_app_vault`, `vm_app_web_home` (linear), `vm_app_personal_home`,
    `vm_app_work_home`, `vm_app_vault_home` (all three thin),
    `vm_sys_netvm`, and `vm_pool` (0.70 % data, 10.87 % meta).
  - **Installed host set equals the tree at `87bd0ff`, 11 of 11** (ruling
    5 of ai4's read pass). New: `katmate-app-offline@.service` `7151fc2e…`.
    Changed: `katmate-generate-env` `a4817408…`. The hash-first check
    expects no difference.
  - **T1 files:** `netvm.toml`, `app_web.toml`, `app_personal.toml`,
    `app_work.toml` and **`app_vault.toml`** (`675a2614…`, cid 24,
    `netvm = ""`).
  - **netVM unchanged:** MainPID `22405`, invocation `ca5f364e…`,
    `NRestarts=0`. The console is logged out (`localhost login:`). No `jbd2`
    hold on `vm_sys_netvm`.
  - **The pool:** 16 `netvm` nodes, no owner, no `appvm`. Links 201–203
    removed. **All four AppVM units inactive**, and
    `katmate-app-routed@app_vault` is inactive after H2's `reset-failed`.
  - Hugepages 6144, all free. Sleep targets unmasked (`static`).
  - **Session files:** `/home/host/katmate-dev/ai4/` (scripts, the three
    build logs, package lists, journal copies, argv copies). Fixtures, not
    live configuration.

  **FOUR APPVMS ON A REBUILT CHAIN, RUN ENVIRONMENT AND `ip` (2026-10-03,
  ai5).** The blocks above are left as published. This block supersedes
  their chain, layers, metas, deltas and `out/vm-agent`. As left at
  17:19:58 CEST (`ai5-report.md`, outside the repository):
  - **Host boot unchanged** (2026-10-02 14:03:24, kernel 7.2.8-hardened).
    No reboot in ai5.
  - **The chain:** `vm_tpl_foundation` (`BUILD_DATE=2026-10-03T14:37:01Z`,
    from `77f1b72`; `foundation.meta` `cb773d77…`; **216 packages**, with
    `iproute2 6.15.0-1` installed after the purge, and no python3 or
    binutils) → `vm_app_web` (`APP_BUILT=2026-10-03T14:37:57Z`, 237),
    `vm_app_office` (`2026-10-03T14:39:09Z`, 368) and `vm_app_vault`
    (`2026-10-03T14:39:41Z`, 292) → `app_web.qcow2`, `app_personal.qcow2`
    (on web), `app_work.qcow2` (office) and `app_vault.qcow2` (vault), each
    new and written by one boot. Every layer carries `/sbin/init`
    `8163e103…`, **vm-agent `5d35567f…`** (R146), `/usr/bin/ip`, and
    `C.utf8` in `locale -a`.
  - **`out/vm-agent` is `5d35567f…`** (built on MINIS from `2a9e638`). The
    previous binary is kept as `/home/host/katmate-dev/ai5/vm-agent.pre-ai5`
    (`87ebdcaa…`), a fixture.
  - **vg0 holds nothing set aside.** `_preai5` is removed. LVs: `root`,
    `swap`, `vm_tpl_foundation`, `vm_app_web`, `vm_app_office`,
    `vm_app_vault`, `vm_app_web_home` (linear), `vm_app_personal_home`,
    `vm_app_work_home`, `vm_app_vault_home` (thin), `vm_sys_netvm`, and
    `vm_pool` (0.71 % data, 10.85 % meta). The homes were untouched.
  - **Installed host set equals the tree, 11 of 11** (no host file changed
    in ai5). T1 files unchanged.
  - **netVM unchanged:** MainPID `22405`, invocation `ca5f364e…`,
    `NRestarts=0`. The console is logged out. No `jbd2` hold on
    `vm_sys_netvm`.
  - **The pool:** 16 `netvm` nodes, no owner, no `appvm`. **All four AppVM
    units inactive.** Hugepages 6144, all free. Sleep targets unmasked
    (`static`).
  - **Session files:** `/home/host/katmate-dev/ai5/` (scripts, both
    foundation build logs, three app-layer logs, package lists, journal and
    argv copies). Fixtures, not live configuration.

  **The uplink is capped by the cable, and that is a condition of the
  environment rather than a defect.** On the boot of 2026-09-12 the link came up
  1 Gbps, went down, and settled at **100 Mbps/Full (downshifted)**, the driver
  printing *"Downshift occurred from negotiated speed 1Gbps to actual speed
  100Mbps, check cabling!"* (liveread § 2.6). **The LAN run to MINIS is UTP-5,
  not 5e** — operator's statement, 2026-09-20 — so **100 Mbit/s is the cable's
  ceiling**, the downshift warning is expected behaviour, and **every throughput
  measurement taken on this uplink is under a 100 Mbit/s ceiling**. Gigabit
  needs the cable replaced; nothing in configuration reaches it. This entry
  publishes `Link is Up 1Gbps/Full` from the 2026-08-19 reading above; that
  value is left as written, because it is what that link negotiated before the
  downshift, and the 100 Mbps figure is what it settles at. **The driver
  reports 1 Gbps/Full at carrier and downshifts to 100 Mbps within
  milliseconds, so a speed read right after *"Link is Up"* shows 1 Gbps**,
  as s4c-b's B3.3 did at 6.75 s. Read the speed a few seconds after carrier
  (operator's statement, 2026-09-30). The same records
  carry **the one place in that session where a name and a MAC were read
  together and agreed**: `enp0s4` carries **38:05:25:34:7c:47**, and the sixteen
  `.link` files correctly do not glob onto it — the uplink keeps its stage-one
  name. **[2026-09-27: on the ADR-037 image the uplink is renamed a second time,
  `enp0s4` → `uplink0` at 3.44 s, by `60-katmate-uplink.link` (B, step 10;
  G2).]**

  **Slot bindings, as left at the close of the 2026-09-12 gate arc, because
  the next measuring session inherits them.** **[HISTORICAL — every binding
  below was destroyed with the process on 2026-09-19 02:26:54; see the block
  above. Nothing in this paragraph can be inherited, only re-taken.]** Slot **00** — `appvm` inode
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
  **[ALL FIVE ABSENT as of 2026-09-20 — `/tmp` did not survive the reboot; they
  must be rewritten after all. See the block above.]**
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
  **2026-09-26: a new `vm_app_web`**, built by `make app-web` on the rebuilt
  foundation — **230 packages**, the foundation's 209 plus `firefox-esr`,
  `foot`, `pcmanfm` and their 18 dependencies; nautilus absent
  (`appweb-rebuild-report.md` § 5.3). The delta `test_web.qcow2` was
  **recreated 2026-09-26** on it (§ 5.4). **First boot by the operator,
  2026-09-26:** pcmanfm, foot and firefox-esr render via waypipe; `run nautilus`
  is refused; firefox has no internet, as expected — no network device,
  `app-offline` (operator, 2026-09-26).
  **[Operator statement, 2026-09-28: that boot was by `app_web.con`, run as
  `host`.]**
  **[2026-09-29, s4a-impl-B: the delta is now
  `/var/lib/katmate/instances/app_web.qcow2`, renamed from `test_web.qcow2`
  (R69), and the instance has also been booted by
  `katmate-app-routed@app_web` (MainPID 361445, 09:35:14–09:36:42 CEST), on
  slot 01, with a routed T1. See *THE FIRST ROUTED APPVM UNIT* above. The
  text is left as written.]**
  **[2026-09-29, s4b-impl-B: `vm_app_web` is rebuilt on the new foundation
  (`APP_BUILT=2026-09-29T09:50:44Z`, 21 packages installed by the layer),
  and `app_web.qcow2` is a new delta on it; the previous delta is
  `app_web.qcow2.pre0929` on `vm_app_web_pre0929`. See *THE FIRST
  SELF-CONFIGURED APPVM* above. The text is left as written.]**
  **[2026-09-29, s4b2-impl-B and s4-gates: `vm_app_web` is rebuilt again
  (`APP_BUILT=2026-09-29T13:09:27Z`) on a foundation carrying R91, and
  `app_web.qcow2` is a new delta on it. 4b-B's delta is
  `app_web.qcow2.pre0929b`. ADR-038's and ADR-037's gates were taken on it.
  See *THE GATED APPVM* above. The text is left as written.]**
  **[2026-10-02, ai1: booted once more by `katmate-app-routed@app_web` on
  slot 01, beside `app_personal`. `app_web.qcow2` is now 3014656 B.
  `vm_app_web_home` is **linear** (`-wi-a-----`), which disagrees with
  ADR-010's thin home LV (a finding, `ai1-report.md` § 5). Its ext4: no
  label, default features, `user/` `1000:1000 0700`. The T1 `be542506…`
  keeps `identity = false` with its NEEDS REVIEW comment. The text is left
  as written.]**
- **app_personal** (CID **22**, slot **02**, `LINK_ID` **202**; created
  2026-10-02 by `ai1`, the first alpha integration AppVM). `class = app`,
  `manifest = web`, `netvm = netvm`, `persistence = persistent`,
  **`identity = true`** (ADR-014's `personal`), `disposable = false`,
  **`mem = "2G"`**, `vcpus = 2`.
  - **T1** `/etc/katmate/vm/app_personal.toml`, `root:root 0644`,
    `042750bf…`, staged in the Acer's ignored `local/etc/katmate/vm/`.
  - **Delta** `/var/lib/katmate/instances/app_personal.qcow2`, `host:host
    0644`, backing `/dev/vg0/vm_app_web` (raw), 10 GiB virtual: `qemu-img
    create -f qcow2 -F raw -b /dev/vg0/vm_app_web <delta> 10G`, then
    `chmod 0644`, as `host`.
  - **Home LV `vm_app_personal_home`**: 10G **thin in `vm_pool`**
    (`Vwi-a-tz--`, no `k` flag, `dm-13` on this boot). **The form of
    record for a home LV** (ruling of 2026-10-02):
    `lvcreate -V 10G -T vg0/vm_pool -n vm_<instance>_home`; read
    `lvs -o lv_name,lv_attr,pool_lv` (active, no `k`) before anything else;
    `mkfs.ext4 /dev/vg0/vm_<instance>_home` with default options (e2fsprogs
    1.47.4: no label, the same 16 features as `vm_app_web_home`); mount;
    `install -d -o 1000 -g 1000 -m 0700 <mnt>/user`; umount.
  - **Booted once** (2026-10-02 08:33–12:28) by
    `katmate-app-routed@app_personal`: `km.ip=10.100.1.18`, MAC
    `52:54:00:f0:e9:bf`, GUI on MINIS's screen beside `app_web`'s. Its
    owner was written by hand and removed at the end, so the next start
    needs it written again (and after any reboot, as with every `/run`
    owner). The per-instance values are in `docs/PARAMETERS.md`.
- **app_work** (CID **23**, slot **03**, `LINK_ID` **203**; created
  2026-10-02 by `ai3`, R128). `class = app`, **`manifest = office`**,
  `netvm = netvm`, `persistence = persistent`, `identity = true`,
  `disposable = false`, `mem = "2G"`, `vcpus = 2`.
  - **T1** `/etc/katmate/vm/app_work.toml`, `root:root 0644`, `bd7f7acc…`,
    staged in the Acer's ignored `local/etc/katmate/vm/`.
  - **Delta** `/var/lib/katmate/instances/app_work.qcow2`, `host:host
    0644`, backing **`/dev/vg0/vm_app_office`** (raw), 10 GiB virtual, in
    the form above with `vm_app_office`.
  - **Home LV `vm_app_work_home`**: 10G thin in `vm_pool`, made in the form
    of record above (`app_personal`). Its ext4 equals
    `vm_app_personal_home`'s field for field. It holds the operator's
    `user/test.odt` (9495 B).
  - **The `office` layer** (`vm_app_office`): the foundation plus
    LibreOffice Writer, Calc and Impress with the GTK3 front end, foot and
    pcmanfm. 356 packages, no JRE. `/usr/bin/libreoffice` is the RUN target.
  - **Booted once** (2026-10-02 15:07–15:31) by
    `katmate-app-routed@app_work`: `km.ip=10.100.1.19`, `km.name=app_work`,
    MAC `52:54:00:b4:ec:6c`, beside `app_web` and `app_personal`. The
    operator ran `foot` and LibreOffice in it. Its owner was removed at the
    end. The per-instance values are in `docs/PARAMETERS.md`.
- **app_vault** (build-only): `vm_app_vault` thin snap RO of `vm_tpl_foundation`,
  built via `make app-vault` (2026-06-29; keepassxc/foot/nautilus). NOT yet
  instantiated — no qcow2 delta, no home LV, no CID (will be allocated from 20+),
  never booted. keepassxc
  still off the vm-agent RUN whitelist (Faza 4 blocker).
  **[2026-10-02, ai3: false since `af6e9d3` in the tree and since ai3's
  foundation on MINIS. keepassxc is on the compile-time whitelist (R130,
  ADR-021's note), and a per-manifest whitelist is post-alpha, not a vault
  blocker. The text is left as written.]**
  **2026-09-26: `vm_app_vault` no longer exists under that name** — only as
  `vm_app_vault_pre0926`, on the old foundation. `manifests/vault.list` now
  names pcmanfm instead of nautilus (`adc217f`). **Not rebuilt**
  (`appweb-rebuild-report.md` § 6).
  **[2026-09-27, host-cleanup: `vm_app_vault_pre0926` is deleted. There is
  now no vault app layer on MINIS under any name.]**
  **[2026-10-02, ai4: this entry is superseded, not reused (R137).** The
  June layer is gone, as the bracket above says, and the instance below is
  new. The text is left as written.**]**
  **The instance, from 2026-10-02 (`ai4`, R137):** CID **24**, **no slot,
  no `LINK_ID`, no owner**. `class = app`, `manifest = vault`, **`netvm =
  ""`** (it derives `app-offline`), `persistence = persistent`, `identity =
  false`, `disposable = false`, `mem = "2G"`, `vcpus = 2`.
  - **Unit** `katmate-app-offline@app_vault` (R135): no network device,
    `km.name=app_vault`, the home drive.
  - **T1** `/etc/katmate/vm/app_vault.toml`, `root:root 0644`, `675a2614…`,
    staged in the Acer's ignored `local/etc/katmate/vm/`.
  - **Delta** `/var/lib/katmate/instances/app_vault.qcow2`, `host:host
    0644`, backing `/dev/vg0/vm_app_vault` (raw), 10 GiB virtual, in the
    form of record.
  - **Home LV `vm_app_vault_home`**: 10G thin in `vm_pool`, in the form of
    record (`app_personal`). Its ext4 equals `vm_app_personal_home`'s. It
    holds the operator's `user/test.kdbx` (2117 B).
  - **The `vault` layer** (`vm_app_vault`): the foundation plus keepassxc,
    `qtwayland5`, foot and pcmanfm. 285 packages.
  - **Booted twice** (2026-10-02 19:07–20:04 on the first vault layer,
    20:05–20:31 on the second) beside the three routed AppVMs. The console
    printed `hostname: app_vault` and `net: offline (no km.ip), lo up`. The
    operator ran the negative test (R139) and KeePassXC (R140).
    **KeePassXC starts only as `QT_QPA_PLATFORM=wayland keepassxc` from a
    foot shell.** A RUN of `keepassxc` opens no window, because vm-agent
    does not select the Qt platform. The per-instance values are in
    `docs/PARAMETERS.md`.
    **[2026-10-03, ai5: superseded. vm-agent sets the platform for a RUN
    child (R146), and on the rebuilt vault layer **RUN `keepassxc` opened
    a window and `~/test.kdbx` opened** (the operator, 17:06). The text is
    left as written.]**
- **Set aside 2026-09-26 (`_pre0926`).** The rebuild renamed rather than
  removed what it replaced: `vm_tpl_foundation_pre0926`, `vm_app_web_pre0926`,
  `vm_app_vault_pre0926`; `instances/test_web.qcow2.pre0926`, **rebased with
  `qemu-img rebase -u` onto `/dev/vg0/vm_app_web_pre0926`** (operator,
  2026-09-26 — before that, its backing name resolved to the *new* layer);
  `/var/lib/katmate/foundation.meta.pre0926`; `/var/lib/katmate/kernels.pre0926/`;
  `~/katmate-build/out/vm-agent.pre0926` (`appweb-rebuild-report.md` §§ 3, 6,
  10). **Removal is the operator's decision.**
  **[Removed 2026-09-27 (host-cleanup, operator ruling). The three LVs and
  `test_web.qcow2.pre0926` are deleted. `foundation.meta.pre0926`,
  `kernels.pre0926/` and `vm-agent.pre0926` were moved to
  `~/katmate-dev/removed-0927b/` on MINIS. Nothing `_pre0926` remains in
  `vg0`, in `/var/lib/katmate/` or in `out/`.]**
- **Host GUI ingress (`waypipe-client`, user unit) — 2026-09-26.** The unit
  files live **only on MINIS**, in `~/.config/systemd/user/`, untracked (#31).
  Edited by the operator 10:47–10:49: `ExecStart` →
  `/opt/katmate/bin/waypipe`; `waypipe-client.socket` **disabled** — it was a
  TCP `[::]:1024` listener, not vsock — and the service's `Requires=`/`After=`
  on it removed; the service is enabled and running, PID stable, its exe the
  `/opt` binary, vsock `*:1024` listening, TCP 1024 closed;
  `WAYLAND_DISPLAY=wayland-1` matches `/run/user/1000/wayland-1`. **Before:**
  `ExecStart` was `/usr/bin/waypipe`, the distro `waypipe 0.11.2-1` (upgraded
  2026-09-18), so host and guest ran **0.11.2 against 0.11.0 from that date**,
  undetected because `katmate-check-waypipe` checks the `/opt` binary.
  Leftovers in the same directory: `personal-vm.service`, `work-vm.service`,
  `netVM.service.d/` (operator, 2026-09-26). **[Removed 2026-09-27
  (host-cleanup): all three were moved to `~/katmate-dev/removed-0927b/user/`
  and are `not-found` after `daemon-reload`. `waypipe-client` kept PID 1592
  throughout. Two dangling `waypipe-client@1024.service` symlinks remain,
  unauthorised (#42).]** Requirement:
  `docs/HOST-CONFIG.md` § 11.
  **Later on 2026-09-26 (operator):** HOST-CONFIG § 11's `ExecStart` arguments
  are verified — the operator showed the unit file. The distro `waypipe` was
  removed (`pacman -Rs waypipe`), `waypipe-client` stayed `active`, and
  `waypipe` is no longer on the host `PATH`.
- **The launcher and the menu (from 2026-10-03, `ai6`; R150–R158).**
  - **`/usr/lib/katmate/katmate-launch`** `root:root 0755`, `7938f47a…` (T4,
    the launch daemon's alpha precursor; ADR-029's note of 2026-10-03).
    `katmate-launch <instance> <app>` | `--stop <instance>` | `--stop-all`,
    as root only. Exit 0 = done, 1 = refused or failed, 2 = usage. Every
    action is a journal line: **`journalctl -t katmate-launch`**. It does
    not start netVM.
  - **`/usr/lib/katmate/ping-client`** `root:root 0755`, `bbeeddf2…` (R155),
    a copy of `~/katmate-build/agent/target/release/ping-client` (built
    2026-07-23). **The installed set is now 13 files:** the eleven of the
    tree, plus `katmate-launch` (against the tree) and `ping-client`
    (against that build output). Hash-first compares `ping-client` with the
    build output, not with the tree.
  - **`/etc/sudoers.d/katmate-launch`** `root:root 0440`, `ebfb91fe…`,
    staged in the Acer's ignored `local/etc/sudoers.d/` (HOST-CONFIG § 13).
    SECURITY-MODEL gap 17. Its sufficiency is UNVERIFIED while `katmate-dev`
    exists (R158).
  - **The menu:** `custom/katmate`, the first module of `modules-left` in
    the tracked `config-sway.jsonc`. `~/.config/waybar/modules-katmate.jsonc`
    and `katmate-menu.xml` are symlinks into `~/katmate-build/desktop/waybar/`
    (HOST-CONFIG § 14). waybar 0.15.0, PID 1420, parented by sway; it was
    reloaded with SIGUSR2.
  - **Its locks and owners:** `/run/katmate/launch/` (`root:root 0700`,
    `flock`). Owners are written and removed by the launcher; none stands
    between starts.
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
   **[Note 2026-10-04: the preflight exists (`installer/preflight.sh`) and has
   run twice on real hardware.** The operator's reports are outside the
   repository: `pf-cubi.txt` and `pf-minis.txt`. What they measured:
   - **MSI Cubi N6000**, Arch live ISO, kernel `7.2.2-arch1-1`. DMAR present,
     two IOMMU units (`dmar0`, `dmar1`). `DMAR-IR: Enabled IRQ remapping in
     x2apic mode`, beside 30 interrupt lines on `IR-` chips.
     `# CONFIG_INTEL_IOMMU_DEFAULT_ON is not set` (`pf-cubi.txt:33`). The run
     was booted with `intel_iommu=on`, and the kernel logged `DMAR: IOMMU
     enabled` (`:46`). A run without the parameter has not been taken.
     `iommu: Default domain type: Translated` (`:58`). The RTL8111
     (`10ec:8168`, `0000:03:00.0`, `r8169`) is alone in group 17. The CNVi
     Wi-Fi (`8086:4df0`, `00:14.3`) is alone in group 6. The xHCI (`00:14.0`)
     shares group 5 with the Shared SRAM (`00:14.2`, `8086:4def`). The GPU is
     `8086:4e71` on `i915`.
   - **MINIS**, the installed host (kernel `7.2.8-hardened1-1-hardened`), not
     a live ISO. IVRS present, one unit (`ivhd0`). `AMD-Vi: Interrupt
     remapping enabled`, beside 43 `IR-` lines. `AMD-Vi: Unknown option -
     'on'` (`pf-minis.txt:46`), which corroborates the `amd_iommu=on` entry
     in § *Invariants & gotchas*. `iommu: Default domain type: Passthrough
     (set via kernel command line)` (`:52`), from `iommu=pt`. The RTL8125 is
     alone in group 12, bound to `vfio-pci`, so its MAC is not readable on
     the host.
   - **Both:** the PCIe Device Serial Number reads `01-00-00-00-68-4c-e0-00`
     on two different Realtek NICs: the Cubi's `10ec:8168`
     (`pf-cubi.txt:160`) and MINIS's `10ec:8125` (`pf-minis.txt:196`). This
     is a measured fact bearing on ADR-030 §5's descriptor question. No
     descriptor is concluded from it. The HCL half of this problem is still
     open.**]**

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

   **[Note 2026-09-30 (`wp-0930`, `06ab509`; R120): the `die` half is
   implemented, UNVERIFIED.** The preflight dies on a missing binary, and on
   one older than any file of `agent/crates/netvm-agent/`,
   `agent/crates/katmate-protocol/` or `agent/Cargo.lock`. It first runs in
   the next netVM build. The `sha256sum` in `netvm.meta` is not done, and
   R120 does not ask for it. The *"line 263"* above no longer names this
   code.**]**

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
   **Cross-reference 2026-09-27:** C1 also has to retire the blanket udev rule
   that gives uid 1000 read-write on every `vm_*` device, thin pool included
   (#43, gap 16).

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

19. **RESOLVED 2026-09-29 — by `d6feb9c`: the guard removed, the
   `app-routed` `REQ_ENV` arm written, and `katmate-app-routed@.service`
   shipped, in one commit (R61).** Kept as a closed marker so the number is
   not reused. **Evidence (s4a-impl-B, MINIS, 2026-09-29):** the first start
   of `katmate-app-routed@app_web` passed the read-back, and the generator
   logged *"projection written: /run/katmate/vm/app_web.env (profile
   app-routed asserted and derived, 13 keys)"*. **The standing risk below
   still holds, and now covers three arms** (`sys-driver`, `app-offline`,
   `app-routed`): per-profile truth is stated in the emissions and again in
   the required-key sets, and nothing measures that they agree. The
   published text is left as written:
   **`katmate-generate-env`'s read-back has no required-key set for
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
   **[Note 2026-09-28 (ADR-037 R60, R61): closed in networking arc step 4a,
   by the commit that adds `katmate-app-routed@.service`, which also removes
   the guard and writes the `REQ_ENV` arm — the three in one commit.]**

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

   **[Note 2026-09-29 (ADR-038 §9): a case is added.** When katmate-init
   refuses a `km.*` set, it leaves through its shutdown path, and the unit
   is **expected (not observed)** to end inactive, not failed. On the host
   that is indistinguishable from a clean shutdown until this problem's
   observation of the agent answering exists.**]**
   **[Note 2026-09-29 (s4a-impl-B § 5.1): `systemctl show` cannot tell them
   apart either.** After a clean stop of `katmate-app-routed@app_web`,
   systemd collected the inactive instance, and its fields read as defaults
   (`Result=success`, `ExecMainStatus=0`, empty `InvocationID=`, every
   `Exec*` record at `pid=0`). A clean stop and an init refusal (ADR-038
   §9, not yet implemented) would read the same there. The journal is the record: *"Deactivated
   successfully"*, with no *"Main process exited"* line.**]**
   **[Note 2026-09-29 (s4b-impl-B § P8): the clean-stop journal shape, a
   second instance.** After SHUTDOWN of the first self-configured
   `app_web`, the journal read *"Deactivated successfully"* and a
   *"Consumed … CPU time"* line, with no *"Main process exited, code="*
   and no *"Failed with result"*. By ADR-038's note of 2026-09-29 (step
   4b), a numeric exit status appears in the journal only for a non-zero
   exit, so this shape is the reading for a clean end — reasoned, one
   instance observed. ADR-038 §9's exit is now implemented and still not
   executed, so an init refusal's shape is not observed.**]**

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

   **Note 2026-09-26 — steps 10 and 11 have now executed.** The foundation
   rebuild of 2026-09-26 ran them for the first time: the sidecar was installed
   into `/var/lib/katmate/kernels/` at step 11 and `foundation.meta` carries
   `KERNEL_PROVENANCE=recorded` (`appweb-rebuild-report.md` § 5.1). **The
   closing condition is unchanged** — nothing yet checks the record — and #22
   stays open.

   **Note 2026-09-27 — the second kernel image is deleted, and it was the tree
   this entry described.** `~/src/kernel/linux-6.12.94/` (no `.git`, Makefile
   6.12.94, 2278703639 B, 97751 files) was deleted by operator ruling (#42,
   hcb). Before deletion, its `arch/x86/boot/bzImage` read 14238720 B with
   mtime `2026-07-06 15:59:27.699084734 +0200`. That is **identical to the
   nanosecond** to the *second kernel image* note's source
   (`adr034-pregate-report.md` § 3.2). The identification is by size and
   nanosecond mtime; that report recorded no hash. **Still no cause is
   assigned** to why the tree existed. `src/kernel/` now holds only
   `linux-6.12.y`.

   **Note 2026-09-27 — the spare `.bak` config is deleted.**
   `~/config-katmate-3flags.bak` (143430 B, mtime 2026-07-01 08:04:56) hashed
   `499a53a2…8a71` before deletion. That is **the same sha256** as the spare
   config of the 2026-09-01 note above, and the same size
   `adr034-pregate-report.md` § 5 records, so it is that object. The archived
   config `7720cf22…`, which `CONFIG_SHA256` names, was not touched
   (`~/katmate-kernels/` is kept).

   **Note 2026-09-28 — the MINIS config is read, header checked.** s4-m0
   (`s4-m0-report.md` § 1, outside the repository) read
   `/home/host/katmate-kernels/config-katmate-microvm-amd64-6.12.87`
   (`7720cf22…`): line 3 is `# Linux/x86 6.12.87 Kernel Configuration`, and
   it carries `CONFIG_IP_PNP=y` (with `_DHCP`, `_BOOTP`, `_RARP`),
   `CONFIG_IPV6=y` and `CONFIG_VIRTIO_NET=y`. The kernel beside it is
   `b34026dd…`, the `-dirty` image. **The caveat stands:** `IKCONFIG` is
   unset, so this config is not proven to be that image's; it is
   consistent with the 2026-08-28 `auto.conf` tie, which is chat-only. The
   image's behaviour agrees with those symbols (kernel `ip=` worked, three
   boots; ADR-035's note of 2026-09-28), which is consistency, not proof.
   #22 stays open. The AppVM kernel also starts `netconsole` (#52).

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
   **[Note 2026-09-28 (ADR-037 R74): the netVM side — `ExecStopPost=`
   unlinking all sixteen `netvm` nodes, for the hijack window — lands in
   networking arc step 4a; the AppVM side (`appvm`) in the `app-routed`
   template.]**
   **[Note 2026-09-29 (step 4a): both halves are written** — netVM's
   sixteen literal `netvm` paths (`1597445`, R74) and the AppVM's one
   `appvm` path (`d6feb9c`, R81, with R84). **The AppVM half is observed**
   on MINIS (s4a-impl-B): after a clean stop the slot's `appvm` was absent,
   attributed to `ExecStopPost=` by inference; after a refused start with a
   stale projection, a sentinel at `appvm` survived, by record (ADR-035's
   note of 2026-09-29). **netVM's half is installed and has not executed**:
   netVM has not been stopped since.**]**

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

   **Read 2026-09-26, in netVM:** `accept_ra=1` on `all` and `default`, and
   `forwarding=0` on both (`net-up-report.md` § 19.3 item 5). netVM would
   therefore process RAs on interfaces that inherit `default`, and is not
   itself a router. Whether anything in netVM *sends* RAs was not read. Carried
   by [ADR-037](docs/DECISIONS.md#adr-037), not decided there.
   **[Note 2026-09-28 (ADR-037 R66): IPv6 in the AppVM is decided by
   networking arc step 4.0's `ipv6.disable=1` reading. If it holds, AppVMs
   are IPv4-only, consistent with R49.]**
   **[Note 2026-09-28, s4-m0 and rulings (ADR-037 R76): the `app-routed`
   template carries `ipv6.disable=1` in `-append`.** Boot C's serial shows
   the guest running no IPv6 at all (*"IPv6: Loaded, but administratively
   disabled"*). **R49 is not a witness for RS:** on an unverified
   hypothesis, an RS to `33:33:00:00:00:02` is dropped by QEMU's
   virtio-net receive filter before netVM's kernel sees it, since netVM is
   not a router and does not join that group; F12b row 3 counted only
   because its fixture sent to `ff02::1`. R49 read +0 on all three 4.0
   boots, with and without the parameter (ADR-035's note of 2026-09-28).
   Whether netVM sends RAs is still unread.**]**
   **[Note 2026-09-29 (ADR-038, R77): the AppVM half is closed in
   direction** by [ADR-038](docs/DECISIONS.md#adr-038): AppVMs are
   IPv4-only, the routed template carries `ipv6.disable=1`, and there is no
   `accept_ra` step. It closes when ADR-038's G1 is taken. **#24 stays
   open.**]**
   **[Note 2026-09-29 (`wp-0929c`, R89): the AppVM half is observed.**
   ADR-038's G1 positive half passed: the first self-configured AppVM ran
   with `ipv6.disable=1` in effect (*"IPv6: Loaded, but administratively
   disabled"*), IPv4-only (s4b-impl-B § P6, § P8). **#24 stays open,
   not RESOLVED**, because it names more than the AppVM half: whether
   netVM sends RAs on internal links is still unread, netVM's
   `accept_ra=1` stands, and the proposed *no RA from netVM* is not
   taken.**]**

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

   **[2026-09-27, host-cleanup: narrowed, still open.** `scratch.qcow2` is
   deleted (operator ruling), and its `qemu-img info` is recorded in the
   2026-09-27 *host-cleanup* entry. The delta that triggered the refusal is gone.
   **The script's handling of an unknown app type is unchanged and still
   open.** Any delta whose suffix is not in `APP_TYPES` still makes
   `--dry-run` fatal. `scratch_home.img` remains (#42).]**

27. **RESOLVED 2026-09-27 — fixed in the image by the ADR-037 rebuild.** Kept
   as a closed marker so the number is not reused. The agent unit is the
   tracked `manifests/netvm.conf.d/etc/systemd/system/netvm-agent.service`
   (`098e868`, R24), and step 7's heredoc is gone. **Gate evidence
   (`adr037-impl-B`, 2026-09-27):** in the guest, `systemctl cat netvm-agent`
   is the tracked file, verbatim, with 0 `networkd` mentions outside comments
   and `ReadWritePaths=/run`. The agent started with no networkd ordering, PING
   answered OK, and NETCFG ADD and REMOVE returned OK in two cycles, with
   `/etc/systemd/network` read-only. It closed in the rebuild, not in the
   pool's commits (ADR-035's 2026-09-27 implementation note). The published text
   is left as written:
   **The `netvm-agent` unit baked into the netVM image still names the Path A
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

   **Note 2026-09-26 — the location is answered.** The unit files exist
   **only on MINIS**, in `~/.config/systemd/user/`, untracked; the socket unit
   there was a TCP listener and is now disabled (operator, 2026-09-26; *Live
   state*, *Host GUI ingress*). So `docs/HOST-CONFIG.md` was the document
   missing an entry, and now has one (§ 11). **Still open:** tracking the unit
   in the repository, and ADR-036's placement of it, which is PROPOSED.

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

   **Confirmed a second time, 2026-09-26, on a different boot:** all 17
   stage-one renames (latest 1.580054) before `systemd-sysctl` finished, and
   all 16 stage-two renames (earliest 3.300430) after it, with the same
   0-of-16 / 17-of-17 split as 2026-09-20; the lower bound of the bracket is a
   journald record, not a rename, so it is looser than 2026-09-20's
   (`net-up-report.md` § 16.5).

   **[Note 2026-09-28 (F D17; ADR-037 R56): ADR-036 § *Open* still lists
   this ordering as open.** ADR-036 is not edited: the operator ruled that it
   is not touched, and the divergence is recorded here only.**]**

34. **RESOLVED 2026-09-30 (R118) — by `1e882d3` (R100): `table arp filter`
   in netVM's ruleset, observed on the step-4c image.** Kept as a closed
   marker so the number is not reused. **Evidence** (`s4c-b-report.md` § B5
   row 7, outside the repository; R117 PASS): six forged ARP frames from
   slot 02 claiming `10.100.1.17`, three requests and three replies, got 0
   answers; `slot_arp`'s drop counter went 0 → 6, and no `.17` neighbour was
   planted anywhere. The control on slot 01 was answered 3 of 3, with the
   counter unchanged. The table loaded before the `kmkk` renames. The
   published text is left as written:
   **The pool's ARP surface is uncovered, and the finding-12 candidate does not
   reach it.** Added 2026-09-20, **named as open at the moment the IPv4 half of
   finding 12 was ruled, deliberately, so the ruling is not read as closing
   finding 12**. **Nothing was run** — this entry names an absence and rests on
   readings taken by earlier sessions.

   **`table inet filter` does not see ARP**, so the guard chain that refuses a
   forged IPv4 source cannot refuse a forged ARP. An AppVM can still plant a
   neighbour entry in netVM for another slot's peer address — **measured, not
   hypothetical**: `10.100.1.17 dev km02`,
   [ADR-035](docs/DECISIONS.md#adr-035)'s revision note of 2026-09-14, finding 4.
   After the candidate is installed a forged **packet** is dropped while a
   poisoned **neighbour entry** survives, and with it the black-holing or
   interception of the true peer's return traffic.

   **Coverage needs `table netdev` ingress or `table arp`, and P2 is
   unresolved.** `nft -c` accepted a netdev ingress chain on an absent device
   **and accepted the control too**, so `-c` cannot settle load-time device
   binding at all (`auditfix-liveread-report.md` §§ 2.5, 5.4). Settling it needs
   a real `nft -f` load, which is a state change.

   **[Note 2026-09-28 (ADR-037 R54): step 3a closes the IPv4 half of finding
   12 only.** Networking arc step 4 may start with this problem open, because
   ARP poisoning needs two tenants on slots. **It must land before the second
   networked AppVM**, not before the first.**]**

   **[Note 2026-09-28, later (f12-impl A and B): the IPv4 half is closed and
   gated** (F12a and F12b PASS, ADR-035's note of that date). **The ARP half
   is this entry**, and R54's condition stands: it must land before the
   second networked AppVM.**]**

   **[Note 2026-09-29 (`wp-0929e`; R100, R101, R110): ruled, not
   resolved.** The mechanism is a `table arp`: sixteen `iifname "kmkk"
   arp saddr ip 10.100.1.(16+k)` pairs, then a counted drop on `km*`. It
   binds no device, so it loads before the renames. `table netdev` is not
   pursued, and P2 is moot, not settled. `s4c-m0` reads whether the
   kernel has the `arp` family. The pairs get an R48-style read-back.
   It lands in 4c (ADR-035's note of this date).**]**
   **[Note 2026-09-30 (`s4c-a`, `1e882d3`): implemented, UNVERIFIED.**
   `table arp filter` in the baked `nftables.conf`, with a build read-back.
   Closing is 4c B's, by gate (a forged ARP from slot `b` claiming slot
   `a`'s peer is dropped and counted, and no neighbour entry is
   planted).**]**
   **[Note 2026-09-30 (`s4c-b`): observed on the rebuilt netVM.** `table
   arp filter` loaded before the `kmkk` renames (2.884 s against 3.216 s).
   Six forged ARP frames from slot 02 claiming `10.100.1.17` (3 requests, 3
   replies): 0 answered, `slot_arp`'s drop counter 0 → 6, and no `.17`
   neighbour anywhere. The control on slot 01 was answered 3 of 3 with the
   counter unchanged. Closing is the operator's.**]**

35. **Foundation dependency debt.** Added 2026-09-26. The rebuilt foundation
   carries `systemd`, `systemd-sysv`, `dbus` and `dbus-daemon`, none of them
   PID 1 and none requested. They are kept by `systemd-sysv`'s `Protected: yes` and by
   the chain GTK3 → dconf → `dbus-user-session` → `libpam-systemd` →
   `systemd-sysv` (`appweb-m2-report.md` § 7.3). It also carries the perl stack,
   `netbase` and `libgdbm*`, left after the waypipe build-dependency purge. That
   is the candidate cause, not measured (`appweb-rebuild-report.md` §§ 5.2, 8
   item 5). **Candidate fixes, unmeasured:** `dbus-x11` as the session-bus
   provider, or an equivs no-content package providing
   `default-dbus-session-bus`. The measurement is the shelved
   `appweb-m3-brief.md` (a fresh debootstrap in tmpfs). **Deferred past the
   alpha** (operator, 2026-09-26).

36. **The divert's claim and its test.** Added 2026-09-26. After the divert,
   `dpkg -S /usr/sbin/init` still lists `systemd-sysv: /usr/sbin/init` beside
   the two diversion lines (`appweb-rebuild-report.md` § 8 item 4). So the
   comment at `build/foundation.sh:183` — the divert means dpkg *"no longer
   owns"* the file — is imprecise: dpkg keeps the path listed and diverted. **The
   settling test is unrun.** It is: reinstall `systemd-sysv` in a throwaway
   overlay, and `/usr/sbin/init` must remain katmate-init. **The read-back
   guard (`5d32dd0`) has been observed only in its passing arm**, and its
   firing arm is unexercised (§ 5.1).

37. **Built LVs remain active after `make foundation` / `make app-web`.** Added
   2026-09-26. Both new LVs read `a` in `lvs` and `ACTIVE (READ-ONLY)` in
   `dmsetup` after their builds. `lv_deactivate` (`build/lib.sh`) runs
   `lvchange -an … 2>/dev/null || true`, which swallows any failure
   (`appweb-rebuild-report.md` § 8 item 2). **Why they stay active is
   unmeasured.** Open count was 0 throughout, so this is not a hold.

38. **RESOLVED 2026-09-27 — fixed in the image by the ADR-037 rebuild.** Kept
   as a closed marker so the number is not reused. Step 5 copies with
   `cp -a --no-preserve=ownership` and reads the ownership back (`6827583`),
   and `nftables.conf` is git mode 0644 (`a209ebf`, R23). **Gate evidence
   (`adr037-impl-B`, 2026-09-27):** the build printed *"Read-back OK: 34
   conf-tree paths in the image, all owned 0:0"* (24 files and 10
   directories), and in the guest `/etc/nftables.conf` is `root:root 0:0 644`.
   The published text is left as written:
   **The netVM build bakes uid-1000 ownership into the ruleset and the network
   files.** Added 2026-09-26. `cp -a` in `netvm.sh` step 5 carries the build
   tree's `host:host` (uid 1000) into the image: in the guest,
   `/etc/nftables.conf` is `1000:1000` with mode **0755**, and
   `20-uplink.network` and all sixteen `70-katmate-slot-*.link` are
   `1000:1000` too. **No uid-1000 user exists in netVM** (`getent passwd 1000`
   rc 2) (`net-up-report.md` § 19.3 item 10, `net-m1-report.md` § 10.7). The
   fix belongs to the netVM rebuild that implements ADR-037 (§ *Next steps*,
   *Networking arc*).

39. **RESOLVED 2026-09-27 — folded, not tracked separately.** Kept as a closed
   marker so the number is not reused. The published text is left as written:
   **`katmate-pool@.service`, the live netVM launcher, is untracked.** Added
   2026-09-26. It exists only at `/etc/systemd/system/katmate-pool@.service` on
   MINIS (`1d727b25…`, 13021 B); `git ls-files` has no pool unit. R4 changes it
   (`addr=` on `vfio-pci`), so **it must enter the repository first**, or the
   change is made to a file no commit can show.
   **[Resolved by option (b), operator ruling of 2026-09-27: the slot pool is
   folded into the tracked `katmate-sys-driver@.service` (`a36bdb2`, `70b08c7`),
   and the pool unit has left `/etc` on MINIS. R4 (`addr=`) now applies to
   `katmate-sys-driver@.service`.]**

40. **RESOLVED 2026-09-27 — implemented, installed on MINIS and gated at
   networking arc step 3.** Kept as a closed marker so the number is not
   reused. The code is `e659db3`…`ba11679` (r8-impl-A) and `8f6ebd5` (R45,
   r8-impl-B). **Gate evidence (r8-impl-B, 2026-09-27; ADR-037's note on the
   step-3 gates):** G6 PASS, pass half and R-a to R-d. The builder printed
   `entries: VERSION uplink (address=10.3.1.172/24 gateway=10.3.1.1
   nameservers=10.3.1.1)`, image `e960fadc…ea1c`, and the guest consumer
   logged the same sha256. R-b, R-c, R42 mode and owner, R45 and a symlink
   were each refused before QEMU, and the absent path leased by DHCP.
   G3's static half PASS: `inet 10.3.1.172/24` on `uplink0`, and 0 DHCP
   packets captured across the static boot, against a positive control of 1.
   What did not run is #46. The published text is left as written:
   **The netVM config disk is decided and not implemented.** Added
   2026-09-26. R8 ([ADR-037](docs/DECISIONS.md#adr-037)): per-installation
   netVM configuration reaches netVM as a read-only `virtio-blk` the host
   assembles from `/etc/katmate/netvm/`. Nothing of it exists; gate G6 of
   ADR-037 is its acceptance test, and `docs/HOST-CONFIG.md` § 12 carries the
   host side as `[OPEN]`.
   **[Note 2026-09-27: ruled, and still not implemented.** The operator's
   rulings R30–R40 (ADR-037's note on the step-3 rulings) settle it before any
   code. The T1 location is `/etc/katmate/vm/<instance>.d/uplink`, not
   `/etc/katmate/netvm/` (R31; ADR-032's note of that date). A T4 executable
   builds `/run/katmate/cfgdisk/<instance>.img` at every start, after
   `katmate-generate-env` (R32). The image is a `ustar` archive with a
   `VERSION` member (R33), attached `readonly=on` at `addr=0x15`,
   `serial=kmcfg` (R34). T1 is parsed and re-emitted, never copied through
   (R35). An absent `uplink` means DHCP, and a malformed one fails closed
   (R36). The schema is `address`, `gateway`, `nameservers` (R37). A guest
   oneshot writes a dhcpcd config to `/run` (R38). The gates are R39's, and
   G1 stays non-discriminating (R40). VPN mode is arc step 5 (R30). The text
   above is left as written.**]**

41. **RESOLVED 2026-09-29 — by `bb6801d`: the `sys` branch is removed, and
   the generator emits `KM_MAC_INT` for an AppVM attached to a netVM
   only.** Kept as a closed marker so the number is not reused. The `app`
   branch stays, per ADR-035 §9. **Evidence (s4a-impl-B, MINIS,
   2026-09-29):** the `app-routed` projection carried
   `KM_MAC_INT=52:54:00:6f:19:35`. That netVM's projection no longer
   carries the key is **not read**, because netVM was not restarted and its
   `netvm.env` is the 2026-09-28 one. The published text is left as written:
   **`KM_MAC_INT` is emitted for `sys` with no consumer.** Added 2026-09-27.
   `katmate-generate-env:360-364` derives it when `CLASS == sys` and
   `provides_network == true` (and for an `app` with `netvm` set), and `:403`
   emits it. Its only consumer in `host/` was
   `katmate-sys-driver@.service:138`'s `int0` device, which `a36bdb2` removed,
   so netVM's projection carries a key nothing reads (`pool-fold-report.md`
   § A7; the live projection was not read). **It is not a failure:** the
   `sys-driver` required-key set (`:439-447`) excludes the key deliberately.
   **Ruling of 2026-09-27:** the `sys` branch is removed in its own commit at
   networking arc step 4, alongside #19. The `app` branch stays, per ADR-035
   §9.
   **[Note 2026-09-28 (ADR-037 R60, R61): that is step 4a, the host side.]**

42. **RESOLVED 2026-09-27 — `hcb-d.sh` was deleted by the operator, the one
   item left undecided.** Kept as a closed marker so the number is not reused.
   The token noted below is obsolete (operator ruling, 2026-09-27). The
   published text is left as written:
   **MINIS dev leftovers awaiting the operator's ruling.** Added 2026-09-27
   from the host-cleanup inventory (hc Appendix A, read 11:36:56). **This is a
   list, not a decision.** Each item was judged a leftover from its name, date
   and location only. None was traced, opened or touched, and the operator rules
   in chat. All paths are on MINIS; `~` = `/home/host`.

   - **Instances:** `/var/lib/katmate/instances/scratch_home.img` (4 GiB,
     2026-07-30, `host:host`). It is the companion of the deleted
     `scratch.qcow2` by name only.
   - **User units:** `~/.config/systemd/user/default.target.wants/waypipe-client@1024.service`
     and `…/multi-user.target.wants/waypipe-client@1024.service`, both
     **dangling** symlinks to the absent `waypipe-client@.service` (2026-02-16).
     A `multi-user.target.wants/` in a user manager's directory is itself
     inert. These are `waypipe-client@…`, outside the brief's `waypipe-client.*`
     keep glob, and were not authorised.
   - **System units:** `/etc/systemd/system/vm-lvs.service` (372 B,
     2026-02-23, owned by no package; contents not read), with a root-owned
     copy at `~/vm-lvs.service` (369 B).
   - **networkd files outside `/etc`:** `~/han0.netdev` and `~/han0.network`
     (`root:root`, 2026-03-03). They are inert where they are. Also `~/nftables.conf`
     (`root:root`, 2026-03-03).
   - **A second repository-shaped tree:** `~/katmate-os/` (2026-07-23).
     The synced tree is `~/katmate-build/`; this one's contents and origin were
     not read.
   - **Kernel source:** `~/src/kernel/linux-6.12.94/`, **no `.git`**. This is
     consistent with #22's *second kernel image* note (a different version,
     no `.git`). Its `bzImage` was not checked, so the match is not
     established.
   - **Pre-sysVM / personalVM launchers and logs at `~`:** `net.con2`,
     `net.con3`, `personal.com.1`, `personal.con2`, `personal-firefox`,
     `personal.ses`, `netvm.ses`, `sd-personal.sh`, `personal_boot/`, `vms/`,
     `personal-vm.log`, `netVM.log`, `disk-commit`, `disk-refresh`,
     `vm_disk_creation.txt`.
   - **Superseded prototypes at `~`:** `vm-agent` and `vm-agent.c` (2026-03-20,
     the pre-Rust agent), `vm-power-helper` and `vm-power-helper.c`,
     `vm-fileget.sh`, `vm-fileput.sh`, `grok`, `grok2`, `grok3` and their `.c`.
   - **Earlier sessions' dev scripts at `~`:** `adr034-gate.sh`,
     `adr034-pregate-read.sh`, `adr034-pregate-read2.sh`, `g1-dgram-probe.sh`,
     `g1-step0.sh`, `g8.sh`, `gate2-g.sh`, `gate2-r1.sh`, `gate2-r2.sh`,
     `gate-fn.sh`, `gate-hop.sh`, `gate-stage/`, `q2-measure.sh`,
     `recapture.sh`, `guest-cmds.txt`, and the fifteen `nv-*.sh` of
     2026-09-03. This session's own `hc-i.sh`, `hc-r.sh`, `hc-s.sh` and `hc-s2.sh`
     join them. Their hashes are in hc.
   - **Logs, captures and backups at `~`:** `frac035_run.log`,
     `grok3_run.log`, `wd03_run.log`, `wd10_run.log`, `wd50_clean.log` and its
     three `.bak*`, `run1.csv`, `run2.csv`, `host.txt`, `kernel.txt`
     (`root:root`), `netVM.txt`, `personal.txt`, `nft.txt`, `minis_capture.txt`,
     `minis_harvest.sh`, `host.sh`, `minis_dela.md.bak`,
     `config-katmate-3flags.bak`, `run-waypipe-enoch.txt`, `winwin.txt`, an
     empty `.pkg.tar.zst`.
   - **Session records:** `~/katmate-dev/net-m1/` and `~/katmate-dev/net-up/`.
     These are the 2026-09-26 transcripts, which the brief did not keep-list.

   **Not judged leftovers, and listed so their absence here is not read as an
   oversight:** `~/host_lan_up.sh` and `~/proton-wg-up.sh`. The host uplink is
   volatile and `proton` is up, so either may be how they come up.
   `~/.katmate-netvm-pass` is, by its name, the netVM dev root secret (#11, #12).
   `~/code_auth_token.txt` holds a credential and is the operator's to handle.
   **[Note 2026-09-27 (operator ruling): the token was rotated several times
   and is obsolete. No revocation is needed.]**
   `Pictures/`, `walls/`, `sway.sh`, the `shot-*.png`, `sway-old-*.tar.gz`,
   `iso/`, `arch-cache/`, `acer/` and `Claude.assistent/` are not judged. Neither
   is `~/katmate-build/out/netvm/` (`root:root`, 2026-07-08, contents not read).

   **Note 2026-09-27 (hcb) — ruled and executed. Only this session's own
   deletion script remains undecided.** Everything was pinned, re-checked and
   recorded in hcb Appendix D.
   - **Resolved, deleted 12:37 CEST:** everything listed above except the
     items below:
     - the instance image `scratch_home.img`;
     - both dangling `waypipe-client@1024.service` symlinks, and also
       `waypipe-client.socket`;
     - both `vm-lvs.service` copies (the unit was disabled and names only the
       absent `vm_personal_*` LVs);
     - `han0.*` and `nftables.conf`;
     - `~/katmate-os/`, which had no `.git`, only `agent/`, `app_web.con` and
       `init/`;
     - `linux-6.12.94/`, which was #22's second kernel image (#22 note);
     - the personalVM launchers and logs, prototypes, dev scripts (`hc-*.sh`
       included), logs, captures and backups;
     - `config-katmate-3flags.bak` (#22 note);
     - `.katmate-netvm-pass` (a credential already rotated);
     - `code_auth_token.txt`, identified by prefix and length as a claude.ai
       token. Revocation is the operator's step. **[Note 2026-09-27
       (operator ruling): the token was rotated several times and is
       obsolete. No revocation is needed.]**
   - **Kept, as ruled:**
     - `vms/` (only a personalVM `personal_VARS.fd`), `iso/`, `acer/`,
       `arch-cache/`, `Pictures/`, `walls/`, `sway.sh`, `shot-*.png`,
       `sway-old-*.tar.gz` and `Claude.assistent/`;
     - `~/katmate-dev/`, so `net-m1/` and `net-up/` stay, and
       `~/katmate-build/`, so `out/netvm/` stays;
     - **`host_lan_up.sh` and `proton-wg-up.sh`**, which bring up the host
       uplink and `proton`. They retire when HOST-CONFIG §2 lands;
     - `99-vm-lvm.rules`, now #43 and gap 16.
   - **Undecided:** `~/hcb-d.sh` (18524 B, `5d783a98…`), the deleting script
     itself, which was not on the list. **#42 stays open for that one item
     only.**
     **[Note 2026-09-27 (operator ruling): `hcb-d.sh` was deleted by the
     operator, so #42 closes.]**

43. **A blanket udev rule gives uid 1000 read-write access under every thin
   LV.** Added 2026-09-27. `/etc/udev/rules.d/99-vm-lvm.rules` on MINIS
   (2026-02-09, untracked, in no document before today) runs `chown host:host`
   and `chmod 0660` on every `vg0` block device whose LV name matches `vm_*`.
   **Observed** (hcb Phase P): `host:host brw-rw----` on `vm_sys_netvm`,
   `vm_tpl_foundation` and `vm_app_web_home`, **and on `vm_pool`,
   `vm_pool-tpool`, `vm_pool_tdata` and `vm_pool_tmeta`**. uid 1000 therefore
   has read-write access to netVM's rootfs, to the shared template, and to the
   thin pool's raw data and metadata, i.e. under every thin LV, active or not.
   Its likely consumer is `app_web.con`, launched as `host`. That is
   **inferred, not measured**. **Kept for now, by operator ruling.** The fix
   belongs to **C1** (#17): per-LV, per-instance DAC granted by the unit's
   `ExecStartPre=+`, never a blanket rule. SECURITY-MODEL **gap 16**.

44. **Nothing checks that the unit's `addr=` and the image's uplink `Path=`
   agree.** Added 2026-09-27 (ADR-037 R13; rp Q-R3b). After the rebuild, the
   guest address of the uplink is one constant in two artefacts on two update
   tracks: `addr=0x4` on `vfio-pci` in `katmate-sys-driver@.service` (the host
   T4 unit, reinstalled) and `Path=pci-0000:00:04.0` in
   `60-katmate-uplink.link` (the netVM image, rebuilt). `netvm.meta` records
   the image's value as `UPLINK_PCI_ADDR` (R13). **No automated preflight
   compares the two.** A mismatch fails closed, **predicted from the rulings
   and not observed**: the uplink falls to `99-default.link`, is not named
   `uplink0`, and gets neither dhcpcd (R14) nor forwarded egress. G2 catches
   it at runtime. To the host it fails
   silently, except through the ARP scan. The preflight is a later step, not
   part of the ADR-037 rebuild.
   **[Note 2026-09-27 (`adr037-impl-B`): both values now exist and agree.**
   The meta carries `UPLINK_PCI_ADDR=0000:00:04.0`, and the installed unit's
   argv carries `addr=0x4`. **There is still no automated check.** The
   agreement was read by hand, and G2 confirmed it at runtime.**]**

45. **RESOLVED 2026-09-30 (R118) — by `66937fa` (DOWN on REMOVE) and
   `2eed9c8` (`ipv6.disable=1`), R102, observed on the step-4c image.** Kept
   as a closed marker so the number is not reused. **Evidence**
   (`s4c-b-report.md` §§ B4 and B5 row 5, outside the repository; R117
   PASS): `/proc/cmdline` carries `ipv6.disable=1`, there is no
   `/proc/sys/net/ipv6`, and `ip -6 addr` is empty (B4). After REMOVE,
   `km01` is DOWN with no address, no route, an empty `ip neigh show dev
   km01` and no link-local (row 5). The published text is left as written:
   **IPv6 on the slots: a raised slot autoconfigures a link-local, and REMOVE
   leaves it.** Added 2026-09-27, from `adr037-impl-B` (G3's refusal half and
   G4). After NETCFG ADD, the kernel autoconfigures an IPv6 link-local address
   on the slot (`km02 UP … fe80::5054:1ff:fe00:2/64`, plus `fe80::/64 dev
   km02`). NETCFG REMOVE removes the IPv4 address and route but leaves the link
   **UP** with its link-local. `km02` and `km05` were left that way. **netVM
   also sends IPv6 on the slots:** MLD and DAD from `::` right after ADD, then
   router solicitations (ICMPv6 to `33:33:00:00:00:02`) from
   `fe80::5054:1ff:fe00:5` at 15:20:21 and 15:20:29 CEST, seen by the G4
   fixture peer. This combines two things already on record: the missing
   *DOWN on REMOVE* (the ADR-035 step-1 inheritance, § *Next steps*) and IPv6
   on the slots (#24, ADR-037 R22). **It is a finding, and no fix is
   decided.** It is not a G3 failure: the operator scoped G3's refusal half
   to dhcpcd-originated state (ADR-037's implementation note).
   **[Note 2026-09-28 (ADR-037 R67): DOWN on REMOVE lands in networking arc
   step 4c, in one netVM rebuild with R55's pairing check and ADR-035 §6
   and §7, after G5 and before the second networked AppVM. G5 does not
   require it.]**
   **[Note 2026-09-29 (`wp-0929e`; R102): ruled, not resolved.** DOWN on
   REMOVE, and `ipv6.disable=1` on netVM's kernel. netVM uses no IPv6,
   since the uplink is `ipv4only` and AppVMs are IPv4-only. This ends both
   halves of this entry and netVM's own router solicitations (#24). It
   lands in 4c (ADR-037's note of this date).**]**
   **[Note 2026-09-30 (`s4c-a`, `66937fa`, `2eed9c8`): implemented,
   UNVERIFIED.** REMOVE clears `IFF_UP` after the routes and the address,
   and `katmate-sys-driver@.service` passes `ipv6.disable=1`. Closing is 4c
   B's: after REMOVE the slot is DOWN with no neighbour entry, and netVM
   has no IPv6 on any link.**]**
   **[Note 2026-09-30 (`s4c-b`): observed.** `/proc/cmdline` carries
   `ipv6.disable=1`, there is no `/proc/sys/net/ipv6`, `ip -6 addr` is
   empty, and link-local reads 0 on `km01` after every ADD and REMOVE.
   After REMOVE, `km01` is DOWN and `ip neigh show dev km01` is empty (a
   `.17` entry before). A hand-added `peer/32 metric 300` route was gone
   after the DOWN. Closing is the operator's.**]**

46. **Parts of networking arc step 3 have not run as installed.** Added
   2026-09-27, from r8-impl-B § 6 (*not executed*). The gates ran the absent
   path, the static path and the file-level refusals on MINIS; these did not
   run there:
   - **the builder's `trap` cleanup and its stale-file sweep.** No leftover
     existed, and every refusal fired before staging;
   - **the directory-level refusals**: a group-writable or non-root
     `<instance>.d/`, `<instance>.d/` as a symbolic link or as a
     non-directory, and also an unknown or missing key and a leading-zero
     octet. Each ran only in an extracted copy of the validation block (A's
     driver and B's), which is not the installed executable;
   - **every failure path of the guest consumer on a real image.** The
     consumer refuses only a malformed image, and the host never builds one.
   Each is written and **UNVERIFIED**. It is settled by running the refusal
   against the installed builder on MINIS, or by a malformed image attached
   to a test boot.

47. **The `katmate-lib.sh` header is stale.** Added 2026-09-27. `:7` says the
   two readers are what *"three of the four executables would otherwise each
   carry"*. Six executables now source the library
   (`katmate-check-waypipe`, `katmate-check-image`, `katmate-build-cfgdisk`,
   `katmate-generate-env`, `katmate-activate-lvs`, `katmate-publish-nics`).
   Small, and a comment only; the fix is its own commit.

48. **A failed `nftables.service` at netVM boot would leave forwarding on
   with no ruleset.** Added 2026-09-28, in the step-3a rulings.
   `30-netvm-forward.conf` sets `net.ipv4.ip_forward = 1`, and the ruleset is
   loaded by `nftables.service`. If that unit fails at boot, netVM is left
   with `ip_forward = 1` and no ruleset: **fail-open**. **Predicted, not
   measured.** The R52 build preflight (`nft -c -f` on the baked file, in the
   build chroot) lowers the chance. It does not remove the case.
   **[Note 2026-09-28, later (f12-impl A and B): R52's preflight exists
   (`56b3c96`) and has executed, on its pass path only. The fail-open case
   itself is still unmeasured.]**
   **[Note 2026-09-29 (`wp-0929e`; R111): ruled, not resolved.**
   `ip_forward=1` moves out of `sysctl.d`, into a oneshot unit with
   `Requires=` and `After=nftables.service`, so a ruleset that fails to
   load leaves forwarding off. R52's limit is recorded (R110): it checks
   against the build host's kernel, not netVM's. It lands in 4c.**]**
   **[Note 2026-09-30 (`s4c-a`, `9010130`): implemented, UNVERIFIED.**
   `katmate-ip-forward.service` (`Requires=`/`After=nftables.service`,
   oneshot, `WantedBy=multi-user.target`) writes `ip_forward`, and
   `30-netvm-forward.conf` no longer does. The build refuses any sysctl
   file that sets IPv4 forwarding. Closing is 4c B's: `ip_forward` reads 1
   on a normal boot, and 0 with the ruleset made to fail.**]**
   **[Note 2026-09-30 (`s4c-b`): half observed.** On a normal boot of the
   rebuilt image, `katmate-ip-forward` starts after `Finished
   nftables.service`, is `active`, and `ip_forward` reads 1. The build's
   no-forwarding-sysctl read-back passed. **The fail-closed half (0 with
   `nftables.service` failed) is not taken.** It needs a boot with a broken
   ruleset, which the operator has not asked for.**]**
   **[Note 2026-09-30 (`wp-0930`; R118): narrowed to the fail-closed half.**
   The normal-boot half is observed and is no longer open. What remains is
   the pair of observations that settles the rest: on a boot with
   `nftables.service` failed, `katmate-ip-forward` does not run and
   `ip_forward` reads `0`.**]**

49. **RESOLVED 2026-09-30 (R118) — by `4bdfb0f` (R103): the pairing check
   in `netvm-agent`'s parser, observed in the guest.** Kept as a closed
   marker so the number is not reused. **Evidence** (`s4c-b-report.md` § B5
   row 1, outside the repository; R117 PASS): ADD `:01` with peer
   `10.100.1.18` → ERR, no record, nothing programmed, and the journal names
   R103; the true pair → OK. The published text is left as written:
   **The agent does not bind a peer address to its slot.** Added
   2026-09-28, from F D20 (`f12-readpass-report.md`, outside the repository).
   `netvm-agent` accepts any peer in the `/24` on any slot (F § 1.7). Under
   the finding-12 guard, a NETCFG ADD that pairs slot `kk` with a peer other
   than `10.100.1.(16+k)` is accepted by the agent, and its traffic is then
   dropped by the guard **silently**: a counter with no reader, since the
   agent has no `RUN`. **Deferred to networking arc step 4** (ADR-037 R55),
   with #19 and #41, where the host assigns slots.
   **[Note 2026-09-28 (ADR-037 R67): it lands in step 4c, the netVM rebuild
   after G5 and before the second networked AppVM, not with #19 and #41 in
   4a. G5 does not require it.]**
   **[Note 2026-09-29 (`wp-0929e`; R103): ruled, not resolved.** The check
   is a decode-time `Rejected` in the agent's parser. A pool MAC
   `52:54:01:00:00:kk` requires the peer `10.100.1.(16+k)`, and a non-pool
   MAC may not name a peer in `.16`–`.31`. On the wire it is a bare ERR, and
   the reason is in the agent's journal. It lands in 4c (ADR-035's note of
   this date).**]**
   **[Note 2026-09-30 (`s4c-a`, `4bdfb0f`): implemented in `parse()`,
   unit-tested on the Acer, UNVERIFIED in a guest.** Closing is 4c B's
   (a mis-paired ADD → ERR, nothing programmed, the reason in the
   journal).**]**
   **[Note 2026-09-30 (`s4c-b`): observed in the guest.** ADD `:01` with
   peer `10.100.1.18` → ERR, no record, `km01` DOWN with no address, and
   the journal reads *"a pool MAC 52:54:01:00:00:kk requires the peer
   10.100.1.(16+k) (R103)"*. The true pair → OK. Closing is the
   operator's.**]**

50. **The failure paths of R52's preflight and R48's read-back have not run
   on a real image.** Added 2026-09-28, from `f12-impl-B-report.md` § 6
   (*not executed*, outside the repository). Both executed in the step-3a
   build on their pass paths only. The failure paths are written and
   **UNVERIFIED**. They first execute on a build with a deliberately broken
   ruleset (R52) or a broken pair (R48). The pair of observations that
   settles each is a `die` line quoting nft's output (R52) or naming the
   slot (R48), then the trap's `lvremove`. R48's extracted block ran six
   mutations on the Acer in f12-impl-A's driver, which is not the
   executable.

51. **RESOLVED 2026-09-30 (R118) — by `c8950b6` (R73): the four comments are
   corrected to ADR-024.** Kept as a closed marker so the number is not
   reused. **Evidence:** the commit, in `s4c-a-report.md` W5 (outside the
   repository). Comments only, so there is nothing behavioural to observe.
   The published text is left as written:
   **Stale SHUTDOWN comments contradict ADR-024 and the netVM agent.**
   Added 2026-09-28, from S D6 (`s4-readpass-report.md`, outside the
   repository). `agent/crates/katmate-protocol/src/opcode.rs:22` gives
   SHUTDOWN in netvm-agent as *"absent — host QMP/ACPI"*, `:25–29` says it
   is absent *"by design"* because the host powers netVM down with QMP
   `system_powerdown`, and `:43–45` says *"netVM does NOT handle this"*.
   `agent/crates/vm-agent/src/op.rs:22–23` says *"netVM does NOT have this
   opcode; it is q35, so the host uses QMP instead."* netvm-agent handles
   SHUTDOWN (ADR-024; `agent/crates/netvm-agent/src/op.rs`). Comments only,
   and nothing behaves wrongly. **Ruled (ADR-037 R73):** fixed in their own
   commit, in networking arc step 4c.
   **[Note 2026-09-30 (`s4c-a`, `c8950b6`): the four comments are
   corrected to ADR-024.** They are comments only, with nothing behavioural
   to gate; whether this entry is closed is the operator's.**]**

52. **The AppVM kernel starts `netconsole`, and where it sends is unread.**
   Added 2026-09-28, from s4-m0 (`s4-m0-report.md` § 6 item 6, outside the
   repository). Every boot of step 4.0 printed *"printk: legacy console
   [netcon0] enabled"* and *"netconsole: network logging started"* on the
   microVM kernel `b34026dd…`. Its targets, and whether any kernel message
   left the guest over the slot, were not read. It belongs with the kernel
   config and #22: the config that would say how `netconsole` is built and
   configured is not proven to be the image's.

53. **RESOLVED 2026-09-29 — by `47c4305` (R91): katmate-init sets
   `umask(022)` in `spawn_agent()`'s child before `vm-agent` starts, and
   PID 1 keeps `umask(0)`.** Kept as a closed marker so the number is not
   reused. **Evidence:** an `objdump` reading shows it in the baked
   `/sbin/init` (s4b2-impl-B P4, P5). In a guest on that image, G2's
   positive half read `umask` `0022` and a new file `-rw-r--r--`, as uid
   1000 in `foot` (s4-gates, `g2p.txt`). `g1.txt`, written before R91,
   stays `0666` on the home LV. The published text is left as written:
   **Files created in the AppVM's user session are mode `0666`.** Added
   2026-09-29, from s4b-impl-B § P8 (`s4b-impl-B-report.md`, outside the
   repository). `g1.txt`, written by the operator's shell in a `foot`
   window as uid 1000, reads `-rw-rw-rw- host host` on the home LV. That
   suggests umask 0 in the user session. **Cause inferred, not read:**
   katmate-init runs with `umask(0)` (`main()`'s first statement) and
   starts `vm-agent`, which starts the applications; that the umask is
   inherited that far was not read, and no `umask` was run in the guest.
   Every file an application writes in `/home/user` would be
   world-writable. Outside ADR-038. Look before the next guest release.

54. **RESOLVED 2026-09-29 — by the operator's R97: `proton.conf` carries
   the pref-100 hooks, `wg-quick@proton` owns the tunnel, and host IPv6 is
   off permanently, by decision.** Kept as a closed marker so the number is
   not reused. `[Interface]` carries `PostUp = ip -6 rule add pref 100
   unreachable` and `PreDown = ip -6 rule del pref 100 || true` (applied
   17:32–17:36 CEST). The tunnel had been up outside systemd
   (`wg-quick@proton` `disabled`, `failed`); the operator ran `wg-quick down
   proton`, then `systemctl start` and `enable` on the unit. **Evidence
   (`wp-0929e`'s P-check, MINIS, 18:25:00 CEST, read only):** `ip -6 rule
   list` shows `100: from all unreachable`; the unit is `enabled` and
   `active`; `proton.conf:11–12` are exactly the two hook lines. The
   operator observed `curl -6` failing in 46 ms (*Could not connect to
   server*) and `curl -4` in 0.28 s. Host IPv6 returns only by removing the
   hooks, or for a measurement by `ip -6 rule del pref 100` at runtime.
   **Still on MINIS at the P-check:** the `gai.conf` workaround,
   `/etc/gai.conf:66` `precedence ::ffff:0:0/96  100`. It is now
   unnecessary, and its removal is the operator's. Why the chroot's apt
   flooded (B's P3) is still not read. The published text is left as
   written:
   **MINIS's IPv6 through `proton` is a black hole.** Added 2026-09-29
   (the operator, during s4b-impl-B; `wp-0929c`). The host's traffic, IPv4
   and IPv6, is policy-routed into the `proton` WireGuard tunnel (table
   `51820`: `ip route get 151.101.2.132` → `dev proton table 51820 src
   10.2.0.2`). IPv4 through it works (`curl -4`: 0.35 s); IPv6 does not
   (`curl -6`: connect timeout at 20 s). `wget`, debootstrap's fetcher,
   tries IPv6 first and waits out a TCP timeout per file. **Workaround:**
   the operator appended `precedence ::ffff:0:0/96  100` to MINIS's
   `/etc/gai.conf` on 2026-09-29 at 11:42, during B's `make foundation`,
   so host processes prefer IPv4. **Its limits:** it applies to host
   processes only; a chroot's apt reads the chroot's own `/etc/gai.conf`,
   not the host's. It is a **dev-host workaround**, not part of the
   shipped host, and is therefore not in `docs/HOST-CONFIG.md` (operator
   ruling, 2026-09-29). **The real fix is the VPN's IPv6 configuration,
   which is the operator's.** Beside it, unexplained: B's P3 anomaly —
   about 1.8 M apt *"Tried to start delayed item … but failed"* warnings
   inside the chroot in the foundation build, and 61 min against 30 on
   2026-09-26. Whether the black hole caused them is not read.
   **[Note 2026-09-29, later (s4b2-impl-B; the operator's rulings;
   `wp-0929d`): it is intermittent, not a black hole.** Over the day, IPv6
   through `proton` answered once (HTTP 200 at 14:45:17, in 1.8 s) and
   timed out five times (11:39, 14:57:20, 14:57:50, 14:58:20 and 15:10:08,
   20 s each). Every time, the route was `dev proton table 51820`. R93's
   premise is restated to match: IPv6 through `proton` cannot be relied on
   for the duration of a build, so every image build holds host IPv6 off
   (§ *Invariants & gotchas*). **Beside the rule,** `make foundation` took
   5 min 16 s with 0 apt `W:` lines, against 61 min and 1,797,989 without
   it. There is one run each, so that the flood was the IPv6 wait is an
   inference. **The planned fix, not yet applied:** the operator will add
   `PostUp = ip -6 rule add pref 100 unreachable` and `PreDown = ip -6 rule
   del pref 100` to the `proton` WireGuard configuration. Once that is
   applied, the `/etc/gai.conf` line becomes unnecessary. The title and the
   text above are left as written.**]**

55. **An AppVM reaches the host's own LAN address (development
   configuration only).** Added 2026-09-29 (operator ruling R99;
   `wp-0929e`). **Scope:** the production host has no NIC of its own,
   because netVM holds the only one. On MINIS the dev NIC (`10.3.1.3`) shares
   the LAN with netVM's uplink. ADR-037's G5 showed the path: the guest's SYN
   to `10.3.1.3:8099`, NATed by netVM to `10.3.1.172`, reached MINIS's own
   dev NIC, and only the host's `inet filter input` decided what got
   through. **What is open today** (`wp-0929e`'s P-check, 18:25:00 CEST,
   read only):

   ```
   table inet filter {
   	chain input {
   		type filter hook input priority filter; policy drop;
   		ct state invalid drop comment "early drop of invalid connections"
   		ct state { established, related } accept comment "allow tracked connections"
   		iif "lo" accept comment "allow from loopback"
   		meta l4proto { icmp, ipv6-icmp } accept comment "allow icmp"
   		tcp dport 22 accept comment "allow sshd"
   		meta pkttype host limit rate 5/second burst 5 packets counter packets 14 bytes 840 reject with icmpx admin-prohibited
   		counter packets 1084 bytes 64280
   	}
   }
   ```

   So an AppVM reaches the host's **ICMP and TCP 22 (sshd, open problem
   #4)**. Anything else addressed to the host gets the rate-limited
   `admin-prohibited` reject, which is G5's *"No route to host"* by
   inference, or the policy drop. **A block is wanted, later, and it is not
   decided.** The candidates: a drop on the host for netVM's uplink address
   (a DHCP lease, which may change), or a `forward` drop in netVM for the
   segment → the host's LAN address.

56. **The shared decoder no longer rejects an unhandled opcode before it
   reads the request body.** Added 2026-10-03 (operator ruling R145; cd2,
   read in the tree, not run). ADR-039 specified that the reader validates
   the command in the fixed header, before any variable-length data. Since
   the workspace split (ADR-021), `read_request`
   (`agent/crates/katmate-protocol/src/frame.rs:215`) reads the opcode
   unmapped (`:226`), then the arguments and the payload, and each binary
   maps the opcode only afterwards (`vm-agent/src/main.rs:475`,
   `netvm-agent/src/main.rs:192`). A request carrying an opcode the
   receiving binary does not handle can therefore cost a read and an
   allocation of up to `MAX_FILE_SIZE` (100 MiB) before the ERR response.
   **The risk as it stands:** the peer of both agents is the host, which is
   TCB, so reaching this path needs a host process able to connect to the
   agent's port (see #18 on the global CID space). Whether the decoder
   should again reject an unhandled opcode before the body is the open
   question. ADR-039's revision note of 2026-10-03 records the change.
   **[2026-10-03, ai5: `vm-agent/src/main.rs:475` above is now `:513`
   (`2a9e638` added code above it). The text is left as written.]**

57. **`katmate-update` maps an instance delta to its app type by the
   name's suffix.** Added 2026-10-03 (operator ruling R149; found by ai4,
   ai4-report § 5 item 6; read in the tree by ai5, not run).
   `build/katmate-update.sh:160–161` and `:193–195` take the type as the
   last `_` segment of the delta's name (`type="${base##*_}"`), and
   `:164` dies on a type outside `APP_TYPES`. Of the four deltas,
   `app_web` → `web` and `app_vault` → `vault` map right by coincidence of
   name. `app_personal` → `personal` and `app_work` → `work` are unknown,
   so **the first such delta aborts the whole update**, before anything is
   rebuilt. (ai4's entry, now in `docs/SESSIONS.md`, also lists `app_vault`
   as refused. The code maps it.) The instance's T1 `manifest` key, or
   the delta's own backing file, would name the type. Which one the
   updater should read is the open question. It is not fixed here.

## Next steps

**ADR numbering.** `ADR-030` = *what the launch daemon reads* (2026-08-06).
`ADR-031` = the licence declaration (GPL-3.0 attribution for the
CYBRland-derived `desktop/` subtree) — **decision taken, document not written**;
the number stays reserved and the gap in the sequence is an honest record of
that. `ADR-032` = *where each tier lives* (2026-08-09).
**[Note 2026-10-03 (R168): ADR-031 is written** (`acfd764`, R159):
GPL-3.0-only for the whole repository, and the reservation is filled.**]**

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
   on the wrong interface. **[2026-09-27: the `katmate-sys-driver@.service`
   half is done (`a36bdb2`); `net-sys.con` still names `tap-int0` and is not
   done.]** `ExecStopPost=` must unlink the slot's socket, since a
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
live root shell** — no login step is needed. **[BOTH FALSE as of 2026-09-20,
and this sentence is the one addressed to a reader about to touch the machine:
the host rebooted on 2026-09-19, the slot tree and the console are gone, and
the next `systemctl start` of either template hits `208/STDIN` before
`ExecStart=`. See § *Live state*, the block *The apparatus described above and
below is destroyed*, and § *Invariants & gotchas*. The `ping-client` line above
remains the correct re-install form; there is nothing to issue it to.]**
**[`208/STDIN`: ruled and applied 2026-09-26 (R1) — both `/etc` drop-ins
removed; see § *Live state*, netVM.]** **Outstanding before the next
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
   **[2026-10-02, `ai4` (read-pass ruling 3): the first half of this item no
   longer holds.** `katmate-app-offline@` ships (`233794d`, R135), and
   `app-web.meta` exists (it has since 2026-09-26). The gates the item
   refers to are ADR-030's G2, re-pointed to `katmate-app-offline@app_vault`,
   and ADR-032 H2, taken in its original pairing (ADR-030's note of
   2026-10-02). The `.con` deletion half is unchanged. The item is left as
   written.**]**

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

- **[SUPERSEDED 2026-09-27 by ADR-037 (R5, R17, R18), and implemented
  (`8f388d4`; G4 passed on 2026-09-27).** netVM resolves directly upstream
  through dhcpcd's `resolv.conf`, and dnsmasq serves the slots only. There is
  no `20-uplink.network` any more, and vanilla has no ProtonVPN. Clear-text DNS
  to the upstream the uplink receives is accepted for vanilla (R18). *"(LAN
  router)"* below is wrong as well: `1.1.1.1` is a public resolver, and the
  router is `10.3.1.1` (rp D5). The item is left as written.**]**
  **DNS-leak policy in the manifest** — the uplink DHCP offers `DNS=1.1.1.1`
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
  **[Note 2026-09-27: vanilla netVM carries no VPN** and no placeholder
  (ADR-037 R20; `proton.conf.template` is removed). A VPN is a post-install
  option: the user supplies a WireGuard config through the config disk (R8),
  which is **not implemented** (networking arc step 3). The text above is
  left as written.**]**
  **[Note 2026-09-27 (R30, ADR-037's note on the step-3 rulings): VPN mode is
  networking arc step 5, not step 3**, under its own ADR, after arc step 4.
  Arc step 3 is the config disk and the static uplink only. R8's T1
  directory is now `/etc/katmate/vm/<instance>.d/` (R31); the modes for a
  secret there are step 5's.**]**

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
  **[2026-09-27: `tap-int0` is retired on the host. Both files were moved to
  `~/katmate-dev/removed-0927/` and the link deleted (§ *Live state*,
  netVM). The `RequiredForOnline=no` lesson stands.]**

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
  **2026-09-26: see open problem #35.** Two keepers were measured, and the fix
  is deferred past the alpha.
- ~~**udisks2 check:** confirm nautilus works with udisks2 disabled, then bake
  `systemctl disable udisks2` into the app-layer build.~~ — **retired
  2026-09-26: the subject is void.** nautilus is gone, and `udisks2` is absent
  from the built foundation and from `vm_app_web` (`appweb-rebuild-report.md`
  §§ 5.2, 5.3).
- **Networking arc for `app_web`** (added 2026-09-26). The order is: bring
  netVM up, which needs the `208/STDIN` decision first; then the slot on the
  AppVM side; then the guest's IP, following the operator's direction of
  2026-09-26 (katmate-init sets it at boot, and vm-agent may also set address,
  DNS and gateway at runtime; the mechanism is not chosen); then `NETCFG`; then
  forward, NAT and DNS in netVM.
  **[SUPERSEDED later on 2026-09-26 by the *Networking arc (2026-09-26)* block
  below: netVM is up, `208/STDIN` is ruled (R1), and forward, NAT and DNS are
  decided by ADR-037. Left as written.]**
- **Networking arc (2026-09-26)**, in this order
  ([ADR-037](docs/DECISIONS.md#adr-037), PROPOSED):
  1. **The pool unit into the repository** (open problem #39) — R4 changes it,
     so it is tracked before it is edited. **[Done 2026-09-27 by folding: the
     pool is in the tracked `katmate-sys-driver@.service` (`a36bdb2`), and R4
     is made to that unit.]**
  2. **ADR-037 implemented in one netVM rebuild:** `addr=` on `vfio-pci`,
     `uplink0.link` on `Path=`, the ruleset on `oifname "uplink0"`, `dhcpcd`,
     `dnsmasq`, and the ownership fix (open problem #38), with #27 alongside.
     Its gates G1–G4 are read on that build.
     **[Note 2026-09-27 (operator rulings R10–R28, ADR-037's note of that
     date): the step now contains** `addr=0x4` with comment (6) (R10);
     `60-katmate-uplink.link` and the rename build gate as a file check on 17
     `.link` files (R12); `UPLINK_PCI_ADDR` in `netvm.meta` (R13); dhcpcd
     with `allowinterfaces uplink0`, `noipv4ll`, `ipv4only`, in its dbus-free
     package form (R14, R16); systemd-networkd disabled, and the agent's
     `Wants=`/`After=` on it dropped (R15); dnsmasq in wildcard mode on `km*`,
     DNS only (R17); no loopback in `resolv.conf` (R18); no explicit reverse
     rule and no `udp dport 51820` (R19); `proton.conf.template` removed and
     `wireguard-tools` kept (R20); no `icmpv6` accept (R22); `root:root` in
     step 5 (#38) and `nftables.conf` at `0644` in its own commit (R23); the
     agent unit moved into `manifests/netvm.conf.d/` (#27, R24); and a dev
     build (R27). **G3 is split (R25):** the DHCP half, with its `km*`
     refusal half (R14), is taken here, and the static half at step 3. **G4 is
     taken with a fixture peer** on a slot's `appvm` socket, plus a LAN
     refusal half (R26). G1 is accepted as not discriminating cause (R11).
     The finding-12 guard is **not** in this step (R21).**]**
     **[DONE 2026-09-27 (`adr037-impl` A and B):** implemented in
     `6827583`…`c37f9d1` (pushed), built at `2026-09-27T13:01:13Z`. **G1 PASS**
     (does not discriminate cause, R11); **G2 PASS**; **G3 DHCP half PASS**, and
     its refusal half **PASS as ruled** (scoped to dhcpcd-originated state);
     **G4 PASS**, and its refusal half **PASS** (does not discriminate cause);
     the R12 build gate **PASS**. ADR-037 stays PROPOSED. **Next, in order:**
     step 3 (R8, G6, and G3's static half), then 3a (the finding-12 guard),
     then step 4 (the AppVM side, G5, and #45).**]**
  3. **The config disk** (R8, open problem #40; ADR-037 G6).
     **[Note 2026-09-27 (rulings R30–R40, ADR-037's note on the step-3
     rulings): the step is the config disk and the static uplink** (R30),
     gated by G6 and G3's static half (R39). VPN mode is not in it (step 5
     below). **Two readings come before any code:** the guest PCI
     enumeration from the host journal, with the command in r8 Q-R8d (R34);
     and, in the guest, the packaged `dhcpcd.service` and its hooks (R38).
     **The sequence is r8 § 4's:** the flat-reader refactor of
     `katmate-lib.sh` in its own commit (R37); a `0700` run-subdirectory
     helper, if the existing one is not parameterised (R32); the builder;
     then the unit
     change (the `ExecStartPre=+` line and the drive/device pair), installed
     onto the **current** image with no T1, the absent path. **That comes
     before the guest consumer and the rebuild. It is the one hard ordering
     constraint**, because a rebuilt image with the consumer would wait on a
     disk that is never attached. Then the consumer, the dev-build rebuild
     (reboot before, suspend masked), G6 with R-a…R-d, and G3's static half.
     **The static T1 for G3**, which the operator writes on MINIS himself
     (R25): `address = "10.3.1.172/24"`, `gateway = "10.3.1.1"`,
     `nameservers = "10.3.1.1"`. r8 is `~/Claude.assistent/r8-readpass-report.md`,
     outside the repository.**]**
     **[DONE 2026-09-27 (r8-impl A and B):** the two pre-code readings taken
     (R34, R38), implemented in `e659db3`…`ba11679` and `8f6ebd5` (R45),
     pushed; installed on MINIS in the r8 § 4 order, the absent path first on
     the old image; rebuilt at `2026-09-27T18:34:22Z`. **G6 PASS**, pass half
     and R-a to R-d, with the R42, R45 and symlink refusals; **G3's static
     half PASS**, pass and refusal, with a positive control. The static T1
     was written under R46 and stays. ADR-037 stays PROPOSED (G5). What did
     not run as installed is #46. **Next, in order:** 3a (the finding-12
     guard), then step 4 (the AppVM side, G5, and #45), then step 5.**]**
     **3a. The finding-12 slot guard** (added 2026-09-27, R21). It is its own
     step with its own gate, and it must land **before step 4**, the first
     AppVM on a slot. The candidate is
     `~/Claude.assistent/nftables-f12-candidate.conf`, outside the repository.
     It was written against the pre-ADR-037 ruleset, and its gate (a),
     `nft -c` inside netVM (nft 1.1.3), is untaken. *(Numbered 3a so that
     "arc step 4" keeps the meaning every existing reference gives it.)*
     **[Note 2026-09-28 (rulings R47–R56, ADR-037's note of that date; gates
     F12a and F12b, ADR-035's note of that date): ruled, not implemented.**
     The candidate is a source for the `slot_guard` chain only (R47). **The
     sequence:** `f12-impl-A` on the Acer — the guard on the ruleset in the
     tree (R47–R50), R51's `30-netvm-forward.conf` in its own commit, the
     `netvm.sh` read-back of the sixteen pairs (R48) and the `nft -c`
     preflight (R52), and the extended fixture (R53); then `f12-impl-B` on
     MINIS — read `rp_filter` on the running image (R51's precondition),
     reboot, rebuild, F12a, F12b.**]**
     **[DONE 2026-09-28 (f12-impl A and B):** implemented in `629c92d`,
     `2ca851f` and `56b3c96` (pushed); built at `2026-09-28T17:38:12Z`.
     **F12a PASS; F12b PASS**, every row, 2c on the kernel martian witness
     (R59). R51's `rp_filter` reading held before and after. The IPv4 half
     of finding 12 only; #34 is the ARP half (R54). ADR-037 stays PROPOSED
     (G5). What did not run is #50. **Next is step 4, then step 5.**]**
  4. **The AppVM side:** the slot, the guest IP, `NETCFG`, and `accept_ra=0`
     (open problem #24); ADR-037 G5 needs this step. **[Added 2026-09-27:**
     also the removal of the generator's `KM_MAC_INT` `sys` branch, in its own
     commit, alongside #19 (open problem #41).**]** **[Added 2026-09-28
     (ADR-037 R54):** this step may start with the ARP half of finding 12
     (#34) open. #34 must land before the second networked AppVM.**]**
     **[Note 2026-09-28, later: this is the next step.** It carries the
     slot, the guest IP, `NETCFG`, `accept_ra=0` (#24), G5, #45, #19 and
     #41, and R55's agent-side pairing check (#49).**]**
     **[Note 2026-09-28, s4-readpass and rulings (ADR-037 R60–R75): this
     step is split, and this sub-list supersedes the list above** (R60),
     which is left as written. In order:
     - **4.0** — a measurement with no code, fixture-grade.
     - **ADR-038** — guest addressing, written after 4.0 (R65).
     - **4a** — the host side: the `app-routed` template, the generator
       (#19's guard and the `REQ_ENV` arm in one commit, R61; #41), the
       slot (R62, R63), `ExecStopPost=` (R74), the delta rename (R69).
     - **4b** — the guest image: katmate-init; foundation → app layer →
       delta.
     - **G5** — with a real AppVM, and its refusal half (R71).
     - **4c** — `netvm-agent`, in one netVM rebuild, after G5 and before
       the second networked AppVM, together with #34 (R67); and the
       SHUTDOWN comments in their own commit (R73, #51).**]**
     **[Note 2026-09-29 (`wp-0929a`, R77): ADR-038 is written, PROPOSED.**
     4b carries its three build and code items: katmate-init per ADR-038;
     the resolver symlink `../run/resolv.conf` with its read-back in
     `foundation.sh` and `app-layer.sh`; and the rebuild chain, foundation →
     app layer → delta. The text above is left as written.**]**
     **[Note 2026-09-29 (`wp-0929b`): 4a is done** (s4a-impl A and B;
     ADR-037's note of 2026-09-29). No gate was taken. Next is 4b. Two
     deferred items travel with the next host install (4b or later), in
     the same session as their reinstall, because both touch installed
     files: the stale comments of the T1 `app_web.toml` on both machines,
     and `katmate-app-routed@.service:149–152`'s *"UNVERIFIED … 4a-B
     observes it"*. The text above is left as written.**]**
     **[Note 2026-09-29 (`wp-0929c`): 4b is done** (s4b-impl A and B;
     ADR-038's and ADR-037's notes of 2026-09-29, step 4b). ADR-038's G1
     positive half and G3 are passed (R89, R90). What remains of step 4: a
     ruling on the vehicle for an altered `-append` (G1's refusal half, G2,
     and G5's refusal half, R71); the `init/tests/run.sh` route-verdict fix
     with its re-run of `--apply` on MINIS; the guest umask (#53); then G5,
     then 4c. The two deferred host-install items above still travel with
     the next host install. The text above is left as written.**]**
     **[Note 2026-09-29 (`wp-0929d`): networking arc step 4 is closed.**
     R91 and the harness fix landed (4b2-A), and the chain was rebuilt on
     them (4b2-B). On R92's vehicle, ADR-038's G1 refusal half and G2, and
     ADR-037's G5 in both halves, passed (R95). **ADR-037 and ADR-038 are
     Accepted** (R96), so this block's *"(ADR-037, PROPOSED)"* is stale
     from this date. **Next is 4c**, one netVM rebuild before a second
     networked AppVM. It carries `netvm-agent`'s items (R55's pairing check
     #49, ADR-035 §7's count and §6, and DOWN on REMOVE #45) and #34's ARP
     half. R73's SHUTDOWN comments (#51) go in their own commit. The two
     deferred host-install items still travel with the next host install.
     The text above is left as written.**]**
     **[Note 2026-09-29 (`wp-0929e`): 4c's read pass is done** (on the
     Acer, `s4c-readpass-report.md`, outside the repository), and the
     operator has ruled on it: **R100–R113** (ADR-035's and ADR-037's notes
     of this date). In short: #34 is a `table arp` (R100); R55 is a
     decode-time `Rejected` keyed on the MAC (R103); §7 counts, and REMOVE
     does not absorb a duplicate (R104); records are keyed by `match_mac`
     (R105); no `RTM_DELNEIGH` (R106); the conntrack flush is by mark
     (R107); `ipv6.disable=1` on netVM's kernel (R102); `ip_forward` is set
     after `nftables.service` (R111). The commit order is R108's. **Next is
     `s4c-m0`** (R101): a console measurement with no code — the four
     kernel config symbols, `nft --version`, one throwaway `table arp`, and
     no `flush ruleset`. **Then 4c A** (the code, on the Acer) **and B**
     (one netVM rebuild, with the reboot before `netvm.sh`, and the gates).
     The text above is left as written.**]**
     **[Note 2026-09-30 (`s4c-a`): `s4c-m0` and 4c A are done.** 4c's code
     and configuration are committed and pushed (`c8950b6`…`9010130`), with
     R114–R116 in ADR-035's and ADR-037's notes of 2026-09-30. **Next is 4c
     B:** rsync; reinstall `katmate-sys-driver@.service`
     (`ipv6.disable=1`); build `netvm-agent`; reboot before `netvm.sh`, with
     suspend masked; rebuild; then the gates on the new image, with R109's
     `f12peer.py` modes. The UNVERIFIED list is § *This session* and
     `s4c-a-report.md` § 6. The text above is left as written.**]**
     **[Note 2026-09-30 (`s4c-b`): 4c B is done** (§ *This session*). The
     gates are observed, and the verdicts are the operator's. Still open
     from 4c: G6b (no procedure in the record) and #48's fail-closed half.
     For the next write pass: whether `build/netvm.sh` builds
     `netvm-agent`, and s4c-a's proposed notes (ADR-021's bake list; the
     supersession windows: a leftover `peer/32` route of the shape tested
     is cleared by the DOWN at the slot's next REMOVE).
     The text above is left as written.**]**
     **[DONE 2026-09-30 (`wp-0930`): networking arc step 4 is done.** 4c's
     verdict is PASS (R117), on every row of s4c-b's B5 and B6. #34, #45,
     #49 and #51 are closed, and #48 is open for its fail-closed half only
     (R118). ADR-035 stays PROPOSED until G6b is taken or deferred (R119).
     The write pass's items are done: `netvm.sh` refuses a missing or stale
     agent and does not build it (R120, `06ab509`), and both of s4c-a's
     proposed notes are written (ADR-021's in `17479cf`, ADR-035's in
     `ff68306`). **Next is the alpha integration** (`ROADMAP.md` § *Build
     order*, *Alpha integration*, the operator's ruling of 2026-09-21): the
     remaining AppVMs on the existing netVM's slots, one at a time and vault
     last, MINIS first. `docs/PARAMETERS.md` is created by the first
     integration session with its first row, and filled as each AppVM
     lands. Still open from 4c: G6b and #48's fail-closed half.**]**
     **[Note 2026-10-02 (`ai1`): alpha integration step 1 is done.**
     `app_personal` (CID 22, slot 02, `LINK_ID=202`) ran beside `app_web`
     (CID 21, slot 01) on one netVM, and `docs/PARAMETERS.md` exists
     (`5b331c1`). See § *This session*. **Next is the next alpha AppVM.**
     office needs a manifest, which is a design choice not yet made, and
     vault needs the per-manifest RUN whitelist. **Each one first needs a
     decision on the hugepage pool**: four AppVMs at 4G + 2G + … exceed
     4096 × 2 MiB. Still open from 4c: G6b and #48's fail-closed
     half.**]**
     **[Note 2026-10-02 (`ai3`): alpha integration step 3 is done, and two
     clauses of the note above no longer hold.** office has its manifest
     (`office.list`, R129), and `app_work` (CID 23, slot 03, `LINK_ID=203`)
     ran beside the other two. *"vault needs the per-manifest RUN
     whitelist"* is false: keepassxc is on the compile-time whitelist (R130,
     ADR-021's note), and a per-manifest whitelist is post-alpha. The pool
     question was answered by R126 (ai2, 12 GiB). **Next is the vault
     AppVM**, the last of the alpha: it needs an offline template that
     carries `km.name=%i`. Still open from 4c: G6b and #48's fail-closed
     half.**]**
     **[Note 2026-10-02 (`ai4`): alpha integration step 4 is done.**
     `app_vault` (CID 24, offline) ran under `katmate-app-offline@` beside
     the three routed AppVMs, and every AppVM of the alpha has now run.
     **Next:** the menu step that ends the alpha (its input is the ai4
     report's § 6 ledger); vm-agent selecting the Qt platform for a RUN
     child, so that RUN `keepassxc` opens a window (a foundation rebuild);
     `katmate-update`'s delta-to-type mapping, which works by name suffix.
     Still open from 4c: G6b and #48's fail-closed half.**]**
     **[Note 2026-10-03 (`ai5`): the Qt platform item is done** (R146; RUN
     `keepassxc` opened a window on the rebuilt chain), and every layer has
     `ip` (R147). `katmate-update`'s mapping is open problem #57 (R149).
     **Next:** the menu step that ends the alpha (ai6; its inputs are the
     ai4 report's § 6 ledger and the ai5 report's § 6). Still open from 4c:
     G6b and #48's fail-closed half.**]**
  5. **VPN mode** (added 2026-09-27, R30): the WireGuard config, the VPN
     ruleset and the kill-switch, under **its own ADR**, after step 4. R8
     names the config disk as the WireGuard config's channel, and R31 gives
     the T1 directory; the modes for a secret there are this step's (r8 D12).
     Nothing else of it is designed. *(Numbered 5, not "3b": build-order step 3b is
     the launch daemon, and shipped T4 comments cite it by that name; r8 D9.)*
- **waypipe on the host** (added 2026-09-26):
  - ~~Remove the distro `waypipe` package from MINIS.~~ — **done 2026-09-26**
    by the operator (`pacman -Rs waypipe`); see § *Live state*, *Host GUI
    ingress*.
  - Bring the `waypipe-client` unit into the repository. HOST-CONFIG § 11 now
    records it as a requirement; the unit file itself is still untracked (#31).
  - Do the single static waypipe build (direction ruled 2026-09-14) and any
    version bump together, through `katmate-update`.
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
  **[Note 2026-09-27: vanilla netVM carries no VPN** (ADR-037 R20). A VPN is
  a post-install option through the config disk (R8), **not implemented**.
  The tunnel this item guards against is the host's `proton` link, which is
  dev scaffolding (the operator's gap-3 ruling of 2026-09-27; SECURITY-MODEL
  gap 3). The text above is left as written.**]**

## Invariants & gotchas (quick reminders — detail in git/ADRs)
- **The guest's serial console is durable in the HOST journal, and that is an
  observation path no document recorded.** `katmate-pool@.service` binds the
  guest serial line to a stdio chardev (`-chardev stdio,id=console0,signal=off
  -serial chardev:console0`) and carries `StandardOutput=journal`, so **the
  guest's whole boot console lands in the host journal** — which is persistent
  back to 2026-07-28 and **outlived the guest by a reboot**. This is how open
  problem #33 was answered on 2026-09-20 with netVM destroyed: the guest boot of
  2026-09-12 was read out of the host journal of the *previous* host boot. **A
  reading that needs the guest's boot messages does not need the guest.** Two
  consequences, and both matter: the path is load-bearing for observation, and
  it is also an unrated, unlabelled write from guest to host (SECURITY-MODEL
  gap 15 territory — a containment is **proposed** in
  `~/Claude.assistent/b1-docwrite-report.md`, not written).

  **The trap it carries: `journalctl` records embed ANSI escapes between
  words.** `grep 'Finished systemd-sysctl'` matched **nothing** on a record that
  reads `Finished \x1b[0;1;39msystemd-sysctl.service\x1b[0m` — the phrase is
  present and the search cannot see it. The probe that hit it failed loudly only
  because a later command depended on its empty result; the silent version of
  the same mistake produces a confident wrong bracket. **Anchor on text that
  carries no embedded escape** — the re-take anchored on `Apply Kernel
  Variables` and worked. **Same class as *"a quotation that wraps across a line
  is not a search string"*** below, and as every other case in this section
  where a check that cannot fire is indistinguishable from a check that found
  nothing. Source: `auditfix-liveread-report.md` §§ 2.3, 2.6, 4.3.
- **Kernel `ip=`: a netmask of `255.255.255.255` is replaced by a guess,
  and the gateway is kept.** `ip=10.100.1.17::10.100.1.1:255.255.255.255:::off`
  gave *"IP-Config: Guessing netmask 255.0.0.0"* and completed with
  `mask=255.0.0.0, gw=10.100.1.1`: a `/8` for this `10.x` address, and
  no refusal of the gateway. A `/32` is not expressible through that
  field. With `255.255.255.0` the mask is taken as given. Why the kernel
  guesses was not read. Observed 2026-09-28 on the AppVM kernel
  `b34026dd…`, one boot. Source: `s4-m0-report.md`, boot A.
- **TTL tells a forwarded packet from an originated one**, when a LAN
  host's packet in the same capture is the control. The guest's SYNs,
  NATed to netVM's uplink address, carried **ttl 63** against the Acer's
  **ttl 64** in the same host capture: one routing hop, so forwarded, not
  netVM-originated. It needs `tcpdump -v`; a listing without `-v` does not
  print the TTL, and s4-m0's listing could not answer the question.
  Observed 2026-09-28 (the operator's reading over s4-m0's `cap-B` and
  `cap-C`; the table is in `wp-0928d-brief.md`, outside the repository).
- **`vm-agent` RUN opens the window on MINIS's screen, and firefox restores
  its last session from the persistent `/home`.** Traffic can start about a
  second after RUN, before anyone types a URL: in s4-m0's boot C the first
  SYN came 1.3 s after RUN `firefox-esr`, reloading the tab boot B had
  saved. A procedure that has the operator load a page must say where the
  window appears (not on the Acer, whose own firefox voided two steps of
  s4-m0) and must account for the restore. **The `waypipe-client` user
  journal logs no connections**, not even the RUN of boot B, so it cannot
  attribute a window: its silence is a check that cannot fire. Observed
  2026-09-28. Source: `s4-m0-report.md` §§ 3, 8.
- **A step that opens a window on MINIS's screen is announced first, and RUN
  waits until the operator confirms he is at MINIS's screen.** *"Ready"* is
  not that confirmation. In s4c-b's B6, the first RUN `foot` went out after
  the operator answered *"ready"*. He was not at MINIS and did not know the
  window was up, so the 2-minute poll window saw no flow and measured
  nothing. The second attempt, sent after he confirmed he was at the
  screen, produced the flow. Ask where the operator is, not whether he is
  ready. Observed 2026-09-30. Source: `s4c-b-report.md` § B6, § 4 item 9.
- **`nft -c` run unprivileged is a check that cannot fire — any `nft -c`
  preflight must run as root.** Unprivileged it returns **exit 1 with
  *"netlink: Error: cache initialization failed: Operation not permitted"* on
  every input**, valid and invalid alike, because it cannot open the netlink
  cache before it reaches the ruleset. A preflight written that way **reports
  every candidate as broken while measuring nothing**, and its output is
  indistinguishable from a real syntax rejection. Measured 2026-09-20 on the
  MINIS host under `nftables v1.1.7`, and found only because both privilege
  levels were run as a control: as root the same two files return exit 0 and
  exit 1 respectively, which is precisely the discrimination the unprivileged
  run destroys. Source: `auditfix-liveread-report.md` § 2.5.
- **The unprivileged `nft -c` failure message differs by site; both forms
  mean the check cannot fire.** On MINIS (nft 1.1.7) it is the *"cache
  initialization failed"* line above. On the Acer (nft 1.1.7) it is
  *"Error: Could not process rule: Operation not permitted"* at `flush
  ruleset`, then *"Error: Operation not permitted (perhaps you must be
  root?)"*, exit 1, on a good file and a broken control alike. A search for
  one site's wording does not find the other's. Measured 2026-09-28. Source:
  `f12-impl-A-report.md` §§ 2, 6.
- **The Acer has no site for an `nft -c` syntax check.** `unshare -rn`, the
  unprivileged way to get a network namespace in which nft would run as
  root, is refused on the Acer's kernel (`7.2.6-hardened1-1-hardened`):
  *"unshare: unshare failed: Operation not permitted"*, on the good file
  and on the broken control. Why it fails was not read. A ruleset written
  on the Acer is **UNVERIFIED** until an `nft -c` as root on MINIS (the
  build preflight) or in the guest. Measured 2026-09-28. Source:
  `f12-impl-A-report.md` §§ 2, 5 item 2, 6.
- **R48's extraction strips `#` to the end of the line, so a `#` inside an
  nft comment string cuts the rule.** `build/netvm.sh` reads chains out of
  the baked `nftables.conf` on R48's model, which drops everything from `#`
  onward. A drop rule whose comment read `#34` lost its tail, and the
  read-back failed the good case. **An nft comment in an extracted chain
  carries no `#`.** Making the stripping quote-aware was rejected, because
  it would change R48's proven extraction too. Found 2026-09-30 while
  testing `table arp filter`'s read-back. Source: `s4c-a-report.md` W11.
- **A packet whose source is one of the receiving host's own addresses is
  dropped as a martian source at the input route lookup, before any nft
  hook**, so a counter rule written for that source can never fire.
  Measured 2026-09-28 in netVM: five frames from `10.100.1.1` on `km05` gave
  `in_martian_src` +5 in `/proc/net/stat/rt_cache` and five `log_martians`
  lines naming `km05`, while the R50 counter, whose match covers that
  source, read +0 (F12b row 2c). It was predicted from recall before the
  run (`f12-impl-A-report.md` § 5, item 1) and observed in
  `f12-impl-B-report.md`, gate table. **The same family as *"a check that
  cannot fire"*:** a counter that stays at 0 for such a source measures
  nothing about the rule. Test a rule with a source the kernel lets through.
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

  **The precondition is LIVE and CONFIRMED as of 2026-09-20, and it is armed on
  BOTH units, not only the one this entry names.** After the reboot of
  2026-09-19, `/etc/systemd/system/katmate-pool@.service.d/90-dev-monitor.conf`
  (`:31`) **and**
  `/etc/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf`
  (`:28`) both survived in `/etc`, both setting
  `StandardInput=file:/run/katmate-dev/netvm-console.in`, while
  `/run/katmate-dev/` and the transient holder did not survive — the exact
  asymmetry this entry predicts. `systemctl show` resolves it to a bare
  `StandardInput=file` with **no path and no `StandardInputPath` beside it**,
  confirmed live rather than carried over. **The next `systemctl start` of
  either unit fails above `ExecStart=`.** **Not repaired:** the choice between
  recreating the FIFO and its holder and deleting the drop-in — which restores
  the shipped `StandardInput=null` — is the operator's, and it is unmade.
  Source: `auditfix-liveread-report.md` §§ 2.0, 2.3, 6.2.
  **Ruled and applied 2026-09-26 (R1):** both `/etc` drop-ins removed and
  `StandardInput=null` restored; console input is installed per session, all
  on tmpfs (`net-up-report.md` §§ 14, 15). Absence after a reboot is
  UNVERIFIED until the next boot (§ *Live state*, netVM).
  **[Ruled 2026-09-27 (R9): the drop-in this entry places in `/etc` now goes
  only in `/run/systemd/system/katmate-sys-driver@.service.d/90-dev-monitor.conf`,
  per session, never in `/etc`, so a reboot takes it with the FIFO.]**
  **[Settled 2026-09-27: both UNVERIFIED halves. After the 10:30:45 boot both
  units read `StandardInput=null` with empty `DropInPaths=`, and the folded
  unit started with no `/run/katmate-dev/` (`pool-fold-report.md` §§ 2.1,
  2.6).]**

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
  **The holder, in the form of record** (`netvm-rebuild-3-report.md:267–272`,
  added 2026-09-26; run verbatim as root by net-up § 15):

  ```
  mkdir -m 0755 -p /run/katmate-dev
  chown root:root /run/katmate-dev
  mkfifo -m 0600 /run/katmate-dev/netvm-console.in
  chown root:root /run/katmate-dev/netvm-console.in
  systemd-run --unit=km-console-holder --description='KatMate dev console FIFO writer-holder (dev scaffolding, transient)' \
    /usr/bin/bash -c 'exec 3>/run/katmate-dev/netvm-console.in; sleep infinity'
  ```

  **Before the unit starts, the holder is `comm=bash` with no fd 3** — blocked
  in `wait_for_partner` on the FIFO's open — and that is correct, not a fault:
  the rendezvous completes when the VM unit opens the read end, and only then
  is it `comm=sleep` with fd 3 `l-wx` on the FIFO (`net-up-report.md` §§ 15,
  16.2). A procedure that expects fd 3 before the start misreads a healthy
  holder. **The absence of any recorded form of this holder is what halted
  net-up (its H6); it must not recur.**
  **[Note 2026-09-27 (`adr037-impl-B`): the form of record covers the FIFO and
  the holder, but not the drop-in's content.** Sessions install a saved copy
  unedited, under `/run/systemd/system/<unit>.d/90-dev-monitor.conf` (R9). For
  sys-driver that copy is
  `~/katmate-dev/removed-0926/katmate-sys-driver@.service.d--90-dev-monitor.conf`,
  `b44de3a9…`, 1470 B. Its comments are **stale**: they say it belongs in
  `/etc`, and they cite `katmate-sys-driver@.service:141-147`, which is now at
  `:201-211`. It works as installed, and the stale text is not
  corrected.**]**
- **On the netVM serial console, a pager eats the rest of a command file.**
  Added 2026-09-27, from `r8-impl-B-report.md` (Phase 5, and § 6's proposed
  entry). The serial console is a terminal, so a `systemctl` without
  `--no-pager` opens `less`, and **every following line of a command file
  becomes keystrokes** for `less`. It happened in r8-impl-B: `less` consumed
  the rest of the file, the sending script timed out, and recovery took `q`,
  `q` and a bare newline. Nothing on disk changed, because `less`'s
  log-file command was unavailable and no line began a shell escape.
  **Command files set `SYSTEMD_PAGER=cat` and pass
  `--no-pager`.**
- **`katmate-sys-driver@netvm` and `katmate-pool@netvm` must never run at
  once** — same instance name, same LV, same CID, same VFIO device — and both
  point at the same FIFO, so the `208/STDIN` failure after a host reboot now
  applies to both.
  **Ruled and applied 2026-09-26 (R1):** neither unit carries an `/etc`
  drop-in now (`net-up-report.md` § 14).
  **[2026-09-27: there is now one unit. The pool is folded into
  `katmate-sys-driver@.service`, and `katmate-pool@netvm` is `not-found`
  (`pool-fold-report.md` § 2.5).]**
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
  **[2026-09-27: this applies to the folded `katmate-sys-driver@.service`
  exactly as it did to the pool unit. It carries no `ExecStopPost=` either.]**
  **[2026-09-29: *"remains unimplemented"* and the bracket above are false
  of the tree since `1597445` (R74) and of MINIS since s4a-impl-B installed
  it. The running netVM's loaded unit carries the sixteen-path
  `ExecStopPost=`. It is **unexecuted**, because netVM has not been stopped
  since.]**
  **[2026-09-30 (s4c-b, ruling 5): *"unexecuted"* above is superseded.** At
  netVM's stop of 16:15:28 CEST the sixteen `netvm` nodes went from 16 to 0,
  and the `appvm` nodes it does not name stayed. The record is collected
  after a clean stop, so this is by inference from the paths (ADR-035's note
  of 2026-09-30).**]**
- **`Type=simple` returns from `systemctl start` as soon as QEMU forks —
  before QEMU has bound its netdevs — so the slot bindings are read after the
  guest answers PING, not after `start`.** Measured 2026-09-27: a binding check
  run straight after `start` read **0/16**. It had snapshotted
  `/proc/<pid>/fd` before walking the slots while QEMU was still binding.
  Nodes 00–07 were absent, and 08–0f were compared against the stale fd list.
  A re-take 26 s later read **16/16**, with the same socket inodes for 08–0f,
  so both readings describe one set of bindings seen at two moments.
  **Same family as *"a check that cannot fire…"*:** the first reading was
  confident, well-formed and wrong. Source: `pool-fold-report.md` §§ 2.6,
  2.7.
- **After a clean stop, `systemctl show` on a template instance returns
  defaults; the journal is the record.** systemd garbage-collects an
  inactive, non-failed instance, and the query then loads it fresh:
  `Result=success`, `ExecMainStatus=0`, empty `InvocationID=` and
  `ExecMainExitTimestamp=`, and every `Exec*` record at `start_time=[n/a] …
  pid=0 … code=(null)`. A check of `Result` or `ExecMainStatus` after a
  clean stop cannot fire. What shows the clean exit is the journal:
  *"Deactivated successfully."*, with no *"Main process exited, code=…"*
  and no *"Failed with result"*. A failed unit is not collected, so its
  records are real. **Same family as *"a check that cannot fire"*.**
  Measured 2026-09-29 on `katmate-app-routed@app_web` (P7 against P4 and
  P8). Source: `s4a-impl-B-report.md` §§ 5.1, 6.
- **systemd names the unset variables an `Exec*` line expanded empty.** It
  logs *"Referenced but unset environment variable evaluates to an empty
  string: KM_NETVM, KM_SLOT"*, under `(rm)`, when `ExecStopPost=` runs with
  no projection loaded. It is a free, positive signal that an expansion was
  empty. Its absence after a successful run is consistent with the
  projection having been read, and it does not prove it. systemd does not
  print the expanded argv. Observed 2026-09-29 on
  `katmate-app-routed@app_web` (P4, P8; absent in P7). Source:
  `s4a-impl-B-report.md` §§ P4, P8, 6.
- **`vm-agent` answers PING about 5 s after `systemctl start` of an AppVM
  unit.** Before that, `ping-client` gets *"connect: No route to host (os
  error 113)"*. That error is the not-yet-listening state, not a fault, so
  a PING probe polls: every 2 s, up to 30 s, with the try count recorded.
  Observed 2026-09-29, once, on `katmate-app-routed@app_web`: OK on try 3,
  at about 5 s. Source: `s4a-impl-B-report.md` §§ P6, 6.
  **[2026-09-29, s4b-impl-B § P6: held again — OK on try 3, at about
  4 s, the first self-configured boot. First try `No such device (os error
  19)`, second `No route to host`.]**
  **[2026-09-29, s4b2-impl-B and s4-gates: held four more times, OK on
  try 3 each time. A PING poll's first tries fail with `113` (*No route to
  host*) or `19` (*No such device*), and both have been seen: 19 then 113
  in 4b-B and 4b2-B, and 113 twice in G2+, G5+ and G5−. Neither is a
  fault.]**
- **iproute2 7.2.0 ends each route line with a space — compare route
  output trimmed.** `ip -4 route show` prints `default via 10.100.1.1 dev
  km0 onlink ` (trailing space before the newline), and an exact string
  comparison fails on a correct route. `init/tests/run.sh`'s route verdict
  failed that way. Observed 2026-09-29 on MINIS, in a netns and in the
  host's own main table (`od -c`). Source: `s4b-impl-B-report.md` § P1.
- **`sit0` exists in the AppVM under `ipv6.disable=1`.** The AppVM kernel
  builds `CONFIG_IPV6_SIT` in; the guest lists `eth0`, `lo` and `sit0`
  (flags `0x80`, down). Anything that counts the guest's links must not
  count by *"not loopback"*; katmate-init counts device-backed links
  (R85). Observed 2026-09-29, one boot. Source: `s4b-impl-B-report.md` §
  P8.
- **A file written in the guest is read on the host by mounting the home
  LV read-only after the guest is down.** Have the operator write the
  reading to `~/<file>` in a `foot` window, stop the instance, then mount
  `vg0/vm_app_web_home` with `-o ro,noload` on the host, copy the file,
  unmount. The reading is verbatim, not transcribed, and the LV is never
  mounted while the guest holds it. Used 2026-09-29 for `g1.txt`. Source:
  `s4b-impl-B-report.md` § P8.
- **The foundation build log can reach ~200 MB of apt `W:` lines.** On
  2026-09-29 `make foundation` wrote 1,797,989 identical *"Tried to start
  delayed item … gcc-14 … but failed"* warnings from step 5's `apt-get
  install` (1.8 M lines, 203 MB) and still exited 0. Count by pattern
  (`grep -c '^W:'`, `^E:`), never page the log. The cause is not read (#54
  records what lies beside it). Source: `s4b-impl-B-report.md` § P3.
  **[2026-09-29, s4b2-impl-B: with host IPv6 held off, the log was 173 kB
  with 0 `W:` lines. See the next entry.]**
- **Every image build holds host IPv6 off, and removes the hold after.**
  Before `make foundation` or `make app-web` on MINIS, run `sudo -n ip -6
  rule add pref 100 unreachable`; `ip -6 rule list` then shows `100: from
  all unreachable`. After the builds, run `sudo -n ip -6 rule del pref 100`,
  and the list is as before. Under the rule, `curl -6` fails in under 0.1 s
  instead of waiting out a connect timeout. **Why:** the host's IPv6 goes
  through `proton`, where it is intermittent (#54), and a fetcher that
  tries IPv6 first waits it out per file. **The timing pair:** `make
  foundation` took 5 min 16 s with 0 apt `W:` lines under the rule
  (2026-09-29, 15:01–15:07), and 61 min with 1,797,989 without it (4b-B).
  There is one run each, so the cause is inferred. No VPN file is touched.
  Ruled 2026-09-29 (R93, premise restated). Source:
  `s4b2-impl-B-report.md` §§ P2, P4, P6.
  **[Superseded 2026-09-29, later (R98; `wp-0929e`): a build no longer adds
  or removes the rule.** Since R97 the pref-100 `unreachable` rule is
  permanent, installed by `proton.conf`'s `PostUp` (#54). Adding it would
  fail on the existing rule, and removing it would delete the permanent one.
  A build now **checks** that `ip -6 rule list` shows `100: from all
  unreachable`, and stops if it does not. The *"No VPN file is touched"*
  above describes R93's procedure; R97 is the operator's change to
  `proton.conf`, not a build's. The entry is left as written.**]**
- **`wg-quick down` runs the hooks of the config file as it is now, not as
  it was when the tunnel came up.** A `PreDown` added to a running tunnel's
  file runs at the next `down`. So it must tolerate the absence of what its
  `PostUp` never created: `ip -6 rule del pref 100 || true`. On 2026-09-29
  the hooks were added to `proton.conf` while the tunnel was up, so the
  first `down` ran a `PreDown` whose rule no `PostUp` had made. Source: the
  operator's application of R97, 17:32–17:36 CEST; recorded by `wp-0929e`.
- **`wg-quick@proton` is the one owner of the `proton` tunnel.** Before
  2026-09-29 the tunnel was brought up by hand, with the unit `disabled`
  (and `failed`). `restart` on an inactive unit is a `start`, which fails on
  the existing interface (*"`proton' already exists"*). Bring a hand-made
  tunnel down with `wg-quick down proton` first, then `systemctl start` and
  `enable` the unit. Read `enabled` and `active` on 2026-09-29 at 18:25
  (`wp-0929e`'s P-check). Source: R97, the operator.
- **A gate's altered `-append` is a per-session `/run` drop-in, one line
  different, removed after.** Write
  `/run/systemd/system/katmate-app-routed@<instance>.service.d/90-gate.conf`
  with `[Service]`, an empty `ExecStart=`, and then the installed unit's
  `ExecStart=` copied verbatim with only the `-append` line changed. Run
  `daemon-reload`. Show the `diff` of the two `ExecStart=` blocks as
  `systemctl cat` prints them (exactly one line on each side), and
  `systemctl show -p ExecStart`'s count (1). Run the variant. Then remove
  the file and its directory, run `daemon-reload`, and run `reset-failed`
  only if the unit failed. Never under `/etc` (R9). Ruled 2026-09-29
  (R92); s4-gates used it four times (G1−, G2−, G2+, G5−). Source:
  `s4-gates-report.md` (the scaffolding table, and each variant's install
  and removal).
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
- **`pgrep -f` on a bare daemon name matches any command line containing it.**
  Added 2026-09-27, from `r8-impl-B-report.md` (Phase 4, and § 6's proposed
  entry). The build's host-dnsmasq watcher read `pgrep -af dnsmasq` exit 0,
  with `44245 systemctl enable dnsmasq`: the build's own `systemctl` in the
  chroot, not a daemon. `/proc/*/comm == dnsmasq` read 0 at the same probe.
  **So `pgrep -f <name>` is not a daemon check; the `comm` count is the
  reading that decides.** The entry above recommends `pgrep -f` for QEMU,
  where the argv is long and specific; for a short daemon name it can fire
  on anything that mentions the name.
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
  **Extended 2026-09-26:** `networkctl status` is inert too (*"Failed to
  connect to system bus"*, `rc=1`), and **networkd without `resolved` puts the
  DHCP DNS only in its private lease file**, `/run/systemd/netif/leases/<n>`,
  headed *"Do not parse"* (`net-m1-report.md` § 9.3). ADR-037's gate G3
  applies this rule to dhcpcd.
  **[Note 2026-09-27 (ADR-037 image; ruling V1): the daemon is still
  absent,** with `dbus` `un`, no `dbus-daemon` and no `/run/dbus`, and G3
  passed with dhcpcd running without a bus. **The image now carries the
  library `libdbus-1-3 1.16.2-2`**, which dnsmasq-base depends on. It is
  accepted as a library with no bus, and the build refuses `enable-dbus`.
  "`dbus`-free" in this entry means daemon-free.**]**
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
- **`-e` on a symlink inside a mounted image resolves on the build host when
  the link is absolute.** `-e` follows the link, and outside the chroot an
  absolute target such as `/usr/lib/systemd/system/…` is the build host's
  path. The check then passes or fails on the host's files, not the
  image's. **Test an image entry with `-L || -f`.** Found 2026-09-30 in the
  first form of R115's read-back of
  `sysinit.target.wants/systemd-modules-load.service`. Source:
  `s4c-a-report.md` W10.
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
- **Map an LV to its `dm-N` from the `/dev/<vg>/<lv>` symlink, not by parsing
  `dmsetup info`.** Its `Major, minor: 254, 8` line is easy to parse into the
  **major**: an `awk -F'[:,]' … print $3` did exactly that on 2026-09-27
  (`adr037-impl-B`, 14:45:35). The scripted `jbd2` precondition before the
  `lvremove` then searched for `jbd2/dm-254-*`, a guard that **could not
  fire**, and it printed `dm node: dm-254`. The precondition held in fact, and
  that is known only because the full `jbd2` thread listing was printed beside
  the verdict (`jbd2/dm-2-8` and `jbd2/nvme0n1p2-8`, no `dm-8`; the symlink
  said `../dm-8`). Read `ls -l /dev/<vg>/<lv>` for the number, and print the
  raw listing next to any verdict drawn from it.
- **A transient `systemd-run` unit without `User=` has no `HOME`, and
  `build/config.sh` under `set -u` dies on it.** Measured 2026-09-27
  (`adr037-impl-B`): the build wrapper, run as `km-netvm-build`, logged
  `HOME before: '<unset>'`. `config.sh:41` expands `$HOME`, and `netvm.sh` runs
  with `set -u`. The wrapper exports `HOME=/root` (what `sudo` would give)
  before it calls `netvm.sh`. A build started in the ruled launch form (§ *Live
  state*, *Dev access to MINIS*) needs that export.
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

- **netVM's `input` chain has no ICMPv6 accept rule, and that absence is
  load-bearing (ADR-037 R22, 2026-09-27).** `input` is `policy drop` with no
  `icmpv6` rule, so it drops every inbound ICMPv6, **router advertisements
  arriving on the slots included**. That is what keeps netVM from taking an RA
  from an AppVM while `accept_ra=1` is set on `default` (net-up § 19.3 item 5).
  It is the netVM-receiving direction of open problem #24, which `accept_ra`
  does not cover until arc step 4. **A ruleset rewrite that adds an `icmpv6`
  accept opens #24 silently.** Any such rule needs #24 settled first. The
  source is `adr037-readpass-report.md` Q-R2d, read from the ruleset text; no
  RA was sent to test it.

- **netVM build mirror: pick by VPN exit, not by home geography.** MINIS's
  ProtonVPN exit is in CH; use `DEBIAN_MIRROR=http://ftp.ch.debian.org/debian`
  (via `sudo bash -c 'DEBIAN_MIRROR=... bash netvm.sh'` — `sudo` env_reset drops
  a bare `VAR=... sudo` prefix). An SI mirror over a CH tunnel is worse, and the
  Ljubljana `deb.debian.org` fastly timeout does not apply from a CH exit.
  **[Note 2026-09-27 (rp D14): the host `proton` link this entry presumes is
  dev scaffolding** (the operator's gap-3 ruling of 2026-09-27; SECURITY-MODEL
  gap 3). The product host carries no VPN. **The mirror choice follows whatever
  the host's egress is.** The CH mirror is right only while MINIS exits
  through CH. The 2026-09-27 build used it.**]**

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
  **[Note 2026-09-27 (ADR-037 R3, R10, R12): this entry is reversed for the
  uplink at the ADR-037 rebuild.** The uplink will be named `uplink0` by
  `60-katmate-uplink.link` matched on `Path=pci-0000:00:04.0`, with
  `addr=0x4` pinned in the unit. Its name becomes load-bearing, because
  dhcpcd's `allowinterfaces` and the ruleset's `oifname` use it, and
  `20-uplink.network` is retired. **Until that rebuild lands, this entry still
  describes the tree and the running image.** The internal-segment half is
  not affected by R3.**]**
  **[Note 2026-09-27, `adr037-impl-B`: the condition is met, and the rebuild
  has landed.** The uplink is `uplink0` by `Path=`
  (`ID_NET_LINK_FILE=…/60-katmate-uplink.link`, G2), and `20-uplink.network`
  is gone from the image. For the uplink, this entry is now historical. **The
  internal-segment half stands:** the sixteen slot `.link` files match by
  MAC, 16 slots on 16 distinct files (G2).**]**

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
  **Note 2026-09-26:** `vm_tpl_foundation` was observed **active without the
  `k` flag** on two boots (`Vri-a-tz--`; `appweb-m1-report.md` § 2 item 8,
  `appweb-m1-rerun-report.md` § RA item 8). Neither session read what had
  activated it. Newly built LVs also stay active after their build (#37). So
  "inactive with `k`" is not a state that can be assumed on MINIS. Read
  `lv_attr` first.
  **Note 2026-09-27 — one candidate ruled out, one remains.**
  `/etc/systemd/system/vm-lvs.service` is **ruled out by reading** (hcb P1). It
  was `disabled` and did not run this boot: empty `ExecMainStartTimestamp`, no
  journal entries. Its `ExecStart=` lines name only `vg0/vm_personal_rw` and
  `vg0/vm_personal_home`, which no longer exist. It was deleted the same day.
  **Remaining candidate: LVM event autoactivation** of a `vm_tpl_foundation`
  that carries no `k` flag. That LV reads `Vri-a-tz--` and its dm node dates
  from boot (10:30). **This is UNMEASURED.** It is settled at a boot by the
  journal (`journalctl -b` for `lvm-activate-*` / `pvscan` entries naming
  `vg0`) together with LVM's activation records for that LV.

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
  `7.2.5-hardened1-1-hardened`, NOT a 6.12.y microvm kernel.**
  `~/src/kernel/linux-6.12.y/` (and any 6.12.94 tree) is the GUEST microvm
  kernel source, unrelated to the host. Do not build host modules against it
  (vermagic mismatch) and do not reason about host USB/driver behaviour from
  6.12.y. The custom `6.12.87`/`6.12.94` kernels are `-kernel` payloads for
  guests only. **Corrected 2026-08-28:** this entry read `7.0.12-arch1-1` until
  then; `uname -r` on MINIS reports `7.1.9-hardened1-1-hardened` *(chat-only —
  read on MINIS 2026-08-28, no report file)*. The machine has moved to a
  **hardened** kernel, which the entry did not anticipate, so a host-side
  measurement taken before that date may not reproduce.

  **Corrected again 2026-09-20:** this entry read `7.1.9-hardened1-1-hardened`
  from 2026-08-28 until then; `uname -r` on MINIS reports
  **`7.2.5-hardened1-1-hardened`** (`auditfix-liveread-report.md` §§ 2.0, 5.2),
  the kernel having moved with the `pacman -Syu` that preceded the reboot of
  **2026-09-19**. The previous two values are left visible deliberately: this
  entry exists to stop a host-side measurement being reasoned about under the
  wrong kernel, and **the warning above now covers every host-side measurement
  taken between 2026-08-28 and 2026-09-19** — the whole of the ADR-035 gate arc.
  **No rollback is proposed and none is wanted**; the update is ordinary
  maintenance on a rolling distribution.

  **Corrected again 2026-09-26:** this entry read `7.2.5-hardened1-1-hardened`
  from 2026-09-20 until then. The running kernel on MINIS is now
  **`7.2.7-hardened1-1-hardened`**, booted 2026-09-25 14:00:27
  (`appweb-m1-rerun-report.md` §§ RA, RB.1). In between, `linux-hardened`
  7.2.6 was installed on 2026-09-19 20:49 and never ran; see the next entry for
  what that did to the running 7.2.5. The stock `linux 7.2.6.arch2-1` is also
  installed (§ RA, A12). The previous values are left visible for the reason
  given above.

- **An Arch kernel upgrade without a reboot removes the running kernel's
  `/usr/lib/modules` tree** (measured 2026-09-25). Until the next reboot, no
  module that is not already loaded can load: `modinfo` answers *"Module …
  not found"* and `modprobe` fails, whatever is authorised
  (`appweb-m1-report.md` § 3.1). **Related: `overlay` is `=m` and nothing
  autoloads it on MINIS.** A guard for overlayfs must test **availability** —
  `modinfo -n overlay` resolving under `/usr/lib/modules/$(uname -r)` — and not
  loaded state (`lsmod`, `/proc/filesystems`). The loaded-state form cannot
  tell "absent" from "not yet loaded", and on a fresh boot it halts every time
  (`appweb-m1-rerun-report.md` § R5.4 W1).

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
- **A `connect()` probe on a root-owned socket node must run as root.** Run
  unprivileged, it gets `EACCES`, which says nothing about whether anything
  is bound there. In s4c-b's B6 the stale-node guard probed slot 01's
  `appvm` as `host`, got `EACCES`, and refused, correctly. Re-run as root,
  the probe answered `ECONNREFUSED` (nothing bound), and only then was the
  node unlinked. Same family as *"a check that cannot fire"*. Observed
  2026-09-30. Source: `s4c-b-report.md` § B6, § 4 item 7.
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
  **Answered 2026-09-26:** no uid-1000 user exists in netVM (`getent passwd
  1000` rc 2), and **the mode is `0755`, not `0644`** — *"mode 0644"* above is
  wrong for `nftables.conf` (`1000:1000 755`). The ownership also covers
  `20-uplink.network` and all sixteen slot `.link` files (`net-up-report.md`
  § 19.3 item 10, `net-m1-report.md` § 10.7). Open problem #38.
  **[Note 2026-09-27: fixed in the image.** `cp -a --no-preserve=ownership`
  plus a read-back (`6827583`, C1): the build printed *"34 conf-tree paths …
  all owned 0:0"*, and in the guest `nftables.conf` is `0:0 644`. **The `0755`
  was the git mode**, and it is now 0644 (`a209ebf`, C2, R23). #38 is
  closed.**]**

- **In a netVM build chroot, dnsmasq's postinst starts nothing on the host.**
  Measured 2026-09-27 (`adr037-impl-B`, build log lines 840–842): *"Setting
  up dnsmasq (2.91-1+deb13u2) ... / Running in chroot, ignoring request."*,
  and no `dnsmasq` process on MINIS at either watcher probe (`pgrep -af` and
  `/proc/*/comm`, after apt and at build exit). **The mechanism predicted in
  advance was wrong:** `adr037-impl-A` § 6.1 expected *"could not determine
  current runlevel"*, and that line appears nowhere in the log. Which program
  prints *"Running in chroot"* is **not established** by the log. A package
  that could start a daemon on the build host is checked by watching the host,
  not by predicting the maintainer script.

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
- **After a bare newline, the answer to newline *n* is read after newline
  *n+1*.** A bare newline flushes only the line *before* the prompt it
  provokes; the prompt itself carries no trailing newline and stays unflushed
  until the next write. On 2026-09-26 newline #1 returned only `^M^M`, and the
  `localhost login:` it caused appeared after newline #2 (`net-up-report.md`
  § 17.2). **Once a shell is expected, the reliable check is an evaluated
  probe:** `echo KM-SHELL-$((6*7))` → `KM-SHELL-42`. The echoed input carries
  `$((6*7))`, not `42`, so only a shell that evaluated it produces the line;
  a login prompt and a shell echo the same bytes (net-up §§ 19.1, 22 item 6).
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

  **Instance, 2026-09-20 — and this one did leave a trace, because the machine
  disagreed on the first probe.** The `auditfix-liveread` brief asserted
  *"`MainPID 3628111`, `NRestarts=0` since 2026-09-12 09:59:37 CEST"* as fact in
  its § 3, and carried it again as a premise in §§ 4.1, 4.2 and 4.8 — four
  sections resting on one unchecked sentence. **That process had died six days
  earlier**, at 2026-09-19 02:26:54, when the host rebooted; nobody had
  contacted MINIS since 2026-09-14, so the assertion was stale and had never
  been checked against the machine. **Every *"is"* sentence in that brief should
  have been a *"read and report"* sentence** — had they been, the session would
  have produced the same halt with no wasted premise. Source:
  `auditfix-liveread-report.md` § 5.1.

  **The cheapest guard against this whole class is one command.** A brief's halt
  list is better led by **"the host has rebooted since the last recorded
  session"** — `uptime -s` on MINIS against the boot date recorded in § *Live
  state* — because that single fact implies every apparatus condition beneath
  it: no process, no slot tree, no console, no `/tmp` instrument, no neighbour
  table. The five-condition halt list the liveread brief carried was written as
  five ways a *reading* can be blocked, and what occurred was categorically
  larger than any of them. Source: `auditfix-liveread-report.md` § 5.5.

  **Instance, 2026-09-20, turned outward — the same rule with a document in
  place of the machine.** The `auditfix-liveread` report's § 2.6 wrote, in
  quotation marks, that `state.md` records *"whether the rename fires in the
  running guest has never been measured"*. **`grep -F` finds that sentence in
  neither `state.md` nor `docs/DECISIONS.md`.** The **substance was right** —
  nothing in the tree had claimed the rename was observed firing — **but the
  quotation marks were the report's own paraphrase**, and a later session
  searching for the sentence would have concluded the document was wrong rather
  than the report. A claim about what a document says is measured by reading the
  document; the bullet below on claims about repository documents is the same
  rule stated from the other end. Source: `b1-docwrite-report.md` § 5.4.
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

- **`apt-cache rdepends` does not label relation types.** In its unlabelled
  form it lists Breaks, Replaces and Conflicts together with Depends. The
  unlabelled `dbus` rdepends looks like 8 reverse dependencies, and all 8 are
  Breaks/Replaces. Use `-o APT::Cache::ShowDependencyType=true`.
  `--installed` on a **virtual** package prints only `<name>`, which is a
  well-formed empty answer and measures nothing (`appweb-m2-report.md` § 11 W3,
  W4; the same shape as `libgtk-3-0` → `libgtk-3-0t64` in
  `appweb-m1-rerun-report.md` § S5.4 W2). Source: 2026-09-25.
