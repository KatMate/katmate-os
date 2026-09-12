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
version, inside the foundation chroot so it links against the foundation's own
libraries. Build gotchas (each cost a failed build on 2026-06-20, recorded so
they stay solved):

1. waypipe ≥ 0.11 is partly Rust — the build needs `cargo` + `rustc` +
   `bindgen` (meson errors out without `bindgen`).
2. The `with_lz4` / `with_zstd` features default to `auto`, which can silently
   build with `lz4: false`. Force `-Dwith_lz4=enabled -Dwith_zstd=enabled` so a
   missing lib fails loudly rather than yielding a binary that cannot talk to
   the host.
3. The `wrap-gbm` Cargo workspace member's `build.rs` calls `pkg-config gbm`
   and panics if absent — even with `-Dwith_gbm=disabled`. Install `libgbm-dev`
   to satisfy it; the feature stays off in the final binary.
4. The build wrapper passes `--frozen`, so `cargo fetch` must run before
   `meson setup` (else "attempting to make an HTTP request, but --frozen was
   specified").
5. The host runs waypipe with `-c lz4`; a guest binary with `lz4: false` drops
   the vsock connection — the reason features are forced in (2).

Recipe lives in
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
- **Reproducibility (deferred — see note):** the intent is apt sources pinned
  to a `snapshot.debian.org` timestamp and package versions pinned per
  manifest, so a rebuild from the same inputs yields the same foundation and
  app layers. This is **not yet applied**: the first foundation (2026-06-20) is
  built with a plain `debootstrap trixie` against current packages. The pin is
  added only once a rebuild pipeline (`katmate-update`) exists, where
  determinism actually matters.

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
  `properties.toml` (ADR-015). When `cid = "auto"`, the CID is allocated from
  the dynamic pool by the allocator defined in ADR-017.

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

**Build note (2026-06-20):** the first `foundation` was built and frozen on
MINIS (`vg0/vm_tpl_foundation`, 10G thin, RO): `debootstrap trixie` + vm-agent
+ waypipe 0.11.0 (source, `lz4`/`zstd` on), toolchain purged before freeze.
The thin-snapshot base→app mechanism was proven separately the same day (the
earlier blocker was the LVM `activation skip` flag on thin snapshots, cleared
with `lvchange -K -ay`, not anything architectural). The apt-pin reproducibility
clause above is deliberately deferred: a plain `debootstrap` against current
packages is used, and the RO-frozen image is itself the effective pin until a
rebuild pipeline makes determinism meaningful. Kernel, waypipe and vm-agent are
already baked outside apt.

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
| `cid` | int \| `"auto"` | fixed 20–99 for static domains, or `"auto"` for pool allocation | yes | — |
| `reset_on_shutdown` | bool | — | no | `false` |

`reset_on_shutdown` exists only for the `untrusted` archetype's optional
app-layer reset (ADR-014); `vault` / `personal` / `disposable` omit it and
take the default.

`cid` carries two opposite meanings depending on the domain. For **static**
domains (vault, personal, untrusted) it is an *input*: a fixed value in
20–99, authored in the file, part of the domain's identity. For **disposable**
domains it is an *output*: the literal string `"auto"` declares "not authored
here — the deploy step allocates from the dynamic pool (≥100)" per ADR-017.
A numeric `cid` ≥100 is also accepted (manual/debug pinning), but `"auto"`
is the norm for disposables. CIDs 0–2 are reserved (hypervisor / local /
host-loopback); 3–19 is the sysVM band (ADR-022).

`properties.toml` describes **AppVMs only**. A `cid` in 3–19 is therefore an
**error**, not a permitted value: sysVMs are built declaratively
(`build/netvm.sh`, ADR-021) and carry no `properties.toml`. This restriction
is deliberate and provisional — should sysVMs ever gain a machine-readable
description, the schema needs a `class` field (ADR-022 `Vm.class`) and the
band becomes a function of it. That is the launch daemon's business, not this
ADR's.

*Semantic invariants* (cross-key, derived from the ADR-014 archetypes;
enforced by the pre-deploy validator, `tools/validate-properties.fish`):

- `disposable = true` ⇒ `persistence = ephemeral` — a disposable's
  instance-delta is destroyed on shutdown, so persistent home is contradictory
  (**error**).
- `reset_on_shutdown = true` is meaningful only with `persistence =
  persistent`; on an ephemeral domain the whole overlay is discarded anyway,
  making the app-layer reset redundant (**warning**).
- `network = none` with `manifest = web` is almost certainly wrong — an
  offline domain running the web manifest suggests a mis-set `manifest`
  (should follow the vault pattern) (**warning**).
- `disposable = true` with `identity = true` is unusual — disposable domains
  carry no identity by design (**warning**).

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
- A pre-deploy validator (`tools/validate-properties.fish`) checks the schema
  and the semantic invariants above before deploy; `--strict` promotes warnings
  to errors for pre-commit / CI use. Fish, dev-time, not part of the TCB. A
  C/`tomlc99` reimplementation remains an option if validation ever moves into
  the deploy binary itself.
- Customization surface stays manifest + `properties.toml`, both small enough
  to back a future GUI (ADR-014, v0.4 → v1.0).

**Revision note:** supersedes the loosely-structured early config style for VM
definition. Manifest format (packages) is specified separately in ADR-011.

**Revision note (2026-07-14, [ADR-022](DECISIONS.md#adr-022)):** the static
`cid` band moves from 4–8 to **20–99**. ADR-022 re-scoped the CID map for a
graph that may hold several sysVMs (`3–19`), which the original single-sysVM
scheme could not express. The schema is normative input to
`tools/validate-properties.fish`; the band is corrected here rather than left
to supersession, so that the specification and the tool enforcing it cannot
disagree. Nothing else in this ADR changes.

**Revision note (2026-08-06, [ADR-030](DECISIONS.md#adr-030)):** two changes,
recorded here rather than left to supersession, for the same reason the CID
band was: the specification and the tool enforcing it must not disagree.

1. **`network` is removed.** The enum `none | via-netvm` cannot name *which*
   netVM, and under [ADR-022](DECISIONS.md#adr-022) an AppVM's network access
   *is* which netVM it attaches to. It is replaced by `netvm` (a `VmRef`, or
   absent) and `provides_network` (bool, default `false`) — the two fields
   ADR-022 puts on `Vm`. ADR-022 displaced this field when it was accepted;
   this note is the belated record.
2. **The AppVM-only restriction is lifted.** The `class` field this ADR names
   as the precondition ("that is the launch daemon's business, not this
   ADR's") now exists. `class = sys` **requires** a CID in 3–19; `class = app`
   keeps the 20–99 band, where 3–19 remains an error.

Also added, per ADR-030: `nic` (a label, never a PCI address), `mem`, `vcpus`.
The format (TOML, one file per instance), the validator and every semantic
invariant above are unchanged.

**Revision note (2026-08-09, [ADR-032](DECISIONS.md#adr-032)):** this ADR
records its own discipline twice — the schema is corrected where it lives, so
that the specification and the tool enforcing it cannot disagree. ADR-032 §3
changes the schema substantially and the note belongs here.

1. **The required key set is a function of `class`,** and a key with no meaning
   for a class is **forbidden**, not ignored. Rejection happens at parse, in the
   same spirit as *absent, not disabled*: a `persistence` line on a netVM that
   is silently discarded is the *silent wrong-object* failure this project keeps
   finding. Common: `class`, `cid`, `manifest`, `mem`, `vcpus`. `class = sys`
   additionally requires `nic` and `provides_network`, and forbids `netvm`,
   `persistence`, `identity`, `disposable`, `reset_on_shutdown`. `class = app`
   additionally requires `netvm`, `persistence`, `identity`, `disposable`,
   admits `reset_on_shutdown`, and forbids `nic` and `provides_network`.
   `netvm` is satisfied by being present and explicitly empty — an absent
   `netvm` is an unstated assumption, an empty one is a declared offline vault.
2. **`manifest` becomes class-dependent in its values,** not a widened shared
   enum: `sys` → `netvm`; `app` → `vault | web`. A shared enum would make
   `manifest = netvm` legal on an AppVM — a valid value that builds the wrong
   image.
3. **The CID bands, restated in full because the ADR-030 note above has already
   been misread once.** `class = sys` requires 3–19. `class = app` keeps
   **all three** of this ADR's forms: the static band 20–99, `"auto"` for the
   disposable pool, and a numeric CID ≥ 100. "Keeps the 20–99 band" in the
   ADR-030 note means the *static* band is unchanged; it does not restrict
   `class = app` to that band. Reading it as a restriction deletes the
   disposable archetype at parse time — [ADR-014](DECISIONS.md#adr-014)'s
   fourth archetype is defined by `cid = "auto"` — and the validator has always
   implemented the three forms correctly.
4. **The validator enumerates a directory.** Its contract is
   `/etc/katmate/vm/*.toml` by default (ADR-032 §1 and §4). Invoked on
   individual files it runs per-file rules and reports that cross-file rules
   were **not evaluated**, rather than passing silently. The cross-file rule —
   no two VMs may claim the same `nic` label — is not implementable per-file and
   was not implementable at all until T1 had a location.

The format (TOML, one file per instance), the validator as the enforcement
point, and every semantic invariant above are unchanged. What changed is where
the files live and which keys are legal for which class.

---

## ADR-016 — Two desktop profiles: shared visual layer, Sway default + Hyprland optional

**Status:** Accepted (2026) — direction only; see Consequences for build state

**Context:** The desktop layer (greetd / compositor / bar / launcher) sits
outside the TCB ([SECURITY-MODEL.md](../SECURITY-MODEL.md)) and off the
isolation critical path ([ROADMAP.md](../ROADMAP.md) step 6), yet it shapes the
broad-user experience that [ADR-001](DECISIONS.md#adr-001) makes a first-class
goal. Hyprland (CYBRland config) delivers a richer look — animations, blur,
glow — but carries an explicit "features over stability" upstream: major
releases every 1–3 months, frequent config/plugin breaking changes, no
automatic config migration yet. Porting CYBRland from the Acer reference
machine to MINIS surfaced exactly this fragility: Acer-specific hardcodes
(`eDP-1`, `/home/sch`), plugin/ABI drift, and `hyprctl reload` not applying
changes (only a full session restart does). For a TCB-oriented project whose
default must be boring and maintainable, a rolling-breakage compositor is a
poor default — but the richer option has value for users who want it.

**Decision:** Adopt a two-profile model as the **target** desktop
architecture. Current development builds on the Hyprland profile; the Sway
profile is a recorded future target, not yet built. Both profiles share a
single visual layer.

- **Shared, compositor-independent layer:** waybar (config + `style.css` +
  scripts), rofi, swaync, GTK/Qt theming, palette, fonts. The glow/sij effect
  lives here (waybar CSS), **not** in the compositor — so it renders
  identically under either profile.
- **Sway profile (default, target):** vanilla Sway, no blur / no window
  animations. Boring, stable; intended as the shipped default for ordinary
  users.
- **Hyprland profile (optional):** CYBRland config, full eye-candy (blur,
  animations, glow). Opt-in — analogous to offering an alternative desktop
  environment over a common backend (cf. Qubes offering multiple DEs).

Compositor-specific config (workspace bindings, window rules, animations) is
the only per-profile delta. The "click N → all monitors switch to workspace N"
pattern is a small script in either compositor, not a built-in of either.

**Consequences:**

- The shared layer is built and tested once; only two thin compositor configs
  diverge.
- Hyprland's upstream churn is contained: version-locked like waypipe
  ([ADR-008](DECISIONS.md#adr-008)), upgraded deliberately rather than rolling,
  so its breakage never touches the default path.
- Glow / theming portability is guaranteed by construction (it is CSS,
  compositor-agnostic).
- Default user gets stability; power user gets eye-candy; neither forks the
  visual identity.
- Build state: today only the Hyprland profile exists (CYBRland, ported to
  MINIS, living in `~/.config/` — not yet in git). The Sway default profile is
  a documented intention; building it is deferred, not scheduled. This ADR
  fixes the direction, not a delivery date.
- Installer integration of the desktop layer remains a documented manual step
  until v1.0 ([ROADMAP.md](../ROADMAP.md) step 6) — unchanged; this ADR fixes
  only which layer.

**Revision note (2026-08-06, [ADR-030](DECISIONS.md#adr-030)):** two pointers
into `ROADMAP.md`'s build order move from *step 5* to *step 6*. ADR-030 added a
step and renumbered the tail; the target — installer integration — is
unchanged, and so is every decision in this ADR. Corrected in place rather than
left stale, because a build-order ordinal that silently resolves to a different
step is the same failure class this project keeps finding: a reference that
still points somewhere, just not where it meant to.
---

## ADR-017 — Dynamic CID allocation for disposable AppVMs

**Status:** Accepted (2026-06)

**Context:** [ADR-014](DECISIONS.md#adr-014) fixes the disposable domain
(ephemeral, task-bound, created and destroyed on demand);
[ADR-015](DECISIONS.md#adr-015) lets a disposable declare `cid = "auto"`
instead of a static CID. What ADR-015 deliberately does *not* fix is *how* a
concrete vsock CID is chosen at deploy time and reclaimed at teardown. Three
points framed the decision:

- The vsock CID space is 32-bit — effectively unbounded for this use. The real
  ceiling on concurrent disposables is **hardware** (RAM / hugepages), not CID
  exhaustion. "How big is the pool" was the wrong question; "how many VMs can
  the host hold" is the right one, and it is a *separate* limit.
- A CID must be unique across all live VMs at any instant (vsock routing keys
  on it), allocation must be atomic against concurrent launches, and a
  reclaimed CID must not be re-handed to a new instance while the previous
  vsock endpoint is still tearing down (the disposable's whole purpose is
  isolation — a fast reuse that inherits a half-open connection defeats it).
- A purely random pick was considered and rejected: randomness does not buy
  security here (the CID is not a secret and is not externally reachable), does
  not by itself provide uniqueness (still needs an atomic reservation), and
  loses the determinism that makes deploys debuggable. What the reuse edge
  actually needs is *temporal distance* between release and re-use, not
  unpredictability.

**Decision:**

- **Space:** static domains use fixed CIDs 20–99 (authored in
  `properties.toml`); the dynamic pool is every CID ≥ 100. CIDs 0–2 are
  reserved, 3–19 is the sysVM band ([ADR-022](DECISIONS.md#adr-022); 3 remains
  the primary netVM, [ADR-009](DECISIONS.md#adr-009)). The 100 floor only
  separates the dynamic pool from the static band; there is no upper bound
  from CID space.
- **Policy: monotonically increasing counter** (PID-style), not lowest-free and
  not random. The allocator hands out `max(100, last_allocated + 1)`, skipping
  any CID currently marked in use, and wraps back to 100 only on reaching a
  theoretical ceiling that hardware limits make practically unreachable.
  Monotonicity gives the reuse-safety property for free: a released CID is not
  revisited until the counter has cycled through the entire space, by which
  time the old endpoint is long dead — no grace timer, no randomness needed.
- **State:** `/var/lib/katmate/cid-pool` holds the last-allocated counter and
  the table of currently-in-use CIDs. The deploy step reads and writes it under
  an exclusive lock (`flock` on a separate `cid-pool.lock`, held across the
  whole read → allocate → write cycle, never just the write).
- **Reclaim:** on instance teardown the CID is marked free in the table.
  Because of monotonicity it is not de-facto reusable for a long time anyway.
- **Crash recovery:** a nasty death (instance or host) leaves a CID marked
  in-use with no live VM behind it — a slow leak that eventually clogs the
  table. The allocator reconciles on startup (and may, periodically): compare
  the in-use table against actually-live instances (running QEMU processes /
  active vsock endpoints for those CIDs) and free the orphans.
- **Concurrency ceiling is separate:** the deploy step refuses a new launch
  when hardware (RAM / hugepages) cannot host another VM. This — not CID
  allocation — is what bounds the number of concurrent disposables.

**Consequences:**

- `cid = "auto"` in `properties.toml` (ADR-015) routes through this allocator;
  a numeric pool CID (≥100) bypasses it for manual/debug pinning, at the
  author's risk of collision (the validator cannot see runtime state).
- New host-side state and its lifecycle: `/var/lib/katmate/cid-pool` (+ lock)
  must be created by the installer / first run, and is owned by the deploy
  tooling (`katmate`), not the user.
- Two correctness requirements are first-order, not implementation details:
  the lock must cover the full read-allocate-write cycle (else the collision
  returns through the back door), and reconcile must run (else the pool leaks).
  Both are recorded here so they stay solved.
- Lowest-free and random allocation are explicitly rejected; revisit only if a
  concrete requirement (e.g. CID stability across reboots for a specific
  disposable) appears, which would itself contradict the disposable model.

**Cross-reference:** consumes `cid = "auto"` from
[ADR-015](DECISIONS.md#adr-015); invoked by the deploy-time instance step of
[ADR-011](DECISIONS.md#adr-011); pool floor and reserved CIDs align with the
NetVM CID ([ADR-009](DECISIONS.md#adr-009)).

**Revision note (2026-07-14, [ADR-022](DECISIONS.md#adr-022)):** static band
4–8 → **20–99**, reserved band 3 → **3–19**. The allocation *policy* is
untouched: monotonic counter, `flock` across the whole read-allocate-write
cycle, reconcile on startup. Only the floor of the static band moves.

## ADR-018 — Foundation build: LVM-thin from scratch, external-vmlinuz kernel, systemd-free init

**Status:** Accepted (2026-06 / 2026-07); realizes the pipeline of
[ADR-011](DECISIONS.md#adr-011) and the storage mechanism of
[ADR-010](DECISIONS.md#adr-010).

**Context:** [ADR-011](DECISIONS.md#adr-011) fixed *that* the foundation is
built by shell scripts orchestrated by Make; [ADR-010](DECISIONS.md#adr-010)
fixed the three-level LVM-thin storage chain. What neither pinned was the
concrete build mechanism for the foundation itself, nor several decisions that
only surfaced once the script was written against live hardware. The
pre-revision `foundation.sh` had drifted from reality in three ways, each of
which this ADR settles:

- It built the base into a **qcow2 image over an NBD device**, a mechanism
  ADR-010 rev-2026-06 already replaced with LVM-thin everywhere else
  (`app-layer.sh`). The foundation script was the last holdout, so the codebase
  described a procedure no longer used.
- It shipped the guest kernel as a **`.deb` unpacked into the image**, with the
  dpkg/initrd machinery that implies. Under the monolithic `-kernel` direct
  boot ([ADR-005](DECISIONS.md#adr-005)) there is no `/lib/modules` and no
  initrd, so an in-image kernel package is dead weight that is never consulted
  at boot.
- Its `/sbin/init` was still a **systemd symlink**. The Apr-13 hand-built image
  inherited this and every layer therefore booted systemd, contradicting the
  2026-06-27 decision to remove systemd from the guest entirely (previously an
  unwritten "ADR-worthy" note in `state.md`).

A fourth point is a packaging fact, not drift: `debootstrap --variant=minbase`
ships **neither `useradd` nor `passwd`**, so any account creation that relies on
them silently no-ops (a `|| true` had been swallowing "command not found").

**Decision:** `foundation.sh` builds and freezes `foundation` (concrete:
`vg0/vm_tpl_foundation`) from nothing, and is the single source of the
procedure — no step exists only as a live-state artefact that the script fails
to reproduce.

- **Storage mechanism: LVM-thin throughout, matching the app layer.**
  debootstrap writes directly onto a thin LV (no partition table, so the guest
  boots `root=/dev/vda`, never `vda1`). Build → mount LV → chroot → bake → RO
  freeze (`lvchange -p r`). The rollback trap removes a half-built LV on
  mid-build failure. This makes the foundation and app-type builds share one
  mechanism and one `lib.sh`.
- **Kernel rides as an external vmlinuz, not in the image.** The `.deb`/dpkg/
  initrd path is dropped. `config.sh` carries `KERNEL_VMLINUZ` (not
  `KERNEL_DEB`); the Makefile copies the monolithic vmlinuz from the build
  host's kernel archive into the output. This is the same kernel-delivery model
  as the update flow (ARCHITECTURE.md §4): the kernel is versioned and shipped
  as the external `-kernel`, decoupled from the RO rootfs it boots.
- **systemd is absent from the boot path.** `foundation.sh` compiles
  `init/katmate-init.c` static and bakes it to `/sbin/init` — no `init=` cmdline
  needed. The systemd binary may still physically ship in the image as inert
  mass until a later minimal-TCB purge, but nothing in the boot path invokes it.
  The guest's only root process is the custom PID 1; building anything on
  systemd would be future regression work, since systemd is slated to leave the
  appliance entirely (this supersedes the pre-06-22 plan to ship vm-agent as a
  systemd **user** unit).
- **User 1000 is written directly to the account files.** Because minbase has
  no `useradd`/`passwd`, `foundation.sh` writes `/etc/passwd`, `/etc/group`, and
  `/etc/shadow` by hand (locked `!*` password; no login). This needs no tooling
  in the image, keeps the TCB smaller, and — unlike the old `|| true` path —
  fails loudly if it goes wrong. `/home/user` is the per-instance rw LV, not
  created at foundation-build time.

**Consequences:**

- The build chain is reproducible from nothing: `make foundation` →
  `make app-<type>` → instance boots end-to-end, all off one mechanism.
  Validated live: static-ELF `/sbin/init`, waypipe `lz4:true zstd:true`, user
  1000 in passwd, `[katmate-init] starting (pid 1)` → `vm-agent launched as uid
  1000`, PING `status=0x00 OK`.
- The kernel and the rootfs version independently. A guest-kernel security
  rebuild ships as a new external vmlinuz without rebuilding the foundation
  image, and vice versa.
- Removing systemd from the boot path is now structural, not incidental: the
  image cannot silently regress to booting systemd because `/sbin/init` is the
  baked binary, not a redirectable symlink. The remaining systemd binary is a
  minimal-TCB cleanup item, not a correctness issue.
- Build-host coupling: the kernel archive path is build-host-specific
  (`$(HOME)` under `sudo` resolves to `/root`, so the path is hardcoded rather
  than derived). The kernel build itself is not part of this pipeline — it is a
  separate, manually-run step whose output this pipeline consumes.

**Cross-reference:** realizes the pipeline of
[ADR-011](DECISIONS.md#adr-011) on the storage chain of
[ADR-010](DECISIONS.md#adr-010); the systemd-free PID 1 and no-ACPI shutdown are
the init side of the guest model; waypipe-from-source in the foundation chroot
follows [ADR-008](DECISIONS.md#adr-008); kernel delivery follows
[ADR-005](DECISIONS.md#adr-005) (custom monolithic guest kernel).

---

## ADR-019 — Waypipe as a project-maintained component: pinned upstream tag + KatMate patch queue, one tree for both host and guest binaries

**Status:** Accepted (2026)

**Context:** ADR-008 mandates a version-locked waypipe on both sides of the
trust boundary, but leaves the host binary owned by the host distro (Arch
pacman). Three facts make that ownership untenable:

1. **No wire-protocol stability.** Waypipe's internal client↔server protocol
   carries no compatibility guarantee between versions (the README's "partial
   forward-compatibility" refers to Wayland protocol extensions, not waypipe's
   own wire format; upstream expects both ends on the same release). A skew is
   not a degradation — it is a refused connection (the `header has 100 != own
   200` failure that produced ADR-008).
2. **The guest toolchain is frozen.** The guest binary is built inside the
   trixie foundation chroot with trixie's rustc/meson/wayland stack, frozen
   for the LTS lifetime. Upstream (and Arch) will keep raising MSRV and
   dependency floors; sooner or later a pacman-shipped version exists that
   the foundation **cannot build**. The dependency therefore points host →
   guest, not guest → host: *buildability on trixie is the binding
   constraint*, and the host must follow.
3. **Distribution (ADR-012 direction).** End users of installed KatMate
   systems cannot be assumed to have a distro that packages the required
   waypipe version at all. A host binary owned by the project is a
   prerequisite for any distribution model, not an optimization.

Additionally, waypipe upstream is a single-maintainer project with roughly
one major release per year (0.9.0 2024-03, 0.10.x through 2025, 0.11.0
2025-12), minor releases every 2–4 months in active periods, and historical
multi-year quiet stretches — a cadence that makes deliberate, infrequent
version bumps practical and continuous tracking unnecessary.

**Decision:** Waypipe becomes a project-maintained component — a *patch-queue
fork* ("fork lite"), not a hard fork:

- **One pinned tree.** The project pins an upstream git tag (currently
  `v0.11.0`) plus a small, reviewable queue of KatMate patches kept in the
  repo (`third_party/waypipe/patches/`, applied in order). The pin (tag +
  patch level) is the single project-wide waypipe version.
- **Patch queue scope: strip and harden only.** Remove or compile out paths
  the trust boundary must not carry — ssh mode, video encoding, dmabuf/gbm,
  reconnect — beyond what meson feature flags already disable; keep the
  vsock path as the only entry point. No feature development, no divergence
  from upstream's core; Wayland protocol evolution remains upstream's job.
- **Both binaries from the same tree.** Guest: built in the foundation chroot
  exactly as ADR-008 prescribes (recipe unchanged, source now the pinned
  tree). Host: built by a project script on the host, installed at
  `/opt/katmate/bin/waypipe` outside the package manager; the
  `waypipe-client` systemd user unit points there. The distro waypipe
  package becomes irrelevant and may be removed.
- **Host-side build metadata.** `foundation.sh` writes
  `/var/lib/katmate/foundation.meta` at RO-freeze time: waypipe tag + patch
  level, guest kernel version, build date. This is the source of truth for
  "active foundation version" — readable without booting or mounting
  anything.
- **Launch-time enforcement.** The instance launch path compares the host
  binary's `waypipe --version` against `foundation.meta` and **refuses to
  start the VM loudly on mismatch** — the invariant ("both ends identical")
  is checked where the two ends meet, independent of where either binary
  came from. This is the concrete mechanism behind ADR-008's "katmate-update
  enforces the lock".
- **`katmate-update` is a release-bump orchestrator, not a drift detector.**
  There is no pacman hook and nothing to detect: drift is impossible by
  construction. A version bump is a deliberate act: bump the pin → rebase
  the patch queue → build the host binary → `make foundation` → `make
  app-<type>` for each type → recreate instance deltas → update
  `foundation.meta`.
- **Gating criterion for any bump: it builds on trixie.** If a security fix
  lands only in an upstream version the trixie toolchain cannot build, the
  fix is backported onto the pinned tag and both sides are rebuilt — the
  same practice already applied to the LTS guest kernel (ADR-005).

**Consequences:**

- Upstream CVE tracking (gitlab.freedesktop.org/mstoeckl/waypipe) becomes a
  project responsibility. This extends an existing burden class (LTS kernel
  patch tracking), not a new one.
- Attack surface at the trust boundary shrinks: stripped code paths are
  absent from both binaries, not merely disabled.
- The ADR-008 lock holds by construction (single tree) and is enforced at
  runtime (preflight); the compression-negotiation failure class is closed.
- Expected maintenance: patch-queue rebase roughly 1–2× per year, driven by
  deliberate bumps (typically majors or CVEs), never by upstream cadence.
- The deferred `snapshot.debian.org` apt pin (ADR-011) becomes meaningful at
  the first `katmate-update`-driven rebuild and should be introduced with it.
- ARCHITECTURE.md's update-flow section (pacman hook → detection) is
  obsolete and must be rewritten to the release-bump flow.
- A hard fork remains a future option (upstream death or unacceptable
  direction); the patch queue is its natural starting point.

**Cross-reference:** realizes the lock of [ADR-008](DECISIONS.md#adr-008)
and the "defined sources" reproducibility of
[ADR-007](DECISIONS.md#adr-007)/[ADR-011](DECISIONS.md#adr-011); removes the
distro dependency that [ADR-012](DECISIONS.md#adr-012) cannot tolerate;
mirrors the backport practice of [ADR-005](DECISIONS.md#adr-005).

---

## ADR-020 — Release is a pre-baked signed ISO; install-time carries no build-time dependencies

**Status:** Accepted (2026-07)

**Context:** ADR-019's host build script (`waypipe-host.sh`) clones waypipe
from a public git remote, applies the patch queue, and compiles it with the
full Rust/meson toolchain. That is correct for the *developer's* build
environment, but it forced an implicit question that had never been settled:
does any of this machinery run on the *end user's* machine at install time?

For a security-focused OS the answer must be a hard no, and for reasons of
security, not merely convenience:

- **Network dependency at the worst moment.** Requiring `git clone` (or any
  fetch of project components) during installation makes the install fail
  without a network and, worse, ties the integrity of the installed system to
  whatever a remote served at that instant.
- **Supply-chain / TOFU surface.** What `git clone` pulls at install time is
  not what the developer reviewed and signed. Every install-time fetch is an
  unaudited trust decision made on the user's behalf. A user who chose this OS
  *for* its minimal trust surface cannot be asked to trust a public git remote
  as a precondition of installation.
- **Reproducibility (ADR-007).** Installation must yield bit-for-bit what was
  reviewed and signed at release time. A build performed at install time —
  against moving package repos and git HEADs — cannot offer that.
- **Threat model of the audience.** The users who most want this system are
  precisely those who should not have to reach a public git host to obtain a
  trustworthy install.

**Decision:** The unit of distribution is a **pre-baked, GPG-signed ISO**.
Everything is built ahead of time in the developer's environment and shipped
inside the image; installation is unpacking and provisioning, never building.

- **Build-time (developer, on Acer/MINIS).** `git clone`, patch queue,
  `cargo`/`meson`/`ninja`, `debootstrap`, kernel build — all the pipeline
  scripts (`foundation.sh`, `app-layer.sh`, `waypipe-host.sh`, kernel build)
  run *here*. Git and the toolchain are legitimate at this stage: it is the
  developer's reviewed, signed environment. The **output** of this pipeline is
  the ISO.
- **Release artifact.** The ISO carries every prebuilt component: the
  foundation thin LV image, the app-layer snapshots, the external MicroVM
  `vmlinuz`, and **both** waypipe binaries (guest baked into the foundation,
  host binary destined for `/opt/katmate/bin/waypipe`). The ISO is signed; the
  signature is the trust anchor.
- **Install-time (user).** `download ISO → verify signature → bake to USB →
  boot → installer provisions prebuilt artifacts onto disk` (LVM/thin-pool
  setup, unpack, bootloader). No `git`, no `cargo`/`meson`/`ninja`, no fetch of
  project components. Network access, if used at all, is a separate question
  (e.g. the Debian base) and must never be a path by which *project*
  components arrive unaudited.

**Consequences:**

- The ADR-019 pipeline scripts are firmly **build-time developer tools**; none
  of them ever executes on a user's machine. `/opt/katmate/bin/waypipe` arrives
  on the target as a prebuilt, signed artifact unpacked from the ISO — not as
  something compiled during installation.
- The installer's job shrinks to provisioning: partition/thin-pool, unpack the
  signed images, install the bootloader, write per-instance deltas. It contains
  no build logic and no toolchain.
- Reproducibility and auditability become properties of a single signed
  artifact (the ISO), the natural place to anchor both.
- `katmate-update` (ADR-019) operates on the same principle: it is a
  developer/release-side orchestrator that produces new signed artifacts, not
  an install-time or on-device builder.
- Open follow-up: define whether the installer needs *any* network at all
  (offline install as the target), and how the Debian base within the
  foundation is itself pinned/shipped so that even the base is not fetched
  unaudited at build time (ties into the deferred `snapshot.debian.org` pin,
  ADR-011).

**Cross-reference:** enforces the reproducibility of
[ADR-007](DECISIONS.md#adr-007)/[ADR-011](DECISIONS.md#adr-011) at the
distribution boundary; scopes the build machinery of
[ADR-019](DECISIONS.md#adr-019) to build-tim---

---

## ADR-021 — netVM is a distinct sysVM component class: separate, declarative build, its own control agent and update track

**Status:** Accepted (2026-07). Shutdown model (host QMP → ACPI → logind) and
agent privilege set superseded by [ADR-024](DECISIONS.md#adr-024); all other
decisions remain in force.

**Context:** [ADR-009](DECISIONS.md#adr-009) fixed netVM's *role* — the sole
network-facing domain, owning DHCP/DNS/VPN/firewalling/routing — but never
fixed *how netVM is built, controlled or updated*. By omission it was treated
like every other guest, and in practice it became the one guest built by no
pipeline at all: a hand-installed Debian **netinst pet** (`deb cdrom:` source,
in-guest GRUB + initrd, installer-written configuration). Two facts forced the
question open in the 2026-07-08 session:

- **netVM does not fit the foundation/app-layer model, in either direction.**
  It is the *only* guest that needs `-machine q35` (PCI topology for vfio NIC
  passthrough per [ADR-009](DECISIONS.md#adr-009)), not microvm; and it needs
  full **systemd** (`systemd-networkd`, `wg-quick`, DHCP via networkd) plus
  firmware and an initramfs — the exact inverse of the systemd-free,
  `katmate-init`, monolithic-`-kernel` foundation ([ADR-018](DECISIONS.md#adr-018),
  [ADR-005](DECISIONS.md#adr-005)). It also carries **no waypipe**, so the
  lifecycle premise of the app layer — rebuild is driven by a waypipe version
  bump ([ADR-019](DECISIONS.md#adr-019)) — does not apply to it. In Qubes'
  vocabulary this is a **sysVM**, a different class from AppVMs, and the design
  should say so explicitly rather than leave it as an unclassified exception.
- **The pet just leaked a bug into the most security-exposed VM.** The recurring
  first-boot `Raise network interfaces` failure traced to a stale static block
  for the *host's* USB-NIC MAC (`enx00e04c3961b8`) in `/etc/network/interfaces`
  — written by the netinst installer for a topology that no longer exists, and
  drifting silently ever since. The same artefact reappeared in the pet's
  `nftables.conf` as dead `enx00e04c3961b8` forward rules and a wrong internal
  subnet (`10.100.17.0/24` where the segment is `10.100.1.0/24`). netVM is the
  VM that terminates the raw uplink and holds the VPN keys; installer-authored
  state that no manifest owns is least acceptable *here* of all places.

Two constraints already accepted make the netinst pet untenable, not merely
untidy. [ADR-020](DECISIONS.md#adr-020) fixes the release unit as a pre-baked
signed ISO the user provisions but never builds — which requires netVM to exist
as a prebuilt, reproducible artifact, impossible while it is produced by an
interactive installer run. And [ROADMAP.md](../ROADMAP.md) step 4 (installer
provisions netVM) requires a declarative source for that provisioning.

The real decision is therefore not *whether* netVM is separate — its machine
model, service model and update trigger make that self-evident — but that
"separate" must mean **separately declarative**, never "hand-maintained
forever"; and that netVM, being appVM-agnostic by design (below), needs a
**host-driven control channel** to receive per-appVM network configuration at
launch time rather than baking any appVM topology into the image.

**Decision:** netVM is a first-class **sysVM component class**, built and
updated by its own declarative pipeline, carrying its own privileged control
agent, outside foundation/app-layer and outside `katmate-update`.

- **Own build script, `build/netvm.sh`, debootstrap-based.** netVM is built
  from nothing by debootstrap onto a **standalone linear RW LV**, mount →
  chroot → bake → export, reusing the proven mount/chroot skeleton and rollback
  trap of [ADR-018](DECISIONS.md#adr-018). It is a *sibling* of `foundation.sh`,
  not a copy, and diverges deliberately: full systemd (debootstrap default
  variant, **not** `--variant=minbase`); q35; `non-free-firmware` an enabled apt
  component; an initramfs is generated; **no waypipe, no katmate-init**.
  debootstrap is chosen over keeping netinst + a config-management layer
  specifically because it **closes the drift class** the pet just demonstrated —
  every file in the image answers to the manifest, and there is no unclassified
  installer as a second author. Same reproducibility stance ADR-018 took for the
  foundation, applied to the one guest that had escaped it.

- **Standalone linear RW LV, not thin, not frozen.** netVM is nobody's backing
  store, so it is a plain linear LV — no thin snapshot, and therefore none of
  the `-K -ay` skip-activation trap that governs the foundation/app chain
  ([ADR-010](DECISIONS.md#adr-010)). It is **not** RO-frozen: runtime-mutable
  state (`/var`, DHCP leases, WireGuard handshake state, `resolv.conf`, logs,
  and host-delivered dynamic network config — below) lives on the RW LV. The
  image itself is disposable: a rebuild overwrites the LV.

- **Own package + config manifest.** A netVM-specific manifest declares the
  package set (`systemd`, `firmware-realtek`, `wireguard-tools`, `nftables`,
  `linux-image-amd64`, `initramfs-tools`) and the configuration baked at build
  time. The image is **appVM-agnostic**: it bakes only VM-independent policy and
  bakes **no internal topology at all**:
  - `/etc/systemd/network/20-uplink.network` — MAC-matched DHCP on the vfio
    uplink NIC (not appVM-specific).
  - `/etc/network/interfaces` — reduced to `lo` + `source` only; the stale
    static block is never re-baked.
  - `/etc/wireguard/proton.conf.template` — a **placeholder** config, not a
    secret (see image/state separation below).
  - `/etc/nftables.conf` — a **static** firewall/routing policy that references
    the internal segment only as the aggregate `10.100.1.0/24`, never
    per-appVM. Per-`/32` isolation is provided by **topology** (each appVM is a
    separate p2p link with a link-scoped `/32` route), not by per-appVM firewall
    rules, so the firewall never changes as appVMs come and go. The pet's dead
    `enx00e04c3961b8` forward rules are dropped and the wrong subnet corrected.
  - `/etc/sysctl.d/30-netvm-forward.conf` — `net.ipv4.ip_forward = 1`.
  No `10-personal.network` and no other `/32` route is baked: **not even
  personalVM** (a fixed CID) is treated as an image-level exception. Every
  internal route, personalVM included, is delivered at launch time (below). On a
  clean boot netVM therefore has *no* internal route, which is correct — with no
  running appVMs there is nowhere to route.

- **netVM carries its own control agent (`netvm-agent`), privileged.** The host
  configures netVM's network boundary through a vsock control agent, consistent
  with the vsock-only channel rule ([ADR-003](DECISIONS.md#adr-003)): the host
  is the caller, netVM the executor, and the boundary holds because the mutation
  comes from the *more*-trusted side (host), never from an appVM. This is the
  same trust direction as the host-drawn domain indicator — the boundary is
  moved only by code the constrained side cannot reach. Crucially, the mutating
  party is netVM's **own** agent receiving a host command, **not** an appVM's
  agent reaching across a boundary.

- **Two agent binaries from one Rust workspace; absent, not disabled.** The
  agent becomes a Cargo workspace: a shared `protocol` crate (framing/transport
  + `error.rs`) and **two** bin crates — `vm-agent` (foundation/appVM:
  uid 1000, RUN whitelist, FILEPUT/FILEGET) and `netvm-agent` (netVM:
  privileged, network control). The split is a security measure, not just
  tidiness, on the same principle as the ADR-019 waypipe strip — *absent code
  paths are stronger than disabled ones*. The privileged `netvm-agent` binary
  does **not contain** RUN/FILEPUT code at all; the unprivileged appVM
  `vm-agent` does **not contain** NETCFG code at all. A single build gating
  behaviour at runtime would leave RUN code physically present in a process
  holding `CAP_NET_ADMIN`, and NETCFG code physically present in the
  least-trusted guest — both avoided here by separate compilation. Opcode
  *values* live in a shared registry in `katmate-protocol` (alongside
  framing/transport/error) — one source of truth for the wire; opcode *enums
  and handlers* are per-bin-crate. That split is exactly where the
  absent-not-disabled boundary sits: each binary's `Op` enum (`TryFrom<u8>`)
  maps only the values it handles, so an opcode it must not run does not parse
  into a variant at all — it fails at decode, not at a runtime gate.
  
  Opcode model:

  | Opcode | Value (shared registry) | `netvm-agent` | `vm-agent` (appVM) |
  |---|---|---|---|
  | PING | ✓ | handler | handler |
  | NETCFG | ✓ | handler (privileged) | absent |
  | SHUTDOWN | ✓ | absent — host QMP/ACPI | handler (→ katmate-init) |
  | RUN / FILEPUT / FILEGET | ✓ | absent | handler (uid 1000, whitelist) |

  PING is the only opcode both agents *handle*. SHUTDOWN is handled by the
  appVM `vm-agent` only: appVMs are microvm — no ACPI — so they must carry an
  in-guest SHUTDOWN that asks katmate-init (PID 1) to call `reboot(2)`. netVM
  is q35 and therefore has ACPI, so it is powered down gracefully by the host
  over QMP (below) and its agent carries **no** SHUTDOWN handler. The registry
  holds every opcode's wire value so the host client (`ping-client`) can encode
  any of them; the security property — a `CAP_NET_ADMIN` binary that physically
  cannot execute RUN, an unprivileged binary that physically cannot execute
  NETCFG — is carried by the per-bin enum and handler set, never by presence in
  the registry.

- **`NETCFG` is a typed network-config command, never a generic RUN.** It
  installs a **validated** `systemd-networkd` `.network` fragment (a per-appVM
  `/32` p2p link route on netVM's internal interface) and triggers
  `networkctl reload`; it carries a structured payload, not a shell string. The
  host calls it at appVM launch to add the route and at teardown to remove it.
  This keeps the privileged agent's surface to exactly one job — internal-route
  lifecycle — rather than arbitrary execution. Because the LV is RW, the
  delivered fragment persists as runtime state and is correctly discarded on
  image rebuild (when no appVM is running anyway).

- **netVM shutdown is host-driven over QMP, not an agent opcode.** netVM is the
  project's only q35 guest (PCI topology for vfio), hence the only guest with
  ACPI. The host powers it down with QMP `system_powerdown` — an ACPI
  power-button event that `systemd-logind` (default `HandlePowerKey=poweroff`)
  turns into a clean stop of networkd / wg-quick / nftables, releasing the
  RTL8125 for the FLReset- restart cycle. Consequences, all deliberate: no
  SHUTDOWN opcode in `netvm-agent`, no shutdown-related privilege
  (`CAP_SYS_BOOT` unnecessary), and no dbus/polkit dragged into the most
  network-exposed VM. This is the principled counterpart to the appVM path, not
  an inconsistency: the asymmetry follows from the machine type. The appVM
  in-guest SHUTDOWN exists precisely because microvm has no ACPI (see
  `state.md`, "Shutdown without ACPI"); netVM has ACPI, so it needs neither an
  agent opcode nor an init delegate. The launcher exposes
  `-qmp unix:/run/katmate/netvm-qmp.sock,server,wait=off`; the send-side is a
  small host tool (or subcommand), host surface only — never reachable from a
  guest.

- **Privilege: `netvm-agent` runs with `CAP_NET_ADMIN`** (plus write access to
  `/etc/systemd/network/`), granted via its systemd unit — the minimum for
  writing `.network` fragments, reloading networkd, and touching `nft`, rather
  than full root if capabilities suffice. This is deliberately **more** than the
  appVM `vm-agent` (uid 1000, unprivileged, RUN whitelist): the same protocol,
  two trust/privilege levels by VM class. It runs under systemd (a unit), not
  under katmate-init. With SHUTDOWN handled off-agent (QMP, above),
  `CAP_NET_ADMIN` now covers exactly one job — the NETCFG internal-route
  lifecycle — and no shutdown capability is granted at all.

- **No bootloader in the guest: direct-kernel boot.** q35 supports QEMU
  `-kernel`/`-initrd`/`-append` (SeaBIOS linuxboot), so netVM boots with no
  in-guest GRUB and no `/boot` partition. `build/netvm.sh` installs Debian's
  stock `linux-image-amd64` in the chroot and **exports the resulting
  `vmlinuz` + `initrd.img` to a host-side artifact** at build time; the
  `net-vfio.con` launcher passes them with `-kernel`/`-initrd`, mirroring the
  external-vmlinuz pattern ADR-018 established for the foundation. The stock
  Debian kernel (not a custom build) is used deliberately: its security
  maintenance is Debian's, adding no second kernel configuration to carry. An
  initramfs is retained because the stock kernel has `virtio_blk` as a module
  (trimmed with `MODULES=dep`, not eliminated).

- **Own update track, `netvm-update`, outside `katmate-update`.**
  `katmate-update` ([ADR-019](DECISIONS.md#adr-019)) is a waypipe-version-bump
  orchestrator and **must never touch netVM** — netVM has no waypipe and no
  shared foundation. netVM rebuilds are driven by Debian security updates and
  network-configuration changes; `netvm-update` rebuilds the image from the
  manifest and re-exports kernel + initrd on its own cadence.

- **Image and state are separated.** Because the image is rebuilt from a
  manifest, no per-install secret lives inside it. WireGuard keys and per-deploy
  values live **outside** the image (the manifest carries a config *template*;
  concrete values are written at provisioning time), so a rebuild never destroys
  installed credentials. Host-delivered dynamic routes (NETCFG) are runtime
  state on the RW LV, likewise outside the baked image.

**Alternatives considered:**

- **Fold netVM into the foundation.** Rejected: opposite machine models
  (q35+PCI vs microvm), opposite init models (systemd vs katmate-init),
  unrelated update triggers (Debian security vs waypipe bump). Merging would
  drag systemd, firmware and an initramfs back into the minimal-TCB foundation
  to serve one guest.
- **Keep the hand-installed netinst pet.** Rejected: cannot satisfy ADR-020
  (user provisions a prebuilt artifact) or ROADMAP step 3 (declarative
  provisioning), and is the exact mechanism that leaked the stale-`interfaces`
  and dead-firewall-rule bugs into the most security-exposed VM. Separateness is
  correct; hand-maintenance is what is rejected.
- **A single agent binary gating RUN/NETCFG at runtime.** Rejected on the
  absent-vs-disabled principle: it would ship RUN code inside a
  `CAP_NET_ADMIN`-holding process and NETCFG code inside the least-trusted
  guest. There is no running system to protect and no schedule pressure, so the
  split is done from the start rather than deferred — deferred security
  minimizations accrue as debt, and refactoring a privileged network element
  "later" is strictly more work and risk than building it split now.
- **Guest-side (appVM) agent managing netVM firewall/routes.** Rejected
  outright: it would let a constrained guest move its own boundary — the
  inverse of the trust direction. netVM's own agent receiving a host command is
  the correct shape.
- **Bake per-appVM `/32` routes (or personalVM's) into the image.** Rejected:
  it would couple the stable, rarely-rebuilt netVM image to the dynamic appVM
  lifecycle (CID ≥100 pool). The image stays appVM-agnostic; all internal
  routes arrive via NETCFG at launch.
- **A second custom monolithic kernel for netVM** (no initrd, maximal trim).
  Rejected *for now*, stability over speed: doubles kernel-config maintenance,
  and a built-in `r8169` would probe before root is mounted and fail the
  `rtl8125b-2.fw` load (the blob issue closed 2026-07-08) — soluble only via
  `CONFIG_EXTRA_FIRMWARE`, which raises firmware-licensing questions for ISO
  distribution. Deferred, not adopted.
- **In-agent SHUTDOWN via `CAP_SYS_BOOT`, or via logind over dbus/polkit.**
  Rejected. netVM is q35 and therefore has ACPI, so the host can power it down
  gracefully with QMP `system_powerdown` (an ACPI power-button event that
  `systemd-logind` turns into a clean stop) without granting the agent any
  shutdown privilege at all. `CAP_SYS_BOOT` would widen the privileged binary's
  capability set beyond its one job (NETCFG); the logind path would drag
  dbus + polkitd — a privileged daemon with a poor CVE history — into the most
  network-exposed VM. Both add surface to buy nothing the machine type does not
  already provide. The appVM in-guest SHUTDOWN is not the same case: microvm has
  no ACPI, so there the host has no equivalent lever.

**Consequences:**

- A new build artifact class exists: netVM's image + its exported host-side
  `vmlinuz`/`initrd`, produced by `build/netvm.sh`, distinct from `foundation`
  and the `app-<type>` layers.
- The agent codebase becomes a Cargo workspace (shared `protocol` crate + two
  bin crates). The existing appVM `vm-agent` is unchanged in behaviour; the new
  `netvm-agent` is built and baked by `build/netvm.sh` and run as a privileged
  systemd unit inside netVM.
- `katmate-update` explicitly excludes netVM; `netvm-update` is its own track
  with its own trigger. The two update paths do not interact.
- **Security posture improves at the boundary that matters most.** The boot
  chain of the network-facing VM lives host-side and outside the guest image (no
  in-guest bootloader to rewrite for persistence); the privileged control
  binary contains only network-config code, not general execution; the firewall
  is static and appVM-agnostic, with isolation carried by topology; and the
  least-trusted appVM guest cannot even name a network-config opcode.
- netVM migration is explicitly **not** the AppVM migration: netVM is *not*
  moved onto the katmate-init/foundation chain, it stays systemd. The two tracks
  are independent.
- The launch daemon (future ADR) becomes the owner of *when* NETCFG and
  SHUTDOWN are called: it allocates the appVM's CID and internal `/32`, calls
  NETCFG on netVM to add the route at launch and remove it at teardown, and
  refuses to SHUTDOWN netVM while appVMs depend on it.
- Open follow-ups deferred to `build/netvm.sh` + manifest + agent work (next
  sessions, not fixed here): the exact initramfs/service/firmware trim
  (`MODULES=dep`, disabling unused systemd units, qboot vs SeaBIOS); the
  `netvm-agent` vsock control **port** (distinct from GUI 1024 / control 1025 /
  audio 1026); the `.network`-fragment validation rules NETCFG enforces; the
  internal-interface naming/addressing convention for per-appVM p2p links; the
  `wireguard` listen-port firewall rule audit (the pet's `udp dport 51820` may
  be unnecessary for a client-only tunnel); and the **DNS-leak policy** —
  whether `20-uplink.network` overrides the LAN-supplied `DNS` with the
  ProtonVPN resolver (`DNS=10.2.0.1` + `Domains=~.`) or drops the uplink DNS
  entirely. The DNS decision is security-relevant and belongs in the manifest.

**Cross-reference:** classifies the netVM of [ADR-009](DECISIONS.md#adr-009) as
a sysVM and gives it the build/control/update model ADR-009 left unspecified;
reuses the debootstrap → LV → chroot mechanism and external-kernel pattern of
[ADR-018](DECISIONS.md#adr-018) while diverging on init (systemd), machine (q35)
and storage (standalone linear RW, not thin/frozen); keeps the control channel
within the vsock-only rule of [ADR-003](DECISIONS.md#adr-003); scopes out of
[ADR-019](DECISIONS.md#adr-019) (`katmate-update` never touches netVM); required
by [ADR-020](DECISIONS.md#adr-020) (netVM must be a prebuilt, provisioned
artifact) and by [ROADMAP.md](../ROADMAP.md) step 4; the shared-protocol,
whitelisted appVM agent it splits from is the one specified in
[ADR-018](DECISIONS.md#adr-018).

**Revision note (2026-08-06, [ADR-030](DECISIONS.md#adr-030)):** two pointers
into `ROADMAP.md`'s build order move from *step 3* to *step 4*. ADR-030
inserted a step (VM description as data → launch daemon) and renumbered the
tail; the target — NetVM installer integration — is unchanged, as is every
decision in this ADR.

## ADR-022 — Network topology is a graph; the physical NIC is an assignable object

**Status:** Accepted (2026-07-14)

**Context:**

KatMate's release target ([ADR-020](DECISIONS.md#adr-020)) is a prebuilt host OS
that a user provisions and then *composes* into their own microVM desktop:
their own AppVMs, their own network exposure per AppVM. [ADR-021](DECISIONS.md#adr-021)
established netVM as a first-class **sysVM** class with a declarative build, a
privileged `netvm-agent`, a **static, appVM-agnostic** firewall, and isolation
carried by **topology** (per-appVM `/32` p2p links) rather than by per-appVM
firewall rules. It left the network *shape* of the system unstated: it described
one netVM, terminating one uplink, gatewaying every appVM.

That single-netVM picture cannot express the product requirement — "different
AppVMs with different network access" — without breaking ADR-021's own central
guarantee. Expressing per-appVM access *inside* one netVM would mean NETCFG
delivering firewall policy, which hands the `CAP_NET_ADMIN`-holding agent a
policy-mutation surface and re-introduces exactly the per-appVM firewall churn
ADR-021 removed. The isolation mechanism and the access-control mechanism would
collapse into one.

There is a second, independent problem the single netVM hides. Today netVM runs
the `r8169` driver plus a non-free Realtek firmware blob (`rtl8125b-2.fw`,
required per [ADR-021](DECISIONS.md#adr-021)) — the most exposed code in the
system, driving attacker-reachable hardware — **in the same VM that holds the
WireGuard private key**. Compromise of the NIC driver is compromise of the VPN
credentials. These are two different jobs at two different trust levels sharing
one address space.

Both problems have the same root: the network layer has no object model. There
is no object for "a physical NIC", no object for "a network policy", and no
object for "which network a VM is attached to".

**Decision:** the core models the network as a **graph of VMs**, and the
physical NIC as an **assignable host resource object**. The graph is data, not
structure baked into the code.

- **Object classes.** The core defines five, and only these:

  | Class | Nature | Notes |
  |---|---|---|
  | `Nic` | host inventory | PCI address, IOMMU group, binding (host / `vfio-pci`), `assigned_to: Option<VmRef>`. Assignable to **at most one** VM. The same shape later serves USB controllers and audio. |
  | `Image` | build artifact | foundation (RO) / `app-<type>` (RO thin snapshot) / sysVM image / instance delta. Orthogonal to runtime; unchanged by this ADR. |
  | `Vm` | runtime unit | name, class (`app` \| `sys`), CID, image ref, resources, **`netvm: Option<VmRef>`**, **`provides_network: bool`**. |
  | `Link` | runtime, host-owned | one p2p segment: TAP pair, `/32` addressing, the `.network` fragment delivered by NETCFG. Created at launch, destroyed at teardown. Owned by the launch daemon, never by a guest. |
  | `Policy` | two-layer | (a) compile-time opcode set per VM class (absent-not-disabled, [ADR-021](DECISIONS.md#adr-021)); (b) the static nft ruleset **baked into a netVM image**. |

  The entire topology is expressed by two fields on `Vm`: `netvm` (whom do I
  route through) and `provides_network` (may others route through me). Nothing
  else. A graph edge is a `Link`.

- **Policy is a netVM, not a rule.** An AppVM's network *access* is exactly
  *which netVM it is attached to*. Each netVM image bakes one fixed, immutable
  policy (`netvm-vpn`, `netvm-clearnet`, `netvm-lan-only`, …); differentiating
  access means attaching AppVMs to different netVMs, never mutating rules inside
  one. This preserves ADR-021's static, appVM-agnostic firewall verbatim: the
  ruleset still never changes as AppVMs come and go, and NETCFG still carries no
  policy.

- **`netvm: None` is a first-class offline AppVM.** An AppVM with no netVM
  reference gets no `Link` at all — no TAP, no route, no gateway. Air-gap is the
  absence of an object, not a firewall rule denying traffic. This is the
  strongest possible expression of the absent-not-disabled principle and is
  supported from v1.

- **One physical NIC = one q35 driver domain.** A VM holding a passed-through
  NIC is a **driver domain**: `-machine q35` (PCI topology for vfio,
  [ADR-009](DECISIONS.md#adr-009)), full systemd + networkd + initramfs +
  firmware ([ADR-021](DECISIONS.md#adr-021)), DHCP on the uplink — and **no
  secrets**. It terminates raw hardware and nothing else. Each physical NIC gets
  its own driver domain; a NIC is never shared between VMs.

- **Proxy netVMs are microVMs and may be chained.** A netVM that holds **no**
  physical NIC (a VPN terminator, an aggregating firewall) has only virtio
  links, therefore needs no PCI topology, therefore is a **microVM** — not q35,
  no initramfs, no firmware. Its uplink is just another p2p `Link`, delivered by
  the same NETCFG. Chaining (`appVM → netvm-vpn → netvm-driver → NIC`) is
  therefore cheap here in a way it is not in Xen/Qubes, where every domain
  carries the same weight.

  This chain is also the resolution of the driver/secret co-location problem:
  the WireGuard key moves into a proxy that **cannot see hardware at all**, and
  the NIC driver runs in a domain that **holds no key**. Compromise of `r8169`
  or the Realtek blob yields raw, already-encrypted traffic and nothing else.

- **v1 instantiates the simplest graph.** The shipped default is one driver
  domain terminating the uplink and carrying the VPN — i.e. exactly the netVM
  that runs today, unchanged. The split driver/VPN chain is a *paranoid profile*
  and a post-v1 configuration, not a v1 blocker. **The model is the graph; v1 is
  one node of it.** No existing work is discarded.

- **CID ranges are re-scoped for multiple sysVMs.** The current allocation
  (2 = host, 3 = netVM, 4–8 fixed AppVM, ≥100 disposable) assumes a single
  sysVM. Superseded by:

  | Range | Class |
  |---|---|
  | 2 | host |
  | 3–19 | sysVMs (3 remains the primary/default netVM) |
  | 20–99 | fixed persistent AppVMs |
  | ≥100 | dynamic disposable AppVM pool |

  The launch daemon and the domain indicator both read this range map; it is
  recorded in `state.md`.

- **The launch daemon is the only component that understands the graph.** It
  walks `netvm` references, allocates CIDs and `/32`s, creates `Link`s, and
  calls NETCFG on **each node of the path** at launch and teardown. It refuses
  to tear down a VM with `provides_network: true` while dependents are running.
  The agents stay dumb executors: `netvm-agent` installs the link it is handed
  and knows nothing of the graph it belongs to.

**Alternatives considered:**

- **One netVM with per-AppVM firewall rules** (the "single netVM does
  everything" model). Rejected: it makes NETCFG a policy-delivery channel,
  giving the privileged agent a rule-mutation surface, and re-introduces the
  per-appVM firewall churn ADR-021 removed. Isolation-by-topology and
  access-control-by-topology are the same mechanism here, deliberately.
- **Full Qubes-style mandatory chain (sys-net → sys-firewall → sys-vpn) from
  v1.** Rejected as v1 scope, not as an architecture: it multiplies the number
  of VMs that must boot before a desktop is usable, on a system with exactly one
  developer and no proven launch daemon. The graph model *permits* it; v1 does
  not *require* it.
- **NIC shared between VMs / hot-reassignable at runtime.** Rejected: vfio
  ownership is exclusive, FLR behaviour on the reference RTL8125 is already
  fragile (`disable_idle_d3=1`, [ADR-009](DECISIONS.md#adr-009)), and a
  reassignable NIC is a boundary that moves at runtime — the thing this design
  consistently refuses.
- **Keeping the VPN key in the driver domain** (status quo). Not rejected for
  v1 — it *is* v1 — but recorded as a known co-location, resolved by the proxy
  chain post-v1.

**Consequences:**

- **`Nic` becomes a host inventory object the installer must populate**, which
  makes IOMMU-group quality a **hard hardware requirement** for KatMate, not an
  implementation detail. A driver domain is only possible where the NIC sits in
  a clean, isolable IOMMU group. This implies an **HCL and an installer preflight
  check** (Qubes ships an HCL for precisely this reason). Recorded in
  `ROADMAP.md`; not a v1 blocker, but a product blocker.
- **The shared microVM kernel will need `CONFIG_WIREGUARD` + the nft/netfilter
  set** once proxy netVMs exist, because proxies are microVMs and there is only
  one microVM kernel ([ADR-021](DECISIONS.md#adr-021) rejected a second kernel).
  This code is dead in an AppVM — `vm-agent` runs as uid 1000 without
  `CAP_NET_ADMIN` and cannot reach it — but it is *present*, which is a real (if
  small) departure from absent-not-disabled at the kernel level. **Not folded
  into the pending rebuild** (`HW_RANDOM_VIRTIO` + `SECURITY_LANDLOCK`); it is
  taken up with the proxy work, deliberately.
- **The init model of a proxy netVM is left open.** ADR-021 binds netVM to
  systemd because of `networkd`/DHCP **on the uplink**. A proxy has no uplink
  DHCP — its uplink is a static p2p link delivered by NETCFG — and `wg` + `nft`
  need no networkd. A proxy may therefore be a `katmate-init` sysVM. That is a
  separate decision, taken when the first proxy is built.
- **The domain indicator gains meaning it did not have.** With a graph, "which
  domain am I looking at" also implies "which network is it on". The
  waybar/border indicator should ultimately encode the netVM attachment, not
  merely the CID.
- **`state.md` CID map and `ARCHITECTURE.md` object model are updated by this
  ADR.**

**Cross-reference:** gives the netVM of [ADR-021](DECISIONS.md#adr-021) a
topology it lacked, without weakening any of its guarantees (static firewall,
appVM-agnostic image, absent-not-disabled opcode split) — it generalises them.
Retains the vfio/passthrough constraints of [ADR-009](DECISIONS.md#adr-009) and
scopes them to the driver-domain class. Constrains the NETCFG payload, which is
specified in [ADR-023](DECISIONS.md#adr-023). The launch daemon it presupposes
remains a future ADR.

## ADR-023 — NETCFG describes a link, never an AppVM

**Status:** Accepted (2026-07-14) — wire format and semantics normative;
in-guest implementation mechanism deferred to `netvm-agent` implementation.

**Context:**

[ADR-021](DECISIONS.md#adr-021) introduced NETCFG as a typed, privileged opcode
on `netvm-agent`: it installs a validated network-configuration fragment and is
called by the **host** at AppVM launch and teardown. It deliberately left the
payload unspecified.

[ADR-022](DECISIONS.md#adr-022) now makes that payload's shape decidable — and
constrains it hard. In a graph, the same NETCFG call must serve two structurally
identical but semantically different edges:

- host → `netvm-driver`: "add a p2p link to the AppVM at CID 42"
- host → `netvm-driver`: "add a p2p link to the **proxy netVM** at CID 4"
- host → `netvm-proxy`:  "your **uplink** is a p2p link to CID 3"

If the payload names AppVMs, it can only ever express the first. If it names
*links*, it expresses all three with one opcode and one validator — and the
privileged agent never learns what a graph is.

**Decision:** the NETCFG payload is a **structured description of one p2p link**
and contains **no notion of AppVM, no notion of role, and no policy**.

- **Payload is link-scoped, VM-agnostic.** The wire structure describes:
  interface selection (match), local address, peer address, prefix (`/32`),
  route(s), and metric. It does **not** contain: a VM name, a VM class, the
  words *app* or *proxy*, a trust level, a firewall rule, an nft expression, or
  a shell string. A reader of the payload cannot tell whether the peer is an
  AppVM, a proxy netVM, or the host.
- **Direction is expressed by the link, not by a flag.** An "uplink" and a
  "downlink" differ only in addressing and route — not in opcode, not in payload
  type. There is exactly one link concept.
- **Two operations: `add` and `remove`.** NETCFG installs a link or withdraws
  it, identified by a stable link id supplied by the host. It is idempotent per
  id. There is no `modify` — a changed link is a remove followed by an add,
  because a mutable link is a boundary that moves in place.
- **Validation is total and structural.** `netvm-agent` accepts only a
  well-typed payload with a `/32` prefix on the internal segment
  (`10.100.1.0/24`) and a link id it owns; anything else is rejected at decode,
  not sanitised. The agent never concatenates, never templates, never shells
  out. Consistent with [ADR-021](DECISIONS.md#adr-021)'s "typed command, never a
  generic RUN".
- **Policy stays out.** No NETCFG variant may deliver an nft rule or alter the
  baked firewall. Differentiated network access is expressed by *which netVM a
  VM attaches to* ([ADR-022](DECISIONS.md#adr-022)), never by NETCFG. This is the
  hard boundary of the opcode and the reason the privileged agent's surface stays
  at exactly one job.
- **The host is always the caller.** NETCFG is never initiated by a guest, never
  relayed guest-to-guest. The mutation always arrives from the more-trusted side
  ([ADR-003](DECISIONS.md#adr-003), [ADR-021](DECISIONS.md#adr-021)).
- **Opcode wire value** is registered in the shared `katmate-protocol` opcode
  wire-value registry, but the **handler exists only in `netvm-agent`**; `Op` in
  `vm-agent` cannot name it and fails at `TryFrom<u8>` (absent, not disabled).
- **Deferred to implementation:** *how* the agent effects the link in the guest
  — writing a `systemd-networkd` `.network` fragment plus `networkctl reload`
  (ADR-021's assumption, correct for a systemd driver domain) versus programming
  it directly over `rtnetlink` (which would also serve a future `katmate-init`
  proxy, [ADR-022](DECISIONS.md#adr-022)) — is **not fixed here**. Both satisfy
  this ADR: the wire contract is what is being decided, and it is
  mechanism-independent by construction. The choice is made in the
  `netvm-agent/main.rs` implementation session, with the fragment path as the
  default until a proxy forces the question.

**Alternatives considered:**

- **Payload names the AppVM** (`{cid, name, addr}` with AppVM semantics).
  Rejected: cannot express a proxy's uplink, so a chained topology would need a
  *second* privileged opcode — doubling the privileged surface to say the same
  thing twice.
- **Payload carries an nft snippet or firewall rule.** Rejected outright: it
  converts `netvm-agent` from a link installer into a policy engine, hands a
  `CAP_NET_ADMIN` process a rule-injection surface, and destroys ADR-021's static
  firewall guarantee. Policy is an image property; see
  [ADR-022](DECISIONS.md#adr-022).
- **A generic `NETCMD` taking a config string.** Rejected: it is `RUN` with
  extra steps, in the most privileged guest in the system.
- **`modify` as a third operation.** Rejected: in-place mutation of a live
  boundary. `remove` + `add` is auditable, idempotent and has one failure mode.

**Consequences:**

- One opcode, one validator, one payload type covers AppVM links, proxy uplinks
  and future sysVM-to-sysVM edges. The privileged agent's code does not grow when
  the topology does.
- `netvm-agent` remains a **dumb executor**: it installs the link it is handed
  and has no representation of the graph, no list of AppVMs, no policy. The graph
  lives entirely in the host-side launch daemon
  ([ADR-022](DECISIONS.md#adr-022)).
- Because the payload is mechanism-independent, a future `katmate-init` proxy
  netVM (no systemd, no networkd) is reachable **without a wire-format change**.
- The immediate implementation gate is unchanged: `netvm-agent` listener first
  (`ping-client ping 3 → OK`), NETCFG handler second.

**Cross-reference:** specifies the payload
[ADR-021](DECISIONS.md#adr-021) deferred; constrained by the object model of
[ADR-022](DECISIONS.md#adr-022); stays within the vsock-only, host-as-caller
channel rule of [ADR-003](DECISIONS.md#adr-003); the opcode registry and split
`Op` enums are those of ADR-021 / the `katmate-protocol` workspace.

## ADR-024 — netVM SHUTDOWN returns to the agent: ask PID 1 via SIGRTMIN+4 under CAP_KILL

**Status:** Accepted (2026-07). Partially supersedes
[ADR-021](DECISIONS.md#adr-021): its shutdown model (host QMP → ACPI → logind)
and the agent privilege set are replaced; every other ADR-021 decision —
including its rejections of `CAP_SYS_BOOT` and of dbus/polkit in netVM —
**remains in force** and is reaffirmed below.

**Context:** [ADR-021](DECISIONS.md#adr-021) ruled netVM shutdown off-agent:
the host sends QMP `system_powerdown`, the ACPI power-button event is turned
into a clean stop by `systemd-logind`, and the agent carries no SHUTDOWN
opcode and no shutdown privilege. Live testing on 2026-07-17 proved the path
inert: `system_powerdown` registers in the guest (`Power Button [PWRF]`) and
nothing happens, because logind — binary and unit both present in the image —
never runs. logind requires dbus, and the manifest ships neither `dbus` nor
`libpam-systemd`.

That absence is not an oversight to patch; it is ADR-021's **own** decision.
The same ADR's alternatives section rejects "logind over dbus/polkit" because
it "would drag dbus + polkitd — a privileged daemon with a poor CVE history —
into the most network-exposed VM". ADR-021 therefore rejected the dependency
and accepted the design that depends on it. Both halves are individually
sound; jointly they are vacuous. The root error is the premise that the
machine type provides the lever: q35/ACPI delivers the power-button *event*,
but an event without a userspace *handler* is nothing, and every viable
handler (logind, acpid) costs surface the event was supposed to make
unnecessary. The asymmetry "appVM needs an in-guest SHUTDOWN because microvm
has no ACPI; netVM does not because q35 has ACPI" was never actually
purchased.

The target behaviour itself is intact: `systemctl poweroff` from the root dev
console performs a full clean stop (networkd/wg/nftables down, filesystems
unmounted, RTL8125 released). Only a *permitted, low-surface trigger* was
missing. All candidate triggers were tested live (2026-07-17, running
`vm_sys_netvm`):

| # | Path | Test | Result |
|---|---|---|---|
| E1 | QMP → ACPI → logind | `system_powerdown` (QEMU monitor) | inert — event registered, no handler; logind not running (no dbus) |
| E2 | baseline | root console `systemctl poweroff` | clean graceful stop — target behaviour exists in the image |
| E3 | acpid | packaged (socket-activated) acpid + power-button handler | daemon never wakes — the event does not arrive via `/run/acpid.socket`; works only with a hand-rolled daemon-mode override unit |
| E4 | non-root `systemctl` | `runuser -u nobody -- systemctl poweroff` | `Failed to connect to system scope bus` — no bus without dbus |
| E5 | systemd private socket | `ls -l /run/systemd/private` | `srwx------ root root` — unreachable for a non-root agent |
| E6 | negative control | `nobody`, **no** CAP_KILL: `kill -s RTMIN+4 1` | `EPERM`; VM stays up |
| E7 | signal, root | root: `kill -s RTMIN+4 1` | full graceful poweroff: stop jobs → umount → `/` remounted ro → ACPI S5 |
| E8 | signal, production profile | `setpriv --reuid nobody --regid nogroup --clear-groups --ambient-caps +kill --inh-caps +kill kill -s RTMIN+4 1` | identical full graceful poweroff |

E6 + E8 together prove `CAP_KILL` is both **necessary and sufficient** for a
non-root process to trigger the clean poweroff. (Methodology note: E8 uses
`setpriv` because `systemd-run` itself needs the system bus and fails on this
image — the no-dbus constraint cuts that deep.)

**Decision:** SHUTDOWN becomes a handled opcode in `netvm-agent`. The handler
asks PID 1: it sends `SIGRTMIN+4` to systemd, which starts `poweroff.target`
— systemd's documented direct-signal interface, byte-for-byte the same clean
stop as `systemctl poweroff`, with no bus, no logind, no polkit involved.

- **Wire:** opcode SHUTDOWN (`0x05`, existing shared-registry value; no
  registry or protocol-version change). No payload, mirroring the appVM
  SHUTDOWN. Caller authentication is the existing host-CID accept guard on
  the connection; no per-opcode auth. Response: `OK`, after which the
  connection dies as the VM powers off — the client treats connection loss
  after `OK` as expected.
- **Handler order mirrors `vm-agent`: reply first, act second.** `write_ok`
  goes on the wire *before* the signal, because the poweroff sequence stops
  `netvm-agent.service` early (observed live in the E7/E8 console output) —
  a reply attempted after the signal races the agent's own death. The cost is
  the same one `vm-agent` accepted: if the `kill(2)` itself fails after `OK`
  was sent, the client holds a false `OK` (mitigation: log at error level).
- **Signal number is resolved through libc at runtime** (`SIGRTMIN` is not a
  constant under glibc; in Rust, `libc::SIGRTMIN() + 4`), never hardcoded.
- **Unit:** `AmbientCapabilities=CAP_NET_ADMIN CAP_KILL`; `NoNewPrivileges`,
  `ProtectSystem=strict` and the rest of the sandboxing unchanged.
- **Privilege honesty — what CAP_KILL actually grants.** CAP_KILL allows
  signalling any in-VM process. Against PID 1 it exposes exactly systemd's
  documented signal API (poweroff/reboot/halt and friends; `SIGKILL` to init
  is undeliverable by the kernel) — i.e. VM lifecycle control, which is
  precisely the job being granted. Against other processes it allows DoS —
  which compromise of this agent already implies via `CAP_NET_ADMIN` over the
  entire network path. `CAP_KILL` adds no qualitatively new power to the
  agent's compromise model.
- **The `CAP_SYS_BOOT` rejection is reaffirmed, on two further grounds.**
  (a) Under systemd as PID 1, `reboot(2)` from a non-init process powers the
  kernel off *without* stopping units, unmounting or syncing — a dirty ext4
  on the RW LV every time; it is precisely not graceful. The appVM case is
  different because there `katmate-init` **is** PID 1 and performs its own
  teardown before calling `reboot(2)` — asking PID 1 versus bypassing it.
  (b) `CAP_SYS_BOOT` also unlocks `kexec_load(2)` — a kernel-replacement
  primitive — in the most exposed VM. A signal is not in the same class.
- **Symmetry restored, one level deeper than ADR-021's asymmetry.** Graceful
  shutdown is uniformly *ask your own PID 1*: `vm-agent` →
  `/run/katmate-init.sock` → `katmate-init` → `reboot(2)`; `netvm-agent` →
  `SIGRTMIN+4` → systemd → `poweroff.target`. The transport differs by init
  system; the trust shape — host command → guest's own agent → guest's own
  PID 1 — is identical.
- **Opcode model after this ADR:** the shared set is exactly the lifecycle
  pair (PING, SHUTDOWN); the disjoint sets are exactly the class jobs
  (NETCFG ↔ netVM; RUN/FILEPUT/FILEGET ↔ appVM). Absent-not-disabled now
  separates precisely the privilege-asymmetric opcodes.
- **The agent stays graph-ignorant.** It never checks for dependent appVMs;
  refusing to shut down a `provides_network` VM with live dependents is the
  launch daemon's interlock ([ADR-022](DECISIONS.md#adr-022)), host-side —
  same dumb-executor principle as [ADR-023](DECISIONS.md#adr-023).
- **The QMP shutdown wiring is retired.** The planned
  `-qmp unix:...` socket + host send tool are no longer part of the shutdown
  design (QMP may return later for other host-side management; that is a
  separate decision). dbus, polkit and acpid all stay **out** of the
  manifest.

**Alternatives considered:**

- **Ship `dbus` (+`libpam-systemd`) so logind runs; keep the QMP path.**
  Rejected. It reinstates the exact surface ADR-021 refused to ship, in the
  most network-exposed VM, to buy a shutdown path the agent provides with one
  capability bit — and it is the longest event chain on offer (QEMU ACPI
  emulation → guest kernel → logind policy → `poweroff.target`) versus one
  signal.
- **acpid as a narrow power-button handler.** Rejected empirically (E3):
  Debian packages acpid socket-activated, and the power-button event does not
  traverse `/run/acpid.socket`, so the daemon never wakes. Making it work
  requires a hand-rolled daemon-mode override unit — a divergence from the
  packaged service plus a new always-on event-parsing daemon, in the most
  exposed VM. More surface and more fragility than a signal.
- **`CAP_SYS_BOOT` + direct `reboot(2)`.** Rejected; see above — ADR-021's
  grounds stand, strengthened by non-gracefulness under systemd PID 1 and by
  `kexec_load(2)`.
- **`systemctl poweroff` from the agent.** Dead twice over (E4, E5): no
  system bus without dbus, and `/run/systemd/private` is root-only.
- **Leave it (QMP `quit` / kill QEMU).** Not a shutdown model: an ungraceful
  stop dirties ext4 on the RW LV on every teardown — the exact problem under
  repair.

**Consequences:**

- `netvm-agent`: `Op` gains `Shutdown`; `main.rs` gains `handle_shutdown`
  (reply-first, then `libc::kill(1, libc::SIGRTMIN() + 4)` best-effort). Wire
  and registry unchanged; `ping-client` already encodes SHUTDOWN, so the live
  gate needs no client work — `ping-client shutdown 3` flips from `ERR`
  (absent, proven 2026-07-17) to `OK` + clean poweroff.
- `vm-agent` doc comment (main.rs, the netVM/QMP note) claims netVM carries
  no SHUTDOWN — now false; corrected in the same code session.
- `netvm-agent.service`: `AmbientCapabilities` gains `CAP_KILL`.
- `netvm.list` is **unchanged** — no dbus, no acpid. The hand-installed acpid
  and the unlocked root account in the live image are experiment remnants;
  the image is disposable (ADR-021), so the next `netvm.sh` rebuild erases
  them — no manual cleanup of a live image.
- ADR-021's status line gains a pointer: shutdown model and agent privilege
  set superseded by this ADR; all else in force.
- Open problem #10 closes on the live gate; the QMP-wiring Next-step items
  drop from `state.md`.
- The launch daemon (future ADR) calls SHUTDOWN as an agent opcode for netVM
  teardown instead of QMP; its dependent-appVM interlock is unchanged in
  shape.

**Cross-reference:** partially supersedes [ADR-021](DECISIONS.md#adr-021)
(shutdown bullet, opcode-table row, privilege bullet) while reaffirming its
rejections of `CAP_SYS_BOOT` and of dbus/polkit; stays within the vsock-only
host-caller/guest-executor trust direction of
[ADR-003](DECISIONS.md#adr-003); restores full symmetry with the appVM
SHUTDOWN of [ADR-018](DECISIONS.md#adr-018) (`katmate-init`,
`reboot(RB_AUTOBOOT)`); shares the dumb-executor/no-graph principle of
[ADR-023](DECISIONS.md#adr-023); the dependent-VM interlock belongs to the
launch daemon anticipated by [ADR-021](DECISIONS.md#adr-021) and
[ADR-022](DECISIONS.md#adr-022).

## ADR-025 — NETCFG payload: fixed binary layout, v1-tight total validation, convergence over rollback

**Status:** Accepted (2026-07-20); mechanism resolved to Path B (2026-07-21);
implemented and live-gated (2026-07-23, 7/7 criteria). Implements the wire
contract [ADR-023](DECISIONS.md#adr-023) left abstract. Partially supersedes
one ADR-023 clause: the networkd-fragment mechanism was demoted from *default*
to *co-candidate* pending an empirical gate (E1–E5, below), and that gate
rejected it; every other ADR-023 decision remains in force.

**Context:**

[ADR-023](DECISIONS.md#adr-023) fixed NETCFG's semantics — one p2p link,
`add`/`remove` only, idempotent per host-supplied link id, no VM notion, no
policy, host the only caller — and deferred the byte encoding, the validation
rules, the partial-failure semantics and the in-guest mechanism. Three facts
discovered since it was written reshape the mechanism question:

1. **The ADR-023 default mechanism has an unverified precondition of exactly
   the class that killed ADR-021's shutdown model.**
   [ADR-024](DECISIONS.md#adr-024)'s empirics (E4, E5) proved the no-dbus
   constraint cuts deep: no system bus exists, `systemd-run` itself dies, and
   `/run/systemd/private` is root-only. `networkctl reload` is classically a
   system-bus call to `org.freedesktop.network1.Manager.Reload` — on this
   image it is *expected* inert, and assuming otherwise would repeat ADR-021's
   error (an accepted design standing on a lever nobody verified).
2. **DAC, not sandboxing, blocks the fragment directory.**
   `/run/systemd/network` is root-owned; `ReadWritePaths=` relaxes the unit
   sandbox but does not grant file permissions. A non-root agent cannot write
   there without a manifest-level `tmpfiles.d` ownership change.
3. **The declarative launcher carries no internal netdev at all.** The
   internal p2p device class (tap + `virtio-net-pci`) was proven only on the
   retired pet launcher; `net-sys.con` attaches vsock, virtio-blk, the vfio
   uplink and a 9p share — nothing NETCFG could configure. The
   `10-personal.network`/`enp0s4` convention in prior notes described a device
   that has never existed on the declarative launcher. (Forensic aside: the
   pet's netdev MAC `52:54:0A:64:11:01` byte-encodes `10.100.17.1` — the
   wrong-subnet bug the pet's nftables carried, preserved in its MAC.)

**Decision — wire format.** The NETCFG payload (opcode `0x06`, existing
registry value, riding the existing frame payload field) is a **fixed binary
layout with one count-prefixed, bounded route array**. Not TLV, not a
serialization library.

| offset | size | field | validation (total, at decode) |
|---|---|---|---|
| 0 | 1 | `op` | `0x01` ADD, `0x02` REMOVE |
| 1 | 4 | `link_id` | u32, `!= 0`, host-allocated, opaque |
| — | — | *REMOVE ends here* | total length `== 5` |
| 5 | 6 | `match_mac` | unicast + locally-administered bit set |
| 11 | 4 | `local_addr` | `== INTERNAL_LOCAL` (`10.100.1.1`) |
| 15 | 4 | `peer_addr` | `∈ 10.100.1.0/24`, `∉ {network, broadcast, local}` |
| 19 | 1 | `peer_prefix` | `== 32` |
| 20 | 1 | `route_count` | `1..=4` |
| 21 | 9·n | routes: `dest` u32 + `prefix` u8 + `metric` u32 | v1: `dest == peer_addr && prefix == 32`; metric any u32 |

ADD total length `== 21 + 9n` (30–57 bytes), exact match or ERR. Multi-byte
fields use the byte order `katmate-protocol::frame` already enforces —
normative is *consistency with the frame convention*, the concrete order is
read from `frame.rs` at implementation, not assumed here.

- **No in-payload version byte.** A changed shape mints a new wire value in
  the shared registry; the registry *is* the versioning mechanism. A version
  byte would put a runtime version branch into the privileged parser to buy
  what the registry provides for free.
- **The locally-administered MAC rule is structural uplink protection.**
  Physical NICs carry OUI (globally-administered) MACs; the rule makes the
  RTL8125 unreachable by construction, without the agent knowing which MAC
  the uplink has. The image stays generic; the guarantee costs one bit test.
- **Wire general, validator v1-tight.** The format can already express a
  proxy uplink (default route via peer); the v1 driver-domain validator
  rejects everything but the single `peer/32` route. When the first proxy is
  built, its agent loosens per-binary validation *constants*
  (`INTERNAL_LOCAL`, the route restriction) — never the wire.
- Bounds: `MAX_ROUTES = 4` (parser hygiene — a small constant instead of the
  u8 range, for capability the v1 has no use for) and `MAX_LINKS = 128`
  active links agent-side (ADD of a *new* id at the cap → ERR;
  identical-ADD unaffected). Both are hygiene, not trust boundaries.

**Decision — semantics.**

- **Idempotence per id.** ADD, id absent → install → OK. ADD, id present,
  byte-identical → OK, and the mechanism is still re-driven (see convergence).
  ADD, id present, different → ERR — no modify (ADR-023). REMOVE, id present
  → withdraw → OK. REMOVE, id absent → OK.
- **State is the filesystem; the process is stateless.** Each installed link
  is a record that is a deterministic function of the validated payload,
  written atomically (tmp + rename); identical-ADD is decided by byte
  comparison. Agent restart loses nothing — state is re-read from the record
  set. The agent owns exactly its record namespace and touches nothing else
  (ADR-023: "a link id it owns").
- **State is boot-scoped by design.** Records (and fragments, if that path
  wins) live under `/run` — volatile. This refines ADR-021's "runtime state
  on the RW LV": `/run` satisfies *outside the baked image* more strictly,
  and boot-volatility matches the model in which the launch daemon owns the
  graph and must re-issue every link after a netVM restart anyway (hotplugged
  appVM netdevs do not survive one either).
- **Convergence, not rollback.** Every operation is a full idempotent pass;
  ERR leaves a state that a retry of the *same* operation completes. No
  rollback code exists — it would be a second failure surface buying nothing
  idempotent retry does not already provide. Honest contract: OK = the
  postcondition was reached; ERR = re-issue or escalate — never "nothing was
  touched". Ordering rule per direction: **ADD writes the record before
  driving the mechanism** (a crash leaves a record the retry completes);
  **REMOVE drives the mechanism before deleting the record** (a crash leaves
  a record the retry re-deletes; the inverse order can orphan live kernel
  state with no record — the one unrecoverable shape, hence forbidden).
- **Device presence is not payload validity.** A payload naming a
  not-yet-present interface is valid; whether it fails retryably (rtnetlink
  `ENODEV` → ERR) or waits (networkd applies on appearance) is mechanism
  behaviour. Encoding presence into validation would couple the wire to
  hotplug ordering.
- **Reply ordering: act first, reply second** — the deliberate mirror of
  ADR-024's inverse. SHUTDOWN replies first because the act kills the agent;
  NETCFG's reply *is* the postcondition report and the agent survives it.
- **Response is OK/ERR only**, reason logged at error level in the agent (the
  existing error path). No reason codes in v1.
- **Caller authentication** is the existing host-CID accept guard; no
  per-opcode auth (ADR-024 precedent).
- **Privilege honesty.** Validation is not a trust boundary against the host
  — the host is the more-trusted side by architecture (ADR-003). Its function
  is decode totality plus blast-radius limiting for launch-daemon bugs, and
  this ADR says so rather than implying a boundary that does not exist.

**Decision — mechanism: two candidates behind an empirical gate.** Decided in
the implementation session, after E1–E5 on the running netVM — empirics
before commitment, the ADR-024 method, adopted because ADR-021's shutdown
model died of an assumed mechanism precondition.

- **Path A — networkd fragment.** Agent writes
  `/run/systemd/network/50-katmate-<id8hex>.network` (the fragment is the
  record) and triggers a reload. Preconditions, both open: (A1) a dbus-less
  reload trigger must exist; (A2) DAC on `/run/systemd/network` needs a
  `tmpfiles.d` group-ownership line in the manifest. Strength: tolerance of
  device-later ordering — networkd applies config when the NIC appears — and
  networkd owning link lifecycle (`IFF_UP` included).
- **Path B — direct rtnetlink.** Agent programs address + route + `IFF_UP`
  over an `AF_NETLINK` socket; `CAP_NET_ADMIN` suffices — no bus, no DAC, no
  reload. Records live in its `RuntimeDirectory=` as the raw validated ADD
  payload bytes. Load-bearing fact: the image bakes only the MAC-matched
  `20-uplink.network`, so internal virtio-net NICs are networkd-**unmanaged**
  and networkd will not disturb rtnetlink-programmed state — with the
  corollary manifest rule that **no catch-all `Match` may ever be baked**.
  Costs: netlink code in the privileged binary (hand-rolled minimal `RTM_*`
  vs. a crate — a dependency decision for the implementation session), and
  the device must exist at ADD time (true for the static NIC below; for
  hotplugged appVM NICs the launch daemon orders `device_add` before NETCFG).

E-gate (live netVM, agent's exact profile via `setpriv` — ADR-024
methodology):

| # | Probe | Prediction |
|---|---|---|
| E1 | `networkctl reload` with no dbus-daemon (root console, then agent profile) | inert — E4-class bus failure |
| E2 | reload on networkd's varlink surface, trixie systemd (introspect `io.systemd.Network` / `io.systemd.service`; do not assume) | absent |
| E3 | signal-based networkd reload | none exists — `ExecReload` is bus-based |
| E4 | DAC probe on `/run/systemd/network` + the `tmpfiles.d` group fix | EACCES stock; fix works, costs one manifest line |
| E5 | full Path-B dry run, zero code: `setpriv --ambient-caps +net_admin` driving `ip addr add` / `ip route add` / `ip link set up` on the static NIC, then teardown | works — proves the whole alternative under the production capability profile |

Decision rule: **A stands iff (E1 or E2 yields a working trigger) and E4's
manifest line is accepted; otherwise B.** Stated prediction, honestly: B wins.

**Mechanism resolved (2026-07-21): Path B.** E1–E5 run live under the
agent's capability profile. No dbus-less reload trigger exists: the
classical bus call is inert (E1), the varlink surface carries no
config-mutation method (E2, introspected — only `SetPersistentStorage`,
itself inert on the RO image), and the `notify-reload` unit type does not
honour `SIGRTMIN+1` as reload — the signal terminates networkd rather than
reconfiguring it (E3). Path B's rtnetlink programming (address + `/32`
route + `IFF_UP`) succeeds under `CAP_NET_ADMIN` alone — no bus, no DAC, no
root (E5, via `setpriv` mirroring the unit's ambient profile). The internal
netdev is networkd-`unmanaged` as the load-bearing corollary requires, so
rtnetlink-programmed state is undisturbed. `handle_netcfg` therefore
programs `AF_NETLINK` directly; the E4 `tmpfiles.d` DAC line is not needed.
Security note logged: the `io.systemd.Network` varlink socket is
world-writable (`srw-rw-rw-`) but its sole mutator is inert here — no
Path-A vector and no residual surface beyond it.

**Decision — launcher precondition.** `net-sys.con` gains one static internal
netdev (tap + `virtio-net-pci`, MAC `52:54:0a:64:01:01` — locally-administered
unicast, encoding `10.100.1.1` under the established scheme). A netVM restart
on launcher change is acceptable: sysVMs are not in the appVM hot-launch
path. The amended launcher is authored on Acer and **committed for the first
time** — the file has been MINIS-only since creation, a source-of-truth
invariant breach repaired here. Tap pre-creation/ownership for a non-root
QEMU joins the launch-daemon privilege-split work (dev: sudo). Dynamic MAC
derivation for real appVM links stays with the launch-daemon ADR.

**Alternatives considered:**

- **TLV encoding.** Rejected: optional fields are combinatorics against total
  validation; the single variable dimension (route list) needs only a bounded
  count.
- **serde/CBOR/postcard.** Rejected: a parser dependency in a `CAP_NET_ADMIN`
  binary, for a ≤57-byte payload.
- **In-payload version byte.** Rejected: a runtime version branch in the
  privileged parser; the registry is the versioning mechanism.
- **ERR reason codes.** Deferred, not adopted: idempotence makes coarse ERR
  livable (retry or escalate); revisit only if the launch daemon demonstrates
  a need to branch on failure class.
- **Transactional rollback.** Rejected: rollback code is a second failure
  surface; convergent retry subsumes it, and re-issuing desired state is a
  capability the graph-owning host needs anyway (netVM restart).
- **Fixing the mechanism in this ADR.** Rejected: the ADR-021 shutdown error
  exactly — an accepted design on an unverified precondition, found inert
  nine days later. The wire is decidable *now* because ADR-023 made it
  mechanism-independent; the mechanism is decidable only against the running
  image.
- **Segment-membership-only for `local_addr`** (no shared-local pin).
  Rejected: v1 has exactly one legal local; a free local buys generality only
  a proxy needs, and the proxy loosens a per-binary constant, not the wire.

**Consequences:**

- `katmate-protocol` unchanged (0x06 already registered; payload rides the
  existing frame payload field, well under `MAX_*`).
- `ping-client` gains `netcfg-add` / `netcfg-remove` subcommands
  (implementation session; the live gate needs them — the client predates
  0x06).
- `netvm-agent`: `handle_netcfg` replaces the honest ERR stub *after* the
  E-gate; unit changes follow the mechanism (A: `ReadWritePaths=` +
  `tmpfiles.d` group line; B: `RuntimeDirectory=`).
- **Live gate (minimal, this ADR's):** `netcfg-add → OK` → address + route
  (+ UP) visible on the static NIC in netVM; identical re-ADD → OK;
  conflicting ADD → ERR; `netcfg-remove → OK` → state gone; REMOVE of absent
  id → OK. End-to-end (an appVM routing through) belongs to the launch-daemon
  milestone, not here.
- **Gate criterion corrected (empirical).** Installing a point-to-point
  address causes the kernel to install its own route to the peer, at the
  default metric and under the kernel's own protocol id. A gate asserting
  merely that a route to the peer exists therefore passes even when the
  route-installing message was never sent; the gate must assert the route
  bearing the payload's metric. Two consequences follow: under the v1
  validator the payload's route is additive rather than load-bearing, since
  the implicit route's lower metric always wins; and teardown requires no
  separate step, because withdrawing the address withdraws the implicit route
  with it.
- **New Known Gap (SECURITY-MODEL.md, next free number):** the 9p hostshare
  in `net-sys.con` (`security_model=none`, `/home/host`, into the most
  exposed VM) — dev-only remnant class (sshd/dev-root), documented in no ADR,
  remove before release.
- ADR-021's status line finally receives the ADR-024 pointer its own
  consequences promised (repair of the `--amend`-on-wrong-HEAD casualty).
- The launch daemon explicitly inherits: `link_id` allocation, MAC
  derivation, tap/netdev pre-creation privilege, `device_add`-before-NETCFG
  ordering (under B), and re-issuing all links after a netVM restart.

**Cross-reference:** implements the wire contract of
[ADR-023](DECISIONS.md#adr-023) and demotes its mechanism-default clause;
adopts the empirics-before-commitment method and mirrors the reply-ordering
and privilege-honesty patterns of [ADR-024](DECISIONS.md#adr-024); stays
within the image/state separation of [ADR-021](DECISIONS.md#adr-021)
(refined: NETCFG state is boot-scoped) and the host-caller channel rule of
[ADR-003](DECISIONS.md#adr-003); segment and topology constants per
[ADR-022](DECISIONS.md#adr-022) and ARCHITECTURE.md.

**Revision note (2026-08-09, [ADR-030](DECISIONS.md#adr-030) §3):** the
launcher precondition above specifies the internal netdev's MAC as
`52:54:0a:64:01:01`, "encoding `10.100.1.1` under the established scheme".
[ADR-030](DECISIONS.md#adr-030) §3 forbids that practice — an address must not
be recoverable from a MAC — but cites only the retired pet launcher's
`52:54:0A:64:11:01`, whose visible defect was a *wrong subnet* preserved in the
bytes. It did not state that it also overturns this ADR's decision about the
live launcher. It does. ADR-030 is the later and normative decision, and this
note records the supersession rather than leaving the tree self-contradictory.

**Replacement:** MACs are derived, never authored —
`52:54:00` + the first three bytes of `sha256(<instance name>)`. Locally
administered, unicast, stable across reboots, no allocator state, no address in
the bytes.

**Nothing in this ADR's mechanism changes.** The wire validation above requires
of `match_mac` only that the address be unicast with the locally-administered
bit set, which the derivation satisfies (`0x52` = `0101 0010`). The internal
segment's address travels in `local_addr`, a separate field validated against a
constant, and the netVM image bakes no internal-segment `.network` unit —
`manifests/netvm.conf.d/` carries the MAC-matched **uplink** only, and Path B
programs the internal link by rtnetlink from the payload it is handed. **No
image rebuild is implied.** The change is confined to what the launcher — now
the projection generator — emits.

The `state.md` invariant naming `52:54:0a:64:01:01` as the internal segment's
identity is stale from the moment the generator lands, and is corrected in the
same pass.

**Revision note (2026-09-02, § *Replacement* — [ADR-035](DECISIONS.md#adr-035)
§2 scopes *"derived, never authored"*):** the *Replacement* paragraph above
states the rule without naming what it governs. ADR-035 §2 supplies the scope:
it governs **identity** MACs — a MAC that names an instance — and a netVM
link-pool slot is not an instance. The netVM side of pool slot `k` carries
`52:54:01:00:00:kk`, a pool constant written literally in T4, never projected
and derived from nothing; the two middle octets are reserved zero and will
never carry address bytes. The third octet `01` partitions slot MACs from the
`52:54:00` identity MACs this ADR's derivation produces, so the two classes
cannot collide by construction. ADR-035 rejects hash-derived slot MACs
explicitly, and on this ADR's own evidence: uniqueness across sixteen would
become probabilistic, and the agent returns a first match.

**Nothing in this ADR's mechanism changes.** The wire validation above requires
of `match_mac` only that the address be unicast with the locally-administered
bit set, and `0x52` satisfies it for both classes.

**This note records a supersession and changes no sentence above it.** It
narrows the rule rather than overturning it. ADR-035 is PROPOSED, none of its
six gates has been taken, and no pool exists — what is recorded here is the
scope a later ADR gives this ADR's rule, not an implementation.

**Revision note (2026-09-02, the payload table's `local_addr` row —
[ADR-035](DECISIONS.md#adr-035) §3):** the table above validates `local_addr`
totally against `INTERNAL_LOCAL` (`10.100.1.1`), and § *Alternatives considered*
reserves loosening that constant for the proxy case. ADR-035 §3 leaves the
constant exactly where it is and changes what it means. Under a sixteen-slot
link pool there are sixteen netVM-side interfaces, each ADD carries the same
`local_addr`, and every active slot holds `10.100.1.1/32`. **That sharing is now
by design, not by accident** — one gateway identity on every link, which is what
keeps any per-instance network fact out of an AppVM's configuration and lets
every AppVM image carry the same gateway.

**No validator constant moves and no sentence above is edited.** What changes is
that the constant is load-bearing in a way it was not when it was written as
*"v1 has exactly one legal local"*. That one address can be held on many
interfaces at once is a claim about the kernel, and ADR-035 gates it (G2) —
including the half a confirmation cannot show — rather than assuming it.

**This note records a supersession and changes no sentence above it.**

---

## ADR-026 — Domain indicator carriers: host-resolved waypipe CID, never guest-supplied window properties

**Status:** Accepted (2026-07-28; design settled 2026-07-27, final gate
closed 2026-07-28)

**Context:** The host compositor is inside the TCB because it draws the
domain indicator — the only visual separation between trust domains
([ADR-016](DECISIONS.md#adr-016)). An indicator is worth exactly as much
as the trustworthiness of the state it is keyed on. Sway exposes window
properties (`app_id`, `name`/title) that originate **inside the guest**
and are therefore attacker-controlled: a compromised AppVM can set
`app_id` to whatever another domain uses. Any indicator keyed on those
is decorative, not a security control.

The open question was whether the compositor exposes anything that
resolves to host-side state, and how.

**Decision:**

1. **Carrier set.** The indicator is carried by (a) a **waybar module**
   fed from host-side state — authoritative — and (b) the **focused
   border colour** (hue plus alpha). `sway/window` is never used: it
   renders guest-controlled titles.

2. **Rendering facts, verified 2026-07-27.** `#RRGGBBAA` is parsed *and
   rendered*, so alpha is a usable dimension of the colour carrier.
   `show_marks` draws only inside a titlebar, so marks are rejected
   under `border pixel`.

3. **Identity is resolved in two host-side steps, never read from the
   guest:**

   ```
   swaymsg -t get_tree   →  pid of the host waypipe client
   AF_VSOCK socket diag  →  peer CID of that pid's connection
   ```

   The compositor supplies a **pid**, not an identity. The pid is
   resolved to a guest CID by inspecting the host waypipe client's vsock
   connection. Both steps are host-side and trusted; no input crosses
   from the guest.

4. **`app_id` and window title are explicitly excluded** from the
   identity path, at any level, for any purpose.

**Evidence (live, MINIS, 2026-07-28):**

| # | Observation |
|---|---|
| E1 | `app_web` instance running, CID 5; `ping-client run 5 nautilus` → `status=0x00` |
| E2 | `swaymsg -t get_tree` exposes `pid` on the rendered window alongside `app_id: org.gnome.Nautilus`, `name: Home` |
| E3 | That pid resolves to the **host** waypipe client: `waypipe -s 1024 --vsock --threads 0 -c lz4 client-conn` |
| E4 | `ss -f vsock -p` on that pid: `v_str ESTAB 2:1024 ↔ 5:287463193` — local host CID 2 port 1024 (GUI), **peer CID 5** = the domain |
| E5 | `app_id` and `name` in E2 are guest-supplied and were ignored; only E3→E4 was used |
| E6 | The diag query requires no privilege: an unprivileged caller receives the same peer CID as `root` (verified 2026-07-28). The resolver is therefore not forced into a privileged process. |

E4 is the closure of the gate carried in `state.md` since 2026-07-27
("confirm `swaymsg -t get_tree` exposes a `pid` resolving to the waypipe
client process"). It resolves *further* than the gate asked: not only to
the process, but through it to the CID.

**Consequences:**

- **`vsock_diag` becomes a host-kernel dependency of the TCB.** The
  indicator cannot resolve identity without socket diagnostics for
  `AF_VSOCK`. Present on `linux-hardened` as shipped (verified by the
  `ss -f vsock` call above). This is now a **stated requirement**, not a
  convenience: a future host kernel configuration change that drops it
  silently disables the indicator's identity path.
- **The waybar module must not fork `ss`.** Forking a userspace tool per
  focus change is unacceptable form in a TCB component. Either query
  `SOCK_DIAG` over `AF_NETLINK` directly, or — preferred — have the
  launch daemon maintain the pid↔CID map and expose it, with the module
  as a pure reader. This makes the map a launch daemon responsibility,
  which is consistent with it already owning the topology graph
  ([ADR-022](DECISIONS.md#adr-022)).
- Hyprland/CYBRland remains a dev/demo profile until its own indicator
  implementation is separately verified ([ADR-016](DECISIONS.md#adr-016)
  revision).

**Open items (do not block acceptance):**

- **O1 — privilege of the diag query.** ~~Unverified.~~ **Closed 2026-07-28:**
  an unprivileged caller receives the same peer CID as `root`. The resolver is
  not forced into a privileged process; the launch daemon remains the preferred
  owner of the map for other reasons. See E6.

- **O2 — pid stability across multiple windows.** The pid was stable
  within one instance's lifetime. Behaviour with **two concurrent
  windows from the same domain** (a second `client-conn`), and across
  close/reopen, is **not verified**. If per-connection pids differ, the
  resolver must handle a set, not a single value. A host reboot between
  observations says nothing about this — a new boot means new pids by
  definition.

---

## ADR-027 — VMM containment is a precondition, not an alternative

**Status:** Accepted (2026-07-28)
**Amends:** [ADR-021](DECISIONS.md#adr-021) — scope of *absent, not
disabled*
**Blocks:** [ADR-028](DECISIONS.md#adr-028), any vhost-user device work,
sequencing of the `qemu-full` → `qemu-base` reduction

**Context:** A review of alternative VMMs surfaced a class of argument
this project had no vocabulary for, and consequently mis-filed.

The argument runs: *move a capability out of the host kernel and into a
userspace process; a bug there compromises one process rather than the
kernel.* It underwrites Firecracker/Cloud-Hypervisor "hybrid vsock",
vhost-user device backends, and device disaggregation generally.

The project initially read this as an instance of **absent, not
disabled**. It is not, and the distinction matters enough to write down,
because the principle is load-bearing elsewhere — it is the whole
justification for the two-binary agent split — and a diluted version of
it stops being a usable test.

### Three axes, not one

| # | Axis | Question | Test |
|---|---|---|---|
| 1 | **Existence** | Does the capability exist in this domain class at all? | Is it compiled / instantiated? |
| 2 | **Placement** | Where is it implemented, and how confined is that place? | Is the target more confined than the source? |
| 3 | **Enforcement** | Who holds the boundary? | Kernel-enforced, or dependent on userspace correctness? |

*Absent, not disabled* is the test for **axis 1 only**. Its canonical
instances stand unchanged: `netvm-agent` cannot decode `RUN` — a
forbidden opcode fails at `TryFrom<u8>`, not at a runtime gate
([ADR-021](DECISIONS.md#adr-021)); an AppVM with `netvm: None` has no
`Link` object, so the air-gap is the absence of an object
([ADR-022](DECISIONS.md#adr-022)).

Applied correctly to the vsock control channel, the same test gives: a
VM class that must have no control channel carries no
`-device vhost-vsock-device` on its command line. **The device is
absent. This project already satisfies axis 1 on that channel and needs
to change nothing to keep it.**

Moving virtio-vsock from `vhost_vsock` in the host kernel into a VMM
process or a vhost-user daemon removes **no** capability. The host↔guest
channel exists in full; one implementation is exchanged for another.
That is **relocation of privilege**, and it belongs on axis 2.

### Why the distinction has teeth

The relocation argument is not wrong. It is **conditional**, and the
condition is unstated wherever it is made. With the condition visible:

> Relocating a capability across a privilege boundary yields a security
> benefit **only in proportion to how much more confined the target is
> than the source.**

Applied to this system as of 2026-07-28, **after** the C4/C5b work
recorded below:

| | AppVM launcher (`app_web.con`) | netVM launcher (`net-sys.con`) |
|---|---|---|
| uid | invoking user (`sudo` used **only** for `lvchange`) | **root** (`sudo bash net-sys.con`) |
| seccomp | `-sandbox on` + four `deny` options | `-sandbox on` + four `deny` options |
| filesystem confinement | none (no chroot, no Landlock) | none |
| namespace | `init_netns` | `init_netns` |
| host filesystem exposure | none | none (9p removed 2026-07-28) |
| `memlock` | not required | shell `ulimit -l unlimited`, no unit |

The netVM VMM is the outstanding case: compromise of that process is,
for practical purposes, compromise of the host. Until it is confined,
relocating code *into* it buys close to nothing. Hardening the VMM
process is **not an alternative to the relocation argument — it is its
precondition.**

### netVM does not require a root VMM

Checked, because netVM is the most exposed domain and was launched as
root only as dev expedience. Three preparation steps need privilege.
**None of them is the QEMU process itself:**

| Step | Privileged today | Resolution |
|---|---|---|
| open `/dev/vfio/<group>` | yes | `vfio` group + udev rule (`SUBSYSTEM=="vfio", GROUP="vfio", MODE="0660"`) — already recorded in `state.md` as the template for the launch daemon's non-root QEMU |
| create `tap-int0` | yes | pre-create with `ip tuntap add … user <uid>` and hand over as `fd=`; no `CAP_NET_ADMIN` in the VMM |
| `lvchange -K -ay` | yes | already separated into launcher preflight; becomes `ExecStartPre=+` |

The pattern is a privilege-dropping launcher: prepare as root, then drop
to a per-VM uid before `exec qemu`. The one real obstacle is
`RLIMIT_MEMLOCK` — vfio pins the whole guest RAM and a non-root uid
needs the limit granted explicitly. Today this is an interactive
`ulimit -l unlimited` and there is no unit at all; a unit with
`LimitMEMLOCK=infinity` resolves it. **Configuration, not an
architectural constraint.**

**Decision:**

1. Record the three axes in `SECURITY-MODEL.md` and **scope *absent, not
   disabled* to axis 1**. Add a companion principle for axis 2:
   *relocation is not removal.*

2. Define a **containment gate (C-gate)** on the VMM process. Until it
   passes, **no axis-2 decision is implemented** — not vhost-user-vsock,
   not vhost-user block/net/fs, not a VMM change.

3. Treat the C-gate as a v1 work item on the launch daemon's critical
   path, not as post-v1 hygiene.

### C-gate criteria

Each is live-testable on MINIS in the ADR-024/ADR-025 style: a concrete
observable, not a claim.

| # | Criterion | Observable | Status |
|---|---|---|---|
| **C1** | VMM runs as a per-VM non-root uid | `ps -o user=` on the QEMU pid ≠ `root` | **partial** — holds for AppVMs today; open for netVM |
| **C2** | vfio reachable without root | netVM starts as that uid with `vfio` group + udev rule; no `permission denied` on `/dev/vfio/<group>` | open |
| **C3** | `memlock` granted by unit, not shell | `LimitMEMLOCK` visible in a unit; no interactive `ulimit` | open |
| **C4** | VMM seccomp filter active and tightened | `-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny`; `Seccomp: 2` in `/proc/<pid>/status`; no `SCMP_ACT_KILL` in `dmesg`; control path returns `0x00` | **PASSED 2026-07-28** |
| **C5a** | Filesystem confinement on the VMM | Landlock ruleset or chroot applied to the VMM process | open |
| **C5b** | No host filesystem export into netVM | `/proc/<pid>/cmdline` contains no `fsdev` and no `virtio-9p-pci` | **PASSED 2026-07-28** — closes gap #10 |
| **C6** | Per-VM network namespace | VMM process in its own netns; enables the vsock CID scoping in [ADR-028](DECISIONS.md#adr-028) | open |

**C4 evidence (live, MINIS, 2026-07-28):**

| # | VM | Observation |
|---|---|---|
| E1 | `app_web`, CID 5 | boots to `katmate-init`; `vm-agent launched as uid 1000 (pid 60)` |
| E2 | `app_web` | `Seccomp: 2`, `Seccomp_filters: 1` |
| E3 | `app_web` | `dmesg` grep for `seccomp`/`audit`: empty — no `SCMP_ACT_KILL` |
| E4 | `app_web` | `ping-client ping 5` → `status=0x00 (OK)` |
| E5 | netVM, CID 3 | `Seccomp: 2`, `Seccomp_filters: 1` |
| E6 | netVM | `vfio-pci 0000:01:00.0: resetting` / `reset done`, twice, both successful — the `FLReset-` / `disable_idle_d3=1` workaround is unaffected by the tightened filter |
| E7 | netVM | `ping-client ping 3` → `status=0x00 (OK)` |

The hypothesis that `resourcecontrol=deny` would collide with
`-object iothread` (QEMU setting thread scheduling properties) is
**refuted empirically**, on both machine types, rather than reasoned
about. E6 additionally clears the vfio path, which was the only
substantive risk: the `sched_*` and `setpriority` family is not on
QEMU's launch path here.

**C5b evidence:** `tr '\0' '\n' < /proc/<pid>/cmdline | grep -i '9p\|fsdev'`
returns empty for the running netVM. The proof is taken **host-side, and
that is the stronger form**: the device is absent from instantiation, so
the guest cannot mount what does not exist. This is an axis-1 proof, not
an axis-3 one. In-guest confirmation (`mount | grep 9p`) was deliberately
**not** performed: it would have required unlocking the guest root
account on a declaratively built LV, i.e. reintroducing exactly the
pet-drift that Open problem #6 closed. See the note under `state.md`
Open problem #12.

**Options considered:**

*A — treat hardening as post-v1 hygiene.* No work now; leaves the
largest single privilege item in the TCB unaddressed while the
documentation claims a minimal TCB. Blocks nothing visibly, which is
precisely why it would keep slipping. Rejected.

*B — change VMM to inherit better defaults.* crosvm ships per-device
processes with minijail and per-device seccomp, which is the strongest
disaggregation available. But it does not remove the C-gate, it
**renames** it: an unconfined crosvm is no better than an unconfined
QEMU. Cloud Hypervisor additionally conflicts with
[ADR-003](DECISIONS.md#adr-003) (see [ADR-028](DECISIONS.md#adr-028)).
Both discard the vfio maturity this project depends on — the RTL8125
passthrough with the `disable_idle_d3=1` / `FLReset-` workaround is
proven on QEMU and unproven elsewhere. Rejected: it swaps a known,
bounded hardening task for an unbounded porting task.

*C — gate axis-2 work behind VMM containment.* **Chosen.** Correct
dependency order; the work is bounded, local and already half-designed.
Each criterion is independently testable. Unblocks all vhost-user paths
at once rather than one at a time.

**Consequences:**

*Easier*
- Every later vhost-user decision (vsock, blk, net, fs, gpu) inherits
  one answered question instead of re-litigating containment per device.
- `qemu-full` → `qemu-base` gains a motive and an ordering: reduce the
  binary *and* confine the process, in that order.
- The TCB claim in `SECURITY-MODEL.md` becomes true rather than
  aspirational.

*Harder*
- The launch daemon can no longer be designed as "a thing that runs
  `.con` scripts". It owns privileged preparation and the drop, which
  makes it a larger ADR than currently scoped.
- The dev workflow loses `sudo bash net-sys.con`. A dev profile keeping
  the root path must be explicit and separate, in the ADR-016 style: one
  audited profile ships, the convenient one is dev-only.

*To revisit*
- Whether the per-VM uid is allocated statically (one uid per fixed VM)
  or dynamically for the disposable pool (CID ≥ 100). Interacts with the
  CID allocation model in [ADR-022](DECISIONS.md#adr-022).
- Landlock or chroot for C5a. Landlock does not require a prepared root
  tree, and — decisive for feasibility — **Landlock restrictions are
  inherited across `execve`**. A small `setpriv`-style wrapper can apply
  a ruleset and then `exec qemu`, so C5a needs no QEMU patch. QEMU has no
  built-in Landlock support and none is required.

---

## ADR-028 — virtio-vsock transport placement

**Status:** Accepted — the v1 decision is *no change*; option 3 recorded
and gated
**Depends on:** [ADR-027](DECISIONS.md#adr-027) (C-gate)
**Does not amend:** [ADR-003](DECISIONS.md#adr-003)

**Context:** [ADR-003](DECISIONS.md#adr-003) fixes **AF_VSOCK
exclusively** as the host↔guest channel. It governs the address family,
the CID namespace and the port map (1024 waypipe · 1025 control · 1026
audio). It says nothing about *where the virtio-vsock device model is
implemented*, because until now there was only one answer.

There are three, and the difference is material to the trust model.

| # | Placement | Runs in | Host-side API | A bug there compromises | Kernel-enforced netns |
|---|---|---|---|---|---|
| **1** | `vhost_vsock` (**today**) | host kernel | `AF_VSOCK` | the host kernel | yes (Linux 7.0) |
| **2** | hybrid, Firecracker-style | the VMM process | `AF_UNIX` + text framing | that VMM — which maps guest RAM and holds the KVM fd | no |
| **3** | `vhost-user-vsock` | a separate backend daemon | `AF_UNIX` **or** `AF_VSOCK` | that daemon — maps guest RAM, **no** KVM fd | unverified, see H1 |

QEMU and crosvm use placement 1. Firecracker and Cloud Hypervisor use
placement 2. **Placement 3 is available in QEMU today** (`vhost-user-vsock`
device, rust-vmm `vhost-device-vsock` backend) and therefore does not
require changing VMM.

### What placement 2 costs this project

Cloud Hypervisor's `virtio-vsock` derives from Firecracker's; its host
side is not `AF_VSOCK`. Host→guest requires connecting to the launch-time
Unix socket and prefixing the stream with `CONNECT <port>`, once per
connection. Guest→host requires the host to listen on a Unix socket whose
path is the launch-time path with `_` and the port number appended; the
guest dials the well-known CID 2. Full detail and provenance in
`docs/OBSERVATIONS.md` §2.

Consequences here, in order of severity:

1. **`waypipe --vsock` speaks `AF_VSOCK` on the host.** Placement 2
   requires either a per-connection proxy — a new component inside the
   TCB, sitting on the GUI channel — or a waypipe patch implementing the
   hybrid protocol. The latter is mechanically available
   ([ADR-019](DECISIONS.md#adr-019) already carries a patch queue) but it
   would make this project the maintainer of a behavioural divergence
   from upstream, and the "both binaries from one tree" invariant would
   no longer describe a tree that matches upstream in behaviour.

2. **Loss of kernel-enforced isolation.** The Linux 7.0 namespace work
   covers `vhost-vsock` and `vsock_loopback`. Placement 2 uses neither,
   so the `local`/`global` mechanism does not apply. Isolation would rest
   on DAC over Unix socket paths plus VMM correctness — userspace, not
   kernel.

3. **A new guest-influenced parsing surface:** text framing and host path
   construction from a guest-supplied port number. Bounded, and the
   implementations are mature, but this is a bug class that does not
   exist at all under `AF_VSOCK`.

4. **ADR-003's prose would need rewriting** even though its intent
   survives. The "no netfilter traversal, trivially firewalled" argument
   holds; the "AF_VSOCK exclusively" sentence would not.

**One point in placement 2's favour, stated plainly:** with it,
`vhost_vsock` need not be present in the host kernel at all, and future
defects in that subsystem would be out of scope. Note the provenance,
though — rust-vmm frames this as a *convenience* (testing vsock
applications on hosts without vsock support), not as a security claim.
Promoting a convenience note to a principle is exactly the error the
three axes in [ADR-027](DECISIONS.md#adr-027) guard against: this is
relocation, and its value is conditional on the C-gate.

### What placement 3 offers

`vhost-user-vsock` keeps the device model out of **both** the host kernel
and the VMM process, in a separate daemon that can be confined
independently — and, decisively for this project, it can still present
`AF_VSOCK` on the host side. The rust-vmm backend has two modes: a UDS
mode (Firecracker-compatible hybrid, inheriting all of placement 2's
costs, of no interest here) and a `--forward-cid` mode giving direct
`AF_VSOCK` ↔ `AF_VSOCK`, where guest connections are forwarded to a CID
on the host and the host application listens over `AF_VSOCK`.

In `--forward-cid` mode: guest virtqueue parsing happens in Rust in
userspace, `vhost_vsock` need not be loaded, and **waypipe on the host
still speaks `AF_VSOCK`**. ADR-003 survives untouched.

### The price of vhost-user, stated plainly

vhost-user requires **shared guest memory**: the backend maps the guest's
entire RAM, because it reads virtqueue descriptors pointing into the
guest address space. This holds in `--forward-cid` mode as much as in UDS
mode. It is not vsock-specific — it is the generic entry price for any
vhost-user backend. If the project moves toward device disaggregation at
all (the natural follow-on to ADR-027), the price is paid once and vsock
rides on infrastructure that already exists.

**Decision:**

1. **v1 stays on placement 1** (`vhost_vsock`). No change to launchers,
   agents, waypipe or ADR-003.

2. **Placement 2 is rejected** for this project, on grounds 1–3 above.
   Recorded so it is not re-proposed: the deciding factor is not
   performance or elegance but that it forces either a TCB-resident proxy
   on the GUI channel or a behavioural fork of waypipe, and gives up
   kernel enforcement to do so.

3. **Placement 3 is the only viable alternative** and is **gated behind
   the ADR-027 C-gate**. Its security value is conditional on the backend
   daemon being confined — own uid, seccomp, no KVM fd, ideally own
   netns. An unconfined backend is a lateral move, not an improvement.

4. **ADR-003 is not amended.** It governs address family and namespace;
   this ADR governs implementation location. Keeping them separate is
   deliberate — it is the axis-1 / axis-2 split from ADR-027 applied to
   one concrete channel.

### Open verification items

Hypotheses in the ADR-021 / ADR-025 Path-A class: mechanistic
assumptions that must be gated before they are relied on.

**H1 — netns isolation under `--forward-cid`.** The Linux 7.0 series adds
namespace support to `vhost-vsock` (H2G) and `vsock_loopback` (local).
`--forward-cid` to CID 1 traverses `vsock_loopback`, which is
namespace-aware, so isolation *should* hold with `vhost_vsock` unloaded.
**Not verified.** Gate: two backends forwarding to CID 1 in two
`local`-mode namespaces, a listener in each, cross-namespace connect must
fail.

**H2 — `vhost-user-vsock-device` on this project's `microvm`.** The mmio
variant exists, and QEMU's `nitro-enclave` machine type — itself based on
`microvm` — instantiates `vhost-user-vsock` over `virtio-mmio` in
mainline. **Not verified on this project's machine type with the
monolithic 6.12.x guest kernel.** Gate:
`-device vhost-user-vsock-device,chardev=…` instantiates on `vm_app_web`,
guest reaches host on port 1025, `ping-client` PING returns `0x00`.

**H3 — device-model equivalence.** Whether the rust-vmm backend's
virtio-vsock feature set matches what `katmate-protocol` and waypipe
assume. SEQPACKET is not used; STREAM only — likely fine, unverified.

### netns scoping — separable, available today

Independent of placement, Linux 7.0 makes vsock namespace-aware and this
is usable **now**, on placement 1, on the current MINIS host kernel
(7.0.12-arch1-1).

Mechanism: `/proc/sys/net/vsock/child_ns_mode` (`global` | `local`) sets
the mode inherited by *new child* namespaces;
`/proc/sys/net/vsock/ns_mode` is read-only and immutable after namespace
creation. A VM started by a VMM inside a `local` namespace is reachable
only from that namespace. CIDs may then repeat across namespaces.

**What it fixes here:** today any host process can reach *any* VM's agent
on port 1025 — the CID space is global on the host. The waypipe host user
service, for instance, has no need to reach netVM's agent and currently
can. Tracked as `SECURITY-MODEL.md` gap #12.

**Costs, all real:**

- `child_ns_mode` is **write-once**: the first write locks the value, and
  a subsequent differing write returns `-EBUSY`. This is an architectural
  decision taken once at daemon start, not a runtime toggle.
- The launch daemon must reach *every* VM, so it must enter each
  namespace or hold per-namespace sockets. That shapes where the daemon
  lives.
- G2H transports (virtio, hyperv, vmci) are **not** namespace-aware yet:
  a guest cannot create its own `local` namespace and still reach the
  host. Irrelevant to the current flat topology; relevant if nesting is
  ever considered.

**Interaction with [ADR-026](DECISIONS.md#adr-026), important:** if CIDs
may repeat across namespaces, then the domain indicator's identity is no
longer a CID but the pair **(netns, CID)**. The pid→CID resolution in
ADR-026 must be revisited at the same time as C6, not after. This is the
single hardest coupling introduced by netns scoping and is the reason C6
is listed separately in the C-gate rather than folded into C1–C3.

**Consequences:**

*Easier*
- The VMM question is now decoupled from the vsock question. "Should we
  move to a smaller VMM?" no longer drags ADR-003 with it.
- If device disaggregation happens, vsock is a line item on existing
  infrastructure, not a separate project.

*Harder*
- Three hypotheses to gate before placement 3 is even a candidate, on top
  of the C-gate.
- Shared guest memory becomes unavoidable on any vhost-user path: a
  second process maps the guest RAM and must then be confined at least as
  well as the VMM — the C-gate again, applied to a second binary.

*To revisit*
- If `vhost_vsock` accumulates a defect of the class recorded in
  `docs/OBSERVATIONS.md` §1, the cost/benefit of placement 3 shifts
  sharply. Re-open then, with H1–H3 already gated.

## ADR-029 — The launch daemon orders units; systemd owns the VMM process

**Status:** Accepted (2026-08-02). Gate criteria G0/G1/G3 passed live on MINIS
the same day; G2 was answered by measurement in a form that dissolved the
question it was written to settle.
**Depends on:** [ADR-027](DECISIONS.md#adr-027) (C-gate),
[ADR-028](DECISIONS.md#adr-028) (netns scoping)
**Refines:** [ADR-028](DECISIONS.md#adr-028), netns-scoping section — see below
**Inherits:** graph ownership [ADR-022](DECISIONS.md#adr-022); CID allocation
[ADR-017](DECISIONS.md#adr-017); NETCFG ordering
[ADR-025](DECISIONS.md#adr-025); indicator identity
[ADR-026](DECISIONS.md#adr-026)

**Context:**

Five ADRs anticipate a launch daemon and assign it work: it owns the topology
graph and refuses to tear down a `provides_network` VM with live dependents
([ADR-022](DECISIONS.md#adr-022)); it allocates CIDs and reconciles the pool
([ADR-017](DECISIONS.md#adr-017)); it orders `device_add` before NETCFG and
re-issues every link after a netVM restart ([ADR-025](DECISIONS.md#adr-025));
it maps a window's identity to a VM name ([ADR-026](DECISIONS.md#adr-026)); and
it carries the privilege split that C1–C3 of the C-gate describe
([ADR-027](DECISIONS.md#adr-027)).

None of that was in dispute. Exactly one question was open, and it is prior to
every other design question about the daemon: **is the daemon the direct parent
of the QEMU process** — `fork`/`exec`, inheriting file descriptors, reaping via
`waitpid` — **or does it order systemd units and hold no process relationship
to the VMM at all?**

The question was reached by counting. Four constraints appeared to require
daemon-as-parent: TAP handover as `fd=` (C2), the write-once
`child_ns_mode` at namespace creation (C6), the pid↔CID map for the domain
indicator ([ADR-026](DECISIONS.md#adr-026)), and `_is_alive` in the CID
allocator ([ADR-017](DECISIONS.md#adr-017)). One constraint favoured unit
ownership: `LimitMEMLOCK` (C3), which
[ADR-027](DECISIONS.md#adr-027) itself classifies as configuration rather than
architecture. Four against one.

**The count was not a weighing.** Three of the four have kernel-authoritative,
pid-free resolutions already written into the very ADRs they were drawn from;
the fourth turned out to be a question about a device that does not yet exist.
And the argument that decided the matter appeared on neither list.

### The deciding argument: a name that outlives the naming process

Daemon-as-parent makes the identity of a running VM a *process relationship*.
When the daemon dies or is updated:

- the QEMU processes survive, reparented to PID 1. That is not the problem;
- the new daemon **is not their parent**. `waitpid` is gone. Reconstruction runs
  through a persisted pid and `pidfd_open`, which reintroduces **pid reuse** —
  precisely the race that [ADR-017](DECISIONS.md#adr-017)'s monotonic counter
  and full-cycle `flock` exist to eliminate. A stale pid resolves to an
  unrelated process, and under [ADR-026](DECISIONS.md#adr-026) that is a
  misattributed domain indicator: a security consequence, not an operational
  one;
- under C6 it is worse. [ADR-028](DECISIONS.md#adr-028) establishes that with
  CID reuse across namespaces the identity is the pair **(netns, CID)**. An
  anonymous namespace held only as a descriptor from `/proc/<child>/ns/net`
  dies with the daemon. Half the identity pair is lost, and it is the half that
  cannot be recovered from the kernel by name;
- this is a security-focused OS. The launch daemon will receive security
  updates. A model in which `systemctl restart katmated` requires stopping
  every running VM is a defect in the design, not an inconvenience in
  operations.

systemd is PID 1. It does not restart. A unit name and its cgroup are durable
names for a running VM, independent of any daemon's lifetime.

### Re-examination of the four

| Constraint | Outcome |
|---|---|
| pid↔CID map ([ADR-026](DECISIONS.md#adr-026)) | **Dissolves.** The recorded chain is: compositor gives a window pid → that pid's `AF_VSOCK` connection gives the peer CID (`vsock_diag`). The kernel resolves pid→CID; the daemon is not in that step. Its remaining job is CID→name, a lookup in persisted state, not a child table. |
| `_is_alive` ([ADR-017](DECISIONS.md#adr-017)) | **Dissolves.** ADR-017 already offers the pid-free option — reconcile against *active vsock endpoints for those CIDs*. A live control endpoint **is** this system's definition of a live VM. Strictly better than `waitpid`, because it survives the daemon. |
| `child_ns_mode` write-once (C6) | **Measured; leaves the column.** The write happens in a *parent* namespace and children inherit it at creation (G1). It is a one-time preparation, not a per-`fork` operation, and it produces a **named** namespace rather than a descriptor. It was an argument about ordering, never about parenthood. |
| TAP as `fd=` (C2) | **Dissolved by inspection.** See below. |

**Decision:**

1. **systemd owns the QEMU process.** The launch daemon never `fork`s or `exec`s
   a VMM. Each VM is a systemd unit; PID 1 is the parent, the unit name and its
   cgroup are the durable identity, and the daemon holds no process relationship
   to any VMM.

2. **The launch daemon orders; it does not parent.** It retains everything the
   five ADRs assign it — graph ownership, CID allocation, NETCFG ordering and
   re-issue, the CID→name table, the dependent-VM interlock. The distinction the
   `fork`/`exec` model conflates and this one keeps apart: *who commands* is the
   daemon; *who holds the child* is systemd. The daemon may therefore die at any
   moment without any running VM noticing.

3. **The C-gate privilege split becomes unit directives, not daemon code.**
   C1 is `User=` (per-VM uid); C3 is `LimitMEMLOCK=infinity`, which closes on
   configuration exactly as [ADR-027](DECISIONS.md#adr-027) said it would;
   C5a is a `setpriv`-style Landlock wrapper in `ExecStart=` (rulesets are
   inherited across `execve`); privileged preparation is `ExecStartPre=+`.

4. **Cleanup is `ExecStopPost=+`, not `SIGCHLD`.** Releasing the CID, tearing
   down the link, removing the namespace and deactivating the LV run from the
   unit, as root, on every stop including a crash — and therefore *also when the
   daemon is dead*. `SIGCHLD` requires a living listener; this does not. Measured
   (G3).

5. **The network namespace is prepared, named, and handed over.** The daemon
   creates it — `setns` into a dedicated `katmate-root` namespace carrying
   `child_ns_mode=local`, then `unshare(CLONE_NEWNET)`, then
   `mount --bind /proc/self/ns/net` onto `/run/netns/katmate-<vm>` — and then
   lets go. The unit takes it with `NetworkNamespacePath=`. The namespace has a
   filesystem name, reachable by any privileged process at any time, and does
   not depend on the daemon continuing to exist.

6. **`init_netns` is never written.** `child_ns_mode` is set once, on
   `katmate-root`. Foreign namespaces on the host are unaffected; the write-once
   budget on `init_netns` stays unspent.

7. **No pid is a system identity.** `_is_alive` resolves from a live vsock
   endpoint or unit state; pid→CID stays with `vsock_diag` per
   [ADR-026](DECISIONS.md#adr-026). Any future mechanism that would make a pid
   load-bearing across daemon restart is out of bounds under this ADR.

### Gate results — live, MINIS, 2026-08-02

Empirics before commitment, the [ADR-024](DECISIONS.md#adr-024) method. Each
criterion is an observable, not a claim.

| # | Criterion | Observation | Result |
|---|---|---|---|
| **G0** | `child_ns_mode` exists and is writable | `/proc/sys/net/vsock/child_ns_mode` `rw`; `ns_mode` `r--r--r--`; both `global` at boot | **PASSED** |
| **G1a** | write-once is real, not documented | first write `rc=0`; second, differing write → `EBUSY`, `rc=1`; readback `local` | **PASSED** |
| **G1b** | parent→child inheritance | child of `g1-parent` (`local`) reads `ns_mode=local`; **control:** child of `init_netns` reads `global` | **PASSED** |
| **G1c** | the daemon's actual sequence | `nsenter --net=/run/netns/katmate-root` + `unshare --net` → child reads `local` | **PASSED** |
| **G3** | `ExecStopPost=+` survives violent death | `SIGKILL` to `MainPID` under `User=nobody` → `STOPPOST result=signal status=KILL code=killed uid=0`; unit `Result=signal`, `ExecMainStatus=9` | **PASSED** |
| **G2** | tap reachable by name across netns | `Device "tap-g2" does not exist` in a fresh namespace (control: only `lo` present). Tap is netns-scoped | **PASSED** (isolation confirmed) |
| **G2b** | tap migration as an alternative to fd handover | `ip link set tap-g2 netns g2-test` succeeds; device appears in target | **PASSED** |

### What was measured that no ADR predicted

Four findings, recorded because each is a mechanism that would otherwise be
assumed:

- **`ns_mode` is `r--r--r--`.** After a namespace exists there is no lever.
  Whoever creates a namespace has determined its mode permanently.
- **`ip netns add` is not nestable.** Run under `ip netns exec`, it creates its
  bind mount in the mount namespace of a child process that immediately exits.
  What remains in `/run/netns/` is a `----------` placeholder, not a namespace;
  `setns` on it returns `EINVAL`, and `ip netns list` still lists it. The
  permission bits distinguish the two cases: a live namespace shows `-r--r--r--`
  (the nsfs inode under the bind mount), a placeholder shows `----------`.
  Consequence: the daemon must create namespaces itself, in one process, and
  survive until the bind mount is placed.
- **`/proc` must be remounted to read per-netns sysctls.** After
  `unshare --net`, `/proc/sys/net` continues to show the *old* namespace until
  `/proc` is remounted (`--mount --propagation private` plus
  `mount -t proc proc /proc`). Without it the reading is a **false negative** —
  a plausible, wrong value silently returned. This is the failure class that
  killed [ADR-021](DECISIONS.md#adr-021)'s shutdown model: a mechanism quietly
  consulting the wrong object. It applies to the daemon, not only to tests.
- **Tap migration resets link state, preserves MAC.** `UP` is cleared by
  `ip link set … netns`; the MAC survives. `ip link set … up` must run *after*
  migration, inside the target namespace. The surviving MAC matters to
  [ADR-025](DECISIONS.md#adr-025)'s locally-administered-address check.

### Refinement to ADR-028

[ADR-028](DECISIONS.md#adr-028) records `child_ns_mode` as "an architectural
decision taken once at **daemon start**, not a runtime toggle." G1 refines this:
the write occurs in a *parent* namespace and children inherit at creation. It is
therefore not a daemon-start decision at all, but a one-time preparation on a
dedicated `katmate-root` namespace from which every VM namespace is derived.
The practical difference is scope: `init_netns` is never written, so foreign
namespaces on the host keep `global` and the host-wide write-once budget is
never spent. ADR-028's substance — write-once, `-EBUSY`, `ns_mode` immutable,
and the **(netns, CID)** coupling to ADR-026 — stands unchanged and is now
measured rather than cited.

### C2 was not refuted; it was a question about an absent device

C2 was carried through three rounds of this session as "TAP handover requires
`fd=` inheritance, which requires a parent." Inspection of `app_web.con` ends it
differently: **the AppVM launcher carries no network device at all.** There is
no `-netdev`, no `virtio-net-device`, no tap — on the host or anywhere. An
AppVM today has `vhost-vsock-device` and two block devices, and nothing else.
This is consistent with the rest of the record: NETCFG was live-gated against
netVM itself ([ADR-025](DECISIONS.md#adr-025)), never through a live AppVM,
and `state.md` lists the AppVM route as future work.

So the measurement that "a tap can be migrated into a namespace rather than
inherited as a descriptor" is true and useful, but it answers a question about
a topology that has not been chosen. Per
[ADR-022](DECISIONS.md#adr-022) an AppVM routes through netVM and has no
neighbour on the host, so netVM's end of an AppVM link belongs in the **netVM**
namespace, not `init_netns` — unlike `net-sys.con`'s `tap-int0`, which sits on
the host only because until now there was no other namespace to put it in.

C2 is therefore **neither passed nor failed**: it was not a constraint on
parenthood. When the AppVM acquires a network endpoint it returns as a question
about link topology, and it is to be settled by measurement then — not by
citing this session.

### Alternatives considered

- **Daemon as direct parent (`fork`/`exec`, holds fds).** Rejected. Its four
  supporting constraints reduce to zero under examination, and it purchases, at
  full price, a model in which the identity of every running VM is destroyed by
  a daemon restart and can only be rebuilt through a pid-reuse race. The
  strongest version of this option — a keeper process holding pidfds across
  daemon restarts — is a second always-on component in the TCB whose sole
  function is to compensate for a naming scheme systemd already provides.
- **Hybrid: daemon `fork`s a per-VM supervisor which then orders a unit.**
  Rejected without measurement. It carries the daemon-as-parent lifetime
  problem *and* the unit indirection, and adds a process class with no owner.
- **Objection from precedent — this project removes systemd
  ([ADR-018](DECISIONS.md#adr-018)) and its recent history
  ([ADR-021](DECISIONS.md#adr-021), [ADR-024](DECISIONS.md#adr-024),
  [ADR-025](DECISIONS.md#adr-025)) is a chronicle of systemd mechanisms failing
  their preconditions.** Considered and rejected as inapplicable. Every one of
  those failures is **in the guest**, where the manifest deliberately omits
  `dbus` and bus-dependent components are inert. On the host, systemd is PID 1,
  complete, and already named in the TCB in `SECURITY-MODEL.md`. This decision
  adds no new trust dependency. What the guest history does impose is method,
  not conclusion: gate the mechanism before relying on it — which is what
  G0/G1/G3 are.

### Open items — not measured, not assumed

- **OOM-kill.** G3 used `SIGKILL`. systemd distinguishes `result=oom-kill`
  separately. That `ExecStopPost=+` behaves identically there is **likely and
  unverified**. Gate before relying on cleanup under memory pressure.
- **Tap ownership across migration.** Whether `ip tuntap add … user <uid>`
  ownership survives `ip link set … netns`, and therefore whether a non-root
  VMM in the target namespace may open it. Unmeasured; blocks nothing until an
  AppVM has a network endpoint.
- **AppVM link topology.** Where each end of an AppVM↔netVM link lives. Opened,
  not settled, by the C2 finding above.
- **Unit shape:** `StartTransientUnit` over the system bus versus a
  `katmate-vm@.service` template with a per-instance `EnvironmentFile`.
  Deliberately deferred — this is implementation, and neither choice affects any
  decision in this ADR. The template form is the better default for auditability
  (each unit is a reviewable artifact, matching the "every command on screen"
  posture of [ADR-011](DECISIONS.md#adr-011) and
  [ADR-018](DECISIONS.md#adr-018)); decide when the daemon is written.
- **How the daemon reaches every VM's namespace.**
  [ADR-028](DECISIONS.md#adr-028) notes it must enter each namespace or hold
  per-namespace sockets. With named namespaces under `/run/netns/` this is
  `setns` on demand, but the socket lifetime question is open.

**Consequences:**

*Easier*
- C1, C3, C5a stop being daemon code and become unit directives. C3 closes on
  configuration, as ADR-027 predicted.
- Cleanup correctness no longer depends on the daemon being alive.
- The daemon becomes restartable, and therefore updatable, without touching
  running VMs — a property this project needs specifically because it ships
  security updates.
- `_is_alive` and reconcile ([ADR-017](DECISIONS.md#adr-017)) lose their pid
  dependency and become kernel-authoritative.

*Harder*
- Namespace creation is daemon code (`setns` → `unshare` → bind mount), not a
  shell line, because `ip netns add` is not nestable. Small, but C, not
  configuration.
- Every VM start crosses a process boundary to PID 1. Ordering guarantees that
  were implicit in `fork`/`exec` must now be explicit in the daemon.
- The daemon must treat unit state as the source of truth about liveness and
  resist caching it into anything pid-shaped.

*To revisit*
- If the AppVM link topology turns out to require a descriptor that cannot be
  produced by `ExecStartPre=+` and cannot be migrated, C2 returns as a genuine
  constraint. It would not overturn this decision — `SCM_RIGHTS` to a small
  `exec`-ing shim named in `ExecStart=` keeps systemd as parent — but it would
  add a binary to the TCB and should be recorded as such.

**Cross-reference:** closes the supervision question left open by
[ADR-022](DECISIONS.md#adr-022) and [ADR-027](DECISIONS.md#adr-027); refines
the netns-scoping section of [ADR-028](DECISIONS.md#adr-028); removes the pid
dependency from [ADR-017](DECISIONS.md#adr-017)'s reconcile and from
[ADR-026](DECISIONS.md#adr-026)'s identity chain; adopts the
empirics-before-commitment method of [ADR-024](DECISIONS.md#adr-024); the
C-gate criteria C1, C3 and C5a are hereby assigned to unit configuration rather
than to daemon implementation ([ADR-027](DECISIONS.md#adr-027)).

---

## ADR-030 — What the launch daemon reads: four artefacts, authorship as the tier boundary

**Status:** Accepted (2026-08-06). Gate **E1 passed live on MINIS** the same
day, selecting candidate A; G1–G6 belong to build-order step 3a and are open.
**Depends on:** [ADR-029](DECISIONS.md#adr-029) (systemd owns the VMM process),
[ADR-022](DECISIONS.md#adr-022) (object model), [ADR-027](DECISIONS.md#adr-027)
(C-gate), [ADR-017](DECISIONS.md#adr-017) (CID allocation)
**Partially supersedes:** [ADR-015](DECISIONS.md#adr-015) — the `network` enum
is removed as wrong in *type*, and the AppVM-only restriction is lifted. Every
other ADR-015 decision (TOML, per-instance file, validator, semantic
invariants) remains in force.

**Context:**

[ADR-029](DECISIONS.md#adr-029) settled who parents the VMM process. It did not
settle what the daemon reads, and no document does. Three gaps were named:

1. No `properties.toml` → QEMU argv mapping exists. ADR-015 cites the absence
   of one as its own justification and then does not specify it. The `.con`
   scripts are the de facto specification — hand-written, one per VM.
2. The ADR-015 schema lacks fields for most of what a launcher needs.
3. sysVMs have no machine-readable description at all, and the daemon must
   launch them. ADR-015 defers this by name to "the launch daemon's business".

Two further facts, established by reading the two live launchers against
ADR-022 before any schema work:

- **ADR-030 does not invent an object.** [ADR-022](DECISIONS.md#adr-022)
  already defines `Vm` (name, class, CID, image ref, resources,
  `netvm: Option<VmRef>`, `provides_network: bool`), `Image`, `Nic`, `Link` and
  `Policy`. The subject of this ADR is the **on-disk serialisation** of those
  objects, such that an ADR-029 unit can be produced from it. ADR-015's
  `properties.toml` is a partial, AppVM-only serialisation of `Vm` that
  predates the model.
- **ADR-015's `network` field is wrong in type.** The enum
  `none | via-netvm` cannot name *which* netVM. ADR-022 requires exactly that —
  "policy is a netVM, not a rule"; differentiating an AppVM's access **is**
  choosing its netVM. `provides_network` is absent from ADR-015 entirely. This
  is a replacement, not an extension, and it was never recorded when ADR-022
  silently displaced it.

### Placement in the build order

`ROADMAP.md`'s build order lists artefacts to *build*. Launching already exists
in a degenerate form — two hand-written `.con` scripts — so it never appeared
as a step, and for the same reason the schema was never written: **the `.con`
scripts are the schema, expressed as code.** The missing step is therefore not
"write a launcher" but **the removal of the scripts**.

Checked against the existing steps: step 1's gate ("run an instance overlay off
each") is satisfiable by a `.con`; step 2 is weakly affected; step 3 ("netVM
*lifecycle* automated") and step 4 ("instantiate the domains from … properties")
are both blocked outright. The daemon belongs between 2 and 3, and splits:

- **3a — VM description as data, plus unit templates.** netVM and app_web start
  via `systemctl`. No daemon yet.
- **3b — the launch daemon.** Graph, CID allocation, NETCFG ordering,
  dependent-VM interlock.

3a is simultaneously the empirical gate on *this* ADR: if the unit template can
be filled from data alone, the schema is sufficient; if a `.con` line has
nowhere to go, it is not. This is the [ADR-024](DECISIONS.md#adr-024) method
applied to a schema — a demonstration instead of a review.

Neither horn of the dilemma `state.md` posed is correct: ADR-029 did not run
ahead of its turn, and the build order is not silently wrong. The step was
invisible because the thing it replaces already works.

**Decision:**

### 1. The tier boundary is authorship, not content

The question is not *which fields the schema needs* but **which fields may be
data at all**. `app_web.con` mixes four classes of content, and one of them is
containment configuration: if
`-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny`
becomes an editable field, a file edit disarms C4 — a criterion this project
spent a live gate proving ([ADR-027](DECISIONS.md#adr-027), 2026-07-28).
ADR-015 states that validation is not a trust boundary *against the host*; that
is a different question. `properties.toml` is host-side, user-authored data
consumed by a TCB component. Naively promoting every `.con` line to a schema
field would duplicate ~20 identical lines into every instance **and** create an
attack surface.

Tiers are therefore defined by **who writes the artefact**, and the writer
determines the file:

| Tier | Author | Location | Form |
|---|---|---|---|
| **T1** instance properties | the user | config tree | `properties.toml`, one per VM |
| **T2** image metadata | the build pipeline | `/var/lib/katmate/` | `<image>.meta`, the `foundation.meta` pattern |
| **T3+T4** class profile and TCB constants | the release (signed ISO) | `/usr/lib/systemd/system/` | **the unit template** |
| — | derived at start | `/run/katmate/vm/<instance>.env` | a projection, not a source |

`foundation.meta` already carries `WAYPIPE_TAG` and is the only T2 content that
exists as data today. It is the precedent for the whole tier; no second format
is introduced.

### 2. The unit template *is* the serialisation of T3 and T4

There is no separate profile file. A unit template already contains the machine
type, the device set and the `-sandbox` line; a profile format alongside it
would be a second record of the same fact. The template is world-readable, part
of the signed ISO ([ADR-020](DECISIONS.md#adr-020)), and already read by PID 1.

**The profile is carried in the unit name, not in a field:**

```
katmate-app-routed@personal.service
katmate-app-offline@vault.service
katmate-sys-driver@netvm.service
```

[ADR-029](DECISIONS.md#adr-029) makes the unit name the durable identity of a
running VM. The identity therefore carries its own containment profile;
`systemctl status` displays it without a query to anything.

**The profile is not a field but a function** of `(class, netvm, nic)`:

| `class` | `netvm` | `nic` | profile |
|---|---|---|---|
| `app` | `Some` | — | `app-routed` |
| `app` | `None` | — | `app-offline` |
| `sys` | — | `Some` | `sys-driver` (q35 + vfio) |
| `sys` | — | `None` | `sys-proxy` (microVM) — **named, not shipped** |

The user declares topology and the profile follows. A user therefore **cannot
select weaker containment**, which is the only reason T3 may be derived from T1
without T1 becoming an attack surface.

Device *presence* is a profile choice, not an argument: `netvm: None` yields an
**absent** device, not a disabled one — air-gap is the absence of an object
([ADR-021](DECISIONS.md#adr-021), [ADR-022](DECISIONS.md#adr-022)).

`sys-proxy` is anticipated by ADR-022 (a netVM holding no NIC is a microVM) and
has never been built. The function names it and returns an **explicit error**,
never a default. Shipping an untested unit template for a VM class that does
not exist would invert this project's method.

### 3. What crosses the boundary: named objects, two typed scalars, no free argv

The daemon does not supply arguments. It supplies **named kernel objects**,
which the template references statically. This is the deciding argument of
ADR-029 applied one layer down: *names that outlive whoever created them.*

- **netns** → `NetworkNamespacePath=/run/netns/katmate-%i`
  ([ADR-029](DECISIONS.md#adr-029) §5).
- **tap** → created inside that namespace, name derived from `%i`, **owned by
  the per-VM uid** (`ip tuntap add … user <uid>`) so QEMU opens it by name
  without `CAP_NET_ADMIN`.
- **MAC** → derived, never authored, and **never byte-encoding an address**:
  the retired pet launcher preserved a wrong-subnet bug in its MAC bytes
  (forensic note, [ADR-025](DECISIONS.md#adr-025)).

Network argv is thereby static in the template. Exactly two values still cross,
and both are scalars with a hard type:

1. **`KM_CID`** — authored for static domains, **allocated at start** for
   disposables ([ADR-017](DECISIONS.md#adr-017)); not derivable from `%i`.
2. **`KM_VFIO_BDF`** — host inventory, not derivable (see §5).

They are delivered by `EnvironmentFile=` with a **fixed, validated key set**,
each interpolated at a **fixed position** in `ExecStart=` — `guest-cid=${KM_CID}`,
`host=${KM_VFIO_BDF}`. The braced form is deliberate: `${}` does not word-split,
so a value cannot become additional arguments. A space in a value is a parse
error, not a new argument.

*Rejected — an argv blob.* `EnvironmentFile` plus `ExecStart=… $KATMATE_ARGS`
works (single `$` word-splits), and whoever writes that file injects arbitrary
QEMU arguments: a second `-drive` onto a foreign LV, or a later `-sandbox`
overriding T4. It would make the entire content of T4 optional.

*Rejected — per-instance drop-in plus `daemon-reload`.* Argv in systemd's
configuration space, a race between write and `StartUnit`, and the daemon
becomes load-bearing for identity again — the inverse of ADR-029.

### 4. T1 — `properties.toml`, superseding ADR-015's schema

| Key | Change |
|---|---|
| `network` | **removed** — wrong type against ADR-022 |
| `netvm` | new — `VmRef`, or absent (`Vm.netvm: Option<VmRef>`) |
| `provides_network` | new — bool, default `false` |
| `class` | new — `app` \| `sys`. ADR-015's own deferral, via `Vm.class` |
| `nic` | new — a **label**, not a BDF (§5). Optional |
| `mem`, `vcpus` | new — `Vm.resources` |
| `cid` | band becomes a function of `class`: 3–19 is **required** for `class = sys`, and remains an error for `class = app` |
| `manifest`, `persistence`, `identity`, `disposable`, `reset_on_shutdown` | unchanged |

`properties.toml` now describes sysVMs as well, which ADR-015 explicitly
excludes. Recorded here as a supersession rather than left to inference — the
same treatment the CID renumbering received.

New validator rules (`tools/validate-properties.fish`), both **errors**:

- the same `nic` label on two VMs — the on-disk expression of ADR-022's
  `Nic.assigned_to`, "assignable to at most one VM";
- a `(class, netvm, nic)` tuple that resolves to `sys-proxy`, until that
  profile exists.

### 5. `Nic` is not serialised inventory; the `Vm` carries a label

**A BDF is not an identity.** `0000:01:00.0` is assigned by firmware
enumeration, not by us. It moves if the card is reseated, if an NVMe device
renumbers the bus, or if a firmware setting changes. This is the opposite of a
CID (which we allocate, ADR-017) and of a unit name (which we choose, ADR-029).

The consequence of a stale BDF is not a VM that fails to start. `vfio-pci`
binds to an **address**, not to a device. A stale record means some *other*
device is detached from its host driver and handed to the most exposed VM in
the system — silently, with a plausible result. That is this system's
characteristic failure: a mechanism that quietly consults the wrong object and
returns a believable answer. The same shape as `/proc` read in the wrong netns
(ADR-029), as `Online state: offline` beside `routable`, and as the assumed
precondition that killed [ADR-021](DECISIONS.md#adr-021)'s shutdown model.

Therefore:

- **`Vm` carries a label**, not an address: `nic = "uplink0"`. Absent on every
  AppVM and on proxy netVMs.
- **Resolution is kernel-authoritative and boot-scoped.** The binding step
  (root, at host start) writes `/run/katmate/nics/uplink0` → the current BDF.
  The daemon reads it there, never from git. `/run` for the same reason NETCFG
  records live there ([ADR-025](DECISIONS.md#adr-025)): it is a fact *of this
  boot*.
- **Check at VM start.** `vendor`/`device` at the resolved BDF must match what
  the label was created for — two reads under `/sys`. Not a trust boundary;
  blast-radius limiting against exactly the silent case above, on the same
  reasoning ADR-025 gives for its validation.

What the kernel already knows is not copied into a file:
`/sys/bus/pci/drivers/vfio-pci/` *is* this boot's list of bound devices.

### 6. No QEMU monitor

`-nographic` by itself multiplexes the serial console **and the monitor** onto
one stream, and `-serial mon:stdio` does so explicitly. Under a unit there is no
stdio terminal, and `StandardInput=` would hand the monitor to whoever can write
to it. QMP was already declined for shutdown in favour of an agent opcode
([ADR-021](DECISIONS.md#adr-021), [ADR-024](DECISIONS.md#adr-024)), so no
control socket exists today and none is introduced. T4 becomes:

```
-display none -monitor none -serial <chardev>
```

with `-nographic` removed from both launchers.

**A development monitor is a drop-in, never a field.** A field could be set in
a release. Following the precedent recorded at Gap #10 in `net-sys.con` ("it
must be a separate dev launcher"), a monitor lives in
`/etc/systemd/system/katmate-*@.service.d/90-dev-monitor.conf`: additive, not
unlocking, per-machine and out of git (the anti-drift pattern), and **on the
list of dev scaffolding to be removed before release** alongside SECURITY-MODEL
#3, #4 and #12.

**Coupling that must not be discovered late:** with the serial console in the
journal, the path becomes one-way, and interactive console login — today the
only in-guest observation path for netVM, and the reason open problem #12
exists — disappears. That is the correct end state: #12 becomes *unreachable*
rather than merely resolved. During 3a bring-up a pty or a separate dev
launcher is required; it must not be the same unit.

### 7. `/home` is per instance

`app_web.con` names the persistent home LV after the **app layer**
(`vm_app_web_home`) while the root delta is per instance. Two instances of
`app_web` would mount the same ext4 read-write and corrupt it. It has not
happened only because exactly one instance exists. ROADMAP step 4 already
requires "per-instance home on raw thin LV".

**This ADR decides the tier only:** `/home` is a per-instance object and its
name is derived from the instance, not from the layer. The **storage
mechanism** — a writable thin snapshot of a frozen `vm_home_skel` versus a
qcow2 branch — belongs to [ADR-010](DECISIONS.md#adr-010)/[ADR-011](DECISIONS.md#adr-011)
and is deliberately not settled here. One ADR, one concern.

Recorded because it will be needed there: a qcow2 branch would place a **second
COW layer** on the most write-heavy device in the system, grow monotonically
where `discard` must traverse two layers to return space to the thin pool, and
introduce a backing chain whose semantics are the *opposite* of the app-layer
chain `katmate-update` rebases ([ADR-019](DECISIONS.md#adr-019)) — two similar
mechanisms with contrary meanings in one system. A thin snapshot is one COW
layer, a raw block device, and makes `persistence` a lifecycle property of one
object rather than two storage plans: persistent snapshots are created at
deploy and kept; ephemeral and disposable ones are created at start and
`lvremove`d at teardown. `discard=unmap` through virtio-blk to the thin pool is
a gate, not an assumption.

### 8. The runtime projection

`/run/katmate/vm/<instance>.env` is the merge of T2, T1 and the start-time
scalars, with the same fixed typed key set as §3. It is a **projection, never a
source**: regenerated at every start, in `/run`, so nothing stale survives a
reboot. In 3a it is produced by a script; that script is precisely the piece
that later moves into the daemon, which is why the 3a gate remains meaningful.

**Mechanism — E1, measured 2026-08-06 on MINIS.** Whether `EnvironmentFile=` is
read late enough to see a file created by `ExecStartPre=` *in the same unit*
was open, and this ADR's own prediction was that it probably is not — the shape
of the assumed precondition that killed [ADR-021](DECISIONS.md#adr-021)'s
shutdown model and Path A of [ADR-025](DECISIONS.md#adr-025). The prediction
was wrong, and it was cheaper to be wrong here than in a unit template.

| # | Criterion | Observation | Result |
|---|---|---|---|
| **E1a** | `ExecStartPre=` writes `/run/…env`; `ExecStart=/bin/echo [${KM_CID}]` in the same unit | `A_RESULT=[42]` | **PASSED** |
| **E1b** | control: a separate generator unit, `Requires=` + `After=` | `B_RESULT=[42]` | **PASSED** |

**Decision: candidate A.** The generator runs as `ExecStartPre=+` in the VM
unit. One unit per VM; no second unit class, no ordering edge to maintain, and
the projection is produced and consumed inside one unit's lifetime — so a
half-started VM cannot leave a live env file behind for the next start to
inherit.

**B was not eliminated; it was measured as also working.** Recorded
deliberately: if A later fails on a constraint this probe did not carry, B is
available without a second measurement.

**What the probe did not cover** — stated so that neither result is over-read:

- `Type=oneshot`, where the VM units will be `simple` or `notify`.
  `ExecStartPre=` completes before `ExecStart=` in all three, so the ordering
  is the same, but only `oneshot` was observed.
- `ExecStartPre=` without the `+` prefix. The real generator is privileged;
  `+` changes the credential, not the ordering.
- One `EnvironmentFile=` key. The fixed key set of §3 is two.

None of these is a reason to defer 3a. All are reasons not to cite E1 for
anything beyond what it observed.

**A defect in the probe, recorded because it is the same class the gate
exists to catch.** Its first version installed `trap cleanup EXIT` *above* the
root check, so a non-root run fired `systemctl stop` on units that had never
been created — four polkit prompts, nothing measured, and an exit that looked
like a run. A gate that fails open is worse than no gate. Fixed before the
real run.

**Consequences:**

*Immediately*
- Both `.con` scripts are deleted at the end of 3a. Their content is not
  archived in the repository; the unit templates supersede them.
- ADR-015 needs a revision note; `tools/validate-properties.fish` needs the two
  new error rules and the `class`-dependent CID band.
- The build order gains a step and is renumbered.

*Structurally*
- Containment is no longer expressible as data. That is the point, and it means
  a per-VM containment exception is not a configuration change but a new
  profile in the signed ISO.
- The daemon's input surface is two typed scalars and a set of named kernel
  objects. It has no argv construction path at all, so no bug in it can produce
  an unexpected QEMU argument.

*To revisit*
- `sys-proxy` when the first proxy netVM is built (ADR-022's chained topology).
- The `nic` label's durable descriptor, once measured (see below).
- `Vm.resources` beyond `mem`/`vcpus` if pinning or NUMA ever matters.

### Findings surfaced by the inventory and routed elsewhere

Recorded so they are not lost, and explicitly **not decided here**:

- **Memory backing is divided the wrong way round.** `app_web` (no vfio) uses
  `memory-backend-file` on `/dev/hugepages`; `net-sys` (with vfio) uses
  `memory-backend-memfd`. The vfio VM is the one that benefits from hugepages —
  fewer pages to pin, smaller IOMMU tables. Three axes, none of them
  performance: DAC on `/dev/hugepages` under `User=` (C1) versus memfd needing
  no filesystem permission at all; whether `share=on` has any consumer given
  that vhost-vsock is in-kernel and no vhost-user process exists; and whether
  an undersized pool fails loudly or falls back silently.
  `HOST-CONFIG.md` §6 already marks the reservation `[?]`, so by this project's
  own standard it is not yet a requirement. → deferred, own session.
- **netVM has neither `-nodefaults` nor `-no-user-config`.** Less containment
  in the most exposed VM than in an AppVM. `-vga none` covers graphics only;
  the default configuration file is still read. Closed by construction when the
  T4 template lands in 3a; a q35 machine with `-nodefaults` builds *nothing*
  implicitly, so every device must be listed. → C-gate, gate it in 3a.
- **`-overcommit mem-lock=off` on netVM is probably inert and misleading.**
  vfio pins the entire guest memory for DMA regardless. Under `User=` (C1),
  `LimitMEMLOCK=infinity` stops being an optimisation and becomes a start
  condition. → folds into the memory session and into C3.
- **The same problem exists twice: durable identity against volatile
  enumeration.** Once at the vfio BDF (§5), once at the host USB-NIC, where a
  "persistent MAC-matched profile" is already an open item
  (`HOST-CONFIG.md` §2). One class, two sites, treated separately until now.

**Gate criteria:**

| # | Criterion | Where |
|---|---|---|
| **E1** | `EnvironmentFile=` sees a file created by `ExecStartPre=` in the same unit | **PASSED** 2026-08-06, MINIS — candidate A selected; B also passing, kept as a recorded fallback |
| **G1** | `netvm` starts from `katmate-sys-driver@netvm.service` with no `.con` script present, uplink up | 3a |
| **G2** | `app_web` starts from `katmate-app-routed@…` likewise | 3a |
| **G3** | **both `.con` files deleted from the repository and nothing was lost** — the schema gate | 3a |
| **G4** | netVM starts under `-nodefaults -no-user-config -monitor none` | 3a |
| **G5** | a `properties.toml` with the same `nic` label on two VMs is rejected by the validator | 3a |
| **G6** | a stale `/run/katmate/nics/<label>` whose vendor/device no longer matches refuses the start | 3a |

**Alternatives considered:**

- **Extend the ADR-015 table with the `.con` fields.** Rejected. It duplicates
  identical lines into every instance file and makes containment editable.
- **A separate profile format alongside the unit template.** Rejected: two
  records of one fact, and the second is not read by PID 1.
- **A `profile` field authored by the user.** Rejected. It would let a
  declaration of topology and a declaration of containment disagree, and it is
  the disagreement that is dangerous, not either value.
- **Serialise `Nic` as host inventory.** Rejected — it writes down a value the
  firmware owns and the kernel already publishes, and the failure mode is
  silent misassignment rather than a refused start.

**Cross-reference:** specifies the input of the daemon decided by
[ADR-029](DECISIONS.md#adr-029) and serialises the `Vm` / `Image` / `Nic`
objects of [ADR-022](DECISIONS.md#adr-022); partially supersedes
[ADR-015](DECISIONS.md#adr-015) (the `network` enum, the AppVM-only
restriction); keeps containment out of user data per
[ADR-027](DECISIONS.md#adr-027) C4 and inside the signed artefact of
[ADR-020](DECISIONS.md#adr-020); preserves the absent-not-disabled principle of
[ADR-021](DECISIONS.md#adr-021)/[ADR-022](DECISIONS.md#adr-022) by making
device presence a profile rather than an argument; takes the CID input/output
distinction from [ADR-017](DECISIONS.md#adr-017); adopts the
empirics-before-commitment method of [ADR-024](DECISIONS.md#adr-024) for E1 and
declines the QMP surface [ADR-021](DECISIONS.md#adr-021) already declined; the
`/home` storage mechanism is left to
[ADR-010](DECISIONS.md#adr-010)/[ADR-011](DECISIONS.md#adr-011).

**Revision note (2026-08-09, [ADR-032](DECISIONS.md#adr-032)):** step 3a began
as this ADR's empirical gate — place every line of both `.con` launchers, on
the principle that a line with nowhere to go is a hole in the schema. It
returned five, before any file was modified. Four were holes in this ADR and
are answered by [ADR-032](DECISIONS.md#adr-032); the fifth was a location this
ADR never supplied. Nothing below is withdrawn.

1. **§2 was too narrow.** "The unit template *is* the serialisation of T3 and
   T4" cannot hold, because a template holds only directives, and the ADR-019
   waypipe version lock — normative, and the enforcement point of that ADR — is
   ~38 lines of host control flow that must run before QEMU. T4 is the template
   **plus the executables it references**, at `/usr/lib/katmate/`, under an
   explicit authority limit. §8's projection generator was already such an
   executable; this ADR relied on the category without naming it.
2. **§4 left the `class = sys` key set undefined.** Lifting ADR-015's
   AppVM-only restriction and calling the remaining keys "unchanged" does not
   survive contact with netVM: `persistence` describes a home LV it does not
   have, `identity` / `disposable` / `reset_on_shutdown` are AppVM archetype
   flags, and the validator's `manifest` enum is `vault web`. ADR-032 §3 makes
   the required set a function of `class`, with forbidden keys rejected at
   parse rather than ignored.
3. **§4's duplicate-`nic` rule needed a validator that enumerates.** The rule
   is cross-file; `tools/validate-properties.fish` is strictly per-file and
   erases its accumulator after each file. The rule was not implementable
   without a directory to read — which the tier table did not supply.
4. **T1's location, given as "config tree", existed nowhere.** A
   repository-wide search returned exactly one hit: that table row. ADR-032 §1
   supplies `/etc/katmate/vm/<name>.toml` and, more importantly, makes this
   ADR's authorship principle operative — *who wins on upgrade* — because a
   file's author is not visible in the file, and the principle was
   unfalsifiable as stated.
5. **T2 had no home for payload.** The host-side netVM metadata must name a
   kernel and an initrd, and the only location was `out/`, a `.gitignore`d
   build tree. ADR-032 §5 routes payload by producer.

§7 is unaffected: the apparent contradiction between "`/home` is named from the
instance" and the live `vm_app_web_home` was an artefact of the development
instance name `test_web`. Fixed AppVMs are 1:1 instance-to-VM
([ADR-032](DECISIONS.md#adr-032) §7), so the derivation yields the live name
unchanged.

§6 is unaffected and reinforced: ADR-032 §6 adds that the unit name *asserts* a
profile which the projection generator must verify against the derived one,
failing before QEMU on mismatch.

**Revision note (2026-08-09, build-order step 3a part 1):** gate **G2** names
`katmate-app-routed@` as the unit `app_web` starts from. It is misnamed, and the
correction follows from a fact about the machine rather than from a change of
mind.

`app_web.con` carries vsock, two block devices and an RNG. It has **no
`-netdev`, no `virtio-net-device` and no tap** — no network device of any kind.
[ADR-029](DECISIONS.md#adr-029) records this in its C2 findings and leaves AppVM
link topology *"opened, not settled"*. Under §2's profile function with `netvm`
empty, `app_web` therefore derives **`app-offline`**, and its T1 says so:
`netvm = ""`, which under [ADR-032](DECISIONS.md#adr-032) §3 is a *declaration*
of an offline domain rather than an omission.

Declaring `netvm = "netvm"` instead was considered and rejected. It would have
made step 3a **add** a mechanism rather than transcribe one, and step 3a's whole
value is as this ADR's empirical gate — every line of the launchers placed,
nothing lost. A T1 file asserting a link that no launcher has would have made
the gate measure the author's intent instead of the schema.

Four consequences, all from that one fact:

1. **G2 becomes `katmate-app-offline@app_web`.**
2. **Step 3a ships two unit templates, not three** — `sys-driver` and
   `app-offline`. `app-routed` is a valid profile of §2's function and stays in
   the table; what it does not have is a VM that derives it, so no gate can
   exercise it. A signed ISO carrying a template nobody has run would rot.
   It ships when AppVM link topology is decided and `app_web` gains a real
   `netvm`.
3. **[ADR-032](DECISIONS.md#adr-032) gate H2 needs a different pair.** As
   written it starts a file deriving `app-offline` under `katmate-app-routed@`,
   which cannot exist if `app-routed` does not ship. Inverted, it tests the same
   property with two templates that do exist: a file deriving `sys-driver`,
   started under `katmate-app-offline@`, must be refused by the projection
   generator before QEMU.
4. **[ADR-032](DECISIONS.md#adr-032) §2** names the waypipe gate as shared by
   `katmate-app-routed@` and `katmate-app-offline@`. The sharing is correct and
   unchanged; only one of the two ships in 3a.

**A fifth consequence is not a defect and should not be silenced.** ADR-015's
semantic invariant — a `web` manifest with no network is almost certainly wrong
— survived the removal of the `network` field, since the field changed and the
invariant did not. Re-expressed on `netvm`, it fires on `app_web` under
`--strict`. That warning is true: a web domain without network *is* anomalous,
and it is anomalous precisely because the AppVM network device does not exist
yet. It stops firing when topology is settled. Until then
`validate-properties.fish --strict` cannot serve as a pre-commit gate over the
real T1 set without an expected-warning allowance.

**Revision note, 2026-08-11 (step 3a part 2, §0):** G1's clause "with no `.con`
script present" conflated two properties. That the unit can start netVM is
observable in part 2; that the launcher is redundant is observable only where
the launcher is deleted, which is G3 in part 3. G1 is therefore read as: the
unit starts netVM, the uplink comes up, and QEMU is a child of the unit with the
`.con` not invoked. Literal absence moves to G3. No mechanism changed; the gate
was measuring two things under one name.

**Revision note (2026-08-17, step 3a part 2, gate G1 — E1's unnamed
precondition):** E1's *what the probe did not cover* list names three things. A
fourth, unnamed, is the one that decided the gate. E1a was necessarily measured
with the environment file **already present**: `EnvironmentFile=` without a
leading `-` is loaded before **every** `Exec*` invocation, `ExecStartPre=`
included, and an absent file fails the whole execution-environment setup before
anything is spawned. `systemd.exec(5)` states the rule plainly — the files are
read shortly before each process is executed, so a file generated in one unit
state is readable in the next — and the same rule governs the first state, which
has no producer before it.

Measured on MINIS 2026-08-17, systemd 261, in a probe carrying no KatMate
content. File absent: `Failed to load environment files: No such file or
directory` → `Failed to spawn 'start-pre' task` → `Result=resources`, with
`Mem peak: 0B` and `CPU: 0`; the `ExecStartPre=` that would have created the file
never ran. File present with a different value: the same unit re-read it and
`ExecStart=` saw what `ExecStartPre=` had just written — E1a reproduced exactly.
Both results are true and they are not in tension. E1a measured a **re-read**,
and could only have done so.

**Candidate A as transcribed in §8 therefore cannot start.**
`katmate-generate-env` is the only producer of `/run/katmate/vm/<instance>.env`,
it is referenced from exactly one place — that unit's own `ExecStartPre=` — and
`/run` is empty at every boot. `katmate-sys-driver@netvm.service` failed this way
on its first execution (gate G1, 2026-08-17, FAILED). Nothing in the template's
transcription of `net-sys.con` is implicated: `ExecStart=` was never reached and
remains UNVERIFIED in full.

**What is not withdrawn.** What is refuted is the transcription, not the
candidate. B remains recorded as measured working, with one cost this ADR did not
name: the profile a unit **asserts** reaches the generator as `%p`, and `%p`
inside a generator unit of its own is the generator's name, not the VM profile —
so under B the [ADR-032](DECISIONS.md#adr-032) §6 assertion check loses its
carrier and needs either the `<profile>:<instance>` instance-name idiom of
`systemd-backlight@` or a fourth executable. That cost belongs on the record
before anyone reaches for B expecting it to be free.

The correction is not ruled here. It requires one further measurement (E1c);
this note records the failure only.

**Revision note (2026-08-19, E1c — the correction to §8's mechanism):** **Candidate
A is kept and its transcription corrected.** The projection is declared optional to
systemd (`EnvironmentFile=-/run/katmate/vm/%i.env`) and the refusal that directive
used to carry moves into `katmate-generate-env`, which reads back its own published
output before exiting. Measured on MINIS 2026-08-19, systemd 261, `Type=simple`, on
a `/run` where `/run/katmate` did not yet exist: `PRE_SEES=[]` at the
`ExecStartPre=` read and `PROBE_RESULT=[42]` at the `ExecStart=` read, one start,
`Result=success`. The two reads carry the same journal timestamp and are separable
only by PID. The first is the state E1a could not observe — the file absent at the
first read, absorbed by the `-` rather than fatal — and the second is the same
re-read E1a did measure. E1's `Type=oneshot` caveat is retired with it.

**The `-` is not a fail-open.** It removes an enforcement point from systemd's
environment loader without removing the enforcement. The only path that reaches
`ExecStart=` with no projection is an `ExecStartPre=` that exits 0 without having
produced one, and the generator is written so that path does not exist:
`set -euo pipefail`, a rename into place from a temporary in the same directory,
the previous generation removed before anything can fail, every required key
emitted through a helper that refuses an empty value, and — added here — a
read-back of the published file before exit. [ADR-032](DECISIONS.md#adr-032) §2
puts binary decisions in the T4 executable that owns the input, not in a directive
that can only distinguish present from absent.

**Rejected — a separate generator unit (B).** Working, and dearer than when it was
measured: the `%p` cost named in the note above, plus it splits the
`ExecStartPre=` chain that gate H1 is written against. Against the corrected A it
buys only protection from a producer that exits 0 having written nothing, which
the read-back closes directly.

**Rejected — an `ExecStart=` wrapper that sources the projection and execs QEMU.**
That is `net-sys.con` again, and deleting both `.con` scripts is step 3a's gate.

**Consequences:** the `EnvironmentFile=` comment in `katmate-sys-driver@.service`
is rewritten to cite E1 and E1c together and to state why the `-` is there;
`katmate-generate-env` gains the read-back; G1, G4, G6 and H1 become runnable;
H1's three-preflight wording stands unchanged, since the chain is not split.

**Revision note (2026-09-02, §3 — the premise is superseded, the conclusion is
restored on a new model, and the count was already overtaken):** three separate
things, recorded together because they are one section's fate.

**1. The premise is gone.** §3 grounds itself in a netns and a tap: a
`NetworkNamespacePath=/run/netns/katmate-%i`, and a tap created inside it and
owned by the per-VM uid so QEMU opens it without `CAP_NET_ADMIN`.
[ADR-033](DECISIONS.md#adr-033) abolished both. A link is a pair of AF_UNIX
datagram sockets opened by path at start — no netns, no tap, no bridge, and no
`CAP_NET_ADMIN` anywhere in an AppVM's start path. Those two bullets describe a
mechanism this project no longer intends to build.

**2. The conclusion is restored, on the new model, by
[ADR-035](DECISIONS.md#adr-035) §9** — and restored more strongly than §3
claimed it. Under the netVM link pool the template's network argv is sixteen
literal `-netdev dgram` / `-device virtio-net-pci` pairs, with `%i` in the
socket paths and constant MACs, and **no network scalar crosses at all**;
`KM_MAC_INT` retires with `tap-int0`. §3's principle — a fixed, validated key
set, each key at a fixed position, the braced `${}` form so a value can never
become an argument — is untouched, and is what ADR-035 builds on.

**3. The arithmetic was overtaken before either later ADR, by this project's own
template.** §3 reads *"Exactly two values still cross"* and names `KM_CID` and
`KM_VFIO_BDF`. The shipped template interpolates **nine** distinct `${KM_*}`
values in its `ExecStart=` — measured 2026-09-02 by reading
`host/usr/lib/systemd/system/katmate-sys-driver@.service`: the two named, plus
`KM_MEM`, `KM_VCPUS`, `KM_KERNEL`, `KM_INITRD`, `KM_ROOT_DEVICE`,
`KM_ROOTFS_DEV` and `KM_MAC_INT`. The count is a statement about a template that
did not exist when §3 was written, and it is recorded here so the sentence is not
read literally by a later session. **The rule the count illustrates held
throughout and holds now** — every one of the nine is in the fixed key set, at a
fixed position, in the braced form.

**This note records a supersession and changes no sentence above it.** ADR-035
is PROPOSED and none of its six gates has been taken, so §9's restoration is a
decision about argv, not a template that ships.

---

## ADR-032 — Where each tier lives: the path is the tier, and T4 is more than the template

**Status:** Accepted (2026-08-09). Gates H1–H3 below are open and belong to
build-order step 3a.
**Depends on:** [ADR-030](DECISIONS.md#adr-030) (what the daemon reads),
[ADR-029](DECISIONS.md#adr-029) (systemd owns the VMM process),
[ADR-022](DECISIONS.md#adr-022) (object model), [ADR-019](DECISIONS.md#adr-019)
(waypipe version lock)
**Revises:** [ADR-030](DECISIONS.md#adr-030) §2 and §4 — see the revision note
on that ADR. Nothing in ADR-030 is withdrawn; two definitions are widened and
one location is supplied.

**Context:**

ADR-030 named four artefacts and set the tier boundary at **authorship**. Step
3a began as its empirical gate: take both live `.con` launchers apart and place
every line, on the principle that a line with nowhere to go is a hole in the
schema. The gate ran before any file was modified and returned five holes.

1. **T1 has no location.** ADR-030 gives it as "config tree". A
   repository-wide search for that phrase, for `/etc/katmate` and for
   `etc/katmate`, returns exactly one hit: that table row. No config directory
   exists, no example `properties.toml` exists, and the installer creates
   nothing of the kind. Work order step 2 could not be executed without
   inventing a path no ADR specifies.
2. **`app_web.con`'s waypipe version-lock preflight has no tier.** Roughly 38
   lines that read `foundation.meta`, compare the recorded tag against the host
   binary and refuse to launch on mismatch. ADR-019 makes this the enforcement
   point of the version lock and `state.md` records it as normative. It is not
   T1 (not user data), not T2 (it *consumes* T2), not one of §3's two typed
   scalars, and not a directive that can appear in a unit file. Two smaller
   items of the same class sit beside it: the delta-existence check and the
   kernel-existence check.
3. **The required key set for `class = sys` is undefined.** ADR-030 lifts
   ADR-015's AppVM-only restriction and lists the remaining keys as
   "unchanged", but applied to netVM the remainder does not survive contact:
   `persistence` is a property of a home LV that netVM does not have,
   `identity` / `disposable` / `reset_on_shutdown` are AppVM archetype flags,
   and the validator's `manifest` enum is literally `vault web`.
4. **The duplicate-`nic` rule is not an added rule.**
   `tools/validate-properties.fish` is strictly per-file — `validate_file` ends
   by erasing every parsed key and no cross-file accumulator exists. Gate G5 is
   inherently cross-file and is only satisfiable if the validator has something
   to enumerate, which (1) denies it.
5. **T2 must record a payload path, and no runtime home for a payload
   exists.** The host-side `netvm.meta` has to name a kernel and an initrd.
   Today they are in `out/`, which is `.gitignore`d and is a build tree, not a
   runtime location. `/var/lib/katmate/` was convention for metadata, not for
   payload.

These are five expressions of one omission. ADR-030 answered *what* the daemon
reads and *who wrote it*; it never said **where any of it lies**. The
consequence was not abstract: an agent reading the repository could not
execute step 2 of the work order without inventing a path, and a preflight that
an accepted ADR makes normative had nowhere to be.

**Decision:**

### 1. The path is the tier

Each tier gets a directory, and the directory is the tier's public statement of
what it is. A reader establishes a file's tier with `ls`, not by reading this
document.

| Tier | Author | Directory | Wins on upgrade |
|---|---|---|---|
| **T1** instance properties | the user | `/etc/katmate/vm/<name>.toml` | the **user** |
| **T2** image metadata + payload | the build pipeline | `/var/lib/katmate/` | the **pipeline** |
| **T3+T4** templates and their executables | the release | `/usr/lib/systemd/system/`, `/usr/lib/katmate/` | the **release** |
| — runtime projection | derived at start | `/run/katmate/` | nothing; rebuilt every start |

**"Authorship" is made operative as: who wins on upgrade.** ADR-030's principle
was sound and unfalsifiable as stated — a file's author is not visible in the
file. The upgrade question is answerable and mechanical. `katmate-update` never
touches `/etc/katmate/`; it replaces `/usr/lib/` wholesale.

**The installer seeds T1; it does not own it.** The relation is `/etc/skel` to
`$HOME`. Files written at install time are the user's from that moment, and a
later release that needs a schema change notifies rather than overwrites. This
is the pattern the project already applies to `outputs.conf` and the generated
greetd sessions: per-machine, out of git by design.

**T1 is therefore never in the repository.** This follows from ADR-030's own
principle rather than from taste: a committed `properties.toml` was authored by
the project, and by the tier boundary that makes it T3/T4, not T1. A file
cannot be T1 in the tree and T1 on the machine.

`/etc/katmate/vm/<name>.toml` is flat, one file per VM, `root:root` `0644`. A
per-VM *directory* is rejected because it admits two sources for one VM, which
is this project's characteristic failure class. If drop-ins are ever wanted,
`<name>.toml.d/` is a later extension and does not need to exist now. Root
ownership is not a restriction on the user: the profile is derived either way,
and weaker containment was never selectable.

**Scope limit — this rule governs what the daemon reads as data.** Host
binaries produced by the build pipeline keep the location ADR-019 already
established (`/opt/katmate/bin/`). `/var/lib` is commonly mounted `noexec` and
is not a home for executables. The rule is about tier legibility for
configuration, metadata and payload; it does not relocate binaries, and it is
not evidence that `/opt/katmate/` is wrong.

### 2. T4 is the template **plus the executables it references**

ADR-030 §2 states that the unit template *is* the serialisation of T3 and T4.
A template can only hold directives, so on that reading the waypipe gate — host
control flow that must run before QEMU — has no tier. But the gate ships on the
signed ISO, no user writes it, and a release replaces it wholesale. By every
test this ADR sets, it is T4. The definition was too narrow, not the artefact
misplaced.

**T4 executables live in `/usr/lib/katmate/`** and are referenced from
`ExecStartPre=`. ADR-030 §8 already relies on this category without naming it:
the projection generator is exactly such an executable.

**Authority limit.** A T4 executable:

- **may read** T1 and T2;
- **may write** only under `/run/katmate/`;
- **decides binarily** — proceed, or fail loudly;
- **may derive the profile only from `(class, netvm, nic)`**.

Without the limit, widening T4 would open a second route to the profile: a
future `ExecStartPre=` could read T1 and adjust the projection, and containment
would become negotiable — precisely what ADR-030 §3 refuses. The gate and the
generator are the same kind of object under the same authority, and a later
addition cannot quietly become a third path.

**One executable per check, chained.** systemd stops at the first failing
`ExecStartPre=` and the journal names the line that failed. A single
`katmate-preflight` taking arguments would have to print that itself: more code
for less information. Step 3a therefore ships:

- `katmate-check-waypipe` — the ADR-019 version lock. Shared by
  `katmate-app-routed@` and `katmate-app-offline@`; an offline vault runs
  waypipe too.
- `katmate-check-image` — backing-chain and payload existence.
- `katmate-activate-lvs` — the `lvchange -K -ay` sequence, `ExecStartPre=+`
  because it needs uid 0.
- `katmate-generate-env` — the ADR-030 §8 projection.

### 3. The required key set is a function of `class`

A key with no meaning for a class is **forbidden**, not ignored. A
`persistence` line on a netVM that is silently discarded is the *silent
wrong-object* failure this project keeps finding — the stale BDF passing the
wrong device, `networkctl` reporting `routable` and `offline` together. A key
the user can set that does nothing is worse than a key that does not exist.
Forbidden keys are rejected at parse, in the same spirit as *absent, not
disabled*.

| | Common | `class = sys` | `class = app` |
|---|---|---|---|
| Required | `class`, `cid`, `manifest`, `mem`, `vcpus` | `nic`, `provides_network` | `netvm`, `persistence`, `identity`, `disposable` |
| Optional | — | — | `reset_on_shutdown` |
| Forbidden | — | `netvm`, `persistence`, `identity`, `disposable`, `reset_on_shutdown` | `nic`, `provides_network` |

`nic` forbidden on an AppVM is not tidiness. An AppVM holding hardware directly
defeats the containment model, and parse-time rejection is the one place that
cannot be passed.

`netvm` required on `class = app` is satisfied by the field being present and
explicitly empty; an absent `netvm` is an unstated assumption, an empty one is
a declared offline vault.

**`manifest` becomes class-dependent in its values**, not a widened shared
enum: `sys` → `netvm`; `app` → `vault | web`. A shared enum would make
`manifest = netvm` legal on an AppVM — a valid value that builds the wrong
image.

`persistence` is forbidden on `sys` because netVM's whole rootfs is a
runtime-mutable linear RW LV by construction and there is nothing for the user
to choose. Should a future sysVM carry durable state — the ADR-022 proxy VM
will want a cache — that is a **widening** of this schema, which is the
direction this project's rules permit. Permitting it now and discovering the
key never did anything is the direction that cost ADR-021 and ADR-025 Path A.

### 4. The validator enumerates a directory

`tools/validate-properties.fish` gains a directory argument defaulting to
`/etc/katmate/vm/`, and validates `*.toml` within it. The per-file rules are
unchanged; the cross-file rule ADR-030 §4 requires (no two VMs may claim the
same `nic` label) needs an accumulator that survives `validate_file`, and needs
a guarantee that every VM's file was seen. The directory is that guarantee.
Invoked on individual files, the validator runs per-file rules and **reports
that cross-file rules were not evaluated** rather than passing silently.

`class = sys` with `nic` absent resolves to `sys-proxy`, which ADR-030 §2 names
and does not ship: an explicit error, never a default.

### 5. Payload location follows the producer

The same test as everywhere else in this ADR — who made it, and who wins on
upgrade:

- **`/var/lib/katmate/netvm/`** — `vmlinuz`, `initrd.img`, `netvm.meta`.
  Produced by `build/netvm.sh`, replaced on rebuild, not signed with the ISO.
  Payload and its metadata share a tier and a lifecycle, which is why they
  share a directory. Written after the build succeeds, after `trap - EXIT`, on
  the pattern `build/foundation.sh` already uses.
- **`/var/lib/katmate/kernels/`** — the shared custom microVM kernel. Built
  once, used by every AppVM.
- **`out/`** remains a build tree and is never read at runtime. A unit reading
  from `out/` would mean a release running from build artefacts.

**The AppVM kernel is T2 with one value for all images.** `<image>.meta`
records *which* kernel an image requires, not where it lies. Today every image
records the same one. The alternative — a host property in `HOST-CONFIG.md`
with the unit carrying it as a profile constant — costs nothing today and costs
a migration on the first image that needs a different kernel. One key now.

### 6. The unit name asserts the profile; the projection verifies it

`systemctl start katmate-sys-driver@netvm` asserts a profile. The T1 file
derives one from `(class, netvm, nic)`. `katmate-generate-env` computes the
derived profile and **fails** if it does not match the unit it is running
under, before QEMU is reached.

The check exists for step 3b: when the launch daemon selects unit names, an
unwritten rule would be one it could violate silently. Under ADR-029, systemd
starts the VM and the daemon only orders — so the daemon's choice of unit name
is the one place a wrong profile could enter with nothing to catch it.

### 7. Instance names: 1:1 for fixed AppVMs

For fixed AppVMs (CID 20–99) the instance name **is** the VM name. `%i` is
therefore both the T1 filename stem and the derivation input for per-instance
names.

This closes an apparent contradiction rather than deciding a new thing.
ADR-030 §7 requires `/home` to be named from the instance; the live launcher
declares `INSTANCE=test_web` against `vm_app_web_home`, so a template using
`vm_%i_home` appeared to yield a nonexistent LV. With 1:1 the instance is
`app_web`, the derived name is `vm_app_web_home`, and the live LV needs no
rename. `test_web` was a development artefact. Only the delta filename follows
it.

Instance and VM name diverge for disposables (CID ≥ 100), where the instance is
generated and the definition is shared. §7's rule is written for that case and
is unaffected.

**Consequences:**

- Four new filesystem locations are established: `/etc/katmate/vm/`,
  `/usr/lib/katmate/`, `/var/lib/katmate/netvm/`, `/var/lib/katmate/kernels/`.
  Each is created by the installer; none is in the repository.
- `SECURITY-MODEL.md` gains a checkable property it did not have: a file's
  authority is legible from its path. A T1 file under `/usr/lib/` or a T4
  executable under `/etc/` is a defect visible to `ls`.
- The installer acquires a seeding responsibility (build-order step 6) and a
  constraint: it may create T1 files, and it may never overwrite one it did not
  create in the same run.
- `tools/validate-properties.fish` changes shape, not just rule count.
- ADR-030 §2 and §4 are widened; the revision note on that ADR records it.
- Step 3a is unblocked. Its five blocking findings are answered; the two
  architectural items it correctly refused — memory backing, and storage shape
  as a profile input — remain open and outside both ADRs.

**Alternatives considered:**

- **T1 shipped in the repository, installed to `/etc/`.** Rejected as
  self-contradictory under ADR-030's own boundary: a committed file was
  authored by the project.
- **T1 under `/var/lib/katmate/`.** Rejected. `/var/lib` is state a program
  maintains; T1 is configuration a human writes. The distinction is the whole
  content of the tier boundary.
- **A single `katmate-preflight` binary.** Rejected: loses systemd's
  per-directive failure reporting.
- **A fifth tier for host control flow.** Rejected. It shares an author, a
  location and an upgrade owner with T4; a separate tier would record a
  distinction that does not exist.
- **`persistence` in the common set with a `sys`-specific value.** Rejected:
  the value would state a fact about the image rather than a user choice — T2
  pasted into T1.

**Gates (open, step 3a):**

- **H1 — `ExecStartPre=` chain.** Three preflights, the second made to fail.
  Confirm systemd does not run the third, the unit does not start, and the
  journal names the failing executable. Confirms §2's "one executable per
  check" is worth its cost.
- **H2 — profile mismatch refused.** Start a `properties.toml` deriving
  `app-offline` under `katmate-app-routed@`. Confirm
  `katmate-generate-env` fails before QEMU and the journal states which profile
  was asserted and which derived.
- **H3 — forbidden key rejected.** `persistence` on a `class = sys` file must
  fail validation, not warn. Same for `nic` on `class = app`. Confirms §3 is
  enforced at parse.

**Revision note (2026-08-11, step 3a part 2, §3):** §2 gives
`katmate-check-image` "backing-chain and payload existence". The backing chain
is LVM, and LVM metadata is not readable by the unprivileged user the check
runs as — measured on MINIS as uid 1000: `lvs vg0` exits 5 with
`/dev/mapper/control: open failed: Permission denied` and `Can't get lock for
vg0`, and membership of group `disk` does not help. Since §2 also places the
cheapest gate first, deliberately *before* anything is activated, the two
halves of the sentence cannot both hold: an LV existence check either needs
uid 0 (widening the privileged set from one executable to two, against C1/C3)
or must run after activation (losing the cheapest-first ordering that is §2's
stated reason for the chain).

The chain is therefore split by **what each stage can actually read**:
`katmate-check-image` verifies kernel, initrd and `<image>.meta` — plain files
readable as uid 1000 — and `katmate-activate-lvs`, already `ExecStartPre=+`
for uid 0, carries LV existence, because `lvchange -K -ay` *is* an existence
check and fails by name on an absent LV. No third executable, no widened
privilege, and the ordering §2 argues for survives. The privilege boundary did
not move; it became visible.

**Revision note (2026-08-22, §1 — the runtime projection's lifetime, and what it
is authority for):** §1's table gives `/run/katmate/` as *"derived at start;
nothing wins on upgrade; rebuilt every start"*. That says where it comes from and
says nothing about how long it lasts, and the 2026-08-22 measurements make the
difference matter.

**A runtime projection describes the *last start*, not a running VM.** It is
written by `ExecStartPre=`, it is **not removed at stop**, and it survives both a
clean stop and a failed start; `/run` being tmpfs, it is cleared only at boot.
**The authority for liveness is systemd's unit state, never the presence of a
file under `/run/katmate/`.** Anything that needs to know which VMs are running
asks systemd — that is ADR-029's division (systemd owns the VMM process) applied
to the artefact rather than to the process.

Measured, and this is what the note rests on: `/run/katmate/vm/netvm.env`
survived the part-2 stop **byte-for-byte** — same size, same twelve keys, same
mtime, with the unit `inactive (dead)` and no QEMU — and survived H1's failed
start unchanged as well, describing in both cases a VM that was not running. The
projection is regenerated at every start, so it cannot mislead the start path;
what it can mislead is a **reader of `/run`**, and the rule above is the answer to
that.

**Decided at the same time, and recorded because it is the tempting fix:** an
`ExecStopPost=` that removes the projection is **rejected**. The projection left
behind by a *failed* start is exactly the evidence the next reader needs — it is
what the executables computed on the way to refusing — and deleting it would
delete precisely the case worth inspecting, in exchange for a liveness signal
`/run` should not be carrying in the first place. The failure this project keeps
finding is a plausible artefact that is no longer true; the answer is to state
what the artefact means, not to make its absence mean something too.

Nothing in §1 is withdrawn. The table row is unchanged; its lifetime and its
authority are supplied.

---

## ADR-033 — AppVM link topology: p2p over AF_UNIX datagrams, from a static slot pool

**Status:** Accepted (2026-08-28). Its viability premises were measured by
link-m1 and link-m2 (2026-08-24, MINIS) and its sizing premise by link-m3
(2026-08-28, MINIS), which took gate **M2**; `N` is **16**, ruled on that
measurement and recorded in `state.md` § *Next steps*. This line read
`PROPOSED` until acceptance, and the sentences it carried — *"its sizing
premise is not"* and *"`N` may not be fixed until M2 is taken"* — were true
when written and are discharged by the acceptance note at the end of this ADR.
**Accepted is a decision and not an implementation:** no pool exists in netVM
and no `app-routed` template ships.

**Depends on:** [ADR-022](DECISIONS.md#adr-022) (an AppVM routes through a netVM
and has no neighbour on the host), [ADR-025](DECISIONS.md#adr-025) (NETCFG
programs addressing inside the guest), [ADR-029](DECISIONS.md#adr-029) (systemd
owns the VMM process), [ADR-030](DECISIONS.md#adr-030) (what the launch daemon
reads), [ADR-032](DECISIONS.md#adr-032) (where each tier lives)

**Closes:** the *"AppVM link topology — opened, not settled"* item left by
ADR-029's C2 finding, and with it the unconditional guard in
`katmate-generate-env` that refuses profile `app-routed`.

**Measurement sources:** `~/link-m1-report.md` and `~/link-m2-report.md`, both
2026-08-24, both measured on MINIS against QEMU 11.1.0, unprivileged throughout,
with netVM running and untouched. Neither report is in the repository; section
numbers below are theirs. Every figure in this ADR comes from one of the two.

**Context:**

`ARCHITECTURE.md` fixes the model, and has since before it was implementable:
isolation between AppVMs is carried by **topology** — a per-AppVM p2p link with
a link-scoped `/32` — never by a per-AppVM firewall rule. An AppVM has no
neighbour on the host and no guest-to-guest path.

**The p2p model fixes the device count independently of any backend choice.** A
`/32` per AppVM means one netVM-side interface per AppVM. That is the cost of
the model, not of the mechanism chosen here, and the only topology avoiding it
is a shared segment where every guest is an L2 neighbour of every other and
separation is a bridge port attribute whose absence is not an error but
reachability. **Rejected on the model, not on measurement.**

So the question was narrower than it looked: given one netVM interface per
AppVM, what carries the frames? Three candidates were weighed against the
record — a tap pair joined by a per-link bridge; a shared bridge with port
isolation; and `-netdev dgram` over AF_UNIX socket paths.

**Decision:**

**A link is a pair of AF_UNIX datagram sockets under `/run/katmate/link/`.**
Each end is opened by the QEMU process that owns it, by path, at start. No
descriptor handover, no parent holding fds, no tap, no bridge, no network
namespace, and **no `CAP_NET_ADMIN` anywhere in an AppVM's start path**.

**netVM starts with a fixed pool of `N` link slots.** A slot is a `virtio-net`
device with a `dgram` backend on a fixed socket path. Empty slots have no peer.
An AppVM is allocated a free slot at launch and releases it at teardown; NETCFG
then programs the `/32` inside each guest exactly as it does today.

**Slot allocation is CID allocation's mechanism on a second namespace.**
[ADR-017](DECISIONS.md#adr-017) already allocates and reconciles CIDs; a slot is
another field on the same allocation, not a new subsystem.

### What was measured, and what it settled

**The pool is viable — a slot with no peer is startable, and later usable.**

- **A device whose `remote.path` does not exist starts silently.** Zero bytes on
  stderr, one added fd, **no added thread**, and **zero CPU ticks of 6000
  available** over a 60 s window (link-m1 § 11, against the no-device control in
  § 9).
- **The address is resolved per send.** A guest emitted ten broadcast frames
  into an absent peer, the peer path was then created, and the **first datagram
  to arrive carried `seq=000010`** — the first frame emitted after the socket
  existed. `seq=000000`–`000009` appear nowhere in the receiver's log; from
  `000010` the stream is contiguous. Arrival was 0.605 s after bind. The reverse
  direction works and is a separate result. (link-m2 § B2.2–§ B2.5.)
- **The startup trace names no peer.** Outside dynamic linking, a shape-(ii)
  QEMU issues exactly `unlink(local)` → `ENOENT`, `socket(AF_UNIX,
  SOCK_DGRAM|SOCK_CLOEXEC)`, `bind()`. **No `connect()`, and `remote.path`
  appears nowhere in the trace** — not `stat`-ed, not opened. `ss -xap` reads
  `u_dgr UNCONN, peer *` whether or not the peer exists. (link-m2 § A.3, on a
  trace filter verified against a program known to issue all five call kinds,
  § A.1; `ss` readings link-m1 §§ 11–12.)
- **A stale socket path does not block a later start**, and the `unlink()` above
  is the mechanism: QEMU replaces the node rather than adopting it. (link-m1
  § 19 measures the result — a new inode at the same path; link-m2 § A.4 has the
  call, with the bound that it was traced against an absent path.)
- **`CONFIG_VIRTIO_NET=y`** in the custom microVM kernel, alongside `PACKET`,
  `INET`, `IPV6`, `VIRTIO_MMIO` and `VIRTIO_MMIO_CMDLINE_DEVICES`, all builtin
  (link-m1 § 3a–§ 3b, link-m2 § B0.2). This reading is of the `.config` beside
  the image, **not of the image**: `CONFIG_IKCONFIG` is unset and
  `extract-ikconfig` recovers nothing, so if behaviour ever contradicts one of
  these symbols, that is evidence about the config/image pairing and not about
  the backend (link-m2 § B0.4).

**The cost of an empty slot is small, and asymmetric between machine types.**
Paused QEMU, three repetitions per point, reported individually in link-m1
§§ 20–21. The readings below are the first repetition of each point; the three
agree to within 12 kB at every point measured.

| | `q35` + `virtio-net-pci` | `microvm` + `virtio-net-device` |
|---|---|---|
| RSS, `N`=0 → 1 | 38.7 → 39.5 MB | 38.1 → 38.6 MB |
| RSS, `N`=0 → 8 | 38.7 → 43.3 MB | not measured |
| VmSize, `N`=0 → 1 | 1430112 → 1432588 kB | 1425232 → 1425392 kB |
| VmSize, `N`=8 | 1462392 kB | not measured |
| threads | 3 at every `N` | 3 at every `N` |
| CPU / 60 s | 0 ticks | 0 ticks |

The reports compute no per-device cost and extrapolate to no value of `N`
(link-m1 § 25), so neither does this table: what it shows is the two machine
types' readings side by side, at the points that were run.

**The binding limit is PCI topology, not memory.** `q35` refuses the 31st
`virtio-net-pci` on the default root bus — `PCI: no slot/function available`,
naming `netdev=n30`, all three repetitions, after placing `n0`–`n29` (link-m1
§ 20.1). netVM already carries a vfio NIC, virtio-blk and vhost-vsock
(`net-sys.con:19,24,25`), so **the practical ceiling is below 30 and has not
been measured.** Raising it means added PCIe root ports, which is a topology
change and a separate decision.

### Costs accepted, stated rather than argued away

- **There is no carrier.** A datagram socket cannot represent an absent peer.
  The guest's `sendto` returned `rc=18, errno=0` **identically** in the peerless
  and peered windows (link-m2 § B2.2): the failure is never reported upward, and
  the guest's interface shows link-up regardless. A tap backend can signal
  link-down; this cannot. **Start ordering is therefore entirely the launch
  daemon's responsibility** and the guest cannot assist.
- **No `vhost` acceleration.** `vhost-net` binds to a tap fd and has no
  socket-backend equivalent; `vhost-user` would bring a switching daemon and
  shared memory into the TCB and is rejected. Every frame crosses QEMU's main
  loop, and one frame is one datagram at roughly MTU size.
- **Loss instead of backpressure** on a full receive buffer. Ethernet permits
  it and guest TCP absorbs it, but the behaviour under load is loss.
- **A less-trodden path in the VMM.** `-netdev tap` with `vhost` is the most
  exercised network path in QEMU/KVM; `dgram` is not, and the backend is
  reachable from the guest's virtqueue. Taken deliberately, and recorded in
  `OBSERVATIONS.md` as KatMate's own choice.
- **Growth beyond the pool costs a netVM restart**, and with it every AppVM's
  connectivity.
- **The printed synopsis and the runtime disagree.** QEMU 11.1.0 brackets
  `remote` as optional and then refuses it as mandatory for `unix` and `inet`
  (link-m1 § 2c against § 10). **KatMate treats the runtime refusal as
  authoritative** and every slot names a peer path whether or not the peer
  exists. Worth reporting upstream.

**Consequences:**

*Easier*

- An AppVM's start path needs no privileged network step at all.
- Reconcile ([ADR-017](DECISIONS.md#adr-017)) gains a slot field, not a device
  inventory; no orphan device class is created.
- `app-routed` becomes startable: the guard in `katmate-generate-env` and the
  `REQ_ENV` arm fall **together in one commit**, which is what open problem #19
  requires and in the order it requires.
- ADR-015's `web`-manifest-without-network warning stops firing on `app_web`
  once its T1 names a netVM, and `--strict` becomes usable over the real T1 set.

*Harder*

- netVM's device count becomes a boot-time constant, bounded by PCI topology
  rather than by memory, and the bound is lower than the pool sizes considered.
- **Socket files outlive their processes, including on a failed start.** A QEMU
  that fails during device realisation still leaves every path it bound — 96
  files from three failed runs, measured (link-m1 § 20.1, § 23).
  `ExecStopPost=` must unlink the slot's socket, and, as with the projection,
  **presence of the file is not authority for liveness**; systemd is. Same rule,
  same ADR-032 paragraph.
- **The guest emits IPv6 router solicitations unprompted.** Two `ICMPv6 0x85`
  frames appeared in a 30 s window with no configuration asking for them
  (link-m2 § B2.4). If netVM ever answers with an RA, the AppVM acquires
  addressing by SLAAC **outside NETCFG** — a second source of one truth, which
  this project does not tolerate. AppVM images set `accept_ra=0`; netVM sends no
  RA on internal links.
- The netVM-side slot-to-interface mapping must be stable and legible, or NETCFG
  programs the right `/32` on the wrong interface. **Unresolved.**

*To revisit*

- If M2 shows the single main loop saturating at a small number of active links,
  the p2p model itself — not this backend — needs revisiting, since a per-link
  bridge concentrates the same traffic in the same process.

**Remaining gate:**

**M2 — saturation of netVM's single main loop.** All AppVM traffic converges on
one QEMU process with one event loop, and `dgram` has no `vhost` equivalent, so
that loop is in the data path for every frame. Measurable **without a single
AppVM**: a host-side generator writing to `N` sockets, with netVM's `utime`
watched for the knee. Frames need not be valid — the guest discards them at the
ethernet layer *after* QEMU has done the work being measured. **`N` is fixed
after M2, not before.**

**Open in this ADR, deliberately:** the slot-to-interface naming scheme; `N`;
the socket path convention under `/run/katmate/link/`; whether a released slot
is reused immediately or quarantined; what a slot's MAC derives from (ADR-025's
sha256 scheme is the obvious candidate and is not assumed); and whether QEMU
issues a failing `sendto` per frame or discards without a syscall while a peer
is absent — unmeasured, and relevant only to the cost of an AppVM transmitting
into a dead slot.

**Revision note (2026-08-28, § *Remaining gate*, § *Costs accepted* and
§ *To revisit* — M2 measured, and a cost that did not occur):** M2 has been taken
(`~/link-m3-report.md`, MINIS, 2026-08-28) and **is discharged**. This note
records what it found. **It does not accept this ADR, whose status stays
PROPOSED**, and it changes no sentence above: this file is append-only and the
original text stands as written.

**1. There is no knee, because the loop is saturated at one link.** The gate
above expects a point at which the single main loop stops keeping up as active
links are added. There is no such point in the range that starts. The event loop
thread is at **99.6 %** of one core with **one** active link, and at
**98.7–99.6 %** across all eighteen 60 s windows of a sweep over
`N ∈ {1, 2, 4, 8, 16, 30}`, three repetitions each. Delivered load rises from
~174 000 to ~316 000 frames/s over that range and never falls. **`N` is
therefore no longer gated by saturation** — there is no knee to stay below, and
thirty links cost the loop no more than one does. What scales down is throughput
per link: ~174 000 frames/s on one link, about 10 600 each on thirty.

**2. A cost this ADR accepted did not occur — and only half of the clause is
contradicted.** § *Costs accepted* reads:

> **Loss instead of backpressure** on a full receive buffer. Ethernet permits
> it and guest TCP absorbs it, but the behaviour under load is loss.

**The premise held and the consequent did not.** The receive buffer *did* fill —
31.9 M refusals in a single 60 s window at `N`=30, against
`/proc/sys/net/unix/max_dgram_qlen` = **512** datagrams, which is the entire
buffer between the two processes. What followed was not loss. **Zero frames were
lost in all eighteen runs**: the count the generator was told had been accepted
equals the count the guest's own driver recorded, as identical integers, link by
link and repetition by repetition, with the byte totals matching exactly as well.
The full buffer refused the sender with `EAGAIN` — one errno wide, on every
socket of every run — rather than accepting a frame and discarding it.

**The bound on that, which is why the cost is not simply gone.** The sender in
this measurement was a purpose-written program that **counts** its refusals. The
real sender is another QEMU, and **whether QEMU-as-sender retries or discards on
`EAGAIN` is unmeasured** — it is already among this ADR's own open items above,
and M2 did not close it. So what is now measured is what the **socket** does:
backpressure, not silent loss. What the **sending VMM** does with that
backpressure remains open, and the accepted cost stands until it is measured.

**3. § *To revisit* is NOT triggered.** That clause reads: *"If M2 shows the
single main loop saturating at a small number of active links, the p2p model
itself — not this backend — needs revisiting."* The loop saturates at **one**
link, which is smaller than any number the clause anticipated — and the clause
still does not fire, because **saturating at one link and degrading with link
count are different findings, and only the second implicates the model.** A
per-link bridge would concentrate the same traffic in the same process; it would
not give that process a second core. The measurement shows the shared ceiling
being divided, not a cost that grows with the number of links: per-interface
counts span **7 frames in 634 765** at `N`=30 (repetitions 2 and 3: **2** and
**1**), worst 0.054 % anywhere in the sweep — with the bound that the generator
offered exactly equal load per link, so this is the loop's evenness under equal
offering and not under unequal.

**4. What the gate was measured with, which is not what the sentence above
names.** The *Remaining gate* text specifies **netVM's own `utime`** watched for
the knee. M2 was taken against a **standalone QEMU of the same shape** —
`-machine q35,accel=kvm -cpu host -smp 1`, taken from `net-sys.con` rather than
invented — because netVM carries no `dgram` device today, and giving it one would
*be* the pool whose size was the undecided thing. netVM was **down** throughout
and was not touched. Recorded here so that the difference is visible to anyone
reading this gate as discharged.

**5. The device ceiling, reproduced, and what it is not.** `N`=30 starts and 31
refuses — *"PCI: no slot/function available for virtio-net-pci"*, naming
`netdev=n30`, byte-identical across five observations — this time under KVM with
a booting guest that enumerated all thirty interfaces, where link-m1 § 20.1 found
it under TCG on a machine paused at reset. The ceiling is PCI topology, unmoved
by the accelerator or by whether a guest runs. **This is not netVM's ceiling**,
which remains unmeasured: the paragraph above under *"The binding limit is PCI
topology, not memory"* still stands, and `state.md` § *Next steps* carries the
arithmetic and the value of `N` ruled from it.

**Acceptance note (2026-08-28) — what this rests on, and what it does not yet
do:** the status line above was changed from `PROPOSED` to `Accepted` in place,
which is this file's practice for that one line and only that line: `405289c`
(2026-06-13) moved ADR-010 and ADR-011 from `Proposed` to `Accepted` the same
way, and `5f753b9` (2026-07-23) rewrote ADR-025's to record live-gating. The
body below is untouched and stays append-only.

**One sentence earlier in this ADR is superseded by that change, and is not
edited.** The M2 revision note above states *"It does not accept this ADR, whose
status stays PROPOSED"*. **That was true on the morning of 2026-08-28** — M2 was
discharged hours before the ruling — **and was superseded the same day by the
status line above, which is the authority on this ADR's status.** The note stands
as written because it was true when written. **Its substantive claim remains
true of what M2 did:** discharging a gate is not the same act as accepting the
ADR that named it, and M2's discharge did not accept this one. The acceptance is
a separate ruling, recorded here.

**What acceptance rests on — three measurement sessions, and what each
discharged.**

- **link-m1** (2026-08-24, `~/link-m1-report.md`) — that the **pool is
  possible**. `dgram` exists as a netdev type in QEMU 11.1.0; a slot whose
  `remote.path` does not exist starts silently, at one added fd, **no added
  thread** and **zero CPU ticks** over 60 s; a stale socket path does not block
  a later start; and the binding limit is PCI topology, `q35` refusing the 31st
  `virtio-net-pci` on the default root bus.
- **link-m2** (2026-08-24, `~/link-m2-report.md`) — that the **peer may appear
  afterwards**, which is what makes a pool of empty slots usable rather than
  merely startable. The startup trace is `unlink` → `socket` → `bind` with **no
  `connect()`** and `remote.path` nowhere in it; a guest emitted ten frames into
  an absent peer and the first datagram to arrive after the peer bound carried
  `seq=000010`. The address is resolved per send.
- **link-m3** (2026-08-28, `~/link-m3-report.md`) — gate **M2**, the sizing
  premise, discharged by the revision note above. **There is no knee**: the
  event loop is saturated at **one** link and shared continuously from there, so
  `N` is not bounded by saturation. What now bounds it is netVM's own PCI slot
  ceiling, which is unmeasured.

**`N` is 16.** Ruled by the operator on 2026-08-28 and recorded with its
reasoning in `state.md` § *Next steps*: below an **arithmetic** ceiling of
roughly 26 — the measured 30 on the default `q35` root bus, less netVM's vfio
NIC, `virtio-blk-pci`, `vhost-vsock-pci` and `virtio-rng-pci`, the internal
segment's own `virtio-net-pci` not being subtracted because it is the device the
pool replaces — with margin for devices netVM has not acquired, an empty slot
measured cheap, and growth beyond the pool costing a netVM restart. **netVM's
own ceiling has never been run.**

**One cost this ADR accepted was measured and its consequent did not hold**, and
acceptance does not quietly drop it. § *Costs accepted* predicts loss rather than
backpressure on a full receive buffer. The buffer filled and the loss did not
follow: zero frames lost in eighteen runs, the refusal arriving at the sender as
`EAGAIN`. **The bound stands as the revision note states it** — the sender in
that measurement was a program that counts its refusals, the real sender is
another QEMU, and **what QEMU-as-sender does on `EAGAIN` is unmeasured**. The
clause is therefore not withdrawn by acceptance; it is accepted with its
consequent known to be unmeasured for the sender that matters.

**What acceptance does NOT do.** It is a decision, and none of the following
exists yet:

- **no slot pool in netVM** — neither `net-sys.con` nor
  `katmate-sys-driver@.service` carries a `dgram` netdev, and netVM's internal
  segment is still the `tap-int0` device;
- **no `app-routed` template ships**, and the guard in `katmate-generate-env`
  **still refuses that profile**;
- **open problem #19 stays open.** Its requirement is unchanged: the guard and
  the `REQ_ENV` arm fall **together in one commit**, and acceptance does not
  substitute for that commit;
- the items under *Open in this ADR* that acceptance does not touch remain open —
  the slot-to-interface naming scheme, the socket path convention under
  `/run/katmate/link/`, whether a released slot is reused or quarantined, and
  what a slot's MAC derives from.

**Revision note (2026-08-28, § *Costs accepted* — the tap/vhost comparison is
judgement, not a sourced fact):** the fourth bullet of § *Costs accepted* reads,
in part:

> **A less-trodden path in the VMM.** `-netdev tap` with `vhost` is the most
> exercised network path in QEMU/KVM; `dgram` is not…

**The first clause is a superlative about someone else's code, and this project
gathered no source for it.** It appears in none of the three link reports, and
none was sought. The debt was flagged by the 2026-08-24 write pass — not by the
session that wrote the clause — and carried in `state.md` § *Next steps* as
something to be **sourced or restated as judgement at acceptance**. Acceptance
has arrived and no source was gathered, so it is **restated as judgement**:

**KatMate's judgement, held without a source, is that `tap` with `vhost` is the
better-exercised path and `dgram` the less-trodden one.** It is a belief this
project acts on, not a measured or cited fact, and nothing may be built on it
that could not be built on an opinion.

**What is checkable, and is a fact, is narrower and is about this tree:** every
`-netdev` in this repository is `tap` (`net-sys.con:26` and
`katmate-sys-driver@.service:137`, both netVM's internal segment), and
`app_web.con` carries no network device at all — so **our own gate history covers
`tap` and does not cover `dgram`**, on a code path guest bytes reach.
`docs/OBSERVATIONS.md` § 1 records exactly that, and records it **without** the
superlative, deliberately and from the day it was written. That file's own
conventions — *"Provenance is mandatory"*, *"No comparative judgement"* — are why
the clause could not stand there as fact, and a rule this project enforces in one
file cannot be suspended in another.

**The clause above is not edited.** This file is append-only in its body, the
original stands as written, and this note is what qualifies it. Gate M2 does not
close the question either: it measured saturation and not robustness.

**Revision note (2026-09-02, § *Open in this ADR, deliberately* — four items
closed by [ADR-035](DECISIONS.md#adr-035), one closed earlier, one still open):**
the section above leaves six items open on purpose. Their state is now:

- **the slot-to-interface naming scheme** — closed by ADR-035 §8. Slot `k` is
  named `kmkk` inside netVM, a view of the constant MAC produced by udev, and
  **never load-bearing**: NETCFG selects by MAC, nft references the segment or
  the peer `/28`, and if the rename never happens nothing programmatic changes.
- **`N`** — closed earlier, by the acceptance note above, at **16**.
- **the socket path convention under `/run/katmate/link/`** — closed by ADR-035
  §5: `/run/katmate/link/<netvm>/<kk>/{netvm,appvm,owner}`, one directory per
  slot under the netVM instance's directory, with the tree owned by whoever
  starts the netVM and never removed by a stop.
- **whether a released slot is reused immediately or quarantined** — closed by
  ADR-035 §6: **reused immediately**. Free is a state and not a timer, and the
  quarantine is that FREE is DOWN.
- **what a slot's MAC derives from** — closed by ADR-035 §2: **nothing**. It is
  the T4 constant `52:54:01:00:00:kk`. This ADR named
  [ADR-025](DECISIONS.md#adr-025)'s sha256 scheme as *"the obvious candidate"*
  and declined to assume it; ADR-035 rejects it, because uniqueness across
  sixteen would become probabilistic and the agent returns a first match.

**The sixth remains open, and accepting ADR-035 would not close it.** This ADR
states it as *"whether QEMU issues a failing `sendto` per frame or discards
without a syscall while a peer is absent"*; the M2 revision note above states it
as *"whether QEMU-as-sender retries or discards on `EAGAIN`"*. Both are about
what the sending VMM does when the socket will not take the frame, both are
unmeasured, and ADR-035 lists the second among the things it leaves open. This
note does not rule on whether the two formulations are one question.

**This note records a supersession and changes no sentence above it.** ADR-035
is PROPOSED and none of its six gates has been taken: what is closed above is
the design question in each case, never the mechanism.

---

## ADR-034 — Kernel provenance: a sidecar captured at build, carried into T2, checked at install

**Status:** Accepted (2026-09-01). The draft rested on two read-only
investigations of 2026-08-28 — the MINIS kernel tree and the Acer's — and on one
capture taken under it by hand on MINIS the same day, before the tool existed.
Acceptance rests on those plus four sessions between 2026-08-28 and 2026-09-01, a
pre-gate read, a first gate, a fix-and-regate and one closing gate, all run from
the Acer against MINIS; their reports are named in the acceptance note at the end
of this ADR, and the tool they gated is `tools/capture-kernel-provenance`,
committed with this change. This line read `DRAFT — proposed, not accepted` until
acceptance, and the sentence it carried — *"Nothing here may be cited as measured
beyond that capture's own readings"* — was true when written and is discharged by
that note. **Accepted is a decision and not an implementation:** the sidecar does
not yet travel with the kernel through the build hops, and no image metadata
records it.

**Depends on:** [ADR-005](DECISIONS.md#adr-005) (direct-kernel boot, no initrd),
[ADR-011](DECISIONS.md#adr-011) (build and update pipeline),
[ADR-030](DECISIONS.md#adr-030) (what a launcher reads),
[ADR-032](DECISIONS.md#adr-032) (where each tier lives, §5 payload and metadata
share a directory)

**Bears on:** open problem **#22** and its 2026-08-28 revision notes. This ADR
does not close #22 — it removes the cause of the next instance.

**Sources:** three sessions, all 2026-08-28 — the MINIS tree read, the Acer tree
read, and the capture on MINIS. **None produced a report file; all three
reported in chat**, so there is no 2026-08-28 session entry to look for and no
document to cite by section. Every figure below is therefore marked for what it
is: *chat-only* where it was read on MINIS and cannot be re-derived on the Acer,
unmarked where it was re-derived from the Acer tree or from this repository.
`state.md`'s three 2026-08-28 revision notes under #22 carry the same
distinction and the same readings.

**Numbering:** `ADR-034` was taken as the next free number on 2026-08-28 —
`ADR-033` is the highest written. **`ADR-031` is reserved, not free:** it is
held for the GPL-3.0 licence declaration covering the CYBRland-derived
`desktop/` subtree, decision taken and document not written, per `state.md`
§ *Next steps* and `docs/HOST-CONFIG.md:225`. The gap in the sequence is a
record, not an opening.

**Context:**

The microVM kernel is built **outside the pipeline**, by hand, in a source tree
on each machine, and enters as a file. `Makefile:44–47` copies it from
`KERNEL_SRC_DIR` into `$(OUT)`; `build/foundation.sh:268–274` installs it from
there into `$KATMATE_KERNELS_DIR`. Three copies, no record taken at any hop.
This ADR does not change where the kernel is built. It changes what is written
down when it enters.

Two read-only investigations established what the current arrangement costs:

- The two machines hold **different kernels under one filename**. MINIS:
  `6.12.87-dirty (host@archlinux)`, 2026-07-01 *(chat-only)*. Acer: `6.12.87
  (winterbox@cyberdome)`, 2026-05-13. The name asserts an identity that does
  not hold.
- **`-dirty` was not a patch** *(chat-only — MINIS)*. Ten tracked files deleted,
  371 deletions and **zero added or modified lines**, none of them compiling
  into an x86 kernel. Establishing that took a session, because
  `scripts/setlocalversion` records **one bit** and no manifest of what the dirt
  was.
- **On MINIS the provenance chain exists** *(chat-only)*: the tree's
  `include/config/auto.conf` is symbol-for-symbol identical to the archived
  config. **On the Acer it is broken**: `auto.conf` was overwritten 47 days
  after the image was linked, and nothing else in that tree ties the archived
  config to that build.

The last point is the finding this ADR is written around:

> **The evidence of provenance lives in the build tree, and the next reconfigure
> deletes it silently.** It survived on MINIS by accident. Nothing in the
> distributed artefact carries it, so the tree is the only witness — and any
> `make menuconfig` overwrites the witness.

Two things are being confused when this is called one problem, and separating
them decides where the work goes:

- **Identity** — *what is this file?* `sha256` of image and config, plus the
  banner. Needs only the files; capturable at any time, by anyone.
- **Pairing** — *which config produced this image?* Needs `auto.conf` from that
  tree in its post-build state. Perishable, and capturable **only in the tree,
  at build time**.

`Makefile:44` sees `KERNEL_SRC_DIR` — an image and a config, no tree. **Pairing
cannot be captured at the pipeline boundary.** The pipeline can only carry what
was captured and verify identity.

**Decision:**

**A kernel entering the pipeline is accompanied by a provenance sidecar,
written in the build tree by a tool in this repository, at the time of the
build.**

Beside `vmlinuz-katmate-microvm-<arch>-<ver>`, a file
`vmlinuz-katmate-microvm-<arch>-<ver>.provenance`, flat `KEY=value` — the
`foundation.meta` shape, since [ADR-030](DECISIONS.md#adr-030) §1, on T2, states
that no second format is introduced — but **read with a parser and never with
`source`** (see *Deliberately not sourceable* below):

```
KATMATE_PROVENANCE_VERSION=1
KERNEL_SHA256=      the image
CONFIG_SHA256=      the archived config
AUTOCONF_MATCH=     yes | no        symbol-for-symbol against auto.conf at capture
SRC_COMMIT=         git rev-parse HEAD
SRC_TAG=            git describe --tags
SRC_DIRTY_PATHS=    git diff-index --name-only HEAD, or empty
BANNER=             the version string read out of the image
CAPTURED=           ISO-8601 UTC
```

Sub-decisions, each with the reason it went that way:

- **`SRC_DIRTY_PATHS` is the load-bearing field.** `setlocalversion` writes one
  bit; this writes the manifest. Had it existed, the MINIS `-dirty` question
  would have been answered by reading a file instead of by a session, and the
  Acer's would still be answerable. Captured at build it costs nothing.
- **`AUTOCONF_MATCH` states what was checked, not what is true.** It records
  that the archived config was compared against the tree's own witness at
  capture time. A capture too late to find `auto.conf` writes `no` — which is
  information, not failure.
- **The tool lives in `tools/`, in this repository, and is run by hand** in the
  kernel tree after a build. The format is then defined by the repository rather
  than by habit, and the tool is reviewable, versioned and diffable like
  everything else. The kernel build itself stays outside the pipeline,
  unchanged.
- **The sidecar travels beside the kernel**, into `$(OUT)` and then into
  `$KATMATE_KERNELS_DIR`, on `netvm.meta`'s precedent: payload and its metadata
  share an author, a lifecycle and an upgrade owner
  ([ADR-032](DECISIONS.md#adr-032) §5), so they share a directory.
  Copy-then-rename with a dotted temporary name, as `foundation.sh` step 11 and
  `netvm.sh` step 11 already do.
- **Deliberately not sourceable, and this is a departure that must be stated.**
  `foundation.meta`'s defining property, in its own words at
  `build/foundation.sh:226–227`, is *flat KEY=value, POSIX-sourceable — the
  preflight reads it with no parser*. This file keeps the shape and gives that
  property up. `BANNER` carries spaces and unescaped parentheses; the first
  capture's value is `6.12.87-dirty (host@archlinux) #1 SMP PREEMPT_DYNAMIC Wed
  Jul 1 08:10:48 CEST 2026`, and `. file` fails on it. `SRC_DIRTY_PATHS` is a
  path list that will be longer in other cases. The alternative — inventing a
  quoting convention `foundation.meta` does not use — would make one format look
  like two, and would put shell syntax around data that is not shell. **Every
  reader of this file parses `^KEY=` and takes the rest of the line verbatim**,
  as `build/app-layer.sh`'s `meta_get()` already does with `sed` for a file that
  *is* sourceable, and for the same stated reason: a build script should not
  execute a data file to read it. The file carries no shell metacharacters that
  a `sed` extraction cares about, and any consumer that needs one field gets one
  line.
- **The hash does not go into `app-<type>.meta`.** `build/app-layer.sh` already
  refuses to copy the waypipe tag into every app-layer meta — *provenance needs
  to identify the generation, not restate its contents*. One kernel, one record,
  beside the kernel.
- **Absent is not refused.** A kernel with no sidecar still builds; the pipeline
  records `KERNEL_PROVENANCE=absent` in `foundation.meta`. Both existing kernels
  have no sidecar, and the Acer's pairing is unrecoverable — refusing them would
  stop legitimate work to punish a gap this ADR exists to close going forward.
  This is the project's own *absent, not disabled* shape: the meta states
  honestly that provenance was not recorded, rather than implying it was.
- **`-dirty` is recorded, never refused.** The investigation showed a `-dirty`
  kernel whose dirt was ten deletions irrelevant to x86, and a clean kernel
  whose pairing is lost. **Cleanliness is not provenance.** A refusal keyed on
  the banner would have blocked the better-documented of the two kernels and
  passed the worse.
- **Verification happens at install, not at launch.** `foundation.sh` step 11
  compares the sidecar's `KERNEL_SHA256` against the file it is installing and
  refuses on mismatch. `katmate-check-image` is unchanged: its header states
  *EXISTENCE ONLY … the cheapest gate in the `ExecStartPre=` chain*
  (`host/usr/lib/katmate/katmate-check-image:8–9`), and hashing 14 MB at every
  start would break that contract. **Launch-time integrity is measured boot and
  TPM sealing** — already in the backlog — and a weaker imitation of it inside a
  preflight would be worse than none, because it would read as coverage.

### The first capture, and why the two machines are treated differently

**MINIS is captured; the Acer is deliberately left without a sidecar.** The
asymmetry is the decision, not an inconsistency, and it follows from what each
tree can still prove.

MINIS still holds the witness. *(This paragraph's readings are chat-only —
taken on MINIS 2026-08-28, no report file, and not re-derivable on the Acer.)*
On 2026-08-28 the tree's `arch/x86/boot/bzImage` was re-confirmed byte-identical
to the archived vmlinuz (three times, the last immediately before the write, so
the file cannot outlive the identity it asserts), and `include/config/auto.conf`
was compared against the archived config afresh in that session — 1718 symbol
lines against 1718, **empty diff**, nothing carried forward from the earlier
read. Capture there is not reconstruction: it writes down something that exists
today and that the next `make menuconfig` in that tree destroys. The sidecar was
written to
`~/katmate-kernels/vmlinuz-katmate-microvm-amd64-6.12.87.provenance`,
`AUTOCONF_MATCH=yes`, `SRC_DIRTY_PATHS` carrying the ten deleted paths that
`setlocalversion`'s one bit does not name.

The Acer has no witness. *(Re-derived on the Acer 2026-08-28.)* `auto.conf` was
overwritten 47 days after that image was linked. A capture there would fill
`SRC_COMMIT` and `SRC_TAG` from **today's** tree and present them in the same
fields that are true on MINIS — a form that reads as equivalent and is not. **An
absent record is more honest than a filled-in one**, so the Acer's kernel gets
no sidecar and any build there records `KERNEL_PROVENANCE=absent`.

The general rule this fixes: **capture is only meaningful while the tree that
built the image still holds `auto.conf` from that build.** After that, the
correct action is to record nothing and say so.

**Consequences:**

*Easier*

- The `-dirty` question becomes a file read rather than a session.
- Two machines' kernels become comparable by a fixed record rather than by an
  investigation, and the filename stops being the only identity.
- `foundation.meta` states plainly whether provenance was recorded, so its
  absence is visible rather than assumed.

*Harder*

- **A manual step is added to a manual build**, and a forgotten capture yields
  `KERNEL_PROVENANCE=absent` silently — visible in the meta, but nothing forces
  it. The alternative is bringing the kernel build into the pipeline, which this
  ADR deliberately does not do.
- The sidecar is **unsigned and sits beside the file it describes**. It defends
  against drift, mis-identification and forgetting; it does not defend against
  an adversary who can write to that directory. Stated so it is not mistaken
  for integrity.
- A second file now travels with the kernel through three hops, and each hop
  must carry it or the record is lost where it is least noticed.

*To revisit*

- If the kernel build ever enters the pipeline, capture becomes automatic and
  `absent` should become refusable.
- netVM is **out of scope**: its kernel comes from a signed Debian package
  inside the guest, so its provenance is better than the AppVM kernel's and
  merely unrecorded — `netvm.meta` notes the version and nothing else. Recording
  it is a separate and smaller question.

**Open in this draft, deliberately:** the tool's name and invocation; whether
`SRC_DIRTY_PATHS` records paths only or also a hash of the diff, which would
distinguish ten deletions from ten edits without carrying the edits; whether
`katmate-update.sh` re-verifies the sidecar on a release bump; and whether the
existing MINIS sidecar — written by hand before the tool exists, and carrying
`CAPTURED_BY=manual capture, tools/ implementation pending` — is re-taken by the
tool once it lands, or left standing as the record it already is.

**Acceptance note (2026-09-01) — what acceptance rests on, what the schema
became, and what it does not yet do:** the status line above was changed from
`DRAFT` to `Accepted` in place, which is this file's practice for that one line
and only that line, on ADR-033's precedent (2026-08-28) and ADR-010/ADR-011's
before it. The body below is untouched and stays append-only.

**What acceptance rests on — four sessions, and what each discharged.**

- **The pre-gate read** (2026-09-01, MINIS, `~/adr034-pregate-report.md`) — that the
  witness still exists. The build tree's generated config survived, unchanged in
  the 65 days since the build; the tree image and the archived image are the same
  bytes; and the archived config pairs to the tree symbol-for-symbol. It also
  established the banner extraction method, which could not be settled by reading
  and had to be run against a real image.
- **The first gate** (2026-09-01, MINIS, `~/adr034-tool-gate-report.md`) — which the
  tool **failed**, and the failure is why this note can be written. See *the
  defect* below.
- **The fix and the re-gate** (2026-09-01, Acer and MINIS, `~/adr034-gate2-report.md`) — the two
  readings the first gate could not take, plus the measured before-and-after of
  the defect.
- **One closing gate** (2026-09-01, MINIS, `~/adr034-g8-report.md`) — the last claim in
  the tool that stood on argument rather than measurement, closed in both
  directions against a control.

### A. The four items left open in the draft, and what they resolved to

**1. The tool's name and invocation.** `tools/capture-kernel-provenance`, bash,
**standalone** — it does not source the build pipeline's configuration, because
it runs inside a kernel source tree where that configuration's path computation
and storage names have no meaning. The build tree is the **working directory**
and is not an argument. The sidecar path is **derived** from the image argument
and never given, so the binding between a record and the payload it describes is
structural rather than a parameter that can be passed wrong. It refuses to
overwrite an existing sidecar without `--force`.

**2. Whether `SRC_DIRTY_PATHS` also carries a hash of the diff.** It does not.
The path list stays, and a second field `SRC_DIRTY_STAT` is added carrying the
`--stat` summary line. **The hash was rejected on two grounds.** It distinguishes
two different dirty states from each other but says nothing about the nature of
either — it cannot tell ten deletions from ten edits, which is the question that
cost a session. And `git diff` output is not stable across diff algorithm,
rename detection and context settings, so the hash would depend on the machine
that took it; an identifier that looks stable and is not is worse than none. The
summary line answers *was the dirt a patch?* by reading. Its first measured value
is `10 files changed, 371 deletions(-)`.

**3. Whether the release orchestrator re-verifies the sidecar on a version
bump.** It checks **presence, not content**. A second full verification would be
a second implementation of one truth with nothing holding the two in step, which
is this project's characteristic failure class. Presence is a different
assertion, taken early, and it foretells `KERNEL_PROVENANCE=absent` at the point
where a release is being assembled rather than leaving a reader to discover it
afterwards.

**4. Whether the hand-captured sidecar is re-taken by the tool or left
standing.** It is **replaced by the tool's output**, on the condition that the
tool first reproduce it. **The condition was met** — § D — and the hand-captured
file is quoted in full at § F before being replaced, because until this note it
survived verbatim only in reports that live outside this repository.

### B. What changed in the schema, and why the version did not

- **`IMAGE_MATCH` is added.** The first capture is recorded as having verified
  the tree image against the archived image three times and having written none
  of it down. The field exists so that the check is **recorded** and not merely
  performed.
- **`SRC_DIRTY_STAT` is added**, per A.2.
- **`CAPTURED_BY` is promoted from an ad-hoc field to schema.** The first capture
  invented it and was right to: who wrote a record is part of the record. It
  carries the tool's name and the tool's own hash, so the file says which version
  of the tool wrote it without the tool needing to know where this repository
  lies — which, from inside a kernel tree, it cannot.
- **`SRC_TAG` may be empty, and a failing `git describe --tags` is not a
  refusal.** `SRC_COMMIT` is the tree's **identity** and names the exact state
  that was built; `SRC_TAG` is **legibility**. A provenance tool that refused to
  record anything because a tree carries no reachable tag would be imposing a
  kernel-build policy from the wrong place. A failing `git rev-parse HEAD`
  remains a refusal.
- **The schema is now twelve keys**, and `KATMATE_PROVENANCE_VERSION` stays `1`:
  nothing has ever read a sidecar, so there is no reader to break.
- **An empty value is unambiguous.** The tool writes twelve keys or writes
  nothing — there is no partial record — so an empty field means *established and
  empty*, never *not recorded*.

### C. `AUTOCONF_MATCH` — the comparison is specified here, not left to the tool

This is the substantive addition, and the reason it belongs in the ADR rather
than only in code is that **the schema line as originally written was
under-specified, and a tool implementing it literally would have contradicted a
measurement this project had already recorded twice.**

**The two files are compared as mappings from symbol to value, not as text.**

- **Order is not meaningful.** The two disagree on it: **3434** differing lines
  in a file-order diff of two files carrying the same **1718** symbols, because
  the generated file is in the build system's order and the archived config in
  menu order. Both orders are stable properties of their formats.
- **Quoting is not meaningful.** The two disagree on it: **21** symbols, **86**
  diff lines, every one the same shape, and **no symbol has a different value on
  the two sides**. The quotes are the config format's syntax, not part of any
  value.

**Bound: the comparison covers set symbols only** — 1718 on each side. The
archived config also carries **2601** *"is not set"* comment lines that the
generated file does not have by construction. This is not a gap: an unset symbol
carries no information beyond its absence, and comparing the two complete
normalised streams catches a symbol present on one side and absent on the other
**in either direction**. That was an argument in the tool's own header, and it is
now measured — § D.

### D. The gate, and what it established

**Against the hand-captured record** (MINIS, 2026-09-01). The standing record has **10** keys and the
produced one **12**. **Eight pair identically.** `CAPTURED` and `CAPTURED_BY`
differ **by construction** — the captures are four days apart, and the field
moved from free text to name-and-hash. **Two are new**, `IMAGE_MATCH` and
`SRC_DIRTY_STAT`.

**`BANNER` was compared byte for byte**, not by eye: `cmp` exit **0**, **84**
bytes on each side, identical hashes, with the date's double space present in the
produced value.

**The banner extraction.** A text search over the compressed image finds nothing
and fails **silently**; the method is the boot protocol setup header, guarded by
its magic so that a file which is not such an image is refused rather than read
at meaningless offsets. The version field read the **same value on two different
images** — the MINIS 6.12.87 build and the Acer's — built by different people on
different machines on different dates.

**A defect the gate found, and that a single run would have hidden.** An
early-exiting pipeline consumer raced its producer; when it won, the tool aborted
**with no diagnostic at all**. It was reproduced at **24.5%** — 49 of 200 runs, on
**MINIS** — and at **2.5%** — 1 of 40, on the **Acer**. The two 200-run series
are both MINIS: the unfixed tool and the fixed one, run back to back against the
same inputs. At 2.5% a single smoke test had roughly a **97.5%** chance of
missing it, and did. Fixed by reading to end of input: **200 of 200** runs clean
afterwards, with the extracted value **byte-identical before and after** (`cmp`
exit 0 between the pre-fix and post-fix values), so the repair changed the
failure rate and not the measurement.

**Refutation, not only confirmation.** A fixture that must be accepted proves
half of a comparison.

- A config differing in **exactly one** symbol out of 1718 produces `no`, with
  **exactly two** fields moving: the match field and the hash of the file that
  changed.
- The symbol-set claim was measured **in both directions** — one symbol removed
  from the generated file, then the same symbol removed from the archived config
  — each against a **control** built from the same bytes as the real pair, which
  yields `yes`. Counts: 1718/1718 → `yes`; 1717/1718 → `no`; 1718/1717 → `no`.
  All three on MINIS, 2026-09-01.

### E. What acceptance does not claim

- **The self-hash refusal is unexercised.** Forcing it is contrived and would
  prove less than it costs.
- **Multi-symbol asymmetry is untested.** Only one symbol in each direction was
  measured.
- **A missing symbol whose value is quoted is untested.** The normalisation
  strips quotes before comparing, so it is the same code path — but that is an
  argument, and it is recorded here as one.
- **The compressed-image fallback is deliberately not implemented.** It has never
  been exercised, and an untested fallback path in a provenance tool is worse
  than its absence, because it reads as coverage.

### F. The hand-captured record, quoted before it is replaced

This is the reference fixture. It was captured **by hand, before the tool
existed**, and it is the only thing the tool could be gated against; § A.4
replaces it with the tool's output. It is reproduced here in full so the record
is in this repository and not only in a report outside it.

```
KATMATE_PROVENANCE_VERSION=1
KERNEL_SHA256=b34026dd2b95cd364235ff90eb0be43f405927ab9b994f174681b9367e48c3ce
CONFIG_SHA256=7720cf221b77e61995ae502bcd59b07f066d42fab5d14edae8af2b212bd95281
AUTOCONF_MATCH=yes
SRC_COMMIT=8bf2f55ef536982e44802d99340119dac6f50636
SRC_TAG=v6.12.87
SRC_DIRTY_PATHS=arch/mips/generic/vmlinux.its.S arch/mips/mobileye/vmlinux.its.S arch/nios2/boot/compressed/vmlinux.scr arch/openrisc/kernel/vmlinux.h arch/parisc/boot/compressed/vmlinux.scr arch/sh/boot/compressed/vmlinux.scr arch/sh/boot/romimage/vmlinux.scr tools/perf/util/bpf_skel/vmlinux/.gitignore tools/perf/util/bpf_skel/vmlinux/vmlinux.h tools/testing/selftests/bpf/prog_tests/vmlinux.c
BANNER=6.12.87-dirty (host@archlinux) #1 SMP PREEMPT_DYNAMIC Wed Jul  1 08:10:48 CEST 2026
CAPTURED=2026-08-28T06:58:54Z
CAPTURED_BY=manual capture, tools/ implementation pending
```

Ten keys. `CAPTURED_BY` here is the ad-hoc field that § B promotes to schema; its
free-text value is what that promotion replaces.

### G. What acceptance does NOT do — the implementation is the next commit

Acceptance is a decision. None of the following exists yet, and this note does
not claim it:

- **The sidecar does not travel.** It is written in the kernel build tree and
  stays there; neither build hop copies it, so a record written today is lost at
  the point it is least noticed.
- **No image metadata records provenance.** The `KERNEL_PROVENANCE` field named
  in the decision above is not written by any build.

Two rulings belong to that work and are recorded here so they are not
re-derived:

- **The check goes in the build's preflight**, beside the existing check for the
  kernel file, so a mismatch fails **before** the expensive build rather than
  after the image is frozen and its metadata already written.
- **`KERNEL_PROVENANCE` carries `recorded` or `absent`, not a hash.** A hash
  there would be a second copy of a value that already lives in the sidecar —
  the same objection the app-layer build already makes about restating a version
  it does not own.

---

## ADR-035 — The netVM link pool: a slot is an index, and every face of a slot is a function of that index

**Status:** PROPOSED (2026-09-02). Acceptance is gated on the measurements in
§ *Gates*, none of which has been taken. **Proposed is a decision and not an
implementation:** no pool exists in netVM, no `app-routed` template ships, and
every claim below about the agent's code is a *reading of source* from the
2026-09-02 read pass (`~/adr035-readpass-report.md`, not in the repository),
not an observation of a running system.

**Depends on:** [ADR-023](DECISIONS.md#adr-023) (NETCFG describes a link, never
an AppVM), [ADR-025](DECISIONS.md#adr-025) (the NETCFG payload; `match_mac`
selects the interface; `local_addr` is a v1 constant), [ADR-030](DECISIONS.md#adr-030)
§3 (what crosses the boundary), [ADR-032](DECISIONS.md#adr-032) (`/run/katmate/`
is derived state, and presence of a file is not authority for liveness),
[ADR-033](DECISIONS.md#adr-033) (a link is a pair of AF_UNIX datagram sockets;
netVM starts with a static pool; `N` = 16).

**Closes:** the items ADR-033 left open *deliberately* — the slot-to-interface
naming scheme, the socket path convention under `/run/katmate/link/`, whether a
released slot is reused or quarantined, and what a slot's MAC derives from. It
also settles one item ADR-033 did not name and which the read pass exposed:
what `local_addr` means when there are sixteen interfaces and the validator
permits one value.

**Leaves open, and says so:** whether QEMU-as-sender retries or discards on
`EAGAIN` (ADR-033's own open item, still unmeasured), and the mechanism by which
the *AppVM end* of a link learns its addresses — see § *Dependencies surfaced*.

**Context:**

ADR-033 fixed the mechanism: sixteen `virtio-net` devices in netVM, each with a
`dgram` backend on a fixed socket path, present from netVM's first instruction,
peer or no peer. It left the pool's *identity* open on purpose, and it left one
sentence as a warning rather than a design: *"the netVM-side slot-to-interface
mapping must be stable and legible, or NETCFG programs the right `/32` on the
wrong interface."*

The read pass narrowed that sentence to a fact. ADR-025 resolved its mechanism
to Path B: `handle_netcfg` is a wire adapter over `netcfg::handle`, and the
interface is found by `netlink::ifindex_by_mac` — a `read_dir` over
`/sys/class/net` comparing each `address`, **returning the first match**
(`netlink.rs:493`), rejecting on none (`:496`), **not detecting more than one**,
and imposing no order — nothing in the file sorts. Interface *names* appear
nowhere in the selection. So the mapping question was never about names: it is
**which MAC the netVM side of slot `k` carries, and who knows it when NETCFG is
called.** With one internal interface the first-match rule was invisible; with
sixteen, MAC uniqueness across the pool is a correctness precondition that
nothing currently enforces, and the tie-break is directory order.

The read pass exposed a second constraint ADR-033 did not name. ADR-025's table
requires `local_addr == INTERNAL_LOCAL` (`10.100.1.1`), validated totally at
decode, and the ADR reserves loosening that constant for the proxy case. Sixteen
netVM-side interfaces means sixteen ADDs, each asked to carry the **same** local
address. That is either a design or an accident, and this ADR makes it a design.

Two things the read pass established that this ADR stands on, both readings of
the tree: the netVM image bakes exactly one `[Match]`, in `20-uplink.network`,
carrying only `MACAddress=` — so ADR-025's load-bearing corollary (*no catch-all
match may ever be baked*) holds today and the sixteen slot interfaces will be
networkd-unmanaged; and the guest-side `netvm-agent` unit baked by
`build/netvm.sh` still grants `ReadWritePaths=/etc/systemd/network` from the
dead Path A (open problem #27), which this pool's commit removes because it
rewrites that unit anyway.

**Decision:**

**1. A slot is an index `k ∈ 0…15`, written as two hex digits `kk`, and every
face of a slot is a function of `k` and nothing else.** There is one source of
truth for a slot's identity — its position in the pool — and MAC, path, peer
address and name are all *views* of it. None is derived from another, so none
can drift from another. This is the property ADR-030 §3 was protecting when it
forbade a MAC that byte-encodes an address: the failure it names is a MAC that
*carries* the address and preserves it when the address changes. Here nothing
carries anything; the index is the carrier, and the index does not change.

**2. The netVM side of slot `k` carries MAC `52:54:01:00:00:kk` — a pool constant
written literally in T4, never projected.** The third octet `01` partitions
slot MACs from identity MACs, which stay `52:54:00` + three bytes of
`sha256(<instance>)` per ADR-025: a slot MAC and an identity MAC cannot collide
by construction, and two slot MACs in one pool cannot collide by construction.
The two middle octets are **reserved zero**; they will never carry address bytes.
The first octet is unchanged, so the address stays unicast and locally
administered as `match_mac` requires. The AppVM side of the link keeps its
instance-derived identity MAC; this ADR does not touch it.

This narrows, and does not break, ADR-025's *"MACs are derived, never authored"*:
that rule governs **identity** — a MAC that names an instance — and a slot is not
an instance. A slot MAC is a protocol constant of the pool, in the same class as
a port number, and it lives where protocol constants live: in T4, versioned and
reviewed, not in T1 where an operator could author it and not in T3 where it
would have to be regenerated. The host needs no computation and no state to know
slot `k`'s MAC. `ip -br link` inside netVM shows sixteen addresses whose last
octet *is* the slot. That is the legibility ADR-033 asked for.

**3. Every active slot carries `10.100.1.1/32` — one gateway identity on every
link, and ADR-025's constant stands unchanged.** Linux permits one address on
many interfaces when each is a `/32` on its own point-to-point link with its own
peer route; delivery to a local address does not depend on which interface holds
it, and source selection for `netVM → peer` follows the peer route to slot `k`
and picks the address on slot `k`. Nothing in the validator moves. What changes
is that the constant is now load-bearing in a way it was not: every AppVM image
may carry the same gateway, and no per-instance network fact ever reaches an
AppVM's configuration. **This is a claim about the kernel and is gated (G2)**,
including the half that a confirmation cannot show — that a frame arriving on
slot `b` claiming slot `a`'s peer as its source is not treated as slot `a`.

**4. The peer address of slot `k` is `10.100.1.(16 + k)` — the pool's peer block
is `10.100.1.16/28`.** Allocation becomes derivation: the launch daemon holds no
free list and no lease, and *"the launch daemon allocates `/32`s"*
(`ARCHITECTURE.md`) is satisfied by a function rather than a table. The `/28`
alignment gives nft a single prefix for *"every pool peer"* if it ever needs one
narrower than the segment; `.2`–`.15` remain free for links that are not pool
slots (a proxy netVM's uplink, a future sysVM edge). A second pool, if one ever
exists, takes the next `/28`. Relation to ADR-030 §3 is stated in §1: the MAC's
last octet is `kk` and the address's is `16 + k`, both views of `k`, and the MAC
contains no octet of the address.

**5. Paths: `/run/katmate/link/<netvm>/<kk>/{netvm,appvm,owner}`.** One
directory per slot under the netVM instance's directory.

- `netvm` — the socket the netVM's QEMU binds; literal in the netVM template as
  `/run/katmate/link/%i/kk/netvm`, sixteen times. Zero values cross.
- `appvm` — the socket the AppVM's QEMU binds; in the AppVM template as
  `/run/katmate/link/${KM_NETVM}/${KM_SLOT}/appvm`, where `KM_NETVM` is the
  projection of the T1 `netvm` declaration ADR-032 §3 already defines, and
  `KM_SLOT` is the two hex digits allocated at launch. **Identity crosses, not a
  path:** the path's structure stays in T4, and both scalars have a hard type
  a validator can refuse.
- `owner` — written by the launch daemon at assignment, removed at release:
  the AppVM instance name and the `link_id` used for that assignment. **Absence
  is freedom.** `ls /run/katmate/link/*/*/owner` is the pool's occupancy, and
  `cat` on one is the answer to *"who holds slot `kk` and under which link"*.

**The directory tree belongs to whoever starts the netVM and is never removed
by a stop.** The AppVM's socket lives in the netVM's tree because the netVM's
QEMU must name that path at *its* start, before any AppVM exists — ADR-033's
measurement that `remote.path` is resolved per send and never stat-ed makes
that safe. It also means a `RuntimeDirectory=` that removes on stop would
unlink a live AppVM's socket the moment netVM restarted, and the netVM's
re-issued sends would hit `ENOENT` while the AppVM's still arrived. So: the tree
is created before the netVM's QEMU binds, and it persists across that unit's
stops and restarts. The candidate is `RuntimeDirectory=` naming the sixteen slot
directories with `RuntimeDirectoryPreserve=yes`; the fallback is a T4 helper in
`ExecStartPre=`. **Which one is a mechanism claim about systemd and is gated
(G5)**; the ownership rule is the decision.

`ExecStopPost=` on the netVM unlinks the sixteen `netvm` files — sixteen literal
paths, no shell, no glob; `ExecStopPost=` on the AppVM unlinks its one `appvm`
file. **Open problem #23 closes here**, and ADR-032's rule is restated for this
tree: a socket file's presence is not authority for liveness — systemd is.

Bound: `sun_path` is 108 bytes. With this layout the netVM instance name has
roughly seventy characters before `bind()` fails at start, silently to the
guest. The identifier validator either already bounds names tighter than that
or must; the read pass did not ask, and the write pass will (§ *Questions*).

**6. A released slot is reused immediately. "Free" is a state, not a timer.**

A slot is in exactly one of three states, and each is legible from the tree
and from inside netVM:

| State | `owner` | netVM interface | `appvm` socket |
|---|---|---|---|
| FREE | absent | DOWN, no address, no peer route, no neighbour, no record | absent |
| ASSIGNED | present | UP, `10.100.1.1/32`, `/32` route to peer `k`, record present | bound by the AppVM's QEMU |
| RELEASING | present | being returned to FREE by NETCFG REMOVE | being unlinked |

**REMOVE returns the interface to FREE, and FREE is DOWN.** That is the
quarantine: a down interface receives nothing, so a late or hostile frame into a
released slot is dropped by the kernel before anything reads it. What REMOVE
must therefore do — and what ADD's converse must have done — is enumerable:
delete the peer route, delete the address on that interface (not on others),
delete the neighbour entry for peer `k`, **flush conntrack entries whose source
or reply-destination is peer `k`**, clear `IFF_UP`, delete the record. Each item
has a deletion primitive. The alternative — a time-based quarantine — is a guess
about how long *unenumerated* state lives, and the one piece of state that would
justify it, a NAT-tracked TCP flow, has a default established timeout measured
in days: no quarantine a user would accept covers it, and the flush covers it
exactly. The conntrack flush is the one new capability the pool asks of the
agent, and it is gated with its own refusal fixture (G4). Whether today's REMOVE
clears `IFF_UP` at all is not known from the read pass and is a question, not an
assumption.

**Convergence, restated for the pool.** An ADD naming a `match_mac` that already
carries a record under a different `link_id` **supersedes** that record — an
interface has one link, and the newer assignment is the truth. A REMOVE naming
an unknown `link_id` is absorbed, as the read pass finds it is today
(`netcfg.rs:401`). Together these make a late REMOVE from a previous tenant
harmless to the current one, without encoding generations anywhere: `link_id`
remains ADR-025's opaque host-allocated counter, and the pool adds no structure
to it. The `owner` file records which `link_id` the current assignment used, so
the launch daemon issues the right REMOVE without a lookup table.

**7. `ifindex_by_mac` must count.** Two or more interfaces carrying the requested
address is a **Rejected**, not a first-match. This is the scheme-independent
guard against programming the wrong interface, it needs no knowledge of §2's
layout, it costs one comparison, and it is the correction of the exact code
path the read pass named. It lands in the pool's agent commit and is gated with
a refusal fixture (G3): a confirmation with sixteen distinct MACs proves half
the comparison; the other half is two interfaces with one MAC and a refusal.

**8. Inside netVM, slot `k` is named `kmkk`.** The name is a view of the MAC —
`52:54:01:00:00:kk` → `kmkk` — produced by udev on the constant, so the rule is
instance-independent and bakes into the image without per-instance content.
**The name is never load-bearing.** NETCFG selects by MAC (ADR-025), nft
references the segment or the `/28` and never an interface name
(`ARCHITECTURE.md` § *Networking*, unchanged), and the invariant that netVM
interface names are not normative stands: if the rename does not happen,
nothing programmatic changes, and an operator reads the last octet instead.
Whether the rename is a udev rule or sixteen exact-match `.link` files is the
implementation's; neither is a `.network` match, so ADR-025's corollary is not
touched. Gated (G1).

**9. ADR-030 §3 is amended, not overturned.** §3 grounds *"network argv is
thereby static in the template"* in a netns and a tap that ADR-033 abolished;
the grounding is gone and the conclusion is **restored on the new model**:
under this pool the netVM template's network argv is sixteen literal
`-netdev dgram`/`-device virtio-net-pci` pairs with `%i` paths and constant
MACs, and **no network scalar crosses** — `KM_MAC_INT` retires with `tap-int0`.
The AppVM template gains two typed scalars, `KM_NETVM` and `KM_SLOT`, beside its
own derived identity MAC. §3's principle — a fixed, validated key set, each key
at a fixed position, `${}` so a value can never become an argument — is what
this ADR builds on, and §3's arithmetic (*"exactly two values"*) was already
overtaken by the memory, kernel and root-device keys the shipped template
interpolates; this ADR records that as well rather than leaving §3 to be read
literally.

**Alternatives rejected:**

- **A local address per slot.** Loosens a constant ADR-025 reserved for the
  proxy case, and couples every AppVM's gateway to the slot it happened to
  draw — the one per-instance network fact this design keeps out of AppVMs.
- **Hash-derived slot MACs** (`sha256(<netvm>/kk)`). Uniqueness across sixteen
  becomes probabilistic, and under a first-match agent a collision is the
  silent-wrong-object failure this project has already paid for three times.
  It would also project sixteen keys nothing needs; no consumer distinguishes
  two netVMs' slot MACs, since they are never on one wire.
- **netVM identity in the middle octets.** Same absence of a consumer; the
  octets are reserved instead.
- **Time-based quarantine.** A guess about unenumerated state. The state is
  enumerable (§6) and each item deletes.
- **Slot index encoded in `link_id`, checked by the agent.** Couples NETCFG's
  wire validation to a MAC layout, and would have to be conditional for links
  that are not slots. Duplicate detection (§7) is the guard and is layout-free.
- **A NETCFG v2 carrying the slot.** A wire change for a value the MAC already
  carries.
- **Interface names as selectors.** The invariant, and the read pass: names
  appear nowhere in the selection and have moved three times.
- **`RuntimeDirectory=` on the link tree without preservation.** Unlinks the
  AppVM's socket on netVM restart (§5).
- **A per-link bridge or shared segment.** Rejected by ADR-033 on the model,
  not revisited.

**Consequences:**

*Easier*

- The launch daemon's slot work is: pick the lowest `kk` with no `owner`, write
  `owner`, issue ADD, start the AppVM unit; on stop, issue REMOVE, unlink,
  remove `owner`. No allocator state beyond the tree, and ADR-025's
  *"device_add before NETCFG"* ordering disappears because the device exists
  from netVM's boot. Re-issue after netVM restart is a walk over `owner` files.
- Slot allocation stays *"CID allocation's mechanism on a second namespace"*
  (ADR-033), and reconcile (ADR-017) checks `owner` against running units.
- The netVM template's network section carries no interpolation; the projection
  drops `KM_MAC_INT`; `katmate-generate-env` emits `KM_NETVM` and `KM_SLOT` for
  `app-routed`, which is the `REQ_ENV` arm open problem #19 says must land with
  the guard's removal, in one commit.
- ADR-015's `web`-without-network warning on `app_web`, and
  `validate-properties.fish --strict` over the real T1 set, become reachable
  (ADR-033 § *Easier*, unchanged).
- Open problems #23 and #27 close in the pool's commits; #27's unit rewrite is
  where the stale grant goes.

*Harder*

- **The AppVM end has no addressing mechanism today** — see § *Dependencies
  surfaced*. The pool is measurable without it; the product is not shippable
  without it.
- The agent gains two operations (neighbour delete, conntrack flush), one check
  (§7), and a DOWN on REMOVE if it does not already do that. Each is gated.
- netVM's root bus carries twenty devices (`virtio-rng`, `vhost-vsock`,
  `virtio-blk`, `vfio-pci`, sixteen `virtio-net-pci`) under `-nodefaults`.
  ADR-033 measured refusal at the thirty-first and left the practical ceiling
  unmeasured; G1 measures it at twenty or reports the refusal.
- Sixteen literal device pairs make the template long. That is the price of
  §3's principle applied honestly; a loop would be an argv construction path.
- IPv6: ADR-033's finding stands as a precondition of every slot — AppVM images
  `accept_ra=0`, netVM sends no RA on `km*`. Nothing here weakens it.
- `ARCHITECTURE.md` § *Networking* and the `Link` row in § *Object model* must
  name the peer block, the path layout and the slot states; `SECURITY-MODEL.md`
  § *Known gaps* 14 (start ordering) gains the sentence that ADD may precede the
  AppVM's start because the slot pre-exists.

*Dependencies surfaced — not decided here*

- **How the AppVM end learns `10.100.1.(16+k)/32` and its route to `10.100.1.1`.**
  `app_web.con:12` declares no network; `katmate-init.c` has no network code;
  the opcode table in `ARCHITECTURE.md` marks NETCFG **absent** in `vm-agent`,
  by design, with `vm-agent` at uid 1000 and no `CAP_NET_ADMIN`. ADR-033's
  *"NETCFG programs the `/32` inside each guest exactly as it does today"* has
  no mechanism behind it on the AppVM side. The candidates differ in trust
  placement — a kernel `ip=` from a typed scalar in `-append`; a privileged op
  in `vm-agent`, revising the opcode table; a config the init reads from a
  device — and choosing one is an ADR, not a paragraph. Until it exists, an
  AppVM on the pool configures its address by hand through the console, as a
  gate fixture and nothing more.
- **Socket permissions.** `sendto` on an AF_UNIX path requires write on the
  socket node and search on its directories. Whether the netVM's and the
  AppVMs' QEMU processes share a uid today is a question for the write pass; the
  per-slot directory in §5 is where a per-slot ACL goes when per-VM uids arrive.

**Gates — none taken; each has a refusal half:**

- **G1 — the pool exists.** netVM boots from the pool template under
  `-nodefaults`: `ip -br link` inside shows sixteen interfaces with addresses
  `52:54:01:00:00:00`…`0f`, all DOWN; `networkctl` shows them unmanaged;
  `kmkk` names if §8 landed, and the run reports which mechanism produced them
  or that neither did; RSS against ADR-033's table. *Refusal half:* a
  seventeenth `virtio-net-pci` added to the same template is refused by QEMU, or
  is not — either is the measured ceiling.
- **G2 — one address, many links.** ADD on slots `00` and `01` with host-side
  datagram fixtures as peers: both interfaces carry `10.100.1.1/32`, each has
  its `/32` peer route, ARP for `10.100.1.1` from fixture `00` is answered on
  slot `00` with `…:00` and from fixture `01` on slot `01` with `…:01`
  (captured at the fixtures). *Refusal half:* a frame from fixture `01` with
  source `10.100.1.16` (slot `00`'s peer) arriving on slot `01` is not answered
  and not forwarded — or it is, and the run says so and names `rp_filter`'s
  value as read, not as assumed.
- **G3 — duplicates refuse.** Inside netVM, a second interface given a slot MAC
  (a `dummy` via the dev console): ADD for that MAC returns Rejected and
  programs nothing; with the duplicate removed, the same ADD succeeds. The
  refusal is the gate; the success is the control.
- **G4 — release leaves nothing.** With a fixture peer generating NAT-tracked
  flows through slot `00`: REMOVE, then `ip -br addr`, `ip route`, `ip neigh`
  and `conntrack -L` inside netVM show no address on `km00`, no route and no
  neighbour for `10.100.1.16`, no entry naming `10.100.1.16`, interface DOWN,
  record gone. *Refusal half:* a REMOVE with the previous `link_id` after a new
  ADD on the same slot changes nothing the new ADD programmed.
- **G5 — the tree survives the netVM.** With a fixture bound on
  `…/00/appvm`: stop and start the netVM unit. The `appvm` node keeps its inode;
  `netvm` has a new one; no `netvm` file exists between stop and start; the
  directory exists throughout; a re-issued ADD restores traffic in both
  directions. *Refusal half:* the same run under `RuntimeDirectory=` **without**
  `RuntimeDirectoryPreserve=yes`, expected to unlink `appvm` — measured, not
  argued, because §5's mechanism choice rests on it.
- **G6 — the boundary holds.** `systemd-analyze verify` on both templates; the
  netVM projection carries no `KM_MAC_INT`; an AppVM projection with
  `KM_SLOT=00 -drive` fails the unit at parse and starts no QEMU (ADR-030 §3's
  property, re-proven on the new keys); `KM_SLOT=1g` is refused by the
  generator before any unit sees it.

**Questions the write pass carries to the tree, as questions:**

1. Does today's REMOVE clear `IFF_UP`, delete the address, or only the route?
   Quote `netcfg.rs`.
2. Does today's ADD tolerate `EEXIST` on the address (second interface, same
   address) — convergence — or treat it as failure? Quote the netlink error
   handling.
3. What bounds an instance name's length in `katmate-generate-env` and
   `validate-properties.fish`, against `sun_path` = 108 minus this layout?
4. Under which uid do the netVM's and an AppVM's QEMU run today — is `User=`
   set in either template?
5. Is `CONFIG_IP_PNP` (or any in-kernel addressing) set in the microVM kernel's
   `.config` — relevant to the *dependency* above, recorded so the follow-on
   ADR starts from a reading.

**Revision notes this ADR requires elsewhere, once appended:**

- ADR-025 § *Replacement* (MAC scheme): *derived, never authored* is scoped to
  identity MACs; pool slot MACs are T4 constants under `52:54:01`, per ADR-035
  §2. And § *Table*: `local_addr`'s constant is now shared across every slot of
  a pool by design, per ADR-035 §3.
- ADR-030 §3: premise superseded by ADR-033, conclusion restored for network
  argv by ADR-035 §9; the key-count sentence recorded as overtaken.
- ADR-033 § *Open in this ADR, deliberately*: naming, paths, reuse and MAC
  derivation closed by ADR-035; `EAGAIN` behaviour of QEMU-as-sender remains.

**Revision note (2026-09-03, §5 — a slot's netVM device names the AppVM path,
and QEMU requires it):** §5 above names `remote.path` exactly once, and not as
something the netVM template carries: it cites ADR-033's measurement that the
path is *resolved per send and never stat-ed* as the reason a netVM may name a
socket no AppVM has bound yet. The bullet describing the device itself says only
*"the socket the netVM's QEMU binds; literal in the netVM template as
`/run/katmate/link/%i/kk/netvm`, sixteen times."* **So §5 records why naming an
absent peer is safe, and omits that the option parser demands the parameter at
start.** Measured on MINIS on 2026-09-03 against **QEMU 11.1.1**, the option that
bullet describes does not parse:

```
qemu-system-x86_64: -netdev dgram,id=t0,local.type=unix,local.path=…:
type=inet or type=unix requires remote parameter
```

Seven probes under `-machine none` bounded the finding on both sides rather than
leaving it as one failure. A bogus key added to the same line is rejected by
name (*"Parameter 'zzz' is unexpected"*), so `local.type` and `local.path` are
correct keys and the dotted form is the right one; dropping `local.path` names
it as missing; a non-type value for `local.type` names the enum; the un-dotted
`local=unix:<path>` is refused as the wrong shape. **The defect is exactly one
thing: `remote` is absent and this QEMU requires it.** The corrected line — the
same one plus `remote.type=unix,remote.path=…` — parses, binds and runs to its
`timeout`, with the peer path **absent throughout**.

**This is not a new discovery. It is a published property of this project that
§5 did not carry.** ADR-033 § *Costs accepted* records the same refusal on QEMU
11.1.0, notes that the printed synopsis brackets `remote` as optional while the
runtime refuses it as mandatory, and rules that **the runtime refusal is
authoritative and every slot names a peer path whether or not the peer exists.**
This note reproduces that on 11.1.1 and applies it to §5's own layout.

**The decision it forces, and it is the layout §5 already published:** the
`remote.path` of slot `k` in the netVM template is
`/run/katmate/link/%i/kk/appvm` — the same node §5 assigns to the AppVM's QEMU
to bind. §5 already names that node and already anticipates the naming:

> The AppVM's socket lives in the netVM's tree because the netVM's QEMU must
> name that path at *its* start, before any AppVM exists — ADR-033's measurement
> that `remote.path` is resolved per send and never stat-ed makes that safe.

What is new is not the path and not the naming. It is that the naming is **not
optional**: §5 argues it is safe, and the parser makes it compulsory. The
distinction matters to whoever writes the template, because a safe-but-optional
parameter can be omitted and a compulsory one cannot.

**Three consequences, none of which changes a sentence above:**

1. **The netVM template carries thirty-two literal paths, not sixteen.** Each
   slot names the node it binds and the node it sends to. The `netvm` bullet's
   *"sixteen times"* describes the bind half only.
2. **"Zero values cross" is unaffected**, and so is *"Identity crosses, not a
   path"*. Both paths are literal in T4 and `%i` is systemd's expansion of the
   instance name. The crossing rule governs the **AppVM** side, where `KM_NETVM`
   and `KM_SLOT` are the scalars with a type a validator can refuse; the netVM
   side is literal on both paths, as it already was on one.
3. **The `sun_path` headroom is unchanged, by arithmetic:** `netvm` and `appvm`
   are the same length, so the longer of a slot's two paths is no longer than
   the one §5's *Bound* paragraph estimates at roughly seventy characters of
   instance name. That figure is an estimate and not a measurement, and whether
   any identifier validator enforces it is **open problem #28**, which this note
   neither widens nor closes.

**What this note does not decide.** Socket permissions remain open — §
*Dependencies surfaced* lists them, and the write pass's question 4 answered
only the uids: the netVM's QEMU is root and an AppVM's is the invoking non-root
user. Now that the netVM device names `…/kk/appvm` on its own face, that
asymmetry is visible in the netVM template, and an AF_UNIX datagram `sendto`
requires write permission on the target node. **Nothing is claimed here about
the modes under `/run/katmate/link/`**; the only mode this project has measured
is a socket QEMU bound as a non-root user in `/tmp`, which is a different
directory and a different umask. G1 will bind sixteen of them as root and can
read the modes at no extra cost; that reading is an input to G5, not a result of
G1.

**Status is unchanged: PROPOSED.** No gate of this ADR has been taken, no pool
exists, and this note records a mechanism the tree already held rather than a
measurement that advances the ADR. The G1 session of 2026-09-03 halted before
writing any unit; its report is `~/Claude.assistent/adr035-g1-report.md`, not in
the repository.

**Revision note (2026-09-05, § *Gates* and §5 — what G1 measured, and the four
places the ADR does not match it):** G1's two halves were taken on MINIS as
G1a (2026-09-04, the confirmation half) and G1b (2026-09-05, the refusal half),
against QEMU **11.1.1**. Reports outside the repository:
`~/Claude.assistent/adr035-g1a-report.md` and `…-g1b-report.md`. **Five
findings, appended once rather than as five notes.**

**1. The ceiling is 26, and the seventeenth device is not refused.** G1's
refusal half above reads *"a seventeenth `virtio-net-pci` added to the same
template is refused by QEMU, or is not — either is the measured ceiling."* The
wording admits the outcome; the number misdirects. **Two ceilings were measured,
because only one of them is the one this ADR needs:**

```
bare q35 root bus, nothing else on it   30 virtio-net-pci
katmate-pool@netvm, four other PCI devices present   26 slots
difference                                            4
```

Both by bisection to adjacency. The bare bus: 16 known-good from G1a, 32
refused, then 24, 28 and 30 accepted and 31 refused. The unit: 26 accepted, 27
refused — **`N` = 17 through 25 were never run**, so the unit's ceiling rests on
the adjacency of an acceptance at 26 and a refusal at 27, not on a scan. Both
refusals carried the identical message,
`PCI: no slot/function available for virtio-net-pci, all in use or reserved`.

**The difference of four is a subtraction of two measurements and no cause is
assigned to it.** This ADR does **not** claim that each of `virtio-rng-pci`,
`vhost-vsock-pci`, `virtio-blk-pci` and `vfio-pci` costs exactly one slot —
only that the two ceilings differ by four. (`memory-backend-memfd` is an
`-object` and occupies no slot.) A prediction of 30 − 4 was stated before the
unit was run and agreed with it; **an agreeing prediction is still not a
result.**

**The same misdirection appears a second time, in § *Consequences* §
*Harder*.** That paragraph reads *"netVM's root bus carries twenty devices …
ADR-033 measured refusal at the thirty-first and left the practical ceiling
unmeasured; G1 measures it at twenty or reports the refusal."* **It is not
twenty**, and this is the more misleading of the two statements, because it does
not merely name a number — it says what G1 will find. The unit's ceiling is 26
and the bare bus is 30. The paragraph is otherwise **strengthened** by the
measurement rather than weakened: a bare ceiling of 30 **is** a refusal at the
thirty-first, so ADR-033's figure and this one agree exactly, across two ADRs,
two sessions and two QEMU versions.

**What this means for §2's sixteen.** The pool's sixteen slots sit **ten below
the unit's measured ceiling** on this hardware and this device set. That is
headroom, not licence: **every PCI device added to the netVM later spends
it**, and the number is a property of one machine and one QEMU, not of the
design.

**2. §8's `kmkk` names are not in the image, and interface names moved three
times in three boots.** No udev rule exists; the names are the kernel's
`enp0sN`. G1's own wording admits *"neither did"* as an answer, so this is a
fact about §8 rather than a failure of G1 — and §8's reasoning is strengthened
by it: across three boots of the same unit the uplink was `eth25`, `eth26` and
`eth16`, always renamed to `enp0s4`. **The MAC is the identity and the name
never is.** Three orderings were also observed to disagree — the kernel's
rename order, `ip -br link`'s name order and `networkctl`'s ifindex order — with
no cause assigned, which is the condition §7 exists for, now measured rather
than argued.

**3. §5's `sun_path` headroom is 80 characters of instance name, not "roughly
seventy".** The fixed part of a slot path is 27 bytes of the 108-byte
`sun_path`. This agrees with **open problem #28**, which is that nothing
enforces the bound, and neither widens nor closes it.

**4. G1's RSS reading is not performable as written.** It asks for *"RSS against
ADR-033's table"*, and the two subjects are not comparable: ADR-033 measured a
**paused, guestless** QEMU, while a netVM under this unit runs a booted Debian
with `-m 1G` through `memory-backend-memfd` and holds a `vfio-pci` device that
pins the entire guest RAM for DMA. The numbers are in the G1a report; **no
comparison was computed, and none should be.** This is a finding about the
gate's design, not about memory.

**5. QEMU does not unlink its `netvm` sockets at exit — on a clean stop or
after a failed start.** Four exits were observed, leaving 16, 26, 27 and 26
nodes; the pool unit carries no `ExecStopPost=`, so nothing else could have
removed them, and nothing did. The 27-node case is the informative one: a start
refused at its twenty-seventh **device** had already bound all twenty-seven
**backends**, because QEMU creates netdevs before devices.

**Two consequences, and the second is an input to G5 rather than a finding of
G1.** A pre-start sweep of the slot nodes is **load-bearing, not
precautionary** — without it the next start meets `EADDRINUSE`, which names a
syscall and would be classified as a different failure entirely. And **nothing
is claimed here about the `ExecStopPost=` this ADR proposes, about
`RuntimeDirectory=`, or about `RuntimeDirectoryPreserve=yes`**: G5 asks a larger
question — inode identity across a restart, with a fixture bound on
`…/00/appvm` — and no fixture was bound, no inode compared and no
`RuntimeDirectory=` variant run. The observation is also bounded to `SIGTERM`
and to a QEMU that exited cleanly or refused at start; it says nothing about one
that is `SIGKILL`ed or crashes.

**Status is unchanged: PROPOSED**, and for a reason independent of G1: **G2
through G6 are untaken**. What has changed is that § *Gates*' lead-in, *"none
taken"*, **no longer describes G1** — both its halves are measured, with the
single exception of the RSS reading of finding 4, which is not performable as
that half words it.

**Revision note (2026-09-07, §5 — the tree's mechanism is measured, and uid
ownership is a question §5 did not have):** G5's confirmation and refusal halves
were taken on MINIS as **G5a** (2026-09-07), against systemd on Arch and QEMU
11.1.1. Traffic was **not** taken and is G5b. Report outside the repository:
`~/Claude.assistent/adr035-g5a-report.md`.

**1. The candidate is confirmed; the fallback is not needed for creation.** §5
gates the choice — *"Which one is a mechanism claim about systemd and is gated
(G5)"* — and the mechanism claim holds. `RuntimeDirectory=` naming the sixteen
slot directories **created the tree from a confirmed-absent
`/run/katmate/link`**, three times, including the two parent levels the
directive makes itself. Sixteen directories, `drwxr-xr-x` `0755 root:root`,
every `ExecStartPre=` exiting 0, QEMU binding sixteen `netvm` nodes, the guest
up with `km00`…`km0f` and the uplink's link up.

**This closes a failure that was not hypothetical.** Between the host reboot of
2026-09-05 and this gate, **nothing created the tree**, and the first pool start
after that reboot failed at its first `-netdev` with `No such file or
directory`. The tree had existed only as hand-made `tmpfs` state that no reboot
would reproduce. Under `RuntimeDirectory=` the tree no longer depends on a
manual step; no reboot has occurred since, so that is a property of the
mechanism and not yet an observation.

**2. `RuntimeDirectoryPreserve=yes` is load-bearing, and the refusal half says
so from the other side.** §5 argues it: *"a `RuntimeDirectory=` that removes on
stop would unlink a live AppVM's socket the moment netVM restarted."* Measured,
with a fixture bound on `…/00/appvm` across a stop and start:

```
                     preserve=yes            preserve absent
appvm across stop    4830 → 4830             5000 → absent
netvm across stop    4771 survived → 4875    removed at stop → 5060
slot directory       4748 throughout         4955 → 5038, changed
fixture fd           live throughout         live throughout
```

So the argument is now a measurement: **without `Preserve=yes` a netVM restart
unlinks a live AppVM's socket**, and the AppVM keeps a live fd on an inode with
no path — which is worse than a clean failure, because it looks like a working
socket from inside. The refusal half also bounds the damage: the stop removed
**exactly the sixteen slot directories**; `/run/katmate/link` and
`/run/katmate/link/<i>` survived every stop, and the sibling `nics/` and `vm/`
trees were never at risk.

**3. G5's *"no `netvm` file exists between stop and start"* is untested, not
false.** It presupposes the mechanism §5 itself specifies two paragraphs later —
*"`ExecStopPost=` on the netVM unlinks the sixteen `netvm` files"* — and the
measuring unit carries no `ExecStopPost=`, deliberately. **None was added and
nothing was unlinked to make the clause true.** Under `Preserve=yes` every one
of the sixteen `netvm` nodes survived the stop, slot `00` at the inode QEMU
bound it at.

**Read with the three earlier observations that QEMU does not unlink its sockets
at exit — on a clean `SIGTERM` stop and after a start refused at a device — this
strengthens §5 rather than qualifying it: `ExecStopPost=` is necessary, not
tidy.** Nothing else removes those files, and a surviving node makes the next
`bind()` fail with `EADDRINUSE`, which names a syscall and reads as an entirely
different failure. **It is not yet implemented.**

**4. A non-root `bind()` into a slot directory is refused, and §5 has no rule
that answers it.** As the invoking non-root user, `bind()` on `…/01/appvm`
returned `EACCES` — the directory is `0755 root:root`, systemd's default
`RuntimeDirectoryMode=`, and a datagram `bind()` needs write permission on the
containing directory. Re-confirmed against the consolidated unit's own tree
rather than carried over. **An AppVM's QEMU runs as that user.**

§5 says *"the ownership rule is the decision"*, but the rule it states is about
**who the tree belongs to across a stop**, not about **which uid may bind into a
slot**. That second question did not exist until the first was settled.

**The operator ruled it on 2026-09-07:** `RuntimeDirectory=` creates the
sixteen directories root-owned, and **the launch daemon sets ownership at
assignment and returns it at release** — the same moment the `owner` file is
written and removed, so occupancy and permission are one act rather than two
that can disagree. **Loosening `RuntimeDirectoryMode=` was considered and
rejected**: a group-writable tree would let any member bind into an unassigned
slot, which would make *"absence is freedom"* unenforceable and the `owner` file
a description rather than a record.

**Not decided, and named so it is not lost:** whether the slot directory needs
the sticky bit. Without it an AppVM that may write into its own slot may also
unlink the netVM's `netvm` node there. **No mode was changed and no `chown` was
run** — the launch daemon does not exist, and none of this is implemented.

**5. What G5a did not take.** Traffic. G5's *"a re-issued ADD restores traffic
in both directions"* needs a peer that speaks Ethernet frames, since a
`-netdev dgram` backend carries frames and not IP, and that is G2/G4 apparatus.
It is **G5b**.

**Status is unchanged: PROPOSED.** G2, G3, G4, G5b and G6 are untaken, and
§5's `ExecStopPost=` and the assignment-time ownership are both unimplemented.

**Revision note (2026-09-12, § *Gates*, §6, §7, §9 and § *Questions* — five gate
sessions of one day, and what they measure about three decisions):** G2, G3, G4,
G5b and G6 were taken on MINIS on **2026-09-12**, across five delegated
sessions, against QEMU **11.1.1**, on the netVM run by `katmate-pool@netvm.service`
since the host boot of 2026-09-05 20:10:29. Reports outside the repository, all
of 2026-09-12: `~/Claude.assistent/g5b-rxfilter-report.md`,
`~/Claude.assistent/g5b-restart-report.md`, `~/Claude.assistent/g2-add-report.md`,
`~/Claude.assistent/g2-refusal-g6-report.md` and
`~/Claude.assistent/g3-g4-console-report.md`. **Eleven findings, appended once
rather than as five notes.**

**Three of the eleven are implementation gaps and not design errors**, and are
written as such: finding 1 (supersession), finding 4 (`ifindex_by_mac`) and
finding 5 (§9's keys). In each the decision above stands unchanged and what is
missing is the code that would carry it. **Every code change named below is a
proposal for the code pass, never a decision taken here.**

**1. Supersession is load-bearing, not convenient, and it is not implemented.**
§6's convergence paragraph reads: *"An ADD naming a `match_mac` that already
carries a record under a different `link_id` **supersedes** that record — an
interface has one link, and the newer assignment is the truth."* **The design
stands; the implementation does not do it.**

Measured in `g3-g4-console-report.md` § 5.5b/c (2026-09-12). With link **201**
installed on slot 01, an ADD of link **211** naming the same `match_mac`
`52:54:01:00:00:01` and the same peer `10.100.1.17` was **accepted** —
`status=0x00 (OK)` at 18:39:07 CEST — and it superseded nothing: it wrote a
**second record**, `link-000000d3` beside `link-000000c9`, and added a second
route at metric 200 beside 201's metric 100, the address itself unchanged
because `addr_add` met `EEXIST` and tolerated it. `do_add` keys on `link_id`
alone; that a slot is occupied is not a thing it knows.

The REMOVE of 211, forty-one seconds later, then **deleted the address
`10.100.1.1 peer 10.100.1.17/32` — which *both* records describe** — and with it
link 201's metric-100 route, the kernel's implicit `proto kernel` route and the
`km01` neighbour entry for `10.100.1.17`, **while record `link-000000c9`
survived byte-identical** (§ 5.5c). `drive_remove` withdraws what its own record
describes and has no notion of a sibling. Link 201 was left as *a record
describing a link that is not installed*: from the host side, which holds the
record and an `OK` reply, slot 01 was configured; inside netVM it carried no
address, no route and no neighbour.

**What this changes about §6's harmlessness claim.** §6 concludes that an
absorbed REMOVE and supersession *"together make a late REMOVE from a previous
tenant harmless to the current one, without encoding generations anywhere."*
**That conclusion is conditional on supersession, and the condition is the half
that is missing.** With supersession the previous tenant's `link_id` does not
survive the new ADD, so a late REMOVE naming it meets the absorbing path §6 also
describes and is harmless. Without supersession the stale record can outlive its
mechanism — `netcfg.rs`'s own header names the crash window between
`drive_remove` and `remove_record` — and § 5.5c is that window's outcome
measured directly: the late REMOVE is not absorbed, it de-programs the current
tenant.

**The gap is the absence of supersession, and nothing here argues for encoding
generations.** The measurement shows the opposite: had `do_add` superseded, the
sibling case § 5.5c constructed could not have existed at all. `link_id` remains
ADR-025's opaque counter. **Supersession in `do_add` is a proposal for the code
pass.**

**2. Question 1 is answered: what today's REMOVE does, and the three things it
does not do.** § *Questions* asks *"Does today's REMOVE clear `IFF_UP`, delete
the address, or only the route?"*, and §6 closes by calling this *"a question,
not an assumption"*. It is now an observation.

Measured in `g3-g4-console-report.md` § 5.3 (2026-09-12), on slot 01, against
§6's own enumerable list — **three of six items**:

| §6 requires of REMOVE | measured on slot 01, 18:42:36 CEST |
|---|---|
| delete the address on that interface | **done** — `km01 UP fe80::5054:1ff:fe00:1/64`, no IPv4 address |
| delete the peer route | **done** — no route for `10.100.1.17` of any kind, the agent's `metric 100` one and the kernel's implicit `proto kernel` one both gone |
| delete the record | **done** — `link-000000c9` gone, `c8` and `ca` remain |
| clear `IFF_UP` | **not done** — `km01` still `<BROADCAST,MULTICAST,UP,LOWER_UP>` |
| delete the neighbour entry for peer `k` | **done on the slot, not globally** — the `km01` entry went with the address, by the kernel's own cleanup; `10.100.1.17 dev km02 lladdr 52:54:01:00:01:02 STALE` was untouched |
| flush conntrack entries naming peer `k` | **not done** — the entry survived, read live on both sides of the release |

The conntrack row is the sharpest of the three, because it was read live rather
than by absence: `/proc/net/nf_conntrack` carried
`icmp … src=10.100.1.17 dst=10.100.1.1 … id=54484` with **ttl 27** immediately
before the REMOVE and the same entry with **ttl 23** immediately after
(§ 5.3). **It aged four seconds; it was not flushed.**

**What it changes.** §6's *"REMOVE returns the interface to FREE, and FREE is
DOWN — that is the quarantine: a down interface receives nothing"* **describes a
state today's REMOVE does not produce.** The two missing primitives are
`link_down` and the conntrack flush, and the flush is the one §6 already names as
*"the one new capability the pool asks of the agent"*. §6's argument that an
enumerated teardown beats a time-based quarantine is untouched by this; what is
measured is that two items of the enumeration have no implementation yet. **Both
are proposals for the code pass.** The neighbour row carries one design
consequence §6 does not yet state: *"delete the neighbour entry for peer `k`"*
has to name an interface, and the entry that most needed deleting sat on a
different one (finding 6).

**And the discipline that makes the conntrack row readable is recorded, because
it nearly went the other way.** The session's first conntrack read came back
**empty 39 s after the last flow** (§ 5.2a) — inside the 30 s default ICMP
timeout, so the entry had expired on its own, and an expired entry is
indistinguishable from a flushed one. Every later read was timed inside the
window, on both sides of the REMOVE. **A negative that coincides with a natural
expiry is not a measurement**, and a conntrack row read without that timing would
have reported a flush that does not exist.

**3. Question 2 is answered: today's ADD tolerates `EEXIST`.** § *Questions*
asks whether ADD treats `EEXIST` on the address as convergence or as failure.
Measured in `g3-g4-console-report.md` § 5.5b/c (2026-09-12), which quotes
`netlink.rs:407/437`: it is tolerated on **both** `addr add` and `route add`, and
the ADD of link 211 onto an interface already carrying `10.100.1.1 peer
10.100.1.17/32` returned `OK` with the address unchanged and a new route added.
Convergence works as designed on that axis, and §3's *"one address, many links"*
is not obstructed by the netlink layer. The same session observed the other
convergence claim directly: an **identical re-ADD** of link 201, issued against
an interface whose record had survived but whose kernel state had not, restored
the link completely and did not rewrite the record (§ 5.5d).

**Questions 1 and 2 move out of § *Questions* by this note. Questions 3 and 5
remain open**, and nothing in these five sessions bears on either. **Question 4
was closed by this ADR's revision note of 2026-09-03**, which is where its answer
is; it is not reopened here.

**4. §7 is unimplemented, and G3 measured the harm it exists to prevent.** §7
says `ifindex_by_mac` *"must count"*, that two or more interfaces carrying the
requested address is a **Rejected** and not a first-match, and that this
*"lands in the pool's agent commit"*. **That commit has not landed. This is an
implementation gap, not a design error** — §7 argues exactly the outcome that
was measured, and the measurement is now the evidence for it rather than the
reasoning.

Measured in `g3-g4-console-report.md` § 4 (2026-09-12). A `dummy` interface
`g3dup` was created inside netVM carrying `52:54:01:00:00:03`, slot 03's
constant, and shown to coexist with `km03` before anything was sent — ifindex 19
and ifindex 5, both DOWN, neither carrying an address (§ 4.1). The ADD for that
MAC returned **`status=0x00 (OK)`** (§ 4.2) and programmed **the dummy**: address
`10.100.1.1 peer 10.100.1.19/32`, both routes, `IFF_UP` raised and a well-formed
record `link-000000cb` — **while `km03`, the actual slot, stayed DOWN with
nothing** (§ 4.3). The outcome was decided by enumeration order alone: `ls -U
/sys/class/net` put `g3dup` second and `km03` fourteenth, and the session
predicted the named interface from that order **before** issuing the ADD
(§ 4.1).

**What it changes for the gate.** **G3 did not fail; it is not performable until
§7 lands.** G3 words its subject as a refusal — *"ADD for that MAC returns
Rejected and programs nothing"* — and what exists to be measured today is the
pre-correction behaviour, now with a number attached: **a link assigned to slot
03 was programmed onto an interface that is not slot 03, and nothing on the host
side distinguishes that from a correct install.** The reply was `OK` and the
record is well-formed; only reading interface names inside netVM tells the two
apart, and the host has no such reading. G3's control half — sixteen distinct
MACs, where first-match cannot pick wrongly — holds and was re-read the same day
(§ 3.3). **Counting in `ifindex_by_mac` is a proposal for the code pass.**

**5. §9 is unimplemented, and G6 splits into a half that is taken and a half
that is blocked.** §9 says `KM_MAC_INT` *"retires with `tap-int0`"* and that the
AppVM template *"gains two typed scalars, `KM_NETVM` and `KM_SLOT`"*. **Neither
has happened, and this too is an implementation gap rather than a design error**
— §9 makes both conditional on a change that has not been made.

Measured in `g2-refusal-g6-report.md` § 3.2–3.4 (2026-09-12): the live netVM
projection `/run/katmate/vm/netvm.env` carries **`KM_MAC_INT=52:54:00:21:b2:08`**
among its thirteen keys; the installed `katmate-generate-env` has no `KM_SLOT`
and no `KM_NETVM` key at all (`grep` exit 1 over the installed executable); and
**no AppVM template is installed** — the installed templates are exactly
`katmate-pool@.service` and `katmate-sys-driver@.service`.

**What it changes for the gate. G6 describes the post-§9 world and has to be
split by this note:**

- **G6a — taken** (`g2-refusal-g6-report.md` § 3.1 and § 3.2, 2026-09-12):
  `systemd-analyze verify` on both existing templates, by path and by instance,
  **exit 0** on all four invocations, the only diagnostic belonging to a third
  unit (`vhost-vsock-load.service`'s `ConditionKernelModule`, which systemd notes
  as ignored); and the netVM projection read in full.
- **G6b — blocked until §9 lands** (§ 3.3 and § 3.4): the `KM_SLOT=00 -drive`
  injection has no AppVM projection to inject into and no AppVM unit to start,
  and `KM_SLOT=1g` has no generator input to be refused by. **Neither was run.**
  ADR-030 §3's whitespace guard is present in the generator's `emit()` and would
  catch the injected form, **but only once `KM_SLOT` is an emitted key**, which
  it is not.
- **G6's `KM_MAC_INT` clause belongs to G6b**, not to G6a: the projection carries
  the key today, and §9 says it retires *with* `tap-int0`.

**6. G2's refusal half takes two forms, and they measure different properties.**
The half is worded around a frame that *"is not answered and not forwarded — or
it is, and the run says so and names `rp_filter`'s value as read, not as
assumed."* Both forms were run, in two sessions of the same day, and the value
is read.

**`rp_filter` is 2 — loose — on every slot interface**, `all` = 0, so the
effective value by the kernel's `max(all, iface)` rule is **2**
(`g3-g4-console-report.md` § 3.2, 2026-09-12; read, never set). Loose mode asks
only whether the source address is reachable via *some* interface, not via the
one the packet arrived on. `10.100.1.17` is reachable via `km01`, so a packet
carrying that source and arriving on `km02` **passes ingress** — which is exactly
the mechanism behind the *accepted* the IPv4 form measured. **Strict mode (1) is
what would drop it, and strict mode is not what is configured.**

- **The IPv4 form** (`g2-refusal-g6-report.md` § 2.2–2.5, 2026-09-12) measures
  acceptance and the steering of the response. An ICMP echo request with source
  `10.100.1.17` — slot 01's peer — delivered onto slot 02 at 13:56:39 CEST was
  **accepted and acted on in another tenant's name**: within the same second
  netVM began resolving `10.100.1.17` **on slot 01**, from slot 01's own MAC, and
  **the spoofer on slot 02 received nothing** across 67 s (RX unchanged at 21).
  Two controls bound the reading: the same frame with each slot's own source
  produced an echo reply at that slot's own fixture, in the same millisecond
  (§ 2.2, § 2.3). Re-runs of the legitimate control after the spoof showed **no
  durable redirection toward slot 02** (§ 2.5).
- **The ARP form**, which the half's old wording reaches for and which
  `g2-add-report.md` § 5.4 (2026-09-12) measured, **planted a durable cross-slot
  neighbour entry.** An ARP request carrying `spa=10.100.1.17` and
  `sha=52:54:01:00:01:02` sent onto slot 02 at 12:49:36 CEST was answered by
  netVM on slot 02 and not forwarded to slot 01 — and it left
  `10.100.1.17 dev km02 lladdr 52:54:01:00:01:02` in netVM's neighbour table.
  `g3-g4-console-report.md` § 3.1a dated that entry by `ip -s neigh` ages to
  **12:49:37**, which lands on the ARP-form frame to the second and is **67
  minutes before** the ICMP spoof — which therefore neither created nor refreshed
  it. It was still present at that session's close (§ 5.5c, § 10).

**What it changes.** **The refusal half takes both forms, because they measure
different properties.** The IPv4 form measures what `rp_filter` governs: ingress
acceptance of a foreign source, and the steering of the response by the per-slot
routes. The ARP form measures what `rp_filter` does not govern: contamination of
the neighbour table across slots, a mapping from one tenant's address to another
tenant's MAC that outlives the frame that planted it, survives a release on a
different slot (finding 2), and which the IPv4 form did not show. A run of only
one form answers half the question. **`rp_filter=1` on the slot interfaces is
recorded here as a proposal for the code pass and not as a decision taken** — the
value was read and nothing was set, and what the right value is belongs to the
tier model rather than to a session.

**7. The `EADDRINUSE` claim of this ADR's 2026-09-05 note, finding 5, was never
observed, and the motivation for `ExecStopPost=` is rewritten rather than
withdrawn.** That note publishes, as a measured consequence, that *"A pre-start
sweep of the slot nodes is **load-bearing, not precautionary** — without it the
next start meets `EADDRINUSE`."*

Measured in `g5b-restart-report.md` § 0.1.4, § 3.1 and § 9 (2026-09-12): a
`systemctl restart` of `katmate-pool@netvm.service` was run with **no sweep, no
`ExecStopPost=` in the unit and sixteen surviving `netvm` nodes**, and it
**succeeded** — all sixteen rebound at new inodes (5265 → 7592, the set running
7592–7611), no `EADDRINUSE`, nothing naming a syscall anywhere in the journal
across the stop and the start. The mechanism is **QEMU's own `unlink()` before
`bind()`**, identified on this same unit by `~/Claude.assistent/adr035-g5a-report.md`
§ 5.2 on 2026-09-07; 2026-09-12 is the second independent observation, on a
different boot of the unit and with a live peer bound in the same directory
throughout.

**How the claim came to be published matters more than the claim.** Every
`EADDRINUSE` in `~/Claude.assistent/adr035-g1b-report.md` is **counterfactual** —
*"had they been left, `bind()` would have failed `EADDRINUSE`"* — because that
session's sweep always ran first and removed a non-zero count every time. The
branch was never taken, so the claim was never falsifiable there, and a
hypothesis about an untaken branch was promoted to a measured invariant. It is
the shape `state.md` § *Invariants & gotchas* already names: **a check that
cannot fire is indistinguishable from a check that found nothing.**

**What it changes. §5's `ExecStopPost=` stays, by the operator's ruling of
2026-09-12, with its motivation rewritten.** It is not motivated by
`EADDRINUSE`, which does not occur. It is motivated by what stands in the slot
directory between a stop and a start: the sixteen `netvm` nodes survive the stop
(`g5b-restart-report.md` § 3.1, and `adr035-g5a-report.md` § 5.2 of 2026-09-07
under `RuntimeDirectoryPreserve=yes`), and once the netVM's QEMU is gone those
nodes are **unheld** — which is precisely why the next start can rebind them. An
unheld node in a slot directory is bindable by anything that may write there, and
whatever binds it receives the AppVM's frames in the gateway's place. **A
pre-start sweep runs too late to close that window**; only an unlink at stop
does. §5's own sentence — *"`ExecStopPost=` on the netVM unlinks the sixteen
`netvm` files"* — is unchanged and remains **unimplemented**, as the 2026-09-07
note records.

**8. § *Gates*' lead-in, *"Gates — none taken"*, is now false of every gate but
one, and this note states each with its report.** The lead-in is corrected by
this note and not edited.

| gate | status on 2026-09-12 | evidence |
|---|---|---|
| **G1** | **taken**, both halves | `adr035-g1a-report.md` (2026-09-04) and `adr035-g1b-report.md` (2026-09-05), as the 2026-09-05 note records; its RSS reading is not performable as worded |
| **G2**, confirmation | **taken** | fixture-visible half `g2-add-report.md` § 5.3; the interior — the three `/32`s, the flags, the per-slot routes — `g3-g4-console-report.md` § 3.3, both 2026-09-12 |
| **G2**, refusal | **taken, in two forms** | ARP form `g2-add-report.md` § 5.4; IPv4 form `g2-refusal-g6-report.md` § 2.2–2.5; `rp_filter` read in `g3-g4-console-report.md` § 3.2 — all 2026-09-12 (finding 6) |
| **G3** | **not performable until §7 lands** | `g3-g4-console-report.md` § 4, 2026-09-12 (finding 4) |
| **G4**, confirmation | **partly measured — three of six rows** | `g3-g4-console-report.md` § 5.3, 2026-09-12 (finding 2); the `conntrack -L` clause is vacuous as worded (finding 11) |
| **G4**, refusal | **holds in the literal form, fails in the redesigned one** | `g3-g4-console-report.md` § 5.5a and § 5.5c, 2026-09-12 (findings 1 and 10) |
| **G5a** | **taken**, both halves | `adr035-g5a-report.md`, 2026-09-07, as the 2026-09-07 note records |
| **G5b** | **restart clauses observed; the traffic clause not taken** | `g5b-restart-report.md` § 3.1 and § 4 (2026-09-12): `appvm` inode 7528 unchanged across the restart with its socket and the peer's fd agreeing, `netvm` renewed, the slot directory and both parents never recreated; *"no `netvm` file exists between stop and start"* **still untested and still not false**, since it presupposes the `ExecStopPost=` the unit does not have. *"A re-issued ADD restores traffic in both directions"* was **not taken**, and what nothing measured is restoration **after** the restart. **Neither direction is unexercised, and neither was exercised as this clause words it.** Peer → netVM was taken **before** the restart, in `g5b-rxfilter-report.md` § 2.5.1 (2026-09-12): `km00 rx_packets` 0 → 10 and then 12, reconciling exactly with that session's slot peer's `eth0 tx` at both readings. NetVM → the guest on slot 00 was taken **after** the restart and on the restart-survived binding, in `g2-add-report.md` § 5.2 (2026-09-12): the guest's `eth0 rx` rose **0 → 6 → 11** following the slot-00 ADD of 12:47:42 CEST, after **2034** consecutive readings at zero over that peer's whole life — the peer being `g5br-restartpeer.service`, MainPID 3627150, started 09:58:06 CEST and alive across the 09:59:37 CEST restart. Two things the clause asks for are still missing: the **guest on slot 00 → netVM** direction is **not measured** (`g2-add-report.md` § 6), so no ADD has been shown to carry both directions of one slot; and a counter that had never been non-zero rising for the first time is first traffic, not restoration. In the pre-restart window `km00 tx_packets` stood at 100 across three readings and about seven minutes (`g5b-rxfilter-report.md` § 2.5.2, § 2.6), which measures an idle emitter and not a receiver |
| **G6a** | **taken** | `g2-refusal-g6-report.md` § 3.1, § 3.2, 2026-09-12 (finding 5) |
| **G6b** | **blocked until §9 lands** | `g2-refusal-g6-report.md` § 3.3, § 3.4, 2026-09-12 (finding 5) |

**9. A citation hazard, and the convention going forward.** This ADR numbers its
decisions **1–9**, and the existing notes cite them as `§n` with `n` the
decision's own number. The session reports do not agree with each other:
`g2-refusal-g6-report.md` § 3 writes **`§7`** for **decision 9** (`KM_MAC_INT`,
`KM_NETVM`, `KM_SLOT`, the AppVM template), while `g3-g4-console-report.md`
§ 4.4 writes **`§7`** for **decision 7** (`ifindex_by_mac` must count). Both were
written on 2026-09-12 and only the second matches this ADR. **Nothing is
renumbered; the convention is restated:** a decision of this ADR is cited by the
number this ADR gives it, and a reader meeting `§7` in a report of 2026-09-12
must check which decision the sentence is about before carrying it.

**10. `OK` does not distinguish a removal from an absence, and for a reader of
the reply that is a trap.** Measured in `g3-g4-console-report.md` § 5.5a
(2026-09-12): a REMOVE naming `link_id` 211, which had never been installed,
returned **`status=0x00 (OK)`, payload_len=0** — byte-identical to the reply to
the REMOVE that actually withdrew link 203 earlier the same day (§ 4.5), and
nothing changed. **For convergence this is §6 working as designed** —
*"A REMOVE naming an unknown `link_id` is absorbed"* — and the note records it as
the confirmation of that clause. **For anyone reading the reply as evidence that
a link was installed, it is a trap:** the wire does not distinguish *"I removed
it"* from *"there was nothing to remove"*, and finding 1 supplies the case where
that matters.

**11. `conntrack -L` is not in the netVM image, so G4's clause is vacuous as
worded.** Measured in `g3-g4-console-report.md` § 5.2a (2026-09-12): `command -v
conntrack` returns nothing and `conntrack -L` is `command not found`. **The
subsystem is present and in use, and only the tool is missing:** the guest's own
nft ruleset carries `ct state established,related accept` in both filter chains,
`/proc/net/nf_conntrack` exists and is readable, and
`/proc/sys/net/netfilter/nf_conntrack_count` reads a live value. **G4's clause is
therefore corrected by this note to read `/proc/net/nf_conntrack` and
`nf_conntrack_count` rather than `conntrack -L`**, with finding 2's timing
constraint attached: the reading is only evidence if a live entry existed
immediately before the release. Whether the tool should be added to the image is
a manifest question and is not decided here.

**Status is unchanged: PROPOSED.** Every gate but G1 and G5a has now been taken
or attempted, and the ADR is no closer to acceptance for a reason the gates
themselves report: **three of its decisions have no implementation.** §6's
supersession, its `link_down` and its conntrack flush; §7's duplicate count; §9's
retirement of `KM_MAC_INT` and its two new AppVM scalars — each is a decision
this ADR took and no commit has carried. G3 is not performable until §7 lands and
G6b is not performable until §9 lands; §5's `ExecStopPost=` and the
assignment-time ownership of the slot directories remain unimplemented, as the
2026-09-07 note records. **No code was written, no sysctl was set and no unit was
changed by any of the five sessions**, and every change named in this note is a
proposal for the code pass.
