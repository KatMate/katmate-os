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
//! appVM (run / fileget / fileput / shutdown) and netVM (netcfg / shutdown)
//! — which is precisely why opcode VALUES live in a shared registry while
//! enums and handlers do not. The client encodes raw `opcode::OP_*` values
//! and has no `Op` enum of its own, because it executes nothing. It is a
//! wire driver, not a policy domain.
//!
//! Sending a "forbidden" opcode is allowed here, and SHOULD be: it is how
//! the absent-not-disabled property gets tested against a live agent
//! rather than only in a unit test. `ping-client run 3 foot` (RUN aimed at
//! netVM) must come back ERR — the agent failing at decode — not a
//! launched process.
//!
//! For the same reason the NETCFG payload builders below do NOT validate
//! semantics. The client assembles the bytes it is told to; total
//! validation is the agent's job, and being able to send a payload the
//! agent must reject is what makes that testable (conflicting ADD, a
//! non-local MAC, an out-of-segment peer).
//!
//! Usage:
//!   ping-client ping          <cid> [port]
//!   ping-client run           <cid> <app> [port]              (appVM only)
//!   ping-client shutdown      <cid> [port]
//!   ping-client netcfg-add    <cid> <link_id> <mac> <peer> <metric> [port]
//!   ping-client netcfg-remove <cid> <link_id> [port]
//!
//! `port` defaults to the shared control port (1025). `app` must be on
//! the agent's launch whitelist (firefox-esr / foot / pcmanfm /
//! libreoffice / keepassxc); a rejected app comes back as a clean ERR
//! response, not a hang.
//!
//! SHUTDOWN acks with OK, and the agent then asks its own PID 1 to power
//! the VM off — appVM via katmate-init (ADR-018), netVM via SIGRTMIN+4 to
//! systemd under CAP_KILL (ADR-024). BOTH agents implement it: the QMP ->
//! ACPI -> logind path ADR-021 assumed for netVM was proven inert (logind
//! needs dbus, which the netVM manifest deliberately omits), so SHUTDOWN
//! returned to netvm-agent and was live-gated on 2026-07-18. QEMU (started
//! with -no-reboot) exits shortly after the OK is received.
//!
//! NETCFG (0x06) installs or withdraws ONE internal p2p link in netVM
//! (ADR-023 semantics, ADR-025 payload). `local_addr` and `peer_prefix`
//! are the v1 constants and are not exposed as arguments; v1 admits
//! exactly one route, `peer/32`, whose metric is the only free field.
//! `link_id` is opaque to the agent and is what makes the operation
//! idempotent: re-sending an identical ADD is OK, an ADD that redefines a
//! live id is ERR, and REMOVE of an unknown id is OK.

use std::mem;
use std::os::fd::RawFd;
use std::process::exit;

use katmate_protocol::frame::{self, DEFAULT_CONTROL_PORT, STATUS_OK};
use katmate_protocol::opcode;

