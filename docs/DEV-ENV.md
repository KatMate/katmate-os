# Live state (MINIS/UM870) — summary

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
  [`docs/SESSIONS.md`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/docs/SESSIONS.md) in this commit.

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

  **HOST CONFIGURATION AFTER THE INSTALLER MERGE (2026-10-05, `49a172d`).**
  The blocks above are left as published. This block supersedes their
  hugepage lines and the installed-set statement. **The operator's
  statement, relayed to a cloud session; not read on MINIS by any session
  yet:**
  - **Hugepages:** `/etc/sysctl.d/hugepages.conf` (`vm.nr_hugepages = 6144`)
    is **removed**. Since `49a172d` both AppVM templates use
    `memory-backend-memfd,share=on` and no unit names `/dev/hugepages`
    (HOST-CONFIG §6, its note of this date). Until the next boot the 6144
    pages stay reserved unless they were released by hand; that was not
    stated. **UNVERIFIED until the MINIS gate:** all four AppVMs launch on
    memfd with `HugePages_Total` = 0.
  - **topoext:** the drop-in
    `/etc/systemd/system/katmate-sys-driver@.service.d/10-cpu.conf`
    (`[Service]` / `Environment=KM_CPU_FLAGS=,topoext=on`) is **added by
    hand**, so netVM keeps `-cpu host,topoext=on` under the template's new
    `-cpu host${KM_CPU_FLAGS}`. On a fresh install the installer writes the
    same file on AMD hosts. Its effect on the running netVM needs a
    `daemon-reload` and a netVM restart; whether either was done was not
    stated.
  - **Installed host set:** `host/usr/` **re-synced at `49a172d`**: the
    units (memfd AppVM templates, sys-driver with `KM_CPU_FLAGS`) and
    `/usr/lib/katmate/`. The hash-first check (*Invariants*) against
    `49a172d` is the next session's first action, and no count of matching
    files is recorded here because none was quoted.
  - **Not changed by the merge on MINIS:** the netVM image carries no
    unbooted marker (`build/netvm.sh` step 9b is newer than it) and has been
    booted, so `tools/make-release.sh` refuses it; the first release needs
    a fresh netVM build that is not booted before the export. The deltas
    stay `host:host`, the T1 files stay hand-installed, and `vm_app_web_home`
    stays linear; the installer's forms apply to fresh installs only.

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
