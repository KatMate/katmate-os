# Architecture Decision Records

Format: context → decision → consequences. Status: **Accepted**, **Proposed**
(open question under evaluation), or **Superseded**. Open questions enter as
Proposed and are promoted on decision. Dates are approximate where
reconstructed; backfill from git history where it matters.

---

## ADR-001 — Compartmentalization via QEMU/KVM MicroVMs, not Xen

**Status:** Accepted (project inception)

**Context:** Qubes OS proves the compartmentalization model but carries the
Xen ecosystem: heavy stack, Fedora-centric tooling, demanding UX aimed at
power users.

**Decision:** Standard Linux stack — QEMU/KVM MicroVMs on an Arch host, with
broad-user usability as a first-class goal.

**Consequences:** Simpler codebase, easier kernel experimentation, wider
hardware support. We give up the mature Qubes ecosystem (qrexec, gui-daemon)
and must build our own template, agent and policy layers.

---

## ADR-002 — Arch Linux host, Debian stable guests

**Status:** Accepted (project inception)

**Context:** The host is a developer-facing TCB; guests are user-facing
appliances.

**Decision:** Arch for the host (fresh, flexible, pacman ecosystem); Debian
stable for guests (stability, predictable backports, ABI stability, small
footprint).

**Consequences:** Two package ecosystems to manage; version skew between them
must be handled explicitly (see ADR-008).

---

## ADR-003 — AF_VSOCK as the only host↔guest channel

**Status:** Accepted (v0.1)

**Context:** Any network channel between host and guest expands the attack
surface and complicates firewalling.

**Decision:** All control, file transfer and GUI traffic crosses AF_VSOCK
exclusively. No TCP between host and guests; no guest-to-guest channel.

**Consequences:** vm-agent and waypipe must speak vsock; the firewall story
stays trivial (vsock bypasses netfilter); inter-VM data flow only via the host.

---

## ADR-004 — Host kernel: `linux-hardened` from the Arch repo

**Status:** Accepted (2026)

**Context:** The host is the TCB and benefits from hardening, but a custom
host kernel is a permanent maintenance burden. `linux-hardened` is maintained
in the Arch repo with pacman integration.

**Decision:** `linux-hardened` as the host kernel. A custom host kernel is
justified only if a hard requirement appears that hardened cannot satisfy —
in that case: Arch LTS sources + `katmate-host.config` delta, maintained in git.

**Consequences:** io_uring is disabled (`kernel.io_uring_disabled = 2`) →
QEMU launch scripts use `aio=threads` instead of `aio=io_uring`.
Suspend/resume currently regresses on one development machine (under
investigation — see [state.md](../state.md)). Hardening sysctls may surface
further incompatibilities; each gets recorded here.

---

## ADR-005 — Guest kernel: custom build from Debian LTS sources

**Status:** Accepted (2026)

**Context:** Guests are appliances. A rolling guest kernel would mean a
potentially broken guest on any update — unacceptable for the broad-user UX
goal.

**Decision:** Custom MicroVM-optimized kernel built from Debian LTS sources
(`vmlinuz-katmate-microvm-amd64-6.12.x`): virtio-blk/net/vsock, ext4, tmpfs,
namespaces, cgroups; fast boot, low memory, minimal config surface.

**Consequences:** Kernel updates ride Debian security backports and are
shipped via base image rebuilds (ADR-007); high ABI stability for modules.

---

## ADR-006 — systemd-boot instead of GRUB

**Status:** Accepted (installer v0.3 rewrite)

**Context:** GRUB (used through v0.1) is heavyweight for a single-entry,
UEFI-only appliance boot path.

**Decision:** systemd-boot with `timeout 0` and `editor no` — boot straight
into the OS, no interactive kernel command-line editing.

**Consequences:** UEFI-only (acceptable: all reference hardware is UEFI);
simpler boot chain; docs and installer verification updated accordingly.

---

## ADR-007 — Versioned immutable base image + per-AppVM overlays

**Status:** Accepted (2026)

**Context:** Users must never administer templates, kernels or forwarding
components. System updates must not endanger user data.

**Decision:** Immutable, versioned base image (`katmate-base-YYYYMMDD.img`)
containing OS + kernel + waypipe + vm-agent; AppVM overlays carry user data
only. `katmate-update` detects host/base version mismatches (triggered by a
pacman hook on the host) and rebuilds the base; overlays are recycled onto the
new base. The user receives a notification, no action required.

