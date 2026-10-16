#!/usr/bin/env bash
# shellcheck disable=SC2034
# KatMate install medium, derived from archiso's releng profile (archiso 91).
# @TAG@ is the release tag, filled in by build/iso.sh.
iso_name="katmate-install"
iso_label="KATMATE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="KatMate OS"
iso_application="KatMate OS install medium"
iso_version="@TAG@"
install_dir="arch"
buildmodes=('iso')
# UEFI only: the installer writes systemd-boot and has no BIOS path.
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
# ADR-040: Intel needs intel_iommu=on; its effect on an AMD machine is not measured.
kernel_params_x86_64="intel_iommu=on"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/katmate-install"]="0:0:755"
)
