# Roadmap

## v0.1 — Foundation ✅

- [x] Arch installer (LUKS2, EFI)
- [x] Custom MicroVM kernel
- [x] Debian MicroVM direct kernel boot
- [x] AF_VSOCK host↔guest communication
- [x] Waypipe proof of concept

## v0.2 — Core plumbing 🔧 (current)

- [x] vm-agent in C (PING, RUN, FILEGET, FILEPUT, SHUTDOWN)
- [x] vm-agent rewritten in Rust — versioned binary protocol, bounds-checked
      framing, posix_spawn, atomic FILEPUT, traversal-safe paths (ADR-039;
      FILEPUT and its path guard retired 2026-10-06)
- [x] Agent split into a Cargo workspace — `katmate-protocol` + `vm-agent` +
      `netvm-agent` + `ping-client`; absent-not-disabled opcode model (ADR-021)
- [x] File transfer over VSOCK — **retired 2026-10-06**, before the first
      release: nothing on the host used FILEGET/FILEPUT. `0x03`/`0x04` stay
      reserved; the frame's payload bound fell from 100 MiB to 64 KiB
      (`MAX_PAYLOAD`)
- [x] Waypipe version lock — guest 0.11.0 from source, clipboard functional
- [x] Host kernel → `linux-hardened` (incl. `aio=threads` adaptation)
- [x] Installer rewrite: systemd-boot, proportional LVM sizing, thin pool
- [x] Template model designed (immutable base + overlays, ADR-007)
- [x] NetVM operational — RTL8125 vfio passthrough, WireGuard/ProtonVPN, inner
      segment routing (live on MINIS/UM870; ADR-009 realized ahead of v0.3)
      **[Note 2026-09-27: the ADR-037 image of 2026-09-27 carries no VPN.**
      Vanilla egress is direct through `uplink0` (R2, R20). A VPN is a
      post-install option through the config disk (R8), not implemented.**]**
- [x] NetVM declarative build (`build/netvm.sh`) — sysVM class, debootstrap,
      proven end-to-end; the netinst pet is retired (ADR-021)
- [x] Network object model — topology as a graph, NIC as an assignable object
      (ADR-022); NETCFG payload is link-scoped (ADR-023)
- [x] personalVM operational — microvm, hugepages, qcow2 overlay + raw home LV.
      *Pre-foundation artefact; retired 2026-08-02 (launcher, overlay and
      `vm_personal_home` removed). The `personal` **domain** returns in v0.3 as
      one of the default AppVMs, built from foundation + `web` manifest.*
- [x] `netvm-agent` — listener (gate: `ping-client ping 3 → OK`), then NETCFG
      handler (ADR-025, live-gated 2026-07-23; PING/NETCFG/SHUTDOWN complete)
- [x] CID renumbering to the ADR-022 map (fixed AppVMs 4–8 → 20+)
- [ ] AppVM domain model + three-layer composition (ADR-014, ADR-010)
- [x] `katmate-update` implementation (MVP)
- [ ] Base image build pipeline — foundation + app-`<type>` images, shell+Make (ADR-011)
- [ ] Kernel provenance sidecar — `tools/capture-kernel-provenance` writes
      `<vmlinuz>.provenance` in the kernel tree at build time; the sidecar
      travels with the kernel through both build hops and the foundation build
      records `KERNEL_PROVENANCE` in its metadata (ADR-034). The tool, the
      preflight check and both hops are committed. The metadata field and the
      step-11 install are written but UNVERIFIED — only a real `make
      foundation` exercises them.
      **[Note 2026-09-27: step 10's field and step 11's install executed** in
      the foundation rebuild of 2026-09-26 (`KERNEL_PROVENANCE=recorded`;
      `state.md` open problem #22). The item stays open, because nothing
      checks the record yet.**]**
- [ ] Kernel provenance: the release orchestrator's presence check (ADR-034
      § A.3) — **blocked by open problem #25**, not deferred. `KERNEL_SRC_DIR`
      derives from `$HOME` and resolves under `/root` when the script runs as
      root, so the check could not fire where it matters. Neither this entry
      nor #25 closes while the other stands.
