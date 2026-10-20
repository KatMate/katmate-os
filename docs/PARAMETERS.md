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

**Frozen** for the alpha: MAC and CID. **Not frozen**: memory and vCPUs.
**Since cu3 (2026-10-18)** slot, LINK_ID and socket path are per run: the
alpha's frozen slot rows (01–04, LINK_ID 201–204) end there (orchestrator's
ruling 1 on cu3).

## Conventions

- One row per parameter kind. The *alpha source* cell carries every
  instance's value.
- *Gate* names a gate by its recorded name and status, or a session's
  observation as an observation. A row whose parameter no check covers says
  so.
- Machine state (MainPIDs, inodes, what is running) is not kept here. It
  belongs in [`docs/DEV-ENV.md`](DEV-ENV.md).

## The table

Instances: `app_web`, `app_personal` and `app_work`, on the primary netVM
`netvm`, and the offline `app_vault`, on MINIS. Read back on 2026-10-02
(session `ai1`). The hostname row, and the pool size in the memory row, were
read back the same day by session `ai2`, `app_work`'s values by session `ai3`,
with all three AppVMs running at once, and `app_vault`'s by session `ai4`,
with all four running at once. **Since `ai6` (2026-10-03) every start and
stop goes through `katmate-launch`** (`/usr/lib/katmate/katmate-launch`, the
launch daemon's alpha precursor, ADR-029's note of 2026-10-03). It writes the
owner and issues NETCFG, and the launcher calls it. Through cu2 it did so
from a static table whose literals were this file's values (R156); since cu3
it claims the slot from `katmate-alloc` and takes the slot's faces from
`katmate-generate-env --faces`, and no table remains. Where a row says *by hand*
below, that was the form through `ai5`. An offline AppVM has no slot, LINK_ID, MAC,
socket path or owner: those rows say *none* for it, because the
`katmate-app-offline@` template carries no network device (ADR-030 §2).
**`app_sandbox`** (CID 25, layer `web`, on `netvm`) was added on 2026-10-06
in a cloud session. Each of its values below is marked *planned 2026-10-06,
not read back*, except its CID, read back from T1 on 2026-10-17. They come from operator rulings and the tree, not from the
machine, and the MINIS session that first starts it reads them back.

