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

# root is locked (operator ruling R18): administration is through sudo and
# wheel. install.sh sets the user's password after this script and checks
# /etc/shadow for the '!' marker, not this command's status.
passwd -l root

# No network profile on the host (operator ruling R11): no Wi-Fi profile, no
# VPN, no wired DHCP unit, and neither systemd-networkd nor systemd-resolved
# is enabled, because nothing local needs them. The host's NIC is netVM's
# (vfio-pci from the first boot); VMs reach each other over AF_UNIX datagram
# sockets and the host over vsock. A VPN is an optional, user-supplied
# WireGuard config in netVM (ADR-037), never a host egress tunnel.

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

# HOOKS: encrypt must come before lvm2, lvm2 before filesystems. kms loads the
# GPU driver early, and plymouth comes before encrypt so the LUKS passphrase
# is asked through the splash (operator ruling R15). With plymouth not
# running, the encrypt hook asks on the text console. UNVERIFIED until the
# Cubi gate: Arch's primary sources could not be read where this was written.
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap plymouth block encrypt lvm2 filesystems fsck)/' \
  /etc/mkinitcpio.conf
# MODULES: vfio early, so vfio-pci holds netVM's card before its own driver
# can (install.sh writes the ids and the softdep to modprobe.d, which the
# initramfs carries). HOST-CONFIG §4 records this set on MINIS.
sed -i 's/^MODULES=.*/MODULES=(vfio_pci vfio vfio_iommu_type1)/' /etc/mkinitcpio.conf
grep -qx 'HOOKS=(base udev autodetect modconf kms keyboard keymap plymouth block encrypt lvm2 filesystems fsck)' /etc/mkinitcpio.conf \
  || die "mkinitcpio.conf: HOOKS line not written"
grep -qx 'MODULES=(vfio_pci vfio vfio_iommu_type1)' /etc/mkinitcpio.conf \
  || die "mkinitcpio.conf: MODULES line not written"

mkinitcpio -P

# ---------------------------------------------------------------------------
log "Services"
# ---------------------------------------------------------------------------

# The menu's sudo rule must parse: a broken file under sudoers.d disables
# every rule, wheel's included (HOST-CONFIG §13).
visudo -c -f /etc/sudoers.d/katmate-launch
visudo -c

# netVM starts at boot (HOST-CONFIG §16); AppVMs never do, they start from
# the menu. katmate-publish-nics comes in through the unit's Requires=.
systemctl enable katmate-sys-driver@netvm.service
systemctl enable greetd.service
# The GUI path's host end, for every user's manager (operator ruling R12).
systemctl --global enable waypipe-client.service

# ---------------------------------------------------------------------------
# Tier directories (ADR-032 §1) and T1 seeding are install.sh's, done before
# this script runs: /etc/katmate/vm/ (T1, created from installer/t1/, never
# overwritten), /usr/lib/katmate/ (T4), /var/lib/katmate/{netvm,kernels,
# instances}/ (T2 and the deltas). The installer may CREATE a T1 file; it must
# never OVERWRITE one it did not create in the same run.
# Check with tools/validate-properties.fish, which runs at release time over
# installer/t1/ (fish is not installed here; operator ruling R10).

# ---------------------------------------------------------------------------
log "Postinstall DONE"
# ---------------------------------------------------------------------------
