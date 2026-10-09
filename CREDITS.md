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
| `desktop/waybar/style-sway.css` | CYBRland's waybar stylesheet (`style.css`), extended for Sway on top of `style-cybrbar.css`, which it imports |
| `desktop/waybar/config-sway.jsonc` | CYBRland's waybar configuration (`config.jsonc`), as a Sway counterpart |
| `desktop/waybar/modules-sway.jsonc` | CYBRland's waybar module definitions (`modules.jsonc`), with Sway equivalents of its Hyprland modules |
| `desktop/waybar/modules-cybrbar.jsonc` | CYBRland's waybar module definitions (`modules.jsonc`), pruned to the modules the sway bar shows, with their application-launching click handlers removed |
| `desktop/waybar/style-cybrbar.css` | CYBRland's waybar stylesheet (`style.css`), pruned to the rules and colours of those modules |
| `desktop/waybar/svg/no1-right.svg` | CYBRland's `svg/no1-right.svg`, unchanged |
| `desktop/bin/sway-session` | the environment section of CYBRland's `hyprland.conf`, whose values it carries over |
| `desktop/wallpapers/*.jpg` | wallpapers from **cybrpapers** (<https://github.com/cybrcore/cybrpapers>, CC0 1.0, the collection CYBRland uses), reworked by the operator for dark, text-oriented sessions with transparent windows |

The port and what it dropped are described in
[desktop/README.md](desktop/README.md) § *What this profile is a port of*.
The Hyprland dev profile's own copies of CYBRland's files (`modules.jsonc`,
`style.css`, the rofi themes and scripts) are not in this repository; the sway
bar uses the pruned copies above ([desktop/README.md](desktop/README.md) §
*Shared with the Hyprland dev profile*).

## KatMate branding

The KatMate logos, including `desktop/plymouth/logo.png` and its 256 px derivative `desktop/plymouth/logo-256.png`, are original hand-made work by **Natasha Qualizza**, a professional designer, created for KatMate before and independently of any AI tooling.

`desktop/waybar/svg/katmate-mark.svg`, the mark on the bar's power-menu button, is not a new design: it is a mechanical single-colour trace of `desktop/plymouth/logo.png`'s alpha channel (bitmap tracing with potrace), made in an AI-assisted orchestrator session on 2026-10-09. As a derivative of the logo it falls under the same terms as the logos.

The logos and their derivatives named above are **not** covered by the repository licence (GPL-3.0): all rights assigned to and held by the KatMate project; all rights reserved. Forks may use the code, but not the KatMate name or logos.
