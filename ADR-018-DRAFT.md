## ADR-018 — vm-agent: Rust rewrite and a versioned binary control protocol

**Status:** Accepted (2026)

**Context:** The original vm-agent (ADR-003 control channel) was a ~330-line C
program with a line-oriented, whitespace-split text protocol. Three weaknesses
made it unsuitable as a long-term foundation component: the text protocol could
not carry paths containing spaces, newlines or NUL bytes and had no framing
discipline; lengths were parsed with `atol()` and trusted without bounds, so a
malformed or hostile request could drive an unbounded allocation; and several
syscall return values (socket/bind/listen, writes) and child reaping were
unchecked. The agent is part of the immutable foundation image (ADR-007) and
runs on every domain (ADR-003), so its robustness is part of the host↔guest
trust story. A binary host-side client daemon is planned, which removes the
earlier reason to keep the protocol shell-friendly.

**Decision:** Rewrite vm-agent in Rust, `std` + `libc` only — no async runtime,
no `vsock` crate — keeping the TCB small and the raw VSOCK syscalls visible.
The wire protocol becomes a versioned, little-endian, length-prefixed binary
frame (specified below) that is the single source of truth for both the guest
agent and the future host client. The agent stays synchronous and
single-client: the control channel has exactly one peer (the host), and one
connection is served to completion before the next is accepted.

Key sub-decisions:

- **Little-endian, not network byte order.** All target architectures
  (x86-64, aarch64, riscv64) are little-endian, and VSOCK is host↔guest on the
  same physical CPU, so big-endian would mean a byte-swap on every length field
  for no portability gain. Encoded explicitly via `to_le_bytes`/`from_le_bytes`,
  so the code stays correct on a big-endian host if one ever appears.
- **One-byte protocol version in every frame.** A version mismatch is rejected
  rather than silently misparsed — relevant once the foundation image and the
  host client are updated independently (`katmate-update`).
- **Bounds checked before allocation.** `MAX_ARGC` (8), `MAX_ARG_LEN` (4 KiB)
  and `MAX_FILE_SIZE` (100 MiB) are validated as the fixed header and each
  length prefix are read; an over-limit field yields an error response, never
  an allocation. This is the core hardening over the C agent.
- **Children via `posix_spawn`, not fork-then-work.** waypipe (RUN) and the
  power helper (SHUTDOWN) are launched with `posix_spawnp`; all argv marshalling
  happens in the parent, eliminating the non-async-signal-safe
  allocation-after-fork pattern of the C version. The child inherits the agent's
  environment (so `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR` come from the systemd
  unit, not hardcoded).
- **Zombies reaped by the kernel.** `SIGCHLD` is set to `SIG_IGN` at startup;
  finished children are auto-reaped without a handler or `waitpid`. RUN/SHUTDOWN
  are fire-and-forget, so a child exit status is not needed.
- **Path confinement is traversal-safe without `canonicalize`.** A path must
  start with `/home/user/` and contain no `..` component. This holds for
  not-yet-existing FILEPUT targets, which `canonicalize` (which requires the
  path to exist) could not check.
- **FILEPUT is atomic.** The payload is written to a `<path>.vm-agent.partial`
  temp file, `fsync`-ed, then `rename`-d into place, so a failed transfer never
  leaves a partial file.
- **Debug logging is compile-time gated.** A `log_debug!` macro behind
  `cfg!(debug_assertions)` logs the RUN environment, argv and (via inherited
  child stderr) waypipe diagnostics in debug builds, and is stripped entirely
  from release builds — no runtime cost and no information leak in the shipped
  image. Structured error logging (`AgentError` → journal) remains in all builds
  but only fires on an error path.
- **Transport parameters from the environment.** `CONTROL_PORT`, `HOST_CID` and
  `VSOCK_PORT` (the waypipe GUI port) are read from the unit's environment with
  the protocol defaults as fallback. The control port (default 1025) and the
  waypipe port (default 1024) are two distinct, purposeful ports.

**Wire format (PROTOCOL_VERSION 0x01, little-endian):**

```
REQUEST
  u8    version        0x01
  u8    cmd            0x01 PING  0x02 RUN  0x03 FILEGET
                       0x04 FILEPUT  0x05 SHUTDOWN
  u8    argc           number of arguments (<= MAX_ARGC = 8)
  u64   payload_len    trailing payload size (<= MAX_FILE_SIZE)
  repeated argc times:
    u32 arg_len        argument length (<= MAX_ARG_LEN = 4096)
    u8  arg[arg_len]   raw bytes; space / newline / NUL permitted
  u8    payload[payload_len]   present iff payload_len > 0 (FILEPUT body)

RESPONSE
  u8    version        0x01
  u8    status         0x00 OK  0x01 ERR
  u64   payload_len    response payload size (<= MAX_FILE_SIZE; 0 if none)
  u8    payload[payload_len]   present iff payload_len > 0 (FILEGET body)
```

The reader consumes the fixed header first, validates the version, command and
every length against the limits, and only then reads variable-length data. The
client never learns *why* a request failed (it sees only OK/ERR); the reason is
recorded in the agent's journal.

**Consequences:** The host-side client must be a binary speaker of this exact
frame — fish/shell can no longer drive the agent directly, which is acceptable
given the planned host daemon. The protocol module (`protocol.rs`) holds the
constants and the encode/decode routines together so it can be promoted to a
shared `katmate-protocol` crate once the host client exists, with both daemons
linking the same codec; until then it lives in the agent. The foundation build
gains a Rust toolchain requirement for vm-agent (already present for waypipe
≥ 0.11, ADR-008), and the toolchain is purged before the RO freeze as before.
The 100 MiB `MAX_FILE_SIZE` bounds both FILEGET output and FILEPUT input;
larger transfers are out of scope for the control channel by design.

---
