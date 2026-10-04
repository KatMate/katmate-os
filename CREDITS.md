# Credits

## CYBRland

The desktop profile is based on **CYBRland** by Scherrer (`scherrer-txt`),
<https://github.com/scherrer-txt/cybrland>, a Hyprland configuration licensed
under the GNU General Public License, version 3. KatMate's version is adapted
from it: ported to Sway and substantially modified. The files below are
KatMate's adaptations, not CYBRland's own files.

Files based on CYBRland:

| File | Based on |
|---|---|
| `desktop/sway/config` | CYBRland's Hyprland configuration (`vars.conf`, `theme.conf`, `hyprland.conf`), ported to Sway |
| `desktop/waybar/style-sway.css` | CYBRland's waybar stylesheet (`style.css`), which it imports and extends for Sway |
| `desktop/waybar/config-sway.jsonc` | CYBRland's waybar configuration (`config.jsonc`), as a Sway counterpart |
| `desktop/waybar/modules-sway.jsonc` | CYBRland's waybar module definitions (`modules.jsonc`), with Sway equivalents of its Hyprland modules |
| `desktop/bin/sway-session` | the environment section of CYBRland's `hyprland.conf`, whose values it carries over |
| `desktop/wallpapers/*.jpg` | CYBRland's wallpapers, reworked by the operator for dark, text-oriented sessions with transparent windows |

The port and what it dropped are described in
[desktop/README.md](desktop/README.md) § *What this profile is a port of*.
CYBRland's own files that the desktop shares with the Hyprland profile
(`modules.jsonc`, `style.css`, the rofi themes and scripts) are not in this
repository ([desktop/README.md](desktop/README.md) § *Shared with the
Hyprland dev profile*).