// NETCFG sub-opcodes and v1 constants (ADR-025). Duplicated here rather
// than shared: they are the agent's per-binary validation constants, not
// protocol, and a proxy netVM will have different ones.
const NETCFG_ADD: u8 = 0x01;
const NETCFG_REMOVE: u8 = 0x02;
const INTERNAL_LOCAL: [u8; 4] = [10, 100, 1, 1];
const PEER_PREFIX: u8 = 32;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        usage();
    }

    let cid: u32 = parse_or_die(&args[2], "cid");

    // Resolve the subcommand into (opcode, optional app arg, payload, index
    // where an optional trailing port would sit). The opcode is a raw registry
    // value: the client does not have — and must not have — an Op enum,
    // because it dispatches nothing.
    let (op, app, payload, port_idx): (u8, Option<String>, Vec<u8>, usize) = match args[1].as_str() {
        "ping" => (opcode::OP_PING, None, Vec::new(), 3),
        "run" => {
            if args.len() < 4 {
                usage();
            }
            (opcode::OP_RUN, Some(args[3].clone()), Vec::new(), 4)
        }
        "shutdown" => (opcode::OP_SHUTDOWN, None, Vec::new(), 3),
        "netcfg-add" => {
            if args.len() < 7 {
                usage();
            }
            let link_id: u32 = parse_or_die(&args[3], "link_id");
            let mac = parse_mac(&args[4]);
            let peer = parse_ipv4(&args[5]);
            let metric: u32 = parse_or_die(&args[6], "metric");
            (opcode::OP_NETCFG, None, netcfg_add(link_id, &mac, &peer, metric), 7)
        }
        "netcfg-remove" => {
            if args.len() < 4 {
                usage();
            }
            let link_id: u32 = parse_or_die(&args[3], "link_id");
            (opcode::OP_NETCFG, None, netcfg_remove(link_id), 4)
        }
        _ => usage(),
    };

    let port: u32 = args
        .get(port_idx)
        .map(|s| parse_or_die(s, "port"))
        .unwrap_or(DEFAULT_CONTROL_PORT);

    let fd = vsock_connect(cid, port);
    eprintln!(
        "connected: cid={cid} port={port} op={} (0x{op:02x}) payload_len={}",
        opcode::name(op),
        payload.len()
    );

    // RUN carries one argument (the app name); NETCFG carries a payload and no
    // arguments; PING / SHUTDOWN carry neither.
    let owned_args: Vec<&[u8]> = match &app {
        Some(a) => vec![a.as_bytes()],
        None => Vec::new(),
    };

    if let Err(e) = frame::write_request(fd, op, &owned_args, &payload) {
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
            // FILEGET would carry a body; the others do not. Print it if it
            // happens to be text, for convenience.
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

// --- NETCFG payload builders ---------------------------------------
// Fixed binary layout, ADR-025. Integers little-endian per the frame
// convention; addresses and the MAC are byte arrays in network order and
// are copied through untouched.

/// ADD: 30 bytes (the single-route v1 shape).
fn netcfg_add(link_id: u32, mac: &[u8; 6], peer: &[u8; 4], metric: u32) -> Vec<u8> {
    let mut p = Vec::with_capacity(30);
    p.push(NETCFG_ADD);
    p.extend_from_slice(&link_id.to_le_bytes());
    p.extend_from_slice(mac);
    p.extend_from_slice(&INTERNAL_LOCAL);
    p.extend_from_slice(peer);
    p.push(PEER_PREFIX);
    p.push(1); // route_count
    p.extend_from_slice(peer); // route dest == peer
    p.push(PEER_PREFIX);
    p.extend_from_slice(&metric.to_le_bytes());
    p
}

/// REMOVE: 5 bytes. The agent reconstructs what to withdraw from its own
/// record, so the id is all that travels.
fn netcfg_remove(link_id: u32) -> Vec<u8> {
    let mut p = Vec::with_capacity(5);
    p.push(NETCFG_REMOVE);
    p.extend_from_slice(&link_id.to_le_bytes());
    p
}

// --- argument parsing ----------------------------------------------

fn parse_mac(s: &str) -> [u8; 6] {
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() != 6 {
        eprintln!("invalid mac (want aa:bb:cc:dd:ee:ff): {s}");
        exit(2);
    }
    let mut out = [0u8; 6];
    for (i, part) in parts.iter().enumerate() {
        out[i] = u8::from_str_radix(part, 16).unwrap_or_else(|_| {
            eprintln!("invalid mac octet: {part}");
            exit(2);
        });
    }
    out
}

fn parse_ipv4(s: &str) -> [u8; 4] {
    let parts: Vec<&str> = s.split('.').collect();
    if parts.len() != 4 {
        eprintln!("invalid ipv4 address: {s}");
        exit(2);
    }
    let mut out = [0u8; 4];
    for (i, part) in parts.iter().enumerate() {
        out[i] = part.parse().unwrap_or_else(|_| {
            eprintln!("invalid ipv4 octet: {part}");
            exit(2);
        });
    }
    out
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
    eprintln!("  ping-client ping          <cid> [port]");
    eprintln!("  ping-client run           <cid> <app> [port]");
    eprintln!("  ping-client shutdown      <cid> [port]");
    eprintln!("  ping-client netcfg-add    <cid> <link_id> <mac> <peer> <metric> [port]");
    eprintln!("  ping-client netcfg-remove <cid> <link_id> [port]");
    exit(2);
}

fn die(ctx: &str) -> ! {
    eprintln!("{ctx}: {}", std::io::Error::last_os_error());
    exit(1);
}
