#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KatMate OS — hardware preflight (read-only)
# ---------------------------------------------------------------------------
#
# Run as root on the target machine, booted from the Arch Linux live ISO,
# before install.sh. It MEASURES and does not configure: no modprobe, no sysfs
# write, no driver bind or unbind, no package install. The only file it
# writes is its own report (default ./katmate-preflight-<host>-<UTC>.txt).
#
# Every check ends PASS / WARN / FAIL / SKIPPED with its raw evidence quoted
# under it. The summary ends GO (exit 0), GO-WITH-WARNINGS (exit 1) or NO-GO
# (exit 2). Any exit before the summary is exit 3, PREFLIGHT ABORTED — NO
# VERDICT, so an aborted run can never read as a verdict.
#
# What it records and deliberately does not decide: the kernel cmdline,
# mkinitcpio MODULES, the NIC's durable descriptor (ADR-030 §5) and the vfio
# binding. Those are later steps; this produces their evidence.
#
# Usage: bash preflight.sh [-o <output-file>]
# ---------------------------------------------------------------------------

# Thresholds taken from the tree, not chosen here.
MIN_DISK_GB=32   # install.sh MIN_DISK_GB, same arithmetic (bytes / 1024^3)
MIN_RAM_GB=8     # docs/INSTALL.md "8 GB practical minimum"

# Bridges never disqualify a group (operator ruling 2026-10-04, item 1).
BRIDGE_CLASS="0604"

# ---------------------------------------------------------------------------

OUT=""
OUT_OPEN=0
FINISHED=0

log() {
  say "" "==> $1"
}

die() {
  local msg="ERROR: $1"
  printf '\n%s\n' "$msg" >&2
  (( OUT_OPEN )) && printf '\n%s\n' "$msg" >&3
  exit 3
}

have() {
  command -v "$1" >/dev/null 2>&1
}

# Every line goes to the terminal and to the report.
say() {
  local line
  for line in "$@"; do
    printf '%s\n' "$line"
    (( OUT_OPEN )) && printf '%s\n' "$line" >&3
  done
  return 0
}

# Quote stdin as evidence. Empty input is said to be empty, never omitted.
quote() {
  local line n=0
  while IFS= read -r line; do
    say "    | $line"
    n=$(( n + 1 ))
  done
  (( n > 0 )) || say "    | <empty>"
  return 0
}

# Read one sysfs/procfs value; an unreadable file is a value, not an abort.
readv() {
  local v
  if [[ -r "$1" ]] && v="$(cat -- "$1" 2>/dev/null)"; then
    printf '%s' "$v"
  else
    printf '<unreadable>'
  fi
}

# ---------------------------------------------------------------------------
# Aborts before the summary are exit 3 (ruling 2026-10-04, item 3).
# ---------------------------------------------------------------------------

# Invoked by the trap below, which a static checker does not follow.
# shellcheck disable=SC2329
on_exit() {
  local rc=$?
  if (( ! FINISHED )); then
    printf '\nPREFLIGHT ABORTED — NO VERDICT (internal exit status %s)\n' "$rc" >&2
    (( OUT_OPEN )) && printf '\nPREFLIGHT ABORTED — NO VERDICT (internal exit status %s)\n' "$rc" >&3
    exit 3
  fi
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

while getopts ':o:h' opt; do
  case "$opt" in
    o) OUT="$OPTARG" ;;
    h) printf 'Usage: bash preflight.sh [-o <output-file>]\n'; FINISHED=1; exit 0 ;;
    :) die "-$OPTARG needs an argument" ;;
    *) die "unknown option -$OPTARG (usage: bash preflight.sh [-o <output-file>])" ;;
  esac
