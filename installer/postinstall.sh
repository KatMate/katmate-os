#!/usr/bin/env bash
set -euo pipefail

source /root/install.env

log() {
  echo -e "\n==> $1"
}

die() {
  echo -e "\nERROR: $1"
  exit 1
}

# ---------------------------------------------------------------------------
log "System basics"
# ---------------------------------------------------------------------------

hwclock --systohc

# Passwords are not set here: install.sh applies the hash with chpasswd -e
# after this script returns, so no secret is ever in install.env.
# On a fresh pacstrap an existing name is a system account; refuse it rather
# than add wheel to it.
if id "${USERNAME}" >/dev/null 2>&1; then
  die "User ${USERNAME} already exists in the target (a system account): choose another name."
fi
useradd -m -G wheel "${USERNAME}"

systemctl enable systemd-networkd
systemctl enable systemd-resolved

# No Wi-Fi profile and no VPN on the host. The install-time network is not
# persisted (install.sh), and a VPN is an optional, user-supplied WireGuard
# config in netVM (ADR-037), never a host egress tunnel.

# IMPORTANT:
# Do not touch /etc/resolv.conf here.
# install.sh fixes /mnt/etc/resolv.conf after leaving the chroot.

# ---------------------------------------------------------------------------
log "Locale and keymap"
# ---------------------------------------------------------------------------

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen

locale-gen

cat >/etc/locale.conf <<EOF
LANG=en_US.UTF-8
EOF

cat >/etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
EOF

# ---------------------------------------------------------------------------
log "Firewall config"
# ---------------------------------------------------------------------------

cat >/etc/nftables.conf <<'NFT'
#!/usr/bin/nft -f
# Katmate OS — default firewall ruleset

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;
        policy drop;

        # loopback
        iif lo accept

        # established/related
        ct state established,related accept

        # ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # VSOCK — local (host↔guest communication)
        # vsock has no network rules; it goes through the kernel directly

        # SSH — disabled by default
        # tcp dport 22 accept
    }

    chain forward {
        type filter hook forward priority 0;
        policy drop;
    }

    chain output {
        type filter hook output priority 0;
        policy accept;
    }
}
NFT

chmod 600 /etc/nftables.conf
systemctl enable nftables

# ---------------------------------------------------------------------------
log "VSOCK module autoload"
# ---------------------------------------------------------------------------

# AF_VSOCK is the only host↔guest channel (ADR-003). The module must load at
# boot, or /dev/vsock is absent after the next boot.
echo vhost_vsock > /etc/modules-load.d/katmate-vsock.conf

# ---------------------------------------------------------------------------
log "mkinitcpio"
# ---------------------------------------------------------------------------

# HOOKS: encrypt must come before lvm2, lvm2 before filesystems
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' \
  /etc/mkinitcpio.conf

mkinitcpio -P

# ---------------------------------------------------------------------------
# REQUIREMENT, NOT YET IMPLEMENTED: tier directories (ADR-032 §1) + T1 seeding
# ---------------------------------------------------------------------------
# Written here because a reader of the installer will look for it here. The
# owner of the implementation is step 6 of the build order (ROADMAP.md), not
# this commit.
#
# ADR-032 makes the path the tier: a reader tells a file's tier with `ls`, not
# by reading the ADR. The installer must create four directories, none of
# which exists today:
#
#   /etc/katmate/vm/         T1 — properties.toml, one per VM, root:root 0644
#   /usr/lib/katmate/        T4 — executables called by ExecStartPre=
#   /var/lib/katmate/netvm/  T2 — vmlinuz + initrd.img + netvm.meta
#   /var/lib/katmate/kernels/  T2 — the shared microVM kernel for AppVMs
#
# T1 and seeding. The installer SEEDS T1 but does not own it — the relation is
# /etc/skel to $HOME. A file written at install time is the user's from that
# moment on, and a later release that needs a schema change NOTIFIES, it does
# not overwrite. A hard rule follows from this:
#
#   the installer may CREATE a T1 file;
#   it must never OVERWRITE a file it did not create in the same run.
#
# For the same reason T1 is never in the repository: a committed
# properties.toml is the project's authorship, and by the tier boundary T3/T4,
# not T1. The installer generates it; it does not copy it from the tree.
#
# Check with: tools/validate-properties.fish (with no arguments it defaults to
# /etc/katmate/vm/ and also evaluates the cross-file rules).

# ---------------------------------------------------------------------------
log "Postinstall DONE"
# ---------------------------------------------------------------------------
