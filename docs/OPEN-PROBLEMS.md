# Open problems

The problems still open on 2026-10-10, each under its original number and
in its original text. Numbers are never reused. Closed problems are not
carried here: the full list, closed problems included, is in `state.md` at
[`v0.2.0-alpha2`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md).

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
   split lands — it is in [§ *Next steps*](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md) as *Launch daemon / privilege split*,
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
   by [ADR-037](adr/ADR-037.md), not decided there.
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
   direction** by [ADR-038](adr/ADR-038.md): AppVMs are
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
   [ADR-035](adr/ADR-035.md) §5 it reaches an **`AF_UNIX` socket
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

30. **The host kernel's required-symbol set is recorded nowhere, and the host
   ran outside ADR-004 for an interval no artefact recorded.** Added 2026-09-18,
   from [ADR-036](adr/ADR-036.md) § 7 and § *Gates* G4. **Read from
   the tree only** — nothing was run on MINIS and no kernel config was read on
   either machine.

   The host kernel is load-bearing **by configuration**, and no artefact carries
   the set of symbols the project depends on. `grep -F` over this file returns
   nothing for `vsock_diag` and nothing for `config.gz`; `TMPFS_POSIX_ACL`
   occurs once (`state.md:68`), as a fact about `/run` inside a session entry,
   not as a recorded dependency. The symbols the accepted ADRs have already made
   load-bearing, each named by the ADR that needs it:

   - `vsock_diag` — [ADR-026](adr/ADR-026.md) E4/E6, a *stated
     requirement*. ADR-026 writes its own warning: a future host kernel
     configuration change that drops it silently disables the indicator's
     identity path.
   - the vsock namespace symbols — [ADR-028](adr/ADR-028.md) C6 and
     ADR-029 G0/G1, which together fix a host kernel floor of Linux ≥ 7.0.
   - `TMPFS_POSIX_ACL` — the ADR-035 revision note of 2026-09-15.
   - KVM, VFIO and the IOMMU driver — every netVM boot.
   - whatever the boot-hardening backlog adds.

   **The consequence has already been measured once, and was noticed by
   accident.** The reference host reported `7.0.12-arch1-1` — a stock Arch
   kernel, **not** `linux-hardened` — when ADR-028/029's netns gates were taken
   on 2026-08-02, and `7.1.9-hardened1-1-hardened` on 2026-08-28. For at least
   part of that interval the machine [ADR-004](adr/ADR-004.md)
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
   [ADR-036](adr/ADR-036.md) § 2 and § *Revisit when* 8, which makes
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
   file — [ADR-019](adr/ADR-019.md), the document that *names* the
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
   [ADR-036](adr/ADR-036.md) § *Open, and named as open rather than
   decided*. **Nothing was run** — this entry records the absence of a
   measurement, not its result.

   [ADR-026](adr/ADR-026.md) names two carriers for the domain
   indicator: the bar module and the focused border colour. Both are values a
   user theme can set. No measurement on either machine shows that a
   user-supplied theme cannot reach them, and `grep -F 'theming'` over this file
   returns nothing.

   The question stands independently of ADR-036's status: ADR-026's carriers are
   **accepted**, and if a theme can repaint either of them then the identity path
   is user-modifiable today. What ADR-036 adds is only the rule that the answer
   be **measured** rather than assumed.

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

52. **The AppVM kernel starts `netconsole`, and where it sends is unread.**
   Added 2026-09-28, from s4-m0 (`s4-m0-report.md` § 6 item 6, outside the
   repository). Every boot of step 4.0 printed *"printk: legacy console
   [netcon0] enabled"* and *"netconsole: network logging started"* on the
   microVM kernel `b34026dd…`. Its targets, and whether any kernel message
   left the guest over the slot, were not read. It belongs with the kernel
   config and #22: the config that would say how `netconsole` is built and
   configured is not proven to be the image's.

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
   **[2026-10-06: the bound is now `MAX_PAYLOAD`, 64 KiB, which replaced
   `MAX_FILE_SIZE` when FILEGET/FILEPUT were retired, so the allocation
   above is at most 64 KiB. The open question, rejecting before the body,
   is unchanged. Line numbers above are stale.]**

57. **`katmate-update` maps an instance delta to its app type by the
   name's suffix.** Added 2026-10-03 (operator ruling R149; found by ai4,
   ai4-report § 5 item 6; read in the tree by ai5, not run).
   `build/katmate-update.sh:160–161` and `:193–195` take the type as the
   last `_` segment of the delta's name (`type="${base##*_}"`), and
   `:164` dies on a type outside `APP_TYPES`. Of the four deltas,
   `app_web` → `web` and `app_vault` → `vault` map right by coincidence of
   name. `app_personal` → `personal` and `app_work` → `work` are unknown,
   so **the first such delta aborts the whole update**, before anything is
   rebuilt. (ai4's entry, now in [`docs/SESSIONS.md`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/docs/SESSIONS.md), also lists `app_vault`
   as refused. The code maps it.) The instance's T1 `manifest` key, or
   the delta's own backing file, would name the type. Which one the
   updater should read is the open question. It is not fixed here.
   **[2026-10-06: `app_sandbox` adds a fifth delta that maps wrong:
   `app_sandbox` → `sandbox`, which is not in `APP_TYPES`
   (`build/katmate-update.sh:64`), and the preflight at `:159–165` dies on
   it, as it does on `app_personal` and `app_work`. Read in the tree, not
   run. Line numbers above are as of `799a79b`.]**

58. **`tools/validate-properties.fish` has no CID uniqueness rule.**
   Added 2026-10-06 (cloud session, app_sandbox; operator ruling the same
   day). Shown on the six T1 templates, copied as `tools/make-release.sh`
   copies them: with `app_sandbox.toml`'s `cid` set to `22`, the same as
   `app_personal.toml`, `--strict` read *"skupaj: 0 napak, 0 opozoril"*
   (0 errors, 0 warnings), exit 0. The control was `cid = 5`, which it
   refused with exit 1 (*"cid=5 je v sysVM pasu 3–19"*, cid=5 is in the
   sysVM band). Run under fish 3.7.0 in the cloud container, not on the
   Acer. The cross-file rules run, *"pravila čez datoteke: ovrednotena nad
   6 datotekami"* (cross-file rules evaluated over 6 files), and uniqueness
   is not one of them. So nothing refuses two T1 files carrying one CID,
   neither the validator nor the generator (`docs/PARAMETERS.md`, row
   *CID*: *"None for uniqueness"*). The alpha's CIDs (3, 21–25) are unique
   by reading. **Planned post-alpha.**
