#!/usr/bin/env fish
#
# validate-properties.fish — pred-deploy validator za properties.toml
#
# Shema: ADR-015, kot jo revidirata ADR-030 (odstranjen 'network', dodani
# 'netvm' / 'provides_network' / 'class' / 'nic' / 'mem' / 'vcpus', CID pas kot
# funkcija razreda) in ADR-032 (obvezni ključi kot funkcija razreda, prepovedani
# ključi, razredno odvisne vrednosti 'manifest', naštevanje imenika).
# Semantična pravila iz archetipov ADR-014.
#
# Uporaba:
#   validate-properties.fish [--strict] [<imenik>|<datoteka> ...]
#
#   brez argumentov     validira /etc/katmate/vm/*.toml — privzeti T1 imenik
#                       (ADR-032 §1). Pravila ČEZ datoteke SE ovrednotijo.
#   <imenik>            validira <imenik>/*.toml. Pravila čez datoteke SE
#                       ovrednotijo.
#   <datoteka> ...      SAMO pravila znotraj datoteke. Validator izrecno javi,
#                       da pravila čez datoteke niso bila ovrednotena nad
#                       zajamčeno popolno množico.
#
# Zakaj imenik (ADR-032 §4): pravilo "dve VM ne smeta zahtevati iste 'nic'
# oznake" (ADR-030 §4, gate G5) je po naravi čez datoteke. Ovrednotiti ga je
# mogoče šele ob jamstvu, da smo videli VSE datoteke — imenik JE to jamstvo.
# Klic nad posameznimi datotekami tega jamstva nima, zato pravila ne sme tiho
# izpustiti: tiho preskočeno pravilo je videti kot uspešna validacija.
#
# Zastavice:
#   --strict   opozorila štejejo kot napake (za CI / pre-commit hook)
#
# Izhodne kode:
#   0  vse veljavno (z --strict tudi brez opozoril)
#   1  vsaj ena napaka v shemi (z --strict tudi vsaj eno opozorilo)
#   2  napaka pri rabi / pot ne obstaja / ni bilo kaj validirati
#
# T1 NI nikoli v repozitoriju (ADR-032 §1): commitana properties.toml je delo
# projekta in po tierski meji zato T3/T4, ne T1. To orodje validira datoteke na
# stroju, ne v drevesu.
#
# Jezik: datoteka je slovenska (komentarji in diagnostika), enako kot
# bin/katmate-cid. Projektno pravilo "en_US za dokumentacijo" velja za docs/ in
# .md; orodja v fish so slovenska. Nedoslednost je ZAVEDNA — enotna jezikovna
# odločitev za tools/ + bin/ je svoja sprememba in svoj commit, ne stranski
# učinek te.
#
# Ne kliče tomlc99 — flat key=value TOML parsira interno (shema nima tabel).
# Dev-time orodje, ni del TCB.

set -g errors 0
set -g warns 0
set -g strict 0

# Privzeti T1 imenik (ADR-032 §1).
set -g T1_DIR_DEFAULT /etc/katmate/vm

# --- shema: obvezni ključi so funkcija razreda (ADR-032 §3) ------------------
# Ključ brez pomena za razred je PREPOVEDAN, ne prezrt. Tiho zavržena vrstica
# je natanko tisti "tiho napačni objekt", ki ga ta projekt vedno znova najde
# (zastarel BDF, ki preda napačno napravo; 'routable' ob 'offline'). Ključ, ki
# ga uporabnik lahko nastavi in ne naredi ničesar, je slabši od ključa, ki ne
# obstaja.
set -g keys_common_req  class cid manifest mem vcpus
set -g keys_sys_req     nic provides_network
set -g keys_sys_forbid  netvm persistence identity disposable reset_on_shutdown
set -g keys_app_req     netvm persistence identity disposable
set -g keys_app_opt     reset_on_shutdown
set -g keys_app_forbid  nic provides_network

# Vsi ključi sheme — karkoli izven tega je neznan ključ.
set -g keys_all class cid manifest mem vcpus nic provides_network netvm \
                persistence identity disposable reset_on_shutdown

set -g enum_class    app sys
set -g enum_persist  persistent ephemeral
# 'manifest' je razredno odvisen v VREDNOSTIH, ne razširjen skupni enum
# (ADR-032 §3): skupni enum bi naredil manifest=netvm veljaven na AppVM-u —
# veljavna vrednost, ki zgradi napačno sliko.
set -g enum_man_sys  netvm
set -g enum_man_app  vault web office
set -g bool_keys     identity disposable reset_on_shutdown provides_network

