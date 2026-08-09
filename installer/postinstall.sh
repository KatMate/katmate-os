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

echo "root:${PASSWORD}" | chpasswd

if ! id "${USERNAME}" >/dev/null 2>&1; then
  useradd -m -G wheel "${USERNAME}"
fi

echo "${USERNAME}:${PASSWORD}" | chpasswd

systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable iwd

# ---------------------------------------------------------------------------
log "WiFi config"
# ---------------------------------------------------------------------------

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
# Ne dotikaj se /etc/resolv.conf tukaj.
# install.sh popravi /mnt/etc/resolv.conf po izhodu iz chroot.

# ---------------------------------------------------------------------------
log "Locale config"
# ---------------------------------------------------------------------------

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

        # VSOCK — lokalno (host↔guest komunikacija)
        # vsock nima mrežnih pravil, gre skozi kernel direktno

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
log "WireGuard / ProtonVPN config"
# ---------------------------------------------------------------------------

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
systemctl enable wg-quick@proton

# ---------------------------------------------------------------------------
log "VSOCK module autoload"
# ---------------------------------------------------------------------------

# AF_VSOCK je edini host↔guest kanal (ADR-003). Modul se mora naložiti ob bootu,
# sicer /dev/vsock ob naslednjem zagonu ni prisoten.
echo vhost_vsock > /etc/modules-load.d/katmate-vsock.conf

# ---------------------------------------------------------------------------
log "mkinitcpio"
# ---------------------------------------------------------------------------

# HOOKS: encrypt mora biti pred lvm2, lvm2 pred filesystems
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' \
  /etc/mkinitcpio.conf

mkinitcpio -P

# ---------------------------------------------------------------------------
# ZAHTEVA, ŠE NE IMPLEMENTIRANA: imeniki tierov (ADR-032 §1) + sejanje T1
# ---------------------------------------------------------------------------
# Zapisano tu, ker bo bralec installerja to iskal tu. Lastnik izvedbe je korak 6
# gradbenega vrstnega reda (ROADMAP.md), ne ta commit.
#
# ADR-032 postavi pot kot tier: bralec ugotovi tier datoteke z `ls`, ne z
# branjem ADR-ja. Installer mora ustvariti štiri imenike, od katerih danes ne
# obstaja noben:
#
#   /etc/katmate/vm/         T1 — properties.toml, ena na VM, root:root 0644
#   /usr/lib/katmate/        T4 — izvedljive datoteke, ki jih kliče ExecStartPre=
#   /var/lib/katmate/netvm/  T2 — vmlinuz + initrd.img + netvm.meta
#   /var/lib/katmate/kernels/  T2 — deljeno microVM jedro za AppVM-e
#
# T1 in sejanje. Installer T1 SEJE, ni pa njegov lastnik — razmerje je /etc/skel
# proti $HOME. Datoteka, zapisana ob namestitvi, je od tistega trenutka
# uporabnikova, in kasnejša izdaja, ki potrebuje spremembo sheme, OBVESTI,
# ne prepiše. Iz tega sledi trdo pravilo:
#
#   installer sme USTVARITI datoteko T1;
#   nikoli ne sme PREPISATI datoteke, ki je ni ustvaril v istem teku.
#
# Zato tudi T1 ni nikoli v repozitoriju: commitano properties.toml je avtorstvo
# projekta in po tierski meji T3/T4, ne T1. Installer ga zgenerira, ne kopira
# iz drevesa.
#
# Preveri z: tools/validate-properties.fish (brez argumentov privzame
# /etc/katmate/vm/ in ovrednoti tudi pravila čez datoteke).

# ---------------------------------------------------------------------------
log "Postinstall DONE"
# ---------------------------------------------------------------------------
