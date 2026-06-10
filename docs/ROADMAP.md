# Roadmap

## v0.1 — Foundation ✅

- [x] Arch installer (LUKS2, EFI)
- [x] Custom MicroVM kernel
- [x] Debian MicroVM direct kernel boot
- [x] AF_VSOCK host↔guest communication
- [x] Waypipe proof of concept

## v0.2 — Core plumbing 🔧 (current)

- [x] vm-agent in C (PING, RUN, FILEGET, FILEPUT, SHUTDOWN)
- [x] File transfer over VSOCK
- [x] Waypipe version lock — guest 0.11.0 from source, clipboard functional
- [x] Host kernel → `linux-hardened` (incl. `aio=threads` adaptation)
- [x] Installer rewrite: systemd-boot, proportional LVM sizing, thin pool
- [x] Template model designed (immutable base + overlays, ADR-007)
- [ ] `katmate-update` implementation (MVP)
- [ ] Base image build pipeline (ADR-011)
- [ ] Suspend/resume fix under `linux-hardened`
- [ ] Remove secrets from installer (prompts / `wg genkey`); rotate burned WG key
- [ ] Power management

## v0.3 — Network isolation

- [ ] NetVM (DHCP, DNS, VPN, firewall, routing)
- [ ] VPN migration host → NetVM (ADR-009)
- [ ] Disposable VMs
- [ ] Networking automation

## v0.4 — Management layer

- [ ] Policy engine
- [ ] GUI management tools
- [ ] Base image signing & verification (ADR-013)

## v1.0 — Stable secure desktop

- [ ] Reproducible installation end-to-end
- [ ] Installer integrates the desktop layer (greetd / Hyprland / Plymouth)
- [ ] Documented, reviewed security model
- [ ] Daily-driver usability for non-expert users
