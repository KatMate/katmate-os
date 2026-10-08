# RAIL tests

Test records for Windows application windows via RDP RemoteApp (RAIL,
MS-RDPERP). The plan these tests serve is `ROADMAP.md` § *Windows application
windows via RDP RemoteApp*. Newest first.

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
