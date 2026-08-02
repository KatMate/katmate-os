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
      framing, posix_spawn, atomic FILEPUT, traversal-safe paths (ADR-018)
- [x] Agent split into a Cargo workspace — `katmate-protocol` + `vm-agent` +
      `netvm-agent` + `ping-client`; absent-not-disabled opcode model (ADR-021)
- [x] File transfer over VSOCK
- [x] Waypipe version lock — guest 0.11.0 from source, clipboard functional
- [x] Host kernel → `linux-hardened` (incl. `aio=threads` adaptation)
- [x] Installer rewrite: systemd-boot, proportional LVM sizing, thin pool
- [x] Template model designed (immutable base + overlays, ADR-007)
- [x] NetVM operational — RTL8125 vfio passthrough, WireGuard/ProtonVPN, inner
      segment routing (live on MINIS/UM870; ADR-009 realized ahead of v0.3)
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
- [ ] Suspend/resume fix under `linux-hardened`
- [ ] Remove secrets from installer (prompts / `wg genkey`); rotate burned WG key
- [ ] Remove dev-only sshd (host + netVM) — SECURITY-MODEL #4
- [ ] Power management

## v0.3 — Network isolation & first release target

> **First release target** = installer + preconfigured NetVM + default
> ready-to-run AppVMs ≈ end of v0.3.

- [ ] Launch daemon — owns the topology graph: allocates CIDs and `/32`s,
      creates/destroys `Link`s, calls NETCFG along the path, refuses to tear
      down a `provides_network` VM with live dependents (ADR-022; ADR pending)
- [ ] Default ready-to-run AppVM set (vault / personal / untrusted / disposable)
      from two manifests (ADR-014)
- [ ] Offline AppVM (`netvm: None`) as a shipped domain — air-gap by absence of
      a link (ADR-022)
- [ ] Installer provisions foundation + app-layers + NetVM + default AppVMs
- [ ] Disposable VMs
- [ ] Networking automation (NetVM lifecycle managed by installer/katmate)
- [ ] VPN migration host → NetVM complete in installer (live on MINIS but not
      yet installer-integrated)
- [ ] Domain indicator — waybar module (authoritative) + 2px border, drawn
      host-side from waypipe CID identity, encoding the netVM attachment
      (carriers and identity path settled: ADR-026)
- [ ] **VMM containment gate (C-gate)** — ADR-027. C4 (tightened seccomp) and
      C5b (no host filesystem export into netVM) passed 2026-07-28. Remaining:
      C1–C3 (non-root netVM VMM, vfio via group + udev, `memlock` from a unit),
      C5a (Landlock or chroot wrapper), C6 (per-VM netns). C1–C3 land with the
      launch daemon; C5a and C6 are separable. Gates all axis-2 / vhost-user
      work.

## Build order (first release, critical path)

Each step gates the next:

**Precondition, not a step: C-gate C1–C3** (ADR-027) — the launch daemon's
privilege split (prepare as root, drop to a per-VM uid, `exec qemu`). It is a
*property of* the launch daemon rather than a stage before or after it: the
daemon cannot be designed as "a thing that runs `.con` scripts" and acquire
this later.

1. **Foundation pipeline** (ADR-011) — reproducible foundation; manifest format
   + `app-<type>` generation. Gate: build `vault` and `web` layers, run an
   instance overlay off each. Realizes ADR-014 + ADR-010.
2. **`katmate-update` MVP** — foundation rebuild + app-layer rebase + overlay
   recycling on a waypipe version bump (ADR-019). Never touches sysVMs.
3. **NetVM installer integration** — netVM lifecycle automated from the
   installer; NIC passthrough; VPN provisioned at install time. Unblocked: the
   declarative build and the uplink are proven.
4. **Default AppVMs** — instantiate the domains from two manifests + properties;
   per-instance home on raw thin LV; disposable lifecycle.
5. **Installer integration** — provision the whole set so a fresh install runs,
   including the Sway desktop profile (needs `kms` in mkinitcpio HOOKS).

**Parallel (off critical path, before releasing step 5):** remove installer
secrets + rotate burned WG key + drop `Hidden=true` (SECURITY-MODEL #1–2);
remove dev sshd (#4); remove the `usermod -p` dev-root line from `netvm.sh`
(#12) — see the operational note in `state.md`.
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
