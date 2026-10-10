# Dev environment: live state (MINIS/UM870)

Condensed 2026-10-10; the full text before this pass is at
<https://github.com/KatMate/katmate-os/blob/a92b3ef/docs/DEV-ENV.md>.
Current facts only, each with the date it was last read; report files cited
(`*-report.md`) are outside the repository. Nothing here is product
configuration.

**CID map (authoritative, ADR-022).** `2` host · `3–19` sysVMs (3 = primary
netVM) · `20–99` fixed persistent AppVMs · `≥100` disposable pool. Applied
2026-08-02 in `app_web.con` (5 → 21), ADR-015, ADR-017 and
`tools/validate-properties.fish`. Allocated: netVM 3, `app_web` 21,
`app_personal` 22, `app_work` 23, `app_vault` 24.

- **Host** (Arch): Ryzen 7 8745H, AMD-Vi + vfio. `vg0`: `root` 100G, `swap` 12G,
  `vm_pool` thin pool. Kernel `7.2.8-hardened1-1-hardened`, booted 2026-10-02
  14:03:24 (stock `linux 7.2.6.arch2-1` also installed). Guest microVM kernel
  `6.12.87` at `/home/host/katmate-kernels/` (monolithic, `-kernel`). nft input
  drop; SSH open (open problem #4).
  - **NICs:** the RTL8125 (`01:00.0`) is bound to `vfio-pci` at boot and belongs
    to netVM; `vfio` group + udev rule, `host` a member. Host uplink: USB-NIC
    r8152 `enp195s0f3u1u1`, MAC `00:e0:4c:39:61:b8`, `10.3.1.3` (volatile
    `ip addr`, not a persistent profile).
  - **Egress:** wg-quick policy routing (table 51820) sends the host's own
    traffic, IPv4 and IPv6, into `proton`, not the main table and not netVM.
    Host IPv6 is off permanently (R97): `proton.conf`'s `PostUp` adds `ip -6
    rule add pref 100 unreachable`, `PreDown` removes it. `wg-quick@proton` is
    `enabled`, `active`, the tunnel's one owner (#54 resolved). Removing the
    `/etc/gai.conf` line is the operator's.
  - **Dev packages allowed** (R112): `conntrack-tools 1.4.9-1`, `strace 7.2-1`.
    `nf_conntrack_netlink` is loaded, cause unknown.
  - `host` is in `kvm`, `disk`, `hugepages`, `vfio`. Hugepages: see netVM,
    *Host configuration after the installer merge*.

- **Dev access to MINIS (dev-only; goes out with open problem #4).**
  `ssh host@10.3.1.3`, publickey only; the Acer (`winterbox`, `10.3.1.100`)
  holds the key. `sudo -n` is passwordless via `/etc/sudoers.d/katmate-dev`.
  - **Every `systemctl` on a KatMate unit goes through `sudo -n`**; otherwise
    polkit refuses at D-Bus before the unit is reached, which measures nothing.
  - **The login shell is fish**, so `ssh host@10.3.1.3 '…'` with sh syntax
    dies. The operator may pipe `bash -s <<'EOF'`; a delegated agent may not
    (the classifier refuses it as `curl | sh`): it writes a script, `scp`s it
    and runs it there, which also leaves a hashable record.
    `.claude/settings.local.json` carries the target as configuration.
  - **Permission mode:** auto mode (operator ruling 2026-09-27). On a
    classifier refusal the session stops, reports the exact command and waits;
    it never retries in another form. The operator may switch a session to
    Manual (as for f12-impl-B: an Edit to `docs/DECISIONS.md` and an ssh/scp
    call were refused in auto).
  - **rsync form of record**, dry run (`-an --itemize-changes`) first:
    `rsync -a --delete --exclude=.git/ --exclude=trixie-build/ --exclude=out/
    --exclude=agent/target/ --exclude=git-cli.txt ~/katmate-os/
    host@10.3.1.3:/home/host/katmate-build/`. Without these excludes,
    `--delete` removes MINIS's build outputs.
  - **Build launch form:** a netVM build runs as a transient `systemd-run` unit
    started through `sudo -n bash`, so an ssh drop cannot kill it; followed by
    journal and log file. It has no `HOME` (`docs/INVARIANTS.md`).

- **foundation** (`vm_tpl_foundation`, thin RO): katmate-init is
  `/usr/sbin/init`, systemd's binary diverted to `/usr/sbin/init.systemd`
  (#36); `systemd`, `systemd-sysv`, `dbus`, `dbus-daemon` installed as
  dependency debt, not PID 1 (#35); `foundation.meta` carries
  `KERNEL_PROVENANCE=recorded`. Rebuilt 2026-09-26 (from `5d32dd0`),
  2026-09-29 (from `647a380`) and since; the current layer is in netVM,
  *Layers and LVs*.

- **netVM** (CID 3; Debian trixie, q35; sysVM class, ADR-021; driver domain,
  ADR-022). `vm_sys_netvm`, linear RW 4G, built by `build/netvm.sh`, run by
  the tracked `katmate-sys-driver@netvm.service` with the ADR-035 slot pool
  folded in (`a36bdb2`, R9 comment `70b08c7`); `katmate-pool@netvm` is
  `not-found`, and the netinst pet and `net-sys.con` are retired. Control path
  live-gated (ADR-024, ADR-025).
  - **Image:** `NETVM_BUILT=2026-09-30T14:37:22Z`, guest kernel
    `6.12.111+deb13-amd64`, `UPLINK_PCI_ADDR=0000:00:04.0`, dev build (R27;
    root unlocked, #11), `out/netvm-agent` `4a4e0715…` from `6023a86`. It has
    been booted and carries no unbooted marker (`build/netvm.sh` step 9b), so
    `tools/make-release.sh` refuses it: a release needs a fresh, unbooted build.
  - **Running** (last read 2026-10-03, ai5): MainPID `22405`, invocation
    `ca5f364e…`, `NRestarts=0`, since 2026-10-02 14:19:30. No `jbd2` hold on
    `vm_sys_netvm` (no build this boot), so no reboot is due before the next
    `netvm.sh` unless something mounts it.
  - **Uplink:** `uplink0` by `60-katmate-uplink.link` on
    `Path=pci-0000:00:04.0` (R3, R6), MAC `38:05:25:34:7c:47`, static
    `10.3.1.172/24`, gateway and resolver `10.3.1.1`, from the T1
    `/etc/katmate/vm/netvm.d/uplink` (`6cf06c02…`); removing it returns netVM to
    DHCP (dhcpcd, `allowinterfaces uplink0`). Config disk at `0x15`
    (`/run/katmate/cfgdisk/netvm.img`, `e960fadc…`, read-only). **The LAN run is
    UTP-5:** 100 Mbit/s is the ceiling; the driver reports 1 Gbps at carrier
    and downshifts within milliseconds, so read the speed a few seconds later.
  - **In the guest:** dnsmasq answers DNS on the slots (R5, R17, R18; G4);
    networkd disabled; nftables with `slot_guard` (R49, R50, rule 18) and
    `katmate-ip-forward`; `rp_filter` explicit (R51 in R57's form). The dbus
    daemon is absent, `libdbus-1-3` present (ADR-037). No WireGuard (R20); a
    VPN is a post-install option via the config disk (R8), not implemented.
    The unit passes `ipv6.disable=1` (since `6023a86`).
  - **Slots:** sixteen `dgram` slots, `/run/katmate/link/netvm/00`…`0f` from the
    unit's `RuntimeDirectory=`, preserved across restarts; `ExecStopPost=`
    unlinks the `netvm` nodes. Slot `k` peers at `10.100.1.(16+k)`, gateway
    `10.100.1.1/32`. NETCFG client: `ping-client` (vsock CID 3, port 1025,
    `netcfg-add <cid> <link_id> <mac> <peer> <metric>`, `netcfg-remove`).
  - **Console:** per session only, in `/run` (R1, R9): the drop-in
    `90-dev-monitor.conf` (`b44de3a9…`), the FIFO and `km-console-holder`; a
    reboot removes all three. Left logged out (R94).
  - **Layers and LVs** (2026-10-03, ai5): `vm_tpl_foundation`
    (`BUILD_DATE=2026-10-03T14:37:01Z`, from `77f1b72`, 216 packages) →
    `vm_app_web` (237), `vm_app_office` (368), `vm_app_vault` (292). Every
    layer carries `/sbin/init` `8163e103…` and vm-agent `5d35567f…` (from
    `2a9e638`, R146). Nothing set aside (R132). LVs: `root`, `swap`, the four
    layers, `vm_app_web_home` (linear), `vm_app_personal_home`,
    `vm_app_work_home`, `vm_app_vault_home` (thin), `vm_sys_netvm`, `vm_pool`.
  - **Host configuration after the installer merge** (2026-10-05, `49a172d`;
    the operator's statement, not read on MINIS): `/etc/sysctl.d/hugepages.conf`
    (6144 pages, R126) is removed, as both AppVM templates use
    `memory-backend-memfd` (**UNVERIFIED** until all four AppVMs launch with
    `HugePages_Total` 0); `/etc/systemd/system/katmate-sys-driver@.service.d/10-cpu.conf`
    sets `KM_CPU_FLAGS=,topoext=on` by hand (effect needs `daemon-reload` and a
    netVM restart, not stated); `host/usr` re-synced at `49a172d`, and the
    hash-first check against it is the next session's first action. Deltas stay
    `host:host`, T1 files hand-installed.

- **app_web** (CID 21, slot 01, `LINK_ID` 201): routed T1 (`be542506…`,
  `identity = false` with its NEEDS REVIEW comment); delta
  `/var/lib/katmate/instances/app_web.qcow2` (renamed from `test_web.qcow2`,
  R69) on `vm_app_web`; home `vm_app_web_home`, 10G ext4, **linear**, which
  disagrees with ADR-010's thin home LV (finding, `ai1-report.md` § 5); no
  label, `user/` `1000:1000 0700`. Layer: firefox-esr, foot, pcmanfm;
  `run nautilus` is refused. Run by `katmate-app-routed@app_web`; ADR-037's
  and ADR-038's gates were taken on it (init with R91). `app_web.con` must
  not run beside the unit, and its argv has no network device.

- **app_personal** (CID 22, slot 02, `LINK_ID` 202; `ai1`, 2026-10-02).
  `class = app`, `manifest = web`, `netvm = netvm`, `persistence = persistent`,
  `identity = true` (ADR-014's `personal`), `disposable = false`, `mem = "2G"`,
  `vcpus = 2`.
  - **T1** `/etc/katmate/vm/app_personal.toml`, `root:root 0644`, `042750bf…`,
    staged in the Acer's ignored `local/etc/katmate/vm/`.
  - **Delta** `/var/lib/katmate/instances/app_personal.qcow2`, `host:host 0644`,
    as `host`: `qemu-img create -f qcow2 -F raw -b /dev/vg0/vm_app_web <delta>
    10G`, then `chmod 0644`.
  - **Home LV, the form of record** (ruling of 2026-10-02):
    `lvcreate -V 10G -T vg0/vm_pool -n vm_<instance>_home`; read
    `lvs -o lv_name,lv_attr,pool_lv` (active, no `k`); `mkfs.ext4` with
    defaults; mount; `install -d -o 1000 -g 1000 -m 0700 <mnt>/user`; umount.
  - Booted by `katmate-app-routed@app_personal` (`km.ip=10.100.1.18`). The
    `/run` owner is written per start and gone after a reboot. Per-instance
    values: `docs/PARAMETERS.md`.

- **app_work** (CID 23, slot 03, `LINK_ID` 203; `ai3`, R128). As
  `app_personal`, with `manifest = office`.
  - **T1** `/etc/katmate/vm/app_work.toml`, `root:root 0644`, `bd7f7acc…`.
  - **Delta** `/var/lib/katmate/instances/app_work.qcow2` on
    `/dev/vg0/vm_app_office`; **home** `vm_app_work_home` in the form of record
    (holds the operator's `user/test.odt`).
  - **`office` layer:** foundation plus LibreOffice Writer, Calc, Impress
    (GTK3), foot, pcmanfm; no JRE; RUN target `/usr/bin/libreoffice`.
  - Booted by `katmate-app-routed@app_work` (`km.ip=10.100.1.19`). Values:
    `docs/PARAMETERS.md`.

- **app_vault** (CID 24, no slot, no `LINK_ID`, no owner; `ai4`, R137).
  `manifest = vault`, `netvm = ""` (derives `app-offline`), `identity = false`,
  otherwise as `app_personal`. The June 2026 build-only layer is gone; its
  nautilus → pcmanfm change is `adc217f`, and keepassxc is on the compile-time
  RUN whitelist since `af6e9d3` (R130, ADR-021's note).
  - **Unit** `katmate-app-offline@app_vault` (R135): no network device,
    `km.name=app_vault`, the home drive.
  - **T1** `/etc/katmate/vm/app_vault.toml`, `root:root 0644`, `675a2614…`.
    **Delta** `/var/lib/katmate/instances/app_vault.qcow2` on
    `/dev/vg0/vm_app_vault`; **home** `vm_app_vault_home` (holds
    `user/test.kdbx`).
  - **`vault` layer** (`manifests/vault.list`): foundation plus keepassxc,
    `qtwayland5`, foot, pcmanfm. RUN `keepassxc` opens a window since vm-agent
    sets the Qt platform (R146; R139 and R140 tests). Values:
    `docs/PARAMETERS.md`.

- **Host GUI ingress (`waypipe-client`, user unit).** The unit files live only
  on MINIS, in `~/.config/systemd/user/`, untracked (#31). `ExecStart` is
  `/opt/katmate/bin/waypipe`; `waypipe-client.socket` (a TCP `[::]:1024`
  listener) is disabled; vsock `*:1024` listens; the distro `waypipe` is
  removed from the host. Two dangling `waypipe-client@1024.service` symlinks
  remain (#42). Requirement: `docs/HOST-CONFIG.md` § 11.

- **The launcher and the menu (from 2026-10-03, `ai6`; R150–R158).**
  - **`/usr/lib/katmate/katmate-launch`** `root:root 0755`, `7938f47a…` (T4,
    the launch daemon's alpha precursor; ADR-029's note of 2026-10-03).
    `katmate-launch <instance> <app>` | `--stop <instance>` | `--stop-all`, as
    root only. Exit 0 done, 1 refused or failed, 2 usage. Journal:
    `journalctl -t katmate-launch`. It does not start netVM.
  - **`/usr/lib/katmate/ping-client`** `root:root 0755`, `bbeeddf2…` (R155), a
    copy of `~/katmate-build/agent/target/release/ping-client`. **The installed
    set is 13 files:** the tree's eleven, `katmate-launch` (against the tree)
    and `ping-client` (against that build output).
  - **`/etc/sudoers.d/katmate-launch`** `root:root 0440`, `ebfb91fe…`, staged
    in the Acer's ignored `local/etc/sudoers.d/` (HOST-CONFIG § 13).
    SECURITY-MODEL gap 17. Sufficiency **UNVERIFIED** while `katmate-dev`
    exists (R158).
  - **The menu:** `custom/katmate`, first in `modules-left` of the tracked
    `config-sway.jsonc`; `~/.config/waybar/modules-katmate.jsonc` and
    `katmate-menu.xml` are symlinks into `~/katmate-build/desktop/waybar/`
    (HOST-CONFIG § 14). Reload waybar with SIGUSR2.
  - **Locks and owners:** `/run/katmate/launch/` (`root:root 0700`, `flock`);
    owners are written and removed by the launcher.

- **Disk chain**: three-level LVM-thin chain proven live through a full
  boot/render/shutdown cycle.
