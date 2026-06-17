# Security Model

## Goal

Compromise containment: a compromised workload must not be able to compromise
other workloads or the host. The host is the trusted computing base; everything
else is assumed breachable.

## Threat model

### In scope

- Malicious websites and browser exploits
- Document exploits (PDF, office formats)
- Application compromise inside a VM
- Data theft between workloads
- Network tracking
- VPN failures / leaks

### Out of scope

- Physical access attacks (evil maid, DMA)
- Hardware implants
- Malicious firmware
- Side-channel attacks
- Nation-state hardware attacks

### Scope consequences

- Full-disk encryption (LUKS2) protects confidentiality of data at rest, e.g.
  on device theft. It does **not** defend against an attacker with repeated or
  runtime physical access — that is explicitly out of scope.
- Secure Boot / measured boot is intentionally absent at this stage. This is
  *consistent* with the exclusion of physical access attacks, not an oversight.
  Revisit at v1.0 if the scope changes.

## Trust boundaries

- The host controls VM lifecycle; VMs never control the host.
- Communication crosses only explicitly exposed AF_VSOCK channels.
- Each VM is its own trust domain; inter-VM communication does not exist by
  design (no guest-to-guest channel).

## Principles

1. Default deny
2. Explicit whitelisting
3. Minimal services
4. Least privilege
5. Minimal dependencies
6. Small, auditable management layer
7. Separation of duties (system in base image, data in overlay)

## Controls by component

### Host firewall (nftables)

Input policy `drop`; accepted: loopback, established/related, ICMP/ICMPv6.
Forward policy `drop`. SSH disabled by default (rule present but commented
in the installer-provisioned ruleset).
VSOCK does not traverse netfilter — host↔guest traffic never touches the
network stack.

### Boot chain

systemd-boot with `timeout 0` and `editor no` — no interactive kernel
command-line tampering at the boot menu. Kernel: `linux-hardened`
(out-of-the-box hardening for the TCB; operational consequences in
[ADR-004](DECISIONS.md#adr-004)).

### VM agent

- VSOCK connections accepted from the host only
- `RUN` restricted to an application whitelist (`firefox-esr`, `foot`, `nautilus`)
- `FILEGET`/`FILEPUT` restricted by path whitelist and transfer size limits
- No arbitrary command execution path

### GUI forwarding

Waypipe over VSOCK — no network listener, no X11 surface. Host side is a
socket-activated systemd *user* service (unprivileged).

### Guests

Minimal Debian userspace, minimal services, direct kernel boot, custom
MicroVM kernel with a reduced config surface. Nothing persists outside the
per-AppVM overlay.

## Trusted computing base

Host kernel (`linux-hardened`) + QEMU/KVM + systemd + host side of vm-agent +
waypipe client + installer-provisioned configuration. Kept deliberately small;
`qemu-full` → `qemu-base` reduction is under evaluation.

## Known gaps (tracked)

| # | Gap | Status / remediation |
|---|---|---|
| 1 | **Secrets committed in installer scripts** — WireGuard private key, WiFi SSID+PSK, default user credentials | Critical hygiene gap. The committed WG key is considered burned and must be rotated. Replace with install-time prompts / `wg genkey` generation. v0.2 blocker. |
| 2 | Hidden SSID + AutoConnect forces clients into active probing — the machine broadcasts the network name everywhere | Switch to a visible SSID; drop `Hidden=true`. |
| 3 | ~~VPN terminates on the host, contradicting the NetVM target architecture~~ | **Resolved (live on MINIS):** WireGuard/ProtonVPN now terminates in NetVM per [ADR-009](DECISIONS.md#adr-009). Host carries no VPN. |
| 4 | **SSH open on development host** — `tcp dport 22 accept` active on MINIS (dev convenience, not installer default) | Close or gate behind a stricter rule before power-user release. Not present in the installer-provisioned ruleset. |
| 5 | No base image signing / integrity verification | [ADR-013](DECISIONS.md#adr-013) (Proposed). |
| 6 | No Secure Boot chain | Consistent with threat model (see above); revisit at v1.0. |
