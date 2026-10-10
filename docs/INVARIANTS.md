# Invariants & gotchas (quick reminders — detail in git/ADRs)
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
  sound?".** The entry above and the one under [*Next steps*](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md) describe this
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
  map. Numbers in [SESSIONS.md](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/docs/SESSIONS.md) are pre-ADR-022 and are not rewritten.

- **`amd_iommu=on` is a DEAD cmdline param** (kernel prints `AMD-Vi: Unknown
  option` and ignores it). IOMMU actually runs via `iommu=pt` + IVHD/IVRS. The
  MINIS cmdline still carries the dead `amd_iommu=on`; harmless, clean up
  someday. IOMMU group 12 (RTL8125) is clean/isolated — passthrough-safe.
  **[Note 2026-10-04 (ADR-040): *"IOMMU actually runs via `iommu=pt` +
  IVHD/IVRS"* is superseded as practice.** The AMD IOMMU is on by default,
  driven by the IVRS table. `iommu=pt` only put every host device into a
  passthrough DMA domain (*"Default domain type: Passthrough (set via kernel
  command line)"*, the operator's `pf-minis.txt:52`). ADR-040 forbids
  `iommu=pt`, and `amd_iommu=on` too, so *"harmless, clean up someday"* is now
  a requirement. **Both are removed from MINIS's persistent command line:
  done 2026-10-04 by the operator, and observed.** The source is
  `/etc/kernel/cmdline`, applied with `mkinitcpio -P` (HOST-CONFIG §15).
  After the reboot:

  ```
  /proc/cmdline: pti=on page_alloc.shuffle=1 root=/dev/vg0/root rw
    cryptdevice=UUID=…:cryptroot quiet splash
  [    1.538555] iommu: Default domain type: Translated
  ```

  and no *"AMD-Vi: Unknown option"* line. `pti=on page_alloc.shuffle=1` is
  not in that file. It is `linux-hardened`'s built-in command line
  (`CONFIG_CMDLINE_BOOL=y`, `CONFIG_CMDLINE="pti=on page_alloc.shuffle=1"`,
  `/proc/config.gz` on `7.2.8-hardened1-1-hardened`), prepended at boot.
  The text above is left as written.**]**

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