done
shift $(( OPTIND - 1 ))
(( $# == 0 )) || die "unexpected argument(s): $*"

# ---------------------------------------------------------------------------
# Root. Unprivileged, the ACPI tables and parts of the kernel log are
# unreadable, and the checks reading them would fail without measuring.
# ---------------------------------------------------------------------------

(( EUID == 0 )) || die "must run as root: the ACPI tables and the kernel log are root-only, and an unprivileged run cannot tell 'absent' from 'not allowed'"

for c in cat grep sed awk sort uniq tr ls readlink basename dirname date uname wc head; do
  have "$c" || die "Missing command: $c"
done

# ---------------------------------------------------------------------------
# Output file: verified writable by creating it, before any check runs. The
# Arch ISO medium is iso9660 and read-only, so the directory may not be.
# ---------------------------------------------------------------------------

HOST_NAME="$(uname -n)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
[[ -n "$OUT" ]] || OUT="./katmate-preflight-${HOST_NAME}-${STAMP}.txt"

[[ ! -e "$OUT" ]] || die "$OUT already exists; refusing to overwrite it (use -o)"
set -o noclobber
if ! exec 3>"$OUT"; then
  die "cannot create $OUT: the directory is not writable (the Arch ISO medium is read-only). Run from a writable directory or pass -o, e.g. -o /tmp/preflight.txt, and copy it off before reboot"
fi
OUT_OPEN=1

# ---------------------------------------------------------------------------
# Result bookkeeping
# ---------------------------------------------------------------------------

R_NAME=()
R_STATUS=()
R_NOTE=()

record() {
  R_NAME+=("$1")
  R_STATUS+=("$2")
  R_NOTE+=("$3")
  say "  -> $2: $3"
}

say "KatMate preflight (read-only)" \
    "host:    $HOST_NAME" \
    "kernel:  $(uname -r)" \
    "time:    $STAMP (UTC)" \
    "output:  $OUT" \
    "No module is loaded, no sysfs file is written, no driver is bound or unbound."

# ---------------------------------------------------------------------------
# Kernel log, read once. dmesg first; the journal is the fallback when the
# boot-time lines have left the ring buffer (a long-running host).
# ---------------------------------------------------------------------------

KLOG_DMESG=""
KLOG_DMESG_STATE="not available (dmesg not installed)"
if have dmesg; then
  if KLOG_DMESG="$(dmesg 2>&1)"; then
    KLOG_DMESG_STATE="read ($(printf '%s\n' "$KLOG_DMESG" | wc -l) lines)"
  else
    KLOG_DMESG_STATE="failed: $(printf '%s' "$KLOG_DMESG" | head -n 1)"
    KLOG_DMESG=""
  fi
fi

KLOG_JOURNAL=""
KLOG_JOURNAL_STATE="not available (journalctl not installed)"
if have journalctl; then
  if KLOG_JOURNAL="$(journalctl -k -b 0 -o cat --no-pager 2>&1)"; then
    KLOG_JOURNAL_STATE="read ($(printf '%s\n' "$KLOG_JOURNAL" | wc -l) lines)"
  else
    KLOG_JOURNAL_STATE="failed: $(printf '%s' "$KLOG_JOURNAL" | head -n 1)"
    KLOG_JOURNAL=""
  fi
fi

# klog_grep <ERE>: matching lines from dmesg, or from the journal only if
# dmesg had none. Sets KLOG_HITS and KLOG_SRC (globals: a $(...) caller would
# lose the source).
KLOG_HITS=""
KLOG_SRC=""
klog_grep() {
  KLOG_HITS="$(printf '%s\n' "$KLOG_DMESG" | grep -E -- "$1" || true)"
  KLOG_SRC="dmesg"
  if [[ -z "$KLOG_HITS" ]]; then
    KLOG_HITS="$(printf '%s\n' "$KLOG_JOURNAL" | grep -E -- "$1" || true)"
    if [[ -n "$KLOG_HITS" ]]; then KLOG_SRC="journalctl -k -b 0"; else KLOG_SRC="none"; fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------

log "CPU"

CPU_VENDOR=""
if [[ -r /proc/cpuinfo ]]; then
  CPU_VENDOR="$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}' || true)"
  CPU_MODEL="$(grep -m1 '^model name' /proc/cpuinfo | sed 's/^model name[[:space:]]*:[[:space:]]*//' || true)"
  CPU_VIRT="$(grep -m1 '^flags' /proc/cpuinfo | grep -o -w -E 'vmx|svm' | sort -u | tr '\n' ' ' || true)"
  say "  vendor_id:  ${CPU_VENDOR:-<none>}" \
      "  model name: ${CPU_MODEL:-<none>}" \
      "  virtualisation flags in the first 'flags' line: ${CPU_VIRT:-<none>}"
  case "$CPU_VENDOR" in
    GenuineIntel) want=vmx ;;
    AuthenticAMD) want=svm ;;
    *)            want="" ;;
  esac
  if [[ -z "$want" ]]; then
    record "cpu" FAIL "vendor '${CPU_VENDOR:-<none>}' is neither GenuineIntel nor AuthenticAMD (IOMMU-capable platforms only)"
  elif [[ " $CPU_VIRT " == *" $want "* ]]; then
    record "cpu" PASS "$CPU_VENDOR, '$want' present"
  else
    record "cpu" FAIL "$CPU_VENDOR without '$want': virtualisation unsupported or disabled in firmware"
  fi
else
  record "cpu" FAIL "/proc/cpuinfo unreadable"
fi

# ---------------------------------------------------------------------------
# Firmware
# ---------------------------------------------------------------------------

log "Firmware"

if [[ -d /sys/firmware/efi ]]; then
  say "  /sys/firmware/efi exists; fw_platform_size: $(readv /sys/firmware/efi/fw_platform_size)"
  record "uefi" PASS "booted via UEFI"
else
  say "  /sys/firmware/efi: absent"
  record "uefi" FAIL "not booted via UEFI (/sys/firmware/efi absent); install.sh needs an ESP and systemd-boot"
fi

# ---------------------------------------------------------------------------
# KVM — observed only; nothing is loaded.
# ---------------------------------------------------------------------------

log "KVM"

