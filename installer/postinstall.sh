#!/usr/bin/env bash
set -euo pipefail

source /root/install.env

log() {
  echo -e "\n==> $1"
}

log "Chroot postinstall"

log "System basics"

hwclock --systohc

echo "root:${PASSWORD}" | chpasswd

if ! id "${USERNAME}" >/dev/null 2>&1; then
  useradd -m -G wheel "${USERNAME}"
fi

echo "${USERNAME}:${PASSWORD}" | chpasswd

systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable iwd

log "WiFi config"

mkdir -p /var/lib/iwd

cat >"/var/lib/iwd/${SSID}.psk" <<WIFI
[Security]
Passphrase=${PASS}

[Settings]
AutoConnect=true
Hidden=true
WIFI

chmod 600 "/var/lib/iwd/${SSID}.psk"

mkdir -p /etc/iwd

cat >/etc/iwd/main.conf <<EOF
[General]
EnableNetworkConfiguration=true
UseDefaultInterface=true
EOF

# IMPORTANT:
# Do NOT touch /etc/resolv.conf here.
# Inside arch-chroot it can be bind-mounted or busy.
# install.sh fixes /mnt/etc/resolv.conf after this script exits.

log "Locale config"

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#sl_SI.UTF-8 UTF-8/sl_SI.UTF-8 UTF-8/' /etc/locale.gen

locale-gen

cat >/etc/locale.conf <<EOF
LANG=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_NUMERIC=sl_SI.UTF-8
LC_TIME=sl_SI.UTF-8
LC_COLLATE=sl_SI.UTF-8
LC_MONETARY=sl_SI.UTF-8
LC_PAPER=sl_SI.UTF-8
LC_NAME=sl_SI.UTF-8
LC_ADDRESS=sl_SI.UTF-8
LC_TELEPHONE=sl_SI.UTF-8
LC_MEASUREMENT=sl_SI.UTF-8
LC_IDENTIFICATION=sl_SI.UTF-8
EOF
cat >/etc/vconsole.conf <<EOF
KEYMAP=slovene
EOF

log "Firewall config"

cat >/etc/nftables.conf <<'NFT'
#!/usr/bin/nft -f
# IPv4/IPv6 Simple & Safe firewall ruleset.

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;
        policy drop;

        # loopback
        iif lo accept

        # allow established/related
        ct state established,related accept

        # ping
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # ssh disabled by default
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

log "WireGuard / ProtonVPN config"

mkdir -p /etc/wireguard

cat >/etc/wireguard/proton.conf <<'WG'
[Interface]
# Key for protonCH
# Bouncing = 14
# NetShield = 2
# Moderate NAT = off
# NAT-PMP (Port Forwarding) = off
# VPN Accelerator = on

PrivateKey = qE8UtQBwp3CptrJ+EHxawfO5u5h7MoZsY1mQNFitpVk=
Address = 10.2.0.2/32

# DNS via systemd-resolved
PostUp = resolvectl dns %i 10.2.0.1
PostUp = resolvectl domain %i "~."
PostDown = resolvectl revert %i

[Peer]
# CH#1025
PublicKey = 0zgCMx51QcrEp2vWqOK8XrmmX+ta/KGnUcEXmo124AY=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 66.234.146.2:51820
PersistentKeepalive = 25
WG

chmod 600 /etc/wireguard/proton.conf

# Ne enable-am avtomatsko, da VPN ne zaklene sveže instalacije, če endpoint/DNS/network še ni OK.
# Če želiš autostart:
# systemctl enable wg-quick@proton
systemctl enable wg-quick@proton

log "mkinitcpio"

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf

mkinitcpio -P
# systemctl enable wg-quick@proton

log "GRUB config only"

sed -i '/^GRUB_ENABLE_CRYPTODISK=/d' /etc/default/grub
sed -i '/^GRUB_CMDLINE_LINUX=/d' /etc/default/grub

echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot\"" >> /etc/default/grub

log "Postinstall DONE"
