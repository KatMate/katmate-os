# Invariants & gotchas (quick reminders — detail in git/ADRs)

Condensed 2026-10-10; the full text before this pass is at
<https://github.com/KatMate/katmate-os/blob/a92b3ef/docs/INVARIANTS.md>.
Report files cited as sources (`*-report.md`) are outside the repository.
Recurring family: **a check that cannot fire is indistinguishable from a check
that found nothing** — make the condition true on purpose and see it noticed.

- **The guest serial console is durable in the host journal.** The VM unit
  binds the serial line to stdio with `StandardOutput=journal`, so guest boot
  output outlives the guest and a host reboot. It is an observation path and an
  unrated guest→host write (SECURITY-MODEL gap 15). **Trap:** records embed ANSI
  escapes between words (`Finished \x1b[0;1;39msystemd-sysctl…`), so `grep`
  misses present text; anchor on escape-free text. Source:
  `auditfix-liveread-report.md` §§ 2.3, 2.6, 4.3.
- **Kernel `ip=` with netmask `255.255.255.255` is replaced by a guess** (*"Guessing
  netmask 255.0.0.0"*) and the gateway kept; a `/32` is not expressible there.
  `255.255.255.0` is taken as given. Observed once on `b34026dd…`. Source:
  `s4-m0-report.md`, boot A.
- **TTL tells forwarded from originated**, with a LAN host's packet as control:
  NATed guest SYNs carried ttl 63 against the Acer's 64. Needs `tcpdump -v`.
  Source: s4-m0 `cap-B`/`cap-C`, `wp-0928d-brief.md`.
- **`vm-agent` RUN opens the window on MINIS's screen, and firefox restores its
  last session from `/home`**, so traffic can start ~1 s after RUN. Procedures
  must say where the window appears and account for the restore. The
  `waypipe-client` user journal logs no connections, so it cannot attribute a
  window. Source: `s4-m0-report.md` §§ 3, 8.
- **Announce a step that opens a window on MINIS, and RUN only after the
  operator confirms he is at MINIS's screen** — *"ready"* is not that. Ask where
  he is. Source: `s4c-b-report.md` § B6, § 4 item 9.
- **`nft -c` unprivileged cannot fire; run any `nft -c` preflight as root.** It
  exits 1 on every input (*"cache initialization failed: Operation not
  permitted"*), valid or not. As root, good and broken files give 0 and 1.
  Source: `auditfix-liveread-report.md` § 2.5.
- **The unprivileged `nft -c` message differs by site.** MINIS: *"cache
  initialization failed"*; Acer: *"Could not process rule: Operation not
  permitted"* at `flush ruleset`. A search for one misses the other. Source:
  `f12-impl-A-report.md` §§ 2, 6.
- **The Acer has no site for an `nft -c` check:** `unshare -rn` is refused on its
  hardened kernel. A ruleset written on the Acer is **UNVERIFIED** until `nft -c`
  as root on MINIS (build preflight) or in the guest. Source:
  `f12-impl-A-report.md` §§ 2, 5, 6.
- **R48's extraction strips `#` to end of line**, so a `#` inside an nft comment
  in an extracted chain (`build/netvm.sh`) cuts the rule. Such comments carry no
  `#`; quote-aware stripping was rejected. Source: `s4c-a-report.md` W11.
- **A packet sourced from the receiver's own address is dropped as a martian
  before any nft hook**, so a counter for that source never fires (netVM:
  `in_martian_src` +5, the R50 counter +0). Test a rule with a source the kernel
  lets through. Source: `f12-impl-B-report.md`.
- **`chmod` after `setfacl` rewrites the ACL mask** and can make every named
  entry ineffective. Order: mode, then ACL, then `getfacl` read-back; only the
  `#effective:` comment shows an entry works.
- **A code path run only in its convenient (unprivileged) mode is untested in
  the one that matters.** `sudo` resets `HOME`, `PATH` and the environment, so
  `${VAR:-$HOME/...}` resolves differently as root (#25). Measure environment
  derived values in both modes: `sudo -n bash -c 'source <config>; echo "$VAR"'`.
- **A refusal list is an execution order:** a check behind a refusal is
  untested until that refusal is relaxed, and relaxing one exposes downstream
  code as new (`tools/capture-kernel-provenance`, 2026-09-01).
- **A dev-console drop-in in `/etc` outlives its tmpfs FIFO and makes the unit
  fail with `208/STDIN`, above `ExecStart=`.** No `ExecStartPre=` runs, and the
  journal names neither path nor drop-in. Same class as `EnvironmentFile=`
  without `-`: a directive that opens a file does so before the preflight can
  speak. Ruled R1 (`/etc` drop-ins removed, `StandardInput=null`) and R9
  (per-session drop-ins only under `/run/systemd/system/<unit>.d/`); settled
  after the 2026-09-27 boot. Sources: `auditfix-liveread-report.md`,
  `net-up-report.md` §§ 14–15, `pool-fold-report.md` §§ 2.1, 2.6.
- **Read the netVM console with `journalctl -o cat`.** The default format shows
  records with non-printable bytes as `[NNNB blob data]`, hiding `Password:`.
  Absence of a prompt in the default format is not evidence. Read the output,
  never the echo.
- **FIFO login takes two writes, ≥3 s apart.** A single write of username and
  password loses the password and reads like a wrong password after ~62 s. Gate
  on *"last `localhost login:` older than 65 s"*, not on the banner. Why the
  single write fails is unmeasured. Type the password before the first write.
- **A command form in a brief is untested code, and can be well-formed and
  wrong:** `ip -o link | awk '{print $2, $(NF-2)}'` returns the broadcast
  address; `pgrep -a qemu-system-x86_64` cannot match. Measure, or ask.
- **The dev console procedure.** Two writes into
  `/run/katmate-dev/netvm-console.in`, ≥3 s apart, within `agetty`'s 60 s; read
  back with `journalctl -o cat`; send a bare newline first — a login prompt takes
  the credential, a shell must not. Close with `exit` through the FIFO. The
  holder, verbatim as root (`netvm-rebuild-3-report.md:267–272`):

  ```
  mkdir -m 0755 -p /run/katmate-dev
  chown root:root /run/katmate-dev
  mkfifo -m 0600 /run/katmate-dev/netvm-console.in
  chown root:root /run/katmate-dev/netvm-console.in
  systemd-run --unit=km-console-holder --description='KatMate dev console FIFO writer-holder (dev scaffolding, transient)' \
    /usr/bin/bash -c 'exec 3>/run/katmate-dev/netvm-console.in; sleep infinity'
  ```

  Before the unit starts the holder is `comm=bash` with no fd 3 (correct); after
  the rendezvous it is `comm=sleep` with fd 3 `l-wx`. The drop-in is a saved copy
  installed unedited under `/run/systemd/system/<unit>.d/90-dev-monitor.conf`
  (R9; `~/katmate-dev/removed-0926/…`, `b44de3a9…`); its comments are stale.
- **On the netVM serial console a pager eats the rest of a command file.**
  Command files set `SYSTEMD_PAGER=cat` and pass `--no-pager`. Source:
  `r8-impl-B-report.md`.
- **`katmate-sys-driver@netvm` and `katmate-pool@netvm` must never run at
  once.** Moot since 2026-09-27: the pool is folded into
  `katmate-sys-driver@.service` and `katmate-pool@netvm` is `not-found` (R1;
  `pool-fold-report.md` § 2.5).
- **QEMU `unlink()`s its `netvm` nodes before `bind()` but not at exit**, so a
  restart with stale nodes succeeds; there is no `EADDRINUSE` (the earlier claim
  was wrong; ADR-035's 2026-09-12 note, finding 7). A refused start has already
  bound all its backends. Source: `g5b-restart-report.md`.
- **`ExecStopPost=` unlinks the sixteen `netvm` nodes to close a hijack window**
  between stop and start (an unheld node can be bound by anyone with write
  access); a pre-start sweep is too late. In the tree since `1597445` (R74);
  executed at netVM's stop of 2026-09-30 (16 → 0, by inference; ADR-035's note
  of 2026-09-30).
- **`Type=simple` returns at QEMU's fork, before the netdevs bind**: read slot
  bindings after the guest answers PING (0/16 straight after `start`, 16/16 26 s
  later). Source: `pool-fold-report.md` §§ 2.6, 2.7.
- **After a clean stop, `systemctl show` on a template instance returns
  defaults** (`Result=success`, `ExecMainStatus=0`, `pid=0`); the journal is the
  record: *"Deactivated successfully."* with no *"Main process exited"*. A failed
  unit is not collected. Source: `s4a-impl-B-report.md` §§ 5.1, 6.
- **systemd names unset variables an `Exec*` line expanded empty** (*"Referenced
  but unset environment variable …: KM_NETVM, KM_SLOT"*). Its absence does not
  prove the projection was read; systemd does not print the argv. Source:
  `s4a-impl-B-report.md` §§ P4, P8, 6.
- **`vm-agent` answers PING ~4–5 s after `systemctl start`.** Poll every 2 s up
  to 30 s; early `113` (*No route to host*) and `19` (*No such device*) are not
  faults. OK on try 3 in every run so far. Sources: `s4a-impl-B`,
  `s4b-impl-B`, `s4b2-impl-B`, `s4-gates` reports.
- **iproute2 7.2.0 ends route lines with a space**; compare trimmed
  (`init/tests/run.sh`'s verdict failed on it). Source: `s4b-impl-B-report.md`
  § P1.
- **`sit0` exists in the AppVM under `ipv6.disable=1`** (`CONFIG_IPV6_SIT`).
  Don't count links by *"not loopback"*; katmate-init counts device-backed
  links (R85). Source: `s4b-impl-B-report.md` § P8.
- **Read a guest-written file by mounting the home LV read-only after the guest
  is down:** `vg0/vm_app_web_home` with `-o ro,noload`, copy, unmount. Never
  while the guest holds it. Source: `s4b-impl-B-report.md` § P8.
- **The foundation build log can reach ~200 MB of apt `W:` lines** (1.8 M
  identical gcc-14 warnings, exit 0) when host IPv6 is not held off. Count by
  pattern (`grep -c '^W:'`), never page it. Source: `s4b-impl-B-report.md` § P3.
- **Image builds need host IPv6 off.** The pref-100 `unreachable` rule is
  permanent since R97 (installed by `proton.conf`'s `PostUp`); a build checks
  that `ip -6 rule list` shows `100: from all unreachable` and stops otherwise
  — it neither adds nor removes it (R98, superseding R93). With the rule,
  `make foundation` took 5 min against 61 min. Source: `s4b2-impl-B-report.md`.
- **`wg-quick down` runs the config file's current hooks**, so a `PreDown`
  added to a running tunnel must tolerate what `PostUp` never made:
  `ip -6 rule del pref 100 || true` (R97).
- **`wg-quick@proton` is the one owner of the `proton` tunnel.** Bring a
  hand-made tunnel down with `wg-quick down proton` before `systemctl start`;
  `restart` of an inactive unit fails on the existing interface (R97).
- **A gate's altered `-append` is a per-session drop-in**
  `/run/systemd/system/katmate-app-routed@<instance>.service.d/90-gate.conf`:
  empty `ExecStart=`, then the installed one with only `-append` changed;
  show the one-line `diff` and `ExecStart` count 1; remove after,
  `daemon-reload`. Never under `/etc` (R9). Ruled R92. Source:
  `s4-gates-report.md`.
- **`RuntimeDirectoryPreserve=yes` is load-bearing:** across a netVM restart the
  peer's `appvm` inode, bound socket and fd were unchanged. Sources:
  `g5b-restart-report.md`, `adr035-g5a-report.md`.
- **`pgrep -x qemu-system-x86_64` never matches** (`comm` is capped at 15
  characters; the name is 18). Use `pgrep -f` or read `/proc/*/comm`. Sources:
  `g2-refusal-g6-report.md`, `g3-g4-console-report.md`.
- **`pgrep -f` on a short daemon name matches any command line containing it**
  (`systemctl enable dnsmasq` in the build chroot). For daemons, the `comm`
  count decides. Source: `r8-impl-B-report.md`.
- **A guard placed as a separate step is not a guard.** It gets skipped; put it
  inside the thing it guards.
- **`grep -F` on a phrase that wraps across a line is a false negative.** Splice
  the file before concluding absence (same class as `$` in a BRE).
- **Vocabulary: abstract in ADR prose, machine names beside measurements.**
  Concrete machine detail belongs in `docs/INVARIANTS.md` and `docs/DEV-ENV.md`,
  not in an ADR (*"the build machine"*); a site named beside a measurement is
  provenance (ADR-033's *"(2026-08-24, MINIS)"*, ADR-034). Ruled 2026-09-01.
- **`systemctl start` on an active `RemainAfterExit=yes` oneshot is a silent
  no-op;** re-run `katmate-publish-nics` with `restart`. A stale label still
  cannot reach a VM: gate G6 refuses it at `katmate-generate-env`.
- **Hash the installed set first in every gate session** (`/usr/lib/katmate/*`
  and the units against the tree); mtime is no substitute, rsync preserves it.
  Source: `3a2-g6h1-report.md` § 3.1.
- **netVM is `dbus`-daemon-free, so bus-dependent mechanisms are inert:**
  `logind`, `resolved`, `networkctl` (incl. `status`), `polkit`, non-root
  `systemctl` fail at the bus. This killed ADR-021's shutdown (ADR-024 E1) and
  ADR-025's Path A. **An ADR whose mechanism talks over the system bus gates it
  empirically before acceptance** (cf. ADR-023 → ADR-025). networkd without
  `resolved` keeps DHCP DNS only in its private lease file. The image carries
  the library `libdbus-1-3` (for dnsmasq-base) and refuses `enable-dbus`
  (ADR-037, ruling V1).
- **netVM initrd needs `MODULES=most`, not `dep`:** `dep` resolves against the
  build root and omits `virtio_blk`, so the guest finds no `/dev/vda`. General
  trap for any image whose build root differs from its runtime root.
- **Seed image config files with `install -D`, not a bare redirect;** a missing
  parent dir aborts the build mid-write (→ stuck jbd2). `bash -n` build scripts
  after editing.
- **`-e` on an absolute symlink inside a mounted image resolves on the build
  host.** Test image entries with `-L || -f`. Source: `s4c-a-report.md` W10
  (R115).
- **Mask suspend before a netVM build:** `systemctl mask sleep.target
  suspend.target hibernate.target hybrid-sleep.target`; unmask after. Disabling
  hypridle is not enough.
- **`netvm.sh` unmounts before `sync`** (`netvm_umount`: umount → `sync` →
  `udevadm settle`, surfacing failure, unlike `lib.sh:umount_root`). What to do
  about a hot jbd2 is the next entry.
- **The stuck-`jbd2` test answers "may I `lvremove`?", not "is the image
  sound?".** `Open count` 0 (`dmsetup info`) and no `[jbd2/dm-N-8]` kthread →
  safe; else reboot, never force. `mount`, `lsof`, `fuser` cannot see it. Every
  `build/netvm.sh` run, successful or not, leaves the hold, so **reboot before
  each build**; its preflight (`build/netvm.sh:122`) suggests `lvremove -f`.
  Source: `netvm-rebuild-3-report.md` § 13.
- **Map an LV to `dm-N` from `ls -l /dev/<vg>/<lv>`, not by parsing `dmsetup
  info`** (an `awk` read the major, 254, and the guard could not fire). Print the
  raw listing beside any verdict.
- **A transient `systemd-run` unit without `User=` has no `HOME`;**
  `build/config.sh` under `set -u` dies on it. The build wrapper exports
  `HOME=/root`, required for the build launch form in `docs/DEV-ENV.md`.
- **netVM root is deliberately unlockable in dev** for console observation
  (open problems #11, #12): only when the build is handed a hash (`23e4268`).
  Release blocker beside the dev sshd (#4). Host-side checks (ARP scan) stay
  preferred.
- **Verify the netVM uplink by ARP scan, not ping;** netVM drops inbound ICMP.
  `nmap -sn 10.3.1.0/24` shows uplink MAC `38:05:25:34:7c:47`.
- **netVM's `input` chain has no ICMPv6 accept, and that is load-bearing**
  (ADR-037 R22): it drops RAs from the slots while `accept_ra=1`. Adding one
  opens #24 silently. Not tested by sending an RA.
- **netVM build mirror follows the host's egress:**
  `DEBIAN_MIRROR=http://ftp.ch.debian.org/debian` while MINIS exits through CH
  (pass it inside `sudo bash -c '…'`; `env_reset` drops a prefix). The `proton`
  link is dev scaffolding (SECURITY-MODEL gap 3).
- **netVM needs `firmware-realtek` for the RTL8125** (`rtl_nic/rtl8125b-2.fw`),
  in the manifest (`build/netvm.sh`), or the PHY stays down.
- **netVM interface identity: the uplink by PCI path, the slots by MAC.** Since
  the ADR-037 rebuild the uplink is `uplink0` by `60-katmate-uplink.link` on
  `Path=pci-0000:00:04.0` with `addr=0x4` pinned (R3, R10, R12); the name is
  load-bearing (dhcpcd, `oifname`) and `20-uplink.network` is gone. The sixteen
  slot `.link` files match by derived MAC (ADR-025; internal MAC was
  `52:54:00:21:b2:08`; `net-sys.con` still carries an authored one).
- **A netinst netVM writes stale installer configs;** the hand-installed netVM
  drifts, which is why it is a declarative build (ADR-021).
- **Thin-LV activation:** an RO-frozen thin LV keeps the `k` flag;
  `lvchange -K -ay` before every instance boot, app layer and foundation, as
  `app_web.con` did. On MINIS `vm_tpl_foundation` has been seen active without
  `k`, and built LVs stay active (#37): read `lv_attr` first. Candidate cause,
  unmeasured: LVM event autoactivation.
- **vfio pins the entire guest RAM, so memlock must be lifted:**
  `LimitMEMLOCK=infinity` in `katmate-sys-driver@.service`; a manual
  `sudo bash net-sys.con` needs `ulimit -l unlimited`, or QEMU dies at
  `VFIO_MAP_DMA` with a false *"cannot allocate memory"*.
- **RTL8125 reports `FLReset-`:** teardown leaves it half-initialised and the
  next `VFIO_MAP_DMA` fails ENOMEM. Workaround in `/etc/modprobe.d/vfio.conf`:
  `options vfio-pci ids=10ec:8125 disable_idle_d3=1` and `softdep r8169 pre:
  vfio-pci`; proven across a guest reboot.
- **`/dev/vfio/<group>` is root-only by default;** non-root QEMU needs a `vfio`
  group, udev `SUBSYSTEM=="vfio", GROUP="vfio", MODE="0660"`, and membership.
- **USB-NIC (r8152) churn is dev-only;** in production devices do not migrate,
  and NIC passthrough is a provision-time job.
- **`driver=[none]` after a clean enumeration → check `/etc/udev/rules.d/` and
  `modprobe.d` first**, not the kernel (the culprit was our own
  `30-usb-nic-qemu.rules`).
- **`r8152-cfgselector` is built into `r8152.ko`,** cannot be blacklisted, and
  is not the problem.
- **Do not blacklist `cdc_ether`/`r8153_ecm`** for the RTL8153; it only removes
  the ECM fallback.
- **USB fallback NIC: a native SuperSpeed port, not a USB4/TB hub** (`error
  -71` there).
- **MINIS runs a hardened Arch host kernel**, not 6.12.y.
  `~/src/kernel/linux-6.12.y/` is the guest microVM source: never build host
  modules against it or reason about host drivers from it. The host kernel moves
  with `pacman -Syu`, and a host-side measurement is tied to the kernel it ran
  under: `7.0.12-arch1-1` (stock) read 2026-08-02; `7.1.9-hardened` read
  2026-08-28 and running through the ADR-035 gate arc to 2026-09-19; `7.2.5`
  from that reboot; `7.2.7` booted 2026-09-25; `7.2.8` by 2026-10-02
  (`docs/DEV-ENV.md`).
- **An Arch kernel upgrade without a reboot removes the running kernel's
  `/usr/lib/modules` tree;** unloaded modules cannot load. `overlay` is `=m` and
  not autoloaded: test availability (`modinfo -n overlay`), not loaded state.
  Sources: `appweb-m1-report.md` § 3.1, `appweb-m1-rerun-report.md` § R5.4.
- **Check a config's header line before reading symbols from it** (line 3:
  `# Linux/x86 6.12.87 Kernel Configuration`); a `.config` in a tree need not
  belong to its last build.
- **Root device has no partition table:** `root=/dev/vda`, not `vda1`.
- **Serial console:** microvm + `-nographic` needs `-serial mon:stdio`
  explicitly.
- **Shutdown without ACPI:** init calls `reboot(RB_AUTOBOOT)`; needs QEMU
  `-no-reboot` and `reboot=t`.
- **Agent PATH:** `PATH=/usr/local/bin:/usr/bin:/bin`; waypipe is the
  source-built `/usr/local/bin/waypipe`.
- **GUI launch:** GTK apps refuse root; use uid 1000 with `XDG_RUNTIME_DIR`.
  waypipe ≥0.11 resolves the host CID itself.
- **VSOCK ports:** 1025 vm-agent control, 1024 waypipe GUI, 1026 audio
  (planned).
- **CID map is range-based (ADR-022):** `2` host · `3–19` sysVM · `20–99` fixed
  AppVM · `≥100` disposable. CIDs in the archived
  [SESSIONS.md](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/docs/SESSIONS.md)
  predate it.
- **`iommu=pt` and `amd_iommu=on` are forbidden (ADR-040)**; the AMD IOMMU is on
  by default from IVRS, and `amd_iommu=on` is an unknown option. Removed from
  MINIS's `/etc/kernel/cmdline` (2026-10-04, `mkinitcpio -P`, HOST-CONFIG § 15);
  now `Default domain type: Translated`. `pti=on page_alloc.shuffle=1` is
  `linux-hardened`'s built-in command line.
- **`foundation.meta` (ADR-019)** at `/var/lib/katmate/foundation.meta`, flat
  `KEY=value`. Launch preflight compares host `waypipe --version` with
  `WAYPIPE_TAG` (config.sh's `WAYPIPE_VERSION`) and refuses on mismatch.
- **Re-bake invalidates deltas:** `qemu-img create -f qcow2 -F raw -b
  /dev/vg0/vm_app_web <delta> 10G`; *"write lock"* means a QEMU still holds it
  (never kill netVM, CID 3).
- **The custom microvm kernel is monolithic**, passed via `-kernel` (no initrd,
  no `/lib/modules`), as an external vmlinuz.
- **Never rsync a kernel build tree with broad `--exclude`:**
  `--exclude='vmlinux.*'` eats `vmlinux.lds.S`. Use `git clone`/`git archive`
  plus `.config`; interrupted builds leave truncated `.o` files.
- **Kernel builds run on MINIS** (`-j16`); the Acer N4200 thermally shuts down.
  Source at `~/src/kernel/linux-6.12.y/` on both.
- **foundation build gotchas:** pseudo-fs mount after debootstrap; ext4 label
  ≤16 chars; no `useradd`/`passwd` in minbase; `$(HOME)` under `sudo` is
  `/root`, so the Makefile hardcodes `/home/host/katmate-kernels`.
- **Naming:** ADRs say `foundation`/`app`/`instance`; LVM names
  (`vm_tpl_foundation`, `vm_app_web`) only here and in live inspection.
- **Source of truth is the Acer `~/katmate-os/`;** MINIS `~/katmate-build/` is
  the build copy itself (not `~/katmate-build/katmate-os/`), synced with
  `--delete`, never edited (`net-sys.con` reads
  `/home/host/katmate-build/out/netvm/`). A stale documented layout is a stale
  BDF.
- **`git rm`, never `rm`, on a tracked tree;** check `git ls-files`, not `find`
  (`agent/crates` was already tracked during the workspace split).
- **Two-stage gate for a refactor:** new client against the old artefact
  (proves the wire), then the new artefact (proves the agent).
- **A parsing harness needs behavioural proof too.** link-m3's harness was wrong
  three times (`printf` field split, process CPU conflating vCPU and loop,
  `comm` `CPU 0/KVM` with a space), each a confident wrong number. Run one
  throwaway repetition and add a reconciliation line that must hold (process
  `utime` includes guest time, so the vCPU row is a floor).
- **`systemd-run --unit` `active` is not proof of work:** the holder's `comm`
  (`bash` vs `sleep`) and fd 3 on the FIFO show the rendezvous.
- **`ss -xl` is not a path check;** it prints the path recorded in the socket.
  `ls -i` answers the path, `/proc/<pid>/fd` the binding.
- **A `connect()` probe on a root-owned socket node runs as root;**
  unprivileged it gets `EACCES`, meaning nothing. Source: `s4c-b-report.md`
  § B6.
- **After a push, `origin/main` is not server confirmation;** ask the server
  with `git ls-remote origin refs/heads/main`.
- **`systemctl show` hides `StandardInput=file:<path>`** (bare
  `StandardInput=file`); verify by the drop-in and by the unit starting.
- **`cp -a` in `netvm.sh` step 5 baked uid 1000 ownership into the image;**
  fixed with `--no-preserve=ownership` and a read-back (`6827583`); the git mode
  of `nftables.conf` is now 0644 (`a209ebf`, R23). #38 closed.
- **In a netVM build chroot, dnsmasq's postinst starts nothing on the host**
  (*"Running in chroot, ignoring request."*). Check by watching the host, not by
  predicting the maintainer script.
- **A negative inside a natural expiry window is not a measurement** (conntrack
  empty 39 s after the last flow). Time reads inside the window (ADR-035's
  2026-09-12 note, finding 2). Source: `g3-g4-console-report.md` § 5.3.
- **A console guard must require a prompt newer than its own probe.** Source:
  `g3-g4-console-report.md`.
- **A guard watches the echo, not the prompt:** `Password:` and `localhost
  login:` carry no newline and never flush; send a bare newline and key on the
  echoed input. Source: `g3-g4-console-report.md`.
- **After a bare newline, the answer to newline *n* appears after newline
  *n+1*.** Once a shell is expected, probe with `echo KM-SHELL-$((6*7))` →
  `KM-SHELL-42`. Source: `net-up-report.md` §§ 17.2, 19.1.
- **A quotation that wraps is not a search string.** On a `grep -F` miss of
  quoted tree text, read the line range; quote unwrappable fragments. Source:
  `adr035-writepass-a-report.md`.
- **The clock is evidence.** The fixtures' `PEER: seq=` line carries no
  timestamp; adding one before the next measuring session is required and not
  done. Source: `g2-add-report.md`.
- **A never-non-zero counter rising measures first traffic, not restoration**
  (ADR-035's 2026-09-12 note, finding 8).
- **Do not assert machine state from memory;** a brief says *read and report*.
  A brief asserting a MainPID six days dead put four sections on one stale
  sentence. Lead halt lists with `uptime -s` against the last recorded boot.
  The same holds for documents: a claimed quotation of `state.md` (then) was
  absent from it and from `docs/DECISIONS.md`. Sources:
  `auditfix-liveread-report.md` §§ 5.1, 5.5; `b1-docwrite-report.md` § 5.4.
- **A comparison reports its cardinality beside its verdict:** a missed escape
  dropped one key and the diff said IDENTICAL over 60 keys instead of 61.
  Source: `mcast-read-report.md` § 8.
- **A claim about what a document says is verified by reading the section;** a
  grep for your own phrasing is a null control (ADR-035 stated the
  *"QEMU-to-QEMU"* fact in other words). Source: `writec-report.md` § 5.3.
- **`apt-cache rdepends` does not label relation types;** use
  `-o APT::Cache::ShowDependencyType=true`. `--installed` on a virtual package
  prints only `<name>`. Sources: `appweb-m2-report.md` § 11,
  `appweb-m1-rerun-report.md` § S5.4.
