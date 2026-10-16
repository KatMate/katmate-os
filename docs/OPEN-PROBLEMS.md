# Open problems

Condensed 2026-10-10; the full text before this pass is at
<https://github.com/KatMate/katmate-os/blob/a92b3ef/docs/OPEN-PROBLEMS.md>.
Numbers are never reused. Closed problems are not carried here: the full list,
closed problems included, is in `state.md` at
[`v0.2.0-alpha2`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/state.md).
Report files cited by name (`*-report.md`, `pf-*.txt`) are outside the
repository.

2. **hyprlock-after-suspend (host).** After host suspend, tty1 Hyprland locks
   and will not unlock. A host DE issue, not KatMate, but it blocks visual
   inspection of guest render. Closes with its own pass.

4. **SSH open on MINIS host** (dev convenience; SECURITY-MODEL gap 4). Fix
   identified, not applied: restrict to the LAN on the host uplink, the USB-NIC
   `enp195s0f3u1u1` (`enp1s0` is gone, the RTL8125 is in vfio):
   `iif <uplink> ip saddr 10.3.1.0/24`, or `ListenAddress 10.3.1.3`, so sshd
   is not reachable through the ProtonVPN tunnel. Removed before release.

5. **ext4 lazy-init warning on vda.** `EXT4-fs error (vda) ... bad block bitmap
   checksum` from `ext4lazyinit` at boot. Cosmetic on a disposable delta;
   `vm_app_web` may want a clean `e2fsck`.

8. **VPN key co-located with the NIC driver (v1, accepted).** In the v1 graph
   the WireGuard private key and `r8169` + the non-free Realtek blob share one
   address space. [ADR-022](adr/ADR-022.md) already permits the fix (driver domain q35 =
   hardware, no secrets; proxy netVM microvm = secrets, no hardware);
   deliberately post-v1. SECURITY-MODEL gap 7.

9. **IOMMU-group quality is unverified at install time.** A bad grouping
   silently weakens passthrough isolation; MINIS's clean group 12 is luck.
   SECURITY-MODEL gap 9. The preflight half exists (`installer/preflight.sh`)
   and ran on two machines (2026-10-04; `pf-cubi.txt`, `pf-minis.txt`):
   - **MSI Cubi N6000** (live ISO, `7.2.2-arch1-1`, booted with
     `intel_iommu=on`; no run without it): DMAR IR enabled in x2apic mode;
     `CONFIG_INTEL_IOMMU_DEFAULT_ON` unset; default domain Translated.
     RTL8111 (`10ec:8168`) alone in group 17, CNVi Wi-Fi alone in group 6,
     xHCI shares group 5 with the Shared SRAM.
   - **MINIS** (`7.2.8-hardened`): AMD-Vi IR enabled, `amd_iommu=on` an
     unknown option, default domain Passthrough from `iommu=pt` (since removed,
     [ADR-040](adr/ADR-040.md)). RTL8125 alone in group 12, on `vfio-pci`.
   - **Both** Realtek NICs report the same PCIe DSN `01-00-00-00-68-4c-e0-00`;
     a fact bearing on [ADR-030](adr/ADR-030.md) §5's descriptor question, nothing concluded.

   **Open:** the HCL half.

11. **Dev-root open.** Since `23e4268`, netVM root is locked unless a build is
   handed `KATMATE_DEV_ROOT_HASH`; `netvm.meta` records
   `NETVM_ROOT_UNLOCKED=yes|no`, and no credential is in the repository. **Open:**
   the image on MINIS is a dev build with root unlocked, so not release-clean.
   Closes with a release build without the variable. The image has no sshd
   (`manifests/netvm.list`); the sshd half is #4, on the host.