| Parameter | Alpha source | Target source | ADR | Gate |
|---|---|---|---|---|
| **Slot** (`KM_SLOT`), and the guest address derived from it | **Per run since cu3.** The slot of the netVM's pool whose `owner` names the instance, found by `katmate-generate-env` across all sixteen slots. At a routed start `katmate-launch` claims it through `katmate-alloc`: the lowest slot that is free or stale, never `05` or `06` (reserved); it is released at the stop. Every routed instance, the shipped ones included, takes it this way; no T1 key carries a slot (ADR-037 R63). `app_vault` → none (offline). The address is `10.100.1.(16+k)`, and netVM's slot MAC `52:54:01:00:00:kk`, both computed only in the generator; `katmate-launch` reads them from `katmate-generate-env --faces <netvm> <kk>` for the NETCFG ADD it issues before the start, and compares the projection's `KM_SLOT` and `KM_GUEST_ADDR` with its claim after it. Through cu2 the slots were fixed: `app_web` 01, `app_personal` 02, `app_work` 03, `app_sandbox` 04, from `katmate-launch`'s static table | The launch daemon, by claiming the slot (build order step 3b); `katmate-alloc` is the library it links | [ADR-035](adr/ADR-035.md) §4, §5; [ADR-037](adr/ADR-037.md) R62, R63; [ADR-038](adr/ADR-038.md) §10 | ADR-037 G5, PASS (R95), slot 01 only. ai1, observed: both slots at once, each guest configured from its own slot (`net: eth0 10.100.1.18/32 via 10.100.1.1`). ai3, observed: three slots at once (`net: eth0 10.100.1.19/32 via 10.100.1.1`), and a flow from `.19` carrying `mark=4` in netVM's conntrack. ai6, observed: at every routed start (four, from the shell and the menu), `katmate-launch`'s read-back found the generator's `KM_GUEST_ADDR` and `KM_SLOT` equal to its literals (`.17`/`01`, `.18`/`02`, `.19`/`03`). The refusal on a difference ran only in the Acer extract. cu3, observed (2026-10-18, MINIS): `app_web` alone claimed `00` and its read-back gave `KM_GUEST_ADDR=10.100.1.16 KM_SLOT=00`; with `app_web` on `00`, the test instance `app_cu3` claimed `01` (`.17`), both running at once; each stop removed its owner. The operator saw each foot window. The stale-owner reclaim ran only in `cargo test` |
| **LINK_ID** | `owner`'s `LINK_ID=` (typed by the generator, not projected) and the NETCFG ADD `ping-client netcfg-add <netvm-cid> <id> 52:54:01:00:00:<kk> <peer> 100`. **Since cu3** an opaque counter with no slot structure (ADR-035 §6): `katmate-alloc` hands out the next value at every claim, under the pool lock, from `/run/katmate/link/<netvm>/link-id` (tmpfs), starting at `1000` and always above every value the counter or a present owner has carried, so it never coincides with the retired `201`–`206`. `katmate-launch` issues the ADD before the start and the REMOVE after the stop, through `/usr/lib/katmate/ping-client`, with netVM's CID read from its T1 file; a stale owner's LINK_ID gets its REMOVE before its slot is reclaimed. `app_vault` → none. Through cu2: `app_web` `201`, `app_personal` `202`, `app_work` `203`, `app_sandbox` `204`, from the static table | The launch daemon, issuing NETCFG (build order step 3b) | [ADR-023](adr/ADR-023.md), [ADR-025](adr/ADR-025.md), [ADR-035](adr/ADR-035.md); ADR-037 R70, R79 | ADR-035 G4, PASS (R117), on slot 01. ai1, observed: REMOVE 202 flushed `mark=3` and left slot 01's record, route and `mark=2` flow in place. ai6, observed: `katmate-launch`'s ADD 201–203 and REMOVE 201–203 each answered OK (journal tag `katmate-launch`). Their effect in netVM was not read. cu3, observed: ADD and REMOVE `1000`, `1001` and `1002` answered OK; the counter read `1002` after the session. Their effect in netVM was not read |
| **CID** | T1 `cid`. `app_web` → `21`, `app_personal` → `22`, `app_work` → `23`, `app_vault` → `24`, `app_sandbox` → `25` (read back from T1, `/etc/katmate/vm/app_sandbox.toml`, 2026-10-17) | T1, created by the installer for the default AppVMs (build order step 6); a user-created AppVM's CID comes from `cid::next` (`katmate-alloc`'s library, taken by `katmate-vm create` since cu4), the lowest free in **32–99** (cu3 ruling 5), and is never changed afterwards. The launch daemon allocates `"auto"` for disposables | [ADR-015](adr/ADR-015.md), [ADR-017](adr/ADR-017.md), [ADR-022](adr/ADR-022.md), [ADR-032](adr/ADR-032.md) §3 | **Uniqueness since cu3 (#58):** `katmate-launch` runs `katmate-alloc cid check` over every T1 file (read with `km_t1_read`) at every launch and refuses on a CID carried twice, on a reserved row of the allocation map (30) or on 0–2; a CID ≥ 100 is a warning (ADR-017's manual pin, which `katmate-cid` does not see). cu3, observed: `katmate-launch --cid-check` exit 0 over the six T1 files on MINIS. `tools/validate-properties.fish` still has no uniqueness rule. The generator checks a CID's band |
| **Identity MAC** (`KM_MAC_INT`) | Derived, never authored: `52:54:00` + `sha256(<instance>)[0:3]` in `katmate-generate-env`. `app_web` → `52:54:00:6f:19:35`, `app_personal` → `52:54:00:f0:e9:bf`, `app_work` → `52:54:00:b4:ec:6c`, `app_sandbox` → `52:54:00:6a:91:45` *(planned 2026-10-06, not read back)*; computed with the generator's own expression, `printf '%s' app_sandbox \| sha256sum \| cut -c1-6`, which gives the recorded values for `app_web` and `app_personal` too. `app_vault` → none: the generator derives a MAC only for an AppVM with a `netvm` | The same derivation. Nothing is hand-set | ADR-025 (revision note); ADR-035 §2, §9 | ai1, observed: both MACs in netVM's neighbour table on their own slot (`km01`, `km02`) |
| **Socket path** | The `katmate-app-routed@` template, from `KM_NETVM` and `KM_SLOT`: `/run/katmate/link/<netvm>/<kk>/appvm` for the slot claimed for that run (row *Slot*), peered with that slot's `netvm`. Through cu2 fixed per instance (`01`–`04`). `app_vault` → none | The same template | ADR-035 §5 | ADR-035 G5a taken, G5b partly taken. ai1, observed: both `appvm` sockets bound at once, each by its own AppVM's QEMU, and each unlinked at its unit's stop. ai4, observed: `app_vault`'s QEMU argv carries 0 `-netdev`, 0 `virtio-net` and 0 `/run/katmate/link` words, against 1 of each on the three routed AppVMs |
| **T1 file** | `/etc/katmate/vm/<instance>.toml`, `root:root 0644`, installed by hand from the ignored staging tree `local/etc/katmate/vm/` ([HOST-CONFIG.md](HOST-CONFIG.md) § 10). `app_web.toml` `be542506…`, `app_personal.toml` `042750bf…`, `app_work.toml` `bd7f7acc…`, `app_vault.toml` `675a2614…` (`netvm = ""`). `app_sandbox.toml`: none on MINIS yet; its template is `installer/t1/app_sandbox.toml.in` *(planned 2026-10-06, not read back)* | The installer, which may create a T1 file and never overwrite one it did not create (build order step 6). **Installer (alpha)** since 2026-10-05: from `installer/t1/*.toml.in`, which carry this file's values (R10) | ADR-015, [ADR-030](adr/ADR-030.md), ADR-032 §1 | The generator's parse at every start. `tools/validate-properties.fish`, exit 0, over the staging directory |
| **Home LV** | `vm_<instance>_home` in `vg0`, made by `katmate-vm` (`create`, or `provision` from the installer) since cu4; the ones below by hand. `vm_app_web_home`: 10G **linear** (2026-06-27). `vm_app_personal_home`: 10G **thin in `vm_pool`** (2026-10-02). `vm_app_work_home`: 10G thin in `vm_pool` (2026-10-02). `vm_app_vault_home`: 10G thin in `vm_pool` (2026-10-02). `vm_app_sandbox_home`: none yet; the installer makes it, 10G thin in `vm_pool` *(planned 2026-10-06, not read back)*. The form of record is in [`docs/DEV-ENV.md`](DEV-ENV.md) | **`katmate-vm`** (`create`; the installer through `provision`): `vm_<instance>_home`, 10G thin in `vm_pool`, ext4, `user/` `1000:1000 0700` (operator ruling R7, 2026-10-05). `katmate-vm`'s constants are the only holder of `10G` and `vm_pool`. Not assigned by any ADR | [ADR-010](adr/ADR-010.md), [ADR-014](adr/ADR-014.md) | `katmate-activate-lvs` at start (both). `vm_app_web_home` being linear disagrees with ADR-010 |
| **Instance delta** | `/var/lib/katmate/instances/<instance>.qcow2`, `root:root 0644` (MINIS corrected 2026-10-20; was `host:host`), made by `katmate-vm` (`create`, or `provision` from the installer) since cu4: `qemu-img create -f qcow2 -F raw -b /dev/<layer's APP_LV> <delta> 10G`. The ones below were made by hand, `-b /dev/vg0/vm_app_<manifest>`. `app_web`, `app_personal` → `vm_app_web`, and `app_sandbox` → `vm_app_web` *(planned 2026-10-06, not read back)*; `app_work` → `vm_app_office`; `app_vault` → `vm_app_vault` | **`katmate-vm`** (`create`; the installer through `provision`): the same `qemu-img create`, `root:root 0644` (operator ruling R7, 2026-10-05); its constants are the only holder of `10G`. Not assigned by any ADR; `katmate-update` recreates deltas at a re-bake | ADR-010, ADR-014, ADR-032 §7 | `katmate-check-image` at start |
| **Owner file** | `/run/katmate/link/<netvm>/<kk>/owner`, `root:root 0644`, `KATMATE_OWNER_VERSION=1`, `INSTANCE=`, `LINK_ID=`, written by hand. On tmpfs, so **a host reboot loses it** and the next start fails closed. `app_vault` takes none: the generator's owner lookup runs for `app-routed` only. **Since ai6** written and removed by `katmate-launch`; **since cu3** through `katmate-alloc`, under one `flock` on `/run/katmate/link/<netvm>/alloc.lock` held across read and write, written to a temporary file and `rename(2)`d without replacing (`RENAME_NOREPLACE`), mode 0644, and removed at the stop only when it names that instance with that LINK_ID. A leftover of the same instance is kept; an owner naming another instance is never overwritten or released. **Stale:** an owner whose `katmate-app-routed@<instance>.service` is not `active`, `activating`, `deactivating` or `reloading` (`systemctl is-active`); `katmate-launch` issues NETCFG REMOVE for its LINK_ID, then `katmate-alloc` removes it if it is still the same owner and still stale | The launch daemon (build order step 3b) | ADR-037 R63, R78 | **The generator's refusals: none observed.** `katmate-generate-env` refuses a missing, foreign-owned, writable or malformed owner, but that is code, read, not a recorded observation. ai6, observed: the acceptance path, at four routed starts on owners written by `katmate-launch` (`root:root 644`, three lines). `katmate-launch`'s own refusals (foreign owner, symlink, absent slot directory) ran only in the Acer extract. cu3, observed: owners written by `katmate-alloc` (`root:root 644`, three lines) accepted by the generator at three routed starts and removed at three stops. `katmate-alloc`'s refusals (foreign owner, symlink, writable or malformed owner, reserved slot, stale reclaim) ran only in `cargo test` |
| **Hostname** | `km.name=%i` on the kernel command line, in the `-append` of both AppVM templates, `katmate-app-routed@` and `katmate-app-offline@`. katmate-init sets it with `sethostname(2)` before the network step. `app_web` → `app_web`, `app_personal` → `app_personal`, `app_work` → `app_work`, `app_vault` → `app_vault`, `app_sandbox` → `app_sandbox` *(planned 2026-10-06, not read back)*. *"Routed AppVMs only today"*, which this row said until 2026-10-02, is resolved: the offline template ships with `km.name=%i` (R135) | The launch daemon, which passes the instance name it starts | [ADR-038](adr/ADR-038.md) (revision note, R125) | ai2, observed: `[katmate-init] hostname: app_web` and `hostname: app_personal` on the consoles, and the operator read `user@app_web:~$` and `user@app_personal:~$` in `foot`. ai3, observed: `hostname: app_work`, and the operator read `user@app_work:~$`. ai4, observed: `hostname: app_vault` beside `net: offline (no km.ip), lo up`, and the operator read `user@app_vault:~$`. Unit tests: `init/tests/run.sh`, group `name` |
| **Memory, vCPUs** (not frozen) | T1 `mem`, `vcpus`. `app_web` → `4G`, `2`. `app_personal` → `2G`, `2`. `app_work` → `2G`, `2`. `app_vault` → `2G`, `2`. `app_sandbox` → `2G`, `2` *(planned 2026-10-06, not read back)*. **Why 2G:** each AppVM's memory comes from the host's hugepage pool, which on MINIS is 4096 × 2 MiB = 8 GiB, set by `/etc/sysctl.d/hugepages.conf`. Two AppVMs at 4G would fill it exactly, with no margin (ruling of 2026-10-02). **Since `ai2` the pool is 6144 × 2 MiB = 12 GiB** (R126, [HOST-CONFIG.md](HOST-CONFIG.md) § 6), which holds `web` 4G plus three AppVMs at 2G. ai3 ran `app_web`, `app_personal` and `app_work` together, which is 8 GiB committed, with 250 of 6144 pages in use after the three boots (pages are taken on fault). ai4 ran all four together, 10 GiB committed, with 316 of 6144 pages in use after the four boots. **Since 2026-10-05 (operator ruling, part 3)** the AppVM templates use `memory-backend-memfd,share=on` and take no hugepages; the pool argument above no longer bounds `mem`, and the installer's floor is 16 GB of host RAM. UNVERIFIED until the MINIS gate | T1 | ADR-030 | None |
| **Apps offered per instance** (added by `ai6`; data since cu2) | The `run` list of the layer the instance's T1 `manifest` names (`manifests/<layer>.toml`, ADR-043 §5–6). The build writes it twice from one list: `RUN=` in `app-<layer>.meta` (T2), which `katmate-launch` checks and `installer/gen-desktop-entries` reads for the launcher's entries, and `/etc/katmate/run-whitelist` in the layer, which vm-agent checks. `web` (`app_web`, `app_personal`, `app_sandbox`; the browser is how tarballs are downloaded) → `firefox-esr`, `foot`, `pcmanfm`; `office` (`app_work`) → `libreoffice`, `foot`, `pcmanfm`; `vault` (`app_vault`) → `keepassxc`, `foot`, `pcmanfm` | The manifest's author: the release for T3 layers, the user for T1 ones (ADR-043 §6); a change is a rebuild of that layer | [ADR-043](adr/ADR-043.md) §5–6; [ADR-021](adr/ADR-021.md) (note of 2026-10-17); [ADR-039](adr/ADR-039.md) | cu2: written and tested on fixtures on the Acer, not yet run on a host. Before cu2, ai6, observed: every menu item the operator clicked opened its window, cold and warm (`app_web` Firefox, Files, Terminal; `app_personal` Terminal, Firefox; `app_work` LibreOffice; `app_vault` KeePassXC), with the waybar menu that fz1 replaced. The generated entries are not yet observed in use |

## Allocation map

Every netVM slot, and every CID in use, reserved or used by a spike, so that
a spike's choice of a "free" value is visible here. **The map is updated
whenever a spike or an instance takes a slot or a CID, in the same commit.**
Read on 2026-10-18 (session `cu3`). **Since cu3 no instance holds a slot
between runs:** every routed AppVM takes the lowest free slot of its netVM's
pool at start, `05` and `06` excepted, and releases it at stop (row *Slot*).
The live slot tree on MINIS held no `owner` in any slot after cu3's stops;
the pool directory also holds `alloc.lock` and `link-id` (`1002`).

| Slot | LINK_ID | CID | Holder | Status | Source |
|---|---|---|---|---|---|
| none (hosts the pool) | none | `3` | `netvm` | shipped | T1 `/etc/katmate/vm/netvm.toml` (`cid = 3`); the running QEMU's `guest-cid=3`, binding all sixteen `netvm` nodes |
| `00` | per run | per run | any routed AppVM | pool | Live slot tree: no owner. ADR-035's gates of September 2026 bound fixtures on it; cu3's A3 and A4 ran `app_web` on it (LINK_ID `1000`, `1001`), released |
| `01` | per run | per run | any routed AppVM | pool | Live slot tree: no owner. `app_web`'s fixed slot through cu2 (LINK_ID `201`); cu3's A4 ran `app_cu3` on it (LINK_ID `1002`), released |
| `02` | per run | per run | any routed AppVM | pool | Live slot tree: no owner. `app_personal`'s fixed slot through cu2 (LINK_ID `202`) |
| `03` | per run | per run | any routed AppVM | pool | Live slot tree: no owner. `app_work`'s fixed slot through cu2 (LINK_ID `203`) |
| `04` | per run | per run | any routed AppVM | pool | Live slot tree: no owner. `app_sandbox`'s fixed slot through cu2 (LINK_ID `204`) |
| `05` | `205` | none | `win_w1`, the Windows guest of w1b and w2 (no vsock device). Kept: the guest `vm_win_w1` and its leftovers (`state.md` § *Leftovers*) | reserved | `w1b-report.md` (NETCFG ADD/REMOVE 205, released 2026-10-13); `w2-report.md` (taken again, released 2026-10-15). Reserved until the leftovers are removed |
| `06` | `206` | none | Layer builder (no vsock device) | reserved | cu1 ruling, 2026-10-17; [ADR-043](adr/ADR-043.md) |
| `07` | per run | per run | any routed AppVM | pool | Live slot tree: no owner. `cu1_web`, cu1's H3 instance, used it with LINK_ID `207` and CID `26`, released 2026-10-16 (`cu1-report.md` §§ 25, 28) |
| `08` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `09` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `0a` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `0b` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `0c` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `0d` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `0e` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| `0f` | per run | per run | any routed AppVM | pool | Live slot tree: no owner |
| per run | per run | `21`, `22`, `23`, `25` | `app_web`, `app_personal`, `app_work`, `app_sandbox` | shipped | T1 `app_web.toml`, `app_personal.toml`, `app_work.toml`, `app_sandbox.toml` (`katmate-alloc cid check` input on MINIS, cu3) |
| none (offline) | none | `24` | `app_vault` | shipped | T1 `app_vault.toml` (`cid = 24`, `netvm = ""`) |
| none | none | `32`–`99` | AppVMs the user creates (cu4's `create`, `katmate-alloc cid next`) | user range | cu3 ruling 5. `32` was `app_cu3`, cu3's A4 instance (`web`, slot `01` for one run), dev, released 2026-10-18 (`cu3-report.md`): T1 file, home LV and delta removed |
| none (dev link `/run/katmate-dev/w2-link`, not a netVM slot) | none | `30` | `gw_w2`, w2's gateway. Kept: `vm_app_gw_w2`, `vm_app_gw_w2b`, `vm_gw_w2_home`, both gateway deltas, `~/katmate-dev/w2/` (`state.md` § *Leftovers*) | reserved | `w2-report.md` (`run-gw.sh`, CID 30; released 2026-10-15). Reserved until the leftovers are removed |

T1 files are those under `/etc/katmate/vm/` on MINIS; report files are outside
the repository. CIDs from before the current CID ranges
([ADR-022](adr/ADR-022.md)) are not tracked.