- [ ] Suspend/resume fix under `linux-hardened`
- [ ] Remove secrets from installer (prompts / `wg genkey`); ~~rotate burned WG key~~
      **rotated, with the Wi-Fi passphrase (R162); removing the values from
      `installer/` stays open**
- [ ] Remove dev-only sshd (host + netVM) — SECURITY-MODEL #4
- [ ] Power management

## v0.3 — Network isolation & first release target

> **First release target** = installer + preconfigured NetVM + default
> ready-to-run AppVMs ≈ end of v0.3.

- [ ] VM description as data — `properties.toml` (superseding ADR-015's
      schema), `<image>.meta`, and the per-profile unit templates; both `.con`
      scripts deleted (ADR-030)
- [ ] Launch daemon — owns the topology graph: allocates CIDs and `/32`s,
      creates/destroys `Link`s, calls NETCFG along the path, refuses to tear
      down a `provides_network` VM with live dependents (ADR-022, ADR-029,
      ADR-030)
- [ ] Default ready-to-run AppVM set (vault / personal / untrusted / disposable)
      from two manifests (ADR-014)
- [ ] Offline AppVM (`netvm: None`) as a shipped domain — air-gap by absence of
      a link (ADR-022)
- [ ] Installer provisions foundation + app-layers + NetVM + default AppVMs
- [ ] Disposable VMs
- [ ] Networking automation (NetVM lifecycle managed by installer/katmate)
- [ ] VPN migration host → NetVM complete in installer (live on MINIS but not
      yet installer-integrated)
      **[Note 2026-09-27: not live.** The 2026-09-26 net-up reading found no
      WireGuard in netVM (`adr037-readpass-report.md` D11, outside the
      repository), and the host's `proton` link is dev scaffolding (the
      operator's gap-3 ruling; SECURITY-MODEL gap 3).**]**
- [ ] Domain indicator — waybar module (authoritative) + 2px border, drawn
      host-side from waypipe CID identity, encoding the netVM attachment
      (carriers and identity path settled: ADR-026)
- [ ] Per-VM waypipe listeners with a Wayland security context
      (`--secctx`): per-domain clipboard isolation, and window labels
      assigned by the host rather than the guest. The alpha shares one
      clipboard across all VMs and the host, and its `[<instance>]` title
      label is guest-set (README, *Known limitations (alpha)*; operator
      ruling 2026-10-05)
- [ ] **VMM containment gate (C-gate)** — ADR-027. C4 (tightened seccomp) and
      C5b (no host filesystem export into netVM) passed 2026-07-28. Remaining:
      C1–C3 (non-root netVM VMM, vfio via group + udev, `memlock` from a unit),
      C5a (Landlock or chroot wrapper), C6 (per-VM netns). **Re-scoped by
      ADR-029:** C1, C3 and C5a are unit directives (`User=`,
      `LimitMEMLOCK=infinity`, a Landlock wrapper in `ExecStart=`), not daemon
      code; C6's namespace preparation *is* daemon code (`ip netns add` is not
      nestable) but preparation only — the unit takes the named namespace with
      `NetworkNamespacePath=`. C4 is additionally re-scoped by ADR-030: the
      `-sandbox` line lives in the unit template, is part of the signed ISO,
      and is not expressible as user data. Gates all axis-2 / vhost-user work.
- [x] **M2 — saturation of netVM's single event loop** (ADR-033, Accepted
      2026-08-28). All AppVM traffic converges on one QEMU main loop and `dgram`
      has no `vhost` equivalent, so that loop is in the data path for every
      frame. Measurable **without a single AppVM** — a host-side generator
      writing to `N` sockets, watched for the knee. **Taken 2026-08-28**
      (`~/link-m3-report.md`), against a standalone QEMU of netVM's shape rather
      than netVM itself, netVM carrying no `dgram` device to measure. **There is
      no knee:** the event loop is saturated at **one** active link — 99.6 % of
      one core — and stays at 98.7–99.6 % across `N` = 1 … 30 while aggregate
      throughput rises, so the ceiling is shared continuously rather than reached
      at some count of links. `N` is therefore not bounded by saturation; it is
      **16**, bounded by netVM's PCI slot count. The precondition this entry
      carried — *"ADR-033 cannot be accepted until it is taken"* — is discharged,
      and the ADR was accepted the same day.