# --- akumulatorji ČEZ datoteke (ADR-032 §4) ----------------------------------
# Preživeti morajo konec validate_file, ki briše vse kv_*.
set -g seen_nic_label
set -g seen_nic_file
set -g crossfile_complete 0   # 1 = množica datotek je zajamčeno popolna

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

# --- TOML parse: vrne v globalne spremenljivke kv_<key> ----------------------
# Podpira:  key = value | key = "value" | key = true/false | komentarje (#) |
#           prazne vrstice. Prazen niz ("") je VELJAVNA vrednost in se razlikuje
#           od odsotnega ključa — 'netvm = ""' je deklarirana offline domena,
#           odsoten 'netvm' je neizrečena predpostavka (ADR-032 §3).
function parse_toml
    set -l file $argv[1]
    set -g seen_keys
    set -l line_no 0

    for raw in (cat $file)
        set line_no (math $line_no + 1)
        set -l line (string replace -r '#.*$' '' -- $raw | string trim)
        test -z "$line"; and continue

        if not string match -qr '^[a-z_]+\s*=' -- $line
            err "vrstica $line_no: neveljavna sintaksa: '$raw'"
            continue
        end

        set -l key (string replace -r '\s*=.*$' '' -- $line | string trim)
        set -l val (string replace -r '^[^=]*=\s*' '' -- $line | string trim)
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

    # --- 0) razred: vse ostalo je odvisno od njega ---------------------------
    set -l cls ""
    if set -q kv_class
        if in_list $kv_class $enum_class
            set cls $kv_class
        else
            err "class='$kv_class' ni v {$enum_class}"
        end
    else
        err "manjka obvezni ključ: 'class' — brez njega razredno odvisnih pravil (obvezni/prepovedani ključi, 'manifest', CID pas) ni mogoče ovrednotiti"
    end

    # --- 1) odstranjeni ključi dobijo svoje sporočilo, ne 'neznan ključ' -----
    if contains -- network $seen_keys
        err "ključ 'network' je ODSTRANJEN (ADR-030 §4; ADR-015 rev. 2026-08-06). Enum none|via-netvm ne more povedati KATERI netVM, dostop AppVM-a pa JE to, na kateri netVM je priklopljen (ADR-022). Nadomeščata ga 'netvm' (ime netVM-a ali prazno) in 'provides_network'."
    end

    # --- 2) neznani ključi ---------------------------------------------------
    for k in $seen_keys
        test "$k" = network; and continue      # že obravnavan zgoraj
        if not in_list $k $keys_all
            err "neznan ključ: '$k'"
        end
    end

    # --- 3) razredno odvisni obvezni / prepovedani ključi (ADR-032 §3) -------
    set -l req
    set -l forbid
    set -l req_label "za class=$cls"
    switch "$cls"
        case sys
            set req $keys_common_req $keys_sys_req
            set forbid $keys_sys_forbid
        case app
            set req $keys_common_req $keys_app_req
            set forbid $keys_app_forbid
        case '*'
            # Razred ni znan. 'class' sam je že javljen zgoraj s svojim
            # razlogom — ne podvajaj ga tu. Razredno odvisnih množic ni mogoče
            # ovrednotiti; povej to, namesto da bi tišina izgledala kot uspeh.
            set req (string match -v class $keys_common_req)
            set req_label "(skupni; razredno odvisni ključi niso bili preverjeni)"
    end

    # sys-proxy PRED splošnim preverjanjem manjkajočih ključev, da razred dobi
    # svojo razlago namesto golega "manjka nic".
    set -l skip_req
    if test "$cls" = sys; and not set -q kv_nic
        err "class=sys brez 'nic' se razreši v profil sys-proxy (ADR-030 §2): netVM brez fizične kartice je microVM. Ta profil je IMENOVAN, ni pa dostavljen — izrecna napaka, nikoli privzetek. Dodaj oznako 'nic' (npr. \"uplink0\") ali počakaj, da sys-proxy obstaja."
        set skip_req nic
    end

    for k in $req
        contains -- $k $skip_req; and continue
        if not contains -- $k $seen_keys
            err "manjka obvezni ključ $req_label: '$k'"
        end
    end

    for k in $forbid
        if contains -- $k $seen_keys
            err "prepovedan ključ pri class=$cls: '$k' (ADR-032 §3) — ključ brez pomena za razred je prepovedan, ne prezrt"
        end
    end

    # --- 4) tipi in enumi ----------------------------------------------------
    set -q kv_manifest; and begin
        switch "$cls"
            case sys
                in_list $kv_manifest $enum_man_sys
                or err "manifest='$kv_manifest' pri class=sys ni v {$enum_man_sys}"
            case app
                in_list $kv_manifest $enum_man_app
                or err "manifest='$kv_manifest' pri class=app ni v {$enum_man_app}"
        end
    end

    set -q kv_persistence; and begin
        in_list $kv_persistence $enum_persist
        or err "persistence='$kv_persistence' ni v {$enum_persist}"
    end

    for bk in $bool_keys
        set -l name kv_$bk
        set -q $name; and begin
            set -l v $$name
            test "$v" = true -o "$v" = false
            or err "$bk='$v' mora biti true/false"
        end
    end

    set -q kv_mem; and begin
        string match -qr '^[0-9]+[MG]$' -- $kv_mem
        or err "mem='$kv_mem' mora biti število s pripono M ali G (npr. 1G, 512M). Format ni predpisan v nobenem ADR-ju; zožen je tu, da 'mem' ni nevalidiran prost niz v datoteki, ki jo bere komponenta TCB."
    end

    set -q kv_vcpus; and begin
        string match -qr '^[1-9][0-9]*$' -- $kv_vcpus
        or err "vcpus='$kv_vcpus' mora biti pozitiven int"
    end

    set -q kv_nic; and begin
        if test -z "$kv_nic"
            err "'nic' je prazen — oznaka mora biti neprazna (ADR-030 §5)"
        else if string match -qr ':' -- $kv_nic
            err "nic='$kv_nic' je videti kot PCI naslov. 'nic' je OZNAKA, nikoli BDF (ADR-030 §5): BDF dodeli firmware ob naštevanju in se premakne ob presedanju kartice ali preštevilčenju vodila. Posledica zastarelega zapisa ni VM, ki se ne zažene, ampak DRUGA naprava, tiho predana najbolj izpostavljeni VM v sistemu. Razrešitev je jedrna in vezana na zagon: /run/katmate/nics/<oznaka>."
        else if not string match -qr '^[a-z][a-z0-9_-]*$' -- $kv_nic
            err "nic='$kv_nic': oznaka naj bo [a-z][a-z0-9_-]*"
        end
    end

    set -q kv_netvm; and begin
        if test -n "$kv_netvm"
            string match -qr '^[a-z][a-z0-9_]*$' -- $kv_netvm
            or err "netvm='$kv_netvm': ime VM naj bo [a-z][a-z0-9_]*"
        end
    end

    # --- 5) CID pas kot funkcija razreda -------------------------------------
    # Pasovi (ADR-022, avtoritativno v docs/DEV-ENV.md): 0–2 rezervirani ·
    # 3–19 sysVM · 20–99 fiksni AppVM · ≥100 dinamični disposable pool.
    # class=app obdrži VSE TRI oblike ADR-015: 20–99, "auto" in ≥100. Branje
    # "app = samo 20–99" izbriše disposable arhetip ob parsanju — četrti
    # arhetip ADR-014 je definiran z cid="auto" (ADR-015 rev. 2026-08-09).
    set -q kv_cid; and begin
        switch "$cls"
            case sys
                if is_int $kv_cid
                    if test $kv_cid -ge 3 -a $kv_cid -le 19
                        # sysVM pas — ok
                    else
                        err "cid=$kv_cid: class=sys zahteva sysVM pas 3–19 (ADR-030 §4, ADR-022). 0–2 rezervirani (hypervisor/local/host), 20–99 fiksni AppVM, ≥100 disposable pool."
                    end
                else
                    err "cid='$kv_cid': class=sys zahteva fiksen int v 3–19. 'auto' je za disposable AppVM-e (ADR-017) in za sysVM ni veljaven — sysVM CID je del identitete domene."
                end
            case app
                if test "$kv_cid" = auto
                    test "$kv_disposable" = true
                    or warn "cid=auto naj se rabi le pri disposable=true (dinamični pool ≥100, ADR-017)"
                else if is_int $kv_cid
                    if test $kv_cid -ge 20 -a $kv_cid -le 99
                        # fiksni AppVM pas — ok
                    else if test $kv_cid -ge 100
                        # dinamični pool: ročno/debug pinjanje (ADR-015) — ok
                    else if test $kv_cid -ge 3 -a $kv_cid -le 19
                        err "cid=$kv_cid je v sysVM pasu 3–19 (ADR-022), razred pa je app. sysVM-i nosijo class=sys."
                    else
                        err "cid=$kv_cid izven veljavnih pasov za class=app (20–99 fiksni, ≥100 dinamični, ali \"auto\"); 0–2 rezervirani"
                    end
                else
                    err "cid='$kv_cid' ni int niti 'auto'"
                end
        end
    end

    # --- 6) semantična pravila iz archetipov (ADR-014) -----------------------
    if test "$kv_persistence" = ephemeral -a "$kv_reset_on_shutdown" = true
        warn "reset_on_shutdown=true je odvečen pri persistence=ephemeral (cel home se itak zavrže)"
    end
    if test "$kv_disposable" = true -a "$kv_persistence" = persistent
        err "disposable=true zahteva persistence=ephemeral (instance-delta se uniči ob shutdownu)"
    end
    if test "$kv_disposable" = true -a "$kv_identity" = true
        warn "disposable=true z identity=true: nenavadno — disposable domene praviloma nimajo identitete"
    end
    # ADR-015 pravilo "network=none z manifest=web", prepisano na novo polje:
    # offline domena je zdaj prazen 'netvm' (ADR-030 §4).
    if test "$cls" = app; and set -q kv_netvm; and test -z "$kv_netvm"
        if test "$kv_manifest" = web
            warn "netvm je prazen (deklarirana offline domena) z manifest=web: brez mreže je 'web' manifest verjetno napačen (vault-vzorec?)"
        end
    end

    # --- 7) akumulacija za pravilo čez datoteke ------------------------------
    # Nic je dodeljiv NAJVEČ eni VM (ADR-022, Nic.assigned_to). Dve VM na isti
    # kartici ni konfiguracija, ampak vfio konflikt.
    if set -q kv_nic; and test -n "$kv_nic"
        if contains -- $kv_nic $seen_nic_label
            set -l idx (contains -i -- $kv_nic $seen_nic_label)
            err "podvojena 'nic' oznaka '$kv_nic': isto oznako zahteva že $seen_nic_file[$idx] (ADR-022: Nic je dodeljiv največ eni VM)"
        else
            set -g seen_nic_label $seen_nic_label $kv_nic
            set -g seen_nic_file $seen_nic_file $file
        end
    end

    if test $errors -eq $file_errors_start
        set_color green; echo "  ✓ veljavno"; set_color normal
    end

    # počisti kv_* za naslednjo datoteko (akumulatorji zgoraj NISO kv_*)
    for k in $seen_keys
        set -e kv_$k
    end
