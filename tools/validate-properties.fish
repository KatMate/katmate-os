#!/usr/bin/env fish
#
# validate-properties.fish — pred-deploy validator za properties.toml (ADR-015)
#
# Uporaba:
#   validate-properties.fish [--strict] <pot/do/properties.toml> [<pot2> ...]
#
# Zastavice:
#   --strict   opozorila štejejo kot napake (za CI / pre-commit hook)
#
# Izhodne kode:
#   0  vse datoteke veljavne (z --strict tudi brez opozoril)
#   1  vsaj ena napaka v shemi (z --strict tudi vsaj eno opozorilo)
#   2  napaka pri rabi / datoteka ne obstaja
#
# Validira proti shemi ADR-015 + semantičnim pravilom iz archetipov ADR-014.
# CID pasovi po ADR-022 (glej točko 4).
# Ne kliče tomlc99 — flat key=value TOML parsira interno (shema nima tabel/array).
# Dev-time orodje, ni del TCB.

set -g errors 0
set -g warns 0
set -g strict 0

# --- shema (ADR-015) ---
set -g req_keys      manifest network persistence identity disposable cid
set -g opt_keys      reset_on_shutdown
set -g enum_network  none via-netvm
set -g enum_persist  persistent ephemeral
set -g enum_manifest vault web
set -g bool_keys     identity disposable reset_on_shutdown

function err
    set_color red; echo "  NAPAKA: $argv"; set_color normal
    set -g errors (math $errors + 1)
end

function warn
    set_color yellow; echo "  opozorilo: $argv"; set_color normal
    set -g warns (math $warns + 1)
    test $strict -eq 1; and set -g errors (math $errors + 1)
end

function is_int
    string match -qr '^-?[0-9]+$' -- $argv[1]
end

function in_list
    set -l needle $argv[1]
    set -l hay $argv[2..-1]
    contains -- $needle $hay
end

# --- TOML parse: vrne v globalni assoc preko set -g kv_<key> ---
# Podpira:  key = value | key = "value" | key = true/false | komentarje (#) | prazne vrstice
function parse_toml
    set -l file $argv[1]
    set -g seen_keys
    set -l line_no 0

    for raw in (cat $file)
        set line_no (math $line_no + 1)
        # odstrani komentar (preprost: vse za prvim #, razen v narekovajih ni mogoče tu)
        set -l line (string replace -r '#.*$' '' -- $raw | string trim)
        test -z "$line"; and continue

        if not string match -qr '^[a-z_]+\s*=' -- $line
            err "vrstica $line_no: neveljavna sintaksa: '$raw'"
            continue
        end

        set -l key (string replace -r '\s*=.*$' '' -- $line | string trim)
        set -l val (string replace -r '^[^=]*=\s*' '' -- $line | string trim)
        # sleci dvojne narekovaje za string vrednosti
        set val (string replace -r '^"(.*)"$' '$1' -- $val)

        if contains -- $key $seen_keys
            err "podvojen ključ: '$key' (vrstica $line_no)"
        end
        set -g seen_keys $seen_keys $key
        set -g "kv_$key" $val
    end
end

function validate_file
    set -l file $argv[1]
    set -g file_errors_start $errors
    set_color --bold; echo "» $file"; set_color normal

    if not test -f $file
        err "datoteka ne obstaja"
        return
    end

    parse_toml $file

    # 1) obvezni ključi prisotni
    for k in $req_keys
        if not contains -- $k $seen_keys
            err "manjka obvezni ključ: '$k'"
        end
    end

    # 2) neznani ključi
    for k in $seen_keys
        if not in_list $k $req_keys $opt_keys
            err "neznan ključ: '$k'"
        end
    end

    # 3) tipi / enumi
    set -q kv_manifest; and begin
        in_list $kv_manifest $enum_manifest
        or err "manifest='$kv_manifest' ni v {$enum_manifest}"
    end

    set -q kv_network; and begin
        in_list $kv_network $enum_network
        or err "network='$kv_network' ni v {$enum_network}"
    end

    set -q kv_persistence; and begin
        in_list $kv_persistence $enum_persist
        or err "persistence='$kv_persistence' ni v {$enum_persist}"
    end

    for bk in $bool_keys
        set -q kv_$bk; and begin
            set -l v (eval echo \$kv_$bk)
            test "$v" = true -o "$v" = false
            or err "$bk='$v' mora biti true/false"
        end
    end

    # 4) cid: int 20-99 (fiksni AppVM), ali >=100 (dinamični pool), ali "auto".
    #    Pasovi po ADR-022: 0-2 rezervirani · 3-19 sysVM · 20-99 fiksni AppVM ·
    #    >=100 disposable. properties.toml opisuje IZKLJUČNO AppVM-e, zato je
    #    sysVM pas napaka z razlogom, ne tiho sprejeta vrednost.
    set -q kv_cid; and begin
        if test "$kv_cid" = auto
            # dovoljeno samo za disposable / dinamični pool
            test "$kv_disposable" = true
            or warn "cid=auto naj se rabi le pri disposable=true (dinamični pool ≥100)"
        else if is_int $kv_cid
            if test $kv_cid -ge 20 -a $kv_cid -le 99
                # fiksni AppVM pas — ok
            else if test $kv_cid -ge 100
                # dinamični pool — ok
            else if test $kv_cid -ge 3 -a $kv_cid -le 19
                err "cid=$kv_cid je v sysVM pasu 3–19 (ADR-022); properties.toml opisuje samo AppVM-e — sysVM-i se gradijo deklarativno (build/netvm.sh, ADR-021) in nimajo properties.toml"
            else
                err "cid=$kv_cid izven veljavnih pasov (fiksni AppVM 20–99 ali ≥100); 0–2 rezervirani (hypervisor/local/host)"
            end
        else
            err "cid='$kv_cid' ni int niti 'auto'"
        end
    end

    # 5) semantična pravila iz archetipov (ADR-014) — opozorila, ne napake
    if test "$kv_persistence" = ephemeral -a "$kv_reset_on_shutdown" = true
        warn "reset_on_shutdown=true je odvečen pri persistence=ephemeral (cel home se itak zavrže)"
    end
    if test "$kv_network" = none -a "$kv_manifest" = web
        warn "network=none z manifest=web: brez mreže je 'web' manifest verjetno napačen (vault-vzorec?)"
    end
    if test "$kv_disposable" = true -a "$kv_persistence" = persistent
        err "disposable=true zahteva persistence=ephemeral (instance-delta se uniči ob shutdownu)"
    end
    if test "$kv_disposable" = true -a "$kv_identity" = true
        warn "disposable=true z identity=true: nenavadno — disposable domene praviloma nimajo identitete"
    end

    if test $errors -eq $file_errors_start
        set_color green; echo "  ✓ veljavno"; set_color normal
    end

    # počisti kv_* za naslednjo datoteko
    for k in $seen_keys
        set -e kv_$k
    end
end

# --- main ---
set -l files
for a in $argv
    switch $a
        case --strict
            set -g strict 1
        case '--*'
            echo "neznana zastavica: $a" >&2
            exit 2
        case '*'
            set files $files $a
    end
end

if test (count $files) -eq 0
    echo "uporaba: validate-properties.fish [--strict] <properties.toml> [...]" >&2
    exit 2
end

for f in $files
    validate_file $f
end

echo
set -l mode_note ""
test $strict -eq 1; and set mode_note " (--strict: opozorila štejejo kot napake)"
echo "skupaj: $errors napak, $warns opozoril$mode_note"
test $errors -eq 0; and exit 0; or exit 1
