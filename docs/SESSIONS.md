# Session Archive — Katmate OS

> Historical session log, split out of `state.md` on 2026-07-14 (it had grown to
> 1090 lines / 68 KB, against its own "stays short" mandate). `state.md` keeps the
> header, the current focus, the **two most recent sessions**, and the living
> sections (live state, open problems, next steps, invariants). Everything older
> lands here, verbatim, newest first.
>
> **Entries are append-only and are never rewritten.** They are records of what
> was true on the day they were written, not statements about the current target.
> Two *insertions* have been made, both repairs of the ordering invariant rather
> than edits to any entry: on 2026-07-26 the 07-14 and 07-13 entries, and on
> 2026-08-06 the 07-23, 07-21 and 07-20 entries plus the first of the two
> 2026-08-02 sessions. The *second* 2026-08-02 session (ADR-029) arrived here
> normally on 2026-08-06 as `state.md` rotated it out, and therefore sits above
> the first — newest first, as everywhere in this file. In each case the material had been stranded in `state.md`
> while later sessions went straight to this file. The 2026-08-06 insertion
> carried two repairs inside a moved block, both marked where they occur: a
> dangling "see debt #14 below" cross-reference now pointing at `../state.md`,
> and the removal of the leading `**YYYY-MM-DD ...**` date stamps that only made
> sense in `state.md`'s flat preamble. The 2026-08-02 entry is explicitly
> reconstructed and says so in its own header.
>
> **Reading note — CIDs.** [ADR-022](DECISIONS.md#adr-022) was written in the
> 2026-07-14 session. Entries dated **2026-07-13 and earlier** use the old
> single-sysVM map (`3` = netVM, `4` = personalVM, `5` = app_web). The current
> map is `2` host / `3–19` sysVM / `20–99` fixed AppVM / `≥100` disposable, under
> which **personalVM becomes 20 and app_web becomes 21** (netVM stays 3). Old
> numbers are left as written — they are what actually ran at the time.
> `state.md` carries the authoritative map.
>
> **Reading note — build-order ordinals.** `ROADMAP.md`'s build order is
> referenced by number from several entries. [ADR-030](DECISIONS.md#adr-030)
> (2026-08-06) inserted a step and renumbered the tail: old 3/4/5 became
> **4/5/6**, and a new step 3 (VM description as data → launch daemon) took
> their place. Entries written **before 2026-08-06** use the old numbers and
> are left as written. `ROADMAP.md` carries the authoritative list.

---

## This session (2026-08-02, second of two) — ADR-029: systemd owns the VMM process; four constraints re-examined and gone

Architecture session (thinking-on) plus four live gates on MINIS. Scope was
deliberately one question and nothing else: **who is the parent of the QEMU
process.** Everything downstream — privilege split, allocation, netns — was
treated as consequence, not as co-equal design surface.

### Decided

- **ADR-029 — the launch daemon orders units; systemd owns the VMM process.**
  The daemon never `fork`s or `exec`s a VMM. Each VM is a systemd unit; PID 1
  is the parent; the unit name and its cgroup are the durable identity. The
  daemon retains everything the five prior ADRs assign it (graph, CID
  allocation, NETCFG ordering and re-issue, CID→name, dependent-VM interlock)
  and may die at any moment without any running VM noticing.

### The four constraints, re-examined

The question was reached by counting 4:1 in favour of daemon-as-parent. The
count was not a weighing. Three of the four dissolve against the ADRs they were
drawn from; the fourth was a question about a device that does not exist.

| Constraint | Outcome |
|---|---|
| pid↔CID (ADR-026) | dissolves — `vsock_diag` resolves pid→CID in the kernel; the daemon's part is CID→name, persisted state |
| `_is_alive` (ADR-017) | dissolves — ADR-017 already offers "active vsock endpoints for those CIDs". A live control endpoint **is** liveness here |
| `child_ns_mode` write-once (C6) | measured, leaves the column — the write is in a *parent* namespace, children inherit at creation; produces a **named** namespace, not a descriptor |
| TAP as `fd=` (C2) | dissolved by inspection — `app_web.con` carries **no network device at all** |

### The argument that decided it, on neither list

Daemon-as-parent makes the identity of a running VM a process relationship. On
daemon death or update the QEMU processes survive (reparented) — that is not
the problem. The problem is that the new daemon is not their parent: `waitpid`
is gone, and reconstruction through a persisted pid + `pidfd_open` reintroduces
**pid reuse**, the exact race ADR-017's monotonic counter and full-cycle
`flock` exist to eliminate. Under C6 it is worse: identity is **(netns, CID)**
(ADR-028), and an anonymous namespace held as a descriptor from
`/proc/<child>/ns/net` dies with the daemon — the half that cannot be recovered
by name. This project ships security updates; a model where
`systemctl restart katmated` requires stopping every VM is a design defect.

systemd is PID 1. It does not restart.

### Gates passed (live, MINIS)

| # | Observation | Result |
|---|---|---|
| G0 | `/proc/sys/net/vsock/child_ns_mode` `rw`, `ns_mode` `r--r--r--`, both `global` at boot | PASSED |
| G1a | first write `rc=0`; second differing write → `EBUSY`. Write-once measured, not cited | PASSED |
| G1b | child of `local` parent reads `local`; **control:** child of `init_netns` reads `global` | PASSED |
| G1c | `nsenter --net=/run/netns/katmate-root` + `unshare --net` → child reads `local` — the daemon's actual sequence | PASSED |
| G3 | `SIGKILL` to `MainPID` under `User=nobody` → `STOPPOST result=signal status=KILL code=killed uid=0`; unit `Result=signal` | PASSED |
| G2 | tap is netns-scoped (`Device "tap-g2" does not exist`; control: only `lo`) | PASSED |
| G2b | `ip link set tap-g2 netns g2-test` succeeds — migration is an alternative to fd inheritance | PASSED |

`init_netns` `child_ns_mode` remains `global` — the host-wide write-once budget
was never spent.

### Measured, predicted by no ADR

- **`ip netns add` is not nestable.** Under `ip netns exec` the bind mount is
  made in a child mount namespace that immediately exits. What remains is a
  `----------` placeholder; `setns` → `EINVAL`, and `ip netns list` still lists
  it. Permission bits distinguish: live namespace `-r--r--r--` (nsfs inode under
  the bind mount) vs placeholder `----------`. **Consequence: namespace creation
  is daemon code** — `setns` → `unshare` → `mount --bind`, one process, alive
  until the bind mount lands.
- **`/proc` must be remounted to read per-netns sysctls.** After
  `unshare --net`, `/proc/sys/net` shows the *old* namespace until `/proc` is
  remounted. The failure mode is a **false negative** — a plausible wrong value,
  silently returned. Same class that killed ADR-021's shutdown model: a
  mechanism quietly consulting the wrong object. Applies to the daemon, not only
  to tests.
- **`ns_mode` is `r--r--r--`.** After a namespace exists there is no lever.
  Whoever creates it has fixed its mode permanently.
- **Tap migration clears `UP`, preserves MAC.** `ip link set … up` must run
  *after* migration, inside the target namespace. The surviving MAC matters to
  ADR-025's locally-administered-address check.

### Correction to an earlier internal statement

Mid-session it was asserted that AppVM links "probably need veth rather than tap
because AppVMs route through netVM, not the host". The reasoning was right and
the premise was wrong: it generalised from `net-sys.con`'s host-side `tap-int0`,
which sits on the host only because until now there was no other namespace to
put it in. Inspection of `app_web.con` settles it differently — **the AppVM
launcher has no network device of any kind.** No `-netdev`, no
`virtio-net-device`, no tap. AppVM networking does not exist yet, which is
consistent with NETCFG having been live-gated against netVM itself and never
through a live AppVM.

C2 is therefore recorded as **neither passed nor failed**: it was not a
constraint on parenthood. It returns as a link-topology question when the AppVM
acquires an endpoint, to be settled by measurement then.

### Refinement to ADR-028

ADR-028 records `child_ns_mode` as "a decision taken once at **daemon start**".
G1 refines: the write is in a *parent* namespace, children inherit at creation.
It is a one-time preparation on a dedicated `katmate-root` namespace, not a
daemon-start decision — so `init_netns` is never written and foreign namespaces
on the host keep `global`. ADR-028's substance stands and is now measured rather
than cited.

### Not measured, recorded as not measured

- **OOM-kill.** G3 used `SIGKILL`; systemd distinguishes `result=oom-kill`
  separately. `ExecStopPost=+` behaving identically is likely and unverified.
- **Tap ownership across migration** — whether `user <uid>` survives
  `ip link set … netns`. Blocks nothing until an AppVM has an endpoint.
- **AppVM link topology** — opened, not settled, by the C2 finding.
- **Unit shape** — `StartTransientUnit` vs a `katmate-vm@.service` template.
  Deliberately deferred; neither affects any ADR-029 decision.

### Housekeeping

`/etc/systemd/system/vhost-vsock-load.service:5` uses `ConditionKernelModule`,
which systemd does not know; the line is silently ignored (visible in `dmesg`).
The unit works — the condition does not exist. Drift, not a defect.

### Docs debt raised this session — CLOSED 2026-08-06

The earlier 2026-08-02 session (CID renumbering `app_web` 5 → 21, personalVM
deletion) is threaded through this file's live sections but **has no session
heading**. It is therefore invisible as a session while its consequences are
visible as state. Give it its own heading, or fold it in here — not left as is.

> **Closed 2026-08-06.** Written up as its own entry —
> *2026-08-02, first of two* — at the top of [docs/SESSIONS.md](docs/SESSIONS.md),
> explicitly marked as reconstructed rather than same-day.

---

## This session (2026-08-02, first of two) — CID renumbering applied; personalVM artefacts removed

> **Reconstructed 2026-08-06; not written on the day.** This session's
> consequences were threaded into `../state.md`'s living sections while the
> session itself never received a heading — it was therefore invisible as a
> session while fully visible as state. Flagged as docs debt in the second
> 2026-08-02 entry and closed here. The entry below is assembled from those
> sections and from `../ROADMAP.md`; it is not a same-day record and asserts
> nothing that was not already written down elsewhere.

### CID renumbering to the ADR-022 map — done

The renumbering carried from the 2026-07-14 session was applied:

- `app_web` **5 → 21** in `app_web.con` (line 25, with the band named in the
  comment).
- The normative band **4–8 → 20–99** in [ADR-015](DECISIONS.md#adr-015),
  [ADR-017](DECISIONS.md#adr-017) and `tools/validate-properties.fish`.
- `properties.toml` restricted to the **AppVM class**: a CID in 3–19 is a hard
  error, not a warning. sysVMs are not described by that schema.

**personalVM was not renumbered — it was deleted instead** (below). `20` is
therefore simply the lowest free fixed AppVM CID, reserved for nothing in
particular. netVM (3) is unchanged by the new map.

**The agents needed no change.** They know only host CID 2 and the peer CID
returned by `accept`; the map is host-side throughout. No instantiated
`properties.toml` existed at the time, so no instance file was touched.

### personalVM artefacts removed

`vm_personal_home` (40 G thin) deleted. The launcher and the qcow2 overlay had
already gone in the 2026-07-25 housekeeping pass, so this removed the last
pre-foundation artefact on MINIS.

Migration was considered and rejected: the old personalVM ran the
pre-foundation systemd-user / linear-root model, which nothing will boot again.
Migrating would have meant renumbering it and then rebuilding an artefact that
the v0.3 AppVM work regenerates from foundation + the `web` manifest anyway.

**The artefact is gone; the `personal` archetype
([ADR-014](DECISIONS.md#adr-014)) is not.** It returns as one of the default
AppVMs, with a CID allocated from 20–99 at that point.

---

## This session (2026-07-28) — C-gate defined and half-passed; vsock placement settled; indicator carriers closed

Architecture session (thinking-on) plus three live gates. Origin: a review of
alternative VMMs that turned into a correction of how this project applies
*absent, not disabled*.

### Decided

- **ADR-026 — domain indicator carriers.** Accepted, gate closed. Identity
  resolves in two host-side steps: the compositor gives a window `pid`, and
  that pid's AF_VSOCK connection gives the peer CID. `app_id` and window title
  are guest-controlled and excluded from the identity path at every level.
- **ADR-027 — VMM containment is a precondition, not an alternative.**
  Introduces three axes of capability control and scopes *absent, not disabled*
  to axis 1 (existence). Adds principle 10, *relocation is not removal*.
  Defines the C-gate; no axis-2 work is implemented until it passes.
- **ADR-028 — virtio-vsock transport placement.** v1 stays on `vhost_vsock`.
  Hybrid placement rejected with reasons recorded so it is not re-proposed.
  `vhost-user-vsock` with `--forward-cid` identified as the only viable
  alternative, gated behind the C-gate, with H1–H3 open.

### Gates passed (live, MINIS)

- **C4 — tightened seccomp filter.** `resourcecontrol=deny` added to both
  launchers. `app_web` (CID 5): `Seccomp: 2`, one filter, `dmesg` clean,
  `ping 5 → 0x00`. netVM (CID 3): `Seccomp: 2`, one filter, `ping 3 → 0x00`,
  and `vfio-pci 0000:01:00.0: resetting / reset done` twice — the `FLReset-`
  workaround is unaffected. The hypothesis that `resourcecontrol=deny` would
  collide with `-object iothread` is **refuted empirically on both machine
  types**, not reasoned about.
- **C5b — 9p removed from netVM** (SECURITY-MODEL gap #10 closed). `-fsdev` and
  `-device virtio-9p-pci` deleted from `net-sys.con`; `/proc/<pid>/cmdline` of
  the running VMM contains neither. Proof taken host-side deliberately — the
  device is absent from instantiation, which is an axis-1 proof and stronger
  than an in-guest `mount` check. See the operational note added to open
  problem #12.
- **ADR-026 gate.** `swaymsg -t get_tree` on a rendered `nautilus` window
  reported `app_id: org.gnome.Nautilus`, `name: Home`, and a `pid`. That pid
  resolved to `waypipe -s 1024 --vsock --threads 0 -c lz4 client-conn`, and
  `ss -f vsock -p` on it reported `v_str ESTAB 2:1024 ↔ 5:287463193` — peer
  CID 5. The gate as written asked only whether a pid resolves to the waypipe
  client; it resolved further, through the client to the CID. **Also
  verified:** the query needs no privilege — an unprivileged caller receives
  the same peer CID as root, so the resolver is not forced into a privileged
  process.

### Still open on ADR-026

Pid stability with **two concurrent windows from one domain** (a second
`client-conn`), and across close/reopen, is unverified. If per-connection pids
differ, the resolver must handle a set rather than a single value. A host
reboot between observations says nothing about this — a new boot means new pids
by definition.

### Corrections to earlier internal statements

Recorded so the error mode stays visible, in the spirit of the ADR-025 gate
correction.

1. **"`-sandbox` is not enabled / unused."** Wrong.
   `-sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny` was already
   present in **both** launchers; only `resourcecontrol=deny` was missing. The
   claim was made without reading the launchers.
2. **"The VMM runs as root."** Over-generalised. True of `net-sys.con` only.
   `app_web.con` uses `sudo` solely for `lvchange`; QEMU runs as the invoking
   user, so C1 is already satisfied for AppVMs. The correction is in the
   project's favour and would have been lost.
3. **"The hybrid vsock model is an instance of absent-not-disabled."** Wrong,
   and the correction is the substance of ADR-027. It is relocation of
   privilege; the principle applies to existence, not placement.
4. **"`share=on` may be avoidable on the `--forward-cid` path."** Void — shared
   guest memory is required by vhost-user generally, in both backend modes.
   **What this does not settle:** `app_web.con` uses `share=on` on a hugetlbfs
   backing file with kernel `vhost-vsock` and *no* vhost-user. Whether it is
   needed there is still open and unmeasured.
5. **"Spectrum has no network design."** Wrong. Asserted from a design document
   of around 2020 without checking the repository or the lists. The failure was
   the one this project has a standing rule against: a claim made without
   capturing the reference fixture first.

### New file

`docs/OBSERVATIONS.md` — append-only, newest-first log of publicly available
material bearing on recorded decisions. Conventions live in the file header;
the central one is that **the subject of every entry is one of our decisions**,
and that our own stack is held to the same standard as anything else.

### Numbering note

The open-problems list in this file already ran to **15**, not 12. An earlier
draft of this session's additions assumed 12 and would have collided. Same rule
as for ADRs: count the list, never the memory of it.

## This session (2026-07-27) — Sway deployed to MINIS, greetd swap done

Mechanical session. The Sway profile built on the Acer on 07-26 is now live on
MINIS, and greetd offers a session picker instead of one pinned command. No new
code; three empirical findings, all of which feed ADR-016 and ADR-026.

Sway 1.12 was purged and reinstalled clean — the machine carried a 1408-byte
generic skeleton config from March, unrelated to CYBRland. `pacman -Rs --print`
confirmed only `wlroots0.20` and `gnu-free-fonts` came with it; Hyprland uses
`aquamarine`, not wlroots, so the live session on tty1 was never at risk.

### Portability fixes to `desktop/`

The profile was written against the Acer and would not have started on MINIS:

| was | now |
|---|---|
| `/home/winterbox/…` ×6 | `$HOME/…` |
| `output eDP-1 { … }` | no output block; `include outputs.conf` |
| `"output": "eDP-1"` (waybar) | removed — bar draws on all outputs |
| `"eDP-1": [1,2,3,4]` (modules) | `"*": [1,2,3,4]` |
| `$rofi_scripts/screenshot/…` | `$HOME/.local/bin/km-shot` |
| `restartAudio` bind | removed — script exists on neither machine |

**Absence of an `output` block is a decision, not a debt.** A hardcoded output
name that does not match is *silently ignored* by sway, which is worse than no
block at all: it looks configured. Sway's default lays outputs out horizontally
in discovery order, which on MINIS came out correct (left/right as cabled).
This is the same failure shape as matching a NIC by interface name instead of
MAC (cf. `20-uplink.network`) — third instance of this pattern in the
project.
Per-machine geometry belongs in an installer-generated file.

### Findings

- **`include` tolerates a missing file.** `outputs.conf` did not exist and sway
  started without complaint. The installer therefore writes the file only when
  it has something to write; no empty placeholder is needed.
- **`$HOME` works in `set`.** Sway leaves undefined `$vars` as literal text and
  the shell expands them at `exec` time. Valid only in `exec` context — it
  would NOT work in `output … bg`, but that line is gone.
- **`--sessions <dir>` replaces the default, it does not merge.** Verified
  live: `hyprland-uwsm.desktop` did not leak in from
  `/usr/share/wayland-sessions/`. The anti-injection pattern holds against
  package upgrades.
- `$mod+Tab` (`focus next sibling`) parses and works — last `VERIFY` in the
  config closed.
- Neither `hyprctl`, `swaymsg` nor `sway --validate` works over SSH: no seat.
  `--validate` fails in the backend before it ever parses the config. Desktop
  work needs a physical console or a running session, full stop.

### greetd

`--cmd hyprland-quiet` removed; `/etc/greetd/sessions/` holds two entries,
`Exec=` pointing at wrappers under `/usr/local/bin` so no entry reaches the
compositor without `sway-session`'s Qt/GTK/XDG environment. `sway-quiet`
mirrors the existing `hyprland-quiet` (ANSI clear before handing over). The
`hyprland-uwsm` entry was deliberately not carried: uwsm wraps the session in
its own systemd-user scope and bypasses the wrapper by construction.

Picker verified live (F3). **Open problem #1 is closed.**

### Deployment shape

User files are symlinks out of `~/katmate-build/desktop/`; `/etc` and
`/usr/local/bin` files are copies, with reference copies committed back into
`desktop/greetd/` and `desktop/bin/`. `~/.config/sway/outputs.conf` is local
and ungitted by design — the wallpaper line lives there.

### Carried

- `desktop/` still needs a licence decision (derived from CYBRland, GPL-3.0).
- swayidle/swaylock still absent — `hypridle.conf` was never supplied.
- `~/.config/rofi/` on MINIS is a separate CYBRland checkout with its own
  `.git`. Two sources of truth for the rofi layer; not reconciled.
- MINIS `~/katmate-build/` carried a nested stale `katmate-os/` with a live
  `.git` whose work tree was the parent — removed. It was the reason
  `--exclude='katmate-os/'` sat in the standard rsync line; that exclude is
  now unnecessary and was dropped.

## This session (2026-07-26) — Sway profile built and live on Acer

First desktop-layer session. Hyprland/CYBRland ported to Sway from scratch on
the Acer; the profile now lives in git under `desktop/` where nothing of the
DE ever was. Sway is running as the default session via greetd/tuigreet.

No decision was recorded. ADR-016 revision and the indicator ADR are held back
deliberately — see "Gated on empirics" below.

### What was built

`desktop/` tree, new:

| file | note |
|---|---|
| `sway/config` | full port; `VERIFY` comments mark three uncertain points |
| `waybar/config-sway.jsonc` | parallel to `config.jsonc`; Hyprland untouched |
| `waybar/modules-sway.jsonc` | `sway/{workspaces,window,language}` |
| `waybar/style-sway.css` | `@import "style.css"` + `.focused` (sway) vs `.active` (hyprland) |
| `bin/sway-session` | env wrapper — sway config has no `env =` directive |
| `bin/km-shot` | grim/slurp + notification actions; replaces hyprshot |
| `bin/km-scratch` | sway scratchpad toggle; replaces pyprland and `toggle_scratchpad.sh` |
| `greetd/` | reference copies of `config.toml` + two `.desktop` entries |

User files are symlinked out of the repo (same anti-drift pattern as
`~/net-sys.con`); system files under `/etc` are copies, deployed by hand.

greetd was already tuigreet, pinned to one command by `--cmd hyprland-quiet`.
Removing that flag restored the session picker; the two `.desktop` entries were
moved from `/usr/share/wayland-sessions/` to `/etc/greetd/sessions/` so a
package upgrade cannot inject an entry that bypasses `sway-session`.

Three shared rofi scripts were made compositor-neutral rather than forked:
`powermenu` → `loginctl terminate-session`, `keybindings` → class at launch.
`wallpaper` was left alone: it targets `DP-2`, which exists on neither machine,
so it has never worked under Hyprland either.

### What the port cost

Dropped, because Sway has none of them: coloured glow (`shadow range 30,
render_power 5`), bevelled corners (`rounding 28, rounding_power 1.0` — a 45°
chamfer, not a radius), background blur (`size 6, passes 4`). Borders, gaps,
palette, fonts and terminal transparency transferred exactly. Animations were
already off upstream.

SwayFX evaluated and rejected: a fork needing a manual rebase per Sway release
(0.5 on 1.10.1, upstream at 1.12), and `scenefx` replaces the wlroots scene
graph rather than adding a render pass. Wrong shape for a TCB component.

The GUI is visibly faster. On the N4200 that is expected rather than
surprising — Hyprland was doing four blur passes over what was effectively the
whole desktop (kitty runs `background_opacity 0`), plus a shadow and a
non-rectangular window shape that defeats occlusion culling.

### Findings worth keeping

- **Sway has no per-window border colour.** `client.focused` is global. This
  does *not* block the domain indicator: inactive windows carry no visible
  border, so only the focused window's colour matters, and one global value
  set over IPC on each focus change is sufficient. Cost per frame: zero. The
  layer-shell overlay considered earlier is unnecessary.
- **Marks are host-set and unspoofable.** Settable only via IPC, drawn by the
  compositor. The strongest candidate carrier for a text-shaped indicator.
- **Per-window channels that a guest cannot reach**, all keyed on PID: border
  width, opacity, mark, workspace. `app_id` and window title are not among
  them and must never be used.
- **The transparency was never Hyprland's.** `active_opacity = 1` in
  `vars.conf`; the effect comes from kitty's `background_opacity 0`. It ports
  unchanged. What does not port is the blur *behind* it — which matters only
  over busy content, since both wallpapers measure near-black (mean RGB
  (11,14,20) and (10,8,10)).
- **Qubes solves the same problem by writing its own GUI daemon**
  (`qubes-gui-daemon` draws per-VM borders under X11). The Sway + IPC route is
  cheaper because Wayland already provides the input isolation Qubes had to
  build.

### Gated on empirics

Two facts remained untested at the time, and both fed the indicator decision:

1. does Sway accept `#RRGGBBAA` in `client.*`? (Hyprland's
   `col.inactive_border` was `#29BECC00`; the port approximates with opaque
   near-black)
2. does `show_marks` draw anything under `border pixel`, which has no
   titlebar? If not, marks need `default_border normal`.

ADR-016 revision and ADR-026 (indicator carriers) were deliberately not written
until these were gated. Writing them first would repeat the ADR-021 and
ADR-025 Path A failure mode: mechanism accepted, then found not to exist.

**Both were gated on 2026-07-27** — see *Next steps*.

### Carried

- `desktop/` needs a licence decision before it is useful to anyone else: the
  Sway config and `style-sway.css` are derived from CYBRland (GPL-3.0) and
  `README.md` declares no project licence.
- MINIS: no output block — resolved 2026-07-27 as a decision, not a debt.
- swayidle/swaylock deliberately absent — `hypridle.conf` was never supplied.
- `~/.config/rofi/scripts/wallpaper/wallpaper` still Hyprland-only.

## This session (2026-07-25) — doc drift sweep, ADR-004/024 propagation, MINIS housekeeping

Found that ADR-024 never reached `SECURITY-MODEL.md` or `ARCHITECTURE.md`: both
still claimed netVM had no SHUTDOWN opcode and no shutdown privilege, six days
after the opcode went live. Corrected, and `CAP_KILL` added to the agent's
recorded capability set. Recorded the underlying cause as a first-class
invariant — netVM is dbus-free by manifest, so bus-dependent systemd mechanisms
are *inert*, not merely unconfigured; this had already invalidated ADR-021's
shutdown path and ADR-025's Path A, and is the open precondition under the
DNS-leak policy. Rule now written down: gate the mechanism empirically before
accepting an ADR that depends on one.

Also: yesterday's `netvm.sh` cleanup fix existed only in the working tree while
`state.md` already called it resolved (committed, `47ece34`). `aio=threads`
landed in both launchers per ADR-004 — empirically `kernel.io_uring_disabled=1`,
not `2`, so only unprivileged QEMU was affected, which is why `app_web.con` broke
and root-launched `net-sys.con` did not. MINIS `~/` and `vg0` cleared of
pre-sysVM remnants.

Commits: `47ece34`, `894d7e3`, `c31dff7`, `e4afc40`.

## This session (2026-07-24) — netVM housekeeping closed; host boot pipeline recorded

Short mechanical session, deliberately cut before the Sway work so the netVM
track closes clean.

### `netvm.sh` — three fixes, one commit

- **Cleanup ordering.** `netvm_cleanup` ran `sync` before `umount_root`; a sync
  on a still-open mount does not settle jbd2. Reordered to umount → `sync` →
  `udevadm settle`.
- **`netvm_umount` added.** `lib.sh:umount_root` swallows failure
  (`2>/dev/null || true`), which is wrong here: a failed umount *is* the
  hot-jbd2 case the loud warning exists for. The local helper returns non-zero
  and says so. Step 10 uses it too, so under `set -e` an incompletely unmounted
  image no longer reports as built.
- **Unit aligned with ADR-025 Path B.** `ReadWritePaths=/etc/systemd/network /run`
  → `/run`. The agent programs rtnetlink directly; `networkctl reload` is inert
  without dbus (E1–E3), so the networkd fragment directory is never written and
  the E4 `tmpfiles.d` DAC line was never needed. The `CAP_NET_ADMIN` comment,
  which still described the dead Path A, was rewritten.
- **Executable bit restored** — `git update-index --chmod=+x build/netvm.sh`
  (`micro` strips it; commit `d6d9267`). Open problem #15 closed.

### What the review actually found

The "Harden `netvm.sh` cleanup" item had been carrying a prescription that could
not have worked (`sync` + `settle` + `sleep` *before* return — on failure the
script never reaches its unmount). The trap itself had existed since the ADR-021
build. The real defect was ordering, and it was three lines. Recorded because the
next stale next-steps entry will look just as authoritative as this one did.

### Documentation corrections

- **Open problem #12 re-aimed.** It read "the password hash in `netvm.sh` is
  invalid" and prescribed substituting a valid one. The debt is that the
  `usermod -p` line exists at all: step 6 locks root and then unlocks it in the
  next breath. Deliberate — the console is the only in-guest observation path
  while the agent has no RUN — but it is a release blocker beside #3 and #4, not
  a hash to correct. (#11 already recorded this correctly; #12 did not.)
- **Interface-name inconsistency resolved in favour of the MAC.** The uplink has
  been written up as `enp0s6`, `enp0s4` and `enp0s5` in different entries. The
  match is and always was on `MACAddress=38:05:25:34:7c:47`; the name is
  incidental and the `10-personal.network` / `Name=enp0s4` convention is void
  (it described the retired pet).
- **DNS-leak entry narrowed.** Override with `Domains=~.` is the stronger
  candidate, but `systemd-resolved` is deliberately not enabled and the image is
  dbus-free — so whether `.network` DNS settings do anything at all is an
  unverified mechanism precondition, the same class that killed ADR-021 shutdown
  and ADR-025 Path A. Probe before deciding; probing needs the console.

### Host boot pipeline (MINIS) — recorded, not decided

`minis_dela.md` documents work already carried out on the host: `linux` →
`linux-hardened` (ADR-004) and GRUB → systemd-boot (ADR-006) — implementation of
decisions already accepted and already ticked in `ROADMAP.md` — plus a UKI at
`/boot/efi/EFI/Linux/arch-linux-hardened.efi`, a `katmate` Plymouth theme
(graphical LUKS unlock + spinner) and a `splash-katmate.bmp` from `katmate-a.png`.
`mkinitcpio` HOOKS put `plymouth` before `encrypt` (otherwise the LUKS prompt is
not graphical) and add `kms`; MODULES carries `amdgpu vfio_pci vfio
vfio_iommu_type1`.

Two notes worth keeping. The `kms` hook is not only cosmetic — `ROADMAP.md` build
step 5 already lists it as a prerequisite for the Sway/installer desktop
integration. And the boot ends in Hyprland, not Sway: consistent with ADR-016's
build state (Sway is target and reference, only the Hyprland profile exists
today) and with the ARCHITECTURE.md release target (greetd + tuigreet → Sway,
Plymouth). Not a defect.

This covers Open problem #1 except the **greetd swap**, which remains open.

### Not done, deliberately

The "next steps" listed at the end of `minis_dela.md` — TPM2 auto-unlock,
Secure Boot, Measured Boot, PCR sealing, `systemd-cryptenroll`, signed UKI,
removal of the GRUB EFI entry, "zero console" boot — are that document's own
horizon, not this session's agenda. They are not in `ROADMAP.md`; they are
backlog candidates.

---

## This session (2026-07-23) — ADR-025 CLOSED: NETCFG live-gated; netvm-agent functionally complete

`handle_netcfg` was the last ERR stub in the agent; all three opcodes
(PING / NETCFG / SHUTDOWN) are now implemented and live-gated. Path B
(rtnetlink) carried out per the 07-21 E-gate.

**Method — golden fixtures.** Before any code, the bytes iproute2 sends over
`AF_NETLINK` were captured (`strace -e trace=sendmsg`, dummy iface, local
10.100.1.1 peer 10.100.1.2/32 metric 100). Five shapes: `RTM_NEWADDR` 40 B,
`RTM_NEWLINK` 32 B, `RTM_NEWROUTE` 52 B, `RTM_DELROUTE` 52 B, `RTM_DELADDR`
40 B. Each is pinned by a unit test comparing the encoder's output against the
capture. "Did I build the message correctly" is therefore PROVEN against a
reference implementation rather than remembered from a header — the ADR-024
method applied to code.

Two structural findings from the capture: `IFA_LOCAL` = local, `IFA_ADDRESS` =
**peer** (the p2p form matches the ADR-025 payload with no translation; the E5
`/24` form would install a connected route for the whole segment and break
"REMOVE → state gone"); and DEL uses a **wildcard body** (`RTPROT_UNSPEC` /
`RT_SCOPE_NOWHERE` / `RTN_UNSPEC`), it does not mirror ADD.

**Empirical finding that corrects the ADR-025 gate.** A peer address installs
the kernel's own route to the peer (`10.100.1.2 proto kernel scope link src
10.100.1.1`, metric 0). Consequences: (a) in v1 the payload's route is
ADDITIVE, not what carries reachability — the kernel's lower metric always
wins; (b) the gate criterion "a route to the peer is visible" is TOO WEAK — it
would pass even if `RTM_NEWROUTE` had never been sent. The gate must assert the
line bearing `metric N`. (c) Teardown is complete without extra work:
`DELADDR` takes the kernel's route with it.

**Dependency call: hand-rolled, not a crate.** The first possible runtime
dependency in the only privileged agent (CAP_NET_ADMIN + CAP_KILL, sharing an
address space with r8169 + the Realtek blob + the v1 WG key). The deciding
inversion: the netlink UAPI is frozen by kernel contract, the crate APIs are
not (`netlink-packet-route` broke across 0.17/0.19/0.21, `neli` across
0.6/0.7, `rtnetlink` is async-only → a tokio runtime in a binary serving one
synchronous request at a time). A crate does not remove netlink semantics, it
relocates them and adds churn. Same conclusion as the non-serde wire. The
multipart `RTM_GETLINK` dump — the one genuinely hard part of netlink — drops
out: MAC→ifindex resolution goes through sysfs.

**Code.** `netlink.rs` (~350 lines, 5 `unsafe`: socket/sendto/recvfrom/close/
zeroed — the same class as `libc::kill`): five message builders, an `NlSocket`
owning its sequence counter, reply validation on two axes (`nl_pid == 0` =
from the kernel, sequence match), and an errno policy following the
convergence contract (`EEXIST` on ADD → OK, `ESRCH`/`ENOENT`/`EADDRNOTAVAIL`
on REMOVE → OK, `ENODEV` = retryable ERR). `netcfg.rs`: total validation per
the ADR-025 table, the record set under `RuntimeDirectory=`, convergent
ADD/REMOVE. `ping-client`: `netcfg-add` / `netcfg-remove`, plus repair of
stale comments claiming netVM does not implement SHUTDOWN (ADR-024 reversed
that on 07-18).

Byte order (implementation reading of ADR-025): LE governs GENUINE INTEGERS
(`link_id`, `metric`); addresses and the MAC are byte arrays in network order,
the same class of field as `match_mac`. Consequence: there is NO address
conversion anywhere in the privileged path — and therefore none to get wrong.

**Live gate — 7/7.** All five ADR-025 criteria plus two extra:

| criterion | result |
|---|---|
| ADD → address + route + UP | OK; `10.100.1.2 scope link metric 100` visible |
| identical re-ADD | OK |
| conflicting ADD (same id, different peer) | ERR |
| REMOVE of an absent id | OK |
| REMOVE → state gone | OK; `enp0s5` has no IPv4, record dir empty, iface still UP |
| RUN aimed at netVM | ERR (absent-not-disabled, on the fresh binary) |
| ADD naming the uplink's OUI MAC (`38:05:25:34:7c:47`) | ERR (structural fence, rejected in the parser) |

The last one is quiet but load-bearing: across seven operations — including one
that named the uplink's MAC explicitly — `enp0s4` never moved (DHCP lease
`10.3.1.110` untouched). The agent does not know which MAC the uplink has; one
bit test makes it unreachable.

**19 unit tests** (2 op + 7 netlink + 10 netcfg), all green.

**Rebuild.** `vm_sys_netvm` rebuilt from a clean `netvm.sh`, KVER
**6.12.96+deb13-amd64** (was 6.12.95). Boot clean: `landlock: Up and running`,
`crng init done` @ 0.010s, `PF_VSOCK registered`, `getty-static … because dbus
and logind are not available` (the manifest stays dbus-free). SHUTDOWN
regression passed on the new kernel. The agent binary in the image was
ultimately replaced BY HAND (mount + install), not by a rebuild — see `../state.md`
debt #14.

Next architectural piece: the **launch daemon** (owns the graph; allocates CIDs
and `/32`s, orders `device_add` before NETCFG, refuses to tear down a VM with
live dependents). ADR-sized, thinking-on.

---

## This session (2026-07-21) — E-gate: NETCFG mechanism resolved, Path B

ADR-025's E1–E5 run live on `vm_sys_netvm` (root unlocked via offline chroot
`passwd`, dev-only, image otherwise untouched — `passwd -l root` still the
release state). Internal netdev confirmed: `enp0s5`, MAC
`52:54:0a:64:01:01`, **`unmanaged`** by networkd (only `20-uplink.network`
baked, matching `enp0s4` uplink) — the load-bearing fact for Path B.
**Result: Path A dead on all three trigger probes, Path B proven.** E1:
`networkctl reload` inert (`Failed to connect to system bus` — no dbus, the
ADR-021-class precondition failure). E2: the varlink surface
`/run/systemd/netif/io.systemd.Network` **exists** (introspected via
`varlinkctl`, world-writable `srw-rw-rw-`) but exposes **no config-mutation
method** — only `GetStates`/`GetLLDPNeighbors`/`GetNamespaceId`/
`SetPersistentStorage` (the last returns `StorageReadOnly` on the RO image).
Stronger than the predicted "absent": surface present, introspected,
provably no reload. E3: `Type=notify-reload` promised a signal path, but
`SIGRTMIN+1` to networkd **kills it** (`code=killed, status=35/RTMIN+1` →
systemd restart), not a reload — empirics overriding introspection, the
ADR-021 trap avoided. E5: a full Path-B dry run under the agent's exact
profile (`setpriv --reuid nobody --inh-caps +net_admin --ambient-caps
+net_admin` — the ADR-024 E8 both-sets pattern) drove `ip addr add
10.100.1.1/24` + `ip link set up` + `ip route add 10.100.1.2/32` on
`enp0s5`, all `=0`, `UP,LOWER_UP`, no bus/DAC/root. Decision rule (A iff
(E1∨E2) trigger ∧ E4): no trigger → **B**, exactly as ADR-025 predicted. E4
(DAC) moot, not tested. Next: `handle_netcfg` (thinking-on/Fable session —
includes the hand-rolled `RTM_*` vs netlink-crate dependency call, ADR-025
§ mechanism). Aside: `SIGRTMIN+1` to networkd is a config-plane DoS
(kill+restart) — noted, immaterial to the trust model (agent already holds
`CAP_NET_ADMIN`).

---

## This session (2026-07-20) — ADR-025 NETCFG payload fixed (design); `net-sys.con` committed

The NETCFG wire contract ADR-023 left abstract is now fixed. **Wire:** fixed
binary layout, opcode `0x06`, count-prefixed bounded route array
(`route_count 1..=4`); no version byte (new shape → new registry value); byte
order deferred to `katmate-protocol::frame`. Locally-administered MAC check = structural uplink
protection; `local_addr == 10.100.1.1`, `peer ∈ 10.100.1.0/24 /32`. **Semantics:**
idempotent per host `link_id`; **convergence, not rollback**; state is the
filesystem, boot-scoped under `/run`; **act-first / reply-second** (mirror of
ADR-024). **Mechanism deferred, E-gated** (Path A networkd-fragment vs Path B
rtnetlink; E1–E5 next session decide — ADR-024 method, since ADR-021's shutdown
died of an assumed mechanism precondition; predicted winner B, no dbus for
`networkctl reload`). Done: ADR-025 committed; ADR-021 status line repaired;
`net-sys.con` **committed for the first time** (`f5f8ef2` — was MINIS-only since
07-09, invariant breach now closed) with a static internal netdev (tap `tap-int0`
+ `virtio-net-pci`, MAC `52:54:0a:64:01:01`); host-side `tap-int0` persisted via
networkd. (Forensic aside: the retired pet netdev MAC `52:54:0A:64:11:01`
byte-encoded `10.100.17.1` — the wrong-subnet bug the pet's nftables carried,
preserved in the MAC; the new MAC encodes `10.100.1.1` correctly.) Next:
boot → confirm guest sees the netdev → E1–E5 → `handle_netcfg` +
`ping-client netcfg-*` → minimal live gate.

### Housekeeping

`vm_sys_netvm` actually rebuilt from a clean `netvm.sh` today (dm-17
open-flag needed a host reboot first); acpid / dev-root / `ffc08537` remnants
gone only now, not 07-18. Stale `vm_tpl_net_root` + `vm_net_overlay.qcow2`
removed. `netvm.sh` export-block dedupe (`9149e17`).

---

## This session (2026-07-18) — netVM SHUTDOWN via agent; #10 closed (ADR-024)
Code + live session, split model: empirical + mechanical parts thinking-off,
ADR-024 authoring thinking-on. Closed Open problem #10 (netVM graceful shutdown)
— not by shipping dbus, but by returning SHUTDOWN to `netvm-agent`.
### The contradiction, not an oversight
The QMP `system_powerdown` path ADR-021 assumed was proven inert last session:
logind needs dbus, and the manifest deliberately omits it — ADR-021's OWN
exclusion. So ADR-021 rejected the dependency and kept the design that stands on
it: a contradiction, not a patchable gap. Fix = replace the shutdown model, not
add dbus.
### Empirical, not guessed (E1-E8, tabulated in ADR-024)
Eight live probes on the running `vm_sys_netvm` settled the mechanism: QMP/logind
inert; non-root `systemctl` has no bus; `/run/systemd/private` root-only; a
negative control (`nobody`, no CAP_KILL → EPERM) bounded the claim; and both root
`kill` and a `setpriv` non-root+CAP_KILL run gave the full graceful poweroff.
Winner: `kill(1, SIGRTMIN+4)` — systemd's documented signal for `poweroff.target`
— under one added capability, `CAP_KILL`. `CAP_SYS_BOOT` stayed rejected (not
graceful under systemd PID 1; also unlocks kexec); dbus/polkit/acpid stayed out.
Symmetry with vm-agent deepened rather than broke: both agents ask their own
PID 1 (vm-agent → INIT_SOCK → katmate-init; netvm-agent → SIGRTMIN+4 → systemd),
transport differing only by init system.
### Code + bake
`Op` gained `Shutdown` (0x05 now decodes; RUN/FILE* stay absent — boundary test
narrowed); `handle_shutdown` is reply-first then best-effort
`libc::kill(1, libc::SIGRTMIN()+4)` (SIGRTMIN is a runtime function under glibc,
not a constant); unit gained `CAP_KILL` (ambient+bounding); vm-agent's doc
comment (claimed netVM carries no SHUTDOWN) corrected. Committed `d609ada`
(code) + ADR-024/unit; ADR-021 status now points to ADR-024. Bake was a FULL
`netvm.sh` rebuild (unit changed — hand-bake would miss `CAP_KILL`), which also
erased the acpid + unlocked-root experiment remnants; root re-locked, manifest
clean. New stock kernel pulled in passing (KVER 6.12.95+deb13-amd64).
### Live gate — PASSED
`ping-client ping 3 → OK` (regression clean), then `ping-client shutdown 3 →
status=0x00 (OK)` with the console running the full stop to `EXT4-fs (vda):
re-mounted … ro` → `reboot: Power down`. Reply-first confirmed by the console
stopping `netvm-agent.service` mid-sequence — OK reached the wire before the
agent died. #10 closed.
### Snags worth remembering
- The `CAP_KILL` unit edit was first made in a non-authoritative tree, missing
  both the commit and MINIS — caught by `grep CAP_KILL` coming back empty on both
  machines; re-done on Acer. (Same class as last session's MINIS drift: edit only
  on Acer source-of-truth.)
- An `--amend` landed on the wrong HEAD (docs commit, not code commit); left as
  is since nothing was pushed. `netvm.sh` thus sits in the ADR-024 docs commit.
- A stale `/mnt/netvm-build` mount (pseudo-fs included) from an interrupted build
  held `vm_sys_netvm` open and blocked `lvremove`; `umount -R` cleared it.
- `netvm.sh` has a duplicated vmlinuz/initrd export block (harmless; cleanup).
### Next
NETCFG payload (ADR-023 impl) is now the only ERR-stub handler and gates the
AppVM internal network — live test first needs a `netcfg` subcommand in
`ping-client` (opcode 0x06 postdates the client).

---

## This session (2026-07-17) — netvm-agent LIVE-GATED; shutdown gap found

Code + live session, thinking off. Took `netvm-agent` from "compiles on Acer"
to "answers on the wire inside a booted netVM". The listener gate passed; a real
shutdown gap surfaced and was diagnosed to root cause.

Also: a long detour reconciling MINIS, which had drifted. `~/katmate-build/`
carried a stale git (behind origin by several sessions) whose "modified" flags
were an artifact of the old commit it compared against, not local edits — every
tracked file was either identical to Acer or older, never newer, so nothing was
orphaned (the "never edit on MINIS" invariant held). Resolved by rsync
(Acer→MINIS, `--delete` with explicit excludes: `.git/`, `target/`, `out/`,
`trixie-build/`, `katmate-os/`). MINIS git is henceforth ignored as authority;
MINIS realigns by rsync only (Path A).

### Build + bake (all on MINIS)

- **Build is host-toolchain, NOT chroot.** Fish history + `foundation.sh:56`
  settled the open question from the 2026-07-10 memory note: the agent is built
  with MINIS host `cargo build --release`, not inside the trixie chroot. It works
  because the host binary links a low-enough glibc: `objdump -T … | grep GLIBC`
  → max `GLIBC_2.34` < trixie 2.41. Same check, same result as vm-agent.
- **`netvm.sh` is monolithic (no `--bake-only`).** Running it overwrites the
  whole `vm_sys_netvm` LV (debootstrap → apt → config → step-7 agent bake →
  kernel/initrd export). So for a first iteration the agent was **hand-baked**
  into the existing image instead: `vm_sys_netvm` is a standalone linear RW LV
  (not thin, not frozen — no `-K -ay`), so mount RW → `install -D -m 0755
  netvm-agent /usr/local/bin/` → write `netvm-agent.service` verbatim from step 7
  (`CAP_NET_ADMIN`, `NoNewPrivileges`, `ProtectSystem=strict`) → chroot
  `systemctl enable` → sync + udevadm settle + umount (the anti-jbd2 pattern; the
  umount was clean). The `systemctl enable` `/proc not mounted` warning is
  harmless — enable is a pure symlink op.

### Live gate — PASSED

Booted via `~/net-sys.con` (q35, CID 3, RTL8125 vfio, stock Debian kernel
`6.12.95+deb13-amd64` + initramfs). Boot reached `multi-user.target` /
`graphical.target`; `netvm-agent.service` started; `PF_VSOCK` registered. From
the host:

- `ping-client ping 3` → `connected: cid=3 port=1025 op=PING (0x01)` →
  `status=0x00 (OK)`. **First live control path into netVM.** Closes "nothing
  inside the declarative image has ever been verified".
- `ping-client shutdown 3` → `status=0x01 (ERR)`. **"absent, not disabled"**
  proven on the wire: SHUTDOWN (0x05) has no variant in netvm-agent's `Op`, so it
  dies at `Op::try_from` (log + ERR + connection kept alive), not at a runtime
  gate. The unit-test assertion, now confirmed live.
- NETCFG could **not** be live-tested: `ping-client` has no `netcfg` subcommand
  (it predates opcode 0x06 and only knows ping/run/shutdown). NETCFG live test
  waits on a client that can encode it — which waits on the ADR-023 payload.

### Shutdown gap — found and diagnosed (NEW open problem #10)

Attempting a clean stop, `system_powerdown` in the qemu monitor did **nothing**
(sent twice; VM stayed up). This matters because ADR-021's netVM shutdown model
IS `system_powerdown` → logind → clean stop. Diagnosed, not left as a mystery:

- Boot log already said it: `getty-static.service … dbus and logind are not
  available`.
- `netvm.list` ships neither `dbus` nor `libpam-systemd`.
- Mount-inspect of the image: `systemd-logind` binary (309768 B) **and**
  `systemd-logind.service` unit are **present** — but `dbus-daemon` is **absent**.

So logind cannot register on the system bus → never runs → the registered ACPI
power button (`Power Button [PWRF]`) has no handler → `system_powerdown` is
inert. **ADR-021 is NOT disproven** — its precondition (a running logind) was
simply missing from the image. One-line fix: add `dbus` (+`libpam-systemd`) to
`netvm.list`, rebuild, re-test. Worth weighing first (thinking-on): dbus in the
most-exposed VM is added attack surface; a narrow `acpid` power-button path is a
lower-surface alternative — ADR-worthy. Dev shutdown meanwhile was `quit` in the
monitor (ungraceful; LV confirmed healthy after, `-wi-a-----`, clean, unmounted).

### Next

1. Add `dbus` (+`libpam-systemd`) to `netvm.list` (or decide the `acpid`
   alternative first); rebuild via `netvm.sh`; re-test `system_powerdown` → clean
   poweroff. This also makes the manual bake reproducible declaratively.
2. Then wire QMP (`-qmp …` in `net-sys.con` + host tool) — pointless before
   logind can act on it.
3. ADR-023 NETCFG payload (thinking-on) + a client subcommand to live-test it.

## This session (2026-07-15) — netvm-agent listener + per-connection loop (code)

Code session, thinking off. Wrote the mechanical half of `netvm-agent` — the
one designed on 2026-07-10 and unblocked by the 2026-07-13 workspace split. No
live boot: this landed the transport, not the network operation. NETCFG's real
handler (ADR-023 payload) is still a separate session.

### What was written

`agent/crates/netvm-agent/src/main.rs` — a deliberate SUBTRACTION from
`vm-agent/src/main.rs`, keeping only the skeleton both agents genuinely share:

- **Kept:** `AF_VSOCK` socket, `bind(VMADDR_CID_ANY, DEFAULT_CONTROL_PORT)`,
  `listen`, the accept loop with its `peer.svm_cid != VMADDR_CID_HOST` reject +
  close, and the synchronous single-client per-connection loop (`read_request`
  → `Op::try_from` → dispatch → per-request ERR on handler error, EOF ends the
  loop quietly).
- **Dropped (all appVM policy, none of it protocol):** `config.rs` (no config
  surface), `posix_spawn` + `environ` (no child — there is no `spawn()` in this
  binary at all), `signal_init_shutdown` (no SHUTDOWN), `path_is_allowed` (no
  file surface), the `WHITELIST`/`HOME_PREFIX`/`INIT_SOCK`/`SHUTDOWN_CMD`
  constants, and the `SIGCHLD` `SIG_IGN` (nothing forks here, so there is
  nothing to reap).
- **Dispatch is two branches:** `Op::Ping → frame::write_ok`;
  `Op::Netcfg → handle_netcfg`.

### Two judgement calls worth recording

1. **NETCFG is an ERR stub, not `todo!()`.** NETCFG *decodes* here — it is a
   genuine capability of this binary (unlike RUN/FILEGET/FILEPUT/SHUTDOWN, which
   have no variant in `netvm-agent`'s `Op` and die at `Op::try_from`). But its
   real handler (the ADR-023 payload) is a separate session, so the handler
   currently logs and returns ERR with `Rejected("NETCFG not yet implemented")`.
   `todo!()` was rejected on purpose: a panic would crash the agent and drop the
   connection the first time the host sent NETCFG. An honest "I decode this, I
   just don't do it yet" is the right seam to leave.

2. **Port is the shared default, no env override.** `netvm-agent` uses
   `frame::DEFAULT_CONTROL_PORT` directly, with no `CONTROL_PORT` env read. This
   is not an omission — it follows the note already written in
   `vm-agent/config.rs`: *"netvm-agent has NO config.rs … its control port is
   the shared default. If it ever needs one, it gets its own."* Same port,
   different CID, exactly as the wire intends. `vm-agent` keeps its env override
   because it also carries a waypipe target; netVM carries neither.

### Verification (Acer only — host toolchain)

- `cargo build -p netvm-agent` → clean (dev + release).
- `cargo test -p netvm-agent` → `2 passed` (`forbidden_opcodes_fail_at_decode`,
  `handled_opcodes_map`) — the security-boundary assertions in `op.rs` still
  hold through this `main`.
- clippy: no new warnings from `main.rs` (the 8 `overindented` notes are
  pre-existing, from `op.rs` doc comments).
- Committed + GPG-signed on Acer as `4538e29` ("netvm-agent: implement listener
  + per-connection loop").

### What this does NOT close

The **live gate is not reached.** Acer is a host-toolchain syntax/type check
only; the shipped binary must come from the **trixie chroot on MINIS**
(`cargo build --release -p netvm-agent`), then bake into `$OUT/netvm-agent`
(netvm.sh step 7) and boot netVM for `ping-client ping 3 → OK`. Until that
runs, "nothing inside the declarative netVM image has ever been verified" still
stands — the listener exists in source, not yet on the wire.

## This session (2026-07-14) — network object model FINALIZED (design, no code)

Two ADRs written, no live work. The network layer gets an object model.

**ADR-022 — topology is a graph; the NIC is an assignable object.** Five object
classes (`Nic`, `Image`, `Vm`, `Link`, `Policy`). The whole topology is two
fields on `Vm`: `netvm: Option<VmRef>` + `provides_network: bool`. Consequences:
policy is a *netVM*, never a rule (differentiated access = attach to a different
netVM, each baking one immutable policy — ADR-021's static firewall survives
intact); `netvm: None` = first-class offline/air-gap AppVM (absence of an object,
not a deny rule); one physical NIC = one **q35 driver domain** (hardware, no
secrets); **proxy netVMs are microVMs** (no PCI → no q35) and may be chained, so
`appVM → netvm-vpn → netvm-driver → NIC` is cheap here in a way it is not in
Xen/Qubes. **v1 ships the simplest graph = the netVM running today.** Nothing
built so far is discarded.

**ADR-023 — NETCFG describes a link, never an AppVM.** Payload = one p2p link
(match, local/peer addr, `/32`, route, metric), ops `add`/`remove` only (no
`modify` — a mutable link is a boundary that moves in place). No VM name, no
role, no policy, no nft, no shell string. One opcode therefore serves an AppVM
downlink, a proxy uplink and a future sysVM↔sysVM edge; `netvm-agent` stays a
dumb executor with no representation of the graph. **In-guest mechanism left
open** (networkd fragment vs direct `rtnetlink`) — decided in the
`netvm-agent/main.rs` session, fragment path is the default.

### Consequences to act on

- **CID renumbering (breaking).** New map: `2` host / `3–19` sysVM (3 = primary
  netVM) / `20–99` fixed AppVM / `≥100` disposable. **personalVM 4 → 20,
  app_web 5 → 21.** Launchers, `.con` scripts and any hardcoded CID must follow.
- **Kernel:** proxy sysVMs will need `CONFIG_WIREGUARD` + nft/netfilter in the
  shared microvm kernel — which all AppVMs also run. The code is unreachable from
  an AppVM (uid 1000, no `CAP_NET_ADMIN`) but *present*: a conscious departure
  from absent-not-disabled at the kernel level, accepted because ADR-021 already
  rejected a second kernel (doubled config maintenance, firmware-licensing issues
  for ISO distribution). Taken up when the first proxy is built, not before.
  (Note: there is NO pending rebuild — `HW_RANDOM_VIRTIO` and
  `SECURITY_LANDLOCK` went in on 2026-07-01 and are live.)
- **Proxy init model is open:** ADR-021 binds netVM to systemd for *uplink* DHCP;
  a proxy has no uplink DHCP (static p2p link via NETCFG) and `wg`+`nft` need no
  networkd → a proxy may be a `katmate-init` sysVM. Separate decision, when the
  first proxy is built.
- **Known gap #7 (new):** in v1 the WireGuard key and the `r8169` driver + Realtek
  blob share one address space. Accepted for v1; the model already permits the
  split.
- **Known gap #9 (new):** IOMMU-group quality is now a *hard* requirement →
  HCL + installer preflight. Product blocker, not a v1 code blocker.
- **DE decided (→ ADR-016 revision, next session):** the host compositor is in the
  TCB (it draws the domain indicator). **Sway ships alone**, no installer choice,
  no dual install. Hyprland/CYBRland stays a dev/demo profile until its indicator
  implementation is separately verified. DE profile contract documented in
  ARCHITECTURE.md.

**Next session unchanged:** `netvm-agent/main.rs` listener (mechanical, thinking
off). Live gate: `ping-client ping 3 → OK`.

## This session (2026-07-13) — agent Cargo workspace split

Mechanical migration of the existing Rust agent into the workspace skeleton
designed in the 2026-07-10 architecture session. No behaviour change intended in
`vm-agent`; the split had to be provably transparent on the wire before
`netvm-agent` could be written against it.

### What moved where

| from | to | change |
|---|---|---|
| `agent/src/protocol.rs` (codec) | `katmate-protocol/src/frame.rs` | `Cmd` + `from_u8`/`to_u8` **removed, no replacement**; `Request` → `RawRequest{opcode: u8}`; `encode_request(op: u8, …)` |
| `agent/src/protocol.rs` (policy consts) | `vm-agent/src/main.rs` | `WHITELIST`, `HOME_PREFIX`, `INIT_SOCK`, `SHUTDOWN_CMD`, `DEFAULT_HOST_CID`, `DEFAULT_WAYPIPE_PORT` |
| `agent/src/error.rs` | `katmate-protocol/src/error.rs` | verbatim; only `UnknownCommand`'s doc + `Display` reworded |
| `agent/src/config.rs` | `vm-agent/src/config.rs` | fallbacks re-pointed |
| `agent/src/main.rs` | `vm-agent/src/main.rs` | `match req.cmd` → `Op::try_from(req.opcode)?` |
| `bin/ping-client/` | `crates/ping-client/` | symlinks into `agent/src/` gone; encodes raw `opcode::OP_*`, has no `Op` of its own |
| `agent/vm-agent.c` | — | legacy C agent deleted |

The constant split is the whole point and is worth restating: `frame.rs` keeps
only what is genuinely shared wire (`PROTOCOL_VERSION`, `STATUS_*`, `MAX_*`,
`DEFAULT_CONTROL_PORT`). Everything else was never protocol — it was appVM
policy, and `netvm-agent` must not inherit it.

### One judgement call worth recording

An unmapped opcode no longer closes the connection. Previously `Cmd::from_u8`
lived *inside* `read_request`, so a bad opcode surfaced as a decode error and
`handle_connection` dropped the peer. Now decode and mapping are separate steps,
so this had to be chosen rather than inherited: `Op::try_from` failure → log +
ERR + **`continue`**. Rationale: the peer did not corrupt the stream, it asked
for something this binary does not implement. Keep serving. (Reverting to
drop-the-connection is a one-line change if that turns out wrong.)

### Regression gate — PASSED

Deliberately run against the **pre-split guest image** (`vm_app_web` still
carries the old monolithic `vm-agent`), because that is the one thing this test
can prove and the new image cannot: **the wire did not change.** New workspace
`ping-client` → old in-guest agent:

- `ping-client ping 5` → `status=0x00 (OK)`
- `ping-client run 5 nautilus` → `OK`, nautilus renders on host Hyprland

If the split had broken the codec, this fails. It did not. Any future failure
against a *new* image is therefore in `vm-agent`, not in `katmate-protocol` —
which is exactly the isolation the two-stage gate buys.

Baking the new `vm-agent` into an app layer is a separate step (app-layer
rebuild), not done this session.

### Housekeeping

- **Binary path changed:** `agent/target/release/ping-client`
  (was `bin/ping-client/target/release/ping-client`). Anything on MINIS that
  invokes it — and the rsync exclude set — needs the update.
- Stale `agent/src/`, `agent/vm-agent.c`, `bin/ping-client/` removed from the
  MINIS build copy by hand before rsync (the sync runs without `--delete`).
- Boot log re-confirms the 2026-07-01 kernel flags are live: `landlock: Up and
  running`, `ALSA #0: Loopback 1`, `crng init done` @ 0.010s. No kernel rebuild
  pending.

## This session (2026-07-10) — netvm-agent architecture + QMP shutdown (design)

Design/thinking session, no live boot. Turned "netvm-agent is the unblocking
next step" into a finished, buildable design and revised ADR-021. Read the
actual sources (`agent/src/{main,protocol,error,config}.rs`, `bin/ping-client/`)
and `build/netvm.sh` before deciding — resolutions follow the code, not memory.

### Decisions (all confirmed)

1. **Cargo workspace, one shared crate.** `agent/` is the workspace root; ONE
   shared `katmate-protocol` (framing + VSOCK transport + `error` module +
   shared opcode value registry). Two guest bins: `vm-agent` (uid 1000) and
   `netvm-agent` (`CAP_NET_ADMIN`). `ping-client` moves `bin/ping-client →
   agent/crates/ping-client` as a member; symlinks dropped. Per-package guest
   builds (`cargo build --release -p vm-agent -p netvm-agent` in the trixie
   chroot); host builds `-p ping-client`. One `[profile.release]` at root.
2. **Opcode values shared, enums + handlers per-bin.** Shared `read_request`
   returns a RAW `u8` opcode (`RawRequest`), not `Cmd`; length validation stays
   shared, opcode→handler is per-bin `TryFrom<u8>`. Forbidden opcode fails at
   decode. Registry exists so `ping-client` can encode any opcode (drives both).
3. **netVM shutdown = host QMP, not an agent opcode.** q35 → ACPI. Host sends
   `system_powerdown` → logind `HandlePowerKey=poweroff` → clean networkd/wg/nft
   stop, releasing the RTL8125 for FLReset-. So `netvm-agent` = **NETCFG + PING
   only**; no SHUTDOWN, no `CAP_SYS_BOOT`, no dbus/polkit. appVM `vm-agent` KEEPS
   SHUTDOWN (→ katmate-init; microvm has no ACPI). ("graceful ⟹ root" was wrong —
   graceful = ask PID 1 / the host, not privilege the agent.)
4. **In-guest verification uses a dev-only console password** (decision B),
   out-of-band, same "remove before release" class as sshd. The agent has no
   RUN, so it is NOT the verification path.

### ADR-021 revised (committed, GPG-signed, pushed)

Four blocks: opcode table + registry/absent-not-disabled wording; QMP shutdown
bullet (replaces old "SHUTDOWN … graceful teardown"); `CAP_NET_ADMIN` scope (now
one job, NETCFG); rejected alternative (in-agent SHUTDOWN via `CAP_SYS_BOOT` or
logind/polkit — q35 ACPI makes host QMP graceful without guest privilege).

### Next (CODE session, thinking off)

Ordered, each with a gate: (a) `katmate-protocol` (codec split, raw-opcode
`read_request`); (b) `vm-agent` onto it, UNCHANGED behaviour — regression gate
`ping-client ping 5 → OK` before touching netVM; (c) `netvm-agent` (PING +
NETCFG); (d) `ping-client` moved in. Then bake `$OUT/netvm-agent` (netvm.sh step
7, already scaffolded), boot-test `ping-client ping 3 → OK` as first live
control-path proof.

## This session (2026-07-09) — netVM sysVM declarative build PROVEN

The ADR-021 declarative build (`build/netvm.sh`, from the 2026-07-08 session)
was taken from "builds cleanly" to "boots and reaches the network" on MINIS.
Objective: prove the built `vm_sys_netvm` image boots unaided and reproduces the
uplink that previously lived only in the hand-installed netinst pet. Done — with
two real bugs fixed along the way and a host-side motiliec (suspend) neutralised.

### Two build-blocking bugs fixed (both in `netvm.sh`, committed + pushed)

1. **initrd `MODULES=dep` → `MODULES=most`.** The first sysVM boot dropped to an
   initramfs shell: `ALERT! /dev/vda does not exist`. Root cause: `MODULES=dep`
   resolves needed modules against the BUILD-time root (ext4-on-dm in the chroot),
   so `virtio_blk`/`virtio_pci` were omitted — but the guest boots as a virtio
   device with root on `/dev/vda`. `virtio-pci` transport was present (device
   enumerated as `virtio2`), but without `virtio_blk` no `/dev/vda` node. Fix:
   `MODULES=most` includes the full virtio + common-storage set regardless of
   build context. Proof: initrd grew 11MB → 36MB; second boot showed
   `virtio_blk virtio2: [vda] ... 4.00 GiB` and `EXT4-fs (vda): mounted`.
   (`dep` was originally chosen for a trimmed initrd + to avoid the jbd2-inducing
   post-apt `update-initramfs` — `most` keeps the "postinst generates it" path,
   only widens the module set.)
2. **conf.d seed `printf >` → `install -D`.** After the `most` edit, the build
   aborted mid-write: `.../initramfs-tools/conf.d/modules-most: No such file or
   directory`. Cause: `printf > path` does NOT create parent dirs, and
   `/etc/initramfs-tools/conf.d/` does not exist yet on a fresh debootstrap. The
   original `dep` code used `install -D` (creates dir + mode + content in one).
   Fix: restore `install -D -m 0644 /dev/stdin ... <<< 'MODULES=most'`. (A stray
   deleted `)` on the adjacent `mapfile` line was caught by `git diff` + `bash -n`
   before commit — the reason to always `bash -n` a build script after editing.)

Conf renamed `modules-dep` → `modules-most` to match. Both fixes GPG-signed and
pushed (commits `bd96a21`, `37c3fb0`).

### Host suspend masked (the real time-sink this session)

hypridle put MINIS to sleep TWICE mid-build while attention was elsewhere,
each time killing the build and leaving a stuck `jbd2` kthread on the new LV
(the documented "build failure mid-`/boot` write" pattern → host reboot the only
cure). Neutralised for good:
`systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
— a hard, reboot-surviving block independent of any idle daemon. UNMASK after
the build sessions are over. General rule now: mask suspend before any netVM
build run; the build host must stay awake through debootstrap + `/boot` write.

### Boot + uplink gate — PASSED

Built via `sudo bash -c 'DEBIAN_MIRROR=http://ftp.ch.debian.org/debian bash
netvm.sh'` (CH mirror because MINIS's ProtonVPN exit is in Switzerland; the
Ljubljana `deb.debian.org` fastly timeouts do not apply from a CH exit, and an
SI mirror over a CH tunnel would be worse). Build ran clean to `Exporting
vmlinuz + initrd` + `netvm.meta` + `Unmounting`. Boot via a fresh minimal
`~/net-sys.con` (uplink only — internal TAP dropped for this gate):

- `virtio_blk virtio2: [vda] 8388608 512-byte logical blocks (4.00 GiB)` — the
  `most` fix working; `/dev/vda` present.
- `EXT4-fs (vda): mounted filesystem ... r/w` — root mounted (was the failure
  point).
- Full systemd to `multi-user.target` / `graphical.target` — sysVM, not
  katmate-init (correct for netVM).
- `r8169 ... enp0s5: RTL8125B, 38:05:25:34:7c:47` — firmware loaded (no `-2`;
  `firmware-realtek` from the manifest), then
  `enp0s5: Link is Up - 1Gbps/Full`.
- **DHCP lease confirmed from the host:** `nmap -sn 10.3.1.0/24` shows
  `10.3.1.110` up with MAC `38:05:25:34:7c:47`. (ICMP ping did NOT answer —
  netVM nftables drops it — but the ARP scan proves L2 presence + lease. This is
  the correct security posture, not a fault.)

Interface is `enp0s5` here, not `enp0s6` — this minimal launcher omits the
internal TAP NIC, so the RTL8125 lands on a different PCI slot / name. Irrelevant
by design: `20-uplink.network` matches by MAC, not `Name=`, which is the whole
reason for the MAC match. `Open count: 0` after `QEMU: Terminated` — clean
teardown, no jbd2.

### What this closes, what it does not

- **Closes:** the netVM pet-drift class (Open problem #6). The uplink is now
  reproduced from `netvm.sh`, not from a hand-installed instance. ADR-021's
  central claim (declarative sysVM build) is proven end-to-end for the uplink.
- **Does NOT close yet:** there is no way INTO the guest — `netvm.sh` locks root
  ("dev sets a console password out-of-band", which was never done), so console
  login fails and there is no `netvm-agent` yet. `networkctl status` /
  WireGuard bring-up / inner-segment (personalVM p2p) are all unverified from
  inside because of this. The `netvm-agent` is now the unblocking next step, not
  a nicety.

### Follow-ups noticed this session

- **`netvm.sh` cleanup leaves a hot jbd2 even on SUCCESS.** The successful build
  ended with `Open count: 1` + live `jbd2/dm-17` despite `mount` empty and
  `lsof`/`fuser` clean — the umount returned before jbd2 committed. Harden
  cleanup: `umount -R "$NETVM_MNT"` → `sync` → `udevadm settle` → short `sleep`
  before the script returns, so a successful build does not force a reboot.
- **`W: No zstd ... using gzip`** during initramfs generation — the image lacks
  `zstd`, so initrd is gzip-compressed (larger, works). Add `zstd` to the netVM
  manifest if a smaller/faster initrd is wanted. Cosmetic.
- **`net-sys.con` vs `net-vfio.con` naming + location.** The new sysVM launcher
  is `~/net-sys.con` (host-local, not in git); the retired pet used
  `~/net-vfio.con`. `netvm.sh` comment still says `net-vfio.con`. Settle the
  canonical launcher name + location when the pet is formally retired.

## This session (2026-07-08) — netVM uplink complete; netVM = sysVM decision

Live work on MINIS console + serial into netVM (CID 3). Objective: point the
guest at the passed-through RTL8125 (`enp0s6`), then run the critical
second-boot FLReset- test. Both done; a firmware gap surfaced and was closed;
and the session produced an architectural decision about how netVM is built.

### netVM in-guest netconf (`enp0s6`) — DONE

- **Diagnosis of the first-boot `[FAILED] Raise network interfaces`:** the guest
  had TWO stacks active — `systemd-networkd` (enabled, running) AND `networking`
  (ifupdown, enabled but **failed**). `/etc/network/interfaces` carried a stale
  static block for `enx00e04c3961b8` — the HOST's USB-NIC MAC, wrong VM entirely
  — almost certainly written by the original netinst installer back when the
  USB-NIC was passed into netVM. That is the source of the recurring boot
  failure, not `enp0s6` itself.
- **Fix (ifupdown side):** reduced `/etc/network/interfaces` to `lo` +
  `source interfaces.d/*` only. The primary-interface job now belongs entirely
  to networkd.
- **New `/etc/systemd/network/20-uplink.network`** — MAC-match (stable across
  PCI topology), DHCP:
  ```ini
  [Match]
  MACAddress=38:05:25:34:7c:47

  [Network]
  DHCP=ipv4

  [DHCP]
  RouteMetric=100
  ```
  (`38:05:25:34:7c:47` = the RTL8125's MAC as seen in the guest. Matches by MAC,
  not `Name=enp0s6`, so a slot/name change does not break it — the whole reason
  for the exercise. `10-personal.network` stays `Name=`-matched on `enp0s4`, the
  internal p2p segment to personalVM at `10.100.1.2`.)

### Firmware gap (the real last blocker) — closed

- **Symptom:** after networkd matched and brought the link UP, it stayed
  `no-carrier`: `r8169 0000:00:06.0: Unable to load firmware
  rtl_nic/rtl8125b-2.fw (-2)`. `-2` = ENOENT: `/lib/firmware/rtl_nic/` was empty.
- **Root cause:** vfio hands the RTL8125 to the guest as a plain PCI device, and
  the guest's own `r8169` needs the Realtek firmware blob to bring the PHY up.
  The netinst netVM image never had `firmware-realtek` (the USB-NIC r8152 the
  guest used before does not need a separate blob).
- **Fix:** `apt install firmware-realtek` (already had `non-free-firmware` in
  `sources.list`; apt reached the mirror over the internal segment).
  `ip link set enp0s6 down; up` reloaded the driver with the blob present.
- **Result:** `Gained carrier` → `DHCPv4 address 10.3.1.110/24, gateway
  10.3.1.1`. `networkctl status enp0s6`: `State: routable (configured)`,
  `Online state: online`, `Speed: 1Gbps` full duplex.

### Second-boot FLReset- test — PASSED (the critical gate)

Clean shutdown of netVM → fresh `net-vfio.con` launch. On the second boot the
guest reached the console with no ENOMEM and no VFIO reset error, firmware
loaded at boot (no `-2` this time), and `enp0s6` came back `routable` with the
same DHCP lease `10.3.1.110/24`, 1Gbps full duplex, fresh `systemd-networkd`
PID. This proves `disable_idle_d3=1` survives a guest reboot cycle for the
FLR-less RTL8125 — the first boot succeeding was never sufficient; this is the
result that makes the passthrough usable. The earlier one-off `Link DOWN /
Lost carrier` blip did NOT recur (was a switch/cable renegotiation, not the
device).

### Architectural decision — netVM is a sysVM (→ ADR-021, pending)

netVM is deliberately a **separate component class**, not an appVM, and will
NOT be folded into foundation/app-layer or `katmate-update`. Rationale:
- **Different machine model:** the ONLY VM with `-machine q35` (needs PCI for
  vfio passthrough), not microvm. Needs ACPI/initramfs/firmware and full
  systemd (networkd, wg-quick, DHCP client) — the exact opposite of the
  systemd-free, katmate-init foundation.
- **Different lifecycle:** appVM rebuilds are driven by waypipe bumps (ADR-019);
  netVM has no waypipe at all. netVM rebuilds are driven by Debian security
  updates + network config. `katmate-update` must never touch it.
- **In Qubes terms:** this is a sysVM, a different class from appVMs.

BUT "separate" must mean "separately declarative", NOT "hand-maintained forever".
The current netVM is a netinst pet (`deb cdrom:` line, GRUB+initrd in-guest,
installer-written configs) — and that pet just leaked the stale-`interfaces`
bug into the most security-exposed VM (raw network, VPN keys). ADR-020 (release
= pre-baked ISO, user never builds) and ROADMAP step 3 (NetVM installer
integration) both REQUIRE netVM to be provisioned declaratively by the
installer, which is impossible while it is a hand-installed pet. So the decision
is: **a dedicated `build/netvm.sh` (debootstrap-based, its own package + config
manifest), a separate `netvm-update` track, and ADR-021 to record it.** Full
design + the script belong to a dedicated Opus/thinking session, not this one.

### netVM manual deltas PENDING pipeline (must not be lost)

These fixes exist ONLY in the running netVM instance and will vanish on any
rebuild until `build/netvm.sh` exists:
1. `firmware-realtek` installed (for `rtl8125b-2.fw`).
2. `/etc/systemd/network/20-uplink.network` (MAC-matched DHCP for `enp0s6`).
3. `/etc/network/interfaces` reduced to `lo` + `source` (stale
   `enx00e04c3961b8` static block removed).
Also to check at pipeline time: where the stale `enx00e04c3961b8` block came
from (netinst installer artefact) so it is not re-baked.

### Open follow-up noticed this session

- **DNS leak risk:** the DHCP lease on `enp0s6` set `DNS: 1.1.1.1` (LAN-router
  supplied). netVM is meant to push DNS through ProtonVPN (`10.2.0.1`); a
  LAN-supplied resolver on the uplink can leak queries outside the tunnel.
  Decide whether to override with `DNS=10.2.0.1` + `Domains=~.` in
  `20-uplink.network`, or ignore the uplink's DNS entirely. Security-relevant;
  fold into the netvm manifest.

## Archived — completed threads (2026-07-05 / 2026-07-06)

Both the RTL8125 passthrough and the USB-NIC host recovery threads are now
CLOSED (the uplink completion above supersedes them). One-line each; full
detail in git history and the invariants below.

- **2026-07-05 — RTL8125 PCIe passthrough achieved.** `memlock` drop-in
  (`netVM.service.d/memlock.conf` → `LimitMEMLOCK=infinity`),
  `/etc/modprobe.d/vfio.conf` (`ids=10ec:8125 disable_idle_d3=1` +
  `softdep r8169 pre: vfio-pci`), vfio modules in mkinitcpio, `/dev/vfio/12`
  via a `vfio` group + udev rule. Post-reboot bind confirmed
  (`Kernel driver in use: vfio-pci`); `net-vfio.con` first boot reached
  `enp0s6`. (See invariants: memlock, FLReset-, vfio device permission.)
- **2026-07-06 — USB-NIC (r8152, `0bda:8153`) host recovery SOLVED (#7).** Root
  cause was OUR OWN leftover udev rule `/etc/udev/rules.d/30-usb-nic-qemu.rules`
  running `r8152/unbind` on every plug → `driver=[none]` after clean
  enumeration, on every port/bus. Fix: `rm` the rule + `udevadm` reload. NIC
  came up as `enp195s0f3u1u1` (MAC `00:e0:4c:39:61:b8`). A full `linux-6.12.94`
  build that session was wasted effort (MINIS runs Arch `7.0.12`, not 6.12.y;
  r8152 was present all along). Diagnostic lesson promoted to an invariant
  (check `udev/rules.d` before kernel hypotheses).

## This session (2026-07-04) — katmate-update MVP orchestrator

`build/katmate-update.sh` written and dry-run-validated on MINIS. Closes
ROADMAP build-order step 2 (the orchestrator that chains a waypipe bump end to
end).

- **`build/katmate-update.sh` (bash, committed):** sources `build/config.sh`,
  then chains the proven steps in dependency order — build host waypipe
  (`waypipe-host.sh`) → `make foundation` (writes `foundation.meta`) →
  `make app-web` + `make app-vault` → recreate instance deltas. Home LVs
  untouched. Realizes ADR-019 / ARCHITECTURE.md update-flow §1.
  - **MVP scope, deliberately narrow:** instances assumed STOPPED — no
    teardown (that is launch-daemon policy: disposable vs persistent, must not
    kill netVM/CID 3). Preflight aborts loudly (via `fuser`) if any qemu holds
    an instance delta, BEFORE the destructive foundation rebuild.
  - `WAYPIPE_VERSION` edited by hand in `config.sh`; the script only reads it.
    App types hardcoded `web vault` (matches Makefile `APP_TYPES`).
  - vm-agent + kernel vmlinuz are NOT built here; their presence is checked so
    a missing artefact fails before rebuild, not mid-`make`.
  - Delta → app-type mapping by `<instance>_<type>.qcow2` convention, validated
    in the preflight (type = last `_` segment).
  - `--dry-run`: runs all checks, prints the plan, performs no build/make/
    recreate (root not required). Used to validate this session — no live
    rebuild was run (would needlessly destroy the working frozen foundation).
- **Dry-run result:** config read (`v0.11.0`), all paths resolved, single delta
  `test_web.qcow2` found + free, mapping `test_web → web → /dev/vg0/vm_app_web`
  OK, full chain printed. Clean.
- **`out/vm-agent` staged on MINIS:** the Makefile foundation target requires
  `out/vm-agent`, but the binary was only ever built to
  `agent/target/release/vm-agent` (never copied to `out/`). Copied into place.
  Verified: dynamically linked, max symbol `GLIBC_2.34` (well under trixie's
  2.41 — safe for the guest). `out/` is a build artefact, gitignored.

### Notes / cosmetics observed 2026-07-04

- **Naming wart (`WAYPIPE_VERSION` vs `WAYPIPE_TAG`):** `config.sh` exports the
  variable as `WAYPIPE_VERSION`; the `foundation.meta` KEY written by
  `foundation.sh` is `WAYPIPE_TAG`. Same value, two names — a trap. Worth
  unifying, or at least cross-referencing in an ADR comment.
- **Stale Makefile header comment:** still lists `out/linux-image-...deb` as a
  foundation prerequisite, though the kernel path is now `KERNEL_VMLINUZ`
  (external vmlinuz, not `.deb`). Cosmetic; clean up on next Makefile touch.

## This session (2026-07-03) — ADR-019 chain closed (items #2–#4)

Implementation session; the three remaining version-lock items landed and were
validated live on MINIS. No design changes — the ADR-019/020 decisions from
2026-07-02 held as written.

- **Patch-queue scaffold (committed):** `third_party/waypipe/patches/` with
  `.gitkeep` + `README.md`. Convention fixed to `git apply` (README aligned to
  match `waypipe-host.sh` and the guest recipe — the earlier `patch -p1` note is
  gone). Empty, patch level 0.
- **`build/waypipe-host.sh` (committed, bash):** clone pinned `v0.11.0` → apply
  patch queue (`git apply`, ascending filename order) → `cargo fetch` → `meson`
  with the SAME flags as the guest (`lz4/zstd enabled`, `gbm/dmabuf/video
  disabled`) → install to `/opt/katmate/bin/waypipe`. Build-deps are CHECKED
  only (`command -v` + `pkg-config --exists`), never auto-installed (ADR-020);
  no build-dep purge (host is not an appliance). Ephemeral clone in `mktemp -d`
  with a cleanup trap; patch dir resolved relative to the script.
  - **Live build on MINIS:** the only missing host dep was `bindgen` (Arch
    package `rust-bindgen`); after install the build succeeded. Result:
    `waypipe 0.11.0`, `lz4: true, zstd: true, dmabuf: false, video: false`. Gate
    passed.
- **Launch preflight (committed, fish, in `app_web.con`):** reads `WAYPIPE_TAG`
  from `/var/lib/katmate/foundation.meta`, strips leading `v`, compares against
  `waypipe --version` (parsed with `string match -rg`). Placed FIRST — before
  the `lvchange -K -ay` activation block — because it is the cheapest gate (a
  file read, no sudo, no LVM). An initial version had it AFTER activation; the
  negative test exposed the wrong order and it was moved up.
  - **Negative test:** meta temporarily set to `WAYPIPE_TAG=v0.10.0` → preflight
    prints FATAL mismatch and exits BEFORE `activating backing chain`. Meta
    restored to `v0.11.0`.
  - **Positive test:** `waypipe version OK (0.11.0, matches foundation)` prints
    before activation, then normal boot (kernel `6.12.87-dirty` on ttyS0).
- **`ping-client` built on MINIS:** `cargo build --release` in
  `~/katmate-build/bin/ping-client/` — the `error.rs`/`protocol.rs` symlinks into
  `agent/src/` resolved correctly. Binary at
  `bin/ping-client/target/release/ping-client`; `shutdown <cid> [port]`
  subcommand present. (Closes the standing "next immediate step".)

### Notes / cosmetics observed 2026-07-03

- **rsync `--delete` without excludes** still tries to remove MINIS-only
  build output (`trixie-build/`, root-owned) → `Permission denied` noise.
  Harmless (source transferred fine) but a standing wart; a fixed `--exclude`
  set (`.git/ trixie-build/ out/ agent/target/ git-cli.txt`) or a `sync.fish`
  wrapper is the clean fix. NOT yet done.
- **`zoxide` error** in `~/.config/fish/config.fish:81` on MINIS prints on every
  script invocation (`zoxide` not installed there). Non-blocking; guard the line
  (`command -q zoxide; and zoxide init fish | source`) or install it.

## This session (2026-07-02) — ADR-019/020, `foundation.meta` writer

Design/doc session, one implementation slice landed. No new live boot proof;
scope was the waypipe ownership model, the release boundary, and the first
concrete piece of the version-lock machinery.

- **ADR-019 (committed):** waypipe is now a project-maintained *patch-queue
  fork* — one pinned upstream tag (`v0.11.0`) + a KatMate patch queue
  (`third_party/waypipe/patches/`, strip & harden only), both host and guest
  binaries built from the same tree. Host binary lives at
  `/opt/katmate/bin/waypipe`, outside pacman. Drift impossible by construction.
- **`foundation.meta` writer (committed):** `foundation.sh` writes
  `/var/lib/katmate/foundation.meta` at RO-freeze — flat `KEY=value`,
  POSIX-sourceable, no parser needed by the launch preflight. Placed AFTER the
  freeze and AFTER the rollback trap is disarmed: a meta-write failure dies
  loudly (`set -e`) without destroying a valid frozen LV. `WAYPIPE_PATCH_LEVEL`
  counts `*.patch` in `WAYPIPE_PATCHES_DIR` (0 until the scaffold lands).
  `config.sh` gains `FOUNDATION_META` + `WAYPIPE_PATCHES_DIR`;
  `KERNEL_VERSION` is now the declared source for the meta field (not filename
  parse). This is the first of ADR-019's four open items.
- **Existing frozen foundation covered:** meta hand-written on MINIS
  (`WAYPIPE_TAG=v0.11.0`, `KERNEL_VERSION=6.12.87`, patch level 0) so the future
  preflight will not reject the current live foundation. Host waypipe on MINIS
  confirmed `0.11.0`.
- **ADR-020 (committed):** the build-time / install-time boundary is now
  formal. Release = a pre-baked, GPG-signed **ISO** carrying every prebuilt
  component (foundation, app-layers, external vmlinuz, both waypipe binaries);
  install = verify → bake USB → boot → provision, **never build**. No git, no
  toolchain, no fetch of project components on the user's machine — a security
  requirement (network + supply-chain surface at the worst moment), not
  convenience. This scopes ALL pipeline scripts (`foundation.sh`,
  `app-layer.sh`, `waypipe-host.sh`, kernel build) to build-time developer
  tooling whose *output* is the ISO.
- **Ordering correction for the remaining ADR-019 items:** the host build
  script (`waypipe-host.sh`) must come BEFORE the launch preflight — the
  preflight compares against `/opt/katmate/bin/waypipe`, which the host build
  script produces. Preflight was drafted (fish, in `app_web.con`) but parked
  until the host binary exists. Decisions taken for it: compare bare `x.y.z`
  (strip leading `v` both sides); version only, NOT patch level (`waypipe
  --version` does not report the patch queue); hard path `/opt/katmate/bin/
  waypipe`, no fallback to the distro binary.
- **Convention (recorded):** build/pipeline scripts are bash
  (`#!/usr/bin/env bash`); `app_web.con` stays fish (host-side launcher). Guest
  = bash everywhere. Matt uses fish interactively on MINIS + Acer only.

## Proven this session (2026-07-01) — kernel rebuild, three flags, live-validated

Added three config flags to the monolithic microvm kernel `6.12.87` and proved
all three on a live `vm_app_web` boot (CID 5) + GUI RUN. This closes the kernel
technical debt carried since the `make foundation` work.

- **Flags (all `=y`, monolithic — never `=m`):**
  - `CONFIG_HW_RANDOM_VIRTIO=y` — the guest already had `-device
    virtio-rng-device` but no driver, so `getrandom` could block at boot. Now
    paired: device + driver.
  - `CONFIG_SECURITY_LANDLOCK=y` — eliminates the Tracker landlock-ABI warning
    and gives the desired sandboxing primitive. `landlock` was already listed in
    `CONFIG_LSM=` but inert until the code was built in; `CONFIG_LSM` needed no
    edit.
  - `CONFIG_SND_ALOOP=y` — proactive, for the future audio path 3 (snd-aloop +
    thin C daemon → VSOCK 1026 → PipeWire host-side). Audio itself not built yet.
- **Live boot proof (dmesg on ttyS0):**
  - `random: crng init done` @ 10 ms — no getrandom block.
  - `LSM: initializing lsm=capability,landlock,selinux` + `landlock: Up and
    running.`
  - `ALSA device list: #0: Loopback 1` — snd-aloop registers.
  - Boot chain unchanged: `Run /sbin/init` → `[katmate-init] starting (pid 1)`
    → `vm-agent launched as uid 1000`.
- **Landlock user-space proof:** `ping-client run 5 nautilus` → `status=0x00
  (OK)`, nautilus rendered on host Hyprland, and — the key result — the Tracker
  landlock-ABI warning that used to print on ttyS0 is **gone** (absence = pass).
- **Version carries `-dirty`** (`6.12.87-dirty`): the rsync'd source tree is not
  a clean git checkout. Cosmetic; functionally correct. Clean up when the kernel
  source is set up as a proper git checkout on MINIS. Archive filename kept as
  `vmlinuz-katmate-microvm-amd64-6.12.87` (no `-dirty` in the name) but `uname
  -r` in the guest reports `-dirty`.
- **Build migrated to MINIS.** Source tree rsync'd Acer → MINIS
  (`~/src/kernel/linux-6.12.y/`); built with `make -j16` on the Ryzen after the
  Acer (N4200, passive) thermal-shut-down twice mid-build at ~34 °C ambient (LJ
  heatwave), corrupting object files. This is NOT a project migration — git +
  GPG signing + source-of-truth stay on Acer. New vmlinuz + config archived to
  `/home/host/katmate-kernels/` on MINIS.

## Proven this session (2026-06-29 evening) — `make foundation` from scratch

`build/foundation.sh` migrated from the pre-revision **qcow2/nbd** mechanism to
**LVM-thin**, matching `app-layer.sh`. The script now builds and freezes
`vg0/vm_tpl_foundation` from nothing and codifies the real procedure (no longer
diverges from live state — the old script still installed systemd + a vm-agent
systemd unit, which was the pre-06-27 plan, not reality).

- **Kernel as external vmlinuz, NOT `.deb`.** Dropped the `.deb`/dpkg/initrd
  detour (meaningless under monolithic `-kernel` boot with no `/lib/modules`).
  `config.sh`: `KERNEL_DEB` → `KERNEL_VMLINUZ`; `Makefile` copies the vmlinuz
  from `KERNEL_SRC_DIR` (hardcoded `/home/host/katmate-kernels`, MINIS is the
  only build host) into `out/`. Aligns with ARCHITECTURE.md update-flow §4
  (kernel rides as the external `-kernel`, not in-image).
- **systemd out, katmate-init in (in the RO base).** foundation.sh compiles
  `init/katmate-init.c` static and bakes it to `/sbin/init` (per the init header:
  "bake to /sbin/init; no init= cmdline needed"). This is what the Apr-13 image
  never did — its `/sbin/init` was still a systemd symlink, which is why every
  layer booted systemd until now.
- **waypipe 0.11 from source + purge build-deps** (carried over from old script,
  ADR-008). Validated live: `waypipe --version` → `lz4: true, zstd: true`.
- **user 1000 via direct passwd/group/shadow write** — `useradd`/`passwd` are
  NOT in the minbase image, so the first build silently skipped the account
  (`|| true` swallowed "command not found"). Now written directly to the account
  files (no tooling, smaller TCB; locked `!*` password; `/home/user` is the
  per-instance rw LV, not created here).
- **Mount ordering fix:** pseudo-fs (`/proc`/`/sys`/`/dev`) must mount AFTER
  debootstrap (a fresh ext4 has no such dirs yet). `lib.sh:mount_root` does both
  at once (correct for app-layer.sh, which mounts an already-bootstrapped snap);
  foundation.sh stages the mounts manually.
- **`lib.sh`** — added `lv_thin_create` (`lvcreate -T pool -V size`) beside
  `lv_snapshot_create`; reuses the same `SNAP_CREATED` rollback slot, so
  `cleanup()` is unchanged. Mid-build failure removes the half-built LV.

**Validated live:** `/sbin/init` = static ELF (not systemd symlink); waypipe
lz4+zstd true; vm-agent + waypipe at `/usr/local/bin`; `user:x:1000:1000:...` in
passwd. Boot log: `Run /sbin/init as init process` → `[katmate-init] starting
(pid 1)` → `[katmate-init] vm-agent launched as uid 1000 (pid 60)`. `ping-client
ping 5` → `status=0x00 (OK)`. **Foundation pipeline complete (part of
ROADMAP build-order step 1).**

> NOTE: flaky `deb.debian.org` (fastly) timeouts hit `libicu76` mid-install
> twice during bring-up — retry cleared it. This is the standing argument for the
> deferred `snapshot.debian.org` pin (ADR-011) once `katmate-update` makes
> determinism matter.

## Proven this session (2026-06-29) — app-layer build pipeline on LVM-thin

Migrated `build/` pipeline + `Makefile` from the pre-revision qcow2/nbd
mechanism to the LVM-thin mechanism (ADR-010 rev 2026-06). The scripts now
codify the proven manual procedure instead of diverging from it.

- **`build/app-layer.sh`** — `qemu-img create -f qcow2 -b foundation.qcow2`
  + `nbd_connect` replaced by `lvcreate -s --name vm_app_<type>
  vg0/vm_tpl_foundation` → `lvchange -K -ay` → mount LV directly → chroot apt
  install → umount → `lvchange --permission r` freeze. Refuses to clobber an
  existing app-layer; `cleanup` trap removes a half-built snapshot on mid-build
  failure (`SNAP_CREATED`/`FREEZE_DONE` state).
- **`build/lib.sh`** — nbd helpers replaced by `lv_snapshot_create` /
  `lv_activate` (`-K -ay`) / `lv_freeze` (`-p r`) / `lv_deactivate`.
- **`build/config.sh`** — nbd/qcow2 paths dropped; `VG`/`POOL`/`FOUNDATION_LV`/
  `APP_LV_PREFIX` added. `SNAPSHOT` apt-pin retained but explicitly DEFERRED and
  unused (per ADR-011 build note).
- **`Makefile`** — `.qcow2` file targets → `.PHONY app-<type>` targets (LVs have
  no timestamp); vm-agent hook fixed from `gcc vm-agent.c` to Rust `cargo build`
  (foundation step only — app-layers need neither kernel nor agent).
- Scripts marked executable in git (`update-index --chmod=+x`) so rsync carries
  mode 755 (the `Permission denied` that bit once is fixed at source).

**Gate passed:** `make app-web` (rebuilt) and `make app-vault` (new) both
produce `Vri-a-tz-k` thin snapshots of `vm_tpl_foundation`. Two manifest axes
validated (web = network/ephemeral-capable; vault = offline/persistent). ADR-014
dual axes realized; **ROADMAP build-order step 1 closed.**

## Proven earlier (2026-06-27) — live on MINIS, CID 5

The whole app-layer hardening slice, validated against `ping-client`:

- **PING** → `status=0x00 OK` — VSOCK control channel (port 1025) live.
- **RUN nautilus** → `status=0x00 OK` — agent spawns waypipe; host-side
  `waypipe ... client-conn -c lz4` connection established (render path live;
  lz4 matches guest `lz4:true`). nautilus rendered without dbus-run-session.
- **SHUTDOWN** → `status=0x00 OK` → clean teardown observed on ttyS0:
  agent → init socket → init kills children → `/home` (vdb) unmounted →
  root (vda) re-mounted RO → `reboot(RB_AUTOBOOT)` → triple-fault →
  QEMU (`-no-reboot`) exits cleanly. No hard kill.

### Architecture decided 2026-06-27 (ADR-worthy, not yet written)

**systemd removed from the microvm guest.** The guest's only root process is a
custom statically-linked ANSI C `katmate-init` as PID 1. The earlier plan
(state.md ≤06-22) to ship vm-agent as a systemd **user** unit is abandoned —
building on systemd would be future regression work, since systemd is slated to
leave the appliance entirely.

`katmate-init` responsibilities (and nothing more): mount pseudo-fs + the
persistent `/home` rw LV (vdb, ext4); set up `XDG_RUNTIME_DIR` for uid 1000;
open an AF_UNIX SOCK_SEQPACKET control socket (`/run/katmate-init.sock`); launch
vm-agent dropped to uid 1000 (signalfd+poll supervision, zombie reaping); on
shutdown request, kill children → unmount `/home` → sync → remount root RO →
`reboot(RB_AUTOBOOT)`. Static ANSI C, baked to `/sbin/init`. No NSS lookups
(uid 1000 hardcoded; user 1000 baked into image).

**Shutdown authority lives in init, not a setuid helper.** vm-agent is uid 1000
and cannot call `reboot(2)`; it delegates. `handle_shutdown` now acks OK, then
`signal_init_shutdown()` connects `/run/katmate-init.sock` and sends `SHUTDOWN`.
init verifies the peer credential (uid 1000) before acting. **`vm-power-helper`
removed entirely** (the `POWER_HELPER` const + setuid binary are gone — one less
root binary, smaller TCB). This is the "B3" path chosen after ACPI was rejected.

**No ACPI in the microvm.** ACPI was considered for clean shutdown but rejected:
it would pull SeaBIOS instead of qboot, slower boot, larger firmware surface —
against the minimal-TCB philosophy. With no ACPI there is no clean power-off
path, so shutdown uses guest triple-fault + host `-no-reboot` (QEMU exits on the
reboot event). The next kernel is built without ACPI deliberately.

**File transfer goes through the agent, not 9p.** Each VM has its own rw LV
mounted as `/home` (persistent per-VM storage); host↔guest file exchange is the
agent's FILEGET/FILEPUT over the VSOCK control channel (Qubes-`qvm-copy` style,
not a shared folder). 9p hostshare is dev-only and deliberately **not** mounted
by init (isolated under `#ifdef DEV_HOSTSHARE` for later if ever needed).

### Files changed 2026-06-27 (committed to Codeberg)

- `init/katmate-init.c` — new. ~330 lines static ANSI C. Compiles clean
  (`-Wall -Wextra`), also under `-DUSE_DBUS_SESSION`.
- `agent/src/protocol.rs` — `POWER_HELPER` removed; added `INIT_SOCK`
  (`/run/katmate-init.sock`) + `SHUTDOWN_CMD` (`b"SHUTDOWN"`).
- `agent/src/main.rs` — `handle_shutdown` rewritten to delegate via
  `signal_init_shutdown()` (AF_UNIX SEQPACKET → init socket). `handle_run`
  untouched (bare waypipe). `.bak-pre-initsock` backups kept on MINIS.
- `ping-client/src/main.rs` — added `shutdown <cid> [port]` subcommand
  (`Cmd::Shutdown`, no args), updated usage.
- `app_web.con` — new parametrised fish launcher (details under Invariants).

