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
| `cid` | int \| `"auto"` | fixed 4–8 for static domains, or `"auto"` for pool allocation | yes | — |
| `reset_on_shutdown` | bool | — | no | `false` |

`reset_on_shutdown` exists only for the `untrusted` archetype's optional
app-layer reset (ADR-014); `vault` / `personal` / `disposable` omit it and
take the default.

`cid` carries two opposite meanings depending on the domain. For **static**
domains (vault, personal, untrusted) it is an *input*: a fixed value in
4–8, authored in the file, part of the domain's identity. For **disposable**
domains it is an *output*: the literal string `"auto"` declares "not authored
here — the deploy step allocates from the dynamic pool (≥100)" per ADR-017.
A numeric `cid` ≥100 is also accepted (manual/debug pinning), but `"auto"`
is the norm for disposables. CIDs 0–2 are reserved (hypervisor / local /
host-loopback); 3 is the NetVM (ADR-009).

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
---

## ADR-016 — Two desktop profiles: shared visual layer, Sway default + Hyprland optional

**Status:** Accepted (2026) — direction only; see Consequences for build state

**Context:** The desktop layer (greetd / compositor / bar / launcher) sits
outside the TCB ([SECURITY-MODEL.md](../SECURITY-MODEL.md)) and off the
isolation critical path ([ROADMAP.md](../ROADMAP.md) step 5), yet it shapes the
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
  until v1.0 ([ROADMAP.md](../ROADMAP.md) step 5) — unchanged; this ADR fixes
  only which layer.
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

- **Space:** static domains use fixed CIDs 4–8 (authored in `properties.toml`);
  the dynamic pool is every CID ≥ 100. CIDs 0–2 are reserved, 3 is the NetVM
  ([ADR-009](DECISIONS.md#adr-009)). The 100 floor only separates the dynamic
  pool from the static band; there is no upper bound from CID space.
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

**Status:** Accepted (2026-07)

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
interactive installer run. And [ROADMAP.md](../ROADMAP.md) step 3 (installer
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
artifact) and by [ROADMAP.md](../ROADMAP.md) step 3; the shared-protocol,
whitelisted appVM agent it splits from is the one specified in
[ADR-018](DECISIONS.md#adr-018).

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