## Build order (first release, critical path)

Each step gates the next:

**Precondition, not a step: C-gate C1–C3** (ADR-027) — the privilege split
(prepare as root, drop to a per-VM uid, run QEMU). **After ADR-029 this is unit
configuration** — `ExecStartPre=+`, `User=`, `LimitMEMLOCK=`, `ExecStopPost=+` —
not daemon code. It remains a precondition because the *supervision model* is
what cannot be acquired later: a daemon written as "a thing that runs `.con`
scripts" is a daemon that `fork`s QEMU, and every identity in the system then
depends on that daemon staying alive.

1. **Foundation pipeline** (ADR-011) — reproducible foundation; manifest format
   + `app-<type>` generation. Gate: build `vault` and `web` layers, run an
   instance overlay off each. Realizes ADR-014 + ADR-010.
2. **`katmate-update` MVP** — foundation rebuild + app-layer rebase + overlay
   recycling on a waypipe version bump (ADR-019). Never touches sysVMs.
3. **VM description as data → launch daemon** (ADR-030, ADR-029). This step was
   invisible in earlier revisions of this list because launching already exists
   in a degenerate form: two hand-written `.con` scripts, which *are* the
   schema expressed as code. The step is their removal.
   - **3a — description + unit templates.** `properties.toml` per ADR-030,
     `<image>.meta` on the `foundation.meta` pattern, and the
     `katmate-{app-routed,app-offline,sys-driver}@.service` templates. netVM
     and app_web start via `systemctl`, no daemon. **Gate: both `.con` files
     deleted from the repository and nothing was lost** — which is also the
     empirical gate on ADR-030's schema. ADR-030 gate E1 passed 2026-08-06
     (candidate A: generator as `ExecStartPre=+` in the VM unit).
     **[Note 2026-09-28: step 3a shipped `sys-driver` only.** Under ADR-037
     R61 the other two follow in this order: `app-routed` lands at
     networking arc step 4a, and `app-offline` ships with the vault
     instance. The `.con` deletion is not in networking arc step 4. See
     ADR-030's note of 2026-09-28. The text above is left as written.**]**
   - **3b — the launch daemon.** Graph ownership, CID allocation and reconcile
     (ADR-017), NETCFG ordering and re-issue (ADR-025), CID→name (ADR-026),
     dependent-VM interlock (ADR-022). Orders units; parents nothing (ADR-029).
4. **NetVM installer integration** — netVM lifecycle automated from the
   installer; NIC passthrough; VPN provisioned at install time. Unblocked: the
   declarative build and the uplink are proven.
   **[Note 2026-09-27: not "at install time".** Under ADR-037 R2 the VPN is a
   post-install option the user enables by supplying a WireGuard config. VPN
   mode is **networking arc step 5**, under its own ADR (R30, in ADR-037's
   note on the step-3 rulings; `state.md` § *Next steps*). That is the
   networking arc's numbering, not this build order's step 5. The text above
   is left as written.**]**
5. **Default AppVMs** — instantiate the domains from two manifests + properties;
   per-instance home on raw thin LV (ADR-030 §7: the home LV is per instance,
   not per app layer — today's name is per layer and would corrupt on a second
   instance); disposable lifecycle.
6. **Installer integration** — provision the whole set so a fresh install runs,
   including the Sway desktop profile (needs `kms` in mkinitcpio HOOKS).
   **[Note 2026-10-05 (`49a172d`): implemented, ungated.** The installer
   provisions the whole alpha from a signed release (GitHub release assets
   made by `tools/make-release.sh` and signed on the Acer; ADR-020 holds, so
   it builds nothing): netVM and the four AppVMs as prebuilt images, T1 from
   `installer/t1/`, home LVs and deltas, the KatMate units and
   `/usr/lib/katmate/`, the Sway desktop at system paths, greetd, and a
   Plymouth splash with `kms` and `plymouth` before `encrypt` in HOOKS. The
   host keeps no network. It has not run: the gate is a Cubi install from
   the first release, which needs that release built on MINIS first. The
   text above is left as written.**]**

**Alpha integration** (operator ruling, 2026-09-21). A pre-loaded desktop —
web, office/work, vault and personal AppVMs plus netVM — launched from a
menu, built by feeding hand-written static parameters into the existing
architecture: no static branch, no ISO, no change of direction. The
hand-written configuration doubles as the launch daemon's output
specification. It is a reproducible integration gate: it tests composition,
complementing the per-mechanism gates.
- **Frozen:** slot, MAC, CID and socket path; not RAM or vCPU.
- **Order:** the existing netVM's slots 1–4 (no second netVM; the NIC is PCI
  passthrough), then one AppVM at a time, vault last as the negative test;
  MINIS first, so failures are attributable, then the MSI Cubi as the
  reproducibility gate.
