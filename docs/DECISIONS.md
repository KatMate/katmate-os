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