end

# --- main --------------------------------------------------------------------
set -l paths
set -g had_file_arg 0

for a in $argv
    switch $a
        case --strict
            set -g strict 1
        case '--*'
            echo "neznana zastavica: $a" >&2
            exit 2
        case '*'
            set paths $paths $a
    end
end

# Brez poti: privzeti T1 imenik (ADR-032 §1).
if test (count $paths) -eq 0
    set paths $T1_DIR_DEFAULT
end

set -l files
for p in $paths
    if test -d $p
        for f in (find $p -maxdepth 1 -type f -name '*.toml' | sort)
            set files $files $f
        end
    else if test -f $p
        set files $files $p
        set -g had_file_arg 1
    else
        echo "pot ne obstaja: $p" >&2
        exit 2
    end
end

if test (count $files) -eq 0
    echo "nič ni bilo validirano: v "(string join ', ' $paths)" ni nobene *.toml" >&2
    echo "(prazen izpis in izhod 0 bi bil videti kot uspeh — zato izhod 2)" >&2
    exit 2
end

# Pravila čez datoteke so ovrednotena le nad zajamčeno popolno množico, torej
# kadar so bile vse poti imeniki (ADR-032 §4).
if test $had_file_arg -eq 0
    set -g crossfile_complete 1
end

for f in $files
    validate_file $f
end

echo
if test $crossfile_complete -eq 1
    echo "pravila čez datoteke: ovrednotena nad "(count $files)" datotekami v "(string join ', ' $paths)
else
    set_color yellow
    echo "pravila čez datoteke: NISO ovrednotena nad zajamčeno popolno množico."
    echo "  Klicano nad posameznimi datotekami, zato validator ne more vedeti, da"
    echo "  je videl vse VM-e. Podvojena 'nic' oznaka MED PODANIMI datotekami je"
    echo "  bila preverjena; oznaka, ki jo zahteva neka nepodana datoteka, ni."
    echo "  Za polno preverjanje poženi nad imenikom (privzeto $T1_DIR_DEFAULT)."
    set_color normal
end

set -l mode_note ""
test $strict -eq 1; and set mode_note " (--strict: opozorila štejejo kot napake)"
echo "skupaj: $errors napak, $warns opozoril$mode_note"
test $errors -eq 0; and exit 0; or exit 1