12. **No structured in-guest observation path in netVM.** The `usermod -p`
   line is gone (`23e4268`), so the original debt is discharged. **Open:**
   `netvm-agent` has no RUN opcode or equivalent, so in-guest checks cost the
   dev console (a FIFO on the VM's stdin; scaffolding on the removal list).
   The cost was shown at [ADR-027](adr/ADR-027.md)'s C5b gate (2026-07-28), settled host-side
   instead; [ADR-025](adr/ADR-025.md)'s live gate relied on the console. Closes with a
   structured observation path in `netvm-agent`. Removed with the dev sshd (#4).

14. **`netvm.sh` does not fully verify agent binary freshness.** The `die` half
   is implemented (`06ab509`, R120), **UNVERIFIED** until the next netVM
   build: the preflight dies on a missing binary or one older than any file of
   `agent/crates/netvm-agent/`, `agent/crates/katmate-protocol/` or
   `agent/Cargo.lock`. **Open:** a `sha256sum` of the binary in
   `/var/lib/katmate/netvm/netvm.meta`; R120 does not ask for it.

17. **C-gate remainder — netVM VMM privilege (C1, C2, C3, C5a).** QEMU runs as
   root, without chroot or Landlock, in `init_netns` (written against
   `net-sys.con` under `sudo`). C4 and C5b passed 2026-07-28. **Blocks all
   axis-2 work** ([ADR-027](adr/ADR-027.md)). Re-scoped by [ADR-029](adr/ADR-029.md): C1, C3, C5a are unit
   directives (`User=`, `LimitMEMLOCK=infinity`, a `setpriv`-style Landlock
   wrapper in `ExecStart=`; Landlock is inherited across `execve`, no QEMU
   patch), privileged preparation in `ExecStartPre=+`, cleanup in
   `ExecStopPost=+` (runs as uid 0 after `SIGKILL`). C2 is under review:
   `app_web.con` carries no network device, and netVM's tap can be
   pre-created `user <uid>`. C1 must also retire the blanket udev rule (#43,
   gap 16). SECURITY-MODEL gap 11.

18. **vsock CID space is global on the host (C6).** Any host process can reach
   any VM's agent on port 1025. Fix: per-VM netns with `child_ns_mode=local`
   (Linux ≥ 7.0). Measured ([ADR-029](adr/ADR-029.md) G0/G1): `child_ns_mode` is write-once and
   `ns_mode` immutable, so this is a one-time preparation on a dedicated
   `katmate-root` namespace, not a daemon-start decision as [ADR-028](adr/ADR-028.md) states;
   `init_netns` is never written. `ip netns add` does not nest, so the daemon
   creates namespaces itself (`setns` → `unshare` → bind-mount) and hands the
   named result to the unit via `NetworkNamespacePath=`. Per-netns sysctls
   need `/proc` remounted, or the old namespace's value is read. **Open:** how
   the daemon reaches every VM (`setns` on demand vs per-namespace sockets).
   With CID reuse the domain indicator's identity becomes (netns, CID), so C6
   and [ADR-026](adr/ADR-026.md) are revisited together. SECURITY-MODEL gap 12; mechanism in
   ADR-028.

21. **Every stop is a hard termination; the clean path is not wired.** The
   clean path exists: `netvm-agent`'s SHUTDOWN `0x05` signals PID 1 with
   `SIGRTMIN+4` under `CAP_KILL` ([ADR-024](adr/ADR-024.md)), dbus-free. Missing:
   `katmate-sys-driver@.service` has no `ExecStop=` invoking it, so `stop` is
   SIGTERM to QEMU. Measured once: the next boot replayed the ext4 journal;
   the initrd carries no `fsck`, so the filesystem is never checked, and that
   stays true after wiring (a `TimeoutStopSec` miss falls back to SIGTERM).
   **Order:** (a) gate PING and SHUTDOWN from the host, (b) add `ExecStop=`,
   (c) re-measure the stop path; wiring first would repeat the failure that
   killed [ADR-021](adr/ADR-021.md)'s QMP→ACPI→logind shutdown and [ADR-025](adr/ADR-025.md)'s Path A. Also: the
   stop deactivates no LV (disposable AppVMs will need it); the measurement was
   taken with QEMU as root and is retaken after the `User=` split ([ADR-027](adr/ADR-027.md)
   C1/C3/C5a). An init refusal ([ADR-038](adr/ADR-038.md) §9) is expected to end inactive like a
   clean stop; `systemctl show` reads defaults after a clean stop, and the
   journal shape (*"Deactivated successfully"*, no *"Main process exited"*) is
   the record; an init refusal's shape is not observed.

22. **Kernel provenance is unverifiable for the existing images.**
   `~/katmate-kernels/` holds different bytes under one filename: Acer
   `a7581389…` (`6.12.87`), MINIS `b34026dd…` (`6.12.87-dirty`), the one every
   AppVM boots (`app_web.con:29`). `CONFIG_IKCONFIG` is unset in both configs;
   `extract-ikconfig` on the MINIS image gave `Cannot find kernel config.`
   (not re-tested since). Setting `IKCONFIG` is rejected: it widens what a
   guest can read.
   - **MINIS:** the chain exists through the build tree (`bzImage` identical;
     `include/config/auto.conf` matches the archived config `7720cf22…`,
     1718/1718; chat-only, 2026-08-28) and is captured in a sidecar beside the
     image (`bfed14af…`, `AUTOCONF_MATCH=yes`, `SRC_DIRTY_PATHS`). `-dirty` is
     ten deleted `vmlinux*` files (mips, nios2, openrisc, parisc, sh, a perf
     bpf skeleton, a bpf selftest), none built for x86, no patch; `.gitignore`
     does not explain them, and they are consistent with, not attributed to,
     the `--exclude='vmlinux.*'` gotcha in `CLAUDE.md`. A `-dirty` banner is
     one bit; neither form carries a commit SHA.
   - **Acer:** broken; `auto.conf` was overwritten 47 days after the link
     (`.config.old` `4e30950b…` is post-build), so no sidecar, deliberately.
   - **Mechanism ([ADR-034](adr/ADR-034.md), accepted):** `tools/capture-kernel-provenance`
     (`5b1f16c3…`); `kernel_provenance_check()` in `build/lib.sh`, run in
     `build/foundation.sh`'s preflight; `KERNEL_PROVENANCE` in
     `foundation.meta` (step 10); the sidecar installed at step 11
     (`build/foundation.sh:268–274`; `build/netvm.sh:345–347` writes the same
     way) and copied by `Makefile:44–47`. Steps 10–11 executed 2026-09-26.
     The sidecar is not sourceable; readers parse `^KEY=` as `meta_get()` in
     `build/app-layer.sh:101` does.
   - **Open:** nothing reads or checks the sidecar at install or launch;
     ADR-034 § A.3's presence check is blocked by #25. Closes when the
     pipeline carries and checks the record. A release-blocker candidate: a
     filename asserting an identity that does not hold (cf. [ADR-032](adr/ADR-032.md)'s
     2026-08-22 note).
   - Side facts: a config is not environment-independent
     (`CONFIG_PAHOLE_VERSION` differed in a spare copy, `499a53a2…`, deleted
     2026-09-27, as was the stray `linux-6.12.94` tree, #42). The MINIS config
     header reads 6.12.87 with `IP_PNP`, `IPV6`, `VIRTIO_NET` =y, consistent
     with boots ([ADR-035](adr/ADR-035.md)'s note of 2026-09-28). `netconsole` is #52.


24. **IPv6 router solicitations from AppVM guests; RAs from netVM.** An answering
   RA would give an AppVM SLAAC addressing outside NETCFG, the only source
   ([ADR-023](adr/ADR-023.md), [ADR-025](adr/ADR-025.md)). **AppVM half closed:** [ADR-038](adr/ADR-038.md) (R77) makes AppVMs
   IPv4-only via `ipv6.disable=1` (R66, R76), observed in G1 (R89). R49 is no
   witness for RS (R76; [ADR-035](adr/ADR-035.md)'s note of 2026-09-28). **Open:** whether netVM
   sends RAs on internal links is unread; netVM's `accept_ra=1` stands; *no RA
   from netVM* is not taken (carried by [ADR-037](adr/ADR-037.md)).

25. **`KERNEL_SRC_DIR` derives from `$HOME` and resolves under `/root`.**
   `build/config.sh:33` defaults to `$HOME/katmate-kernels`; both scripts that
   read it run as root, giving `/root/katmate-kernels`, which does not exist.
   `build/katmate-update.sh:114` dies there with a wrong cause (`:115`) and
   `:121` logs the wrong path; `build/foundation.sh:52,53,132` prints it in
   diagnostics only; `Makefile:23,45,47` hardcodes the right path and is
   unaffected. Fails safe (dies before any mutation). Blocks [ADR-034](adr/ADR-034.md) § A.3's
   presence check (pointer in `ROADMAP.md`). Not fixed.

26. **`katmate-update.sh` refuses an instance delta of unknown app type.** The
   triggering `scratch.qcow2` is deleted (2026-09-27); **open:** any delta whose
   suffix is not in `APP_TYPES` still makes `--dry-run` fatal (see #57).
   `scratch_home.img` remains (#42).

28. **No bound on an instance name's length.** `km_check_instance`
   (`host/usr/lib/katmate/katmate-lib.sh:67`, `^[a-z][a-z0-9_]*$`) is the only
   check `katmate-generate-env:48` applies; `tools/validate-properties.fish`
   never reads the name. Under [ADR-035](adr/ADR-035.md) §5 the name reaches
   `/run/katmate/link/<netvm>/<kk>/netvm`, and `sun_path` is 108 bytes: fixed
   part 27, so the netVM name bound is **80** (81 without the NUL). A longer
   name fails at `bind()`, silently ([ADR-033](adr/ADR-033.md)). ADR-035 §5 says *"roughly
   seventy"*; the discrepancy awaits the operator. Where the bound goes is a
   decision; none was added.

30. **The host kernel's required-symbol set is recorded nowhere.** Load-bearing
   symbols: `vsock_diag` ([ADR-026](adr/ADR-026.md) E4/E6), the vsock namespace symbols ([ADR-028](adr/ADR-028.md)
   C6, [ADR-029](adr/ADR-029.md) G0/G1; Linux ≥ 7.0), `TMPFS_POSIX_ACL` ([ADR-035](adr/ADR-035.md)'s note of
   2026-09-15), KVM/VFIO/IOMMU, and whatever boot hardening adds. The host
   ran stock `7.0.12-arch1-1`, outside [ADR-004](adr/ADR-004.md)'s `linux-hardened`, for an
   unrecorded interval (2026-08-02 gates). **Sub-question closed:**
   `/proc/config.gz` is readable at runtime on the host ([ADR-040](adr/ADR-040.md)'s note,
   `7.2.8-hardened`); the open part is that the set is still recorded
   nowhere. `state.md` (alpha2) `:68`, `:1118`, `:1269` are the old citations; #22's `extract-ikconfig` result is the guest image. Distinct
   from #22. From [ADR-036](adr/ADR-036.md) § 7, G4.

31. **The GUI ingress is not in version control.** [ADR-036](adr/ADR-036.md) § 2 makes locating
   it a precondition. On 2026-09-18 `git ls-files` found two units
   (`host/usr/lib/systemd/system/katmate-publish-nics.service`,
   `host/usr/lib/systemd/system/katmate-sys-driver@.service`), neither the
   listener; `waypipe-client` occurred only in [ADR-019](adr/ADR-019.md) (then in
   `docs/DECISIONS.md`). Located 2026-09-26: the unit files exist only on
   MINIS, in `~/.config/systemd/user/`, untracked; `docs/HOST-CONFIG.md` § 11
   now carries the requirement. **Open:** tracking the unit, and ADR-036's
   placement of it (PROPOSED).

32. **Whether user theming reaches the domain-indicator carriers is unmeasured.**
   [ADR-026](adr/ADR-026.md)'s two carriers (bar module, focused border colour) are both
   theme-settable values, and nothing shows a user theme cannot reach them; if
   one can, the identity path is user-modifiable today. [ADR-036](adr/ADR-036.md) asks for a
   measurement. Nothing was run.

35. **Foundation dependency debt.** The foundation carries `systemd`,
   `systemd-sysv`, `dbus`, `dbus-daemon` (none PID 1, none requested; kept by
   `systemd-sysv`'s `Protected: yes` and GTK3 → dconf → `dbus-user-session` →
   `libpam-systemd` → `systemd-sysv`), and the perl stack, `netbase`,
   `libgdbm*` (candidate cause: the waypipe build-dependency purge).
   Candidate fixes, unmeasured: `dbus-x11`, or an equivs package providing
   `default-dbus-session-bus`; the measurement is the shelved
   `appweb-m3-brief.md`. Deferred past the alpha. Sources:
   `appweb-m2-report.md` § 7.3, `appweb-rebuild-report.md` §§ 5.2, 8.

36. **The divert's claim and its test.** `dpkg -S /usr/sbin/init` still lists
   `systemd-sysv` beside the diversion, so `build/foundation.sh:183`'s *"no
   longer owns"* is imprecise. Settling test, unrun: reinstall `systemd-sysv`
   in a throwaway overlay; `/usr/sbin/init` must stay katmate-init. The
   read-back guard (`5d32dd0`) is observed only in its passing arm.

37. **Built LVs remain active after `make foundation` / `make app-web`.**
   `lv_deactivate` (`build/lib.sh`) runs `lvchange -an … 2>/dev/null || true`
   and swallows failure. Open count 0, so not a hold. Why they stay active is
   unmeasured.

43. **A blanket udev rule gives uid 1000 read-write under every thin LV.**
   `/etc/udev/rules.d/99-vm-lvm.rules` on MINIS (untracked) makes every
   `vg0/vm_*` device `host:host 0660`, the thin pool's `_tdata`/`_tmeta`
   included. Likely consumer `app_web.con` (inferred). Kept by operator
   ruling; the fix belongs to C1 (#17): per-LV DAC in `ExecStartPre=+`.
   SECURITY-MODEL gap 16. On MINIS `host` is also in `disk`, which reaches the
   whole disk regardless of the rule (gap 16's note of 2026-10-14; #63).

44. **Nothing checks that the unit's `addr=` and the image's uplink `Path=`
   agree.** `addr=0x4` in `katmate-sys-driver@.service` and
   `Path=pci-0000:00:04.0` in `60-katmate-uplink.link` (`netvm.meta`
   `UPLINK_PCI_ADDR`, R13) are one constant on two update tracks. A mismatch
   is predicted to fail closed (no `uplink0`, no dhcpcd R14, no egress),
   caught by G2 ([ADR-037](adr/ADR-037.md)). Both agree today, read by hand. **Open:** an
   automated preflight.

46. **Parts of networking arc step 3 have not run as installed.** Written and
   **UNVERIFIED**: the builder's `trap` cleanup and stale-file sweep; the
   directory-level refusals (`<instance>.d/` group-writable, non-root,
   symlink, non-directory; unknown or missing key; leading-zero octet), run
   only in extracted copies; every failure path of the guest consumer on a real
   image. Settled by running them against the installed builder on MINIS, or a
   malformed image at a test boot. Source: `r8-impl-B` § 6.

47. **The `katmate-lib.sh` header is stale.** `:7` speaks of *"three of the four
   executables"*; six source it (`katmate-check-waypipe`,
   `katmate-check-image`, `katmate-build-cfgdisk`, `katmate-generate-env`,
   `katmate-activate-lvs`, `katmate-publish-nics`). A comment-only fix, its own
   commit.

48. **netVM forwarding with a failed ruleset — the fail-closed half.**
   `ip_forward` is now set by `katmate-ip-forward.service` (`Requires=`/
   `After=nftables.service`; R111; `9010130`), and the build refuses a sysctl
   file that sets IPv4 forwarding. The normal-boot half is observed (R118).
   R52's preflight (`56b3c96`) checks against the build host's kernel, not
   netVM's (R110). **Open:** on a boot with `nftables.service` failed,
   `katmate-ip-forward` does not run and `ip_forward` reads `0`.

50. **The failure paths of R52's preflight and R48's read-back have not run on a
   real image.** Both ran on pass paths only; failure paths **UNVERIFIED**.
   Settled on a build with a broken ruleset (R52) or a broken pair (R48): a
   `die` quoting nft's output or naming the slot, then the trap's `lvremove`.
   Source: `f12-impl-B-report.md` § 6.

52. **The AppVM kernel starts `netconsole`, and where it sends is unread.**
   Every step-4.0 boot of `b34026dd…` printed *"netconsole: network logging
   started"*. Targets, and whether anything left the guest over the slot, were
   not read. Belongs with #22. Source: `s4-m0-report.md` § 6.

55. **An AppVM reaches the host's own LAN address (development configuration
   only).** The product host has no NIC of its own. On MINIS the dev NIC
   `10.3.1.3` shares the LAN with netVM's uplink ([ADR-037](adr/ADR-037.md) G5; R99). The host's
   `inet filter input` accepts ICMP and TCP 22 (sshd, #4) and rejects or drops
   the rest (`wp-0929e`'s P-check). **Open, undecided:** a host drop for netVM's
   uplink address, or a netVM `forward` drop for segment → host LAN address.

56. **The shared decoder reads the body before rejecting an unhandled opcode.**
   [ADR-039](adr/ADR-039.md) specified validating the command in the fixed header first; since
   the workspace split ([ADR-021](adr/ADR-021.md)) `read_request`
   (`agent/crates/katmate-protocol/src/frame.rs:215`) reads the opcode unmapped
   and each binary maps it afterwards. Cost: a read and allocation up to
   `MAX_PAYLOAD` (64 KiB) before ERR. The peer is the host (TCB; see #18).
   **Open:** whether to reject before the body again (R145; ADR-039's note of
   2026-10-03). Line numbers are stale since `2a9e638`.

57. **`katmate-update` maps an instance delta to its app type by the name's
   suffix.** `build/katmate-update.sh:160–161`, `:193–195`
   (`type="${base##*_}"`); `:164` dies outside `APP_TYPES` (`:64`). `app_web`
   and `app_vault` map by coincidence; `app_personal`, `app_work` and
   `app_sandbox` abort the whole update before anything is rebuilt. Lines as of
   `799a79b`. **Open:** read the type from the T1 `manifest` key or the delta's
   backing file (R149). ai4's entry is in the archived
   [`docs/SESSIONS.md`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/docs/SESSIONS.md).

58. **`tools/validate-properties.fish` has no CID uniqueness rule.** Two T1
   files with one `cid` (22) pass `--strict` with 0 errors; `cid = 5` is
   refused (sysVM band). Neither the validator nor the generator checks
   uniqueness (`docs/PARAMETERS.md`, row *CID*). Shown on the six templates as
   `tools/make-release.sh` copies them, fish 3.7.0, cloud container. The
   alpha's CIDs (3, 21–25) are unique by reading. Planned post-alpha.

59. **Why the Windows guest rebooted itself overnight in w2 is not known.**
   Windows ended the RAIL session at 00:11:07 (report time, zone not
   stated), *"initiated by an administrative tool on the server"*, and
   rebooted at 00:12:49Z (2026-10-15);
   the host saw nothing (no `-no-reboot`). Hypotheses, neither observed:
   Windows Update's automatic restart; RTC skew for the System events that
   are missing. The prepared event read `ev2.ps1` (outside the repository)
   was not run and is UNVERIFIED. **Open:** run it read-only at the next
   Windows boot. Product items 9–13 of [ADR-041](adr/ADR-041.md) depend on
   the answer. Source: `w2-report.md` S3.33, S3.36, S3.39.

60. **katmate-init cannot express a link-only address.** `km.ip`, `km.gw`
   and `km.dns` are all three or none (`init/katmate-init.c:13–15`, `:346`)
   and always install an on-link default route via `km.gw` and a resolver.
   On a link whose peer is not a router (the RDP gateway's 1:1 link to its
   Windows guest, [ADR-041](adr/ADR-041.md)) the default route and
   `resolv.conf` point at the peer. Accepted for the w2 spike. **Open:** an
   address-only form. Source: `w2-report.md` H1 D5.

61. **A failed deactivation after a layer build is silent.**
   `build/lib.sh:70–74` `lv_deactivate` runs `lvchange -an … 2>/dev/null ||
   true`. After both w2 gateway layer builds the LV still showed the `o`
   (open) flag right after the build; later reads were not open. **Open:**
   report the failure (it is the jbd2 class of INVARIANTS). Source:
   `w2-report.md` S2.6, S3.23.

62. **Why `lvcreate` of a thin snapshot of a thin origin probed
   `dm-snapshot`.** Observed on 2026-10-14 (module tree absent after a kernel
   upgrade, INVARIANTS); a thin snapshot should need `dm-thin-pool` only. Not
   investigated. Source: `w2-report.md` S2.3, H2.

63. **The installer does not refuse a desktop user in the `disk` group.**
   Membership in `disk` gives write access to the LUKS mapping, the host root
   LV and the raw NVMe device (SECURITY-MODEL gap 16, note of 2026-10-14).
   `installer/postinstall.sh:28` creates the user with `-G wheel` only, so a
   fresh install is not affected today; nothing checks it.
   **Open:** a check that refuses ([ADR-041](adr/ADR-041.md) item 3).

64. **No product unit sets `panic=`, so a guest that panics at boot leaves its
   QEMU and unit running indefinitely.** Not Windows-specific. The AppVM units
   (`katmate-app-routed@`, `katmate-app-offline@`) carry `-no-reboot`, so
   `panic=1` on their command line would end the QEMU.
   **`katmate-sys-driver@` has no `-no-reboot`:** `panic=1` alone would make a
   panic loop; it needs both. Observed in w2 with a gateway whose delta was
   smaller than its layer. Recorded, not fixed ([ADR-041](adr/ADR-041.md)
   item 4). Source: `w2-report.md` H4, S3.3.

65. **install.sh's IOMMU-group listing for netVM's card has an unguarded
   glob.** *netVM's card* sets
   `GRP_DIR="/sys/bus/pci/devices/$NIC_BDF/iommu_group/devices"` and loops
   over `"$GRP_DIR"/*` without `nullglob`. With no IOMMU group (no IOMMU, or a
   VM without a vIOMMU) the loop sees the literal `…/devices/*`, `OTHERS`
   becomes ` *`, and the user is asked `Continue with this card anyway
   (yes/no)` for a group that does not exist. Read, not run. Recorded, not
   fixed. Source: `iso1-report.md` H2.7, H3.6.

66. **Install-medium builds are refused from about 2026-11-01 until
   `archlinux-keyring` extends two packager keys.** With today's keyring the
   earliest expiry among the keys that sign the offline repository is
   2026-12-31 (`A85E811EB4CA2E08`, `539DFD48135182EF`), and `build/iso.sh`
   refuses a medium with fewer than 60 days left
   ([ADR-042](adr/ADR-042.md) Decision 5). A constraint on the release date,
   not a defect: a release medium planned for November or December depends on
   a newer keyring that extends or replaces those keys. Source:
   `iso1-report.md` H3.7.

67. **The install medium's signature is not part of the release process.**
   [ADR-042](adr/ADR-042.md) Decision 7: the ISO is covered by the release
   key ([ADR-020](adr/ADR-020.md)) as a detached signature, listed in
   `SHA256SUMS`. `tools/make-release.sh` neither takes nor lists an ISO
   today, and `build/iso.sh` writes an unsigned `.sha256` only. **Open:** add
   the ISO to the release set and its signing on the Acer.

68. **The install medium's unexecuted branches.** Written in `01026ac`, not
   run in iso1 (UNVERIFIED): install.sh's own offline pacstrap line
   (`PACSTRAP_OPTS`; iso1 ran the same arguments by hand); the URL path on
   the medium (tag-pinned default URL, the network step for a URL, Wi-Fi via
   iwd, the live network firmware); the refusals for more than one
   `KMRELEASE` filesystem, for a release disk chosen as target, and for a
   `KMRELEASE` filesystem that resolves to no disk; preflight's
   `release-medium` record and exclusion; real hardware, and whether the five
   live firmware subpackages cover the Cubi's NIC and Wi-Fi. **Closes with**
   the Cubi gate: an end-to-end install from the next tagged release
   ([ADR-042](adr/ADR-042.md)). Source: `iso1-report.md` H2.6, H3.5.
