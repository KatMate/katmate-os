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
│   └── style-sway.css              @imports style.css, adds .focused
├── bin/
│   ├── sway-session                env wrapper — sway has no `env =`
│   ├── sway-quiet                  greetd entry's Exec: clears the tty, execs sway-session
│   ├── km-shot                     region screenshot (replaces hyprshot)
│   ├── km-launch                   the menu's katmate-launch wrapper: notifies on failure
│   └── km-scratch                  scratchpad toggle (replaces pyprland)
├── wallpapers/
│   ├── default.jpg                 the one sway/config is wired to
│   └── wall_km_*.jpg               alternatives (CREDITS.md)
└── greetd/
    ├── config.toml                 reference copy of /etc/greetd/config.toml
    └── wayland-sessions/           reference copies of the .desktop entries
        ├── sway.desktop
        └── hyprland.desktop
```


## Deployment

Two classes of file, deployed differently.

**User files are symlinked**, so this tree is the only original. On MINIS
the links point into the synced copy, so an edit made through them is removed
by the next `rsync --delete`: edit in the git tree and sync. Same anti-drift
pattern as `~/net-sys.con`.

The source is `~/katmate-build/`, not `~/katmate-os/`, because MINIS holds
the copy synced one-way from the Acer's git tree, not the git tree itself
([CLAUDE.md](../CLAUDE.md) § *The two machines*).

```sh
ln -s ~/katmate-build/desktop/sway/config               ~/.config/sway/config
ln -s ~/katmate-build/desktop/waybar/config-sway.jsonc  ~/.config/waybar/
ln -s ~/katmate-build/desktop/waybar/modules-sway.jsonc ~/.config/waybar/
ln -s ~/katmate-build/desktop/waybar/style-sway.css     ~/.config/waybar/
ln -s ~/katmate-build/desktop/waybar/modules-katmate.jsonc ~/.config/waybar/
ln -s ~/katmate-build/desktop/waybar/katmate-menu.xml      ~/.config/waybar/
ln -s ~/katmate-build/desktop/bin/km-shot               ~/.local/bin/
ln -s ~/katmate-build/desktop/bin/km-scratch            ~/.local/bin/
ln -s ~/katmate-build/desktop/bin/km-launch             ~/.local/bin/
```

The launcher menu (`custom/katmate`) needs waybar ≥ 0.11 (`menu`,
`menu-file`, `menu-actions`). It does nothing on its own: each item runs
`/home/host/.local/bin/km-launch …`, the symlink above, which runs
`sudo -n /usr/lib/katmate/katmate-launch …` and, on a non-zero exit, shows
the last FATAL line as a critical notification (`notify-send`, so libnotify
and swaync, as for `km-shot`). So it also needs that executable and its
sudoers rule ([HOST-CONFIG.md](../docs/HOST-CONFIG.md) § 13). Its
`menu-file` names `/home/host/.config/waybar/katmate-menu.xml`, the symlink
above, by absolute path.

**System files are copied**, never symlinked. `/etc/greetd/config.toml` is read
by the unprivileged `greeter` user and sits on a privilege boundary; a symlink
into a user's home directory there would be a mistake. The copies in
`greetd/` are reference only — deployment is manual until the installer owns
it ([ROADMAP.md](../ROADMAP.md) step 5).

```sh
sudo install -m 755 desktop/bin/sway-session /usr/local/bin/
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

`~/.config/waybar/{modules.jsonc,style.css,svg/}`, the rofi themes and scripts,
and swaync are used by both profiles and are **not** in this tree. They live in
`~/.config/` and remain scherrer-txt's files.

Three rofi scripts called `hyprctl` and were made compositor-neutral rather
than forked: `powermenu` now uses `loginctl terminate-session`, `keybindings`
sets a class at launch instead of an inline Hyprland window rule. The
`wallpaper` script is still Hyprland-only and was already broken there — it
targets `DP-2`, an output that exists on neither reference machine.


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
