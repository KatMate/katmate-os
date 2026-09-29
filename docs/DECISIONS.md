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

**Revision note 2026-09-26 — the foundation carries the shared GUI runtime, and has
since 2026-06-29.** § *Context* and the layer table describe the foundation as
"OS + kernel + waypipe + vm-agent" carrying "no applications". From `9fddf9d`
(2026-06-29) `build/foundation.sh` also installed `dbus`, `libgtk-3-0`, `foot` and
`nautilus`. Measured 2026-09-25 on the live foundation: 415 packages, 88 manual.
Ruled 2026-09-26: the foundation carries the minimal GUI runtime every GUI domain
shares (GTK3, fonts, GBM, Wayland client, the waypipe compression libraries) and no
applications; `foot` and the file manager (`pcmanfm`, replacing `nautilus`) move to
the domain manifests. Measured result in a trial of the new list: 204 packages.
Accepted as debt, not as design: `systemd`, `systemd-sysv`, `dbus` and `dbus-daemon`
remain installed and never run, pulled by GTK3 → dconf-service → dbus-user-session →
libpam-systemd. Their removal is deferred past the alpha. The domain table's `web`
row (firefox-esr, foot, nautilus) is superseded by `manifests/web.list`:
firefox-esr, foot, pcmanfm.

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

**Revision note (2026-09-26, § *Decision*, *Both binaries from the same tree*
— the unit did not point where this ADR says, for at least eight days):** the
sentence *"the `waypipe-client` systemd user unit points there"* was **not
true on MINIS from at least 2026-09-18 until 2026-09-26**. The unit's
`ExecStart` pointed at `/usr/bin/waypipe`, the distro package at **0.11.2**,
not at `/opt/katmate/bin/waypipe`, so host and guest ran different waypipe
versions, undetected because `katmate-check-waypipe` checks the `/opt` binary.
The operator repointed the unit on 2026-09-26, and removed the distro package
the same day (`pacman -Rs waypipe`); `waypipe` is no longer on the host
`PATH`. The decision is unchanged; what was wrong was the state this ADR
described. Sources: the operator's statements of 2026-09-26, recorded in
`state.md` § *Live state*, *Host GUI ingress*; `docs/HOST-CONFIG.md` § 11.

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

