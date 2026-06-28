//! Host-side client for the vm-agent control channel.
//!
//! Speaks the shared `protocol.rs` codec, symlinked in from the agent
//! (`src/protocol.rs -> ../../agent/src/protocol.rs`,
//!  `src/error.rs    -> ../../agent/src/error.rs`). This is the first
//! concrete step toward a `katmate-protocol` crate: when that crate
//! exists, the two `mod` lines below become `use katmate_protocol::*`
//! and the symlinks go away — nothing else changes.
//!
//! Usage:
//!   ping-client ping     <cid> [port]
//!   ping-client run      <cid> <app> [port]
//!   ping-client shutdown <cid> [port]
//!
//! `port` defaults to the agent control port (1025). `app` must be on
//! the agent's launch whitelist (firefox-esr / foot / nautilus); a
//! rejected app comes back as a clean ERR response, not a hang.
//!
//! SHUTDOWN acks with OK and the agent then asks PID 1 (katmate-init)
//! to power the VM off; QEMU (started with -no-reboot) exits shortly
//! after the OK is received.

#[allow(dead_code)] // agent-side half of the codec is unused here
mod error;
#[allow(dead_code)] // ditto: read_request / write_response live here too
mod protocol;

use std::mem;
use std::os::fd::RawFd;
use std::process::exit;

use protocol::{Cmd, DEFAULT_CONTROL_PORT, STATUS_OK};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        usage();
    }

    let cid: u32 = parse_or_die(&args[2], "cid");

    // Resolve the subcommand into (cmd, optional app arg, index where
    // an optional trailing port would sit).
    let (cmd, app, port_idx): (Cmd, Option<String>, usize) = match args[1].as_str() {
        "ping" => (Cmd::Ping, None, 3),
        "run" => {
            if args.len() < 4 {
                usage();
            }
            (Cmd::Run, Some(args[3].clone()), 4)
        }
        "shutdown" => (Cmd::Shutdown, None, 3),
        _ => usage(),
    };

    let port: u32 = args
        .get(port_idx)
        .map(|s| parse_or_die(s, "port"))
        .unwrap_or(DEFAULT_CONTROL_PORT);

    let fd = vsock_connect(cid, port);
    eprintln!("connected: cid={cid} port={port}");

    // RUN carries one argument (the app name); PING / SHUTDOWN carry none.
    let owned_args: Vec<&[u8]> = match &app {
        Some(a) => vec![a.as_bytes()],
        None => Vec::new(),
    };

    if let Err(e) = protocol::write_request(fd, cmd, &owned_args, &[]) {
        eprintln!("send failed: {e}");
        unsafe { libc::close(fd) };
        exit(1);
    }

    match protocol::read_response(fd) {
        Ok(resp) => {
            let label = if resp.status == STATUS_OK { "OK" } else { "ERR" };
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
