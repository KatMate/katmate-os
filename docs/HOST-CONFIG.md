# Host configuration

Host-side configuration that KatMate depends on, lives outside the repository,
and must therefore be produced by the installer. Append-only, newest first
within each section.

## What this file is for

Some of what makes KatMate work is not in git. It is in `/etc`, in firmware
settings, in kernel command lines, and in per-machine generated files that
[the anti-drift pattern](../state.md) deliberately keeps out of version control.
Each such item was discovered by running the system, applied by hand on one
machine, and is invisible to a fresh install.

This file is the list. It is **an input to the installer** (ROADMAP build order
step 6), not a log. An entry earns its place by answering: *what must be set,
where, and what silently breaks if it is not.*

## What this file is not

- **Not `OBSERVATIONS.md`.** That file holds externally published material
  bearing on our decisions, and its conventions route corrections of our own
  statements elsewhere. Everything here is our own measurement on our own
  hardware.
- **Not `DECISIONS.md`.** Nothing here is an architectural choice. These are
  consequences of choices recorded there.
- **Not `state.md`.** That file describes what is true on the machines today.
  This file describes what must be true on *any* machine for KatMate to work,
  including one that does not exist yet.

## Conventions

- **Every entry states its failure mode.** An entry that only says what to set
  is a note; an entry that says what breaks without it is a requirement. Where
  the failure is silent, say so explicitly — silent failures are the reason
  this file exists.
- **Status markers:** `[LIVE]` applied by hand on a machine, not automated ·
  `[OPEN]` known requirement, applied nowhere · `[AUTO]` produced by the
  installer already.
- **Confidence markers:** `[V]` verified on hardware · `[?]` believed true,
  not re-checked at the time of writing. A `[?]` entry is not yet a
  requirement — it is a thing to verify before it becomes one.
- **Machine scope is mandatory.** MINIS, Acer, Cubi, or *all*. A requirement
  without a scope cannot be implemented.

---

# Network

## 1. `RequiredForOnline=no` on all tap and bridge link definitions

**Scope:** any host running VM taps under networkd · **[LIVE]** on MINIS
(`/etc/systemd/network/`) · **[V]** 2026-08-02

**Re-measured 2026-09-27, after the host clean-up: MINIS now has no tap and no
bridge, and networkd manages no link.** The last six networkd-managed links
are gone from the host: `tap-int0` (moved out that morning) and `br-personal`,
`tap0`, `tap-outer`, `tap-personal` and `tap-work`. Their files are
in `~/katmate-dev/removed-0927/` and `removed-0927b/`. `/etc/systemd/network/` is empty.
Readings (`../state.md`, 2026-09-27 *host-cleanup* entry):
`networkctl list` shows `lo`, `enp195s0f3u1u1` (routable) and `proton`
(routable), **all three `unmanaged`**. `networkctl status` gives `State: routable` and
`Online state: unknown`. `network-online.target` and
`systemd-networkd-wait-online.service` (enabled) are both `inactive (dead)`.
**Neither has run during this boot:** every activation timestamp is empty and
the journal has no entries for either. The only unit that pulls the target in
is `archlinux-keyring-wkd-sync.service`. A direct probe,
`/usr/lib/systemd/systemd-networkd-wait-online --timeout=15`, printed
*"Timeout occurred while waiting for network connectivity."* and **exited 1
after 15.2 s**. No probe was taken before the removal, so this reading is not
evidence that the removal changed anything.

**Correction, as a note — the text below is left as published.** *"On MINIS
every networkd-managed link is a carrier-less tap"* did not describe the host.
`br-personal` was a networkd-managed, carrier-less **bridge**. Its `.netdev`
dates from 2026-03-12, before this section's 2026-08-02 verification. The
requirement text already names bridges, so only the description changes. That a
bridge with the default holds `network-online.target` the way the taps did was
never measured.

**The requirement stands.** Installer output for any **future** tap or bridge
still carries `RequiredForOnline=no`. MINIS today has none, so the `[LIVE]`
marker above has nothing on MINIS to apply to until a tap or bridge returns.
**What the host does at its next boot, or the next time something pulls in
`network-online.target`, with zero managed links, is UNVERIFIED.** This
boot reached its targets without ever activating that target, so it says
nothing either way. It is settled by `systemctl show -p
ActiveState,Result,ActiveEnterTimestamp network-online.target
systemd-networkd-wait-online.service` and `journalctl -b -u
systemd-networkd-wait-online`, after a boot or an
`archlinux-keyring-wkd-sync` run. The probe's timeout predicts a failed
wait-online there, and it is a prediction until that reading exists. The ADR-029
bearing below is unchanged: VM units must not depend on
`network-online.target`.