case "$CPU_VENDOR" in
  GenuineIntel) KVM_MOD=kvm_intel ;;
  AuthenticAMD) KVM_MOD=kvm_amd ;;
  *)            KVM_MOD="" ;;
esac

{
  if [[ -e /dev/kvm ]]; then ls -l /dev/kvm 2>&1 || true; else echo "/dev/kvm: absent"; fi
  for m in kvm kvm_intel kvm_amd; do
    if [[ -d "/sys/module/$m" ]]; then echo "module $m: present (/sys/module/$m)"; else echo "module $m: not loaded"; fi
  done
  for m in kvm_intel kvm_amd; do
    [[ -e "/sys/module/$m/parameters/nested" ]] && echo "$m nested: $(readv "/sys/module/$m/parameters/nested")"
  done
  true
} | quote

if [[ -z "$KVM_MOD" ]]; then
  record "kvm" SKIPPED "CPU vendor unknown, no KVM module to expect"
elif [[ -c /dev/kvm && -d "/sys/module/$KVM_MOD" ]]; then
  record "kvm" PASS "/dev/kvm present, $KVM_MOD loaded"
else
  record "kvm" WARN "/dev/kvm or $KVM_MOD not present; this script loads nothing, so absence is not proof that KVM is unusable"
fi

# ---------------------------------------------------------------------------
# Kernel command line. The IOMMU results below depend on it.
# ---------------------------------------------------------------------------

log "Kernel command line"

CMDLINE=""
IOMMU_PARAMS=""
if CMDLINE="$(cat /proc/cmdline 2>/dev/null)"; then
  printf '%s\n' "$CMDLINE" | quote
  set -f
  for tok in $CMDLINE; do
    case "$tok" in
      intel_iommu=*|amd_iommu=*|iommu=*|iommu.*=*|intremap=*|vfio-pci.*|vfio_pci.*)
        IOMMU_PARAMS+="$tok " ;;
    esac
  done
  set +f
  say "  IOMMU-related parameters this kernel was booted with: ${IOMMU_PARAMS:-none}"
  if [[ " $IOMMU_PARAMS " == *" amd_iommu=on "* ]]; then
    say "  note: 'on' is not an amd_iommu= option; the kernel logs 'AMD-Vi: Unknown option' and ignores it (state.md, Invariants)"
  fi
  record "cmdline" PASS "IOMMU parameters: ${IOMMU_PARAMS:-none}"
else
  record "cmdline" FAIL "/proc/cmdline unreadable"
fi

# The kernel's own defaults, if it publishes its config. Not loaded if absent.
KCONFIG=""
if [[ -r /proc/config.gz ]] && have zcat; then
  KCONFIG="$(zcat /proc/config.gz 2>/dev/null | grep -E '^(# )?CONFIG_(INTEL_IOMMU|INTEL_IOMMU_DEFAULT_ON|AMD_IOMMU|IRQ_REMAP)[ =]' || true)"
  say "  /proc/config.gz:"
  printf '%s\n' "$KCONFIG" | quote
else
  say "  /proc/config.gz: not readable (absent, or zcat missing); kernel IOMMU defaults unknown"
fi

# ---------------------------------------------------------------------------
# IOMMU: ACPI table, then activity.
# ---------------------------------------------------------------------------

log "IOMMU — ACPI table"

ACPI_DIR=/sys/firmware/acpi/tables
case "$CPU_VENDOR" in
  GenuineIntel) IOMMU_TABLE=DMAR ;;
  AuthenticAMD) IOMMU_TABLE=IVRS ;;
  *)            IOMMU_TABLE="" ;;
esac

TABLE_PRESENT=0
if [[ -d "$ACPI_DIR" && -r "$ACPI_DIR" ]]; then
  {
    for t in DMAR IVRS; do
      if [[ -e "$ACPI_DIR/$t" ]]; then ls -l "$ACPI_DIR/$t" 2>&1 || true; else echo "$ACPI_DIR/$t: absent"; fi
    done
  } | quote
  if [[ -z "$IOMMU_TABLE" ]]; then
    record "iommu-acpi" FAIL "CPU vendor unknown; no IOMMU table to expect"
  elif [[ -e "$ACPI_DIR/$IOMMU_TABLE" ]]; then
    TABLE_PRESENT=1
    record "iommu-acpi" PASS "$IOMMU_TABLE present"
  else
    record "iommu-acpi" FAIL "$IOMMU_TABLE absent: firmware publishes no IOMMU (VT-d/AMD-Vi disabled in firmware setup, or unsupported)"
  fi
else
  record "iommu-acpi" FAIL "$ACPI_DIR unreadable; the table cannot be checked"
fi

log "IOMMU — active"

