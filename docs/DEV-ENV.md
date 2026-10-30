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
`app_personal` 22, `app_work` 23, `app_vault` 24, `app_sandbox` 25.

- **Host** (Arch): Ryzen 7 8745H, AMD-Vi + vfio. `vg0`: `root` 100G, `swap` 12G,
  `vm_pool` thin pool. Kernel `7.2.10-hardened1-3-hardened`, booted 2026-10-24
  14:33:42 CEST (the `v0.2.0-beta` release run's second reboot); a stock Arch
  kernel is also installed (`7.2.9-arch1-1` tree in `/usr/lib/modules` on
  2026-10-14). Guest microVM kernel
  `6.12.87` at `/home/host/katmate-kernels/` (monolithic, `-kernel`). nft input
  drop; SSH open (open problem #4).
  - **NICs:** the RTL8125 (`01:00.0`) is bound to `vfio-pci` at boot and belongs
    to netVM; `vfio` group + udev rule, `host` a member. Host uplink: USB-NIC
    r8152 `enp195s0f3u1u1`, MAC `00:e0:4c:39:61:b8`, `10.3.1.3` (volatile
    `ip addr`, not a persistent profile).
  - **Egress:** wg-quick policy routing (table 51820) sends the host's own
    traffic, IPv4 and IPv6, into `proton`, not the main table and not netVM.
    Host IPv6 is off permanently (R97): `proton.conf`'s `PostUp` adds `ip -6
    rule add pref 100 unreachable`, `PreDown` removes it. The unit
    `wg-quick@proton` is `disabled` and `inactive` (read 2026-10-23, rel2):
    after every reboot the operator brings the host network, the tunnel
    (wg-quick's rules 32764/32765) and sshd up by hand, so nothing on MINIS is
    reachable over ssh until he has. Removing the `/etc/gai.conf` line is the
    operator's.
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
  - **Image:** the `v0.2.0-beta` release build (rel2):
    `NETVM_BUILT=2026-10-23T18:41:15Z`, guest kernel `6.12.113+deb13-amd64`,
    `NETVM_ROOT_UNLOCKED=no` (no `KATMATE_DEV_ROOT_HASH`), `out/netvm-agent`
    `4777e63b…`. Exported unbooted; booted since by the enable, so
    `tools/make-release.sh` now refuses it: a release needs a fresh, unbooted
    build.
  - **Running** (last read 2026-10-24, rel2): MainPID `5087`, `NRestarts=0`,
    since 2026-10-24 14:39:28 CEST. No `jbd2` hold on `vm_sys_netvm` (no build
    this boot), so no reboot is due before the next `netvm.sh` unless
    something mounts it.
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
  - **Layers and LVs** (2026-10-23, rel2, from `v0.2.0-beta` at `690c48d`):
    `vm_tpl_foundation` (`BUILD_DATE=2026-10-23T17:45:41Z`) → `vm_app_web`
    (`APP_BUILT=…17:48:31Z`), `vm_app_office` (`…17:51:53Z`), `vm_app_vault`
    (`…17:53:09Z`); vm-agent `1d5d2bba…`. These are the images the release
    ships. The five instance deltas were renewed over them on 2026-10-24
    (`root:root 0644`, 10 GiB; #71). LVs: `root`, `swap`, the four layers,
    `vm_app_web_home` (linear), `vm_app_personal_home`, `vm_app_work_home`,
    `vm_app_vault_home`, `vm_app_sandbox_home` (thin), `vm_sys_netvm`,
    `vm_pool`, and w2's `vm_app_gw_w2`, `vm_app_gw_w2b`, `vm_gw_w2_home`.
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
    `lvcreate -V 10G -T vg0/vm_pool -n vm_<instance>_home` (`10G` is the
    default; `katmate-vm create --home-size` chooses another size); read
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
  nautilus → pcmanfm change is `adc217f`, and keepassxc was on the
  compile-time RUN whitelist from `af6e9d3` (R130). Since cu2 the list is the
  layer's `run` (ADR-043 §5); the layer rebuilt in cu2 (2026-10-18) carries
  `RUN=keepassxc foot pcmanfm` in its meta and the same list in
  `/etc/katmate/run-whitelist`.
  - **Unit** `katmate-app-offline@app_vault` (R135): no network device,
    `km.name=app_vault`, the home drive.
  - **T1** `/etc/katmate/vm/app_vault.toml`, `root:root 0644`, `675a2614…`.
    **Delta** `/var/lib/katmate/instances/app_vault.qcow2` on
    `/dev/vg0/vm_app_vault`; **home** `vm_app_vault_home` (holds
    `user/test.kdbx`).
  - **`vault` layer** (`manifests/vault.toml`, then `vault.list`): foundation plus keepassxc,
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
  - **`/usr/lib/katmate/katmate-launch`** `root:root 0755` (T4, the launch
    daemon's alpha precursor; ADR-029's notes of 2026-10-03 and 2026-10-18).
    `katmate-launch <instance> <app>` | `--stop <instance>` | `--stop-all` |
    `--cid-check`, as root only. Exit 0 done, 1 refused or failed, 2 usage. Journal:
    `journalctl -t katmate-launch`. It does not start netVM.
  - **`/usr/lib/katmate/ping-client`** `root:root 0755`, `c073dccf…` (rel2,
    `v0.2.0-beta`), a copy of `~/katmate-build/agent/target/release/ping-client`.
    `katmate-alloc` and `katmate-vm` below were rebuilt in the same run,
    byte-identical to the ones installed before.
  - **`/usr/lib/katmate/katmate-alloc`** `root:root 0755` (cu3), a copy of
    `~/katmate-build/agent/target/release/katmate-alloc`.
  - **`/usr/lib/katmate/katmate-vm`** `root:root 0755` (cu4), a copy of
    `~/katmate-build/agent/target/release/katmate-vm`. `create <name> --layer
    <layer> [--home-size <n>G]` | `status [<name>]` | `delete <name> [--purge]` | `provision
    <name>` | `menu`, as root only; `class = app` names are `app_*`. Homes and deltas
    are made with `katmate-vm create`, not by hand. `menu` (cu5) regenerates
    the launcher's entries; `create` and `delete` do it themselves, under the
    launch lock, `provision` does not. Exit 3: created or deleted, entries not
    updated; the instance is not undone, and `katmate-vm menu` recovers.
    `delete --purge` asks for the instance name on a terminal only (a
    non-terminal stdin is refused) and discards typeahead before each prompt;
    an empty answer re-asks, up to three prompts, and a mismatch refuses at
    once. A refusal removes nothing (cu5f). `--home-size` is the new home
    LV's size: default 10G, a whole number of GiB, refused above the thin
    pool's size and with `--reuse-home`, held by the LV and not by T1;
    `provision` always makes 10G (hs1).
    Journal: `journalctl -t katmate-vm`.
  - **`/usr/lib/katmate/katmate-t1-read`** `root:root 0755` (cu4, in the
    tree): `<instance>` → `key=value` through `km_t1_read`; `--pairs`.
  - **`/usr/lib/katmate/katmate-generate-menu`** `root:root 0755` (cu5, in
    the tree; was `installer/gen-desktop-entries`): `<t1-vm-dir> <t2-dir>
    <outdir>`, run by `katmate-vm menu` and once by the installer.
  - **The tree's installed set is 17 files:** `host/usr`'s fourteen (ten in
    `lib/katmate`, four units; `cp -a`, `installer/install.sh`) and
    `ping-client`, `katmate-alloc`, `katmate-vm` (against that build output).
  - **`/etc/sudoers.d/katmate-launch`** `root:root 0440`, `ebfb91fe…`, staged
    in the Acer's ignored `local/etc/sudoers.d/` (HOST-CONFIG § 13).
    SECURITY-MODEL gap 17. Sufficiency **UNVERIFIED** while `katmate-dev`
    exists (R158).
  - **The launcher:** `km-menu` (fuzzel) on `$mod+space`; the power menu on
    the bar's `custom/arch`. Deployed at the system paths of
    `desktop/README.md` § *Deployment* (HOST-CONFIG § 14). Reload sway with
    `swaymsg reload`, waybar with SIGUSR2. The desktop entries are state in
    `/var/lib/katmate/desktop/applications/`; `katmate-vm create` and
    `delete` rewrite them, and after a layer rebuild or a hand-edited T1
    `sudo /usr/lib/katmate/katmate-vm menu` does.
  - **Locks and owners:** `/run/katmate/launch/` (`root:root 0700`, `flock`)
    serialises the launcher; slot owners, `alloc.lock` and `link-id` are in
    `/run/katmate/link/<netvm>/`, written and removed by `katmate-alloc`.

- **Disk chain**: three-level LVM-thin chain proven live through a full
  boot/render/shutdown cycle.

## Release run

Written for `v0.2.0-beta` (rel1, 2026-10-23) and corrected by its run (rel2,
rel3, 2026-10-23 to 2026-10-30); for another tag, replace the tag throughout.
The release set and its signing: [ADR-020](adr/ADR-020.md) and
[ADR-042](adr/ADR-042.md), revision notes of 2026-10-23.
`tools/make-release.sh` prints step 3 itself, for the paths of its run. The
MINIS address is the one under *Dev access to MINIS* above (volatile); the
script's `BUILD_HOST_SSH` changes with it. Every reboot below needs the
operator at MINIS (LUKS passphrase, then the network, the tunnel and sshd by
hand).

**1. Acer: tag, archive, copy.** From a clean tree at `main`; the rsync dry
run (`-an --itemize-changes`) first. The tag is pushed only at publish.

```
cd ~/katmate-os
git fetch origin && git status --short && git rev-parse HEAD origin/main
git tag -s -u 3F49AE514562ACD3FF9D6049F8841B7B3D3AB436 -m "KatMate OS v0.2.0-beta" v0.2.0-beta
git tag -v v0.2.0-beta
mkdir -p ~/release-v0.2.0-beta
git -c tar.umask=0022 archive --format=tar.gz --prefix=katmate-os-v0.2.0-beta/ -o ~/release-v0.2.0-beta/katmate-os-v0.2.0-beta.tar.gz v0.2.0-beta
rsync -a --delete --exclude=.git/ --exclude=trixie-build/ --exclude=out/ --exclude=agent/target/ --exclude=git-cli.txt ~/katmate-os/ host@10.3.1.3:/home/host/katmate-build/
ssh host@10.3.1.3 mkdir -p /home/host/release-v0.2.0-beta/in
scp ~/release-v0.2.0-beta/katmate-os-v0.2.0-beta.tar.gz host@10.3.1.3:/home/host/release-v0.2.0-beta/in/
```

**2. MINIS: medium, images, release set.** In this order:

1. **The medium.** It needs only the archive and the host's own network, and
   it is the step the keyring deadline binds
   ([open problem #66](OPEN-PROBLEMS.md)). `iso.sh` retries the offline
   repository's download three times; a run that still fails on a download is
   re-run in the same form after its `--out` is moved aside.
2. **The `--built-after` stamp.**
3. **The host binaries, clean:** in `agent/`, `cargo clean`, then
   `cargo build --release --locked`; `vm-agent` and `netvm-agent` into
   `out/`; `ping-client`, `katmate-alloc`, `katmate-vm` into
   `/usr/lib/katmate/` (`root:root 0755`).
4. **The foundation and the layers.** First remove every instance delta in
   `/var/lib/katmate/instances/` whose backing file (`qemu-img info -U`) is
   one of the layers, then `lvchange -an` and `lvremove` the foundation and
   the three layers, each after the stuck-`jbd2` test (`docs/INVARIANTS.md`);
   then `make foundation` and `make apps`.
5. **netVM, with two reboots.** `systemctl disable katmate-sys-driver@netvm`
   → reboot → stuck-`jbd2` test → `lvchange -an` and `lvremove
   vg0/vm_sys_netvm` (no `-f`) → `build/netvm.sh` without
   `KATMATE_DEV_ROOT_HASH` → **reboot** (the build leaves the `jbd2` hold, and
   `make-release.sh` refuses an open LV) → stuck-`jbd2` test →
   `make-release.sh` → `systemctl enable --now katmate-sys-driver@netvm`.
   netVM is never booted between its build and `make-release.sh`.
6. **The instance deltas again**, over the new layers, in `katmate-vm`'s
   form: per instance `katmate-check-image --layer <layer>` for the LV,
   `katmate-activate-lvs --layer <layer>`, `qemu-img create -q -f qcow2 -F raw
   -b /dev/vg0/<layer LV> <delta> 10G`, mode `0644`; then `katmate-vm menu`.
   T1 files and homes are kept ([open problem #71](OPEN-PROBLEMS.md)).

Before every step that fetches from the network (1, 4, `build/netvm.sh`),
`ip -6 rule list` must show `100: from all unreachable`; no script checks it.

```
sudo /home/host/katmate-build/build/iso.sh --archive /home/host/release-v0.2.0-beta/in/katmate-os-v0.2.0-beta.tar.gz --out /home/host/release-v0.2.0-beta/iso
date -u +%Y-%m-%dT%H:%M:%SZ > /home/host/release-v0.2.0-beta/built-after
```

After the image builds and the second reboot:

```
sudo /home/host/katmate-build/tools/make-release.sh --tag v0.2.0-beta --archive /home/host/release-v0.2.0-beta/in/katmate-os-v0.2.0-beta.tar.gz --iso /home/host/release-v0.2.0-beta/iso/katmate-install-v0.2.0-beta-x86_64.iso --out /home/host/release-v0.2.0-beta/out --built-after (cat /home/host/release-v0.2.0-beta/built-after)
sudo systemctl enable --now katmate-sys-driver@netvm
```

**3. Acer: check, sign, verify, copy the signature back.** One chain:
nothing is signed after a failed step.

```
cd ~/katmate-os && git tag -v v0.2.0-beta \
  && scp host@10.3.1.3:/home/host/release-v0.2.0-beta/out/SHA256SUMS ~/release-v0.2.0-beta/SHA256SUMS \
  && cd ~/release-v0.2.0-beta && sha256sum -c --ignore-missing SHA256SUMS \
  && gpg --local-user 3F49AE514562ACD3FF9D6049F8841B7B3D3AB436 --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS \
  && gpg --verify SHA256SUMS.asc SHA256SUMS
scp ~/release-v0.2.0-beta/SHA256SUMS.asc host@10.3.1.3:/home/host/release-v0.2.0-beta/
```

Expected: `katmate-os-v0.2.0-beta.tar.gz: OK`, then a good signature from
KatMate. The signature goes back to MINIS for the install media.

**4. MINIS: the media for the Cubi gate**, as in
[`docs/INSTALL.md`](INSTALL.md): the ISO on one stick, every file of `out/`
except the ISO plus `SHA256SUMS.asc` on a `KMRELEASE` disk, each checked
after the write. The gate installs from them before anything is published.

**5. Publish, after the Cubi gate passes** (Acer; `gh` logged in as KatMate).
The upload took about two hours on the lab's LTE uplink.

```
rsync -a --partial --progress host@10.3.1.3:/home/host/release-v0.2.0-beta/out/ ~/release-v0.2.0-beta/out/
cd ~/release-v0.2.0-beta/out && cmp SHA256SUMS ../SHA256SUMS && sha256sum -c SHA256SUMS && cp ../SHA256SUMS.asc . && gpg --verify SHA256SUMS.asc SHA256SUMS
cd ~/katmate-os && git push origin v0.2.0-beta
gh release create v0.2.0-beta --repo KatMate/katmate-os --verify-tag --draft --prerelease --title "KatMate OS v0.2.0-beta" --notes-file ~/Claude.assistent/beta-notes.md ~/release-v0.2.0-beta/out/*
```

Then compare each asset's `digest` with `SHA256SUMS` before publishing:

```
gh api repos/KatMate/katmate-os/releases --jq '.[] | select(.tag_name=="v0.2.0-beta") | "draft=\(.draft) assets=\(.assets|length)", (.assets[] | "\(.digest) \(.size) \(.name) \(.state)")'
gh api -X PATCH repos/KatMate/katmate-os/releases/(gh api repos/KatMate/katmate-os/releases --jq '.[] | select(.tag_name=="v0.2.0-beta") | .id') -F draft=false
```

`gh release edit --draft=false` returned HTTP 500 for `v0.2.0-beta`; the
minimal `PATCH` published it. Only the current release is kept: the previous
one goes with `gh release delete` (for the beta: `v0.2.0-alpha2 --yes`), and
its tag stays.
