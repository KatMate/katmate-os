# Trust-boundary audit — 2026-09-18

> A read-only audit of this repository, run on 2026-09-18 in a delegated
> session. **No files were modified by it**; it took no measurement on MINIS and
> ran nothing — every finding is read from the tree.
>
> **Line numbers are against that day's HEAD**, which was the `audit-fable`
> branch, and are not corrected as the tree moves. A finding is resolved by a
> later record, never by editing this file: like [`docs/SESSIONS.md`](https://github.com/KatMate/katmate-os/blob/v0.2.0-alpha2/docs/SESSIONS.md), this is a
> record of what was true on the day it was written.
>
> Thirteen findings, ordered most severe first. The report is reproduced
> verbatim below, exactly as the audit emitted it.
>
> Cited by [ADR-036](../adr/ADR-036.md), which reasons from these findings
> about *placement* and uses none of them as a task.

## The report, verbatim

Audit complete. No files were modified. Findings are ordered most severe first. Line numbers are against HEAD of `audit-fable`.

1. **`desktop/sway/config:316-329`** — The domain indicator ADR-026 makes the sole trustworthy identity carrier is a placeholder ("Nothing here yet"), so every window rule below it is the de facto identity path and all of those key on guest-controlled `app_id` and title. — A hostile guest's forwarded window is pixel-identical to a host window, and every finding below inherits from this.

2. **`desktop/sway/config:302`** — A window whose `app_id` is `xfce-polkit` is floated exactly like the host polkit authentication agent. — A compromised guest sets that `app_id` on a waypipe-forwarded window and presents a credential prompt indistinguishable from the host's, harvesting the operator's password.

3. **`desktop/waybar/config-sway.jsonc:34` and `desktop/waybar/modules-sway.jsonc:23-30`** — The bar renders the focused window's title via `sway/window`, which ADR-026 point 1 states "is never used" precisely because it shows guest-controlled text, and the `rewrite` rules decorate a title ending in `- Mozilla Firefox` with the host Firefox glyph. — A guest window can claim any host application's name in the TCB status bar.

4. **`desktop/sway/config:284`** — Any window titled `Save File…`, `Open File…` etc. is centered and floated like a host file chooser. — A guest window impersonates a host save dialog and captures paths or documents the operator believes are going to the host.

5. **`desktop/bin/km-scratch:50-51`** — The scratchpad toggle decides whether the host tool is already running by grepping `swaymsg -t get_tree` for a matching `app_id`. — A guest window carrying `scratchpad-btop` or any bound `app_id` makes the host command never launch and shows the guest window in its place.

6. **`desktop/sway/config:340`** — `wl-paste --watch cliphist store` persists every clipboard selection, including those set by a focused guest window, into host clipboard history with no domain tag. — A guest plants a payload such as a shell command with a trailing newline that later resurfaces from the host picker and is pasted into a host terminal.

7. **`docs/DECISIONS.md:2156-2157`** (the `waypipe-client` user unit itself is untracked) — The host listener `waypipe -s 1024 --vsock … client-conn` accepts on port 1024 from any CID with no peer check; there is no authentication step before waypipe starts parsing the guest's Wayland stream into the host compositor. — Any VM, netVM included (see gap 12's mirror case), can open arbitrary windows in the host session and drive the compositor's protocol parser.

8. **`app_web.con:122` and `net-sys.con:16`** — `-serial mon:stdio` writes the guest console raw to the operator's terminal, as root for netVM. — A guest emits terminal control sequences (OSC 52 clipboard write, title changes, output spoofing) into the host terminal emulator.

9. **`agent/crates/ping-client/src/main.rs:152-155`** — A response payload from the guest is printed verbatim to stdout if it is valid UTF-8. — A guest agent returns up to 100 MiB of terminal escape sequences that execute in the operator's terminal.

10. **`agent/crates/katmate-protocol/src/frame.rs:385-393` with `agent/crates/ping-client/src/main.rs:137`** — The host reads the guest's `payload_len` and allocates up to `MAX_FILE_SIZE` before any content arrives, on a socket with no read timeout. — A guest pins 100 MiB per connection and stalls the host client, and therefore the future launch daemon built on this codec, indefinitely.

11. **`host/usr/lib/systemd/system/katmate-sys-driver@.service:126-127,149`** — netVM's console is journaled under the unit's own identifier with no distinction from host-side `ExecStartPre` diagnostics. — A compromised netVM forges lines that read as `katmate-activate-lvs` or `katmate-generate-env` output, or floods the host journal.

12. **`manifests/netvm.conf.d/etc/nftables.conf:36,53`** — Input and forward accept the aggregate `10.100.1.0/24` with no per-link `iifname` binding and no reverse-path check in `30-netvm-forward.conf`. — An AppVM spoofs another AppVM's `/32` source address to poison netVM conntrack and hijack or black-hole that peer's return traffic, and reaches every listener in netVM.

13. **`desktop/sway/config:309`** — A fullscreen window with `app_id` `mpv` or `celluloid` inhibits host idle. — A guest keeps the host from locking the screen for as long as it wishes.