**Requirement:** every networkd `[Link]` section for a tap or bridge carries
`RequiredForOnline=no`.

**Failure mode — silent.** With the `RequiredForOnline=yes` default,
`network-online.target` never fires. Not late: never. On MINIS every
networkd-*managed* link is a carrier-less tap, while both actually routable
links are *unmanaged*, so networkd reports `State: routable` alongside
`Online state: offline` — a pair that reads as healthy unless both lines are
read together. `systemd-timesyncd` consequently never polled, and logged
nothing about it. Anything ordered `After=network-online.target` waits forever
without an error.

**Bearing on ADR-029.** VM units must not depend on `network-online.target`.
An AppVM's connectivity arrives through netVM and NETCFG
([ADR-023](DECISIONS.md#adr-023), [ADR-025](DECISIONS.md#adr-025)), never
through the host's networkd; and on this host that dependency is unsatisfiable
in a way that produces no diagnostic. Recorded as an ADR-029 constraint, not
merely as host hygiene.

**History.** Recorded 2026-07-20 as resolved with the prediction that the
default would at worst "slow boot". Re-classified 2026-08-02: the prediction
was wrong in kind, not in degree.

## 2. Host uplink persistent profile, matched on MAC

**Scope:** MINIS · **[OPEN]** · **[V]** 2026-07-06

**Requirement:** a persistent networkd profile for the USB-NIC uplink, matched
on **MAC** (`00:e0:4c:39:61:b8`), not on the interface name.

**Failure mode.** The address `10.3.1.3` is currently configured with a bare
`ip addr` and does not survive a reboot. The name `enp195s0f3u1u1` encodes the
USB path, so a different port yields a different name and a name-matched
profile would not apply.

**Cross-reference:** ties to the sshd exposure work (SECURITY-MODEL gap #4) —
sshd should bind to the LAN address, not to the VPN tunnel address.

## 3. RTL8125 bound to `vfio-pci` at boot

**Scope:** MINIS (any host with a passed-through NIC) · **[LIVE]** · **[V]**

**Requirement:** `0000:01:00.0` bound to `vfio-pci` rather than `r8169` from
boot; a `vfio` group and a udev rule granting the desktop user access.

**Failure mode.** If the host driver claims the NIC first, netVM cannot take it
and `net-sys.con` fails at `-device vfio-pci`. If the group/udev rule is
missing, the launcher requires root for the device node — which conflicts with
C1/C2 of the [C-gate](DECISIONS.md#adr-027).

**Generalisation needed.** IOMMU-group quality is unverified at install time
(open problem #9): a driver domain is only safe where the NIC sits in a cleanly
isolable group. The installer needs a preflight, not just a binding step.

**A BDF is not a durable name.** [ADR-030](DECISIONS.md#adr-030) §5 makes the
`Vm` carry a label (`nic = "uplink0"`) and requires the boot-time binding step
to publish the resolution at `/run/katmate/nics/<label>`. What that label
resolves *from* is unspecified and must be measured, not chosen at a desk:
`vendor:device` is not unique on a two-port card, the MAC is only readable
before `vfio-pci` binds, and the slot path is stable against reseating but not
against a firmware change.

**Failure mode, and it is silent.** `vfio-pci` binds to an address, not to a
device. A stale BDF hands *some other* device to the most network-exposed VM in
the system, and QEMU starts normally. ADR-030 requires a `vendor`/`device`
check at VM start as blast-radius limiting; that check is not a substitute for
choosing a durable descriptor here.

**Same class as §2.** The USB-NIC profile and this entry are one problem —
durable identity against volatile enumeration — at two sites. Solve the
descriptor question once.

---

# Boot and firmware

## 4. mkinitcpio HOOKS and MODULES for the UKI pipeline

**Scope:** MINIS · **[LIVE]** · **[?]** — exact values not re-checked

**Requirement:** `plymouth` before `encrypt` in HOOKS, plus `kms`; `amdgpu` and
the `vfio_pci` / `vfio` / `vfio_iommu_type1` set in MODULES.

**Failure mode.** Wrong HOOKS ordering loses the graphical LUKS unlock (the
prompt falls back to text, or the theme does not load). Missing `kms` breaks
the Sway desktop profile at install time — already noted against ROADMAP build
order step 6.

**Verify before treating as a requirement:** read the live
`/etc/mkinitcpio.conf` on MINIS and replace this entry with the exact lines.

## 5. `vhost_vsock` module load unit

**Scope:** all · **[LIVE]** on MINIS · **[V]** 2026-08-02

**Requirement:** `vhost_vsock` loaded before any VM starts.

**Defect in the current implementation.** MINIS carries
`/etc/systemd/system/vhost-vsock-load.service`, whose line 5 uses
`ConditionKernelModule` — a key systemd does not know. It is parsed, reported
as unknown in `dmesg`, and ignored. The unit works; the condition does not
exist. The installer should not reproduce it.

**Failure mode if the module is absent.** `-device vhost-vsock-device` fails at
QEMU start, so no VM has a control path or a GUI path
([ADR-028](DECISIONS.md#adr-028)).

## 6. Hugepages backing for `/dev/hugepages`

**Scope:** all · **[LIVE]** on MINIS · **[V]** 2026-09-26 (was `[?]` — not
verified as a configured requirement)

**Requirement (believed):** `app_web.con` uses
`memory-backend-file,mem-path=/dev/hugepages,share=on`, which requires
hugepages to be reserved and the mount to exist.

**Measured on MINIS, 2026-09-26** (operator, before the first boot of the
rebuilt `app_web`): **4096 × 2 MB hugepages reserved** (`HugePages_Total`
4096, `Free` 4096, `Hugepagesize` 2048 kB); `/dev/hugepages` is
`root:hugepages`, mode `1770`; the `host` account is in `hugepages` (and in
`kvm`, `disk`, `vfio`). `app_web` then booted on it. How the reservation is
configured (sysctl, kernel command line or unit) was **not** read, and it is
what the installer would have to reproduce.

**Failure mode.** QEMU fails to allocate the memory backend at start. Whether
MINIS carries an explicit reservation or relies on a default is **unchecked** —
verify before this becomes a requirement, and note that a reservation
interacts with `memlock` (C3) and with the transparent-hugepage behaviour noted
in `../state.md`.

**Probably allocated the wrong way round.** `app_web` (no vfio) takes
hugepages; `net-sys` (vfio) takes `memory-backend-memfd`. The vfio VM is the
one that benefits — fewer pages to pin, smaller IOMMU tables — and under C1
(`User=`) hugepages additionally require DAC on `/dev/hugepages`, which memfd
does not. Whether `share=on` has any consumer at all is also unchecked:
vhost-vsock is in-kernel and no vhost-user process exists. Surfaced by the
ADR-030 launcher inventory; deferred to its own session, together with C3.

---

# Desktop and session

## 11. `waypipe-client` user unit — the host end of the GUI path

**Scope:** MINIS · **[LIVE]** · **[V]** 2026-09-26

**Requirement:** a systemd user unit for the desktop user whose `ExecStart` is
`/opt/katmate/bin/waypipe --vsock --socket 2:1024 client`. That is the
version-locked binary of [ADR-019](DECISIONS.md#adr-019), not the distro's
`/usr/bin/waypipe`. There is **no socket unit**. The service's
`WAYLAND_DISPLAY` must name the compositor's actual socket (on MINIS,
`wayland-1`, matching `/run/user/1000/wayland-1`). On MINIS today the unit
lives in `~/.config/systemd/user/`, untracked. It was edited by hand on
2026-09-26 and runs as described: its exe is the `/opt` binary, vsock `*:1024`
is listening, and TCP 1024 is closed.

**`ExecStart` verified against the unit file, 2026-09-26.** The operator showed
the unit file on MINIS, and its `ExecStart` arguments are the ones above. The
distro `waypipe` was removed from MINIS the same day (`pacman -Rs waypipe`);
`waypipe-client` stayed `active`, and `waypipe` is no longer on the host
`PATH`.

**Failure modes.**
- **Absent:** there is no GUI path at all. This is **silent until an app is
  run**. A guest boots and its agent answers, and nothing draws.
- **Pointing at `/usr/bin/waypipe`:** host and guest run different waypipe
  versions, and `katmate-check-waypipe` does **not** see it, because it checks
  the `/opt` binary. On MINIS this was the state from the distro upgrade of
  2026-09-18 (0.11.2 against the guest's 0.11.0) until 2026-09-26.
- **With a socket unit as shipped here:** the host opens **TCP port 1024** on
  `[::]`, not a vsock listener. That is a network-reachable listener on the
  host, where the design has only vsock.

See `../state.md` open problem #31 (location; tracking still open),
[ADR-019](DECISIONS.md#adr-019), and [ADR-036](DECISIONS.md#adr-036)
(PROPOSED), which would place the ingress in the system rather than the user
session.

## 7. greetd session entries

**Scope:** MINIS (any machine with a desktop) · **[LIVE]** · **[?]** — path and
wrapper name not re-checked

**Requirement:** two session entries under `/etc/greetd/sessions/`, the Sway one
invoked through a `sway-quiet` wrapper.

**Failure mode.** Without them greetd pins a single hardcoded command, so the
Sway/Hyprland choice of [ADR-016](DECISIONS.md#adr-016) is not offered and the
machine boots whichever session was compiled into the config.

**Deliberately per-machine.** These are generated, not tracked — consistent
with the anti-drift pattern. That is precisely why they must be installer
output.

## 8. Sway output configuration

**Scope:** per-machine · **[LIVE]** on MINIS and Acer · **[V]**

**Requirement:** an `outputs.conf` fragment naming the machine's actual
outputs — MINIS has `DP-3` and `HDMI-A-1`, the Acer has only `eDP-1`.

**Not a debt.** The absence of an `output` block in the tracked Sway config is
a decision (recorded 2026-07-27): a hardcoded output name in git would be wrong
on every machine but one. The installer must therefore *generate* this, not
ship it.

## 9. rofi configuration source

**Scope:** MINIS · **[OPEN]** · **[V]**

**Problem.** `~/.config/rofi/` on MINIS is a separate CYBRland checkout with its
own `.git`. The rofi layer has two sources of truth and they are not reconciled.

**Failure mode.** Not a runtime failure — a provenance failure. A fresh install
has no defined rofi source, and the licence position of the CYBRland-derived
`desktop/` subtree is still open (GPL-3.0 attribution, ADR-031 planned).

---

# VM description

## 12. `/etc/katmate/netvm/` — per-installation netVM configuration

**Scope:** all · **[OPEN]** — decided, not implemented; no confidence marker,
because nothing exists yet to verify

**Note 2026-09-27, after networking arc step 3: `[LIVE]` on MINIS, `[V]`
2026-09-27.** The mechanism is implemented, installed on MINIS and gated
(ADR-037's note of 2026-09-27 on the step-3 gates: G6 and G3's static half
PASS). The operator's static T1 is in place on MINIS as
`/etc/katmate/vm/netvm.d/uplink`, `root:root 0644`, in a `root:root 0755`
directory, and netVM runs on it with a static uplink. The Scope line above
and the notes below are left as written.
- **Failure mode, now stated and observed.** A malformed `uplink`, an unknown
  file in `<instance>.d/`, a symbolic link for `uplink`, or an `uplink` with a
  wrong owner or mode **fails closed**. The builder refuses, the unit fails
  before QEMU starts, and netVM does not start, so there is no uplink for any
  AppVM. The journal names the file, and for a malformed value the key. **An
  absent `uplink` is not a failure:** the disk is built without the entry, and
  netVM leases by DHCP. The same refusals for the **directory** (wrong owner or
  mode, a symbolic link, not a directory) are implemented and were run only
  against an extracted copy of the check, not the installed builder.
- **Not measured:** whether the static T1 holds across a host reboot. No
  reboot was taken with the file in place.
- **The installer** may create `<instance>.d/` and its files only under
  [ADR-032](DECISIONS.md#adr-032)'s rule for T1: it creates, and it never
  overwrites a file it did not create in the same run.

**Note 2026-09-28, after networking arc step 3a: the static T1 held across
one host reboot.** After the MINIS boot of 2026-09-28 19:12:42 and netVM's
start on the rebuilt image, the host's ARP scan found the uplink MAC at
`10.3.1.172` (`f12-impl-B-report.md`, Phase C, outside the repository). The
T1 was unchanged across the reboot (`6cf06c02…`). This is **one
observation**, and it answers the 2026-09-27 note's *Not measured* line for
that one reboot. The note above is left as written.

**Ruled 2026-09-27, before any code: the location is now
`/etc/katmate/vm/<instance>.d/uplink`, and still `[OPEN]`.** The operator's
rulings of that day (ADR-037's note of 2026-09-27 on the step-3 rulings; the
T1 form is recorded in ADR-032's note of the same date) change this entry as
follows. The heading and the text below are left as written.
- **Location (R31).** `/etc/katmate/vm/<netvm-instance>.d/`, keyed by
  instance, one file per concern, and **not** `/etc/katmate/netvm/`. Arc step
  3's file is `uplink`, the static uplink. An unknown file there is refused.
  The WireGuard config is arc step 5's (R30), and so are the modes for a
  secret.
- **The disk (R32).** It is built at every start by a T4 executable, as
  `/run/katmate/cfgdisk/<instance>.img` (directory `root:root 0700`, image
  `root:root 0600`), a runtime projection and not a file this section owns.
- **The failure mode to state here once it is implemented (R36):** a
  malformed `uplink`, or an unknown file, **fails closed**. The builder
  refuses and netVM does not start, so there is no uplink for any AppVM. An
  absent `uplink` is not a failure: netVM leases by DHCP.

**Requirement:** a directory `/etc/katmate/netvm/` holding the per-installation
configuration of netVM — T1, the user's and never the image's
([ADR-032](DECISIONS.md#adr-032)). It carries the **static uplink**
configuration, where the uplink is not configured by DHCP, and the **WireGuard
config** the user supplies to enable a VPN. The host assembles a read-only
config disk from it, which netVM attaches as an extra `virtio-blk`
([ADR-037](DECISIONS.md#adr-037), R7 and R8; Accepted).

**Failure mode: none yet, because the mechanism is not implemented.** No
config disk is built, attached or read today, so nothing can fail for the
directory's absence and nothing reads it if it is present. What breaks without
it is to be stated here when the mechanism exists; ADR-037's gate G6 specifies
the fallback it must show — netVM starting without the disk, on DHCP.

## 10. `/etc/katmate/vm/` — T1 instance properties

**Scope:** all · **[LIVE]** on MINIS · **[V]** 2026-08-11

**Requirement:** one `<name>.toml` per VM at `/etc/katmate/vm/`, flat, one file
per VM, `root:root` `0644` ([ADR-032](DECISIONS.md#adr-032) §1). MINIS carries
`netvm.toml` and `app_web.toml`.

**Failure mode, and part of it is silent.** `tools/validate-properties.fish`
defaults to this directory; with the directory absent it exits **2** ("nothing
was validated") rather than 0, which is deliberate — an empty run reporting
success would look like a pass. The unit path is the unsilent half: no T1 means
`katmate-generate-env` has nothing to project and the VM does not start. The
silent half is the **cross-file** rule: the "no two VMs may claim the same `nic`
label" check ([ADR-030](DECISIONS.md#adr-030) §4, gate G5) is only evaluated
over a directory, because only a directory guarantees every VM's file was seen.
Validating individual files instead skips it, and a skipped cross-file rule
looks exactly like a passing one.

**Staged in the repository at `local/etc/katmate/vm/`, which is ignored, not
tracked** (`.gitignore` line 12, `/local/`). The staging tree mirrors install
paths *inside itself*, so the install step is a **copy and never an authoring
step** — a second authored copy is precisely the drift ADR-032 exists to
prevent.

**Why ignored rather than tracked.** ADR-032 §1: T1 is never in the repository.
A committed `properties.toml` was authored by the project, and by the tier
boundary that makes it T3/T4, not T1. A file cannot be T1 in the tree and T1 on
the machine. For the same reason `local/` must **not** move under `host/`: in
`host/` the path asserts what is shipped, and a T1 file under `host/etc/katmate/`
would be the exact mistake ADR-032 exists to make visible from the path alone.

**Applied by hand on 2026-08-11**, `install -D -m 0644 -o root -g root` from the
staging tree, verified with `cmp` and `sha256sum` against the source rather than
by eye. **Build-order step 6 replaces this hand-copy with installer
provisioning**, under ADR-032's constraint on the installer: it may create a T1
file, and it may **never** overwrite one it did not create in the same run. The
relation is `/etc/skel` to `$HOME` — files written at install time are the
user's from that moment, and a later release that needs a schema change
notifies rather than overwrites.

---

# Not in this file

- Dev-only scaffolding that must be **removed** before release — host sshd
  (open problem #4), the `usermod -p` line in `netvm.sh` (#12), installer
  secrets (#3). Those are release blockers tracked in `../state.md`, not host
  requirements.
- Anything tracked in git. If it is in the repo, it is not host configuration.
