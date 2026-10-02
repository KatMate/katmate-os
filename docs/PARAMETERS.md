# Parameters

Every per-instance parameter the alpha integration sets by hand, where it is
set today, and which component will own it later. Filled during integration,
one AppVM at a time, never written up front
([ROADMAP.md](../ROADMAP.md) § *Alpha integration*). The table is complete
when every row's target source exists. That is the integration's stopping
rule.

## What this file is for

The alpha integration feeds hand-written static parameters into the existing
architecture. That hand-written configuration also serves as the output
specification for the launch daemon. This file names each parameter once and
says where its value lives now (*alpha source*), which component writes it
once the alpha is over (*target source*), the decision that defines it
(*ADR*), and the observation that covers it (*gate*). **Values are read back
from the machine, never copied from a brief.**

**Frozen** for the alpha: slot, MAC, CID and socket path. **Not frozen**:
memory and vCPUs.

## Conventions

- One row per parameter kind. The *alpha source* cell carries every
  instance's value.
- *Gate* names a gate by its recorded name and status, or a session's
  observation as an observation. A row whose parameter no check covers says
  so.
- Machine state (MainPIDs, inodes, what is running) is not kept here. It
  belongs in [`state.md`](../state.md) § *Live state*.

## The table

Instances: `app_web` and `app_personal`, on the primary netVM `netvm`, on MINIS.
Read back on 2026-10-02 (session `ai1`).

| Parameter | Alpha source | Target source | ADR | Gate |
|---|---|---|---|---|
| **Slot** (`KM_SLOT`), and the guest address derived from it | The slot of `netvm`'s pool whose `owner` names the instance, found by `katmate-generate-env` across all sixteen slots. `app_web` → `01` (`km.ip=10.100.1.17`). `app_personal` → `02` (`km.ip=10.100.1.18`). The address is `10.100.1.(16+k)`, computed only in the generator | The launch daemon, by writing the owner (build order step 3b) | [ADR-035](DECISIONS.md#adr-035) §4, §5; [ADR-037](DECISIONS.md#adr-037) R62, R63; [ADR-038](DECISIONS.md#adr-038) §10 | ADR-037 G5, PASS (R95), slot 01 only. ai1, observed: both slots at once, each guest configured from its own slot (`net: eth0 10.100.1.18/32 via 10.100.1.1`) |
| **LINK_ID** | `owner`'s `LINK_ID=` (typed by the generator, not projected) and the NETCFG ADD issued by hand with `ping-client netcfg-add 3 <id> 52:54:01:00:00:<kk> <peer> 100`. `app_web` → `201`, `app_personal` → `202` | The launch daemon, issuing NETCFG (build order step 3b) | [ADR-023](DECISIONS.md#adr-023), [ADR-025](DECISIONS.md#adr-025), [ADR-035](DECISIONS.md#adr-035); ADR-037 R70, R79 | ADR-035 G4, PASS (R117), on slot 01. ai1, observed: REMOVE 202 flushed `mark=3` and left slot 01's record, route and `mark=2` flow in place |
| **CID** | T1 `cid`. `app_web` → `21`, `app_personal` → `22` | T1, created by the installer for the default AppVMs (build order step 6). The launch daemon allocates `"auto"` for disposables | [ADR-015](DECISIONS.md#adr-015), [ADR-017](DECISIONS.md#adr-017), [ADR-022](DECISIONS.md#adr-022), [ADR-032](DECISIONS.md#adr-032) §3 | **None for uniqueness.** The generator checks a CID's band, and nothing refuses two T1 files carrying one CID |
| **Identity MAC** (`KM_MAC_INT`) | Derived, never authored: `52:54:00` + `sha256(<instance>)[0:3]` in `katmate-generate-env`. `app_web` → `52:54:00:6f:19:35`, `app_personal` → `52:54:00:f0:e9:bf` | The same derivation. Nothing is hand-set | ADR-025 (revision note); ADR-035 §2, §9 | ai1, observed: both MACs in netVM's neighbour table on their own slot (`km01`, `km02`) |
| **Socket path** | The `katmate-app-routed@` template, from `KM_NETVM` and `KM_SLOT`: `/run/katmate/link/netvm/01/appvm` and `/run/katmate/link/netvm/02/appvm`, each peered with that slot's `netvm` | The same template | ADR-035 §5 | ADR-035 G5a taken, G5b partly taken. ai1, observed: both `appvm` sockets bound at once, each by its own AppVM's QEMU, and each unlinked at its unit's stop |
| **T1 file** | `/etc/katmate/vm/<instance>.toml`, `root:root 0644`, installed by hand from the ignored staging tree `local/etc/katmate/vm/` ([HOST-CONFIG.md](HOST-CONFIG.md) § 10). `app_web.toml` `be542506…`, `app_personal.toml` `042750bf…` | The installer, which may create a T1 file and never overwrite one it did not create (build order step 6) | ADR-015, [ADR-030](DECISIONS.md#adr-030), ADR-032 §1 | The generator's parse at every start. `tools/validate-properties.fish`, exit 0, over the staging directory |
| **Home LV** | `vm_<instance>_home` in `vg0`, made by hand. `vm_app_web_home`: 10G **linear** (2026-06-27). `vm_app_personal_home`: 10G **thin in `vm_pool`** (2026-10-02). The form of record is in `state.md` § *Live state* | Not assigned by any ADR | [ADR-010](DECISIONS.md#adr-010), [ADR-014](DECISIONS.md#adr-014) | `katmate-activate-lvs` at start (both). `vm_app_web_home` being linear disagrees with ADR-010 |
| **Instance delta** | `/var/lib/katmate/instances/<instance>.qcow2`, `host:host 0644`, made by hand: `qemu-img create -f qcow2 -F raw -b /dev/vg0/vm_app_web <delta> 10G` | Not assigned by any ADR; `katmate-update` recreates deltas at a re-bake | ADR-010, ADR-014, ADR-032 §7 | `katmate-check-image` at start |
| **Owner file** | `/run/katmate/link/<netvm>/<kk>/owner`, `root:root 0644`, `KATMATE_OWNER_VERSION=1`, `INSTANCE=`, `LINK_ID=`, written by hand. On tmpfs, so **a host reboot loses it** and the next start fails closed | The launch daemon (build order step 3b) | ADR-037 R63, R78 | **None observed.** `katmate-generate-env` refuses a missing, foreign-owned, writable or malformed owner, but that is code, read, not a recorded observation |
| **Memory, vCPUs** (not frozen) | T1 `mem`, `vcpus`. `app_web` → `4G`, `2`. `app_personal` → `2G`, `2`. **Why 2G:** each AppVM's memory comes from the host's hugepage pool, which on MINIS is 4096 × 2 MiB = 8 GiB, set by `/etc/sysctl.d/hugepages.conf`. Two AppVMs at 4G would fill it exactly, with no margin (ruling of 2026-10-02) | T1 | ADR-030 | None |