- **`docs/PARAMETERS.md`** (parameter · alpha source · target source · ADR ·
  gate) is filled during integration, not written up front. The first
  integration session creates it with its first row.
- **Stopping rule:** engineering ends when the table is complete and four
  AppVMs launch from the menu.
  **[Status 2026-10-03, `ai6`: the stopping rule is met on MINIS.** All four
  AppVMs (`app_web`, `app_personal`, `app_work`, `app_vault`) launched from
  the waybar menu, cold, through `katmate-launch`, and each opened its window
  (the operator, 4–6 s from click to window). `docs/PARAMETERS.md` has no
  empty cell (12 rows). **The engineering of the alpha is done.** Not done:
  the MSI Cubi as the reproducibility gate (*Order* above), and the launch
  daemon that replaces `katmate-launch` (step 3b). See `state.md`.**]**
- **Framing:** it demonstrates a wider isolation framework, and shows which
  parameters are still hand-set, why, and where in the path they sit.

**Parallel (off critical path, before releasing step 6):** remove installer
secrets (still open) + ~~rotate burned WG key~~ **done (R162)** + drop `Hidden=true` (SECURITY-MODEL #1–2);
remove dev sshd (#4); ~~remove the `usermod -p` dev-root line from `netvm.sh`
(#12)~~ **done in `23e4268` (2026-09-03)** — see the operational note in `state.md`.
**Opportunistic:** suspend/resume under linux-hardened; hibernation decision
(resume hook or shrink swap); `qemu-full` → `qemu-base`.

**Deferred to v0.4+:** policy engine, management GUI, base image signing
(ADR-013), central image distribution (ADR-012).

## v0.4 — Management layer

- [ ] Policy engine
- [ ] GUI management tools
- [ ] Base image signing & verification (ADR-013)

## Boot chain hardening (backlog — from the 2026-07-23 host boot pipeline work)

- [ ] TPM2 auto-unlock for LUKS (`systemd-cryptenroll`, PCR sealing)
- [ ] Secure Boot + signed UKI
- [ ] Measured Boot
- [ ] Remove the leftover GRUB EFI entry
- [ ] "Zero console" boot (no text frame between firmware and greeter)

## Windows application windows via RDP RemoteApp (experimental backlog — not committed, no ADR yet)

Windows apps as ordinary per-window Wayland surfaces next to the other
domains. KatMate ships the **client side only**; the RDP server is the
guest's business (the user's own Windows licence). The Windows guest is an
untrusted domain like any other.

**Compatibility target: the latest Microsoft RDP server** (current Windows
Server / Windows 11 release). The client follows Microsoft's RDP protocol as
it evolves — GFX pipeline, codecs, CredSSP/NLA, RAIL extensions — and is
re-validated against each new Windows release; older servers are not a goal.

- [ ] **RDP gateway VM** — a microVM image running `xfreerdp /app:` (RAIL,
      MS-RDPERP) in its **own rootless XWayland**, so the X11 domain never
      reaches the host and the RDP client, which parses data from an
      untrusted server, stays outside the host TCB. RAIL windows leave the
      gateway as Wayland surfaces over the existing waypipe path (guest-set
      title label until per-VM `--secctx` lands, v0.3)
- [ ] **Network shape** — Windows guest ↔ gateway on an isolated virtual link
      (ADR-022 object model): no route to the host, no uplink except through
      the chosen netVM. TCP/3389 only; no vsock relay inside Windows (extra
      maintenance, no gain)
- [ ] **Channel policy** — drive, USB, printer and smartcard redirection off;
      clipboard off by default, per-domain opt-in (RDP channels are attack
      surface in both directions)
- [ ] **Protocol tracking** — client built against current FreeRDP; on each
      new Windows release re-check GFX/AVC444, NLA/CredSSP and RAIL
      behaviour, and record the validated server version
- [ ] **Guest prerequisites documented** — Pro or higher (Home has no RDP
      server); `fDisabledAllowList=1` under `TSAppAllowList` on client SKUs
      (RemoteApp is officially Server/AVD only); one interactive session per
      client SKU (an RDP logon displaces the console — harmless for a
      headless guest)
- [ ] **Domain indicator** — Windows windows carry the same host-drawn domain
      border/label as other AppVMs (ADR-026)
- [ ] **Watch, not blocker: Wayland-native RAIL** — whether FreeRDP's
      Wayland/SDL3 clients reach usable RAIL support (check `client/Wayland`,
      `client/SDL` and release notes before committing); if so, XWayland
      drops out of the gateway

Prior art: WinApps (Windows 10/11 in KVM or Docker + FreeRDP `/app:`).
Depends on: AppVM domain model (ADR-014), network object model (ADR-022),
per-VM waypipe listeners.

Test records: [docs/RAIL-TESTS.md](docs/RAIL-TESTS.md).

## Product requirements (not code milestones)

- [ ] **Hardware Compatibility List (HCL)** + **installer IOMMU preflight
      check.** A driver domain is only safe where the NIC sits in a cleanly
      isolable IOMMU group (ADR-022). This is a shipping requirement for a
      product a user installs on unknown hardware, not an implementation detail.
      Qubes ships an HCL for exactly this reason.
- [ ] **Second DE profile (Hyprland/CYBRland)** — only once its domain-indicator
      implementation is separately verified. The DE profile contract is
      documented; Sway is the reference implementation (ADR-016).
- [ ] **Paranoid network profile** — driver domain / proxy netVM split, removing
      the v1 co-location of the VPN key with the NIC driver
      (ADR-022, SECURITY-MODEL #7).

## v1.0 — Stable secure desktop

- [ ] Reproducible installation end-to-end
- [ ] Installer integrates the desktop layer (greetd / Sway / Plymouth)
- [ ] Documented, reviewed security model
- [ ] Daily-driver usability for non-expert users

## Direction — managed deployment profile (not committed, no ADR yet)

The isolation boundary is a parameter, not a constant: every I/O device is
placed either behind the IOMMU (in a sysVM) or with the host, per profile.

- **standalone** (default, current target) — the host owns no NIC and no
  external I/O; TCB = the box.
- **managed** — the host keeps one physical NIC on a physically separate
  management LAN; all other I/O stays behind the IOMMU. The organisation
  declares TCB = host + management NIC + management LAN + its management
  actor. KatMate supplies the boundary and the interfaces; the actor is the
  organisation's choice — administrators, a model running on the management
  LAN, or an orchestrator station driving an external model.

Requirements of the managed profile:

- [ ] Actor placement — a station that bridges the management LAN and an
      external network voids the premise; inference runs on the management
      LAN, or the orchestrator's only external link is the model endpoint
      (organisation)
- [ ] Management LAN isolation — hosts reach the management station only,
      never each other (organisation)
- [ ] Input provenance — guest-origin text (serial console, guest logs) kept
      apart from host-origin records, so a model-based actor never reads
      guest-controlled content as host state (framework)
- [ ] Audit trail — every actuation recorded off-box, append-only, not
      writable by the actor (framework hook, organisation sink)

Prerequisites: VM description as data (ADR-030); v0.4 management layer
(ADR-012, ADR-013). The TCB change requires an ADR and a SECURITY-MODEL
entry before any implementation.
