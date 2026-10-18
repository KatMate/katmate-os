# shellcheck shell=bash
# ---------------------------------------------------------------------------
# KatMate OS — the installed host's package set (sourced, not executed)
# ---------------------------------------------------------------------------
#
# One list, two readers: install.sh pacstraps it, and build/iso.sh builds the
# install medium's offline repository from it, with every KM_UCODE_PKGS entry,
# because the vendor is only known at install.
#
# Desktop and session (operator ruling R16): sway with swaybg for its
# wallpaper, waybar, swaync, greetd with tuigreet, foot (R6 of the brief),
# fuzzel (launcher and menus) and swaylock (the power menu's Lock; fz1),
# PipeWire with WirePlumber (wpctl) and pipewire-pulse (waybar's volume module
# talks to a pulse server), brightnessctl, playerctl, grim, slurp,
# wl-clipboard, wf-recorder, libnotify (notify-send), xdg-utils (xdg-open, for
# km-shot), polkit, plymouth, and the GeistMono and Symbols Nerd fonts.
# e2fsprogs for the home LVs' ext4. Package names were checked by a web search
# only for otf-geist-mono-nerd, ttf-nerd-fonts-symbols, greetd-tuigreet,
# swaync and wf-recorder; the rest are UNVERIFIED until the Cubi install.
# No iwd and no wireguard-tools (operator ruling, 2026-10-05): the host has no
# network, its NIC is netVM's, and a VPN is the user's config in netVM
# (ADR-037). The live system's iwctl is install-time only.
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034  # read by install.sh and build/iso.sh
KM_HOST_PKGS=(
  base linux-hardened linux-hardened-headers linux-firmware
  lvm2 e2fsprogs
  efibootmgr cryptsetup
  micro sudo
  nftables
  qemu-full
  plymouth
  sway swaybg waybar swaync greetd greetd-tuigreet foot fuzzel swaylock
  pipewire wireplumber pipewire-pulse
  brightnessctl playerctl grim slurp wl-clipboard wf-recorder libnotify xdg-utils
  polkit
  otf-geist-mono-nerd ttf-nerd-fonts-symbols
)

# shellcheck disable=SC2034
KM_UCODE_PKGS=(amd-ucode intel-ucode)
