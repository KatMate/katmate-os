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
- **Boundaries move only from the more-trusted side.** Network configuration is
  mutated by netVM's *own* agent executing a *host* command
  ([ADR-021](DECISIONS.md#adr-021)); a guest can never move its own boundary.

## Principles

1. Default deny
2. Explicit whitelisting
3. Minimal services
4. Least privilege
5. Minimal dependencies
6. Small, auditable management layer
7. Separation of duties (system in base image, data in overlay)
8. **Absent, not disabled** — a capability that must not exist in a VM class is
   *not compiled into* the binary running there, rather than gated at runtime
   ([ADR-021](DECISIONS.md#adr-021))
9. **Isolation by topology, not by rule** — network separation is expressed by
   which links exist, not by firewall rules discriminating between AppVMs
   ([ADR-022](DECISIONS.md#adr-022))

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

sysVMs boot **direct-kernel** with no in-guest bootloader: the boot chain of the
network-facing VM lives host-side, outside the guest image — there is no
in-guest GRUB to rewrite for persistence ([ADR-021](DECISIONS.md#adr-021)).

### VM agents

Two binaries from one workspace, split by **absent-not-disabled**
([ADR-021](DECISIONS.md#adr-021)). A forbidden opcode fails at decode
(`TryFrom<u8>`), not at a runtime gate.

**`vm-agent` (AppVM, uid 1000, unprivileged):**

- VSOCK connections accepted from the host only
- `RUN` restricted to an application whitelist (`firefox-esr`, `foot`, `nautilus`)
- `FILEGET`/`FILEPUT` restricted by path whitelist and transfer size limits
- No arbitrary command execution path
- **Contains no network-configuration code** — the least-trusted guest cannot
  even *name* the NETCFG opcode

**`netvm-agent` (sysVM, `CAP_NET_ADMIN` only, not root):**

- **Contains no `RUN`, no `FILEPUT`/`FILEGET`** — no general execution path
  exists inside the process holding network privilege
- `NETCFG` is a **typed link description**, never a shell string and never a
  policy ([ADR-023](DECISIONS.md#adr-023)): interface match, local/peer address,
  `/32` prefix, route, metric; `add` / `remove` only, no `modify`. It cannot
  deliver an nft rule and cannot alter the baked firewall. Validation is
  structural and total — malformed payloads are rejected, never sanitised.
- **No `SHUTDOWN` opcode and no shutdown privilege.** netVM is q35 → has ACPI →
  the host powers it down over QMP `system_powerdown`. Graceful ≠ root.

### Network isolation

- Per-AppVM `/32` p2p links; the netVM firewall is **static and AppVM-agnostic**,
  referencing only the aggregate internal segment. It never changes as AppVMs
  come and go ([ADR-021](DECISIONS.md#adr-021)).
- Differentiated network access is expressed as **attachment to a different
  netVM** (each netVM image bakes one immutable policy), never as a per-AppVM
  rule ([ADR-022](DECISIONS.md#adr-022)).
- An AppVM with `netvm: None` has **no link at all** — air-gap is the absence of
  an object, not a rule denying traffic.
- The netVM image bakes **no internal topology**: on a clean boot it has no
  internal route. Routes exist only for running AppVMs.

### GUI forwarding

Waypipe over VSOCK — no network listener, no X11 surface. Host side is a
socket-activated systemd *user* service (unprivileged).

### Desktop compositor

The host compositor is **inside the TCB**: it draws the domain indicator that
visually separates domains. The indicator must be keyed on **waypipe CID
identity**, i.e. host-side trusted state — never on guest-controlled properties
(`app_id`, window title are spoofable). This is why a single audited profile
(Sway) ships, rather than two ([ADR-016](DECISIONS.md#adr-016)).

### Guests

Minimal Debian userspace, minimal services, direct kernel boot, custom
MicroVM kernel with a reduced config surface. Nothing persists outside the
per-AppVM overlay.

## Trusted computing base

Host kernel (`linux-hardened`) + QEMU/KVM + systemd + host side of vm-agent +
waypipe client + **host compositor (Sway — draws the domain indicator)** +
**launch daemon (owns the topology graph)** + installer-provisioned
configuration. Kept deliberately small; `qemu-full` → `qemu-base` reduction is
under evaluation.

## Known gaps (tracked)

| # | Gap | Status / remediation |
|---|---|---|
| 1 | **Secrets committed in installer scripts** — WireGuard private key, WiFi SSID+PSK, default user credentials | Critical hygiene gap. The committed WG key is considered burned and must be rotated. Replace with install-time prompts / `wg genkey` generation. v0.2 blocker. |
| 2 | Hidden SSID + AutoConnect forces clients into active probing — the machine broadcasts the network name everywhere | Switch to a visible SSID; drop `Hidden=true`. |
| 3 | ~~VPN terminates on the host, contradicting the NetVM target architecture~~ | **Resolved (live on MINIS):** WireGuard/ProtonVPN now terminates in NetVM per [ADR-009](DECISIONS.md#adr-009). Host carries no VPN. |
| 4 | **SSH open on development host** — `tcp dport 22 accept` active on MINIS (dev convenience, not installer default). sshd also runs inside netVM (CID 3). | Both are dev-only. Restrict the host rule to LAN (`iif enp1s0 ip saddr 10.3.1.0/24`) and remove both before release. Not present in the installer-provisioned ruleset. |
| 5 | No base image signing / integrity verification | [ADR-013](DECISIONS.md#adr-013) (Proposed). |
| 6 | No Secure Boot chain | Consistent with threat model (see above); revisit at v1.0. |
| 7 | **VPN key co-located with the NIC driver** — in v1 the WireGuard private key and the `r8169` driver + non-free Realtek firmware blob share one address space. Compromise of the most exposed code in the system (hardware-facing driver) is compromise of the VPN credentials. | Accepted for v1; the model already permits the fix. Post-v1: split into a **driver domain** (q35, hardware, no secrets) and a **proxy netVM** (microVM, secrets, no hardware) — [ADR-022](DECISIONS.md#adr-022). |
| 8 | **Proxy sysVMs will add `CONFIG_WIREGUARD` + netfilter to the shared MicroVM kernel**, which all AppVMs also run. The code is unreachable from an AppVM (uid 1000, no `CAP_NET_ADMIN`) but is *present* — a departure from absent-not-disabled at the kernel level. | Accepted consciously ([ADR-021](DECISIONS.md#adr-021) rejected a second kernel: doubled config maintenance, firmware-licensing issues for ISO distribution). Revisit if a second kernel becomes cheap. |
| 9 | **IOMMU-group quality is a hard requirement, unverified at install time.** A driver domain is only safe where the NIC is cleanly isolable; a bad grouping silently weakens passthrough isolation. | HCL + installer preflight check ([ADR-022](DECISIONS.md#adr-022)); on the ROADMAP, not a v1 code blocker. |
| 10 | **9p hostshare into netVM** — `net-sys.con` carries `virtio-9p-pci` with `security_model=none` sharing `/home/host` into the most network-exposed VM. In no ADR; a dev-convenience remnant (same class as SSH #4, dev-root). | Dev-only. Remove the `-fsdev`/`virtio-9p-pci` pair from the release launcher; not present in any installer-provisioned config. |
