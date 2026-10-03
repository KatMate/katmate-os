# Credits

## CYBRland

The Sway and waybar styling of the desktop profile, and one session script,
are derived from **CYBRland** by Scherrer (`scherrer-txt`),
<https://github.com/scherrer-txt/cybrland>, a Hyprland configuration licensed
under the GNU General Public License, version 3.

The derived files:

| File | Derived from |
|---|---|
| `desktop/sway/config` | CYBRland's Hyprland configuration (`vars.conf`, `theme.conf`, `hyprland.conf`), ported to Sway |
| `desktop/waybar/style-sway.css` | CYBRland's waybar stylesheet (`style.css`), which it imports and extends |
| `desktop/bin/sway-session` | the environment section of CYBRland's `hyprland.conf`, values carried over verbatim |

The port and what it dropped are described in
[desktop/README.md](desktop/README.md) § *What this profile is a port of*.
CYBRland's own files that the desktop shares with the Hyprland profile
(`modules.jsonc`, `style.css`, the rofi themes and scripts) are not in this
repository ([desktop/README.md](desktop/README.md) § *Shared with the
Hyprland dev profile*).
