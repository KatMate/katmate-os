//! ping-client — host-side client for the KatMate control channel.
//!
//! Speaks the shared `katmate-protocol` codec. The note the pre-workspace
//! header carried — "when a katmate-protocol crate exists, the two `mod`
//! lines become `use katmate_protocol::*` and the symlinks go away,
//! nothing else changes" — is now cashed in. Exactly that, and nothing
//! else: the `#[allow(dead_code)]` markers go too (unused `pub` items in
//! a library crate do not fire dead_code).
//!
//! This is the one binary that legitimately spans BOTH agents — it drives
//! appVM (run / fileget / fileput / shutdown) and netVM (netcfg) — which
//! is precisely why opcode VALUES live in a shared registry while enums
//! and handlers do not. The client encodes raw `opcode::OP_*` values and
//! has no `Op` enum of its own, because it executes nothing. It is a wire
//! driver, not a policy domain.
//!
//! Sending a "forbidden" opcode is allowed here, and SHOULD be: it is how
//! the absent-not-disabled property gets tested against a live agent
//! rather than only in a unit test. `ping-client run 3 foot` (RUN aimed at
//! netVM) must come back ERR — the agent failing at decode — not a
//! launched process.
//!
//! Usage:
//!   ping-client ping     <cid> [port]
//!   ping-client run      <cid> <app> [port]     (appVM only)
//!   ping-client shutdown <cid> [port]           (appVM only; netVM = host QMP)
//!
//! `port` defaults to the shared control port (1025). `app` must be on
//! the agent's launch whitelist (firefox-esr / foot / nautilus); a
//! rejected app comes back as a clean ERR response, not a hang.
//!
//! SHUTDOWN acks with OK and the appVM agent then asks PID 1
//! (katmate-init) to power the VM off; QEMU (started with -no-reboot)
//! exits shortly after the OK is received. netVM does not implement it —
//! it is q35, so the host uses QMP `system_powerdown` (ADR-021).
//!
//! NETCFG is not wired here yet: its subcommand lands with the NETCFG
//! payload design, since the argument shape is part of that decision.

use std::mem;
use std::os::fd::RawFd;
use std::process::exit;

use katmate_protocol::frame::{self, DEFAULT_CONTROL_PORT, STATUS_OK};
use katmate_protocol::opcode;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        usage();
    }

    let cid: u32 = parse_or_die(&args[2], "cid");

    // Resolve the subcommand into (opcode, optional app arg, index where
    // an optional trailing port would sit). The opcode is a raw registry
    // value: the client does not have — and must not have — an Op enum,
    // because it dispatches nothing.
    let (op, app, port_idx): (u8, Option<String>, usize) = match args[1].as_str() {
        "ping" => (opcode::OP_PING, None, 3),
        "run" => {
            if args.len() < 4 {
                usage();
            }
            (opcode::OP_RUN, Some(args[3].clone()), 4)
        }
        "shutdown" => (opcode::OP_SHUTDOWN, None, 3),
        _ => usage(),
    };

    let port: u32 = args
        .get(port_idx)
        .map(|s| parse_or_die(s, "port"))
        .unwrap_or(DEFAULT_CONTROL_PORT);

    let fd = vsock_connect(cid, port);
    eprintln!(
        "connected: cid={cid} port={port} op={} (0x{op:02x})",
        opcode::name(op)
    );

    // RUN carries one argument (the app name); PING / SHUTDOWN carry none.
    let owned_args: Vec<&[u8]> = match &app {
        Some(a) => vec![a.as_bytes()],
        None => Vec::new(),
    };

    if let Err(e) = frame::write_request(fd, op, &owned_args, &[]) {
        eprintln!("send failed: {e}");
        unsafe { libc::close(fd) };
        exit(1);
    }

    match frame::read_response(fd) {
        Ok(resp) => {
            let label = if resp.status == STATUS_OK {
                "OK"
            } else {
                "ERR"
            };
            println!(
                "response: status=0x{:02x} ({}) payload_len={}",
                resp.status,
                label,
                resp.payload.len()
            );
            // FILEGET would carry a body; ping/run/shutdown do not. Print
            // it if it happens to be text, for convenience.
            if !resp.payload.is_empty() {
                if let Ok(s) = std::str::from_utf8(&resp.payload) {
                    println!("payload: {s}");
                }
            }
            unsafe { libc::close(fd) };
            exit(if resp.status == STATUS_OK { 0 } else { 1 });
        }
        Err(e) => {
            eprintln!("no valid response: {e}");
            unsafe { libc::close(fd) };
            exit(1);
        }
    }
}

/// Open an AF_VSOCK stream to (cid, port) or exit with a diagnostic.
fn vsock_connect(cid: u32, port: u32) -> RawFd {
    let fd = unsafe { libc::socket(libc::AF_VSOCK, libc::SOCK_STREAM, 0) };
    if fd < 0 {
        die("socket(AF_VSOCK)");
    }

    let mut addr: libc::sockaddr_vm = unsafe { mem::zeroed() };
    addr.svm_family = libc::AF_VSOCK as libc::sa_family_t;
    addr.svm_cid = cid;
    addr.svm_port = port;

    let r = unsafe {
        libc::connect(
            fd,
            &addr as *const _ as *const libc::sockaddr,
            mem::size_of::<libc::sockaddr_vm>() as libc::socklen_t,
        )
    };
    if r < 0 {
        die("connect");
    }
    fd
}

fn parse_or_die(s: &str, what: &str) -> u32 {
    s.parse().unwrap_or_else(|_| {
        eprintln!("invalid {what}: {s}");
        exit(2);
    })
}

fn usage() -> ! {
    eprintln!("usage:");
    eprintln!("  ping-client ping     <cid> [port]");
    eprintln!("  ping-client run      <cid> <app> [port]");
    eprintln!("  ping-client shutdown <cid> [port]");
    exit(2);
}

fn die(ctx: &str) -> ! {
    eprintln!("{ctx}: {}", std::io::Error::last_os_error());
    exit(1);
}