**Consequences:** Reproducible base builds become mandatory (pipeline:
ADR-011); strict system/data separation; update logic centralizes in one tool.

---

## ADR-008 — Waypipe version-locked host↔guest; guest builds from source

**Status:** Accepted (2026)

**Context:** Host (Arch) shipped waypipe 0.11.0, guest (Debian stable) 0.9.2.
The version skew produced a compression negotiation mismatch
(`header has 100 != own 200`) — refused connections and SIGSEGV crashes on
clipboard operations.

**Decision:** The guest builds waypipe from source, pinned to the host
version. Build gotchas (recorded so they stay solved): waypipe ≥ 0.11 is
partly Rust; `bindgen` is required or the lz4/zstd feature gates silently
resolve to `false`; the build wrapper passes `--frozen`, so `cargo fetch` must
run before `meson setup`. Recipe lives in
[ARCHITECTURE.md](ARCHITECTURE.md#guest-waypipe-build-part-of-the-base-image-pipeline).

**Consequences:** Waypipe becomes a version-locked base image component;
`katmate-update` enforces the lock (ADR-007). Clipboard guest↔host functional
since.

---

## ADR-009 — NetVM as the sole network-facing domain

**Status:** Accepted as target architecture (implementation: v0.3)

**Context:** Today WireGuard terminates on the host, which contradicts the
isolation model — the TCB carries the VPN and the network-facing surface.

**Decision:** A dedicated NetVM owns DHCP, DNS, VPN, firewalling and routing.
AppVMs receive connectivity exclusively through it. Host-side VPN is an
explicitly transitional state.

**Consequences:** Requires networking automation (v0.3); the migration path
must be kept documented so the transitional state does not fossilize.

---

## ADR-010 — Storage: three-level LVM-thin chain for system images, raw thin LVs for home

<!-- Abstract vocabulary: foundation / app / instance. Concrete LVM names
     (all_root, vm_tpl_*_root, vm_personal_overlay.qcow2) live in state.md. -->

**Status:** Accepted (2026); mechanism revised 2026-06 (was three-level qcow2
backing chain — see Revision note). Composition model: ADR-014.

**Context:** The open question was the exact storage mechanism for base images
and overlays (qcow2-with-backing vs overlayfs vs LVM-thin throughout) and where
the image store sits relative to the LVM thin pool. ADR-014 settled the
three-layer composition (base → app-type → instance); this ADR fixes the
mechanism for each layer.

**Decision:**

- **System images** use a three-level chain realised on **LVM thin volumes**:
  `foundation` (thin, RO) ← `app-<type>` (thin **snapshot** of `foundation`,
  RO-frozen) ← `instance-<name>` (RW delta, qcow2 backing = the app snapshot
  block device). The two read-only system layers are LVM thin volumes so that
  reads resolve through the thin pool in a single metadata lookup with no
  per-block backing-chain walk; the ephemeral writable delta stays qcow2
  because it is thin, sparse and cheap to discard/recreate per instance.
- **Persistent home data** uses a dedicated **raw thin LV per AppVM instance** —
  a direct block device, LVM-snapshottable, decoupled from the image chain so
  it survives base/app rebuilds (overlay recycling, ADR-007).
- **Placement:** all system thin volumes (`foundation`, each `app-<type>`)
  and per-instance home LVs live in the single thin pool provisioned by the
  installer. Per-instance qcow2 deltas are small files held alongside the
  launch config (host filesystem); they back onto the app snapshot block
  device.

**Why LVM-thin over a pure qcow2 chain (the revision):**

- A thin snapshot shares base blocks through the pool: `foundation` is stored
  once, every `app-<type>` snapshot adds only its own delta. Same
  single-foundation property the qcow2 chain promised.
- Reading an unmodified system block is one thin-pool lookup regardless of
  layer, versus an L2 lookup at each qcow2 level walking down to the foundation.
  For the read-mostly, cold-boot-heavy system partition (the browser image is
  re-read on every cold boot) this is the cheaper path — the design intent.
- qcow2 is retained exactly where it is ideal: the thin, throwaway, copy-up RW
  delta.

**Consequences:**

- Clean separation of immutable system (LVM-thin chain) from mutable user data
  (raw home LV); rebuilds touch only the chain.
- LVM thin provisioning gives sparse allocation across base, app snapshots and
  per-instance home LVs from one pool.
- App-layer build (ADR-011) is `lvcreate --snapshot` of `foundation` → install
  manifest into the snapshot → `lvchange --permission r` freeze. No nbd/flatten
  for the layering itself.
- `katmate-update` rebases: rebuild `foundation`, re-snapshot each app layer,
  recreate instance deltas; home LVs untouched.
- Cost vs pure linear RO: a thin snapshot adds a small metadata-indirection
  read cost over a flat linear LV. Accepted because block sharing across N app
  layers outweighs it once N > 2; for the present two domains the gain is
  latent, not yet material.

**Revision note (2026-06):** the original ADR-010 specified a three-level
**qcow2** backing chain (`foundation.qcow2` ← `app-<type>.qcow2` ←
`instance.qcow2`) stored on a filesystem-backed thin LV. Live inspection
confirmed the implemented and intended model is the LVM-thin hybrid above. The
qcow2-chain wording is superseded; ADR-011 and ADR-014 mechanism references
update accordingly (the *composition* in ADR-014 — three layers, two manifests,
RO/RW split — is unchanged; only the per-layer mechanism moves from qcow2 to
LVM-thin for the two RO layers).

---

## ADR-011 — Base image build pipeline: shell scripts orchestrated by Make

**Status:** Accepted (2026); layer mechanism revised 2026-06 to track ADR-010
(qcow2-chain → LVM-thin). Tooling decision (shell + Make over mkosi) unchanged.

**Context:** ADR-007 makes reproducible base builds mandatory; ADR-014 fixes
the artifact model (three layers: foundation ← app-type ← instance); ADR-010
fixes the mechanism (LVM-thin for the two RO layers, qcow2 for the RW delta).
The remaining question was tooling. `mkosi` was evaluated: its `BaseTrees=`
expresses the layer model declaratively and it handles partitioning/bootstrap
implicitly, but it adds a dependency and ties the build to systemd-tooling
behaviour and release tempo — opacity that runs against revisability, which for
a TCB is a first-order property (and against the stated development philosophy:
the simplest fully-scripted, diffable thing).

**Decision:** POSIX/bash build scripts orchestrated by a `Makefile`, one target
per layer. Layers are LVM thin volumes (ADR-010), not qcow2 files.

- **Foundation** (`make foundation`): create a thin LV, `debootstrap` a Debian
  rootfs into it (mount the LV, bootstrap, bind-mount, chroot), install the
  custom MicroVM kernel, waypipe 0.11.0 (source build, ADR-008) and vm-agent
  in-image, then `lvchange --permission r` to freeze it read-only. This is the
  single shared base.
- **App-`<type>` layers** (`make app-<type>`): `lvcreate --snapshot` of the
  frozen foundation thin LV (a thin snapshot — shares base blocks through the
  pool, adds only its own delta), mount it, chroot, install the manifest
  package set, then `lvchange --permission r` to RO-freeze the snapshot. No
  nbd, no qemu-img, no flatten — the thin snapshot relationship is what stores
  the foundation once and keeps the chain three-level.
- **Instance** (deploy-time, not a build target): `qemu-img create -f qcow2
  -F raw -b /dev/<vg>/<app-snapshot>` — a thin qcow2 RW delta backing onto the
  frozen app snapshot block device. Discarded/recreated per instance.
- All mounts/bind-mounts, snapshot activation and teardown are explicit, with
  `trap` cleanup — every command on screen, nothing implicit.
- **Reproducibility:** apt sources pinned to a `snapshot.debian.org` timestamp
  and package versions pinned per manifest, so a rebuild from the same inputs
  yields the same foundation and app layers.

**Consequences:**

- Build dependencies: `lvm2`, `util-linux`, `coreutils`, `debootstrap`,
  `debian-archive-keyring`, `make` (plus the waypipe/kernel build toolchain for
  the foundation step). `qemu-utils` only for the deploy-time delta, not for
  layering. No build-time runtime stack.
- More lines than a declarative tool, but bootstrap, snapshot and
  package-install steps are auditable line by line — the intended trade for a
  TCB.
- App-layer rebuild is cheap: drop the old snapshot, re-snapshot the
  (rebuilt or unchanged) foundation, reinstall the manifest. `katmate-update`
  drives this on a foundation/waypipe/kernel security update.
- Per-instance home stays a separate raw thin LV (ADR-010), untouched by
  foundation/app rebuilds.
- Realizes the pipeline that ADR-014 and ADR-010 depend on.
- The deploy-time instance step reads its parameters (`cid`, `network`,
  `persistence`, `disposable`, `reset_on_shutdown`) from the per-instance
  `properties.toml` (ADR-015).

**Revision note (2026-06):** the original ADR-011 layered via
`qemu-img create -f qcow2 -F qcow2 -b <foundation>` + `qemu-nbd` + chroot on
qcow2 files. With ADR-010 moving the two RO layers to LVM thin volumes, the
layering mechanism becomes `lvcreate --snapshot` + chroot + `lvchange -pr`.
qcow2/nbd is no longer used for the build; qcow2 survives only as the
deploy-time instance delta. The mkosi-vs-shell tooling decision and the
reproducibility approach are unchanged.

**Cross-reference (2026-06):** the deploy-time instance step reads its
per-instance properties (CID, network, persistence, disposable,
reset_on_shutdown) from a `properties.toml` whose format is fixed in ADR-015.

---

## ADR-012 — Base image distribution model

**Status:** Proposed

**Question:** Local build on every machine vs centrally built and distributed
images for end users. Interacts with ADR-013 (signing) and the
reproducibility principle.

---

## ADR-013 — Base image signing & integrity verification

**Status:** Proposed

**Question:** Signature scheme and verification point for base images
(mandatory if ADR-012 lands on central distribution; useful even for local
builds as tamper evidence).

---

## ADR-014 — AppVM domain model & three-layer image composition

**Status:** Accepted (2026)

**Context:** The base image (ADR-007) deliberately carries no applications,
leaving open how applications reach an AppVM and how AppVMs differ from one
another. The design discussion conflated two separate concerns — what
*defines* a domain vs. which *applications* it runs. Slicing by application
(one app = one VM) multiplies VM count, RAM and management surface, against the
broad-usability goal (ADR-001); Qubes converged on trust-based domains for the
same reason. ADR-010 (storage mechanism) and ADR-011 (pipeline) cannot be
specified until this is settled.

**Decision:**

*Two independent axes.* A domain is defined by its **properties** — network
(none / via NetVM), persistence (persistent / ephemeral), identity (a logged-in
real identity, or none), disposability — **not** by its application set. The
application set follows from the domain's purpose.

AppVMs are sliced **by purpose/trust**, not by application. Default domain set:

| Domain | Network | Persistence | Identity | Manifest |
|---|---|---|---|---|
| vault | none | persistent | — | `vault` (keepassxc, file manager) |
| personal | via NetVM | persistent | yes | `web` (firefox-esr, foot, nautilus) |
| untrusted | via NetVM | persistent † | none | `web` |
| disposable | via NetVM | ephemeral | none | `web` |

† optional reset to the app-layer on shutdown; see consequences.

Four archetypes, **two manifests** — `personal` / `untrusted` / `disposable`
share one manifest and differ only in properties, which proves the two axes are
genuinely independent. Disposable is the single task-bound exception (open this
PDF, destroy), justified because it is tied to a *task*, not a binary.

*Three layers, realized as an LVM-thin chain (mechanism in ADR-010):*

| Layer | Contents | Shared by | Rebuild frequency | Owner |
|---|---|---|---|---|
| foundation | OS + kernel + waypipe + vm-agent (ADR-007) | all VMs | waypipe/kernel security update | `katmate-update`, automatic |
| app-layer | package set **per domain type** | all VMs of that type | rare (domain definition change) | manifest in git |
| overlay | user data | one instance | continuous | user |

Concretely (mechanism in ADR-010): `foundation` (LVM thin, RO) ← `app-<type>`
(LVM thin snapshot of foundation, RO-frozen) ← `instance-<name>` (qcow2 RW delta
backing onto the app snapshot). Persistent home data lives on a separate raw
thin LV, decoupled from the chain so it survives foundation/app rebuilds.
App-layers are **generated** from foundation + manifest (ADR-011), never
hand-curated.

**Consequences:**

- `katmate-update` tracks a **single** foundation → the automatic update path
  stays trivial (one rebuild, not N as a multi-base model would need).
- Customization surface = manifest (packages) + properties. Small and safe
  enough to later expose as GUI toggles (v0.4 → v1.0). Properties get a
  machine-readable per-instance format in ADR-015 (`properties.toml`).
- Per-role minimization preserved: a banking domain would carry only a browser,
  a dev domain only its toolchain.
- Resolves the **mechanism** in ADR-010 (three-level LVM-thin chain + raw thin
  LVs for home).
- Shapes ADR-011: the pipeline must build the foundation and each `app-<type>`
  image reproducibly from defined sources + manifests.
- Banking as a dedicated domain is a documented option, **not** a default until
  the broad-user era; for a single security-aware user, banking inside
  `personal` is sufficient.
- `untrusted` may optionally reset to its app-layer on shutdown (sits between
  disposable and personal); left as a per-deployment property, not baked in.

*Customization evolution* (tracks me → power users → broad):

- **me (first release):** two hardcoded manifests + properties in config files
  edited with `micro`.
- **power users:** documented manifest format + `katmate-vm create --from
  <manifest>` CLI.
- **broad users:** GUI over the same manifest backend.

**Cross-reference (2026-06):** the property axes defined here are given a
machine-readable, typed format (one `properties.toml` per instance) in ADR-015;
the manifest format (package set) is specified in ADR-011.

---

## ADR-015 — VM properties: machine-readable schema (TOML, per-instance)

**Status:** Accepted (2026-06)

**Context:** ADR-014 defines a VM domain by its *properties* (network,
persistence, identity, disposability) as an abstract model, and ADR-011
defines the build pipeline that consumes a *manifest* (package set). Between
them sat no machine-readable layer: properties lived only as a prose table,
leaving the deploy step (CID assignment, home-LV persistence, nft routing,
instance-delta lifecycle) without a defined input format. The loosely-
structured early config style is not typed enough to validate or to map
deterministically to QEMU arguments.

**Decision:** VM properties are expressed as **one `properties.toml` per
instance**, separate from the manifest — the two axes of ADR-014 (what
*defines* a domain vs. which *applications* it runs) stay independent in
storage as they are in the model.

*Format:* TOML. Human-editable with `micro`, typed (unlike the early
`key=value` style), comment-friendly (unlike JSON), and parseable from C via a
single-file library (`tomlc99`) with no build-time runtime stack — consistent
with the ADR-011 TCB constraint.

*Schema:*

| Key | Type | Values | Required | Default |
|---|---|---|---|---|
| `manifest` | string | manifest name (`vault`, `web`) | yes | — |
| `network` | enum | `none` \| `via-netvm` | yes | — |
| `persistence` | enum | `persistent` \| `ephemeral` | yes | — |
| `identity` | bool | — | yes | — |
| `disposable` | bool | — | yes | — |
| `cid` | int | fixed 4–8, or from the dynamic pool (≥100) | yes | — |
| `reset_on_shutdown` | bool | — | no | `false` |

`reset_on_shutdown` exists only for the `untrusted` archetype's optional
app-layer reset (ADR-014); `vault` / `personal` / `disposable` omit it and
take the default.

The four default archetypes express as:

| Instance | manifest | network | persistence | identity | disposable | reset_on_shutdown |
|---|---|---|---|---|---|---|
| vault | `vault` | `none` | `persistent` | `false` | `false` | — |
| personal | `web` | `via-netvm` | `persistent` | `true` | `false` | — |
| untrusted | `web` | `via-netvm` | `persistent` | `false` | `false` | `true` |
| disposable | `web` | `via-netvm` | `ephemeral` | `false` | `true` | — |

**Consequences:**

- The deploy step (ADR-011 pipeline) reads `properties.toml` and maps
  deterministically: `cid` → vsock CID; `network` → vsock/routing config + nft
  rules; `persistence` → whether the raw thin home LV is retained or discarded;
  `disposable` → instance-delta create/destroy lifecycle;
  `reset_on_shutdown` → app-layer reset on teardown.
- This ADR fixes the **format** only. ADR-011 remains the owner of pipeline
  mechanics; ADR-014 remains the owner of the domain model. Cross-referenced
  both ways.
- A lightweight validator (C with `tomlc99`, or fish) can later catch typos
  before deploy; not required until the schema sees broader use (power-user
  era, ADR-014 evolution).
- Customization surface stays manifest + `properties.toml`, both small enough
  to back a future GUI (ADR-014, v0.4 → v1.0).

**Revision note:** supersedes the loosely-structured early config style for VM
definition. Manifest format (packages) is specified separately in ADR-011.
