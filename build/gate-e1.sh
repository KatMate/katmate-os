#!/usr/bin/env bash
# gate-e1.sh -- ADR-030 gate E1, run on MINIS as root.
#
# Question: is EnvironmentFile= read late enough to see a file that
# ExecStartPre= created in the SAME unit?
#
#   A  generator as ExecStartPre=+ in the VM unit          <- cheaper, preferred
#   B  separate katmate-vm-env@.service, Requires=/After=  <- fallback
#
# Empirics before commitment (ADR-024 method). Assumed-precondition failure is
# what killed ADR-021's shutdown model; no unit template gets written until
# this prints a verdict.
#
# Throwaway. Removes everything it creates.

set -u

# Root check FIRST -- before any trap. (v1 installed the EXIT trap above this
# line, so a non-root run still fired cleanup and triggered polkit prompts
# without measuring anything.)
if [ "$(id -u)" -ne 0 ]; then
    echo "run as root:  sudo $0" >&2
    exit 1
fi

UA=/run/systemd/system/km-e1a.service
UB=/run/systemd/system/km-e1b.service
UBGEN=/run/systemd/system/km-e1b-env.service
ENVA=/run/km-e1a.env
ENVB=/run/km-e1b.env

cleanup() {
    systemctl --no-ask-password stop \
        km-e1a.service km-e1b.service km-e1b-env.service 2>/dev/null
    rm -f "$UA" "$UB" "$UBGEN" "$ENVA" "$ENVB"
    systemctl --no-ask-password daemon-reload
}
trap cleanup EXIT

rm -f "$ENVA" "$ENVB"

# ---- A: generator inside the same unit ------------------------------------
cat > "$UA" <<'EOF'
[Unit]
Description=ADR-030 gate E1 variant A
[Service]
Type=oneshot
EnvironmentFile=-/run/km-e1a.env
ExecStartPre=/bin/sh -c 'printf "KM_CID=42\n" > /run/km-e1a.env'
ExecStart=/bin/echo A_RESULT=[${KM_CID}]
EOF

# ---- B: generator in a preceding unit -------------------------------------
cat > "$UBGEN" <<'EOF'
[Unit]
Description=ADR-030 gate E1 variant B generator
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'printf "KM_CID=42\n" > /run/km-e1b.env'
EOF

cat > "$UB" <<'EOF'
[Unit]
Description=ADR-030 gate E1 variant B
Requires=km-e1b-env.service
After=km-e1b-env.service
[Service]
Type=oneshot
EnvironmentFile=-/run/km-e1b.env
ExecStart=/bin/echo B_RESULT=[${KM_CID}]
EOF

systemctl --no-ask-password daemon-reload

CURSOR=$(journalctl --show-cursor -n0 -o cat 2>/dev/null | sed -n 's/^-- cursor: //p')

systemctl --no-ask-password start km-e1a.service 2>&1 | sed 's/^/  A start: /'
systemctl --no-ask-password start km-e1b.service 2>&1 | sed 's/^/  B start: /'
sleep 1

LOG=$(journalctl --after-cursor="$CURSOR" -o cat --no-pager 2>/dev/null)

A=$(printf '%s\n' "$LOG" | sed -n 's/.*A_RESULT=\[\(.*\)\].*/\1/p' | head -1)
B=$(printf '%s\n' "$LOG" | sed -n 's/.*B_RESULT=\[\(.*\)\].*/\1/p' | head -1)

echo
echo "=============== ADR-030 gate E1 ==============="
printf 'A (ExecStartPre in same unit) : %s\n' "${A:-<no output>}"
printf 'B (separate generator unit)   : %s\n' "${B:-<no output>}"
echo

if [ "${A:-}" = "42" ]; then
    echo "VERDICT: A PASSES -- EnvironmentFile= is read after ExecStartPre=."
    echo "         Use A. One unit per VM, generator as ExecStartPre=+."
elif [ "${B:-}" = "42" ]; then
    echo "VERDICT: A FAILS, B PASSES -- as predicted in ADR-030 section 8."
    echo "         Use B. katmate-vm-env@.service, Requires= + After=."
    echo "         Note: this adds a unit per VM. Record it in ADR-030."
else
    echo "VERDICT: BOTH FAIL. Do not proceed. Neither candidate delivers the"
    echo "         scalar; the /run projection needs a different mechanism"
    echo "         (systemd generator, or drop the env file and template the"
    echo "         two scalars in at deploy time). Reopen ADR-030 section 8."
fi
echo "==============================================="
echo
echo "Also record, verbatim, for the ADR gate table:"
echo "  systemctl show km-e1a.service -p Result -p ExecMainStatus"
systemctl show km-e1a.service -p Result -p ExecMainStatus 2>/dev/null | sed 's/^/  /'S