IOMMU_ACTIVE=0
shopt -s nullglob
IOMMU_UNITS=(/sys/class/iommu/*)
shopt -u nullglob
if (( ${#IOMMU_UNITS[@]} > 0 )); then
  IOMMU_ACTIVE=1
  printf '%s\n' "${IOMMU_UNITS[@]}" | quote
else
  say "  /sys/class/iommu/: empty or absent"
fi
say "  kernel log ($KLOG_DMESG_STATE; journal: $KLOG_JOURNAL_STATE), IOMMU lines:"
klog_grep 'DMAR:|DMAR-IR:|AMD-Vi:|iommu:'
say "  source: $KLOG_SRC (first 40 lines)"
printf '%s\n' "$KLOG_HITS" | head -n 40 | grep -v '^$' | quote || true

if (( IOMMU_ACTIVE )); then
  record "iommu-active" PASS "${#IOMMU_UNITS[@]} IOMMU unit(s) under /sys/class/iommu"
else
  if (( ! TABLE_PRESENT )); then
    cause="no ${IOMMU_TABLE:-IOMMU} table: firmware, not the command line (see iommu-acpi)"
  elif [[ " $IOMMU_PARAMS " =~ \ (intel_iommu=off|amd_iommu=off|iommu=off)\  ]]; then
    cause="disabled by the live command line (${BASH_REMATCH[1]})"
  elif [[ "$CPU_VENDOR" == GenuineIntel && " $IOMMU_PARAMS " != *" intel_iommu=on "* ]]; then
    if printf '%s\n' "$KCONFIG" | grep -q '^CONFIG_INTEL_IOMMU_DEFAULT_ON=y'; then
      cause="DMAR present, kernel default is on, no disabling parameter: cause not determined"
    else
      cause="DMAR present but the live command line lacks intel_iommu=on (kernel default: $(printf '%s\n' "$KCONFIG" | grep 'INTEL_IOMMU_DEFAULT_ON' || echo 'unknown')). NOT a firmware verdict: reboot the live ISO with intel_iommu=on and re-run"
    fi
  else
    cause="table present, no disabling parameter on the command line: cause not determined"
  fi
  record "iommu-active" FAIL "IOMMU inactive — $cause"
fi

# ---------------------------------------------------------------------------
# Interrupt remapping: the kernel log line, and the IR- chips in
# /proc/interrupts as a second reading (ruling 2026-10-04, item 5).
# ---------------------------------------------------------------------------

log "Interrupt remapping"

klog_grep 'DMAR-IR: Enabled IRQ remapping in (x2apic|xapic) mode|AMD-Vi: Interrupt remapping enabled'
IR_LINE="$KLOG_HITS"
IR_LOG_SRC="$KLOG_SRC"
say "  enabling line (source: $IR_LOG_SRC):"
printf '%s\n' "$IR_LINE" | grep -v '^$' | quote || true
klog_grep '[Rr]emapping|intremap'
say "  every kernel log line mentioning remapping (source: $KLOG_SRC, first 20):"
printf '%s\n' "$KLOG_HITS" | head -n 20 | grep -v '^$' | quote || true

IR_CHIPS=-1
if [[ -r /proc/interrupts ]]; then
  IR_CHIPS="$(grep -c ' IR-' /proc/interrupts || true)"
  say "  /proc/interrupts lines on an IR- chip: $IR_CHIPS; chip names seen:"
  { grep -o ' IR-[A-Za-z-]*' /proc/interrupts || true; } | sed 's/^ //' | sort | uniq -c | quote
else
  say "  /proc/interrupts: unreadable"
fi

if [[ -n "$IR_LINE" ]] && (( IR_CHIPS > 0 )); then
  record "interrupt-remap" PASS "enabled: log line ($IR_LOG_SRC) and $IR_CHIPS IR- interrupt lines agree"
elif [[ -n "$IR_LINE" ]] && (( IR_CHIPS == 0 )); then
  record "interrupt-remap" WARN "log says enabled ($IR_LOG_SRC) but /proc/interrupts shows no IR- chip: readings disagree"
elif [[ -n "$IR_LINE" ]]; then
  record "interrupt-remap" WARN "log says enabled ($IR_LOG_SRC); second reading unavailable (/proc/interrupts unreadable)"
elif (( IR_CHIPS > 0 )); then
  record "interrupt-remap" WARN "no enabling line in dmesg or the journal, but $IR_CHIPS IR- interrupt lines: readings disagree"
else
  record "interrupt-remap" FAIL "no enabling line in dmesg or the journal, and no IR- chip in /proc/interrupts"
fi

# ---------------------------------------------------------------------------
# PCI inventory and IOMMU groups
# ---------------------------------------------------------------------------

log "IOMMU groups"

declare -A P_CLASS=() P_VEN=() P_DEV=() P_DRV=() P_GROUP=() G_MEMBERS=() LSPCI=()
PCI_ALL=()

if have lspci; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && LSPCI["${line%% *}"]="${line#* }"
  done < <(lspci -Dnn 2>/dev/null || true)
fi

shopt -s nullglob
for d in /sys/bus/pci/devices/*; do
  bdf="$(basename "$d")"
  PCI_ALL+=("$bdf")
  c="$(readv "$d/class")"; P_CLASS[$bdf]="${c#0x}"
  v="$(readv "$d/vendor")"; P_VEN[$bdf]="${v#0x}"
  v="$(readv "$d/device")"; P_DEV[$bdf]="${v#0x}"
  if [[ -L "$d/driver" ]]; then P_DRV[$bdf]="$(basename "$(readlink "$d/driver")")"; else P_DRV[$bdf]="none"; fi
  if [[ -L "$d/iommu_group" ]]; then
    g="$(basename "$(readlink "$d/iommu_group")")"
    P_GROUP[$bdf]="$g"
    G_MEMBERS[$g]+="$bdf "
  else
    P_GROUP[$bdf]=""
  fi
done
shopt -u nullglob

pci_line() {
  local b="$1"
  printf '%s class %s [%s:%s] driver %s%s' "$b" "${P_CLASS[$b]}" "${P_VEN[$b]}" "${P_DEV[$b]}" "${P_DRV[$b]}" \
    "${LSPCI[$b]:+  — ${LSPCI[$b]}}"
}

if have lspci; then say "  names from lspci -Dnn"; else say "  lspci not installed: names SKIPPED, sysfs values only"; fi

if (( ${#PCI_ALL[@]} == 0 )); then
  record "iommu-groups" FAIL "/sys/bus/pci/devices is empty or unreadable: no PCI device visible"
elif (( ${#G_MEMBERS[@]} == 0 )); then
  if (( IOMMU_ACTIVE )); then
    record "iommu-groups" FAIL "IOMMU active but no device has an iommu_group"
  else
    record "iommu-groups" SKIPPED "no groups: IOMMU inactive (see iommu-active)"
  fi
else
  while IFS= read -r g; do
    say "  group $g:"
    for b in ${G_MEMBERS[$g]}; do say "    $(pci_line "$b")"; done
  done < <(printf '%s\n' "${!G_MEMBERS[@]}" | sort -n)
  # The IOMMU itself (0806) and the host bridge / root complex (0600) sit
  # outside any group by design: measured on MINIS, 2026-10-04 (pf-minis.txt),
  # 0000:00:00.0 [1022:14e8] and 0000:00:00.2 [1022:14e9]. No other class is
  # exempt without a measured case.
  ungrouped=()
  expected=()
  for b in "${PCI_ALL[@]}"; do
    [[ -n "${P_GROUP[$b]}" ]] && continue
    case "${P_CLASS[$b]:0:4}" in
      0806|0600) expected+=("$b") ;;
      *)         ungrouped+=("$b") ;;
    esac
  done
  if (( ${#expected[@]} > 0 )); then
    say "  expected ungrouped (IOMMU 0806, host bridge 0600):"
    for b in "${expected[@]}"; do say "    $(pci_line "$b")"; done
  fi
  if (( ${#ungrouped[@]} > 0 )); then
    say "  devices with no IOMMU group:"
    for b in "${ungrouped[@]}"; do say "    $(pci_line "$b")"; done
    record "iommu-groups" WARN "${#G_MEMBERS[@]} group(s) over ${#PCI_ALL[@]} PCI devices; ${#ungrouped[@]} device(s) in no group"
  else
    record "iommu-groups" PASS "${#G_MEMBERS[@]} group(s) over ${#PCI_ALL[@]} PCI devices${expected[0]:+; ${#expected[@]} expected ungrouped}"
  fi
fi

# ---------------------------------------------------------------------------
# Isolation of passthrough candidates (ruling 2026-10-04, item 1): ISOLABLE
# only if every other group member is a PCI bridge, or a function of the same
# slot with the same PCI class (base + subclass) as the candidate.
# ---------------------------------------------------------------------------

log "Isolation of passthrough candidates"

is_wifi() {
  local b="$1" n
  [[ "${P_CLASS[$b]:0:4}" == 0280 ]] && return 0
  for n in /sys/bus/pci/devices/"$b"/net/*; do
    [[ -e "$n/phy80211" || -d "$n/wireless" ]] && return 0
  done
  return 1
}

ETH=() WIFI=() USB=() GPU=()
for b in "${PCI_ALL[@]}"; do
  c="${P_CLASS[$b]}"
  if is_wifi "$b"; then WIFI+=("$b")
  elif [[ "${c:0:4}" == 0200 ]]; then ETH+=("$b")
  elif [[ "${c:0:4}" == 0c03 ]]; then USB+=("$b")
  fi
  [[ "${c:0:2}" == 03 ]] && GPU+=("$b")
done
say "  Ethernet: ${ETH[*]:-none}" "  Wi-Fi:    ${WIFI[*]:-none}" "  USB:      ${USB[*]:-none}"

ETH_ISO=0
USB_ISO=0

assess() {
  local kind="$1" b="$2" g="${P_GROUP[$2]}" m offenders="" members=""
  say "" "  $kind $(pci_line "$b")"
  if (( ! IOMMU_ACTIVE )); then
    record "isolation $kind $b" SKIPPED "IOMMU inactive (see iommu-active)"
    return 0
  fi
  if [[ -z "$g" ]]; then
    record "isolation $kind $b" WARN "in no IOMMU group; members: $b ${P_CLASS[$b]} ${P_VEN[$b]}:${P_DEV[$b]}"
    return 0
  fi
  say "    group $g members:"
  for m in ${G_MEMBERS[$g]}; do
    say "      $(pci_line "$m")"
    members+="$m ${P_CLASS[$m]} ${P_VEN[$m]}:${P_DEV[$m]}; "
    [[ "$m" == "$b" ]] && continue
    [[ "${P_CLASS[$m]:0:4}" == "$BRIDGE_CLASS" ]] && continue
    [[ "${m%.*}" == "${b%.*}" && "${P_CLASS[$m]:0:4}" == "${P_CLASS[$b]:0:4}" ]] && continue
    offenders+="$m "
  done
  members="${members%; }"
  if [[ -z "$offenders" ]]; then
    case "$kind" in eth) ETH_ISO=$(( ETH_ISO + 1 )) ;; usb) USB_ISO=$(( USB_ISO + 1 )) ;; esac
    record "isolation $kind $b" PASS "isolable, group $g: $members"
  else
    record "isolation $kind $b" WARN "NOT isolable, group $g shares with ${offenders% }: $members"
  fi
}

if (( ${#ETH[@]} == 0 )); then
  record "isolation eth" WARN "no Ethernet controller among ${#PCI_ALL[@]} PCI devices"
fi
for b in "${ETH[@]}"; do assess eth "$b"; done
if (( ${#WIFI[@]} == 0 )); then
  record "isolation wifi" SKIPPED "no Wi-Fi controller among ${#PCI_ALL[@]} PCI devices"
fi
for b in "${WIFI[@]}"; do assess wifi "$b"; done
if (( ${#USB[@]} == 0 )); then
  record "isolation usb" SKIPPED "no USB controller among ${#PCI_ALL[@]} PCI devices"
fi
for b in "${USB[@]}"; do assess usb "$b"; done

# Aggregate (ruling 2026-10-04, item 2; ADR-022).
say ""
if (( ! IOMMU_ACTIVE )); then
  record "isolation-aggregate" SKIPPED "IOMMU inactive (see iommu-active)"
elif (( ETH_ISO == 0 && USB_ISO == 0 )); then
  record "isolation-aggregate" FAIL "no isolable Ethernet and no isolable USB controller: no driver-domain path (ADR-022)"
elif (( ETH_ISO == 0 )); then
  record "isolation-aggregate" WARN "no isolable Ethernet controller; $USB_ISO isolable USB controller(s): USB NIC path only"
else
  record "isolation-aggregate" PASS "$ETH_ISO isolable Ethernet, $USB_ISO isolable USB controller(s)"
fi

# ---------------------------------------------------------------------------
# Ethernet NICs: raw identity data for the ADR-030 §5 descriptor question.
# No descriptor is chosen here.
# ---------------------------------------------------------------------------

log "Ethernet NIC identity (candidates for the ADR-030 §5 descriptor, none chosen)"

for b in "${ETH[@]}"; do
  d="/sys/bus/pci/devices/$b"
  say "" "  NIC $b"
  mac_ok=0
  {
    echo "vendor:device        ${P_VEN[$b]}:${P_DEV[$b]}"
    echo "subsystem            $(readv "$d/subsystem_vendor"):$(readv "$d/subsystem_device")"
    echo "driver               ${P_DRV[$b]}"
    echo "sysfs path           $(readlink -f "$d" 2>/dev/null || echo '<unreadable>')"
    echo "firmware_node path   $(readv "$d/firmware_node/path")"
    echo "acpi_index           $(readv "$d/acpi_index")"
    echo "label (SMBIOS)       $(readv "$d/label")"
    slot=""
    for s in /sys/bus/pci/slots/*/address; do
      [[ -r "$s" && "$(cat "$s" 2>/dev/null)" == "${b%.*}" ]] && slot+="$(basename "$(dirname "$s")") "
    done
    echo "physical slot        ${slot:-<none published>}"
    if have lspci; then
      dsn="$(lspci -vv -s "$b" 2>/dev/null | grep 'Device Serial Number' || true)"
      echo "PCIe DSN             ${dsn:-<none>}"
    else
      echo "PCIe DSN             SKIPPED (lspci not installed)"
    fi
  } | quote
  for n in "$d"/net/*; do
    [[ -e "$n" ]] || continue
    ifc="$(basename "$n")"
    mac_ok=1
    {
      echo "interface            $ifc"
      echo "address              $(readv "$n/address")"
      echo "addr_assign_type     $(readv "$n/addr_assign_type") (0 = permanent)"
      if have ethtool; then
        echo "ethtool -P           $(ethtool -P "$ifc" 2>&1 || true)"
      else
        echo "ethtool -P           SKIPPED (ethtool not installed)"
      fi
      if have udevadm; then
        udevadm info -q property -p "/sys/class/net/$ifc" 2>/dev/null | grep -E '^(ID_PATH|ID_NET_NAME_[A-Z]+|ID_NET_NAME)=' || echo "udev: no ID_PATH/ID_NET_NAME properties"
      else
        echo "udev                 SKIPPED (udevadm not installed)"
      fi
    } | quote
  done
  if (( mac_ok )); then
    record "nic $b" PASS "MAC read before any vfio bind (HOST-CONFIG §3: readable only before vfio-pci binds)"
  else
    if [[ "${P_DRV[$b]}" == vfio-pci ]]; then
      record "nic $b" WARN "bound to vfio-pci: no network interface, MAC not readable on this host (HOST-CONFIG §3: readable only before vfio-pci binds)"
    else
      record "nic $b" WARN "no network interface under the PCI device (driver ${P_DRV[$b]}): MAC not read"
    fi
  fi
done
(( ${#ETH[@]} > 0 )) || say "  no Ethernet controller (see isolation eth)"

# ---------------------------------------------------------------------------
# GPU — recorded for the future MODULES decision, not decided.
# ---------------------------------------------------------------------------

log "GPU"

if (( ${#GPU[@]} == 0 )); then
  record "gpu" WARN "no display controller (class 03xx) among ${#PCI_ALL[@]} PCI devices"
else
  for b in "${GPU[@]}"; do pci_line "$b"; echo; done | quote
  note=""
  for b in "${GPU[@]}"; do note+="$b ${P_VEN[$b]}:${P_DEV[$b]} driver ${P_DRV[$b]}; "; done
  record "gpu" PASS "${note%; }"
fi

# ---------------------------------------------------------------------------
# Sizing: RAM, CPUs, disks
# ---------------------------------------------------------------------------

log "Sizing"

MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
if [[ "$MEM_KB" =~ ^[0-9]+$ ]]; then
  say "  MemTotal: $MEM_KB kB ($(( MEM_KB / 1024 / 1024 )) GiB, rounded down)"
  if (( MEM_KB < MIN_RAM_GB * 1024 * 1024 )); then
    record "ram" WARN "$(( MEM_KB / 1024 )) MiB, below the ${MIN_RAM_GB} GiB practical minimum (INSTALL.md)"
  else
    record "ram" PASS "$(( MEM_KB / 1024 )) MiB"
  fi
else
  record "ram" FAIL "MemTotal unreadable from /proc/meminfo"
fi

ONLINE="$(readv /sys/devices/system/cpu/online)"
NPROC="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || true)"
say "  /sys/devices/system/cpu/online: $ONLINE" "  processor entries in /proc/cpuinfo: ${NPROC:-<unreadable>}"
if [[ "$NPROC" =~ ^[1-9][0-9]*$ ]]; then
  record "cpus" PASS "$NPROC logical CPUs (online: $ONLINE)"
else
  record "cpus" FAIL "CPU count unreadable"
fi

# disk_of <path>: the disk a block device (or a link to one) belongs to.
disk_of() {
  local dev pk
  dev="$(readlink -f -- "$1" 2>/dev/null || true)"
  [[ -n "$dev" && -b "$dev" ]] || return 1
  pk="$(lsblk -n -d -o PKNAME "$dev" 2>/dev/null | head -n 1 || true)"
  pk="${pk//[[:space:]]/}"
  if [[ -z "$pk" ]]; then
    pk="$(lsblk -n -d -o NAME "$dev" 2>/dev/null | head -n 1 || true)"
    pk="${pk//[[:space:]]/}"
  fi
  [[ -n "$pk" ]] || return 1
  printf '%s' "$pk"
}

if have lsblk; then
  # The live boot medium, so that it is never offered as an install target.
  # Methods in the archiso hook's own order (mkinitcpio-archiso hooks/archiso,
  # read 2026-10-04): an explicit archisodevice=; archisosearchuuid= resolved
  # as UUID=<uuid>; archisolabel= as /dev/disk/by-label/<label>. The hook's
  # mount, /run/archiso/bootmnt, is a secondary source only: with copytoram
  # (default auto) the hook unmounts it after copying the image to RAM.
  LIVE_DISK=""
  a_uuid="" a_label="" a_dev="" ARCHISO_PARAMS=""
  set -f
  for tok in $CMDLINE; do
    case "$tok" in
      archisosearchuuid=*) a_uuid="${tok#*=}";  ARCHISO_PARAMS+="$tok " ;;
      archisolabel=*)      a_label="${tok#*=}"; ARCHISO_PARAMS+="$tok " ;;
      archisodevice=*)     a_dev="${tok#*=}";   ARCHISO_PARAMS+="$tok " ;;
      copytoram=*)         ARCHISO_PARAMS+="$tok " ;;
    esac
  done
  set +f

  if [[ "$ARCHISO_PARAMS" != *archiso* ]]; then
    say "  live boot medium: not an archiso live boot: no boot medium to exclude"
  else
    say "  archiso parameters on the command line: ${ARCHISO_PARAMS% }"
    cands=()
    [[ -n "$a_dev" ]]   && cands+=("archisodevice|$a_dev")
    [[ -n "$a_uuid" ]]  && cands+=("archisosearchuuid|/dev/disk/by-uuid/$a_uuid")
    [[ -n "$a_label" ]] && cands+=("archisolabel|/dev/disk/by-label/$a_label")
    src=""
    if have findmnt; then
      src="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
    fi
    if [[ -n "$src" ]]; then
      cands+=("/run/archiso/bootmnt|$src")
    elif [[ -d /run/archiso/copytoram ]]; then
      say "  /run/archiso/bootmnt: not mounted; /run/archiso/copytoram exists, so the hook copied the image to RAM and unmounted the boot medium (copytoram)"
    else
      say "  /run/archiso/bootmnt: not mounted; no /run/archiso/copytoram, so why is not determinable here"
    fi
    LIVE_SEEN=""
    for c in "${cands[@]}"; do
      how="${c%%|*}"; path="${c#*|}"
      if d="$(disk_of "$path")"; then
        say "  $how: $path -> $(readlink -f -- "$path") -> disk $d"
        [[ " $LIVE_SEEN " == *" $d "* ]] || LIVE_SEEN+="$d "
        [[ -n "$LIVE_DISK" ]] || LIVE_DISK="$d"
      else
        say "  $how: $path does not resolve to a block device"
      fi
    done
    LIVE_SEEN="${LIVE_SEEN% }"
    if [[ -z "$LIVE_DISK" ]]; then
      record "live-medium" WARN "archiso boot (${ARCHISO_PARAMS% }) but no method resolves the boot medium to a disk: it cannot be excluded from the install candidates"
    elif [[ "$LIVE_SEEN" == *" "* ]]; then
      record "live-medium" WARN "methods disagree on the boot medium: $LIVE_SEEN; excluding $LIVE_DISK only"
    else
      record "live-medium" PASS "$LIVE_DISK, excluded from the install candidates"
    fi
  fi
  DISKS="$(lsblk -d -b -n -o NAME,TYPE,SIZE,TRAN,MODEL 2>/dev/null || true)"
  say "  lsblk -d -b (NAME TYPE SIZE TRAN MODEL):"
  printf '%s\n' "$DISKS" | grep -v '^$' | quote || true
  fit=""
  nfit=0
  nusb=0
  ndisk=0
  while read -r name type size _; do
    [[ "$type" == disk && "$size" =~ ^[0-9]+$ ]] || continue
    ndisk=$(( ndisk + 1 ))
    gb=$(( size / 1024 / 1024 / 1024 ))
    # Read per disk: an empty TRAN column would shift the table's fields.
    tran="$(lsblk -n -d -o TRAN "/dev/$name" 2>/dev/null | head -n 1 || true)"
    tran="${tran//[[:space:]]/}"
    say "  $name: ${gb}G by install.sh's arithmetic, transport ${tran:-unknown}$( [[ "$name" == "$LIVE_DISK" ]] && echo ' (live boot medium)')"
    if [[ "$name" != "$LIVE_DISK" ]] && (( gb >= MIN_DISK_GB )); then
      fit+="$name(${gb}G,${tran:-unknown}) "
      nfit=$(( nfit + 1 ))
      [[ "$tran" == usb ]] && nusb=$(( nusb + 1 ))
    fi
  done < <(printf '%s\n' "$DISKS")
  if (( ndisk == 0 )); then
    record "disks" WARN "lsblk lists no disk"
  elif [[ -z "$fit" ]]; then
    record "disks" WARN "no disk other than the live medium reaches install.sh's ${MIN_DISK_GB}G minimum"
  elif (( nusb == nfit )); then
    record "disks" WARN "only USB-attached candidates for install.sh (>= ${MIN_DISK_GB}G): ${fit% }"
  else
    record "disks" PASS "candidates for install.sh (>= ${MIN_DISK_GB}G): ${fit% }"
  fi
else
  record "disks" SKIPPED "lsblk not installed"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log "Summary"

NFAIL=0
NWARN=0
for i in "${!R_NAME[@]}"; do
  say "$(printf '%-8s %-38s %s' "${R_STATUS[$i]}" "${R_NAME[$i]}" "${R_NOTE[$i]}")"
  case "${R_STATUS[$i]}" in
    FAIL) NFAIL=$(( NFAIL + 1 )) ;;
    WARN) NWARN=$(( NWARN + 1 )) ;;
  esac
done

if (( NFAIL > 0 )); then
  VERDICT="NO-GO"; RC=2
elif (( NWARN > 0 )); then
  VERDICT="GO-WITH-WARNINGS"; RC=1
else
  VERDICT="GO"; RC=0
fi

say "" "OVERALL: $VERDICT ($NFAIL FAIL, $NWARN WARN, ${#R_NAME[@]} checks) — report: $OUT"
exec 3>&-
OUT_OPEN=0
FINISHED=1
exit "$RC"
