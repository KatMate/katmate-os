# Desktop layer

The desktop profile for KatMate OS. Sway is the single shipped compositor
([ADR-016](../docs/DECISIONS.md#adr-016)); the host compositor is inside the
TCB because it draws the domain indicator.

This tree holds the *user-facing* half of the desktop, and the wallpapers.
Themes and fonts are deliberately absent — see "Not in git" below.


## Layout

```
desktop/
├── sway/
│   └── config                      compositor config
├── waybar/
│   ├── config-sway.jsonc           bar layout (sway session)
│   ├── modules-sway.jsonc          sway/{workspaces,window,language}
│   ├── modules-katmate.jsonc       custom/katmate: the alpha's launcher menu
│   ├── katmate-menu.xml            its GTK builder menu (ids = menu-actions keys)
│   ├── power-menu.xml              custom/arch's power menu (Power off, Reboot, Suspend, Exit)
│   ├── modules-cybrbar.jsonc       CYBRland's module definitions, pruned to this bar
│   ├── style-cybrbar.css           CYBRland's stylesheet, pruned to this bar
│   ├── svg/no1-right.svg           the one powerline arrow the bar draws
│   └── style-sway.css              @imports style-cybrbar.css, adds .focused
├── bin/
│   ├── sway-session                env wrapper — sway has no `env =`
│   ├── sway-quiet                  greetd entry's Exec: clears the tty, execs sway-session
│   ├── km-shot                     region screenshot (replaces hyprshot)
│   ├── km-launch                   the menu's katmate-launch wrapper: notifies on failure
│   └── km-scratch                  scratchpad toggle; nothing calls it since 2026-10-05
├── wallpapers/
│   ├── default.jpg                 the one sway/config is wired to
│   └── wall_km_*.jpg               alternatives (CREDITS.md)
└── greetd/
    ├── config.toml                 reference copy of /etc/greetd/config.toml
    └── wayland-sessions/           reference copies of the .desktop entries
        └── sway.desktop
```


## Deployment

This section is the **dev-host** procedure. A fresh install is deployed by
`installer/install.sh`, which copies the same files to the same system paths
(and `sway/config` to `/etc/sway/config`, KatMate's own; a `.pacnew` on a
sway upgrade is accepted), so nothing below is run on an installed host
(operator ruling R13, 2026-10-05).

Two classes of file, deployed differently.

**The sway config is symlinked**, so this tree is the only original. On MINIS
the link points into the synced copy, so an edit made through it is removed
by the next `rsync --delete`: edit in the git tree and sync. Same anti-drift
pattern as `~/net-sys.con`.

The source is `~/katmate-build/`, not `~/katmate-os/`, because MINIS holds
the copy synced one-way from the Acer's git tree, not the git tree itself
([CLAUDE.md](../CLAUDE.md) § *The two machines*).

```sh
ln -s ~/katmate-build/desktop/sway/config               ~/.config/sway/config
```

**Everything the sway config and the bar name is at a system path** (operator
ruling 2026-10-05, D8), the layout the installer deploys, so nothing names
a user's home:

| Path | From | Mode |
|---|---|---|
| `/etc/xdg/waybar/config-sway.jsonc`, `modules-cybrbar.jsonc`, `modules-sway.jsonc`, `modules-katmate.jsonc`, `style-cybrbar.css`, `style-sway.css`, `svg/no1-right.svg` | `desktop/waybar/` | 644 |
| `/usr/share/katmate/waybar/katmate-menu.xml`, `power-menu.xml` | `desktop/waybar/` | 644 |
| `/usr/local/bin/km-launch`, `/usr/local/bin/km-shot` | `desktop/bin/` | 755 |

Until the installer owns them, a dev host deploys them by hand from the synced
copy, as root, and **again after every sync** that changes one of them: they
are copies, so a sync alone does not reach them.

```sh
cd ~/katmate-build
sudo install -m 644 -D -t /etc/xdg/waybar/ \
    desktop/waybar/config-sway.jsonc desktop/waybar/modules-cybrbar.jsonc \
    desktop/waybar/modules-sway.jsonc desktop/waybar/modules-katmate.jsonc \
    desktop/waybar/style-cybrbar.css desktop/waybar/style-sway.css
sudo install -m 644 -D -t /etc/xdg/waybar/svg/ desktop/waybar/svg/no1-right.svg
sudo install -m 644 -D -t /usr/share/katmate/waybar/ desktop/waybar/katmate-menu.xml desktop/waybar/power-menu.xml
sudo install -m 755 -D -t /usr/local/bin/ desktop/bin/km-launch desktop/bin/km-shot
```

The symlinks earlier versions of this file placed in `~/.config/waybar/` and
`~/.local/bin/` are no longer read and can be removed. `/etc/xdg/waybar/`
also holds the waybar package's own `config.jsonc` and `style.css`; no file
deployed here takes either name.

The launcher menu (`custom/katmate`) needs waybar ≥ 0.11 (`menu`,
`menu-file`, `menu-actions`). It does nothing on its own: each item runs
`/usr/local/bin/km-launch …`, which runs
`sudo -n /usr/lib/katmate/katmate-launch …` and, on a non-zero exit, shows
the last FATAL line as a critical notification (`notify-send`, so libnotify
and swaync, as for `km-shot`). So it also needs that executable and its
sudoers rule ([HOST-CONFIG.md](../docs/HOST-CONFIG.md) § 13). Its
`menu-file` is `/usr/share/katmate/waybar/katmate-menu.xml`.

**System files are copied**, never symlinked. `/etc/greetd/config.toml` is read
by the unprivileged `greeter` user and sits on a privilege boundary; a symlink
into a user's home directory there would be a mistake. The copies in
`greetd/` are reference only — deployment is manual until the installer owns
it ([ROADMAP.md](../ROADMAP.md) step 5).

```sh
sudo install -m 755 desktop/bin/sway-session desktop/bin/sway-quiet /usr/local/bin/
sudo install -m 644 desktop/greetd/config.toml /etc/greetd/
sudo install -m 644 -D desktop/greetd/wayland-sessions/*.desktop -t /etc/greetd/sessions/
sudo install -m 644 -D desktop/wallpapers/*.jpg -t /usr/share/backgrounds/katmate/
```

The wallpapers are copied rather than symlinked for a smaller reason than
greetd's: `sway/config` names `/usr/share/backgrounds/katmate/default.jpg`, a
path that does not depend on the user. If it is absent, sway falls back to the
solid `$no0` that `output * bg` names as its fallback colour.

`/etc/greetd/sessions/` rather than `/usr/share/wayland-sessions/` on purpose:
the latter is package-owned, so a `sway` or `hyprland` upgrade can add entries
to the login menu. Entries that bypass `sway-session` start the compositor
without the Qt/GTK/XDG environment, and the resulting breakage is subtle.

Executable bits matter and `micro` strips them on save. After editing anything
under `bin/`, `chmod +x` before `git add`.


## Keyboard layout: `/etc/sway/config.d/10-keyboard.conf`

`sway/config` does not choose the keyboard layout. It sets `xkb_layout "us"`
as a default and ends with `include /etc/sway/config.d/*`. The installer
writes the machine's layout there (the installer pass). The contract:

- **Path:** `/etc/sway/config.d/10-keyboard.conf`, `root:root 0644`. It is
  written by the installer, never by hand.
- **Content:** exactly one block, and nothing else:

  ```
  input type:keyboard {
      xkb_layout  "<XKB layout>[,<XKB layout>…]"
      xkb_variant "<XKB variant>[,…]"      # optional
  }
  ```

- **The value is an XKB layout name** (`si`, `de`, `us`), as listed by
  `localectl list-x11-keymap-layouts`. It is **not** the console keymap that
  `vconsole.conf` takes (`slovene`, `de-latin1`). The two name spaces differ,
  and a console keymap name given to `xkb_layout` gives no layout.
- **Absent file:** the session starts on `us`, and nothing fails.
- `xkb_options` and `xkb_numlock` stay in `sway/config`. sway merges a later
  `input` block for the same identifier over the earlier one, so the file
  replaces only what it names.

UNVERIFIED on a running sway: the merge of the two `input` blocks, and that
an absent file leaves the include silent. Settled on MINIS by
`swaymsg -t get_inputs` reading the file's layout with the file present, and
`us` with it renamed away.

## What this profile is a port of

CYBRland by scherrer-txt (GPL-3.0), originally a Hyprland configuration.
Ported to Sway 2026-07-26. Values carried over verbatim from `vars.conf` and
`theme.conf`: 1 px border, 4/8 px gaps, `#2DD4BF` accent on `#030408`,
GeistMono Nerd Font.

Three decorations do not survive the port, because Sway has none of them:

| dropped | Hyprland setting |
|---|---|
| coloured glow | `shadow { range 30, render_power 5, color #2DD4BF20 }` |
| bevelled corners | `rounding 28, rounding_power 1.0` |
| background blur | `blur { size 6, passes 4, noise 0.05 }` |

SwayFX would restore all three and was rejected: it is a fork requiring a
manual rebase per Sway release (0.5 sits on 1.10.1 while upstream is at 1.12),
and `scenefx` replaces the wlroots scene graph rather than merely adding a
render pass. Both properties are wrong for a component inside the TCB.

Animations were already disabled upstream (`animations { enabled = false }`),
so nothing was lost there.


## Domain indicator

Not implemented. The section is reserved in `sway/config`.

Sway has no per-window border *colour* — `client.focused` is global. This does
not block the indicator, because inactive windows carry no visible border, so
the colour of the focused window is the only one that matters and a single
global value suffices. A host-side process subscribed to sway IPC issues
`swaymsg client.focused …` on each focus change.

Channels available, all keyed on PID, which the host knows because it spawned
the waypipe client. None of them is reachable by a guest:

| channel | mechanism |
|---|---|
| border width | `for_window [pid=N] border pixel <n>` |
| opacity | `for_window [pid=N] opacity <f>` |
| mark | `swaymsg [pid=N] mark <domain>` + `show_marks yes` |
| workspace | host moves the window by PID |
| focused colour | `swaymsg client.focused …`, global, one at a time |

Nothing here uses `app_id` or window title — both are guest-controlled.

Known limitation of the colour channel: between a focus change and the IPC
round trip the border still shows the previous domain's colour for roughly one
frame.

Two facts are untested and gate the ADR:

1. whether Sway accepts `#RRGGBBAA` in `client.*` (an exact match for
   Hyprland's `col.inactive_border` alpha `00` would be `#29BECC00`);
2. whether `show_marks` draws anything under `border pixel`, which has no
   titlebar — if not, marks require `default_border normal`.


## Shared with the Hyprland dev profile

Only swaync is shared now. The sway bar no longer reads
`~/.config/waybar/{modules.jsonc,style.css,svg/}`: it uses pruned copies of
them, tracked here (`modules-cybrbar.jsonc`, `style-cybrbar.css`, `svg/`,
credited in `CREDITS.md`). The Hyprland profile's own copies stay in
`~/.config/` and remain scherrer-txt's files.

The sway profile uses no rofi (operator ruling 2026-10-05): applications come
from the waybar KatMate menu, and nothing in `sway/config` binds a rofi
script. The rofi themes and scripts in `~/.config/rofi/` are the Hyprland
profile's alone.


## Not in git

- `~/.config/sway/walls/` — local wallpapers, binary, third-party provenance;
  nothing in `sway/config` reads them. The shipped wallpapers are tracked in
  `wallpapers/` since 2026-10-04 (`CREDITS.md` names their source).
- the Hyprland/CYBRland profile itself — a dev/demo profile, not a release
  artifact ([ADR-016](../docs/DECISIONS.md#adr-016))


## Reference machine

MINIS (MINISFORUM UM870). Outputs are not configured in this tree:
`sway/config` includes `outputs.conf`, which is local to the machine and
not tracked.
