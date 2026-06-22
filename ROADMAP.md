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
      framing, posix_spawn, atomic FILEPUT, traversal-safe paths (ADR-018);
      live-host validation pending
- [x] File transfer over VSOCK
- [x] Waypipe version lock — guest 0.11.0 from source, clipboard functional
- [x] Host kernel → `linux-hardened` (incl. `aio=threads` adaptation)
- [x] Installer rewrite: systemd-boot, proportional LVM sizing, thin pool
- [x] Template model designed (immutable base + overlays, ADR-007)
- [x] NetVM operational — USB-NIC passthrough, WireGuard/ProtonVPN, inner
      segment routing (live on MINIS/UM870; ADR-009 realized ahead of v0.3)
- [x] personalVM operational — microvm, hugepages, qcow2 overlay + raw home LV
- [ ] AppVM domain model + three-layer composition (ADR-014, ADR-010)
- [ ] `katmate-update` implementation (MVP)
- [ ] Base image build pipeline — foundation + app-`<type>` images, shell+Make (ADR-011)
- [ ] Suspend/resume fix under `linux-hardened`
- [ ] Remove secrets from installer (prompts / `wg genkey`); rotate burned WG key
- [ ] Power management

## v0.3 — Network isolation & first release target

> **First release target** = installer + preconfigured NetVM + default
> ready-to-run AppVMs ≈ end of v0.3.

- [ ] Default ready-to-run AppVM set (vault / personal / untrusted / disposable)
      from two manifests (ADR-014)
- [ ] Installer provisions foundation + app-layers + NetVM + default AppVMs
- [ ] Disposable VMs
- [ ] Networking automation (NetVM lifecycle managed by installer/katmate)
- [ ] VPN migration host → NetVM complete in installer (live on MINIS but not
      yet installer-integrated)

## Build order (first release, critical path)

Each step gates the next:

1. **Foundation pipeline** (ADR-011) — reproducible `foundation.qcow2`; manifest
   format + `app-<type>` generation. Gate: build `vault` and `web` layers, run
   an instance overlay off each. Realizes ADR-014 + ADR-010.
2. **`katmate-update` MVP** — host-waypipe vs foundation version detection
   (pacman hook), foundation rebuild + app-layer rebase + overlay recycling.
3. **NetVM installer integration** — NetVM lifecycle automated from installer;
   USB-NIC or PCIe NIC passthrough; VPN provisioned at install time.
4. **Default AppVMs** — instantiate the four domains from two manifests +
   properties; per-instance home on raw thin LV; disposable lifecycle.
5. **Installer integration** — provision the whole set so a fresh install runs.
   Desktop layer (greetd/Hyprland/Plymouth, needs `kms` in mkinitcpio HOOKS)
   stays a documented manual step until v1.0 — not on the isolation critical path.

**Parallel (off critical path, before releasing step 5):** remove installer
secrets + rotate burned WG key + drop `Hidden=true` (SECURITY-MODEL #1–2).
**Opportunistic:** suspend/resume under linux-hardened; hibernation decision
(resume hook or shrink swap); `qemu-full` → `qemu-base`.

**Deferred to v0.4+:** policy engine, management GUI, base image signing
(ADR-013), central image distribution (ADR-012).

## v0.4 — Management layer

- [ ] Policy engine
- [ ] GUI management tools
- [ ] Base image signing & verification (ADR-013)

## v1.0 — Stable secure desktop

- [ ] Reproducible installation end-to-end
- [ ] Installer integrates the desktop layer (greetd / Hyprland / Plymouth)
- [ ] Documented, reviewed security model
- [ ] Daily-driver usability for non-expert users
