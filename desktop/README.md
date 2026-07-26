# Desktop layer

The desktop profile for KatMate OS. Sway is the single shipped compositor
([ADR-016](../docs/DECISIONS.md#adr-016)); the host compositor is inside the
TCB because it draws the domain indicator.

This tree holds the *user-facing* half of the desktop. Wallpapers, themes and
fonts are deliberately absent — see "Not in git" below.


## Layout

```
desktop/
├── sway/
│   └── config                      compositor config
├── waybar/
│   ├── config-sway.jsonc           bar layout (sway session)
│   ├── modules-sway.jsonc          sway/{workspaces,window,language}
│   └── style-sway.css              @imports style.css, adds .focused
├── bin/
│   ├── sway-session                env wrapper — sway has no `env =`
│   ├── km-shot                     region screenshot (replaces hyprshot)
│   └── km-scratch                  scratchpad toggle (replaces pyprland)
└── greetd/
    ├── config.toml                 reference copy of /etc/greetd/config.toml
    └── sessions/                   reference copies of the .desktop entries
        ├── katmate-sway.desktop
        └── hyprland-quiet.desktop
```


## Deployment

Two classes of file, deployed differently.

**User files are symlinked**, so this tree is the only original and editing
the live config edits the repo. Same anti-drift pattern as `~/net-sys.con`.

```sh
ln -s ~/katmate-os/desktop/sway/config               ~/.config/sway/config
ln -s ~/katmate-os/desktop/waybar/config-sway.jsonc  ~/.config/waybar/
ln -s ~/katmate-os/desktop/waybar/modules-sway.jsonc ~/.config/waybar/
ln -s ~/katmate-os/desktop/waybar/style-sway.css     ~/.config/waybar/
ln -s ~/katmate-os/desktop/bin/km-shot               ~/.local/bin/
ln -s ~/katmate-os/desktop/bin/km-scratch            ~/.local/bin/
```

**System files are copied**, never symlinked. `/etc/greetd/config.toml` is read
by the unprivileged `greeter` user and sits on a privilege boundary; a symlink
into a user's home directory there would be a mistake. The copies in
`greetd/` are reference only — deployment is manual until the installer owns
it ([ROADMAP.md](../ROADMAP.md) step 5).

```sh
sudo install -m 755 desktop/bin/sway-session /usr/local/bin/
sudo install -m 644 desktop/greetd/config.toml /etc/greetd/
sudo install -m 644 -D desktop/greetd/sessions/*.desktop -t /etc/greetd/sessions/
```

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

- `~/.config/sway/walls/` — wallpapers, binary, third-party provenance
- the Hyprland/CYBRland profile itself — a dev/demo profile, not a release
  artifact ([ADR-016](../docs/DECISIONS.md#adr-016))


## Reference machine

Acer ES1-633, single output `eDP-1`. The MINIS two-output block
(`DP-3` @ 0x0, `HDMI-A-1` @ 1920x0) is not written yet.