**Revision note (2026-09-26, [ADR-037](DECISIONS.md#adr-037)):** this ADR's
premise that netVM egress is ProtonVPN, and its open **DNS-leak policy**
decision, are **superseded by ADR-037** (PROPOSED), on the operator's rulings of
2026-09-26: vanilla egress is direct through the uplink, with VPN a
post-install option enabled by a user-supplied WireGuard config (R2); AppVM DNS
is `dnsmasq` in netVM on `10.100.1.1`, forwarding to the DNS server the uplink
receives (R5); and `dhcpcd` replaces systemd-networkd on the uplink (R6). The
rest of this ADR — the sysVM class, the declarative build, the agent and the
update track — is unchanged. Sources: ADR-037 § *Context* (`net-up-report.md`
§ 19.3, `net-m1-report.md` § 9).

**Revision note (2026-09-27, § *Decision* — the uplink bake-list bullet, the
agent's write grant, and the initramfs `MODULES=` value):** three sentences of
this ADR no longer describe the target, or no longer describe the tree. They
are recorded here and left as written. The source is ADR-037's read pass
(`adr037-readpass-report.md`, outside the repository, divergences D2, D10 and
D13) and the operator's rulings of 2026-09-27 (ADR-037's note of that date).

- **The bake-list bullet *"`/etc/systemd/network/20-uplink.network` —
  MAC-matched DHCP on the vfio uplink NIC"* retires (D2).** Under
  [ADR-037](DECISIONS.md#adr-037) R3 the uplink is named `uplink0` by a `.link`
  matched on `Path=`, and under R6 `dhcpcd`, not systemd-networkd, takes its
  lease. The 2026-09-26 note above names R2, R5 and R6 but not R3. The bullet
  describes the tree until the implementation lands.
- **§ *Privilege*'s *"plus write access to `/etc/systemd/network/`"*, and its
  *"writing `.network` fragments, reloading networkd"*, retire with the fix
  of open problem #27 (D10).** [ADR-025](DECISIONS.md#adr-025) Path B programs
  the internal links by rtnetlink, and needs no file write and no reload.
  ADR-037 R24 moves the agent unit into `manifests/netvm.conf.d/` with one
  author, and the grant goes with it. Until then, the baked unit still carries
  `ReadWritePaths=/etc/systemd/network /run` (`build/netvm.sh` step 7).
- **The initramfs is `MODULES=most`, not *"`MODULES=dep`"* (D13).** `dep`
  resolves modules against the chroot's build root and omits `virtio_blk`, so
  the guest cannot find `/dev/vda`. The change was made and proven on
  2026-07-09. It is recorded in `state.md` § *Invariants & gotchas* (*"netVM
  initrd needs `MODULES=most`, NOT `dep`"*), and `build/netvm.sh` pre-seeds
  `MODULES=most` before the kernel is installed. The initramfs is still
  retained, not eliminated, as the bullet says.

**Revision note (2026-09-27, follow-up to the note above — both retirements
landed):** the note above states two retirements prospectively. Both have
landed in the ADR-037 implementation, and the image built from it
([ADR-037](DECISIONS.md#adr-037)'s implementation note of 2026-09-27).

- **The bake-list bullet.** `0f304c9` names the uplink `uplink0` by
  `60-katmate-uplink.link` on `Path=` (R3), and `bb1481a` replaces
  systemd-networkd with `dhcpcd` on the uplink and removes `20-uplink.network`
  (R6). Gate G2 passed on the rebuilt image, and so did G3's DHCP half.
- **The `/etc/systemd/network/` grant.** `098e868` makes the agent unit a
  tracked file in `manifests/netvm.conf.d/` (R24), with
  `ReadWritePaths=/run` only. Open problem #27 closed on 2026-09-27 on that
  image: NETCFG ADD and REMOVE returned OK with `/etc/systemd/network`
  read-only.

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

**Revision note (2026-09-29, § *Decision*, *v1 instantiates the simplest
graph* — the v1 default carries no VPN):** *"The shipped default is one driver
domain terminating the uplink and carrying the VPN — i.e. exactly the netVM
that runs today, unchanged"* no longer describes the target or the running
system. Under [ADR-037](DECISIONS.md#adr-037) (Accepted 2026-09-29), vanilla
egress is direct through `uplink0` with no VPN (R2). VPN mode is a
post-install option: networking arc step 5, under its own ADR (R30). When
enabled, it runs in the same driver domain. The v1 default is therefore one
driver domain terminating the uplink, with no key in it. The driver/secret
co-location this ADR names arises only when VPN mode is enabled. The rest of
the decision is unchanged: the graph, and the split chain as a post-v1
paranoid profile. `docs/ARCHITECTURE.md` § *Object model* and *Known v1
co-location* were brought into line on 2026-09-29 (`bfb47d0`). The text above
is not edited.

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

**Revision note (2026-09-27, Path B's load-bearing fact and the 2026-08-09
note — the uplink is no longer MAC-matched):** two sentences above describe
the uplink as it was before [ADR-037](DECISIONS.md#adr-037). Path B's
load-bearing fact reads *"the image bakes only the MAC-matched
`20-uplink.network`"*. The 2026-08-09 note reads *"`manifests/netvm.conf.d/`
carries the MAC-matched **uplink** only"*. Both are stale on the ADR-037
image. The source is ADR-037's read pass (`adr037-readpass-report.md`,
outside the repository, divergence D2).

- **For the uplink, MAC matching is replaced by `Path=`.** Under ADR-037 R3
  the guest names it `uplink0` by `60-katmate-uplink.link`, matched on
  `Path=pci-0000:00:04.0`, and `20-uplink.network` is gone from the image.
  Gate G2 passed on 2026-09-27.
- **The internal-segment half is unchanged.** The sixteen slot `.link` files
  still match by MAC, and G2 read 16 slots on 16 distinct files. The image
  still bakes no internal-segment `.network` unit.
- **NETCFG's own mechanism is not affected.** Path B programs the internal
  links by rtnetlink, as decided above.
- **The corollary that internal NICs are unmanaged** no longer rests on
  networkd, which ADR-037 R15 disables in netVM. Its `dhcpcd` form is
  ADR-037 R14, `allowinterfaces uplink0`. G3's refusal half passed as ruled
  on 2026-09-27, scoped to dhcpcd-originated state on the slots (ADR-037's
  implementation note).

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

**Revision note (2026-09-28, the order the unit templates ship in —
[ADR-037](DECISIONS.md#adr-037) R61):** this note qualifies the 2026-08-09
note. It changes no text above. Step 3a shipped `sys-driver` only. Under
R61, **`app-routed` ships first**, at networking arc step 4a, together with
the removal of the generator's guard (open problem #19) and the `REQ_ENV`
arm in one commit; **`app-offline` ships with the vault instance**, not
before, since a template nobody runs would rot. The 2026-08-09 note's
*"Step 3a ships two unit templates, not three — `sys-driver` and
`app-offline`"* stands as written, qualified by this note: that was the
plan for 3a, and 3a shipped one of the two.

**Revision note (2026-09-29, `app-routed` shipped):** this note records a
shipment. It changes no text above and takes no gate.
`katmate-app-routed@.service` shipped in `d6feb9c` (networking arc step
4a, [ADR-037](DECISIONS.md#adr-037) R61, together with the removal of the
generator's guard and the `REQ_ENV` arm), and it first ran on MINIS on
2026-09-29 as `katmate-app-routed@app_web` (`s4a-impl-B-report.md`,
outside the repository; ADR-037's note of the same date). Two templates
now ship, `sys-driver` and `app-routed`. **`app-offline` still ships with
the vault instance** (R61). **The deletion of the `.con` files (G3) is
still not in step 4**; `app_web.con` and `katmate-app-routed@app_web` must
never run at once.

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

**Revision note (2026-09-27, §1 — a second T1 form, per concern, for
configuration that is not a property):** the operator ruled on 2026-09-27
(ADR-037's R31, in its note of that date; `r8-readpass-report.md` D1, D2 and
D12, outside the repository) that §1's T1 row has **two forms**. The table
itself is left as written, and this note amends it:

| Tier | Author | Directory | Wins on upgrade |
|---|---|---|---|
| **T1** instance properties | the user | `/etc/katmate/vm/<name>.toml` | the **user** |
| **T1** per-instance configuration that is not a property | the user | `/etc/katmate/vm/<instance>.d/`, one file per concern | the **user** |

- **Keyed by instance**, like `<name>.toml`, and never by manifest or class.
  Each file holds one concern. The first is ADR-037's `uplink` (arc step 3).
- **No overlap.** No key may appear both in `<instance>.d/` and in
  `<instance>.toml`. The directory holds only concerns that are not properties.
- **An unknown file in `<instance>.d/` is refused.**
- **Why §1's rejection does not apply.** §1 rejects a per-VM directory because
  it *"admits two sources for one VM"*. This directory is not a second source
  for any key: every key has exactly one home, a property in `<name>.toml` or
  a concern in `<instance>.d/`, and the no-overlap rule and the refusal of
  unknown files hold that.
- **`<name>.toml.d/` stays reserved** for property drop-ins, the later
  extension §1 names. `<instance>.d/` is not that extension, and neither name
  may be used for the other's purpose.
- **Modes.** §1's `root:root` `0644` is stated for `<name>.toml`, and a
  world-readable mode is wrong for a key (r8 D12). The modes for a secret in
  `<instance>.d/` are decided at ADR-037's arc step 5 (VPN mode). This note
  sets no mode.

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

**Revision note (2026-09-28, § *Decision* — the slot is not a field on
ADR-017's allocation):** *"Slot allocation is CID allocation's mechanism on
a second namespace … a slot is another field on the same allocation, not a
new subsystem"*, and *"Reconcile ([ADR-017](DECISIONS.md#adr-017)) gains
a slot field"*, are
superseded by [ADR-035](DECISIONS.md#adr-035) §5: a slot is the lowest
`kk` with no `owner` in the runtime tree, and a fixed AppVM needs no
ADR-017 record for its slot. This is the operator's ruling R62 of
2026-09-28 ([ADR-037](DECISIONS.md#adr-037)'s note of that date). The text
above is not edited.

**Revision note (2026-09-29, § *Decision* — who programs the AppVM end of
a link):** *"NETCFG then programs the `/32` inside each guest exactly as it
does today"* is superseded **for the AppVM end** by
[ADR-038](DECISIONS.md#adr-038), accepted on 2026-09-29. katmate-init
configures the guest from typed `km.*` kernel command-line parameters
before `vm-agent` starts: its `/32`, an on-link default route via
`10.100.1.1`, and the resolver `10.100.1.1`. NETCFG programs **netVM's
end** of the link only, and it stays absent in `vm-agent`. On the AppVM
side the sentence never had a mechanism
([ADR-035](DECISIONS.md#adr-035) § *Dependencies surfaced*, first item,
and its note of 2026-09-28, R72). This note is part of the documentation
ADR-038 requires on acceptance. The text above is not edited.

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

**Revision note (2026-09-14, § *Gates*, §6 and the gate table of the 2026-09-12
note — no frame has ever been shown to cross a slot on its own destination
address, and G5b's traffic clause is rewritten around that):** three read
sessions were run on MINIS on **2026-09-14**, on the netVM run by
`katmate-pool@netvm.service` since the host boot of 2026-09-05 20:10:29 and
unrestarted since 2026-09-12 09:59:37 CEST. Reports outside the repository, all
of 2026-09-14: `~/Claude.assistent/harvest-report.md`,
`~/Claude.assistent/promisc-report.md` and
`~/Claude.assistent/mcast-read-report.md`. **Five findings, appended once rather
than as five notes.** Exactly one state change was made across the three
sessions — `IFF_PROMISC` on `km00`, set at 09:58:29 and cleared at 10:18:44,
both halves confirmed by read-back (`promisc-report.md` § 2, § 6) — and no code,
no unit, no sysctl and no ADD or REMOVE.

**1. The condition under which every measured delivery across a slot was taken,
and G5b's traffic clause rewritten around it. This is the substantive finding.**

**No frame has ever been shown to cross a slot on its own destination address.
Every measured delivery across a slot was into a receiver with `IFF_PROMISC`
set, and the same pair was measured failing without it.**

The readings, both directions, at both flag values, with the slot-00 guest rows
beside them. **The table is the whole of the argument.**

| sender → receiver | receiver's flags | result | source |
|---|---|---|---|
| peer QEMU → netVM QEMU | `km00` **0x1003** | **nothing arrived** — the peer's guest handed **11** frames to its device and `km00 rx_packets` read **0 → 0** with **RX zero in every column**: not arrived-and-dropped, not arrived-with-errors. Neither socket had anything queued | `adr035-g5b-v3-report.md` § 7.1 (2026-09-09) |
| peer QEMU → netVM QEMU | `km00` **0x1103** | **delivered** — `km00 rx` 0 → **10**, **796 bytes**, reconciling exactly with the peer guest's own `eth0 tx=10`, error columns 0. *"Two independent instruments, on opposite sides of two QEMUs and a host socket, agree exactly"* | `g5b-rxfilter-report.md` § 2.5.1 (2026-09-12) |
| netVM QEMU → peer QEMU | peer `eth0` **0x1003** | **nothing arrived** — netVM's guest handed **5** more frames to its device (`km00 tx` 6 → 11) and the peer's `eth0 rx` read **0 at every one of 31 readings**, and 0 at every one of up to **3,475** readings over that peer's 4.8-hour life | `adr035-g5b-v3-report.md` § 7.1; `g5b-matrix-report.md` § 3.1, § 4 (2026-09-09) |
| netVM QEMU → peer QEMU | peer `eth0` **0x1103**, promiscuous from its own `/init` | **delivered** — `km00 tx_packets` **57** equals the guest's `eth0 rx` **57** absolutely, not merely by delta, and the two were caught rising 56 → 57 together | flag `g5b-restart-report.md` § 1.3; `g2-add-report.md` § 5.2; `harvest-report.md` § 1.3, § 1.6; `promisc-report.md` § 5.4 |
| guest on slot 00 → netVM | `km00` **0x1003** | **not counted** — one emission at **09:09:59.965 CEST**, `km00 rx` **7 / 490 B** unmoved when read at +29 s and +181 s, `errors`/`dropped`/`missed` all 0 | `harvest-report.md` § 1.4, § 1.5 (2026-09-14) |
| guest on slot 00 → netVM | `km00` **0x1103** | **counted** — one emission at **10:06:48.513 CEST**, `km00 rx` 7 → 8 and 490 → 560: **+1 packet and +70 bytes**, error columns 0 throughout | `promisc-report.md` § 0, § 5.4 (2026-09-14) |

**The flag is the only difference in each pair.** `IFF_PROMISC` changes nothing
but the destination-address filter, so in rows 5 and 6 — same emitter, same
interface, same 70-byte frame size, same run of the same netVM — **the
destination filter is the whole of the difference**. Rows 1 and 2 are the same
two processes' successor designs, differing in **one line** of the peer's
`/init` (`ip link set "$n" promisc on`), confirmed by diff rather than by
assertion (`g5b-rxfilter-report.md` § 1.1: 59 → 60 lines, same kernel, same
busybox, same command line).

**What is NOT claimed. Nothing here says the transport does not carry. It
carries, under promisc.** Rows 2 and 4 are two QEMUs at both ends of a host
`AF_UNIX` `SOCK_DGRAM` pair, and each reconciles frame for frame. **What is
unshown is addressed delivery** — a frame accepted because it was addressed to
the receiving interface, rather than because the receiving interface was
accepting everything. Two further bounds, so the table is not read as more than
it is: the 2026-09-09 rows cannot say whether either QEMU wrote a datagram to
the peer path at all, which that session states as its own limit
(`adr035-g5b-v3-report.md` § 7.2, against ADR-033's open `EAGAIN` item); and for
the guest → netVM direction **the 2026-09-14 promisc reading closes exactly that
gap** — the frames do traverse the socket pair, QEMU and the virtio device and
arrive at `km00`, so **the loss is at the device's address filter and not
upstream of it** (`promisc-report.md` § 0, § 9.2).

**This ADR's gate table of 2026-09-12 publishes rows 2 and 4 without the
condition, and the row is corrected by this note rather than edited.** Its
**G5b** row records *"Peer → netVM was taken **before** the restart … `km00
rx_packets` 0 → 10 and then 12, reconciling exactly"* and *"NetVM → the guest on
slot 00 was taken **after** the restart … the guest's `eth0 rx` rose 0 → 6 →
11"*, and names no flag in either case. **A published result whose enabling
condition is unpublished is the expensive kind of wrong:** the next reader takes
the row as proof that the path carries the frames a slot's tenant would send,
and it does not. Before this note the word `promisc` appeared nowhere in
`docs/DECISIONS.md` or in `state.md`, which is why the condition is stated here
in full rather than by cross-reference.

**The operator's ruling of 2026-09-14 on what the clause measures.** G5b's *"a
re-issued ADD restores traffic in both directions"* measures whether **the
guest's netdev carries**, not whether the slot carries. Both ends are a guest's
`eth0`; the path therefore includes QEMU's `-netdev dgram` on the sending side
and virtio injection on the receiving side. **Under that reading the clause is
NOT taken, and the fixture measurements of slots 01 and 02 do not take it** —
they put a plain socket at one end, as ADR-033's link-m2 did in both of its own
directions, where the reverse frame was sent *"out of the very socket bound at
`h.sock`, by the receiver itself"* (`link-m2-report.md` § B1.2, § B2.5).

**The rewritten clause. G5b's traffic clause requires a directed frame —
addressed to the netVM slot's own MAC `52:54:01:00:00:kk`, emitted when the
measurer chooses — observed at both ends, in both directions, under one ADD**,
with the receiving interface's flags read at the moment of each reading. **It is
now the only gate of this ADR that would show addressed delivery, and that is
why it is written this way:** rows 1, 3 and 5 above are the destination filter
refusing frames, and every row that delivered had that filter switched off at
the receiving end.

**Why the emitter must be the measurer's, recorded because the requirement is
not fussiness. Three arcs have been measured with an uncontrolled emitter, and
each cost sessions spent explaining the instrument rather than the phenomenon:**

- **`ip=dhcp` as the emitter — which does not exist on this initrd.** Measured
  false in **63 consecutive boots**: `init-premount` completes, no networking of
  any kind occurs, and the kernel reports `ip=dhcp` as an unknown parameter
  passed to user space (`adr035-g5b-report.md` § 12.3, § 15, 2026-09-08). The
  peer's device side was never the problem; what was missing was something that
  executed a link bring-up and stayed alive.
- **The unprompted MLDv2 report to `ff02::16`, which clusters around link
  events.** *"Every frame this arc has sent is an unprompted MLDv2 report"*
  (`g5b-rxfilter-report.md` § 0, carried from `g5b-matrix-report.md`), and the
  matrix session took its ten frames **within 0.3 s of a link bring-up**. When a
  later session performed no link event, netVM emitted nothing at all — `km00
  tx_packets` stood at **100** at both ends of the window — so the netVM → peer
  direction was **not exercised**, and a receiver reading zero measures nothing
  about the receiver (`g5b-rxfilter-report.md` § 2.5.2, § 2.6).
- **The hourly guest emission of 2026-09-14.** The slot-00 peer transmits about
  **once every 3,670 s**, derived from the step between `tx` transitions
  (681–786 readings, ~733) and two dated anchors 26,926 readings apart
  (`harvest-report.md` § 1.2). The first window opened on it was **186 s**, about
  a twentieth of that period, and a flat counter across it is evidence of
  nothing (§ 1.1). The finding of § 1.5 exists only because a second window of
  **3,480 s** was opened afterwards.

**An uncontrolled emitter is not an instrument.** Nothing above is a criticism of
those sessions' readings — each reported the idleness correctly and refused to
name a direction failed — and the cost fell on the arcs, not on the reports.

**2. The receive-path finding on slot 00, with its bounds, and the control that
says where the cause is not.**

**The cause is named: the receive path rejected the frame on its destination
address** (`promisc-report.md` § 0, rows 5 and 6 of finding 1's table). The
guest's own kernel announced both transitions — `entered promiscuous mode` and
`left promiscuous mode` — which is an independent witness to the change from the
driver rather than from the tool that made it (§ 2, § 6).

**What is NOT known, and is written as not known. The bytes of none of the eight
frames `km00` has ever counted have been read.** Slot 00 has no fixture and
cannot have one while its `appvm` node is held by the peer's QEMU — that being
the point of slot 00 — so nothing has read a destination address, an ethertype
or a payload (`promisc-report.md` § 8, § 9.4). What is known is the length, and
the length does not discriminate: **490 / 7 = 70 exactly and 560 / 8 = 70
exactly**, so the seven accepted without the flag and the eighth that needed it
are **the same size** (§ 1.1). They therefore differ in destination address and
in nothing this project has measured. **Which address, and whether the
difference is two frame types or a change of filter state across the 48 h 07 m
between `km00`'s counter epoch — netVM's QEMU start of 2026-09-12 09:59:37
CEST — and the eighth frame of 2026-09-14 10:06:48.513 CEST, is unmeasured and
undated.**

**One arithmetic bound belongs beside that, so the eight are not read as the
whole population.** `km00`'s counters begin at 09:59:37, the peer's at 09:58:06,
and the slot-00 ADD raised `km00` only at 12:47:42: **at most 60 and at least 43
guest transmissions fall inside `km00`'s interval, and `km00` counted 7**
(`harvest-report.md` § 1.3). Most of the emitter's frames were not counted
either; only the eighth is dated against a known flag state. **And the
non-delivery is not a single instance:** the same direction with `km00` at
`0x1003` was measured on **2026-09-09** on a different netVM process, where 11
emitted frames produced `RX` zero in every column
(`adr035-g5b-v3-report.md` § 7.1).

**The control, and it is the sharp half: the difference is not in
configuration.** `km00`, `km01` and `km02` carry **identical IPv6 configuration
across all 61 keys** of `net.ipv6.conf.<iface>.*` and **identical multicast
group membership apart from their own solicited-node groups**, which differ by
construction because each derives from that interface's own address
(`mcast-read-report.md` § 1, § 6, § 7). **`ff02::2` and its link-layer form
`33:33:00:00:00:02` are joined by none of the three**, and **IPv6 forwarding is
0 on every interface, on `all` and on `default`, while IPv4 forwarding is 1**
(§ 1, § 5). **Not one IPv6 value in that reading comes from a file:** no file in
the sysctl search path names `ipv6` at all, `/etc/sysctl.conf` and
`/run/sysctl.d/` do not exist, and the sole `/etc` file
`30-netvm-forward.conf` sets exactly one IPv4 key (§ 4.1, § 6). **So the two
slots whose counters reconcile exactly and the slot whose counters do not are
byte-identical in every one of those readings**, and nothing about the
difference is explained by configuration this project wrote. No further
conclusion is drawn, and no hypothesis about the seven accepted frames is
stated, confirmed or ruled out (§ 9).

**3. `rp_filter` — its provenance, and the arithmetic consequence for how any
change is written.**

**Read, never set:** `net.ipv4.conf.all.rp_filter` = **0**;
`net.ipv4.conf.default.rp_filter` = **2**; **every one of the sixteen slots,
`lo` and the uplink `enp0s4`** = **2** (`harvest-report.md` § 4.1). There is no
interface answering to *"internal"*: the pool replaced the single internal
device with sixteen `dgram` slots, so `km00`…`km0f` **are** the internal
segment, and `ip -br link` lists nothing else besides `lo` and the uplink
(§ 4.2, § 3.1).

**Exactly one file in the sysctl search path names `rp_filter`, and it is a
vendor default:** `/usr/lib/sysctl.d/50-default.conf`, md5
`0b8b57132bc965929ded2f24878c7707`, whose own header says *"This file originated
from systemd"*, carrying three lines —
`net.ipv4.conf.default.rp_filter = 2`, the glob
`net.ipv4.conf.*.rp_filter = 2`, and the exclusion
`-net.ipv4.conf.all.rp_filter` (§ 4.3). **It is neither a kernel default — the
kernel's own is 0 — nor a decision taken on this project: no KatMate artefact
mentions `rp_filter` anywhere.** The three lines also explain the shape of the
reading, which no earlier session had the provenance to explain: the glob is why
sixteen slots, `lo` and the uplink all read 2 with nothing enumerating them, and
the exclusion is why `all` alone stands at 0.

**The arithmetic consequence: the effective value is `max(all, iface)`, so
setting `all = 1` changes nothing** — `max(1, 2)` is still 2. **Any change must
write the per-device or `default` knobs.** Two properties of the mechanism
follow from the file rather than from argument (§ 4.4): **a glob has to be
overridden by a glob or by sixteen assignments**, since an override naming only
the assigned slots leaves the rest at 2 and slots are assigned dynamically; and
**`enp0s4` is inside the same glob**, so a glob-shaped override changes the
filtering of the one interface here that faces a real network. Whether that is
wanted is a tier-model question and is not answered by a reading.

**Recorded as UNMEASURED, because it is a precondition of the change and no
session has read it: whether `systemd-sysctl` runs before or after udev renames
the sixteen virtio devices to `km00`…`km0f`.** Per-device and glob entries take
effect only on interfaces that exist when they are applied; `default` affects
interfaces created afterwards. **The reading available cannot settle it**, by
arithmetic: `default` is 2, so an interface created after `systemd-sysctl` ran
would inherit 2 regardless, and the observed 2 on all sixteen slots
discriminates neither order. That is a reason the question is open, not a reason
to treat it as answered. §8's rename landed as sixteen exact-match `.link` files
in the netVM build of 2026-09-05, so the ordering is between two systemd
components and is readable at the next boot.

**4. The cross-slot neighbour entry outlives the release of the slot that caused
it.**

Planted by the ARP form of G2's refusal half — the frame sent onto slot 02 at
**12:49:36 CEST** on 2026-09-12, as finding 6 of the 2026-09-12 note records
from `g2-add-report.md` § 5.4 — the entry
`10.100.1.17 dev km02 lladdr 52:54:01:00:01:02` was **still present 43 h 29 m
later**: **STALE**, `lladdr` unchanged, `probes 0`, `updated` equal to `used`,
**never re-probed once** (`harvest-report.md` § 3). netVM's whole neighbour table
holds three entries, the third being the uplink's gateway on the home LAN.

**`km01`'s silence is the sharper half.** `10.100.1.17` is slot **01**'s peer
address, and slot 01 was left released by G4: `km01` carries **no IPv4 address
and no neighbour entry at all**, while still `UP`, since REMOVE does not clear
`IFF_UP` — G4's measured end state, standing 43 hours on (§ 3, § 3.1).
**The only place `10.100.1.17` is resolvable in netVM's neighbour table is on
the wrong interface, mapped to the wrong tenant's MAC.**

**What it changes.** Finding 6 of the 2026-09-12 note measured that the
contamination *outlives the frame that planted it*. **What this reading adds is
that it outlives the release of the slot that caused it, and would still be
standing when that slot is reinstalled** — 43½ hours so far, with no mechanism
in evidence that would end it. **`rp_filter` does not address this**: finding 6
already records that the ARP form measures what `rp_filter` does not govern.
**It belongs to §6's release semantics**, where §6's *"delete the neighbour entry
for peer `k`"* has to name an interface and the entry that most needs deleting
sits on a different one from the slot being released. That remains a proposal
for the code pass and is not decided here.

*Three readings date the same frame to 12:49:35, 12:49:36 and 12:49:37 — the
send itself (`g2-add-report.md` § 5.4) and two independent derivations from
neighbour ages taken 37 hours apart (`g3-g4-console-report.md` § 3.1a;
`harvest-report.md` § 3). The two-second spread is the arithmetic of the
derivations and is load-bearing nowhere.*

**5. The gate table, updated for what 2026-09-14 changed and for nothing else.**

| gate | change on 2026-09-14 | evidence |
|---|---|---|
| **G5b**, traffic clause | **still not taken**, and **rewritten** as finding 1 words it: a directed frame to the slot's own MAC, emitted by the measurer, both ends, both directions, one ADD. The **guest → netVM** direction has been **ATTEMPTED** and produced a **finding rather than a measurement** — one emission inside a 3,480 s window with `km00`'s receive counters unmoved, the cause then named by the promisc discriminator as the destination filter. **It remains untrue that one ADD has been shown to carry both directions of one slot** | `harvest-report.md` § 1.4–§ 1.6; `promisc-report.md` § 0, § 9.5 |
| **G2**, refusal half | **status unchanged; gains the slot-02 control** that `g3-g4-console-report.md` § 5.4 named as the one frame that would settle its own confound. One gratuitous ARP at 08:21:22.006 CEST moved `10.100.1.18 dev km02` from **FAILED with no `lladdr`** to **STALE with one**, its `updated` age of 36 s landing on the send to the second; the echo at 08:22:25.998 drew an **ICMP echo reply at fixture 02 one millisecond later, from `52:54:01:00:00:02` — `km02`'s own MAC** — carrying the request's id, sequence and payload. **Slot 02 was never damaged: the missing reply of 2026-09-12 was the passive fixture's own silence**, in the direction § 5.4 predicted | `harvest-report.md` § 2.1, § 2.2 |

**No other gate's status changes**, and the 2026-09-12 note's table stands for
every other row: G1 and G5a taken, G3 not performable until §7 lands, G6b not
performable until §9 lands, G4's confirmation at three of six rows.

**Status is unchanged: PROPOSED**, for the reason the 2026-09-12 note already
records and which nothing on 2026-09-14 touched: **three of this ADR's decisions
have no implementation** — §6's supersession, its `link_down` and its conntrack
flush; §7's duplicate count; §9's retirement of `KM_MAC_INT` and its two new
AppVM scalars — and §5's `ExecStopPost=` and the assignment-time ownership of
the slot directories are likewise unimplemented. **No code was written, no unit
was changed, no sysctl was set and no ADD or REMOVE was issued by any of the
three sessions of 2026-09-14**, and every change named in this note is a
proposal for the code pass.

**Revision note (2026-09-15, §5 — the ACL mechanism is measured, and
`RuntimeDirectory=` is measured to undo assignment-time ownership):** Taken on
MINIS in two passes on 2026-09-15, against systemd on Arch, on the boot of
2026-09-05. Reports outside the repository: `~/Claude.assistent/acl-report.md`
and `~/Claude.assistent/acl-report-b.md`; the second pass re-took three gates
the first brief had written defectively. No code was written, no unit was
changed, no ADD or REMOVE was issued, and `/run/katmate/link/` was not entered.

**1. POSIX ACLs are available where the tree lives.**
`CONFIG_TMPFS_POSIX_ACL=y` and `CONFIG_FS_POSIX_ACL=y`; `/run` is `tmpfs`. A
named user entry and a default entry land on a directory there with
`mask::rwx`, and the same `setfacl` is refused `Operation not supported` on
`proc`, `sysfs`, `cgroup2` and `vfat`.

**2. `bind()` applies the umask, and a default ACL does not override it.** Two
runs, same directory, same default ACL, uid 61001 binding: under `umask 0007`
the node is `0770` with `mask::rwx` and the named `rw` entry fully effective;
under `umask 0022` it is `0755` with `mask::r-x` and the same entry reading
`#effective:r--`. A `UMask=` on both QEMU units is therefore load-bearing, and
its absence fails silently — `getfacl` shows a correct-looking entry while the
peer cannot send.

**3. Removing a named ACL entry reaches a running process.** One sender,
uid 61002, pid 1313424, unchanged across three permission states, against one
receiver holding a bound node: a datagram is delivered; after `setfacl -x` the
**same process** is refused `EACCES` and nothing arrives; after the entry is
restored the same process delivers again. With ADR-033's measurement that
`remote.path` is resolved per send, removing a named entry is an immediate and
reversible cut of one slot's traffic, in both directions, with no signal
delivered to either QEMU and no restart of either.

**4. The sticky bit refuses an unlink that directory write permission allows.**
With uid 61002 holding an effective `rwx` on the directory at `mask::rwx`, the
unlink of a root-owned `owner` is refused `EPERM` while the bit is set and
returns `rc=0` with the file gone once the bit is cleared and the same ACL
re-applied; the same uid unlinks its own bound node in either case. A slot
directory that grants an AppVM write and does not carry `+t` therefore lets that
AppVM delete its own `owner` and make an occupied slot read as FREE — §5's
*"absence is freedom"* read as a grant.

**5. `chmod` on an object carrying an access ACL rewrites the ACL mask.**
Measured as an accident: `chmod 1710` applied after `setfacl` left `mask::--x`
and a named `rwx` entry reading `#effective:--x`, so both halves of that gate
were decided by the mask before the sticky bit was reached. The rule this puts
on every writer of this tree: **mode first, ACL second, `getfacl` read-back
third** — any `chmod` invalidates every ACL applied before it, including one
issued by the launch daemon's own reconcile.

**6. `RuntimeDirectory=` restores its own ownership and mode at every start, and
strips ACLs with them.** G5a (2026-09-07) confirmed that the directive creates
the tree and that `RuntimeDirectoryPreserve=yes` keeps it across a **stop**;
both hold and neither is disturbed here. What is new is the far side of a
**start**. With the unit's directory chowned to a non-root uid, `chmod 0770`,
carrying an access and a default ACL, and with a socket node bound inside it by
that uid, a `systemctl restart` leaves the directory at its inode and the node
at its inode — and returns **both** to `root:root`, restores the directory to
`0755`, and leaves no named entry, no `mask::` and no `default:` entry on
either. The ownership rule of the 2026-09-07 revision note — *"the launch daemon
sets ownership at assignment and returns it at release"* — does not survive a
netVM restart under this directive, and no ACL placed beside it would either.

**The choice §5 gates is therefore reopened rather than settled.** §5's
fallback — *"a T4 helper in `ExecStartPre=`"* — creates the tree with the same
reboot-independence G5a bought, and if it is written to be idempotent and
non-destructive (create when absent; never `chown` or `chmod` an existing
directory) it re-asserts nothing at start. Under it a directory's default ACL
survives a netVM restart, and the netVM's QEMU — which `unlink`s before
`bind`s — receives a correctly permissioned `netvm` node by inheritance, with no
daemon involvement and no re-apply pass. Keeping the directive instead obliges
the launch daemon to re-apply ownership and ACLs after every netVM start, under
the hazard in 7. **Neither is decided here.**

**7. The reset is not ordered against the return of `systemctl restart`.** Two
readings seconds apart in one script disagree: `ls -ldi` prints the mode already
at `0755` with the owner still the assigned uid and the ACL marker present,
while `getfacl` on the next line reports `root:root` and no ACL at all. Nothing
in the run timestamps either reading and no instrument attributes the change to
an actor. **Unresolved**, and recorded because it bears on 6: a daemon that
re-applies attributes on seeing the unit active may be writing into a reset that
has not finished, so any such re-apply must read back and repeat rather than
fire once.

**8. What the pool's assignment step looks like under 1–7 — proposals for the
code pass, not decisions.** The slot directories exist before any assignment,
whichever mechanism 6 settles on, so **`mkdir` cannot be the claim**; §5's
*"pick the lowest `kk` with no `owner`, write `owner`"* is check-then-write, and
`open("owner", O_CREAT|O_EXCL)` is the only atomic claim the layout as written
offers. Order follows from 5 and from the 2026-09-07 ruling that occupancy and
permission are one act: **assign** — `owner` by `O_EXCL`, then mode, then ACL,
then `getfacl` read-back, then start the unit; **release** — NETCFG REMOVE, then
the ACL removed, then `owner` unlinked. Both orders are chosen so that an
interruption leaves a slot that reads occupied and is not traversable, never one
that reads free while still carrying the previous tenant's grant. And because
the daemon must write the ACL before the AppVM's unit starts, it must know that
uid in advance, which `DynamicUser=` cannot supply; a uid derived from the
already-allocated CID would add no third allocator. Whether `User=` accepts a
bare numeric uid absent from `passwd` is untested.

**9. Not shown.** Nothing was measured under `/run/katmate/link/`; its slot
directories' modes, owners, masks and default ACLs are unread. The subject
throughout is a fifty-two-line AF_UNIX `SOCK_DGRAM` fixture, not QEMU, and
whether QEMU's own `bind()` and `sendto()` meet these permissions identically is
untested. Uids 61001 and 61002 are absent from `passwd` and every run used
`setpriv --clear-groups`, so no supplementary group, login session or PAM path
was in play. Every positive half was taken on `tmpfs`; none on `ext4`. No reboot
occurred, and nothing was read back on a later boot. No timing, latency,
ordering or concurrency property was read, and 7 is the one place that shows
this session cannot read one. GA5b created one node in one directory, not
sixteen. What produced the reset in 6 is unread: no `strace`, no journal, no
systemd source was consulted.

**Revision note, 2026-09-20 — §8's prohibition on interface names is
narrowed, and the name becomes load-bearing. Ruled by the operator.**

**§8 may no longer be read as forbidding a per-slot binding in nft.** Its
sentence *"nft references the segment or the `/28` and never an interface
name"* was written to stop an interface name standing in for topology or
carrying an instance's identity. A per-slot rule does neither: `km00`…`km0f`
are **pool constants in T4, functions of the index alone**, identical in
every installation, and a ruleset built on them **still does not change as
AppVMs come and go** — which is what `docs/ARCHITECTURE.md` § *Networking*
actually requires when it says *"never a per-AppVM rule"*. **A per-slot rule
is not a per-AppVM rule.**

**The citation is corrected.** §8 cited `ARCHITECTURE.md` § *Networking* for
the wording *"never an interface name"*; that document does not contain it,
and its own sentence — *"forward limited to segment ↔ `proton`"* — describes
a rule that names an interface. `ARCHITECTURE.md` is **unchanged and
uncontradicted**; what was wrong was §8's account of it. This closes the
divergence raised on 2026-09-20 by the `auditfix-readpass` session.

**What this costs, and it is stated rather than absorbed: the name is now
load-bearing, and §8's sentence that it is not no longer holds.** §8 says
*"if the rename does not happen, nothing programmatic changes, and an
operator reads the last octet instead."* Under the finding-12 guard a failed
rename stops **all** pool traffic at once, by design: the sixteen pairing
rules match nothing and every pool-sourced packet falls to a counted drop. A
security control that goes inert when its precondition fails is worse than
one that stops the traffic, so the failure is deliberate and loud. **NETCFG
still selects by MAC (ADR-025, untouched), and the invariant that netVM's
*uplink* interface name is not normative is untouched** — that name is
bus-derived and has moved across sessions; `kmkk` is a function of a literal
T4 constant through sixteen exact-match `.link` files, and the two are not
the same mechanism.

**Why a name at all, when this project prefers MACs.** The pool has no MAC to
match on at ingress: `52:54:01:00:00:kk` is netVM's **own** side of the link,
while the frame's `ether saddr` is the AppVM's instance-derived identity MAC,
which is not a pool constant. §3 puts the same `10.100.1.1/32` on every link,
so the **interface is the only discriminator the pool has** on a per-packet
basis. That is the whole of the argument for the ruling.

**Measurements this rests on**, both 2026-09-20
(`auditfix-liveread-report.md` §§ 2.5, 2.6): `iifname` is a **per-packet
string comparison** — `nft -c` accepts `iifname "nosuchdev0"` (exit 0) while
`iif nosuchdev0` is rejected with *"Interface does not exist"* (exit 1), both
`lo` controls passing — so a per-slot ruleset **loads whether or not the
sixteen interfaces exist or have been renamed, and the fix is therefore
independent of open problem #33**; and the rename **fires**, 16 of 16, each
name exactly once, no gaps and no duplicates, on the boot of 2026-09-12. The
`iifname` form is required and the `iif` form is refused: `iif` resolves an
ifindex at load time and would fail the entire load if a single slot were
absent. Both were measured under `nftables v1.1.7` **on the host**; netVM's
version is unread.

**A consequence for the build, which follows from the name being
load-bearing:** the rename becomes a **build gate** on the netVM image —
sixteen names, counted — so that a lost or mismatched `.link` file is caught
before the image is used, rather than presenting later as *"nothing works"*
three steps from its cause. The in-guest counter that would name the cause is
unreadable without the console while `netvm-agent` has no `RUN`.

**What this note does NOT cover, named here so the ruling is not read as
closing audit finding 12: the ARP half.** `table inet filter` does not see
ARP, so a forged **neighbour entry** survives a ruleset that refuses a forged
**packet** — and that is measured, not hypothetical (this ADR's note of
2026-09-14, finding 4: `10.100.1.17 dev km02`). Coverage needs `table netdev`
ingress or `table arp`, and the probe that would establish how such a chain
binds its device is **unresolved**: `nft -c` accepts a netdev ingress chain on
an absent device and accepts the control too, so `-c` cannot settle it.
Carried as an open problem in `state.md`.

**Status: the candidate ruleset is written and ungated.** It is at
`~/Claude.assistent/nftables-f12-candidate.conf`, outside the repository, and
it changes one thing — a `slot_guard` chain of sixteen `(iifname, ip saddr)`
pairs plus two counted drops, jumped from `input` and `forward` **above**
their `ct state established,related` rules, because a conntrack lookup that
runs before the admission test *is* the poisoning the audit found. No policy
rule is altered, `30-netvm-forward.conf` is untouched, no reverse-path check
is added — a per-`kmkk` sysctl is unavailable in any case, `systemd-sysctl`
running before the rename — and nothing logs, nft logging inside netVM being
a guest-driven write into the host journal.

**Two gates, before anything is installed.** (a) `nft -c -f` on the candidate,
**as root** — unprivileged `nft -c` fails on every input, valid or not — on
the MINIS host **and** inside netVM, with `nft --version` read on both sides;
the guest's version is currently unknown and the host result does not carry
until it is. (b) A live refusal measurement: with the candidate loaded, a
frame sent from slot *b* claiming slot *a*'s peer as its source is **dropped
and counted**, while the same traffic on its own slot is delivered — the same
pairing ADR-035 §3's G2 names, taken here against the ruleset rather than
against the kernel. Numbering is left to the § *Gates* block, which this note
does not edit.

**Revision note (2026-09-26, the 2026-09-20 note — netVM's `nftables` version is
read, and it differs):** the 2026-09-20 note says *"netVM's version is
unread"*. It is **`nftables v1.1.3`**, not the host's 1.1.7
(`net-up-report.md` § 19.2 row 1, § 19.3 item 1). So that note's P1 result —
`iifname` accepted and `iif` refused on an absent interface, measured on the
host — **does not carry into netVM by version identity**. Gate (a) of that
note, `nft -c -f` on the candidate as root **inside netVM**, is still untaken.

**Revision note (2026-09-27, §5 and §9 — the pool is in the shipped unit, and
§9's retirement is half done):** this note records rulings and measurements. It
changes no decision.

- **§5's *"literal in the netVM template"* is now true of the shipped unit.**
  `katmate-sys-driver@.service` at `a36bdb2` carries the sixteen
  `-netdev dgram`/`-device virtio-net-pci` pairs with `%i` paths, the §2
  MACs, and `RuntimeDirectory=` naming the sixteen slot directories with
  `RuntimeDirectoryPreserve=yes`. They are transcribed byte-for-byte from the
  scaffolding template `katmate-pool@.service` (`1d727b25…`), which ran under
  G1–G5. Installed on MINIS and started on 2026-09-27: 16 `dgram` netdevs in
  the argv, 0 `tap,`, and 16/16 `netvm` nodes bound by the QEMU process
  (`pool-fold-report.md` §§ 2.6–2.8). The pool unit has left `/etc`, and
  **one unit now starts netVM** (operator ruling, 2026-09-27: open problem
  #39, option (b)). The measurement of the 2026-09-12 note, finding 5, that
  the installed templates are exactly `katmate-pool@.service` and
  `katmate-sys-driver@.service`, stands as a measurement of that date.
- **§9's retirement of `KM_MAC_INT` is half done.** The unit no longer reads it:
  the `int0` tap device and its `mac=${KM_MAC_INT}` are gone, and host-side
  `tap-int0` was removed on 2026-09-27. The generator still emits the key for
  `sys`, with no consumer. Because the key is not in the `sys-driver`
  required-key set, nothing fails (`pool-fold-report.md` § A7). **Ruled
  2026-09-27:** the `sys` branch is removed in its own commit at the AppVM
  step (networking arc step 4); the `app` branch stays, per §9. §9's
  `KM_NETVM`/`KM_SLOT` half is unchanged by this note.
- **§5's `ExecStopPost=` is still unimplemented.** The folded unit carries
  none. The hijack window of the 2026-09-12 note, finding 7, applies to
  `katmate-sys-driver@.service` exactly as it did to the pool unit.

**Revision note (2026-09-27, the 2026-09-20 note's build gate and
§ *Consequences* — ADR-037's implementation):** this note records what exists.
It changes no decision.

- **The rename build gate of the 2026-09-20 note exists** (`0f304c9`,
  [ADR-037](DECISIONS.md#adr-037) R12). It is a **file check**: the image must
  carry exactly 17 `*katmate*.link` files with the expected content, the
  sixteen `70-katmate-slot-kk.link` and `60-katmate-uplink.link`. It **passed
  on a real image** on 2026-09-27: *"Build gate OK: 17 katmate .link files — 16
  slots, and the uplink on pci-0000:00:04.0"*. **The note's *"sixteen names,
  counted"* is met by counting files, not names, because a chroot renames
  nothing.** The names are checked at runtime by ADR-037's G2, which passed
  on 2026-09-27 with 16 slots on 16 distinct slot `.link` files and one
  `uplink0`.
- **§ *Consequences*, *"Open problems #23 and #27 close in the pool's
  commits"*, did not hold** (rp D9). #27 closed in the ADR-037 rebuild
  (`098e868`, R24): the agent unit is a tracked file in the conf tree, and
  the baked unit is that file. It was not closed in the pool's commits. **#23's
  `ExecStopPost=` is still unimplemented**, as this ADR's previous note says.
  The shipped `katmate-sys-driver@.service` carries none.

**Revision note (2026-09-28, the 2026-09-20 note's gates (a) and (b) — gates
F12a and F12b of the finding-12 guard):** this note defines two gates. It
takes neither, and changes no text above. **Both are untaken.** The rulings
behind them are [ADR-037](DECISIONS.md#adr-037)'s note of 2026-09-28 (R47–R56;
the gates are R52 and R53, and R56 places them here). They are named after
gates (a) and (b) of this ADR's note of 2026-09-20, because § *Gates* is body
and is not edited. They are the gates of the finding-12 slot guard,
networking arc step 3a.

- **F12a (R52)**, after the rebuild that bakes the guard, in the guest as
  root through the dev console: `nft --version`, `nft -c -f
  /etc/nftables.conf`, `systemctl is-active nftables`, and `nft list chain
  inet filter slot_guard`. `build/netvm.sh`'s `nft -c -f` on the baked file
  in the build chroot is a build preflight, **not** this gate: it checks
  against the build host's kernel.
- **F12b (R53)**, a live refusal against **both** `input` (DNS to
  `10.100.1.1`) and `forward` (ICMP echo to `1.1.1.1` via `uplink0`), with
  two fixture peers on two slots (NETCFG ADD). Each row names the counter it
  must increment:
  1. a pool source on the wrong slot (slot *b* claiming slot *a*'s peer) →
     the R50 counter;
  2. `10.100.1.1`, and an off-segment source (TEST-NET), on a slot → the
     rule-18 counter;
  3. IPv6 on a slot → the R49 counter;
  4. a segment source on `uplink0`, sent from the MINIS host to netVM's
     uplink address → the R50 counter. Control: the same packet with source
     `10.3.1.3` leaves that counter unchanged.

  **Positive control, in the same run:** each peer's true source on its own
  slot gets a DNS answer and an echo reply. The counters are read before and
  after through the console, and each row's increment equals the frames
  sent. `rp_filter` is read before and after (R51). The instrument is
  `g4peer.py` extended with a slot and a source parameter and an IPv6 frame,
  with a timestamp on every line.

**Finding 12 is the audit's, not this ADR's.** The note of 2026-09-12 has
**eleven** findings (*"Eleven findings, appended once"*), and the list ends
at 11. Finding 12 is counted in [ADR-036](DECISIONS.md#adr-036): netVM's
forwarding plane accepting the aggregate `10.100.1.0/24` with no per-link
binding. (`f12-readpass-report.md` D1, outside the repository.)

**Revision note (2026-09-28, correction to the note above — F12b row 2
splits, [ADR-037](DECISIONS.md#adr-037) R58):** this note corrects one row
of the gate definition above. It takes no gate. F12a and F12b are still
untaken. Row 2 was written without applying the chain order of ADR-037 R50:
the sixteen `return`s, then R49, then R50 (`iifname != "lo" ip saddr
10.100.1.0/24 counter drop`), then rule 18. `10.100.1.1` lies in
`10.100.1.0/24`, and a slot is not `lo`, so R50 drops it and rule 18 never
sees it. Row 2 is therefore replaced by:

- **2a.** `10.100.1.1` as the source, on a slot → **the R50 counter**;
- **2b.** an off-segment (TEST-NET) source, on a slot → **the rule-18
  counter**.

Rows 1, 3 and 4, the control of row 4, the positive control, the counter
reading, the `rp_filter` readings and the instrument are unchanged. A
fixture peer's own MAC is `52:54:01:00:01:kk`, as it was for every earlier
peer. `52:54:01:00:00:kk` is netVM's side of the slot (§ 2) and is only the
NETCFG ADD argument. That ruling is ADR-037's note of the same date, and it
is repeated here because it concerns this gate's instrument.
(`f12-impl-A-report.md` § 0.2, A1 and A2, outside the repository.)

**Revision note (2026-09-28, second correction — F12b row 2 becomes 2a, 2b
and 2c, [ADR-037](DECISIONS.md#adr-037) R59):** this note corrects the row
split of the note above. It takes no gate. F12a and F12b are still untaken.
A packet whose source is one of netVM's own addresses is expected to be
dropped by the kernel as a martian source at the input route lookup, before
any nft hook **[recall, unverified]**, so `10.100.1.1` may never reach the
R50 counter and cannot discriminate R50 (`f12-impl-A-report.md` § 5, item 1,
outside the repository). Row 2 is therefore replaced once more:

- **2a.** A non-pool **segment** source on a slot (`10.100.1.5` on slot 05)
  → **the R50 counter, +5**, and `answered=0`.
- **2b.** Unchanged: an off-segment (TEST-NET) source on a slot → **the
  rule-18 counter**.
- **2c.** `10.100.1.1` on a slot: an **observation row**, not a counter row.
  It passes if `answered=0` **and exactly one witness accounts for all five
  frames**: either the R50 counter **+5**, or the kernel's martian witness —
  `log_martians` enabled on `km05` for this row only, the journal naming
  `km05` and source `10.100.1.1` five times, together with `in_martian_src`
  in `/proc/net/stat/rt_cache`. The session report records which witness it
  was. Neither, or both partly: the session halts with both readings.

The rows run in the order 2a, 2b, 2c. Rows 1, 3 and 4, the control of row 4,
the positive control, the counter reading, the `rp_filter` readings and the
instrument are unchanged, except that the positive control is taken both
first and last (PC-1 and PC-2), and a failed PC-2 voids every refusal row
(ADR-037 R59's note).

**Revision note (2026-09-28, F12a and F12b taken — the finding-12 guard
gated):** this note records gate results. It changes no text above. The
gates were taken on MINIS on 2026-09-28 by the session f12-impl-B
(`f12-impl-B-report.md`, outside the repository, cited as B), on
`NETVM_BUILT=2026-09-28T17:38:12Z`, in the guest through the dev console.
The operator ruled **F12a PASS** and **F12b PASS**, every row as B's gate
table records it. The full table, with every counter reading before and
after, is B's *Gate table*; in short:

| Row | Sent | Counter, increment | `answered` |
|---|---|---|---|
| F12a | — | `nftables v1.1.3`; `nft -c` rc 0; `active`; 16 `return`s and 3 counted drops at 0 | — |
| PC-1 (02 and 05, DNS and ICMP) | 4 × 5 | none moves | 5 of 5, each |
| 1: 05 as `10.100.1.18` | 10 | R50 +10 | 0; listener on 02 `rx=0` |
| 2a: 05 as `10.100.1.5` | 5 | R50 +5 | 0 |
| 2b: 05 as `192.0.2.10` | 10 | rule 18 +10 | 0 |
| 2c: 05 as `10.100.1.1` | 5 | kernel martian witness: `in_martian_src` +5, five `log_martians` lines naming `km05`; R50 +0 | 0 |
| 3: 05, IPv6 echo to `ff02::1` | 5 | R49 +5 | 0 |
| 4: host → `10.3.1.172` as `10.100.1.5` | 10 | R50 +10 | `rx_from_target=0` |
| 4, control: as `10.3.1.3` | 10 | R50 +0 | `rx_from_target=0` |
| PC-2 (the four again, re-bound sockets) | 4 × 5 | none moves | 5 of 5, each |

Row 2c passed with the kernel martian witness, as R59 defines it. R51's
`rp_filter` reading held before the rebuild (old image) and after it:
`all` 0, and 2 on the other 19 of 20 conf dirs.

**Observed, each on one run and one image (B § 6, *recall items*):**
- Loose `rp_filter` passed every forged IPv4 source **except netVM's own
  address** to nft: an off-slot pool source on a slot (row 1), a non-pool
  segment source on a slot (2a), a TEST-NET source on a slot (2b), and **a
  segment source on `uplink0` (row 4)**. `in_martian_src` did not move, and
  the nft counter took the frames. This answers the open item of
  `f12-readpass-report.md` D18 (outside the repository) for that one run.
- A source equal to netVM's own `10.100.1.1` is dropped as a martian source
  before any nft hook (row 2c): R59's premise, observed.
- QEMU delivers to an `appvm` socket re-bound at the same path (PC-1's
  second run on each slot, every forged run, and all of PC-2).

**Not executed, and therefore not claimed (B § 6):** the failure paths of
[ADR-037](DECISIONS.md#adr-037) R52's build preflight and R48's read-back on
a real image (only their pass paths ran); and the optional
conntrack-shaped repeat of row 1, which is not in the gate.

**Revision note (2026-09-28, step 4 read — § 5, § *Dependencies surfaced*
and § *Questions* item 5):** this note records rulings and readings. It
changes no text above and takes no gate. The rulings are
[ADR-037](DECISIONS.md#adr-037)'s note of the same date (R60–R75); the
readings are the read pass behind them (`s4-readpass-report.md`, outside
the repository, cited as S), taken on the Acer only.

- **§5's `owner` tree governs the slot** (ADR-037 R62). A slot is the
  lowest `kk` with no `owner`, as § *Consequences* states.
  [ADR-033](DECISIONS.md#adr-033)'s *"a slot is another field on the same
  allocation"* as [ADR-017](DECISIONS.md#adr-017)'s is superseded by this
  §5, and a fixed AppVM needs no ADR-017 record for its slot. Until the
  launch daemon exists, `owner` is written by hand (R63).
- **§ *Dependencies surfaced*, corrected (R72; S D5).** *"Until it exists,
  an AppVM on the pool configures its address by hand through the console,
  as a gate fixture and nothing more"* names a mechanism that does not
  exist: katmate-init runs no getty and the AppVM has no console shell, the
  build lists name no `ip` tool for the image, and `vm-agent` runs as uid
  1000 without `CAP_NET_ADMIN` (S § 1.5). The addressing path is
  **ADR-038**, written after networking arc step 4.0 (R60, R65). The
  sentence above is not edited.
- **§ *Questions* item 5 is answered for the Acer's config copy only.**
  `~/katmate-kernels/config-katmate-microvm-amd64-6.12.87` (header line
  `# Linux/x86 6.12.87 Kernel Configuration`) carries `CONFIG_IP_PNP=y`,
  with `_DHCP`, `_BOOTP` and `_RARP` also `=y` (S § 1.5). Open problem
  #22's caveat applies: that file is the Acer's copy and not the config of
  the image on MINIS, and the Acer's copy has `CONFIG_IKCONFIG` unset, so
  the image itself cannot be asked. The question is not answered for the
  running kernel.
- **The 63 `ip=dhcp` boots of the 2026-09-14 note used the Debian netVM
  kernel**, `-kernel /var/lib/katmate/netvm/vmlinuz`, version
  `6.12.107+deb13-amd64` (`adr035-g5b-report.md`, outside the repository;
  S § 1.5). Their *"Unknown kernel command line parameters "ip=dhcp""*
  therefore says nothing about the microVM kernel. **Kernel `ip=` has never
  run on the microVM kernel.**
- **A recorded risk, not a gate item** (S § 3, Q-S4j). Finding 1 of the
  2026-09-14 note stands: *"No frame has ever been shown to cross a slot on
  its own destination address."* Every measured delivery across a slot was
  into a receiver with `IFF_PROMISC` set, and F12b's fixtures were host
  sockets on one end. **The first AppVM on a slot is the first addressed
  QEMU-to-QEMU delivery.**

**Revision note (2026-09-28, step 4.0: the first AppVM on a slot — § *Gates*
finding 1 of the 2026-09-14 note, § *Questions* item 5):** this note
records readings and the operator's rulings on them. It changes no text
above and takes no gate. Networking arc step 4.0
([ADR-037](DECISIONS.md#adr-037) R60) was taken on MINIS on 2026-09-28 by
the session s4-m0 (`s4-m0-report.md`, outside the repository, cited as M):
`app_web`'s image and kernel, started by a fixture launcher outside the
repository (`app_web.con`'s argv plus a `-netdev dgram` on slot 01 and
`virtio-net-device` on the derived MAC `52:54:00:6f:19:35`), against netVM
on NETCFG link 201 (`10.100.1.17`), three boots A, B and C, each with a
different kernel `ip=` tail. The TTL reading below was taken by the
operator over M's captures; its table is in `wp-0928d-brief.md`, outside
the repository.

- **§ *Questions* item 5 is answered for the MINIS config.**
  `/home/host/katmate-kernels/config-katmate-microvm-amd64-6.12.87`
  (`7720cf22…`), header line checked (`# Linux/x86 6.12.87 Kernel
  Configuration`), carries `CONFIG_IP_PNP=y`, with `_DHCP`, `_BOOTP` and
  `_RARP` also `=y` (M § 1). **Kernel `ip=` is observed working on the
  microVM kernel** `b34026dd…` (the `-dirty` 6.12.87), on three boots of
  three: `IP-Config: Complete`, `device=eth0`, the address and the gateway
  taken from the command line with no userspace (M1). The previous note's
  *"Kernel `ip=` has never run on the microVM kernel"* was true when
  written and no longer is. Open problem #22's caveat is unchanged:
  `CONFIG_IKCONFIG` is unset, so the config is not proven to be the
  image's.
- **M2: `ip=` did not give a `/32`.** With the netmask field
  `255.255.255.255` (boot A), the kernel printed *"IP-Config: Guessing
  netmask 255.0.0.0"* and completed with `mask=255.0.0.0` and
  `gw=10.100.1.1`: the mask was replaced by a guess and the gateway was
  kept, not refused. With `255.255.255.0` (B, C) the mask was taken as
  given. **Why the kernel guessed was not read**: the ipconfig source was
  not consulted.
- **M3, finding 1 of the 2026-09-14 note — settled functionally, not by
  measurement.** netVM held `10.100.1.17 lladdr 52:54:00:6f:19:35` on
  `km01` after B and C, and the guest's SYNs left through `uplink0` (M4).
  A unicast SYN to netVM's slot MAC required the guest to receive netVM's
  unicast ARP reply, and netVM to accept a unicast frame: **addressed
  QEMU-to-QEMU delivery works in both directions** (operator ruling,
  2026-09-28). **`IFF_PROMISC` was not read** on `km01` or on the guest's
  `eth0`; nothing in either guest sets it. That both receivers were
  non-promiscuous is an **inference, not a measurement**. This bears on
  finding 1 and does not close it. No capture was taken on the slot, and
  the ARP exchange was not seen directly.
- **M4: the first AppVM traffic to leave through `uplink0`.** A host
  capture on MINIS's LAN interface holds eight SYNs to `10.3.1.3:8099`
  from `10.3.1.172` (netVM's uplink) during boots B and C, and, in capture
  B, three SYNs from the Acer (`10.3.1.170`). Read with `tcpdump -v`, the
  eight carry **ttl 63** against the Acer's **ttl 64** in the same capture:
  each crossed one routing hop, netVM. They are the guest's traffic,
  forwarded through slot 01 and NATed to `10.3.1.172`, not
  netVM-originated (operator ruling, 2026-09-28). C's first SYN came 1.3 s
  after RUN `firefox-esr`: firefox restored the session boot B saved on the
  persistent `/home`. **This is not G5** (ADR-037's note of the same date).
  No conntrack entry was read inside its expiry window.
- **M5 and R49 — a hypothesis, unverified.** R49 read +0 on `km01` in all
  three boots, including A and B without `ipv6.disable=1`. Hypothesis: a
  router solicitation goes to `33:33:00:00:00:02`; netVM is not a router
  and does not join that group, so QEMU's virtio-net receive filter drops
  the frame before netVM's kernel sees it, and R49 cannot count it. F12b
  row 3 counted only because its fixture sent to `ff02::1`, which netVM
  joins. **On that reading R49 is not a witness for RS.** Nothing was run
  to test it. With `ipv6.disable=1` (boot C) the guest runs no IPv6 at
  all, which its serial line shows directly: *"IPv6: Loaded, but
  administratively disabled, reboot required to enable"*.
- **The AppVM kernel starts `netconsole`** (*"netconsole: network logging
  started"*, `[netcon0] enabled`, on every boot; M § 6 item 6). Its
  targets were not read. Open problem #52.

**Not read, and not claimed (M § 5):** `IFF_PROMISC` on either receiver;
any capture on the slot; a conntrack entry inside its expiry window; a
positive control for R49; the guest's own view of its routes, neighbours,
resolver or IPv6 state; why ipconfig guessed `255.0.0.0`; a `/32` by any
other means than `ip=`'s netmask field.

**Revision note (2026-09-28, §5 — R75 and the ruling of the 2026-09-07
note):** this note records the operator's reading of a ruling. It changes
no text above. [ADR-037](DECISIONS.md#adr-037) R75 (per-slot POSIX ACLs
keyed to per-VM local users, not plain `chown`; ruled 2026-09-15, first
recorded 2026-09-28) and the 2026-09-07 note's ruling (*"the launch daemon
sets ownership at assignment and returns it at release"*) were recorded
without a statement of how they relate. The operator's reading, of
2026-09-28:

- **R75 supersedes the mechanism** of the 2026-09-07 ruling: ownership by
  `chown` becomes a per-slot POSIX ACL entry keyed to the VM's user.
- **R75 keeps its timing:** the grant is made at assignment and withdrawn
  at release, the same moment the `owner` file is written and removed, so
  occupancy and permission stay one act.
- **`RuntimeDirectory=` stays.** This settles the choice the 2026-09-15
  note reopened (keep the directive, or a non-destructive `ExecStartPre=`
  helper) in favour of the directive. That note's finding 6 stands: the
  directive resets ownership, mode and ACLs at every netVM start. **How the
  ACL survives that reset is decided in C1**, where R75 is implemented.

Nothing was implemented; no mode, owner or ACL under `/run/katmate/link/`
was changed.

**Revision note (2026-09-29, § *Dependencies surfaced* — the first item
answered by ADR-038):** this note records a decision made elsewhere. It
changes no text above and takes no gate.

- **The first item of § *Dependencies surfaced*** — *"How the AppVM end
  learns `10.100.1.(16+k)/32` and its route to `10.100.1.1`"* — **is
  answered by [ADR-038](DECISIONS.md#adr-038) (PROPOSED)**: katmate-init
  applies the address, the on-link default route and the resolver from
  typed `km.*` kernel command-line parameters. The item's text is left as
  written, and so is the 2026-09-28 note's correction of it (R72).
- **§3's *"no per-instance network fact ever reaches an AppVM's
  configuration"* holds for the image.** The address reaches the guest per
  launch, on the command line, and is never written into the image or the
  root delta; the gateway and the resolver are ADR-025's constant, written
  literally in the template (ADR-038 §10).

Nothing is implemented; ADR-038's gates are untaken.

**Revision note (2026-09-29, §5 implemented — both `ExecStopPost=` halves,
and the `owner` format):** this note records an implementation and its
first observation. It changes no text above and takes no gate. Sources:
`s4a-impl-A-report.md` (A, the code, on the Acer) and
`s4a-impl-B-report.md` (B, install and first start, on MINIS), both
outside the repository; the rulings are in
[ADR-037](DECISIONS.md#adr-037)'s note of the same date.

- **§5's `ExecStopPost=` pair is in the tree.** netVM's half is one
  `ExecStopPost=/usr/bin/rm -f` with the sixteen literal paths
  `/run/katmate/link/%i/00/netvm` … `/run/katmate/link/%i/0f/netvm`, in slot
  order, in `katmate-sys-driver@.service` (`1597445`, ADR-037 R74). The
  AppVM's half is one `rm -f` of the one path
  `/run/katmate/link/${KM_NETVM}/${KM_SLOT}/appvm`, in the new
  `katmate-app-routed@.service` (`d6feb9c`, R81). No shell and no glob in
  either, as §5 requires; both scalars are typed by the generator.
- **The `owner` file's format is R78's.** §5 gives its content (the
  instance name and the `link_id`), not its format. It is a flat
  `KEY=VALUE` file in the form of the nic label file:
  `KATMATE_OWNER_VERSION=1`, `INSTANCE=<name>`, `LINK_ID=<u32>`, read with
  `km_meta_require`. Every `owner` in the netVM's tree, not only the one
  naming the instance being started, must be a regular file (not a
  symlink), owned by uid 0, not group- or world-writable, version 1, with
  an `INSTANCE` matching the instance-name pattern and a decimal `LINK_ID`
  of at most 4294967295, or the start is refused. `owner` decides which
  address a VM gets, so it is a trust input.
- **R84 (A's D1), and why.** The AppVM's path is built from projected
  scalars, and a projection survives stops and failed starts (ADR-032's
  note of 2026-08-22). A start refused before the generator ran would have
  left the previous start's projection standing, and `ExecStopPost=` would
  then have unlinked the `appvm` of a slot this instance may no longer
  hold, possibly a live AppVM's. So the template's first `ExecStartPre=`
  is `+/usr/bin/rm -f /run/katmate/vm/%i.env`: after any refused start
  there is no projection, both scalars expand empty, and the path names
  nothing. `katmate-sys-driver@` does not get the line; its paths are
  literal.
- **Observed on MINIS, 2026-09-29 (B), for the AppVM's half.** After a
  clean SHUTDOWN of `katmate-app-routed@app_web`, slot 01's `appvm` was
  absent while `owner` and the projection stayed (B, P7). That is
  attributed to `ExecStopPost=` **by inference**: systemd collected the
  inactive instance, and its execution record with it. After a start
  refused at `katmate-check-image` with the previous projection present
  (B, P8), the projection was gone, `ExecStopPost=` ran (a record, status
  0), systemd logged *"Referenced but unset environment variable evaluates
  to an empty string: KM_NETVM, KM_SLOT"*, and a sentinel file at slot 01's
  `appvm` path survived on its inode. **R84 is observed by record.** The
  same start without R84's line was not run.
- **Not observed: netVM's half.** It is installed on MINIS and loaded by
  the running netVM's unit, and it has not executed, because netVM has not
  been stopped since. It is settled by reading the sixteen `netvm` paths
  before and after netVM's next stop.

**Status is unchanged: PROPOSED.** No gate of this ADR is taken by this
note.

---

## ADR-036 — The distributable unit is the enforcing set of the trust model; the host base is a pinned composition, neither a mutable install nor a distribution

**Status:** PROPOSED (2026-09-18). Taken on the tree's documents and on one
read-only audit of the repository (2026-09-18, thirteen findings against
`audit-fable` HEAD; the audit's report is filed verbatim at
`docs/audits/2026-09-18-trust-boundary.md`). It takes no new measurement of its
own and names the ones it needs in § *Gates*.
**Proposed is a decision and not an implementation:** no manifest, no signing
scheme, no delivery mechanism and no host image exist, and this ADR defines none
of them at the level of code or configuration.

**Depends on:** [ADR-003](DECISIONS.md#adr-003) (AF_VSOCK only; no
guest-to-guest channel), [ADR-004](DECISIONS.md#adr-004) (host kernel),
[ADR-020](DECISIONS.md#adr-020) (the release is a pre-baked signed ISO),
[ADR-026](DECISIONS.md#adr-026) (identity is resolved host-side from the
connection), [ADR-029](DECISIONS.md#adr-029) (systemd owns the VMM; the daemon
must be updatable without touching running VMs), [ADR-030](DECISIONS.md#adr-030)
and [ADR-032](DECISIONS.md#adr-032) (authorship is the tier; the release wins on
upgrade), [ADR-034](DECISIONS.md#adr-034) (provenance is captured at build and
verified at install, not at launch), [ADR-035](DECISIONS.md#adr-035) (every face
of a slot is a function of its index).
**Decides:** the questions [ADR-012](DECISIONS.md#adr-012) and
[ADR-013](DECISIONS.md#adr-013) have held open since they were entered — *what*
is distributed, and *where* it is verified. The signature scheme itself is named
as open below.
**Amends, by revision notes to be appended on acceptance:** ADR-004 (what
"custom kernel" means), ADR-007 (the pacman-hook trigger), ADR-016 (placement of
the desktop layer), ADR-020 (the ISO's content list), ADR-032 §5 (*"not signed
with the ISO"*).
**Does not amend:** ADR-003. It restates one of that ADR's invariants in the
form the implementation can enforce (§ *Decision* 3).

**Numbering:** `ADR-036` is the next free number; `ADR-031` stays reserved for
the licence declaration, per ADR-034's numbering note.

**Context:**

Two things are true of the project on 2026-09-18, and this ADR reasons from
both.

**There is no update supply chain.** ADR-020 fixes the unit of *installation* —
a signed ISO the user verifies and provisions — and stops there. Nothing says how
an installed system ever changes again. The tree is not silent by oversight; it
is silent in three places that disagree with each other:

- ADR-007 has `katmate-update` triggered by **a pacman hook** on the host: the
  host changes under pacman and KatMate reacts. ADR-019 retracts the hook —
  *"there is no pacman hook and nothing to detect"* — and makes `katmate-update`
  a release-side bump orchestrator; ADR-020 confirms it never runs on a user's
  machine. ADR-007's trigger clause was never marked superseded.
- ADR-032 §1 makes authorship operative as *who wins on upgrade* and states the
  mechanism: *"`katmate-update` never touches `/etc/katmate/`; it replaces
  `/usr/lib/` wholesale."* Under ADR-019/020 there is no on-device actor to do
  the replacing. The tier model has an upgrade owner and no upgrade.
- ADR-012 and ADR-013 stand at *Proposed*, each a single question. ADR-020
  answered ADR-012's question for installation — central build, signed artefact —
  without closing it; nothing has answered ADR-013's.

So the state (A) names is not a gap between two decisions. It is a decision that
was never taken, with three accepted ADRs each assuming a different answer.

**The implementation was audited read-only, and the findings are measurements.**
Eleven of the thirteen concern guest-controlled bytes reaching a host decision —
window identity, terminal state, journal attribution, idle inhibition; one
(finding 10) is a codec resource bound; one (finding 12) is netVM's forwarding
plane accepting the aggregate `10.100.1.0/24` with no per-link binding, so one
AppVM can spoof another's `/32`. **None of the thirteen is used here as a task.**
They are used for what they measure about *placement*: every one of findings 1–6
and 13 is a fact about a configuration file, and finding 7's mechanism is a unit
file that `git status --porcelain --untracked-files=all` over `host/`, `desktop/`
and `manifests/` does not report — so it is either tracked in a tree the check
did not cover or exists only on the reference host's disk. Which of the two is
**unsettled**, and § *Decision* 2 makes settling it a precondition rather than a
curiosity.

**The trust model is documented as enforceable and measured as not.**
`SECURITY-MODEL.md` § *Desktop compositor* records the identity path as *"two
host-side steps and no guest input"*, verified live 2026-07-28 (ADR-026 E1–E6).
Finding 1 records that the carrier the compositor draws is a placeholder and that
every window rule beneath it keys on `app_id` and title. Both are true: ADR-026
proved a **query**; nothing shipped the **indicator**; the rules that stand in its
place are the identity path *in fact*. The model describes a mechanism the
implementation does not have — the shape of ADR-021's shutdown model and
ADR-025's Path A, a third time, and this time on the boundary that separates
domains for the user's eyes.

**Where load-bearing host state lives today, measured:**

- `HOST-CONFIG.md` opens with *"Some of what makes KatMate work is not in git"*
  and lists ten entries: three `[?]`, two `[OPEN]`, and five `[LIVE]` — applied by
  hand on one machine, not automated.
- The reference host reported `7.0.12-arch1-1` — a stock Arch kernel, **not**
  `linux-hardened` — when ADR-028/029's netns gates were measured (2026-08-02,
  MINIS), and `7.1.9-hardened1-1-hardened` on 2026-08-28 (`state.md`
  § *Invariants*, corrected that day). For at least part of that interval the
  machine ADR-004 governs was not on the decided kernel, no artefact recorded
  either transition, and the return was noticed by a `uname` read taken for
  another reason.
- `/usr/lib/katmate/katmate-generate-env` as installed differs from the tree
  (2026-08-22, one wording); § *Invariants* now requires hashing the installed
  set before every gate because *"a gate measures the installed copy"*. That rule
  is a manual integrity check on T4 — the thing an update channel would make
  mechanical.
- `/etc/systemd/system/katmate-pool@.service` and its drop-in; the dev console's
  three pieces (gap 15); `vhost-vsock-load.service` carrying a key systemd does
  not know (HOST-CONFIG §5); the vfio modprobe and udev fragments (§3); the
  greetd sessions (§7): all load-bearing, none in the release.
- netVM's `rp_filter` is **2** on every slot interface, from
  `/usr/lib/sysctl.d/50-default.conf`, a systemd vendor default — *"neither a
  kernel default nor a decision taken on this project: no KatMate artefact
  mentions `rp_filter` anywhere"* (ADR-035 note of 2026-09-14, finding 3). The
  value that decides whether a foreign source is accepted on a slot was inherited,
  not chosen, and G2's refusal half measured the consequence: an echo request
  with slot 01's peer as source, delivered on slot 02, was *"accepted and acted on
  in another tenant's name"* (ADR-035 note of 2026-09-12, finding 6). Finding 12
  of the audit reads the same fact from the tree.

**Three accepted decisions are in tension, and the tension is the subject.**

1. **ADR-016 against ADR-026/ADR-030.** ADR-016's context places the desktop
   layer *outside* the TCB, its build state has it in `~/.config/`, and it defers
   installer integration to a manual step until v1.0; its two-profile decision was
   narrowed to one shipped profile by ADR-026 and `SECURITY-MODEL.md`, but its
   placement was never revisited. ADR-026 puts the compositor *inside* the TCB
   because it draws the indicator; ADR-030 makes containment constants T4 —
   authored by the release, never by the user. The compositor configuration is T4
   by ADR-030's own test — the project writes it, no user may weaken it, a release
   replaces it — and it is installed as a per-user dotfile by ADR-016's build
   state. Findings 1–6 are the measurable form of that tension.
2. **Principle 9 against the forwarding plane.** *"Isolation by topology, not by
   rule"* is true at L2 — ADR-033/035 give every AppVM its own link and no shared
   segment. Inside netVM the sixteen links meet one forwarding plane, one
   conntrack table and one neighbour table, and there the model has no statement
   at all. ADR-021 says the firewall *"references the internal segment only as the
   aggregate"*; that was written to keep per-AppVM *authored* rules out of the
   image, and it was read as licence for the forwarding plane to be aggregate too.
   ADR-003's *"no guest-to-guest channel"* therefore has an enforcing artefact at
   L2 and none at L3.
3. **ADR-032 §5 against the policy it carries.** The netVM image and its exported
   kernel and initramfs are T2 payload, *"produced by `build/netvm.sh`, replaced on
   rebuild, not signed with the ISO."* Inside that payload is the nft ruleset —
   project-authored policy, T4 by authorship — and the vendor sysctl the invariant
   turned out to depend on. The tier with the weakest distribution guarantee
   carries the artefact whose correctness a documented invariant rests on.

**One more, older, and it decides the shape of the answer.** ADR-019 took the
host waypipe binary away from pacman because *"a host binary owned by the project
is a prerequisite for any distribution model"* — a component coupled across the
trust boundary cannot be owned by a distro whose cadence the project does not
control. ADR-032 §1 then made `/usr/lib/katmate/` release-owned for the same
reason. Each step was right and each was drawn around one component. The question
this ADR answers is what the *general* boundary is that those two were instances
of.

**Decision:**

### 1. The unit is the enforcing set of the trust model, bound by one signed manifest

**A KatMate release is one signed manifest that binds, by content hash and
version, every artefact whose correctness is load-bearing for an invariant stated
in `SECURITY-MODEL.md` or in an accepted ADR — and nothing else.** The manifest
is the unit. Components are content-addressed and may be delivered separately and
updated at different cadences; what is atomic is the *combination*, because the
combination is what was tested. This is ADR-019's waypipe lock generalised: the
version lock was enforced *"where the two ends meet"*; the manifest is the record
of every pair of ends that must meet.

**The membership test is one question with two halves:** *does this artefact
enforce an invariant, or is it merely contained by one?* Enforcing → in the unit:
release-authored, tracked, hashed, replaced wholesale on upgrade. Contained →
out. By that test the unit contains:

- **The host kernel image, its command line and its initramfs.** The kernel is
  load-bearing *by config*: `vsock_diag` (ADR-026, a *stated requirement*),
  namespace-aware vsock on Linux ≥ 7.0 (ADR-028, C6), `TMPFS_POSIX_ACL`
  (ADR-035 note of 2026-09-15), KVM, VFIO and the IOMMU driver, and the
  hardening sysctl set whose one visible consequence (`io_uring_disabled = 2`)
  already forced `aio=threads`. HOST-CONFIG §4 shows that the initramfs
  composition is per-installation knowledge today.
- **The host userspace the model names as TCB** — `SECURITY-MODEL.md` § *Trusted
  computing base* lists QEMU/KVM, systemd, the host side of the agent, the waypipe
  client, the compositor, the launch daemon and installer-provisioned
  configuration — **and everything those depend on to render and to take input**:
  while the compositor is on the host that is Mesa, libinput, the font stack, the
  seat manager and the greeter. Pinned as a *set*, by exact version and hash. Not
  because the project builds them (it does not, § 4) but because the set that was
  tested is the set the signature vouches for.
- **T3/T4 as ADR-032 defines them** — unit templates and the executables under
  `/usr/lib/katmate/` — plus the project's host binaries under `/opt/katmate/bin/`
  (ADR-019).
- **Every host-side systemd unit the model depends on, whatever its current
  location:** the VM templates, the module-load and vfio-binding units
  (HOST-CONFIG §3, §5), the NIC publication unit, and **the GUI ingress** — the
  unit that opens port 1024 to guests. § 2 settles where that one is.
- **The host nftables policy** (`SECURITY-MODEL.md` § *Host firewall*).
- **The compositor and bar configuration of the shipped profile.** While the
  compositor is host-resident this configuration *is* the identity path —
  findings 1–6 measure exactly that — and by ADR-030's authorship test it is T4.
  Per-machine output geometry (HOST-CONFIG §8) is installer-generated and stays
  out, as ADR-032 already rules for `outputs.conf`. User theming stays out only
  where it is **measured** not to reach the two carriers ADR-026 names — the bar
  module and the focused border colour — a measurement, not an assumption.
- **The guest images:** the foundation and the app layers (ADR-007/010/014), the
  netVM image with the policy baked into it (ADR-021), the guest microVM kernel
  with its sidecar (ADR-034), and netVM's exported kernel and initramfs.
  **ADR-032 §5's *"not signed with the ISO"* is superseded for every T2 payload
  produced from T4 sources: it enters the manifest by hash.** T2 remains the tier
  — the build pipeline is still the author and still wins on rebuild; what changes
  is that a rebuild is a release act.
- **Both agents and the host-side protocol client(s)**, because the codec is one
  artefact on two sides of the boundary. Finding 10 is what a codec looks like
  when nothing enforces its pair.
- **The T1 schema and its validator** — never T1's values.
- **The conformance tests:** the gate fixtures that measure each invariant. A
  release that cannot re-run its gates has no basis for its signature. This is
  ADR-024's method applied to the release rather than to a mechanism.

**Out of the unit, and why:** T1 values and every per-machine fact HOST-CONFIG
generates — MAC-matched profiles, BDF resolution, outputs, greetd sessions —
under ADR-032's `/etc/skel` relation; user data; software *inside* AppVMs that
Debian's channel updates and the compartment exists to contain; dev scaffolding
on the removal list (open problems #3, #4, #11; gaps 13 and 15).

**What breaks when the unit is drawn too small — each case has already been
measured once on the reference host:**

| unit drawn as | what then enforces the invariant | measured instance |
|---|---|---|
| project-built components only (ADR-020's content list) | whatever `pacman -Syu` last left: the kernel, the VMM, the compositor and their configuration are the distro's | the non-hardened `7.0.12-arch1-1` interval under an accepted ADR-004; `aio=io_uring` found dead by breakage rather than by review |
| host without the compositor configuration | the operator's dotfiles | findings 1–6; ADR-016's `~/.config/` build state |
| host without the netVM image and its policy | whatever netVM last booted, with a load-bearing sysctl from a vendor default | ADR-035 notes of 2026-09-12 (finding 6) and 2026-09-14 (finding 3); audit finding 12 |
| host and images without the agents and client as a pair | a codec that may differ at its two ends | ADR-008's `header has 100 != own 200`, on waypipe; finding 10's class on the agent |
| everything but the kernel | a config that may silently drop `vsock_diag` or the netns floor | ADR-026's own warning; the 2026-08 kernel interval |
| everything **plus** T1 values | the installer, overwriting per-machine facts | the drift class ADR-032 §1 exists to prevent (*"wins on upgrade"*) |

### 2. The boundary is drawn by reference from the model, not by presence in the tree — and the first component to fail that test is the GUI ingress

**The repository is a source of the unit, not its definition.** Two measured
facts prove the two are not the same object: a load-bearing unit the model names
cannot be located in version control (finding 7), and a T4 executable installed
on the reference host differs from the tree (2026-08-22). So the unit's boundary
cannot be *"what is in `host/`"*. It falls at **the set of artefacts the model
references** — and the model must therefore become the index of the unit:

- **`SECURITY-MODEL.md` § *Controls by component* names, for each control, its
  enforcing artefact, that artefact's tier and its test.** A control whose
  artefact resolves to no tracked path is marked *documented, not enforced* until
  it does. This is a documentation-model change and it is the whole of what this
  section decides; it produces the manifest's contents as a by-product.
- **A mechanism the model names and the tree lacks is a hole in the unit,
  visible when a release is assembled** — not when an auditor happens to look.

**The waypipe listener unit is the first entry, and it must be settled before
anything else in this ADR can be gated.** The audit's check covered three
subtrees; the settlement is a whole-tree `git ls-files` on the authoring machine
against `systemctl --user cat` of the socket and service units on the reference
host, compared byte for byte. Either outcome changes a document: if the unit is
tracked elsewhere, finding 7's tracking claim is corrected and the location is
recorded against § *GUI forwarding*; if it exists only on disk, `HOST-CONFIG.md`
gains an entry with its failure mode — **a fresh install has no GUI path at
all** — and the release gains an artefact. **Until settled, the release has no GUI
ingress, and `SECURITY-MODEL.md` § *GUI forwarding* describes a component the
release does not ship.**

**Its classification is decided here whatever its location turns out to be.**
`SECURITY-MODEL.md` calls it *"a socket-activated systemd user service"*; ADR-019
places it in the user's session. **The GUI ingress is not dev scaffolding and it
is not user configuration; it is the host end of the only channel a guest may
draw through, and it belongs to the system, not to the desktop user's session.**
Two reasons, one about today and one about § 6: an ingress owned by a login
session is one the release cannot install and the launch daemon cannot bind to a
VM; and a display domain cannot inherit a listener that lives in a host session
which, by then, will not exist.

### 3. Policy whose correctness is load-bearing for a documented invariant is T4 wherever it executes, and it ships with its refusal test

This is where finding 12 is accounted for. It is not a vulnerability report — the
running system was already measured doing exactly this by ADR-035's G2 refusal
half, in two forms, on 2026-09-12 — it is a **divergence between the model and the
implementation, and the divergence has an owner problem**: the value that decides
acceptance of a foreign source came from a vendor file, and the model's sentence
about it — *"per-`/32` isolation is topology, not firewall"* — has no artefact.

**Three rules follow, all three about tiers and documents, none about which knob
is turned:**

1. **The tier of a policy is its authorship, not its execution site** (ADR-030
   §1, applied honestly). The nft ruleset and every value netVM's forwarding plane
   depends on are written by the project → T4 → in the unit, hashed, replaced
   wholesale, never user-editable, even though they run in a guest and travel
   inside a T2 image.
2. **An invariant with no named enforcing artefact is a defect of the model, and
   a value the invariant depends on that arrives from a vendor default is either
   adopted explicitly — recorded as KatMate's decision, in the unit — or replaced.
   It is never inherited silently.** `rp_filter = 2` is the instance. Whether the
   right binding is strict reverse-path filtering, a per-slot ingress match or
   another primitive is the code pass's question and is already recorded there as
   a proposal (ADR-035 note of 2026-09-12, finding 6: *"belongs to the tier model
   rather than to a session"*). This ADR answers the tier-model half: **the
   binding is T4, and it is a function of the slot index.**
3. **Principle 9 is restated in the form that is true.** *Isolation by topology,
   not by rule* means no **authored, per-AppVM** rule — nothing an operator or the
   daemon writes when an AppVM comes and goes — which is what ADR-021 and ADR-022
   were protecting. It does not mean the forwarding plane may be aggregate.
   ADR-035 §1 already supplies the resolution: every face of slot `k` is a
   function of `k`, and a per-slot binding of source to link is one more face of
   the same index — **topology expressed in the forwarding plane**, derived, not
   authored, constant in T4. ADR-003's *"no guest-to-guest channel"* is thereby
   restated as: **at L2, no shared segment (ADR-033); at L3, netVM's forwarding
   plane binds each peer address to its own slot, and that binding is a shipped,
   tested member of the unit.** ADR-003 is not amended; its invariant gains the
   artefact it lacked.

**The test is part of the policy.** G2's refusal half — both forms, the IPv4
acceptance and the ARP neighbour contamination, because ADR-035's own note records
that they measure different properties — is the conformance test for this
invariant and ships in the unit as a release gate. A policy change that does not
re-run its refusal fixture is not a release.

### 4. The host base stays Arch + `linux-hardened`, and stops being "the host distro": the release composes a signed host image from inputs pinned by version and hash

**Judged first on whether it makes the unit of § 1 buildable, reproducible and
verifiable, and only then on self-maintained surface:**

| option | buildable | reproducible | verifiable | failure mode |
|---|---|---|---|---|
| (i) Arch as today — a mutable install updated by pacman | yes | **no** — no pin exists; the set is whatever the mirror served | per package, by the Arch keyring; **never as a set**, and drift after install is undetected | the TCB's composition is the outcome of the last `pacman -Syu`. **Measured:** the non-hardened kernel interval; a launcher change forced by a hardening sysctl found at run time. This is the state (A) describes, with a signature on the installer in front of it |
| (ii) own minimal base from pinned upstream sources | in principle | only with a bootstrapped toolchain the project also owns | against **KatMate's key only** — no independent builder exists to agree | **cadence collapse:** every CVE in QEMU, Mesa, wlroots, glibc, systemd becomes a maintainer action for one person; the TCB freezes at the last release the maintainer had time for. And it spends the effort on provenance where the risk is presence (§ 6) |
| (iii) **composition:** a dated snapshot of the Arch repositories as input, each package pinned by exact version and hash and verified against the Arch keyring at build; the *set* recorded in the manifest; installed and updated as an image, replaced whole | yes, with tools that exist | to the extent of the snapshot's retention and the archive's reproducible-builds coverage — **both to be measured, § *Gates*** | manifest signature over the set at download and at install; component hashes when placed; Arch's signatures at build. Verification at boot is hardware-dependent and outside the current threat model (gap 6) | **cadence equals the maximum over components:** any security update to any host package obliges a rebuild and a re-run of every gate, so **test automation is the bottleneck** — a release that cannot be re-gated ships stale or untested. The snapshot service is a courtesy, not a contract. Every base-layer update is a reboot |
| (iii-b) the same composition from Debian stable inputs | yes | yes — a time-indexed archive is a first-class service there | as (iii) | **the kernel floor:** see § 5 |
| (iii-c) a declarative store-based base (Nix/Guix family) | yes | by construction | by construction, against the store | puts an evaluator and a store model into the TCB's boot path and contradicts ADR-032's legibility rule — a tier readable by `ls` — and ADR-011's revisability stance; every tool in the tree would be rewritten. **Cost**, not error |
| (iii-d) a KatMate-signed package repository over pacman, updated in place | yes | per package | **per package, never per set**; the solver picks the combination | partial-state windows during update; the TCB's package manager, with its hooks and scriptlets, becomes the update surface; the tested combination is not what is verified. **Cost and risk**, not error |

**Decision: (iii), with Arch inputs, for the reasons § 5 gives and for as long as
they hold.** Concretely, and without deciding any format:

- **The host base is an input to the release pipeline, pinned by version and
  hash, never a runtime dependency on a mirror.** ADR-020's *"the ISO carries
  every prebuilt component"* is extended to the base itself; its open follow-up —
  *"how the Debian base within the foundation is itself pinned/shipped"* — is
  answered in the same breath for both bases: **a dated archive snapshot, recorded
  in the manifest.** ADR-011's deferred `snapshot.debian.org` pin becomes
  mandatory at the first release.
- **The host is installed and updated as an image, replaced whole.** ADR-032's
  *"replaces `/usr/lib/` wholesale"* becomes true of the whole base, and gains the
  actor it lacked: an update is the arrival of a new manifest and the placement of
  the components it names. No package-manager transaction runs on a release host
  after installation. The development hosts are not release hosts; a dev profile
  that keeps pacman is explicit and separate, in the ADR-016/ADR-027 style, and is
  not what ships.
- **Two delivery layers under one manifest, because ADR-029 requires one of them
  to be restartable.** The *base layer* — kernel, initramfs, host userspace —
  changes by reboot. The *KatMate layer* — T3/T4, the daemon, the compositor
  profile, the GUI ingress, the host binaries — changes without touching running
  VMs, which is the property ADR-029 bought and named: *"a property this project
  needs specifically because it ships security updates."* The split is delivery
  granularity; trust granularity is the manifest.
- **Boot-time verification is not claimed.** Signed UKI, measured boot and TPM
  sealing are in the backlog, and gap 6 says why they are absent; ADR-034 already
  refused a launch-time imitation of them. The unit's verification points are the
  manifest at download, install and update, and the component hash at placement.
  If the threat model changes at v1.0 (gap 6's revisit), verification extends to
  boot; the unit's *contents* do not change.
- **The composition tooling is not decided here.** ADR-011 rejected `mkosi` for
  guest images on revisability grounds; whether that reasoning transfers to a host
  image composed from pinned binaries is a separate decision, to be taken against
  a measured comparison of the candidates' auditability, not by citing ADR-011.

**The two update tracks already decided stay two.** `katmate-update` (ADR-019)
and `netvm-update` (ADR-021) remain release-side orchestrators on their own
cadences; each produces components; a manifest is re-issued when either does.
Atomicity lives in the manifest, so a netVM rebuild is a release without being a
re-download of the host.

### 5. On the Arch/Debian question: the install-time choice is rejected, in one line; the reasoning is corrected because a wrongly recorded reason yields a wrong revisit condition

**Agreed, in one line:** an install-time choice between two host bases doubles
the TCB — two hardening baselines, two kernel cadences, two invariant sets, twice
the gates — and solves nothing § 1 names.

**Disagreed on the premise that Debian was perception and not technique.** Both
bases carry technical facts the documents already contain, and they cut in both
directions:

- *For Debian:* a time-indexed archive as a first-class service — the property
  (iii) needs most and the one Arch offers only as a courtesy; reproducible-builds
  coverage; security backports that do not move versions, which is precisely what
  makes a pinned set cheap to keep patched; and one base for host and guests, so
  one snapshot discipline, one keyring and one toolchain for every image the
  release builds.
- *For Arch, and these are dated facts:* `linux-hardened` is packaged there
  (ADR-004). The host kernel floor is **Linux ≥ 7.0**, because C6 and ADR-028's
  namespace-aware vsock require it and were measured on it, while Debian stable's
  kernel is 6.12 — netVM runs `6.12.107+deb13-amd64` (`state.md`) — so a
  Debian-stable host cannot satisfy C6 without a kernel from outside its own
  baseline, which is the second baseline the one-line agreement above refuses.
  Every `dgram` and `-sandbox` measurement in ADR-027/033/035 was taken on
  QEMU 11.1.x, and whether Debian stable's QEMU reproduces them is unmeasured. And
  a stable release's graphics stack lags upstream by definition, which matters
  exactly as long as the graphics stack is host-resident.

**So the reason to stay on Arch is technical, and it expires on two measurable
conditions** — the GUI leaving the host (§ 6), and Debian stable's kernel
reaching the host floor while `linux-hardened`'s availability or cadence fails
(§ 7). Recorded that way in § *Revisit when*, so a future reader reopens the
question on facts and not on a communications judgement.

**One thing the perception argument missed in its own favour.** Under (iii) the
base is invisible in a stronger sense than *"the host is invisible to the user"*:
the user verifies **KatMate's** signature over a set, not Arch's or Debian's over
packages. The audience that reads Arch as a rolling remix is reading a property
the release no longer has.

### 6. An "own minimal host base" and a display domain are one question separated by years; what must not be foreclosed today

**Does § 4's answer change because the graphics stack is in the TCB?** Not the
answer; the *reason* (ii) loses. While Mesa, libinput, font rendering and a
compositor run on the host, an own base would mean **hand-building the largest,
fastest-moving, most defect-dense part of the TCB — the part the architecture
most wants to remove.** Findings 1–9 are not provenance failures: nothing about
*where Mesa came from* would change one of them. They are presence failures: a
compositor that parses guest streams and derives window identity from guest data
is in the TCB, and building it from pinned sources leaves it exactly there.
**(ii) is therefore not incoherent as engineering; it is misdirected as security,
for as long as the GUI is host-resident.** It becomes a coherent goal at the
moment the host's userspace is kernel, VMM, systemd, vsock, the launch daemon and
nothing that renders — and at that moment (ii)'s package count drops from
hundreds to dozens and the cadence objection weakens with it. **The two questions
are one question separated by years, and the second cannot be brought forward by
wanting it:** a display domain needs GPU and input-controller passthrough, which
is a hardware-class change against ADR-001's broad-hardware goal and the
Apollo-Lake performance floor, and open problem #9's preflight has never measured
a GPU group.

**What must not be foreclosed today, stated as constraints on design and not as
work on findings:**

1. **Identity is a property of the connection, never of the window — as a
   portability constraint, not only a security one.** ADR-026's exclusion of
   `app_id` and title stands; what this ADR adds is *why it must*: an identity
   path built into compositor window rules cannot leave the host, and one derived
   from the connection's host end can be handed to any component that owns that
   end. Any indicator implementation before 1.0 consumes identity from the
   connection owner through an interface a display domain could later be given.
2. **The GUI ingress is per domain and policy-driven, and it belongs to the
   system (§ 2).** The question a display domain will ask — *which CID may
   present, and where* — must be expressible as data in the unit before the domain
   exists; a single listener the host session opens to every CID cannot express
   it. The C6 namespace work is the mechanism through which reach is scoped, and
   it must not be designed as sixteen sealed boxes with no object that can grant
   one of them a peer: a display domain is exactly a permitted peer under
   ADR-003's *"inter-VM data flow only via the host"* — a host-mediated path —
   and whether that mediation is a relay or a policy exception is a later ADR,
   not a shape this one may make impossible.
3. **No host-only shortcut enters the GUI or audio path.** ADR-019 already
   strips dmabuf, gbm and video from waypipe; they stay stripped, because a
   display domain cannot share the host GPU's buffers. Audio (port 1026,
   planned) takes the same shape from the start.
4. **The hardware inventory records the GPU and the input controllers now.**
   ADR-022's `Nic` shape *"later serves USB controllers and audio"*; the installer
   preflight open problem #9 asks for is extended to record GPU and
   USB-controller IOMMU groups on every reference machine — a cheap reading today
   that decides, years from now, whether those machines can ever host a display
   domain.
5. **The host must be a subset of itself without a session.** Nothing in the
   KatMate layer may depend on the desktop user's login session — the GUI ingress
   living there is the one such dependency today (§ 2). A headless host must be a
   strict subset of a graphical one, or the display domain costs a redesign of the
   layer rather than the removal of packages.

### 7. ADR-004: the hard requirement has not appeared; a kernel-config dependency set has, and nothing records it

Every requirement the host kernel has acquired since ADR-004 was written is
**satisfied by `linux-hardened` as shipped**: `vsock_diag` (ADR-026 E4/E6,
measured on the hardened kernel then running); namespace-aware vsock
(ADR-029 G0/G1, measured 2026-08-02 on `7.0.12-arch1-1` — present on ≥ 7.0 by
upstream inclusion and therefore on `7.1.9-hardened1-1-hardened`, which is a
reading of version numbers and not a re-measurement); `TMPFS_POSIX_ACL`
(ADR-035 note of 2026-09-15, on the hardened kernel); KVM/VFIO/AMD-Vi (every
netVM boot); and the one hardening consequence the project met
(`io_uring_disabled = 2`) was absorbed by a launcher change and then
independently justified. Nothing in the audit is a kernel deficiency: finding 7
is userspace peer-checking that `AF_VSOCK` already supports; finding 12 is a
guest sysctl; finding 10 is a codec. **ADR-004's clause has not fired.**

**What appeared and went unrecognised is of a different kind.** The kernel is
load-bearing *by configuration*, ADR-026 wrote one such dependency down — *"a
future host kernel configuration change that drops it silently disables the
indicator's identity path"* — and no artefact carries the set. The reference host
then ran a kernel outside ADR-004 for an interval no artefact recorded. The
requirement that appeared is not *a capability `linux-hardened` lacks*; it is
**that the kernel be a pinned, hashed member of the unit whose required-symbol set
is checked at release** — which a distro package satisfies as well as an own build
would, and more cheaply. Decision: the unit carries the required-symbol set as
data, and the release gate reads it out of the pinned kernel's config; how the
config is read is itself a measurement (§ *Gates* G4).

**ADR-004 is amended by note to distinguish three things its one sentence
conflates:** (a) a custom kernel *source* — patches of the project's own — which
remains justified only by a hard requirement, and none has appeared; (b) an own
*config on upstream sources*, which is ADR-004's own fallback form (*"Arch LTS
sources + `katmate-host.config` delta"*) and becomes the natural move when the
host is headless (§ 6) and the config should shed everything that renders;
(c) an own *build and packaging of unmodified `linux-hardened` sources*, which is
what (ii) entails and is rejected with it — unless (d) **`linux-hardened` leaves
the Arch repositories or its release lag exceeds the release cadence**, a lag
that is **unmeasured** today and is named in § *Gates* as an `OBSERVATIONS.md`
entry with provenance.

### 8. What does not change before 1.0, stated plainly

The runtime architecture does not change: the compositor stays on the host, the
vsock device model stays in the host kernel (ADR-028), netVM stays a q35 driver
domain, the host stays Arch with `linux-hardened`. **What changes is the release
architecture** — the unit's boundary (§ 1–2), the tier of load-bearing policy
(§ 3), and the base as a pinned composition rather than a mutable install (§ 4).
None of it is change for its own sake; each part is the general rule of which
ADR-019 and ADR-032 §1 were the first two instances.

**Rejected alternatives:**

*Rejected as wrong — the option does not produce the unit, or produces a false
one.*

- **The mutable Arch host with pacman as the update channel (i).** Not a cost
  trade: it is the absence of a unit with an installer signature in front of it.
  Measured drifting on the reference host under an accepted kernel decision.
- **A unit drawn as ADR-020's content list — project-built components only.**
  Verifies the parts the project made and leaves the kernel, the VMM, the
  compositor and their configuration to the distro. § 1's table.
- **Component-level signatures with no manifest.** Verifies each artefact and
  never the combination that was tested; ADR-008's failure was two individually
  genuine binaries that could not talk.
- **An install-time choice between two host bases.** Doubles the TCB and answers
  nothing; § 5, agreed.
- **An own base while the GUI is host-resident (ii), as a security measure.**
  Spends provenance effort on a component whose risk is presence; § 6. Its cost
  objection is real too, but it is rejected before cost is reached.
- **A custom host kernel now.** No hard requirement has appeared; § 7.
- **Debian, rejected as "perception".** The *conclusion* — stay on Arch — is
  kept; the *reason* as stated is rejected because it is not the operative one and
  would mis-set the revisit condition. The operative reasons are the host kernel
  floor and the host-resident graphics stack, and both are dated.

*Rejected for cost or risk — the option would produce the unit, and a future
reader may legitimately reopen it.*

- **A Debian-composed host (iii-b).** Correct shape, stronger snapshot service;
  loses on the kernel floor and on graphics currency while the GUI is on the host.
  Reopens on § *Revisit when* 1 and 2.
- **A store-based declarative base (iii-c).** Produces the unit by construction;
  rejected for the rewrite it costs and for the mismatch with ADR-011's
  revisability stance and ADR-032's `ls`-legible tiers.
- **A KatMate-signed package repository over pacman (iii-d).** Produces a signed
  *stream*, not a signed *set*; rejected for partial-state windows and for making
  the package manager the TCB's update surface. As far as this project knows
  without a recorded source, it is how Qubes updates dom0 — a judgement, not a
  sourced fact — which is why it is listed as cost and not as error.
- **An own base after the display domain exists.** Not rejected — deferred; it is
  § *Revisit when* 1.
- **Moving the GUI into a VM before 1.0.** Right direction, wrong decade for a
  one-developer project with a hardware floor to keep; the constraints in § 6 are
  what buying it later costs today.

**Consequences:**

*Easier*

- ADR-012 and ADR-013 leave *Proposed*: what is distributed is the manifest and
  its components; where it is verified is at download, install and update, and at
  placement. Only the scheme remains open, and it is one question, not three.
- ADR-032's *"wins on upgrade"* acquires an actor: the manifest.
- Every future *"is X in the TCB?"* question has a mechanical answer: is it in
  the manifest?
- The hash-first discipline `state.md` imposes on every gate session becomes the
  release's own check rather than a brief's first step.
- `HOST-CONFIG.md` gains a third axis beside status and confidence: **unit
  content** (a mechanism the release must ship) against **installer output** (a
  per-machine value the release must generate). Its ten entries sort cleanly:
  §1, §3's binding step, §4 and §5 are mechanisms; §2, §3's resolved BDF, §7, §8
  and §10 are values; §6 is `[?]`; §9 is a provenance question ADR-031 owns.

*Harder*

- **Test automation becomes the release's critical path.** Every gate this
  project has taken was a delegated session against one machine. A release that
  must re-gate on every upstream security update cannot be gated by hand. This is
  the single largest consequence of this ADR and it is not optional.
- The compositor profile, the bar configuration and the GUI ingress become
  release artefacts with a tier, which means their installation leaves `$HOME` —
  ADR-016's *"manual step until v1.0"* is withdrawn by this ADR for everything
  that participates in the identity path.
- ADR-032 §5's T2 payload enters the manifest; a netVM rebuild is a release act,
  with a release's gates.
- A vendor default the model depends on is either adopted on the record or
  replaced; the first instance is `rp_filter`, and the code pass ADR-035's notes
  already anticipate must treat the choice as T4.
- The base layer updates by reboot. Users of a compartmentalised desktop reboot
  for kernel updates already; they will now reboot for Mesa too. The KatMate
  layer's restartability (ADR-029) is what keeps that from being every update.
- The host storage layout of `ARCHITECTURE.md` § *Storage layout* — a single
  root LV — does not accommodate whole replacement with a fallback. ADR-010's
  host partitioning is reopened by this ADR for the root volume only; the VM
  storage chain is untouched.

*Documentation this ADR requires on acceptance*

- `SECURITY-MODEL.md` § *Controls by component*: per control, its enforcing
  artefact, tier and test (§ 2).
- Revision notes: ADR-004 (§ 7's three meanings); ADR-007 (the pacman-hook
  trigger, superseded by ADR-019/020 and this ADR); ADR-016 (the desktop layer is
  inside the TCB by ADR-026; identity-path configuration is T4 and installs to a
  release-owned path); ADR-020 (the content list extended to the base and to every
  § 1 member); ADR-032 §5 (*"not signed with the ISO"* superseded for T2 payload
  from T4 sources); ADR-012 and ADR-013 (status).
- `ARCHITECTURE.md` gains a host-side release-and-update section, which today
  does not exist; the only update flow it describes is the guest image chain.
- `OBSERVATIONS.md` entries, each with provenance: the Arch archive's retention
  and signature policy; reproducible-builds coverage of the pinned set;
  `linux-hardened`'s release lag against mainline stable over a stated window.

*Open, and named as open rather than decided*

- The signature scheme and manifest format — ADR-013's question, narrowed.
- The composition tooling for the host image (§ 4).
- Whether user theming can remain per-user: measured against the two carriers,
  not assumed.
- Whether the host's kernel config is readable on the running system
  (`/proc/config.gz`) or only from the package — decides where G4 runs.
- Whether a uid-1000 account exists inside netVM, since `cp -a` bakes the
  builder's ownership onto `nftables.conf` (`state.md` § *Invariants*): if it
  does, a T4 artefact is owned by a non-root guest account, which is a placement
  defect in § 3's sense regardless of mode bits.
- The `systemd-sysctl`/udev ordering in netVM (`state.md`, recorded as
  unmeasured), a precondition of any per-slot value.

**Gates — none taken; each has a refusal half:**

- **G1 — the model indexes the unit.** Every control in `SECURITY-MODEL.md`
  § *Controls by component* resolves to a tracked path by `git ls-files` over the
  whole tree, or is marked *documented, not enforced*. *Refusal half:* the GUI
  ingress, as of this ADR, resolves to nothing under the three subtrees the audit
  covered; G1 passes only when that row reads a path or a marker.
- **G2 — the reference host is enumerated.** Every file on the reference host
  outside package ownership and outside the installed T1/T2 trees is listed and
  classified as unit content, installer output, dev scaffolding or unknown.
  *Refusal half:* the count of *unknown* is the number that must reach zero before
  a release candidate; the enumeration reports it rather than hiding it, and the
  first run is expected to find the `katmate-pool@` unit, its drop-in and the dev
  console (gap 15) — all already known — beside things not yet known.
- **G3 — a snapshot re-fetches byte-identical.** A dated Arch snapshot fetched
  twice, weeks apart, yields the same package hashes for the pinned set; the same
  for the Debian snapshot the guest images will pin. *Refusal half:* a package
  that cannot be re-fetched, or re-fetches with a different hash, names the
  archive as a non-contractual input and reopens § 4's source.
- **G4 — the kernel's required-symbol set is read, not assumed.** The set —
  `vsock_diag`, the vsock namespace symbols, `TMPFS_POSIX_ACL`, KVM/VFIO/IOMMU,
  and whatever the boot-hardening backlog adds — is read out of the pinned
  `linux-hardened`'s config, and the reading is compared with the running host's.
  *Refusal half:* a symbol present in the config and absent on the running kernel,
  or the reverse, is the drift class § 1 exists to catch, and the interval of
  2026-08 is its recorded instance.
- **G5 — the refusal fixtures of every invariant run from the release, not from a
  brief.** ADR-035's G2 refusal half in both forms is the first; the waypipe
  version lock's refusal — a mismatched host binary refused before QEMU — is the
  second. *Refusal half:* an invariant with no fixture is marked as such in the
  `SECURITY-MODEL.md` table and blocks the row it belongs to, not the release.

**Revisit when:**

1. **A display domain exists** — a VM owns the GPU and the input controllers and
   the host's package set contains no compositor and no Mesa. Reopen (ii) — an
   own minimal base, now for a host of dozens of packages — ADR-004's form (b)
   (own config, headless), and the Debian question, since § 5's first Arch reason
   has expired.
2. **Debian stable ships a kernel at or above the host floor** (namespace-aware
   vsock, Linux ≥ 7.0) **and** `linux-hardened` is either absent from the Arch
   repositories or its measured lag exceeds the release cadence recorded in
   `OBSERVATIONS.md`. Both halves, because either alone leaves one Arch reason
   standing.
3. **G3 fails** — a pinned snapshot cannot be re-fetched byte-identical. Reopen
   the composition source, not the composition.
4. **G4 fails on a pinned kernel** — a required symbol is absent from a
   `linux-hardened` release the project would otherwise pin. This is ADR-004's
   *hard requirement* clause firing for the first time; its form (c), an own build
   of unmodified sources with the project's config, is then the fallback ADR-004
   itself names.
5. **Open problem #9's preflight has measured GPU and USB-controller groups on
   all three reference machines.** Until then a display domain's feasibility on
   the project's own hardware is unknown and § 6 is a set of constraints without a
   date.
6. **Open problem #22 closes and ADR-013's scheme is decided.** Until the pipeline
   carries and checks the guest kernel's sidecar and a signature covers the
   manifest, verification is at install only, as ADR-034 already rules; when both
   hold, the manifest is verifiable end to end and § 4's verification points can
   be gated.
7. **Gap 6's v1.0 revisit changes the threat model to include physical access.**
   Then boot-time verification — signed UKI, measured boot, TPM sealing — enters
   the unit's verification points; the unit's *contents* are unchanged by that,
   which is the reason they are decided now.
8. **The GUI ingress is located (§ 2).** Not a reopening — a precondition.
   Whichever way it settles, § 2's classification stands; what changes is whether
   `HOST-CONFIG.md` or finding 7 is corrected.
9. **The release cadence is measured and test automation does not keep up with
   it.** If the number of upstream security updates to the pinned set per month
   exceeds what automated gates can re-verify, § 4's two-layer split is
   insufficient and the base-layer composition must be narrowed — fewer packages
   in the TCB path, of which the `qemu-full` → `qemu-base` reduction already
   tracked is the first — before the cadence is met by shipping untested sets.

---

## ADR-037 — netVM's vanilla network stack: direct uplink egress, dnsmasq, dhcpcd, and a read-only config disk

**Status:** Accepted (2026-09-29). The decisions are the operator's rulings of
2026-09-26 (R2–R8, recorded in `state.md`); acceptance waits on the gates
below. Taken on two in-guest reading sessions of 2026-09-26 (`net-up`,
`net-m1`, reports outside the repository). **Proposed is a decision and not an
implementation:** no `addr=`, no `uplink0.link`, no dhcpcd, no dnsmasq and no
config disk exist in the tree or on MINIS.

**Depends on:** [ADR-021](DECISIONS.md#adr-021) (netVM as a sysVM class, its
declarative build and its manifest), [ADR-032](DECISIONS.md#adr-032) (the path
is the tier; T1 is `/etc/katmate/`), [ADR-035](DECISIONS.md#adr-035) (the slot
pool and its `km00`…`km0f` names).
**Supersedes, in part:** ADR-021's premise that netVM egress is ProtonVPN, and
its open DNS-leak decision.

**Numbering:** `ADR-037` is the next free number; `ADR-031` stays reserved.

**Context, measured:**

- **The loaded ruleset only lets traffic out through `oifname "proton"`, and
  netVM has no such interface.** `forward` accepts only `ip saddr
  10.100.1.0/24 oifname "proton"` and its reverse, `nat` masquerades only
  `oifname "proton"`, and no WireGuard link exists (`ip -d link show type
  wireguard` and `wg show` both empty). Read from the ruleset text, not tested
  with traffic. (`net-up-report.md` § 19.3 items 2–3.)
- **netVM has no resolver:** `/etc/resolv.conf` is absent and
  `systemd-resolved` is inactive, while `systemd-networkd` is active.
  (`net-up-report.md` § 19.3 item 8.)
- **Without `resolved`, networkd writes the DHCP DNS only into
  `/run/systemd/netif/leases/<n>`**, a `KEY=VALUE` file whose first line is
  *"# This is private data. Do not parse."* (`net-m1-report.md` § 9.3.)
- **`networkctl status` fails without a bus:** *"Failed to connect to system
  bus: No such file or directory"*, `rc=1`. (`net-m1-report.md` § 9.3.)
- **`dnsmasq` is absent:** `command -v dnsmasq` `rc=1`, and `dpkg-query` finds
  neither `dnsmasq` nor `dnsmasq-base`. (`net-m1-report.md` § 9.4.)
- **The uplink sits at guest `0000:00:04.0`.** `vfio-pci` is the 4th
  `-device` of QEMU's argv, with no `addr=`; every device read sits at slot =
  its argv position. That is consistent with placement by argv order, and not
  shown to be caused by it: no second argv was run. (`net-m1-report.md` § 9.1.)
- **`ID_PATH=pci-0000:00:04.0`** on the uplink, which today falls through to
  `99-default.link`. A `.link` matching on `Path=` has not been observed
  selecting an interface in this guest. (`net-m1-report.md` § 9.2.)
- **The LAN hands out `DNS=1.1.1.1`**, a public resolver, not the router
  (`ROUTER=10.3.1.1`). (`net-m1-report.md` § 9.3.)

**Decision:**

1. **Vanilla egress (R2).** netVM egress in a vanilla KatMate is direct
   through the uplink, with no VPN. VPN is a post-install option that the user
   enables by supplying a WireGuard config file.
2. **Uplink name (R3).** The uplink is named `uplink0`, through a `.link`
   matched on `Path=` (the PCI path inside the guest), not on the MAC. The
   ruleset targets `oifname "uplink0"`.
   *Cross-reference, not a further decision:* on implementation this retires,
   for the uplink, the rule that its interface name is not normative and that
   its netconf is MAC-matched (`state.md` § *Invariants & gotchas*,
   `docs/ARCHITECTURE.md` § *Networking*, and ADR-035's revision note of
   2026-09-20). Until the implementation lands, those statements describe the
   tree correctly.
3. **Pinned address (R4).** The `vfio-pci` device carries `addr=` in the unit,
   so `Path=` is stable by construction.
4. **AppVM DNS (R5).** `dnsmasq` runs in netVM, listening on `10.100.1.1`, and
   forwards to the DNS server the uplink receives.
5. **Uplink DHCP client (R6).** `dhcpcd` replaces systemd-networkd on the
   uplink. dhcpcd writes `resolv.conf` itself, for DHCP and static
   configuration alike, and dnsmasq reads that natively.
   *Rejected:*
   - **A `.path` unit with a generator parsing the lease file** — it reads a
     format systemd marks *"Do not parse"*.
   - **A recursive resolver (unbound)** — it contradicts R5, which forwards to
     the DNS server the uplink receives.
6. **Static addressing (R7).** The uplink may be configured statically. That
   is per-installation configuration (T1), never baked into the image.
7. **Config channel (R8).** Per-installation netVM configuration — the static
   IP, the WireGuard config, and anything later — reaches netVM through a
   **read-only config disk**. The host assembles it from `/etc/katmate/netvm/`,
   and netVM attaches it as an extra `virtio-blk`.
   *Rejected:*
   - **An agent `CONFIG-PUT` operation** — it adds surface to the most exposed
     VM.
   - **Writing into netVM's LV at install time** — a declarative rebuild loses
     it.

   *Cost:* a configuration change needs a netVM restart.

**Gates for acceptance — none taken:**

- **G1 — the pinned address holds.** With `addr=` pinned, the guest sees the
  uplink at the pinned address. *Refusal half:* none named.
- **G2 — the `Path=` `.link` is selected.** `ID_NET_LINK_FILE` names it, and
  the name is `uplink0`. *Refusal half:* none named.
- **G3 — dhcpcd runs without a bus.** A mechanism is gated before acceptance:
  resolved, `networkctl reload` and `networkctl status` are already measured
  inert in this dbus-free guest, so dhcpcd's independence from a bus is
  observed, not assumed. dhcpcd takes a lease on `uplink0` and writes
  `resolv.conf`, and the static configuration reaches the same state.
  *Refusal half:* none named.
- **G4 — dnsmasq answers.** dnsmasq on `10.100.1.1` answers through that
  upstream. *Refusal half:* none named.
- **G5 — pool egress.** A pool-sourced packet leaves through `uplink0`, NATed.
  This needs an AppVM on a slot. *Refusal half:* none named.
- **G6 — the config disk.** A file placed under `/etc/katmate/netvm/` on the
  host is visible read-only in the guest. *Refusal half:* netVM starts with the
  config disk absent, and falls back to DHCP.

**Carried, not decided here:**

- the pool unit, `katmate-pool@.service`, is untracked (`state.md` § *Open
  problems*); R4 changes it;
- the ownership bake defect: `cp -a` in `netvm.sh` leaves the ruleset and the
  network files owned `1000:1000` (`state.md` § *Open problems*);
- `accept_ra` (open problem #24);
- open problem #27;
- `20-uplink.network` and its ProtonVPN comment, which are retired by the
  implementation, not by this ADR's write pass.

**Revision note (2026-09-27, § *Status*, § *Decision* and § *Gates* — the
operator's rulings on the read pass, R10–R28, before any implementation):**
**Status: still PROPOSED.** This note refines the decisions. It implements
nothing, takes no gate, and acceptance still waits on the gates. The rulings
are the operator's of 2026-09-27, given on a read pass of the tree against this
ADR (`adr037-readpass-report.md`, outside the repository, cited as rp). They
continue R2–R9 and are numbered R10–R28. Each one cites the rp question or
divergence it answers.

- **R10 — the pinned slot (R4).** `vfio-pci` carries **`addr=0x4`**. It is
  the only measured slot, and the only one with an `ID_PATH` reading behind
  `Path=pci-0000:00:04.0`. The unit gets comment (6): a guest `addr=` is
  assigned by the argv, not by firmware, so
  [ADR-030](DECISIONS.md#adr-030) §5's ban on a BDF does not apply to it.
  (rp Q-R4a, Q-R4c)
- **R11 — G1 does not discriminate cause, and that is accepted.** With the
  pin equal to today's auto-placed slot, G1's positive half passes
  identically without the pin. The discriminator comes at networking-arc step
  3, when R8's config disk adds the first new device. **Rule from now on:
  every new device in the netVM unit carries an explicit `addr=`.**
  (rp Q-R4b, D7)
- **R12 — the uplink `.link` is `60-katmate-uplink.link`.**
  [ADR-035](DECISIONS.md#adr-035)'s rename build gate (its 2026-09-20 note)
  lands in this rebuild **as a file check**: 17 `.link` files with the
  expected content, the sixteen slots and the uplink. The names are checked
  at runtime by G2, because a chroot renames nothing. (rp Q-R3c, D8)
- **R13 — `netvm.meta` records `UPLINK_PCI_ADDR`.** An automated preflight
  comparing it with the unit's `addr=` is a **new open problem**, not part of
  this step. A mismatch fails closed, and G2 catches it. (rp Q-R3b)
- **R14 — dhcpcd's scope (R6).** dhcpcd is restricted with **`allowinterfaces
  uplink0`**, **`noipv4ll`** and **`ipv4only`**. Vanilla egress is IPv4
  only; IPv6 egress needs its own ADR. **G3 gains a refusal half:** after boot
  and one NETCFG ADD/REMOVE cycle, no `km*` interface carries an address, a
  route or a lease that NETCFG did not program. This is the dhcpcd form of
  [ADR-025](DECISIONS.md#adr-025) Path B's precondition that internal NICs are
  unmanaged. (rp Q-R6c, Q-R6d, D3)
- **R15 — systemd-networkd is disabled in netVM.** After R6 it has no job.
  The agent unit drops `Wants=`/`After=systemd-networkd.service`. (rp Q-R6a)
- **R16 — the dhcpcd package is whichever form pulls in no dbus**, either
  `dhcpcd-base` or `dhcpcd`. The implementation measures this with `apt-get -s`
  in the build chroot and with `dpkg-query` after the build, as part of G3.
  (rp Q-R6b)
- **R17 — dnsmasq binding (R5).** dnsmasq runs in its **default wildcard
  mode**, with neither `bind-interfaces` nor `bind-dynamic`. It uses
  `interface=km*` and `except-interface=uplink0`, and serves **DNS only, with
  no DHCP and no RA.** (rp Q-R5a, Q-R5b)
- **R18 — no loopback resolver.** netVM's `/etc/resolv.conf` **never points at
  a loopback address**. netVM resolves directly upstream, and dnsmasq reads the
  same file. Clear-text DNS to the upstream the uplink receives is **accepted
  for vanilla**. (rp Q-R5c)
- **R19 — the forward return path (R2).** There is no explicit reverse forward
  rule; return traffic goes through `ct state established,related` only.
  **`udp dport 51820` is removed.** (rp Q-R2a, Q-R2b)
- **R20 — VPN residue.** **`wireguard-tools` stays**, because the post-install
  VPN needs it. **`proton.conf.template` is removed**, because a provider
  config is the user's T1 and not T4. The VPN-mode ruleset, kill-switch
  included, is designed at arc step 3 with R8. **Nothing baked in this rebuild
  references `proton`.** (rp Q-R2c)
- **R21 — the finding-12 slot guard is not in this rebuild.** It must land
  **before arc step 4** (the first AppVM on a slot), as its own step with its
  own gate. (rp Q-R2d)
- **R22 — no `icmpv6` accept rule is added.** The absence of any ICMPv6 accept
  in netVM's `input` chain is **load-bearing for open problem #24**, because it
  drops RAs arriving on the slots. `accept_ra` stays at arc step 4.
  (rp Q-R2d; #24)
- **R23 — `nftables.conf` becomes mode `0644`**, in its own commit, because a
  git mode change is its own concern. **`root:root` ownership** of everything
  step 5 of `netvm.sh` bakes is fixed in step 5 itself (open problem #38).
  (rp Q-38)
- **R24 — the agent unit gets one author.** It moves into
  `manifests/netvm.conf.d/` as a tracked file, and the heredoc in `netvm.sh`
  step 7 is removed (open problem #27). (rp Q-27)
- **R25 — G3 is split.** The DHCP half is taken on the arc step-2 build. The
  static half is taken at step 3, with R8. There is no fixture path for T1
  content. (rp D6)
- **R26 — G4 is taken with a fixture peer:** ARP and a UDP DNS query on a
  slot's `appvm` socket, as dev scaffolding in `~/katmate-dev/`, with the
  script quoted in full in its report. **G4 gains a refusal half:** a DNS query
  from the LAN (the MINIS host) to netVM's uplink lease gets no answer.
  (rp § 4, G4)
- **R27 — the rebuild is a dev build** (dev root unlocked), because G2 and G3
  need the console. (rp § 8 item 2)
- **R28 — the rulings are recorded before code** (this note). D5 and D8–D14,
  apart from D13, wait for the write pass after the rebuild.

**Corrections to this ADR's own text.** They are recorded here, and the text
above is left as written:

- **§ *Carried*, the pool unit (rp D1).** The pool unit was folded into the
  shipped unit on 2026-09-27 (`a36bdb2`; ADR-035's note of that date). R4, and
  now R10, target **`katmate-sys-driver@.service`**, not an untracked
  `katmate-pool@.service`.
- **§ *Status*, where the rulings live (rp D4).** R1–R9 are recorded in
  `docs/SESSIONS.md`, rotated out of `state.md` in `019478a`, and not in
  `state.md`.
- **§ *Decision* 2, R3's cross-reference, extended (rp D2).** On
  implementation, R3 (with R6) also retires the following statements, which
  the cross-reference did not name. They are named here, and **none of them is
  changed by this note**. Until the implementation lands, each one still
  describes the tree.
  - ADR-021 § *Decision*, the bake-list bullet
    *"`/etc/systemd/network/20-uplink.network` — MAC-matched DHCP on the vfio
    uplink NIC"*.
  - ADR-025 Path B's **load-bearing fact**, *"the image bakes only the
    MAC-matched `20-uplink.network`, so internal virtio-net NICs are
    networkd-unmanaged"*, and ADR-025's 2026-08-09 note, *"`manifests/
    netvm.conf.d/` carries the MAC-matched **uplink** only"*. R14 carries the
    precondition over to dhcpcd.
  - `state.md` § *Live state*, netVM: *"the uplink comes up MAC-matched"* and
    *"Interface names are not normative"*.

**Revision note (2026-09-27, implementation — the tree, the rebuild, and gates
G1–G4):** **Status: still PROPOSED.** G5 and G6 are untaken, and so is G3's
static half (R25). Acceptance waits on them. This note records the
implementation, the gate results and the operator's rulings of the same day. It
changes no decision above. Sources are outside the repository:
`adr037-impl-A-report.md` (cited as A, the code session on the Acer) and
`adr037-impl-B-report.md` (cited as B, the install, rebuild and gate session on
MINIS).

- **Implemented** in nine commits, `6827583`…`c37f9d1`, pushed and
  server-confirmed (`git ls-remote` returned `c37f9d1`; B, step 15).
- **Built** on MINIS as a dev build (R27): `NETVM_BUILT=2026-09-27T13:01:13Z`,
  kernel `6.12.107+deb13-amd64`. netVM runs on that image under
  `katmate-sys-driver@netvm.service`, whose installed copy equals the tree at
  `c37f9d1` (B § 1).

**Gate results.** All were taken on MINIS on 2026-09-27, and each is quoted
verbatim in B:

| Gate | Pass half | Refusal half |
|---|---|---|
| G1 | **PASS**, 2026-09-27: argv `vfio-pci,host=0000:01:00.0,addr=0x4`; guest `r8169 0000:00:04.0 … RTL8125B, 38:05:25:34:7c:47`; on the new image, sysfs `0x10ec`/`0x8125` at `0000:00:04.0`. **Does not discriminate cause** (R11). | none named |
| G2 | **PASS**, 2026-09-27: `ID_NET_LINK_FILE=/usr/lib/systemd/network/60-katmate-uplink.link`; exactly one `uplink0`; 16 slots on 16 distinct slot `.link` files | none named |
| G3, DHCP half (R25) | **PASS**, 2026-09-27: `dhcpcd` active; no `/run/dbus`; `dbus`, `dbus-daemon` and `dbus-system-bus-common` not installed; `/etc/resolv.conf` `0:0 644` carrying dhcpcd's header and the lease nameserver; lease `10.3.1.103` on `uplink0` | **PASS (ruled)**, 2026-09-27, scoped to dhcpcd-originated state (below) |
| G3, static half | not taken; arc step 3, with R8 (R25) | — |
| G4 | **PASS**, 2026-09-27: a fixture peer on slot 05 got an answer with 4 A records from `10.100.1.1`; `ss` shows the wildcard bind (R17); dnsmasq's argv carries `-I lo` | **PASS**, 2026-09-27: no answer from the uplink lease within 5 s, with a positive control. **Does not discriminate cause:** netVM's `input` chain drops the query before dnsmasq's `except-interface=uplink0` is reached |
| G5, G6 | not taken (G5 needs an AppVM on a slot; G6 needs R8) | — |
| R12 build gate | **PASS**, 2026-09-27: `Build gate OK: 17 katmate .link files — 16 slots, and the uplink on pci-0000:00:04.0` | not exercised on a real image |

**Rulings of 2026-09-27, made during the implementation:**

- **R29 — resolv.conf and dnsmasq's loopback** (on A's divergence V2). As
  given: *"netVM's /etc/resolv.conf is baked as an empty root:root 0644 file
  (dhcpcd's sandbox rewrites it in place and cannot create it), and a tracked
  /etc/default/dnsmasq sets DNSMASQ_EXCEPT="lo" — dnsmasq serves the slots
  only (R17's intent) and never registers itself as the system resolver (R18).
  The unmeasured "unit refuses to start without the file" stays UNVERIFIED."*
  The packaged `dhcpcd.service` carries `ProtectSystem=strict` and
  `ReadWritePaths=… /etc/resolv.conf`, and `netvm.sh` deletes the build-time
  file (A § 0).
- **V1 — `libdbus-1-3` is an accepted cost** (on A's divergence V1). No
  dnsmasq package form avoids it: `dnsmasq-base` `Depends:` on it. It is a
  library with no bus to talk to. The dbus daemon stays absent, and G3
  measured it absent. **The build refuses `enable-dbus`** in
  `/etc/dnsmasq.conf` and `/etc/dnsmasq.d/` (A § 1, C7). dnsmasq is compiled
  with D-Bus support, and it is not enabled (B, step 14).

**R14's refusal half, corrected.** R14 above says that after boot and one
NETCFG ADD/REMOVE cycle, *"no `km*` interface carries an address, a route or a
lease that NETCFG did not program"*. That wording was an overreach. **The
operator ruled (2026-09-27, on G3) that its scope is dhcpcd-originated state
on the slots**: a lease, IPv4LL, an IPv4 address or route, or any dhcpcd
journal line naming `km*`. All of it was absent. The kernel's IPv6 link-local
on a slot that NETCFG raised is outside R14. It was recorded as a finding,
not a gate result (B, the G3 ruling). R14's text is left as written.

**§ *Context*, the `Path=` bullet.** *"A `.link` matching on `Path=` has not
been observed selecting an interface in this guest"* is **now observed**, by
G2 on 2026-09-27.

**A recorded hazard (rp D12): `uplink0` names two objects.** One is the
guest-side interface name that R3 fixes, a T4 constant written into dhcpcd's
`allowinterfaces` and the ruleset's `oifname`. The other is the host-side T1
NIC label (`nic = "…"`, published under `/run/katmate/nics/`), which belongs to
the machine's owner and may be anything. They are the same string in different
tiers, one by derivation and one by convention. **It is not a conflict.** The
comment in `60-katmate-uplink.link` says so.

**UNVERIFIED, carried:**

- R29's premise: that the packaged `dhcpcd.service` refuses to start, or
  cannot create the file, when `/etc/resolv.conf` is absent. The empty baked
  file makes it moot for this image, and it was never measured.
- `ipv4only` and router solicitation on the uplink. The man page says only
  *"Only configure IPv4"*, and no reading was taken on the uplink.
- The refusal half of the `NETVM_UPLINK_PCI_ADDR` preflight. Its pass half ran
  in the 2026-09-27 build; a malformed value has never been run.

**Revision note (2026-09-27, step-3 rulings — the config disk and the static
uplink, R30–R40, before any code):** **Status: still PROPOSED.** G5 and G6 are
untaken, and so is G3's static half. This note records rulings. It implements
nothing, takes no gate, and changes no text above. The rulings are the
operator's of 2026-09-27, given on a read pass of the tree against R7 and R8
(`r8-readpass-report.md`, outside the repository, cited as r8). Its divergence
and question numbers (D1–D14, Q-R8a–Q-R8i) are r8's own, and are **not** the
D-numbers of rp cited in the notes above. Each ruling cites what it answers.

- **R30 — arc step 3 is the config disk and the static uplink.** Its gates
  are G6 and G3's static half. **VPN mode** (the WireGuard config, the VPN
  ruleset and the kill-switch) is **arc step 5**, after arc step 4, under its
  own ADR. It is not called "3b": build-order step 3b is the launch daemon,
  and shipped T4 comments cite it by that name. R30 **supersedes R20's
  scheduling sentence**, *"The VPN-mode ruleset, kill-switch included, is
  designed at arc step 3 with R8"*; the rest of R20 stands. R8's *"the
  WireGuard config"* is therefore arc step 5's, not step 3's. (r8 D9, D11)
- **R31 — the T1 location.** Per-installation netVM configuration lives in
  **`/etc/katmate/vm/<instance>.d/`**, keyed by **instance**, one file per
  concern. Step 3's file is **`uplink`**. The directory holds only concerns
  that are not properties: no key may appear both there and in
  `<instance>.toml`, and **an unknown file is refused**. This **replaces
  `/etc/katmate/netvm/`** in R8 and in G6. How it stands against
  [ADR-032](DECISIONS.md#adr-032) § 1 is recorded in ADR-032's note of this
  date. The modes for a secret are arc step 5's. (r8 D1, D2, D12)
- **R32 — who builds the disk, and where it lives.** A new T4 executable,
  run as an `ExecStartPre=+` **after** `katmate-generate-env`. The image is
  `/run/katmate/cfgdisk/<instance>.img`, in a `root:root 0700` directory, and
  is itself `root:root 0600`, from step 3 on. Its tier is **runtime
  projection**. Like the env file, it is not removed at stop. (r8 D3; Q-R8a,
  Q-R8b)
- **R33 — the format.** A raw **`ustar`** archive with reproducible flags: no
  filesystem on either side, and no mount. The first member is `VERSION`, and
  an unknown version is refused. The guest extracts **named members only**,
  into `/run`. (r8 Q-R8c)
- **R34 — the argv.** The image path is static in the template, built from
  `%i`, so `katmate-generate-env` does not change. The drive carries
  `readonly=on` and **no `cache=none`**. The device carries `addr=0x15` and
  `serial=kmcfg`, and the pair is listed immediately after the root drive's
  pair. **One reading is taken before any code:** the guest PCI enumeration,
  from the host journal, with the command r8 Q-R8d gives. (r8 Q-R8d, D6)
- **R35 — parse and re-emit.** T1 content is parsed, validated and re-emitted
  in canonical form on the host. **It is never copied through** into netVM.
  (r8 D5)
- **R36 — absent versus malformed.** **Absent** means there is no `uplink`
  file: the disk is still built and always attached, without the entry, and
  netVM leases by DHCP. **Malformed, or an unknown file:** the host fails
  closed. The builder refuses and QEMU does not start. **A canonical entry
  the guest cannot parse:** the consumer fails, and because `dhcpcd.service`
  `Requires=` the consumer, there is no uplink. (r8 D4, D7; Q-R8f)
- **R37 — the schema.** The file is flat `key = value`, read by a
  **generalised flat reader in `katmate-lib.sh`**, with `km_t1_read` as its
  wrapper; that refactor is its own commit. The keys are
  `address = "a.b.c.d/nn"`, `gateway`, and `nameservers = "x,y"`. **At least
  one nameserver** is required. Loopback and `0.0.0.0` are refused, and every
  value is IPv4 only. **`validate-properties.fish` is not changed.**
  (r8 Q-R8g)
- **R38 — the guest consumer**, r8 Q-R8e's option (i). A oneshot unit,
  ordered before `dhcpcd`, writes a complete dhcpcd configuration to `/run`. A
  `dhcpcd.service` drop-in runs dhcpcd with `-f` on that file and `Requires=`
  the oneshot. The baked `/etc/dhcpcd.conf` is **never rewritten**. The
  packaged `dhcpcd.service` and its hooks are read in the guest before this
  is written. (r8 Q-R8e)
- **R39 — the gates.** G6: the pass half, and the refusal halves R-a to R-d,
  as r8 Q-R8i proposes them. G3's static half, pass: as r8 Q-R8i proposes.
  G3's static half, refusal: **no DHCP on `uplink0` in static mode**. In the
  guest, no lease newer than boot. On the host, a tcpdump that captures zero
  packets, with a positive control. (r8 Q-R8i)
- **R40 — G1 stays non-discriminating.** There is no fixture argv. R11's
  expectation that *"the discriminator comes at networking-arc step 3, when
  R8's config disk adds the first new device"* does not hold: the config disk
  carries an explicit `addr=` under R11's own rule, and so does not move
  `vfio-pci`. (r8 D8)

**The sequence is r8 § 4's.** One ordering is a hard constraint: the unit
change goes onto the current image, with no T1 (the absent path), **before**
the guest consumer and the rebuild. The static T1 for G3's static half is
written on MINIS by the operator (R25).

**G6, read in the sense of R35 and R36.** G6's text is left as written, and
is read as follows. *Pass half:* a T1 file placed under
`/etc/katmate/vm/<instance>.d/` (R31) reaches the guest read-only as its
**re-emission**, not as the file. *Refusal half:* *"netVM starts with the
config disk absent, and falls back to DHCP"* is the **absent** case of R36 (no
`uplink` file, the disk attached without the entry). The disk itself is never
absent. The refusal halves in substance are R39's R-a to R-d.

**§ *Status*, the implementation sentence** (`wp-0927e-report.md` § 5.4,
accepted by the operator on 2026-09-27). § *Status*'s *"no `addr=`, no
`uplink0.link`, no dhcpcd, no dnsmasq … exist in the tree or on MINIS"* is
false from 2026-09-27 for all but the config disk (implementation note; the
`.link` is `60-katmate-uplink.link`, R12).

**Revision note (2026-09-27, rulings R41–R44 and the two readings taken
before step-3 code):** **Status: still PROPOSED.** This note records four
rulings of the operator of 2026-09-27 and two readings. It changes no text
above.

- **R41 — how arc steps are named.** An arc step number is always written
  **"networking arc step N"**. The clash with build-order step numbers is
  accepted, and the qualifier resolves it. "Networking arc step 5" stays the
  name for VPN mode.
- **R42 — the modes in `<instance>.d/`.**
  `/etc/katmate/vm/<instance>.d/uplink` is **`root:root 0644`**, like
  `<instance>.toml`, and the directory is `root:root 0755`. The builder
  **refuses** a file or directory in `<instance>.d/` that is not owned by
  root, or that is group- or world-writable. The modes for a secret remain
  networking arc step 5's.
- **R43 — the validation R37 left open.** The prefix is **8–30**. The
  address is not the network or the broadcast address of its prefix. The
  gateway is inside the prefix, and is not the address, the network or the
  broadcast. Every nameserver is a unicast IPv4 address outside
  `127.0.0.0/8`, `0.0.0.0/8`, `224.0.0.0/4` and `255.255.255.255`. There are
  **at most 3** nameservers, in a comma-separated list with no spaces and no
  duplicates.
- **R44 — the image size** is whatever `ustar` produces from its content.
  There is no padding and no fixed size.

**R34's reading: the guest PCI enumeration.** Taken 2026-09-27 on the build
machine, read-only, from the host journal of the boot that began 14:32:09
CEST, with the command r8 Q-R8d gives (`journalctl -o cat -b -u
katmate-sys-driver@netvm.service`, filtered on the kernel's `pci
0000:00:xx.x: [vvvv:dddd]` lines). **24 lines, one guest boot**: the unit
started once that boot (15:03:40 CEST), and every line occurs once. `00.0`
is the q35 host bridge (`8086:29c0`); `01.0` is `1af4:1005` (virtio-rng);
`02.0` is `1af4:1053` (virtio-vsock); `03.0` is `1af4:1001` (virtio-blk, the
root); `04.0` is `10ec:8125` (the RTL8125, `addr=0x4`); `05.0`…`14.0` are
sixteen `1af4:1000` (virtio-net, the slot NICs); `1f.0`, `1f.2` and `1f.3`
are `8086:2918`, `8086:2922` and `8086:2930` (ICH9 LPC, AHCI, SMBus). **No
device sits at `00:15`…`00:1e`, so `0x15` is free.** Source:
`r8-impl-A-report.md` § *Step 0.1* (outside the repository).

**R38's reading: the packaged dhcpcd, from the Debian package.** The operator
ruled that the pre-code read R38 asks for is taken from the Debian package
of the exact version installed in netVM, not from the guest: the same bytes
the image installed, with no console. The image carries `dhcpcd` and
`dhcpcd-base`, both `1:10.1.0-11+deb13u4` (`adr037-impl-B-report.md`, the
in-guest `dpkg-query`). Both `.deb`s were fetched from the `deb.debian.org`
pool (`dhcpcd_…_all.deb`, sha256 `945719b6…05eb`, 14188 B;
`dhcpcd-base_…_amd64.deb`, sha256 `5226a174…a062`, 201244 B), and both
hashes match trixie's `Packages` index. The unit is in `dhcpcd`, and the
hooks are in `dhcpcd-base`.
- The packaged `dhcpcd.service`: `Type=forking`, `PIDFile=/run/dhcpcd/pid`,
  `RuntimeDirectory=dhcpcd`, `ExecStart=/usr/sbin/dhcpcd -q -b` (`-q` is
  present, and there is no `-f`), `ExecStop=/usr/sbin/dhcpcd -x`,
  `ProtectSystem=strict`, `ReadWritePaths=/var/lib/dhcpcd /run/dhcpcd
  /etc/dhcpcd.conf /etc/resolv.conf`, `ProtectHome=true`,
  `PrivateDevices=true`, and `PrivateTmp` commented out.
- `/usr/lib/dhcpcd/dhcpcd-hooks/` holds `01-test`, `20-resolv.conf`,
  `30-hostname` and `50-timesyncd.conf`. **The resolv.conf hook is
  `20-resolv.conf`.** Its state lives under `/run/dhcpcd/hook-state`.

Source: `r8-impl-A-report.md` § *Step 0.2* (outside the repository).

**Revision note (2026-09-27, rulings R45 and R46, and the implementation's
additions accepted as rulings):** **Status: still PROPOSED.** This note
records the operator's rulings of 2026-09-27 on the step-3 implementation
(`r8-impl-A-report.md`, outside the repository, cited as A). It changes no
text above.

- **R45 — the unicast rule, for every address the builder accepts** (A § 5,
  items 3–5). `address`, `gateway` and each nameserver must each lie outside
  `0.0.0.0/8`, `127.0.0.0/8`, `224.0.0.0/4` and `240.0.0.0/4`; the last
  includes `255.255.255.255`. R45 **supersedes** R37's narrower *"Loopback and
  `0.0.0.0` are refused"* and R43's nameserver list. **Bare (unquoted) values
  stay accepted**, as they are in `<instance>.toml`; the shared flat reader is
  not forked.
- **A's additions are rulings.** The builder **refuses an octet with a
  leading zero** (`010` is 10 to one parser and 8 to `inet_aton(3)`),
  **refuses a symbolic link** for `<instance>.d/` and for `uplink`, **sweeps
  stale temporary files** of an interrupted earlier run together with the
  previous image, and the guest consumer **logs the config device's sha256**,
  so that G6's host/guest comparison is two journal lines (A § 4, items 2–4
  and 6).
- **R46 — gate fixtures, for the session r8-impl-B only.** That session may
  write under `/etc/katmate/vm/netvm.d/`, and only there, for the host
  refusal fixtures and for the operator's static T1: `address =
  "10.3.1.172/24"`, `gateway = "10.3.1.1"`, `nameservers = "10.3.1.1"`. Each
  fixture is removed after its reading; the static T1 stays when the session
  ends. It is the operator's authorisation under `CLAUDE.md` § *Ask before*,
  and **it does not amend R25 for the product**.

R45 is implemented in `katmate-build-cfgdisk` (`8f6ebd5`): one check applied
to each field on its own, the gateway's before its in-prefix check. With a
prefix of 8 or longer, a gateway inside the prefix of an address that has
passed R45 cannot fail it, so the gateway's check fires only for a gateway
that is also outside the prefix; it is placed first so that the diagnostic
names R45.

**Revision note (2026-09-27, step-3 gates — G6, and G3's static half):**
**Status: still PROPOSED.** G5 is untaken, and acceptance waits on it. This
note records gate results and what they settle. It changes no text above.
The gates were taken on MINIS on 2026-09-27 by the session r8-impl-B
(`r8-impl-B-report.md`, outside the repository, cited as B), on the code of
`r8-impl-A-report.md` (cited as A) and `8f6ebd5`. Each reading is quoted
verbatim in B; the operator accepted B's gate table on 2026-09-27.

- **Implemented** in six commits of A, `e659db3`…`ba11679`, and two of B,
  `8f6ebd5` (R45) and `5bc028a` (R45, R46). The host side was installed on
  MINIS and equals the tree at `5bc028a` (B, Phase 1, 9 of 9 by sha256).
- **Built** on MINIS as a dev build (R27): `NETVM_BUILT=2026-09-27T18:34:22Z`,
  kernel `6.12.107+deb13-amd64`, carrying the consumer, the oneshot and the
  `dhcpcd.service` drop-in (B, Phase 4).

| Gate | Result, 2026-09-27 | Source in B |
|---|---|---|
| G6, pass | **PASS.** The builder names `uplink`: `entries: VERSION uplink (address=10.3.1.172/24 gateway=10.3.1.1 nameservers=10.3.1.1)`, image `sha256=e960fadc…ea1c`. The guest consumer logs the same sha256, `members: VERSION uplink`. `/run/katmate-cfg/dhcpcd.conf` carries the `static` block for `uplink0`. The argv carries `cfg0 … readonly=on` and `virtio-blk-pci,drive=cfg0,addr=0x15,serial=kmcfg`; the guest shows `1af4:1001` at `00:15.0`, and the root stays `/dev/vda`. | Phases 2, 5, 6; gate table |
| G6, R-a (absent) | **PASS.** No `uplink`: the builder logs `entries: VERSION only … the absent path`, image `c9a4e5e4…d406`; the consumer logs the same sha256 and `no uplink entry: dhcpcd leases on uplink0 (ADR-037 R36)`; `uplink0` leased `10.3.1.103`, and `/etc/resolv.conf` carries dhcpcd's header. | Phase 5 |
| G6, R-b (malformed) and R-c (unknown file), with the R42, R45 and symlink refusals | **PASS.** Each refused before QEMU, with 0 QEMU processes and no image: R-b `octet 256 in '10.3.1.256' is greater than 255`; R-c `unknown file wg0`; R42 mode `0666`; R42 owner uid 1000; R45 `key 'gateway': 224.0.0.1 is multicast`; a symbolic link for `uplink`. A valid T1 between them started netVM (the positive control). | Phase 3 |
| G6, R-d (read-only) | **PASS.** `dev=vdb ro=1` in the guest, in the absent boot and in the static boot. | Phases 5, 6 |
| G3, static half, pass | **PASS.** `inet 10.3.1.172/24 … scope global noprefixroute uplink0`, `valid_lft forever`; `default via 10.3.1.1 dev uplink0 src 10.3.1.172`; `/etc/resolv.conf` `0:0 644` with dhcpcd's header and `nameserver 10.3.1.1`; the host's ARP scan finds the uplink MAC at `10.3.1.172`. | Phase 6 |
| G3, static half, refusal (R39) | **PASS.** A host capture of DHCP on the LAN interface read **0 packets** across the static boot; its positive control, across a DHCP-mode restart, read 1 (a DHCP Request from the uplink MAC). In the guest, no lease file is newer than boot, and dhcpcd's journal for the boot has no soliciting, offered, leased, rebind, renew, request, discover or inform line. | Phases 5, 6 |
| G5 | not taken (it needs an AppVM on a slot) | — |

Recorded so that the static readings are not misread: in static mode,
dhcpcd's `resolv.conf` header still says *"from uplink0.dhcp"*, and the
prefix route carries `proto dhcp`. These are dhcpcd's labels for the
interface's configuration source, not evidence of DHCP traffic. The refusal
half measures the traffic directly.

**What the gates settle:**

- **r8 D13 is settled.** dhcpcd's `20-resolv.conf` hook writes the static
  nameserver into the baked `/etc/resolv.conf` (`0:0 644`, dhcpcd's header).
  R38's reading had left it UNVERIFIED until G3's static half.
- **A's H3 reading is observed.** dhcpcd runs with `-f
  /run/katmate-cfg/dhcpcd.conf` under the packaged sandbox, unwidened: the
  unit's effective `ExecStart=` is `/usr/sbin/dhcpcd -q -b -f
  /run/katmate-cfg/dhcpcd.conf`, `status=0`, in both modes. (The argv is read
  from the unit, because dhcpcd rewrites its process title.)
- **Tar reproducibility across two machines.** The absent-path image built on
  MINIS has the sha256 of the one built on the Acer (`c9a4e5e4…d406`). Both
  run GNU tar 1.35. It is **not** claimed across tar versions.
- **§ *Status*, the implementation sentence.** The step-3 rulings note says
  § *Status*'s list is false *"for all but the config disk"*. From
  2026-09-27 the config disk exists too, in the tree (`30b1708`, `0996b70`,
  `ba11679`) and on MINIS (above).

**Not executed, and therefore not claimed (B § 6):** the builder's `trap`
cleanup and stale-file sweep; the refusals of a group-writable or non-root
`<instance>.d/` directory, of `<instance>.d/` as a symlink or a
non-directory, of an unknown or missing key and of a leading-zero octet, as
installed (each ran only in an extracted-block driver, not the executable);
every failure path of the guest consumer on a real image;
`ExecStop=/usr/sbin/dhcpcd -x`; and whether the static T1 holds across a host
reboot.

**Revision note (2026-09-28, step-3a rulings — the finding-12 slot guard,
R47–R56, before any code):** **Status: still PROPOSED (G5).** This note
records rulings. It implements nothing, takes no gate, and changes no text
above. The rulings are the operator's of 2026-09-28, given on a read pass of
the tree against the finding-12 candidate
(`f12-readpass-report.md`, outside the repository, cited as F). F's
divergence and question numbers (D1–D20, Q-F12a–Q-F12j) are F's own. The
rulings **elaborate R21**: the guard is networking arc step 3a, and it lands
before networking arc step 4. Each ruling cites what it answers.

**The candidate is a source for the `slot_guard` chain only.**
`~/Claude.assistent/nftables-f12-candidate.conf` (ADR-035's note of
2026-09-20) predates R2, R3 and R19, and its policy lines revert them (F
D5–D8). Nothing but the chain is taken from it.

- **R47 — the base.** The guard lands on the ruleset at `HEAD`,
  `manifests/netvm.conf.d/etc/nftables.conf`. Nothing else is taken from the
  candidate: its pre-ADR-037 policy lines are not taken (F D5–D8), and its
  header is not carried over (F D10–D13). The ruleset header's statement that
  the guard is not in the file (F § 1.2, N:27–30) is updated **in the same
  commit** that adds the guard. (F Q-F12a)
- **R48 — the pairs.** Sixteen literal rules,
  `iifname "kmkk" ip saddr 10.100.1.(16+k) return`. `build/netvm.sh` gains a
  read-back that checks the sixteen pairs in the **baked** file against
  `km%02x ↔ 10.100.1.(16+k)`, in the same loop as the R12 `.link` gate. A
  mismatch fails the build. (F Q-F12b)
- **R49 — IPv6 on the slots.** An explicit rule, immediately after the
  sixteen `return`s: `iifname { km00 … km0f } meta nfproto ipv6 counter
  drop`, commented that the internal segment is IPv4-only. It has its own
  counter. **R22's role narrows:** the absence of an `icmpv6` accept stays
  load-bearing for `uplink0` and `lo`. On the slots it becomes a second guard,
  behind R49. (F Q-F12c)
- **R50 — segment sources off their slot.** The candidate's rule 17 is
  widened from `10.100.1.16/28` to `10.100.1.0/24`, and excludes `lo`:
  `iifname != "lo" ip saddr 10.100.1.0/24 counter drop`. Because only the
  sixteen true pairs return, it drops every other segment source on any
  interface, `uplink0` included. `lo` is excluded because netVM's own traffic
  to `10.100.1.1` arrives there. It lands in the same commit as the guard,
  because it is one invariant. **The chain, in order:** the sixteen
  `return`s; R49; R50; the candidate's rule 18 (`iifname { km* } counter
  drop`). The chain is jumped as **rule 1 of `input` and of `forward`**,
  above `ct state established,related`. (F Q-F12d, D18)
- **R51 — `rp_filter` is adopted explicitly.** In `30-netvm-forward.conf`,
  in its own commit: `all = 0`, `default = 2` and the glob `* = 2`. These
  are the values [ADR-035](DECISIONS.md#adr-035)'s note of 2026-09-14
  (finding 3) records as read, which the vendor file `50-default.conf`
  produces. The file carries a comment that the binding is the nft guard and
  that `rp_filter` is a loose second defence. **Precondition:** `rp_filter`
  is read on the running image before the rebuild (F D4). If it differs from
  those values, the implementation halts. It is read again after the
  rebuild. (F Q-F12e, D15)
- **R52 — gate F12a, and a build preflight.** **F12a** is taken after the
  rebuild, in the guest as root through the dev console: `nft --version`,
  `nft -c -f /etc/nftables.conf`, `systemctl is-active nftables`, and `nft
  list chain inet filter slot_guard`. **Separately, and not a gate:**
  `build/netvm.sh` runs `nft -c -f` on the baked file in the build chroot, as
  root, and a failure fails the build. **The preflight checks against the
  build host's kernel, not netVM's.** (F Q-F12f)
- **R53 — gate F12b.** A live refusal against **both** `input` (DNS to
  `10.100.1.1`) and `forward` (ICMP echo to `1.1.1.1` via `uplink0`), with two
  fixture peers on two slots (NETCFG ADD). Its four rows, its positive
  control and its instrument are defined in ADR-035's note of 2026-09-28.
  (F Q-F12g)
- **R54 — ARP.** Step 3a closes the **IPv4 half** of finding 12 only.
  **Networking arc step 4 may start with the ARP half (open problem #34)
  open**, because ARP poisoning needs two tenants on slots. **#34 must land
  before the second networked AppVM**, not before the first. (F Q-F12h, D16)
- **R55 — the agent-side pairing check** is deferred to networking arc step
  4, with open problems #19 and #41, where the host assigns slots. Until then
  it is open problem #49. (F Q-F12i, D20)
- **R56 — where it is recorded.** These rulings are this ADR's, because they
  elaborate R21. The gates **F12a** and **F12b** are defined in a note on
  [ADR-035](DECISIONS.md#adr-035) of 2026-09-28, named after gates (a) and
  (b) of its 2026-09-20 note, because its § *Gates* is body. The two notes
  cite each other. **ADR-036 is not touched**; F D17 (its § *Open* is stale
  on the sysctl ordering) is recorded in `state.md` only. (F Q-F12j)

**Not done, and not claimed.** Nothing was implemented, built or run.
F12a and F12b are untaken. `rp_filter` is unread on the current image. F's
**[recall, unverified]** statements — that a rule with no L3 match in an
`inet` table applies to IPv6, how conntrack classes ICMPv6 neighbour and
router traffic, whether loose `rp_filter` passes an off-slot segment source
on `uplink0`, and what `nft -c` in a chroot measures — are still
unverified.

**Revision note (2026-09-28, f12-impl-A — rulings R57 and R58, and three
rulings on the step-3a record):** **Status: still PROPOSED (G5).** This note
records rulings. It changes no text above. The operator gave them on
2026-09-28, the first round on `wp-0928a-report.md` (outside the repository,
cited as W) and the second on the halted read pass of the session f12-impl-A
(`f12-impl-A-report.md` § 0.2, outside the repository, cited as I).

- **R51's provenance wording stands.** *"The values … (finding 3) records as
  read, which the vendor file `50-default.conf` produces"*, in the note
  above, is kept as written (W § 5, item 1).
- **R57 — R51's form.** `30-netvm-forward.conf` states the vendor file's
  three lines **verbatim**: `net.ipv4.conf.default.rp_filter = 2`,
  `net.ipv4.conf.*.rp_filter = 2`, and the exclusion
  `-net.ipv4.conf.all.rp_filter`. It does **not** write an explicit `all =
  0`. `all` stays at the kernel default 0 by the same mechanism the vendor
  file already relies on, and `all` was read as 0 on 2026-09-14. This avoids
  the question of how `systemd-sysctl` orders an explicit key against a glob
  (W § 5, item 2), which is **[recall, unverified]** and is not taken on.
  R51's post-rebuild reading remains the check. The file's comment names it
  as KatMate's adoption of the vendor values, and names the nft guard as the
  binding.
- **W's unauthorised decisions (W § 4, items 1–5) are accepted.** W § 5,
  item 3 is accepted as recorded: F12a is taken in the guest only, and the
  host half of the 2026-09-20 note's gate (a) is not carried.
- **R58 — F12b row 2 splits.** Row 2 of F12b in
  [ADR-035](DECISIONS.md#adr-035)'s note of 2026-09-28 was written without
  applying R50's order, and it is wrong. `10.100.1.1` lies in
  `10.100.1.0/24` and a slot is not `lo`, so R50 drops it before rule 18 is
  reached (I, A1). The row splits: **2a**, `10.100.1.1` on a slot → the R50
  counter; **2b**, an off-segment (TEST-NET) source on a slot → the rule-18
  counter. **The chain order R50 ruled is unchanged.** The correction is
  recorded in a note on ADR-035. The candidate's rule-18 comment, which names
  `10.100.1.1`, is not carried over. Rule 18's comment speaks of off-segment
  sources only.
- **A fixture peer's own MAC is `52:54:01:00:01:kk`** (I, A2), as it was for
  every earlier peer. `52:54:01:00:00:kk` is netVM's side of the slot (§ 2 of
  ADR-035) and appears only as the NETCFG ADD argument. This is a ruling on
  the session's brief, not on the ADR, and it changes nothing here.
- **The R52 preflight adds no mount** (I, A3). `build/netvm.sh` mounts
  `proc`, `sysfs` and `/dev` itself after debootstrap, not through
  `build/lib.sh`, and they are in place when step 5 runs. It calls the
  image's `/usr/sbin/nft` by absolute path, because `chroot_run` sets no
  `PATH`. R48's extraction counts the `slot_guard` chain first, so an absent
  chain dies with a named message under `set -euo pipefail` (I § 0.3).

**Revision note (2026-09-28, f12-impl-B — ruling R59, and the rulings on
f12-impl-A's record):** **Status: still PROPOSED (G5).** This note records
rulings. It changes no text above and takes no gate. F12a and F12b are
untaken. The operator gave these rulings on 2026-09-28, in the third round,
on the session report of f12-impl-A (`f12-impl-A-report.md`, outside the
repository, cited as A).

- **R59 — F12b row 2, once more.** A packet whose source is one of netVM's
  own addresses is expected to be dropped by the kernel as a *martian
  source* at the input route lookup, before any nft hook **[recall,
  unverified]**. If that holds, `10.100.1.1` cannot discriminate R50, and
  R58's row 2a could read +0 on a correct ruleset (A § 5, item 1). Row 2
  therefore becomes:
  - **2a** — a non-pool **segment** source on a slot (`10.100.1.5` on slot
    05) → **the R50 counter, +5**, and `answered=0`;
  - **2b** — unchanged: an off-segment (TEST-NET) source on a slot → the
    rule-18 counter;
  - **2c** — `10.100.1.1` on a slot, an **observation row**, not a counter
    row. It passes if `answered=0` **and exactly one witness accounts for
    all five frames**: either the R50 counter **+5**, or the kernel's
    martian witness — `log_martians` enabled on `km05` for this row only,
    the journal naming `km05` and source `10.100.1.1` five times, together
    with `in_martian_src` in `/proc/net/stat/rt_cache`. The report records
    which witness it was. If neither accounts for the frames, or both
    partly, the session **halts** with both readings.

  The chain order R50 ruled is unchanged. The correction is recorded in a
  note on [ADR-035](DECISIONS.md#adr-035).
- **A § 4, items 1–6, are accepted**, `--rebind-stale` included. PC-2, the
  positive control taken last on re-bound sockets, is the check on it: if
  PC-2 fails, every refusal row is void, and the session halts.
- **A § 6's `state.md` write pass is deferred** until after f12-impl-B, so
  that one write pass records the implementation and the gates together.
  The ruleset header's lines N:4–8 (*"matched only as the aggregate
  10.100.1.0/24, never per-appVM"*) stay as they are.
- **A § 6's two Invariant candidates are accepted:** that `unshare -rn`
  fails unprivileged on the Acer's hardened kernel, so the Acer has no site
  for an `nft -c` syntax check; and that the unprivileged `nft -c` message
  differs by site, while both forms mean "cannot fire". They go into that
  write pass, not into this note.

**Revision note (2026-09-28, step 3a done — the finding-12 guard
implemented, built and gated):** **Status: still PROPOSED (G5).** This note
records what exists and what the gates settle. It changes no text above.
Sources: `f12-impl-A-report.md` (A) and `f12-impl-B-report.md` (B), both
outside the repository.

- **Implemented** in `629c92d` (the `slot_guard` chain, R47–R50),
  `2ca851f` (`30-netvm-forward.conf`, R51 in R57's form) and `56b3c96` (the
  R48 read-back and the R52 preflight in `build/netvm.sh`).
- **Built** on MINIS as a dev build: `NETVM_BUILT=2026-09-28T17:38:12Z`,
  kernel `6.12.107+deb13-amd64` (B, Phase B).
- **Gated:** F12a and F12b PASS, [ADR-035](DECISIONS.md#adr-035)'s note of
  the same date. Networking arc step 3a is done. It closes the **IPv4 half**
  of finding 12 only; the ARP half (open problem #34) must land before the
  second networked AppVM (R54).
- **R52's preflight and R48's read-back executed for the first time**, in
  that build, **on their pass paths**: *"nft preflight OK: the image's nft
  -c -f /etc/nftables.conf exit 0 (build host's kernel; not gate F12a)"* and
  *"Build gate OK: slot_guard carries 16 slot pairs, km00..km0f <->
  10.100.1.16..31, and no other return"* (B, `p4.sh`). Their failure paths
  are UNVERIFIED on a real image.
- **R57's premise held on the observed values:** after the rebuild, `all`
  read 0, and `default`, `km00`…`km0f`, `lo` and `uplink0` read 2, 19 of 20
  conf dirs, identical to the reading before it (B, `rpf-after.out`). The
  presence of the vendor file `50-default.conf` on this image was not read;
  only the outcome was.

**Revision note (2026-09-28, step-4 rulings — the AppVM side, R60–R75,
before any code):** **Status: still PROPOSED (G5).** This note records
rulings. It implements nothing, takes no gate, and changes no text above.
The rulings are the operator's of 2026-09-28, given on a read pass of the
tree against networking arc step 4 (`s4-readpass-report.md`, outside the
repository, cited as S), except R75, which is of 2026-09-15 and recorded
here for the first time. S's divergence and question numbers (D1–D9,
Q-S4-1…Q-S4-14) are S's own. Each ruling cites what it answers.

- **R60 — step 4 is split** (Q-S4-14, D7). In this order: **4.0**, a
  measurement with no code, fixture-grade; **ADR-038**, guest addressing,
  written after 4.0; **4a**, the host side (the template, the generator,
  the slot, `ExecStopPost=`, the delta rename); **4b**, the guest image
  (katmate-init; foundation → app layer → delta); **G5**; **4c**,
  `netvm-agent`, in one rebuild. This list supersedes the step-4 list in
  `state.md` § *Next steps*, *Networking arc*.
- **R61 — the launch vehicle** (Q-S4-1, D1). `katmate-app-routed@.service`
  only, with the removal of the generator's guard (open problem #19) and
  the `REQ_ENV` arm **in one commit**. `katmate-app-offline@` ships with the
  vault instance, not before: a template nobody runs would rot. The
  deletion of the `.con` files ([ADR-030](DECISIONS.md#adr-030) G3) is not
  in step 4. `app_web.con` and `katmate-app-routed@app_web` must never run
  at once (same LVs, same CID).
- **R62 — the slot is [ADR-035](DECISIONS.md#adr-035) §5's `owner` tree**,
  lowest free (Q-S4-2, D4). [ADR-033](DECISIONS.md#adr-033)'s *"another
  field on the same allocation"* as [ADR-017](DECISIONS.md#adr-017)'s is
  superseded by ADR-035 §5 (a note on ADR-033 of the same date). A fixed
  AppVM needs no ADR-017 record for its slot.
- **R63 — the carrier before 3b** (Q-S4-3). Until the launch daemon exists,
  the operator writes `owner` by hand with a dev helper outside the
  repository: exactly the write the daemon will make. The generator, for
  `app-routed`, finds the slot whose `owner` names the instance and takes
  `KM_SLOT` and the `link_id` from it; if none does, it refuses. **No T1 key
  carries a slot.** An `owner` is lost at host reboot, and the start then
  fails closed.
- **R64 — the uid** (Q-S4-4, D3). At step 4 the AppVM's QEMU runs **as
  root**, like netVM's, deliberately, and it is recorded as debt:
  SECURITY-MODEL gap #11 is extended to AppVMs **in the commit that makes it
  true (4a)**, not in this note's pass. C1 (per-VM uids, the ACLs, open
  problem #43) is its own step, for all units together. Until 3b re-issues
  links, a netVM restart requires the AppVM to be restarted.
- **R65 — guest addressing is ADR-038** (Q-S4-5, D5), written after 4.0.
  The candidate on the table, **not decided**: the generator derives
  `KM_GUEST_ADDR` from `KM_SLOT`; the template passes it on the command line
  (`katmate.addr=…`, `katmate.gw=10.100.1.1`); katmate-init applies it,
  brings up `lo`, sets `accept_ra=0` on the interface before it is up, and
  writes `resolv.conf`. With no such parameter, init does nothing (the
  offline path). The image never learns the pool's layout. The alternative
  is a kernel `ip=` with a minimal init; 4.0 informs the choice.
- **R66 — IPv6 in the AppVM** (Q-S4-6) is decided by 4.0's
  `ipv6.disable=1` reading. If it holds, AppVMs are IPv4-only, consistent
  with R49.
- **R67 — `netvm-agent`** (Q-S4-7). R55's pairing check (open problem #49),
  ADR-035 §7's count, §6 (supersession, neighbour delete, conntrack flush)
  and DOWN on REMOVE (open problem #45) land in **4c, in one netVM
  rebuild**, after G5 and before the second networked AppVM, together with
  open problem #34 (R54). G5 requires none of them.
- **R68** (Q-S4-8). A check that `netvm` names an existing
  `provides_network = true` sysVM is a cross-file rule in
  `tools/validate-properties.fish`. The generator reads no second T1; the
  `owner` lookup (R63) implies the pool exists.
- **R69** (Q-S4-9). `test_web.qcow2` is renamed `app_web.qcow2` on MINIS
  ([ADR-032](DECISIONS.md#adr-032) §7 already decided it), and
  `app_web.con:24` follows, in the same step (4a).
- **R70** (Q-S4-10). NETCFG ADD and REMOVE are issued by hand with the R63
  helper; the `link_id` comes from `owner`. Re-issue after a netVM restart
  is 3b's.
- **R71 — G5** (Q-S4-11, D8). D8: G5 reads *"This needs an AppVM on a
  slot"*, and F12b's positive controls PC-1 and PC-2 (ADR-035's note of
  2026-09-28) already matched G5's observable with fixture peers. **G5 is
  taken only with a real AppVM:** it is a composition gate. PC-1 and PC-2
  are recorded as its fixture-level precedent, not as G5. **"NATed"** is
  observed as the AppVM's SYN in a host capture on the LAN with source
  `10.3.1.172`. **G5 gains a refusal half:** the same guest, configured
  with the neighbouring slot's address (`.18` on slot 01), gives R50 +N in
  netVM and 0 in the host capture. One parameter differs between the
  halves.
- **R72** (Q-S4-12, D5). ADR-035 § *Dependencies surfaced*'s *"configures
  its address by hand through the console"* has no mechanism: no guest
  shell, no `ip`, and `vm-agent` is unprivileged. It is corrected by a note
  on ADR-035 of the same date; the path is ADR-038.
- **R73** (Q-S4-13, D6). The stale SHUTDOWN comments in
  `agent/crates/katmate-protocol/src/opcode.rs` and
  `agent/crates/vm-agent/src/op.rs` are fixed in their own commit, in 4c.
- **R74** (Q-S4-14). `ExecStopPost=` unlink of the slot socket: the netVM
  side (all sixteen `netvm` nodes, the hijack window) in 4a; the AppVM side
  (`appvm`) in the `app-routed` template.
- **R75 — socket permissions** (D3). **Ruled by the operator on 2026-09-15,
  never recorded until now:** per-slot POSIX ACLs keyed to per-VM local
  users, not plain `chown`. Its implementation belongs to C1. S found no
  record of it (D3); the operator confirmed it on 2026-09-28.

**Recorded, not ruled.** D2: `KM_HOME_DEV` is not a name mismatch; only
`KM_DELTA` is (`app_web.qcow2` against the live `test_web.qcow2`, which R69
resolves). D9: the ruleset header's *"never per-appVM"* lines stay, as ruled
on 2026-09-28, and are not re-raised.

**Not done, and not claimed.** Nothing was implemented, built or run. G5 is
untaken. S's **[recall, unverified]** statements are still unverified:
whether `ipv6.disable=1` works on a built-in IPv6 and whether `sysctl.` boot
parameters reach per-interface defaults early enough (R66 rests on 4.0's
reading); that the kernel's `ip=` writes no resolver file of its own; and
systemd's dependency propagation for a unit that issues NETCFG.

**Revision note (2026-09-28, step 4.0 done — the first AppVM egress, and
R76, ADR-038's direction):** **Status: still PROPOSED (G5).** This note
records a measurement and rulings. It implements nothing, takes no gate,
and changes no text above. Sources: `s4-m0-report.md` (M) and the
operator's TTL reading over M's captures, whose table is in
`wp-0928d-brief.md`; both outside the repository. The readings are in
[ADR-035](DECISIONS.md#adr-035)'s note of the same date.

- **Networking arc step 4.0 is taken** (R60): `app_web`'s image and kernel
  on slot 01, three boots, a fixture launcher outside the repository, no
  code.
- **M4 is the first AppVM traffic to leave through `uplink0`**: eight SYNs
  from `10.3.1.172` in a host capture, ttl 63 against a LAN host's ttl 64
  in the same capture, the guest's traffic forwarded and NATed by netVM.
- **M4 is not G5.** It has no refusal half (R71), and R60 orders G5 after
  4a and 4b. **Ruling of 2026-09-29:** *"a real AppVM"* in R71 means an
  AppVM started by the 4a template, `katmate-app-routed@`; the s4-m0
  fixture launcher does not count.
- **A' not run; M3 and M4 are settled without it.**
- **R66 is answered by 4.0's reading.** On this kernel (`CONFIG_IPV6=y`,
  built in), `ipv6.disable=1` gave *"IPv6: Loaded, but administratively
  disabled, reboot required to enable"* (M, boot C). This answers the S
  recall item above on whether `ipv6.disable=1` works on a built-in IPv6;
  the `sysctl.` item is not reached by it.
- **R76 — ADR-038's direction: katmate-init (candidate B)** (operator,
  2026-09-28). katmate-init applies the guest's network configuration from
  typed command-line parameters: a `/32` address with an on-link default
  route via `10.100.1.1`, `lo` up, and the resolver `10.100.1.1`. The
  generator derives the address from `KM_SLOT`; the `app-routed` template
  carries it and `ipv6.disable=1` in `-append`. With no parameter, init
  configures nothing (the offline path). **Kernel `ip=` (candidate A) is
  not taken:** its netmask field cannot express a `/32` (M2:
  `255.255.255.255` was replaced by a guessed `/8`), and a `/24`
  contradicts netVM's `/32` peer model. Whether IP_PNP is later removed
  from the AppVM kernel is not decided. **ADR-038 is written in its own
  session**; this note records the direction only.

**Not done, and not claimed.** G5 is untaken. Nothing was implemented or
built. ADR-038 is not written. No conntrack entry was read inside its
expiry window in 4.0, and `IFF_PROMISC` was not read (ADR-035's note).

**Revision note (2026-09-29, R65 decided, and R77):** **Status: still
PROPOSED (G5).** This note records a ruling. It implements nothing, takes
no gate, and changes no text above.

- **R65's candidate is decided by [ADR-038](DECISIONS.md#adr-038)**
  (PROPOSED), in R76's direction: katmate-init applies the guest's address
  from typed command-line parameters. Two things differ from R65's
  candidate as written above. The parameter names are `km.ip`, `km.gw` and
  `km.dns`, not `katmate.addr` and `katmate.gw`. There is no `accept_ra`
  step, because IPv6 is disabled (`ipv6.disable=1`, R66 and R76).
- **R77 — ADR-038 as written** (operator, 2026-09-29): the `km.ip`,
  `km.gw`, `km.dns` parameters, dotted and read from `/proc/cmdline`; the
  one-non-loopback-NIC rule (the operator's (a)); rtnetlink from
  katmate-init in C with no library; strict syntactic parsing, no semantic
  check in the image; an error exits the VM through the shutdown path,
  never `fatal()`'s halt; `/etc/resolv.conf` as the relative symlink
  `../run/resolv.conf`, written by init in `/run`; `lo` up on every boot,
  offline included; gateway and resolver written literally in the
  template, only `KM_GUEST_ADDR` projected; gates G1–G3. ADR-038 is
  **PROPOSED**; no gate is taken.

**Not done, and not claimed.** Nothing is implemented: katmate-init has no
network code, no image carries the resolver symlink, and no template
passes a `km.*` parameter. G5 is untaken.

**Revision note (2026-09-29, step 4a done — R78–R84):** **Status: still
PROPOSED (G5).** This note records rulings, an implementation and its
first execution. It takes no gate and changes no text above. Sources:
`s4a-impl-A-brief.md` and `s4a-impl-A-report.md` (A, the code, on the
Acer), `s4a-impl-B-report.md` (B, install and first start, on MINIS), all
outside the repository.

**The rulings (operator, 2026-09-29).**

- **R78 — the `owner` file's format.**
  [ADR-035](DECISIONS.md#adr-035) §5 gives its content (the instance name
  and the `link_id`), not its format. It is a flat `KEY=VALUE` file in the
  form of the nic label file: `KATMATE_OWNER_VERSION=1`,
  `INSTANCE=<name>`, `LINK_ID=<u32>`. It is read with `km_meta_require`.
  **Every** `owner` present in the netVM's tree, not only the one naming
  this instance, must be a regular file (not a symlink), owned by uid 0,
  not group- or world-writable, version 1, with an `INSTANCE` passing
  `km_check_instance`'s pattern and a decimal `LINK_ID` ≤ 4294967295; any
  failure refuses the start. `owner` decides which address a VM gets: it
  is a trust input.
- **R79 — `LINK_ID`** is read and type-checked, **not projected**: nothing
  in 4a consumes it (NETCFG is issued by hand, R70).
- **R80 — `/home` is required for `app-routed`.** katmate-init mounts
  `/dev/vdb` as a fatal condition, so the template lists the home drive
  unconditionally. The generator refuses `app-routed` with
  `persistence = ephemeral` by an explicit *"not shipped"* diagnostic, in
  the form of the sys-proxy refusal, and `KM_HOME_DEV` is in the
  `app-routed` `REQ_ENV` set.
- **R81 — the AppVM's `ExecStopPost=`** is one `rm -f` of
  `/run/katmate/link/${KM_NETVM}/${KM_SLOT}/appvm`: one path, no shell, no
  glob; both scalars are typed by the generator. netVM's is one
  `ExecStopPost=` with sixteen literal paths.
- **R82 — no `Requires=`/`After=` on the netVM unit.** A unit file cannot
  name the netVM from T1; the `owner` lookup is the precondition (R68),
  and a netVM restart requires the AppVM to be restarted (R64).
- **R83 — step 4a is split** into A (code, on the Acer) and B (on MINIS:
  install, rename, T1, `owner`, NETCFG, start and stop observed). The
  memory backend (hugepages, from `app_web.con`) is carried unchanged; it
  belongs to the memory session. The serial console goes to the journal,
  as in `katmate-sys-driver@`.
- **R84 — the projection is removed first** (A's D1). The template's first
  `ExecStartPre=` is `+/usr/bin/rm -f /run/katmate/vm/%i.env`. A start
  refused before the generator (by `katmate-check-image`,
  `katmate-check-waypipe` or `katmate-activate-lvs`) would otherwise leave
  the previous start's projection standing, since it survives stops and
  failed starts ([ADR-032](DECISIONS.md#adr-032)'s note of 2026-08-22), and
  R81's `rm -f` would unlink the `appvm` of a slot this instance may no
  longer hold, possibly a live AppVM's. `katmate-sys-driver@` does not get
  the line.

**On A's halt.** D1 is R84. D2 is accepted: R80's generator refusal cannot
be reached through the unit, because `katmate-activate-lvs` refuses
`persistence = ephemeral` first. It is written as ruled and reached only
by calling the generator directly.

**The four commits (A).** `bb6801d` — the generator emits `KM_MAC_INT` for
an attached AppVM only (open problem #41). `1597445` —
`katmate-sys-driver@`'s sixteen-path `ExecStopPost=` (R74). `d6feb9c` —
`app-routed` ships (R61): the guard removed, the slot lookup and the
`REQ_ENV` arm in the generator, `katmate-app-routed@.service`, and
SECURITY-MODEL gap 11 extended to AppVMs (R64). `46f8a26` —
`app_web.con`'s instance is `app_web` (R69).

**The first execution (B, MINIS, 2026-09-29).** The installed set equals
the tree at `46f8a26`, and the delta is renamed `app_web.qcow2` (R69).

- **P4, no `owner`:** the generator refused at the owner lookup (*"no slot
  in /run/katmate/link/netvm has an owner naming instance 'app_web'"*),
  before QEMU; no projection was written.
- **P6, the start:** with an `owner` naming `app_web` on slot 01 and link
  201 added by hand, the unit started. The projection carried
  `KM_NETVM=netvm`, `KM_SLOT=01`, `KM_GUEST_ADDR=10.100.1.17` and
  `KM_MAC_INT=52:54:00:6f:19:35`. QEMU's MainPID was bound to
  `/run/katmate/link/netvm/01/appvm`, and the agent answered PING about
  5 s after the start.
- **P7, a clean stop:** after SHUTDOWN, slot 01's `appvm` was absent;
  attributed to `ExecStopPost=` by inference, since its execution record
  was not retained.
- **P8, R84 observed:** a start refused at `katmate-check-image` with the
  previous projection present left no projection; `ExecStopPost=`
  expanded `KM_NETVM` and `KM_SLOT` empty (systemd logged both as unset),
  and a sentinel at slot 01's `appvm` path survived.
- **P9, R80 by direct call:** `katmate-generate-env katmate-app-routed`
  on a probe T1 with `persistence = ephemeral` refused with R80's
  diagnostic, exit 1, no projection.

**Not exercised:** R78's refusal paths (a symlinked, non-root, group- or
world-writable `owner`; a wrong version, `INSTANCE` or `LINK_ID`; two
`owner` files naming one instance) and the absent-pool refusal. Only the
zero- and one-owner cases ran. **Not read:** the uid the AppVM's QEMU runs
as; SECURITY-MODEL gap 11's *"as root"* is a reading of the unit.

**This is not G5.** The guest has no address: its image predates
[ADR-038](DECISIONS.md#adr-038), and katmate-init ignores `km.*`. G5
follows 4b.

**Revision note (2026-09-29, step 4b done):** **Status: still PROPOSED
(G5).** This note records a step's completion; it takes no gate and
changes no text above. Sources: `s4b-impl-A-report.md` and
`s4b-impl-B-report.md`, outside the repository; the detail is in
[ADR-038](DECISIONS.md#adr-038)'s note of the same date.

- **Step 4b is done.** katmate-init applies ADR-038 (`04672b8`, with tests
  in `3b06005`), and the layer builds carry the resolver link with its
  read-back (`d6d0006`, tests in `647a380`). On MINIS the chain was rebuilt
  — foundation → app layer → delta — and `app_web`, started by
  `katmate-app-routed@` on slot 01, configured its own `/32`, route and
  resolver from `km.*`. A DNS query through `10.100.1.1` was answered: an
  AAAA record, which is **not tied to IPv4 egress**. ADR-038's G1
  (positive half) and G3 are passed (R89, R90).
- **G5 is untaken.** Its refusal half (R71: the neighbouring slot's
  address) needs a `-append` the template cannot produce, because the
  address is derived from the slot. **The vehicle is the operator's ruling
  in the next session.**

**Acceptance note (2026-09-29) — what acceptance rests on, gate by gate,
and what stays carried:** the status line above was changed from
`PROPOSED (2026-09-26)` to `Accepted (2026-09-29)` in place. That is this
file's practice for that one line and only that line, on the precedent of
[ADR-033](DECISIONS.md#adr-033)'s acceptance note (2026-08-28) and
[ADR-034](DECISIONS.md#adr-034)'s (2026-09-01). The rest of § *Status* is
left as written. Its *"acceptance waits on the gates below"* is discharged
by this note, and its implementation sentence was already superseded by
the notes above. The body stays append-only. Acceptance is the operator's
ruling **R96** (2026-09-29). G5's verdicts are **R95**. Sources, outside
the repository: `s4-gates-report.md` (G5's readings) and this pass's
report, `wp-0929d-report.md` (the P-check below).

**What acceptance rests on, gate by gate.** Every gate below was taken on
MINIS.

| Gate | Verdict | Where recorded |
|---|---|---|
| G1 | PASS, 2026-09-27; does not discriminate cause (R11, R40) | the implementation note |
| G2 | PASS, 2026-09-27 | the implementation note |
| G3, DHCP half | PASS, 2026-09-27; its refusal half PASS as ruled, scoped to dhcpcd-originated state | the implementation note |
| G3, static half | PASS, 2026-09-27, pass and refusal (R39), with a positive control | the step-3 gates note |
| G4 | PASS, 2026-09-27; its refusal half PASS, and it does not discriminate cause | the implementation note |
| G6 | PASS, 2026-09-27, the pass half and R-a to R-d | the step-3 gates note |
| G5 | **PASS, both halves, 2026-09-29 (R95)** | below |

R21's condition, that the finding-12 guard lands before the first AppVM
on a slot, is met: F12a and F12b passed on 2026-09-28 (the step-3a note;
[ADR-035](DECISIONS.md#adr-035)'s note of that date).

- **G5, positive half — R95, PASS.** The AppVM was started by the shipped
  template, `katmate-app-routed@app_web`, with no drop-in, so it is a real
  AppVM in the sense of R71's ruling of 2026-09-29. It configured itself
  from `km.*` (`net: eth0 10.100.1.17/32 via 10.100.1.1 dns 10.100.1.1`).
  A host capture on the LAN interface, filtered on `tcp port 8099`, held
  one SYN from **`10.3.1.172`**, netVM's uplink address, to
  `10.3.1.3:8099`, with **ttl 63**. That is R71's *"NATed"* observable:
  forwarded one hop and masqueraded, not originated by netVM. **R50's
  counter read 25 → 25.** `km01`'s `rx_packets` read 18 → 21.
- **G5, refusal half — R95, PASS.** The same guest on the same slot carried
  `km.ip=10.100.1.18`, slot 02's address, through [ADR-038](DECISIONS.md#adr-038)'s
  R92 vehicle. **One parameter differs:** `diff` of the effective
  `ExecStart=` shows one line, `km.ip=${KM_GUEST_ADDR}` → `km.ip=10.100.1.18`.
  The console read `net: eth0 10.100.1.18/32 via 10.100.1.1 dns
  10.100.1.1`. **R50's counter read 25 → 30 (+5 packets, +300 bytes)**, and
  R49 and rule 18 were unchanged. **The host capture held 0 packets** of any
  kind across 15:56:00–16:00:01 CEST, a window that contains the guest's
  attempt at 15:58:36. The guest's `connect` ended at the 5 s `timeout`
  (`rc=124`).
- **G5's positive half, and what the guest saw.** The guest's `connect`
  failed at once with *"No route to host"* (`rc=1`), in the same second as
  the captured SYN, and the capture holds no answer. **The P-check**
  (MINIS, 2026-09-29, read only) found exactly one `reject` in the host's
  live ruleset. It is in `inet filter input`: `meta pkttype host limit rate
  5/second burst 5 packets counter … reject with icmpx admin-prohibited`
  (`/etc/nftables.conf:18`). **This confirms the mechanism on the host's
  side:** the host answers a packet addressed to it on a port it does not
  accept with ICMP administratively-prohibited. That netVM's conntrack
  carried the answer back through the NAT to the guest is the inference,
  and it is not observed. Attribution is not shown either: the rule's
  counter (14 packets) was not read before and after G5's positive half,
  and no ICMP was captured on either side. That Linux reports this ICMP to a
  connecting socket as `EHOSTUNREACH` is recall, not read here. G5 names
  egress, and the SYN shows it. The return path is not part of G5.

**Due on implementation, and where each stands.** § *Decision* 2's
cross-reference and the D2 extension in the note of 2026-09-27 (§
*Status*, § *Decision* and § *Gates*) are recorded where they point:
[ADR-021](DECISIONS.md#adr-021)'s two notes of 2026-09-27 (the bake-list
bullet retired, and *"both retirements landed"*),
[ADR-025](DECISIONS.md#adr-025)'s note of 2026-09-27 (Path B's load-bearing
fact), [ADR-035](DECISIONS.md#adr-035)'s note of 2026-09-27 (the rename
build gate), and dated notes in `state.md`. ADR-021's note of 2026-09-26
records § *Supersedes, in part*. `20-uplink.network` is not in the tree.
`docs/ARCHITECTURE.md` and `docs/HOST-CONFIG.md` §9 are brought into line
with this ADR in the same pass as this note.

**What stays carried.** None of this is a condition of acceptance, and
acceptance does not do it.

- **Networking arc step 4c (R67)**, in one netVM rebuild: R55's pairing
  check (open problem #49), [ADR-035](DECISIONS.md#adr-035) §7's count and
  §6 (supersession, neighbour delete, conntrack flush), DOWN on REMOVE
  (#45), and the ARP half of finding 12 (#34, R54). It lands **before the
  second networked AppVM**. R73's SHUTDOWN comments (#51) go in their own
  commit.
- **VPN mode** is networking arc step 5, under its own ADR (R30).
- **UNVERIFIED, carried:** R29's premise; `ipv4only` and router
  solicitation on the uplink; the refusal half of the
  `NETVM_UPLINK_PCI_ADDR` preflight; the failure paths of R52's preflight
  and R48's read-back (#50); step 3's paths not run as installed (#46);
  and the fail-open case of a failed `nftables.service` (#48).
- **Not read:** the uid the AppVM's QEMU runs as (R64, SECURITY-MODEL gap
  11; C1 is its own step), and what makes up `km01`'s +3 and +6 frames in
  G5's two halves.

---

## ADR-038 — AppVM guest addressing: katmate-init applies a `/32` from typed `km.*` command-line parameters

**Status:** Accepted (2026-09-29). The direction is the operator's ruling R76
(2026-09-28, [ADR-037](DECISIONS.md#adr-037)'s note of that date); the
parameter names, the interface rule, the mechanism, the failure mode, the
resolver file and `lo` are the operator's rulings of 2026-09-29, recorded
here. Acceptance waits on the gates below. **Proposed is a decision and not an
implementation:** `init/katmate-init.c` has no network code, no image carries
the resolver symlink, and no template passes a `km.*` parameter.

**Depends on:** [ADR-025](DECISIONS.md#adr-025) (`10.100.1.1` as the gateway
constant; rtnetlink as the configuration path, Path B),
[ADR-032](DECISIONS.md#adr-032) (one path to the profile; the generator's
projection), [ADR-035](DECISIONS.md#adr-035) (§3: every slot's netVM end is
`10.100.1.1/32`; §4: slot `k`'s peer is `10.100.1.(16 + k)`),
[ADR-037](DECISIONS.md#adr-037) (R5: dnsmasq answers on `10.100.1.1`; R60:
this ADR precedes 4a; R63: `KM_SLOT` comes from `owner`; R66; R76).
**Closes:** ADR-035 § *Dependencies surfaced*, first item — *"How the AppVM
end learns `10.100.1.(16+k)/32` and its route to `10.100.1.1`"* — and ADR-037
R65, whose candidate this ADR decides.

**Numbering:** `ADR-038` is the next free number; `ADR-031` stays reserved.

**Context, measured or read:**

- **Kernel `ip=` cannot express a `/32`.** A netmask field of
  `255.255.255.255` was replaced: *"Guessing netmask 255.0.0.0"*; the gateway
  was kept. Observed 2026-09-28 on the AppVM kernel, boot A of step 4.0
  (`s4-m0-report.md`, M2; ADR-035's note of 2026-09-28).
- **`ipv6.disable=1` works on this kernel** (`CONFIG_IPV6=y`, built in):
  *"IPv6: Loaded, but administratively disabled, reboot required to enable"*
  (M, boot C; ADR-037's note of 2026-09-28).
- **An AppVM on slot 01 with `10.100.1.17` egresses through netVM**: ttl 63
  against a LAN host's 64 in the same host capture (M4). The guest was
  configured by the fixture's kernel `ip=`; the path, not the mechanism, is
  what 4.0 showed.
- **katmate-init has no network code.** It mounts `/proc` first
  (`init/katmate-init.c:122`), is the only root code in the guest (its
  header, *"Privilege model"*), and starts `vm-agent` with an explicit
  `envp` of five entries (`:269–276`), so nothing from PID 1's own
  environment reaches the agent or the applications. On an error it calls
  `fatal()` (`:91–97`), which logs and then `pause()`s forever: the guest
  stays up and QEMU keeps running.
- **Every layer build writes `/etc/resolv.conf` through the image path.**
  `build/foundation.sh:118` and `build/app-layer.sh:57` run
  `cp /etc/resolv.conf "$MNT/etc/resolv.conf"` (*"build-time DNS only"*) and
  remove it afterwards (`foundation.sh:229`, `app-layer.sh:65`). `cp` follows
  a symlink at its destination, and that resolution happens on the host, not
  in the chroot.
- **The kernel withholds dotted parameters from PID 1.** In `init/main.c`
  (`unknown_bootoption`), a parameter whose name contains a `.` is taken as
  an unused module parameter and is passed neither to init's environment nor
  to its argv; it remains in `/proc/cmdline`. An undotted `key=value` is put
  into init's environment and logged as *"Unknown kernel command line
  parameters … will be passed to user space"*. **Read from the kernel source,
  not observed on this kernel** (G1 observes it).

**Decision:**

1. **Three parameters, dotted, on the kernel command line.**

   | Parameter | Example (slot 01) | Meaning |
   |---|---|---|
   | `km.ip=` | `10.100.1.17` | the guest's address; the prefix is always `/32` and is not a parameter |
   | `km.gw=` | `10.100.1.1` | the next hop of the on-link default route |
   | `km.dns=` | `10.100.1.1` | the only `nameserver` line of the resolver file |

   The `km.` prefix matches the host's `KM_*` projection names. katmate-init
   reads them from `/proc/cmdline`; the kernel does not hand them to PID 1
   (§ *Context*), and katmate-init does not take them from its environment.
2. **Presence of `km.ip` selects the routed path; absence of all three is the
   offline path.** With no `km.*` parameter, init configures no address and
   no route and writes no resolver file (R76). A NIC present on the offline
   path is left down.
3. **Parsing is strict and syntactic only.** Each of the three appears at
   most once; a set is all three or none; each value is a dotted quad as
   `inet_pton(AF_INET)` accepts it; any other `km.*` key is an error. **init
   does not check meaning** — not that `km.ip` lies in `10.100.1.16/28`, not
   that `km.gw` is `.1`. The image never learns the pool's layout (R65); the
   generator is where the address is derived and where it is checked.
4. **The interface is the one non-loopback link (the operator's (a)).** On
   the routed path init enumerates links and requires exactly one that is
   not loopback; zero or more than one is an error. No MAC is matched: the
   NIC carries the instance-derived identity MAC (ADR-035 §2 and §9), which
   is decided but which the image does not know; matching on it would need a
   fourth parameter for a guest that has one NIC. *Revisit* item 1 names when
   this changes.
5. **Mechanism: rtnetlink from katmate-init, in C, with no library** — the
   same path `netvm-agent` uses (ADR-025, Path B). In this order: the NIC up;
   `km.ip/32` on it; a default route via `km.gw` with `RTNH_F_ONLINK` on that
   NIC. One netlink socket, opened and closed before `vm-agent` starts. The
   ioctl path is not taken: with a `/32`, `SIOCADDRT` rejects the gateway as
   unreachable unless a host route to it is added first, which is two routes
   where one suffices.
6. **`lo` is brought up on every boot, routed and offline alike.** It carries
   no external traffic, and applications assume it. This changes the offline
   path, where nothing in init brings `lo` up today.
7. **The resolver file lives in `/run`.** The image carries `/etc/resolv.conf`
   as a **relative** symlink, `../run/resolv.conf`; on the routed path init
   writes `/run/resolv.conf` (`root:root 0644`, one line,
   `nameserver <km.dns>`) on the tmpfs it mounts. Nothing is written into the
   root delta, nothing survives a boot, and on the offline path the symlink
   dangles, which is *"no resolver"*. **Relative, because of the build
   scripts' `cp`** (§ *Context*): through an absolute `/run/resolv.conf`
   link, a build's `cp` would write the **host's** `/run/resolv.conf`;
   through a relative one it lands inside the image. **Every layer build ends
   with `/etc/resolv.conf` as that symlink, checked by read-back**: a build
   step that writes a build-time copy through the link removes that copy
   (`$MNT/run/resolv.conf`, which would otherwise stay in the image beneath
   init's `/run` tmpfs) and leaves the link in place; a layer whose read-back
   differs is refused before freeze.
8. **Everything happens before `vm-agent` starts**, after the pseudo-file
   systems, as the root PID 1. An application started by RUN finds the
   network already configured; there is no window in which the agent runs on
   a half-configured guest.
9. **An error exits the VM; it does not halt it.** A parse error, a wrong
   interface count or a netlink error is logged on the serial console with
   the reason and the offending token, and init leaves through its shutdown
   path (`/home` unmounted, `reboot(RB_AUTOBOOT)`, QEMU exits under
   `-no-reboot`). `vm-agent` is never started. `fatal()`'s halt is not used
   for these errors: a halted guest keeps QEMU running with nothing
   answering, and looks like a slow boot.
10. **What the host passes, and from where.** The generator derives
    `KM_GUEST_ADDR` = `10.100.1.(16 + KM_SLOT)` for `app-routed` (R63 supplies
    `KM_SLOT`). The `katmate-app-routed@` template's `-append` carries
    `km.ip=${KM_GUEST_ADDR} km.gw=10.100.1.1 km.dns=10.100.1.1
    ipv6.disable=1`. The gateway and the resolver are ADR-025's constant and
    are **written literally in the template**, never projected — the same
    rule ADR-035 §2 applies to the slot MAC. Only the address is projected.
11. **init logs what it applied**, one line on the console, e.g.
    `net: eth0 10.100.1.17/32 via 10.100.1.1 dns 10.100.1.1`, and on the
    offline path `net: offline (no km.ip), lo up`.

**Alternatives rejected:**

- **Kernel `ip=` (candidate A of R65).** Its netmask field cannot carry a
  `/32` (M2), and a `/24` contradicts ADR-035's `/32` peer model. It also
  writes no resolver file, so init would need network code anyway.
- **A privileged NETCFG in `vm-agent`.** It revises the opcode table and puts
  `CAP_NET_ADMIN` into the unprivileged half of the guest, the half that
  parses protocol input.
- **A config disk read by init** (netVM's R8 pattern). A device and a file
  format to carry three scalars; justified for netVM's per-installation
  secrets, not here.
- **Undotted names (`km_ip=`).** They arrive in PID 1's environment, and the
  kernel logs every one of them as unknown on every boot.
- **The gateway and resolver as constants inside init.** Shorter command
  line, but it puts a network constant into the image; with parameters the
  generator and the template stay the only place addressing lives.
- **Matching the interface by MAC (the operator's (b)).** Consistent with the
  project's other `.link` matches. The MAC is decided — the instance-derived
  identity MAC (ADR-035 §2) — but the image does not know it, so a `km.mac=`
  would have to carry it: a fourth parameter to select among one NIC. One NIC
  per AppVM is the model.
- **`/etc/resolv.conf` written by init into the root delta.** It persists into
  the next boot, including an offline one; and root being writable is not
  something this ADR should depend on.

**Consequences:**

- **AppVMs are IPv4-only.** R66 made it conditional on 4.0's reading, the
  reading held, and R76 carries `ipv6.disable=1` on the routed path. There is
  therefore no `accept_ra` step (open problem #24, AppVM half).
- katmate-init's *Responsibilities* grow by one item, still before the agent,
  still root-only; its header changes with the code (4b).
- The foundation build and the app-layer build each gain the symlink and its
  read-back; the instance delta is not built by a script that touches
  `/etc/resolv.conf`.
- The kernel's `CONFIG_IP_PNP` is no longer used by any path. Whether it is
  removed from the AppVM kernel stays undecided (R76).

**Gates — none taken; each has a refusal half.** Taken on MINIS with an AppVM
started by `katmate-app-routed@` on slot 01. In-guest readings are made in a
`foot` window as uid 1000 (`cat /proc/net/fib_trie`, `/proc/net/route`,
`/etc/resolv.conf`, `readlink /etc/resolv.conf`); **that window opens on
MINIS's screen**, so the operator is at MINIS for them.

- **G1 — the routed path.** The console shows init's `net:` line; the guest
  holds exactly `10.100.1.17/32` on its one NIC, a default route via
  `10.100.1.1` on that NIC, and `nameserver 10.100.1.1` in the resolver file;
  `lo` is up; the serial log has no *"Unknown kernel command line
  parameters"* line naming a `km.` key. *Refusal half:* the
  same unit with one parameter changed to an unknown key (`km.ipx=`) — the
  console shows the error and the token, `vm-agent` never starts, QEMU exits,
  and a capture on the slot's netVM end shows no frame from the guest.
- **G2 — the offline path.** An AppVM started with no `km.*` parameter: no
  address on any interface but `lo`, no route but `lo`'s, the resolver
  symlink dangling, `lo` up, and init's `net: offline` line. *Refusal half:*
  `km.gw=10.100.1.1` alone — refused as a partial set, not taken as offline.
- **G3 — the symlink survives the layer chain.** After the foundation build
  and after the app-layer build, `readlink` on the frozen layer's
  `/etc/resolv.conf` returns `../run/resolv.conf`, the layer's `/run` holds
  no `resolv.conf`, and the host's
  `/run/resolv.conf` is unchanged across both builds (sha256 before and
  after). *Refusal half:* a layer whose build leaves a regular file there is
  refused by the build's read-back before freeze.

**Carried, not decided here:**

- **The unit is expected to end inactive, not failed, when init refuses**
  (§9): under `-no-reboot` QEMU is expected to exit 0 whichever way the guest
  reboots — **expected, not observed**; G1's refusal half reads the exit
  status and the unit state. Telling an init
  refusal from a clean shutdown on the host is open problem #21's (the host
  observing the agent answer), not this ADR's.
- The vehicle for G2 at 4b (whichever offline start exists then).
- Re-issue of NETCFG after a netVM restart (3b; R64).

**Documentation this ADR requires on acceptance:**

- `docs/ARCHITECTURE.md` § *Networking*: the AppVM end is configured by
  katmate-init from `km.*`, not by NETCFG; NETCFG programs netVM's end only.
  The opcode table is unchanged (NETCFG stays absent in `vm-agent`).
- A revision note on [ADR-033](DECISIONS.md#adr-033): *"NETCFG then programs
  the `/32` inside each guest exactly as it does today"* is superseded for the
  AppVM end by this ADR.
- `init/katmate-init.c`'s header (*Responsibilities*, *Host-side
  requirements*), with the code.

**Revisit when:**

1. **An AppVM needs a second NIC** — then §4's one-NIC rule gives way to a
   match on the identity MAC (ADR-035 §2), passed as a typed `km.mac=`.
2. **The AppVM root becomes read-only** — §7 already writes nothing there;
   the symlink is the only root-side artefact and is baked, so nothing
   changes; recorded so the question is not reopened.
3. **IPv6 is wanted in an AppVM** — reopen R66 and #24 together; `km.*` would
   gain typed IPv6 parameters rather than any autoconfiguration.

**Revision note (2026-09-29, the host half of §10):** **Status: still
PROPOSED.** This note records the implementation of §10's host half and
what its first run showed. It takes no gate and changes no text above.
Sources: `s4a-impl-A-report.md` (A) and `s4a-impl-B-report.md` (B), both
outside the repository; the rulings are in
[ADR-037](DECISIONS.md#adr-037)'s note of the same date.

- **§10's host half is in `d6feb9c`.** The generator derives
  `KM_GUEST_ADDR = 10.100.1.(16 + KM_SLOT)` for `app-routed`, from the slot
  whose `owner` names the instance (R63, R78), and nowhere else. The
  `katmate-app-routed@` template's `-append` carries
  `km.ip=${KM_GUEST_ADDR} km.gw=10.100.1.1 km.dns=10.100.1.1
  ipv6.disable=1`, the gateway and the resolver written literally.
- **On MINIS (B, 2026-09-29)** `katmate-app-routed@app_web` started on
  slot 01 with `KM_GUEST_ADDR=10.100.1.17`. The guest kernel's command line
  carried the four tokens (console lines 16 and 88), and `ipv6.disable=1`
  took effect. **No *"Unknown kernel command line parameters"* line
  appeared, and that reading has no positive control** (B § 5.2): no
  parameter this kernel does not know was passed in that boot, so it is not
  shown that this kernel prints the line at all. § *Context*'s claim about
  dotted parameters is therefore **not yet observed**; it is consistent
  with this boot, and G1 still reads it.
- **§ *Status*'s *"no template passes a `km.*` parameter"* no longer holds
  for the tree**, nor on MINIS. The rest of that sentence stands:
  katmate-init has no network code and no image carries the resolver
  symlink. The guest half is networking arc step 4b; G1–G3 remain.
- **§ *Carried*'s *"inactive, exit 0"*, and how G1 reads it.** After a
  clean SHUTDOWN the journal says *"Deactivated successfully"*, with no
  *"Main process exited, code=…"* and no *"Failed with result"* line. The
  unit's `Result` and `ExecMainStatus` could not be read: systemd collects
  an inactive, non-failed instance, and `systemctl show` then returns
  defaults (B § 5.1). **G1's refusal half therefore reads the journal, not
  `systemctl show`**, for the unit's end state; this is the gate's reading
  method, and it replaces *Carried*'s *"reads the exit status and the unit
  state"*.

The guest ignored the parameters: its image predates this ADR. Nothing
here is G1.

**Revision note (2026-09-29, step 4b — the guest half, G1's positive half,
G3):** **Status: still PROPOSED** — G1's refusal half and G2 (both halves)
are untaken. This note records rulings, the guest half's implementation
and its first execution; it changes no text above, and each superseded
statement is named here rather than edited. Sources, all outside the
repository: `s4b-impl-A-brief.md` (R85–R88), `s4b-impl-A-report.md` (A,
the code and tests, on the Acer), `s4b-impl-B-report.md` (B, the tests,
the rebuilt chain and the first self-configured boot, on MINIS).

- **§4, made precise by R85, and now observed in a guest.** *"The one
  non-loopback link"* is the one entry of `/sys/class/net/` that has a
  `device` link; `lo` and virtual links are not counted and are left
  alone; zero or more than one device-backed link is an error. The AppVM
  kernel builds `CONFIG_IPV6_SIT` in (A § 0.1, the Acer's copy of the
  config), and **in the guest `sit0` exists under `ipv6.disable=1`**, flags
  `0x80`, beside `eth0` and `lo` (B § P8). The literal *"exactly one that
  is not loopback"* would have counted two and refused this boot.
- **§3, made precise by R86.** Every whitespace-separated token of
  `/proc/cmdline` is considered, including any after `--`; a token
  beginning `km.` must be `km.<key>=<value>` with `<key>` one of `ip`,
  `gw`, `dns`; a value is at most 15 characters and must be accepted by
  `inet_pton(AF_INET)`; `/proc/cmdline` unreadable is an error. Measured
  (glibc 2.44, the Acer; the same reading on MINIS): `inet_pton` refuses
  leading zeros in any octet, fewer than four parts, a leading or trailing
  dot, an octet above 255, hex, surrounding whitespace, signs, trailing
  garbage, a bare integer and the empty string (A § 2). An accepted value
  is therefore canonical.
- **§ *Context* and §7, corrected.** *"`cp` follows a symlink at its
  destination"* holds only when the link's target exists: GNU coreutils
  refuses to write through a dangling destination link (9.11 on the Acer,
  A § 5.1; 9.12 on MINIS, B § P1 1b; both measured). Through an absolute
  link, a build's `cp` would therefore overwrite the host's
  `/run/resolv.conf` **when that file exists**, and otherwise fail the
  build. The relative link is a defence; the builds do not write through
  it, but copy explicitly into the image's `run/` and remove the copy
  before the read-back (`d6d0006`).
- **§9, implemented by R87.** The network step runs after the pseudo-file
  systems and the console and before anything else in `main()`; its error
  exit is `do_shutdown(-1)`, the shutdown tail with no control socket to
  close (`04672b8`). `fatal()` is not used for these errors. **Not yet
  executed in a guest** (G1's refusal half).
- **Superseded statements, named and not edited:**
  - § *Context*'s line citations of `init/katmate-init.c` — `:122` (the
    `/proc` mount), `:269–276` (the `envp`), `:91–97` (`fatal()`) — moved
    with `04672b8` to `:147`, `:792–798` and `:116–122` (A § 5.3);
  - § *Context*'s *"katmate-init has no network code"* and § *Status*'s
    *"`init/katmate-init.c` has no network code, no image carries the
    resolver symlink"*: false of the tree since `04672b8` and `d6d0006`,
    and of MINIS's layers since B;
  - the closing line of this ADR's note of 2026-09-29, *"The guest ignored
    the parameters: its image predates this ADR"*: superseded by B's boot.
- **R89 — G1, positive half: PASS** (operator, 2026-09-29). Evidence: B §
  P6, the console line `[katmate-init] net: eth0 10.100.1.17/32 via
  10.100.1.1 dns 10.100.1.1`, from the unit `katmate-app-routed@app_web`
  on slot 01; and B § P8, `g1.txt`, written in the guest by uid 1000 in a
  `foot` window and read off the home LV read-only on the host after the
  guest was down, quoted in full there. It shows: `/proc/cmdline` with the
  four tokens; `eth0`, `lo`, `sit0`; `lo` flags `0x9` (UP); `eth0` flags
  `0x1003`; `fib_trie` with `10.100.1.17/32` and `lo`'s entries as the
  only host-local addresses; `/proc/net/route`'s one row, `eth0`, default,
  gateway `10.100.1.1`, flags `0x3`; `readlink /etc/resolv.conf` →
  `../run/resolv.conf`; `nameserver 10.100.1.1`; and an answer for
  `deb.debian.org`. **Not read** (the operator's shortened line in the
  guest): the mode and owner of `/run/resolv.conf` (§7's `root:root
  0644`), and `operstate`. **The *"Unknown kernel command line
  parameters"* zero has no positive control**, as in the note of
  2026-09-29, so § *Context*'s dotted-parameter claim is consistent with
  this boot and still not shown. The onlink flag does not appear in
  `/proc/net/route`; it was observed only in the namespace test below.
- **R90 — G3: PASS**, stated exactly (operator, 2026-09-29). The positive
  half on both frozen layers: after `make foundation` and after `make
  app-web`, `readlink` on the frozen layer's `/etc/resolv.conf` returned
  `../run/resolv.conf` and the layer's `/run` held no `resolv.conf` (B §
  P3, § P4). The refusal half was executed at **function level** —
  `resolv_link_check` against fixture trees, on the Acer (A § 2, the run
  before case 6's rewrite, in which every refusal case passed) and on
  MINIS (B § P1 1b, the committed script, 21 cases, 0 failed) — **not
  inside a real build**. The host control read absent → absent across both
  builds (B R3): it shows that no build created the host's
  `/run/resolv.conf`, and it cannot show an overwrite, since there was
  nothing to overwrite.
- **The apply group on a real kernel** (B § P1 2a/2b, MINIS, as root).
  Without a private namespace the harness refused (*"this is PID 1's
  network namespace"*) and the host's tables were unchanged. Under
  `unshare -n`, with `km0` a `dummy` link: `10.100.1.17/32` on `km0`,
  `default via 10.100.1.1 dev km0 onlink`, `lo` UP from a fresh `lo`
  DOWN, the resolver file `nameserver 10.100.1.1`, and a non-existent
  ifindex refused with the kernel's `No such device` through the ack path.
  The route verdict failed on iproute2 7.2.0's trailing space alone: a
  **harness defect** in `init/tests/run.sh` (it compares untrimmed `ip -4
  route show`), accepted as observed by the operator's ruling on B's P1,
  and fixed in its own commit with a re-run of `--apply`, not here.
- **The narrowing of this ADR's note of 2026-09-29.** That note's
  *"replaces *Carried*'s 'reads the exit status and the unit state'"* is
  narrowed (operator, 2026-09-29): the journal gives the unit's end state;
  a numeric exit status appears there only for a non-zero exit (*"Main
  process exited, code=exited, status=N"* and *"Failed with result"*), so
  *"Deactivated successfully"* with neither is the reading for a clean
  end. **Reasoned from systemd's behaviour; one instance observed** (B §
  P8, the clean stop after SHUTDOWN).

**Outside this ADR, recorded so it is not lost:** a file created in the
guest's user session is mode `0666` (`g1.txt`, B § P8). The cause is
inferred, not read: katmate-init's `umask(0)` inherited through
`vm-agent` to the applications.

**Not taken:** G1's refusal half (`km.ipx=`), G2 (both halves), G3's
refusal half inside a real build. The vehicle for an altered `-append` is
the operator's ruling.

**Acceptance note (2026-09-29) — what acceptance rests on, gate by gate,
and what it does not claim:** the status line above was changed from
`PROPOSED` to `Accepted` in place. That is this file's practice for that
one line and only that line, on the precedent of ADR-033's acceptance note
(2026-08-28) and ADR-034's (2026-09-01). The rest of § *Status* is left as
written. Its *"Acceptance waits on the gates below"* is discharged by this
note. Its *"`init/katmate-init.c` has no network code, no image carries the
resolver symlink, and no template passes a `km.*` parameter"* was already
superseded by the two notes above. The body stays append-only. Acceptance
is the operator's ruling **R96** (2026-09-29). The gate verdicts it rests
on are **R89**, **R90** and **R95**. Sources, all outside the repository:
`s4b-impl-B-report.md`; `s4b2-impl-A-brief.md` (R91–R93) and its report;
`s4b2-impl-B-report.md` (the image the gates ran on); and
`s4-gates-report.md` (the gate readings, and R94).

**The image the gates ran on.** It was built on MINIS on 2026-09-29 from
`a64c13d` (s4b2-impl-B): `vm_tpl_foundation`
(`BUILD_DATE=2026-09-29T13:07:13Z`) → `vm_app_web`
(`APP_BUILT=2026-09-29T13:09:27Z`) → a new delta. Both layers carry
`/sbin/init` equal to `out/katmate-init` (`c3ad714a…`), and an `objdump`
reading shows R91's `umask(0x12)` in it. G1's positive half and G3 (R89,
R90) were read on the build before it, from `647a380`. The network step
did not change between the two: `47c4305` touches `spawn_agent()` and a
comment in `main()` only. G3's positive half was read again on the new
layers: the relative link, and no `run/resolv.conf`.

**What acceptance rests on, gate by gate.** All gates were taken on MINIS
with `katmate-app-routed@app_web` on slot 01, link 201 added by hand, and
netVM unchanged (MainPID 49895).

- **G1, positive half — R89, PASS**, as the note above records it. The
  `net:` line, `[katmate-init] net: eth0 10.100.1.17/32 via 10.100.1.1 dns
  10.100.1.1`, recurred byte for byte on the new image, at s4b2-impl-B's
  boot and at ADR-037 G5's positive half.
- **G1, refusal half — R95, PASS.** `km.ip=` became `km.ipx=`, with the same
  value and nothing else changed: one line of `ExecStart=` differs by
  `diff`, taken from `systemctl cat`. The console showed `net: ERROR:
  unknown km.* key: 'km.ipx=10.100.1.17'`, `net: vm-agent not started;
  exiting the VM (ADR-038 §9)`, `shutting down` and `reboot(RB_AUTOBOOT)
  -> triple-fault -> QEMU exits`. No *"vm-agent launched"* line appeared.
  QEMU was gone within 5 s. **No frame from the guest:** netVM's `km01`
  `rx_packets` read 18 before and 18 after (R94).
- **G2, refusal half — R95, PASS.** The variant was `km.gw=10.100.1.1
  ipv6.disable=1` alone. The console showed `net: ERROR: partial km.* set
  (all three or none): km.ip MISSING, km.gw given, km.dns MISSING`, then
  the same three exit lines, with no `net: offline` line. QEMU was gone
  within 5 s. `km01` read 18 → 18. It was refused as a partial set, not
  taken as offline.
- **G2, positive half — R95, PASS.** The variant had no `km.*` token, and
  `ipv6.disable=1` was kept. The console showed `net: offline (no km.ip),
  lo up`, then `vm-agent launched`. The in-guest reading is `g2p.txt`,
  written by uid 1000 in `foot` and read off the home LV read-only after
  shutdown. `fib_trie` holds only `127.0.0.0/8`'s entries.
  `/proc/net/route` has its header and no row. `lo`'s flags are `0x9`.
  `readlink /etc/resolv.conf` gives `../run/resolv.conf`, and `cat` gives
  *No such file or directory*: the dangling link, which is §7's *"no
  resolver"*. **§2's *"A NIC present on the offline path is left down"* is
  observed:** `eth0`'s flags are `0x1002`, without `IFF_UP`. `km01` read
  18 → 18 across 8.5 minutes with the NIC present.
- **G3 — R90, PASS**, stated exactly in the note above. The positive half
  holds on both frozen layers, and was read again on the rebuilt ones. The
  refusal half was run at function level only, not inside a real build.
  The host control read absent → absent.
- **R94 — how *"no frame from the guest"* was read** (operator, 2026-09-29).
  G1's text names *"a capture on the slot's netVM end"*, and the netVM
  image carries no capture tool by design. The observable is therefore
  netVM's `km01` `rx_packets`, unchanged across the run. The only sender on
  slot 01's link is the guest's `appvm` socket, and the interface counter
  counts every frame, ARP included. Its positive control is ADR-037 G5's
  positive half on the same link, where the counter rose 18 → 21. G1's text
  is left as written; this is the reading method that narrows it.
- **The vehicle — R92** (operator, 2026-09-29). An altered `-append` is
  carried by a per-session drop-in,
  `/run/systemd/system/katmate-app-routed@app_web.service.d/90-gate.conf`.
  It resets `ExecStart=` and restates the installed unit's with only
  `-append` changed. `diff` shows the change, and the drop-in is removed
  after each run. It is never under `/etc` (R9). This answers §
  *Carried*'s *"The vehicle for G2 at 4b"*. G2's refusal variant kept
  `ipv6.disable=1` (R94).

**§ *Carried*'s first item is observed.** *"The unit is expected to end
inactive, not failed, when init refuses … expected, not observed"*: after
G1's and G2's refusal halves, the journal read *"Deactivated
successfully."*, with no *"Main process exited"* and no *"Failed with
result"* line. By the narrowing in the note above, that is a clean end.
There are two instances. Telling an init refusal from a clean shutdown on
the host is still open problem #21's.

**R91's umask, observed as a by-product.** In G2's positive half,
`umask` read `0022` in a `foot` shell as uid 1000, and a new file read
`-rw-r--r--`. `47c4305` sets `umask(022)` in `spawn_agent()`'s child
before `vm-agent` starts (R91; open problem #53, resolved). The note
above's paragraph *"Outside this ADR, recorded so it is not lost"* (a file
mode `0666`) describes the image before R91. It is superseded, and it is
not edited.

**What acceptance does not claim.**

- **The *"Unknown kernel command line parameters"* zero still has no
  positive control.** It read 0 in every boot of the gate session. Every
  `km.*` token is dotted, and no parameter was passed for which this kernel
  is shown to print the line. § *Context*'s dotted-parameter claim is
  consistent with every boot and is still not shown.
- In the guest, `/run/resolv.conf`'s mode and owner (§7's `root:root
  0644`) and `operstate` are not read (R89).
- G3's refusal half has not run inside a real build (R90).
- The uid the AppVM's QEMU runs as is not read.
- R78's refusal paths ([ADR-037](DECISIONS.md#adr-037)'s note of
  2026-09-29, step 4a) are unexercised.
- `ExecStopPost=`'s execution is inferred from `appvm`'s absence after
  each stop, and it is not recorded.

**Documentation this ADR requires on acceptance.** `docs/ARCHITECTURE.md`
§ *Networking* and the revision note on
[ADR-033](DECISIONS.md#adr-033) are written in the same pass as this note.
`init/katmate-init.c`'s header changed with the code (`04672b8`).
