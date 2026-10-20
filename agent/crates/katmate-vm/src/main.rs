//! katmate-vm — create, show and delete an AppVM instance over a frozen layer
//! (T4, `/usr/lib/katmate/katmate-vm`; cu4, step 3 of user-created AppVMs).
//!
//! Usage:
//!   katmate-vm create <name> --layer <layer> [--mem 2G] [--vcpus 2] [--offline] [--reuse-home]
//!   katmate-vm status [<name>]
//!   katmate-vm delete <name> [--purge]
//!
//! Runs as uid 0 and refuses otherwise. T1 is read only through
//! `katmate-t1-read` (R150); the layer is checked by `katmate-check-image
//! --layer` and `katmate-activate-lvs --layer`. Exit: 0 done, 1 refused or
//! failed, 2 usage.

mod host;
mod t1;
mod vm;

use std::process::exit;

const USAGE: &str = "usage: katmate-vm create <name> --layer <layer> [--mem <n>M|G] [--vcpus <n>] [--offline] [--reuse-home] | \
                     katmate-vm status [<name>] | katmate-vm delete <name> [--purge]";

fn usage(why: &str) -> ! {
    eprintln!("[katmate-vm] USAGE: {why}\n{USAGE}");
    exit(2)
}

fn die(msg: impl std::fmt::Display) -> ! {
    eprintln!("[katmate-vm] FATAL: {msg}");
    exit(1)
}

/// `create`'s arguments; every option once at most, in any order after the name.
fn parse_create(args: &[String]) -> vm::CreateOpts {
    let Some((name, rest)) = args.split_first() else { usage("create needs a name") };
    let (mut layer, mut mem, mut vcpus) = (None, None, None);
    let (mut offline, mut reuse_home) = (false, false);
    let mut it = rest.iter();
    while let Some(a) = it.next() {
        let mut value = |slot: &mut Option<String>| {
            let Some(v) = it.next() else { usage(&format!("{a} needs a value")) };
            if slot.replace(v.clone()).is_some() {
                usage(&format!("{a} given twice"));
            }
        };
        match a.as_str() {
            "--layer" => value(&mut layer),
            "--mem" => value(&mut mem),
            "--vcpus" => value(&mut vcpus),
            "--offline" if !offline => offline = true,
            "--reuse-home" if !reuse_home => reuse_home = true,
            "--offline" | "--reuse-home" => usage(&format!("{a} given twice")),
            _ => usage(&format!("unknown argument '{a}'")),
        }
    }
    vm::CreateOpts {
        name: name.clone(),
        layer: layer.unwrap_or_else(|| usage("create needs --layer <layer>")),
        mem: mem.unwrap_or_else(|| t1::MEM_DEFAULT.to_string()),
        vcpus: vcpus.unwrap_or_else(|| t1::VCPUS_DEFAULT.to_string()),
        offline,
        reuse_home,
    }
}

fn main() {
    // SAFETY: geteuid cannot fail.
    if unsafe { libc::geteuid() } != 0 {
        die("must run as uid 0 (sudo /usr/lib/katmate/katmate-vm …): it writes T1, creates and removes LVs, and reads the slot pools");
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    let env = vm::Env::system();
    let host = host::RealHost;
    let Some((cmd, rest)) = args.split_first() else { usage("no subcommand") };
    match cmd.as_str() {
        "create" => {
            let o = parse_create(rest);
            vm::create(&env, &host, &o).unwrap_or_else(|e| die(e));
        }
        "delete" => {
            let (name, purge) = match rest {
                [n] => (n, false),
                [n, p] if p == "--purge" => (n, true),
                _ => usage("delete <name> [--purge]"),
            };
            vm::delete(&env, &host, name, purge).unwrap_or_else(|e| die(e));
        }
        "status" => {
            let name = match rest {
                [] => None,
                [n] => Some(n.as_str()),
                _ => usage("status [<name>]"),
            };
            let (rows, errors) = vm::status(&env, &host, name).unwrap_or_else(|e| die(e));
            println!("{}", vm::header());
            for r in &rows {
                println!("{}", vm::fmt_row(r));
            }
            if !errors.is_empty() {
                die(errors.join("; "));
            }
        }
        _ => usage(&format!("unknown subcommand '{cmd}'")),
    }
}

#[cfg(test)]
mod tests;
