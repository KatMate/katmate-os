# RAIL tests

Test records for Windows application windows via RDP RemoteApp (RAIL,
MS-RDPERP). The plan these tests serve is `ROADMAP.md` § *Windows application
windows via RDP RemoteApp*. Newest first.

## RAIL test w2 — Word through the gateway microVM (2026-10-14/15)

**Context:** First run of the target shape: a Windows 11 Pro AppVM (Office
LTSC 2024) on the build/runtime host, an RDP gateway microVM, a 1:1 link
between them, RemoteApp windows to the host through waypipe. Spike only; no
repository change. Measurements, verdict and product items:
[ADR-041](adr/ADR-041.md).

**Environment:** host kernel `7.2.10-hardened1-1`. Gateway: foundation
snapshot + `foot` + FreeRDP 3.32.2 built from upstream source (signature
checked) in a throwaway trixie chroot, SDL3 3.2.10 from trixie, binary
`/opt/freerdp/bin/sdl-freerdp`. Link `10.200.0.2` (gateway) ↔ `10.200.0.1`
(Windows); Windows also on a netVM slot for its uplink. Account `rail`.

**RAIL results**
- Word: main window with its own frame, no licence or sign-in dialog; first
  window ≤ ~1 s after the password Enter, twice. 30-page typing/scrolling,
  Save As, New: *"great"* (operator).
- Channels at run time: ainput, rdpgfx, disp; no rdpdr. Clipboard off
  (`-clipboard`), audio off.
- GFX: RDPGFX v10.7, ClearCodec/Alpha/Progressive; H.264 offered, not used.

**Pitfalls found**
- FreeRDP's RDP8 defaults load `rdpdr`; switched off (`.rdp`:
  `networkautodetect:i:0`, `bandwidthautodetect:i:0`; `-heartbeat
  -multitransport /network:auto`).
- SDL3 dlopens EGL/GLES (`libegl1`, `libgles2`); without them: *"Couldn't
  find matching render driver"*. `ldd` does not show them.
- TOFU on a new host prints *"has changed … Host key verification failed"*
  while it stores the certificate (FreeRDP 3.32.2 text swap).
- Windows rebooted itself overnight and ended the RAIL session; cause open
  ([OPEN-PROBLEMS](OPEN-PROBLEMS.md) #59).

**Launch** (in the gateway's `foot`; w2's M7 line, logging options included,
without its `| tee`; `~/w2.rdp` holds the two `networkautodetect` and
`bandwidthautodetect` lines above)

    SDL_VIDEO_DRIVER=wayland /opt/freerdp/bin/sdl-freerdp ~/w2.rdp /v:10.200.0.1 /u:rail \
        /cert:tofu '/auth-pkg-list:!kerberos' /kbd:layout:0x424 -clipboard /audio-mode:none \
        -heartbeat -multitransport /network:auto /log-level:INFO \
        /log-filters:com.freerdp.channels.rdpgfx.client:DEBUG \
        '/app:program:C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'

S3.25 added `EGL_LOG_LEVEL=debug` for diagnosis; whether the working window
needed it was not tested.

## RAIL test — Windows 11 Pro + Office LTSC 2024 (2026-10-08)

**Context:** The remote mini PC is a validation testbed only. The goal is to verify RAIL
behavior (FreeRDP client, window integration, Office as a stress test) before implementing
Windows 11 as a local KatMate VM, reached via the gateway microVM as planned in ROADMAP.md.
Findings here inform that implementation; the network setup itself is not the target architecture.

**Environment:** mini PC N95/16 GB, Win11 Pro, IP 10.3.1.101; client `sdl-freerdp3` (Wayland/SDL).

**Windows-side setup**
- RDP server enabled, firewall rule, `TSAppAllowList\fDisabledAllowList=1`, AC standby disabled.
- Dedicated local account `rail` (Remote Desktop Users, SID S-1-5-32-555), no startup clutter.
  Profile created via one-time full-desktop logon + first Word launch (single welcome dialog), then Sign out.

**Office: ODT, reproducible package**
- `C:\odt\config.xml`: ProPlus2024Volume, channel PerpetualVL2024, x64, UI en-us,
  ProofingTools sl-si, excluding OneDrive/Access/Lync, Updates=FALSE, logs in `C:\odt\log`.
- `setup.exe /download` + `/configure`; folder `C:\odt` (Office + config.xml) = offline,
  identical install → basis for the KatMate Windows image.
- Pitfalls: non-ASCII characters in path (č), retail product in VL channel (0-2039), invalid XML.
- Result: Word LTSC 2408 (16.0.17932.21000), unactivated (no KMS/MAK) — not a blocker for RAIL testing.
- LTSC = frozen version → stable baseline for *Protocol tracking*.

**RAIL results**
- Notepad: tab and new window OK, clean log. *File → Open* not yet tested.
- Word: main window, backstage (File → Account), combobox (Office Theme), modal About dialog
  — all OK, correctly positioned in the tiling environment.
- Clipboard (cliprdr) Win → Linux works.
- Clipboard was enabled for this testbed only; channel policy default remains off.

**Open items**
- Keyboard: client sends US layout and overrides the session setting → `/kbd:layout:0x424` (SI), not yet verified.
- Session does not end after the last window closes when the client attaches to an existing session
  with tray apps (hypothesis: hidden/tray windows) → reason for a separate clean `rail` account.
- Still to test: splash screen, ribbon dropdowns/galleries/tooltips, Save As, two documents at once,
  rich-text/image clipboard in both directions, typing responsiveness.

**Launch**

    env SDL_VIDEO_DRIVER=wayland sdl-freerdp3 /v:10.3.1.101 /u:rail /cert:tofu \
        /auth-pkg-list:!kerberos /kbd:layout:0x424 \
        /app:program:'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'
