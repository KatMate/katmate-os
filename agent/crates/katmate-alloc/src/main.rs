//! katmate-alloc — the slot pool and CID checks for `katmate-launch` (T4,
//! `/usr/lib/katmate/katmate-alloc`). Runs as root under `katmate-launch`;
//! the library is what cu4's CLI links.
//!
//! Usage:
//!   katmate-alloc slot claim   <netvm> <instance>
//!       prints `claimed|kept|stale <slot> <link_id> <owner-instance>`
//!   katmate-alloc slot reclaim <netvm> <slot> <stale-instance> <link_id>
//!   katmate-alloc slot release <netvm> <instance> <link_id>
//!   katmate-alloc slot find    <netvm> <instance>   prints `<slot> <link_id>`, or nothing
//!   katmate-alloc slot list    <netvm>              one line per slot
//!   katmate-alloc cid check    < pairs              warnings on stderr
//!   katmate-alloc cid next     < pairs              prints the lowest free user CID
//!
//! `pairs` is `<instance> <cid>` per line, read from T1 by the caller with
//! `km_t1_read` (R150). Exit: 0 done, 1 refused, 2 usage.

use katmate_alloc::{cid, is_reserved, Claim, Pool, Released};
use std::io::Read;
use std::path::Path;
use std::process::{exit, Command};

const RUN_DIR: &str = "/run/katmate";
const SYSTEMCTL: &str = "/usr/bin/systemctl";

fn usage() -> ! {
    eprintln!(
        "usage: katmate-alloc slot claim <netvm> <instance> | slot reclaim <netvm> <slot> <instance> <link_id> | \
         slot release <netvm> <instance> <link_id> | slot find <netvm> <instance> | slot list <netvm> | \
         cid check | cid next"
    );
    exit(2)
}

fn die(msg: impl std::fmt::Display) -> ! {
    eprintln!("[katmate-alloc] FATAL: {msg}");
    exit(1)
}

/// The stale-owner rule: an owner is live while its instance's routed unit
/// is active, activating, deactivating or reloading. Anything else,
/// including a systemctl that cannot answer, is not live.
fn is_live(instance: &str) -> bool {
    let unit = format!("katmate-app-routed@{instance}.service");
    match Command::new(SYSTEMCTL).args(["is-active", &unit]).output() {
        Ok(o) => matches!(String::from_utf8_lossy(&o.stdout).trim(), "active" | "activating" | "deactivating" | "reloading"),
        Err(e) => die(format!("cannot run {SYSTEMCTL}: {e}")),
    }
}

fn link_id(s: &str) -> u32 {
    s.parse().unwrap_or_else(|_| die(format!("LINK_ID '{s}' is not a decimal u32")))
}

fn pairs() -> Vec<cid::Entry> {
    let mut text = String::new();
    std::io::stdin().read_to_string(&mut text).unwrap_or_else(|e| die(format!("cannot read stdin: {e}")));
    cid::parse_pairs(&text).unwrap_or_else(|e| die(e))
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let pool = |netvm: &str| Pool::new(Path::new(RUN_DIR), netvm).unwrap_or_else(|e| die(e));
    match a.as_slice() {
        ["slot", "claim", netvm, instance] => {
            let p = pool(netvm);
            let l = p.lock().unwrap_or_else(|e| die(e));
            let (state, slot, owner) = match l.claim(instance, &is_live).unwrap_or_else(|e| die(e)) {
                Claim::Claimed { slot, owner } => ("claimed", slot, owner),
                Claim::Kept { slot, owner } => ("kept", slot, owner),
                Claim::Stale { slot, owner } => ("stale", slot, owner),
            };
            println!("{state} {slot} {} {}", owner.link_id, owner.instance);
        }
        ["slot", "reclaim", netvm, slot, instance, id] => {
            let p = pool(netvm);
            let l = p.lock().unwrap_or_else(|e| die(e));
            let stale = katmate_alloc::Owner { instance: instance.to_string(), link_id: link_id(id) };
            l.reclaim(slot, &stale, &is_live).unwrap_or_else(|e| die(e));
        }
        ["slot", "release", netvm, instance, id] => {
            let p = pool(netvm);
            let l = p.lock().unwrap_or_else(|e| die(e));
            match l.release(instance, link_id(id)).unwrap_or_else(|e| die(e)) {
                Released::Removed { slot } => println!("removed {slot}"),
                Released::Absent => println!("absent"),
            }
        }
        ["slot", "find", netvm, instance] => {
            let p = pool(netvm);
            let l = p.lock().unwrap_or_else(|e| die(e));
            if let Some((slot, owner)) = l.find(instance).unwrap_or_else(|e| die(e)) {
                println!("{slot} {}", owner.link_id);
            }
        }
        ["slot", "list", netvm] => {
            let p = pool(netvm);
            let l = p.lock().unwrap_or_else(|e| die(e));
            for (slot, owner) in l.owners().unwrap_or_else(|e| die(e)) {
                let tag = if is_reserved(slot) { " (reserved)" } else { "" };
                match owner {
                    Some(o) => println!("{slot} {} {}{tag}", o.instance, o.link_id),
                    None => println!("{slot} free{tag}"),
                }
            }
        }
        ["cid", "check"] => {
            let r = cid::check(&pairs());
            for w in &r.warnings {
                eprintln!("[katmate-alloc] WARNING: {w}");
            }
            if !r.errors.is_empty() {
                die(r.errors.join("; "));
            }
        }
        ["cid", "next"] => println!("{}", cid::next(&pairs()).unwrap_or_else(|e| die(e))),
        _ => usage(),
    }
}
