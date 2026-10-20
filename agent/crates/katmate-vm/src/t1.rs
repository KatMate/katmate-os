//! The T1 file `create` writes: a fixed key set, the alpha templates' order
//! (`installer/t1/*.toml.in`). Nothing here parses TOML (R150): what is read
//! back comes from `katmate-t1-read` as `key=value` lines.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Props {
    pub cid: u32,
    pub manifest: String,
    /// Empty for an offline instance: `netvm = ""` (ADR-032 §3).
    pub netvm: String,
    pub mem: String,
    pub vcpus: String,
}

pub const NETVM_DEFAULT: &str = "netvm";
pub const MEM_DEFAULT: &str = "2G";
pub const VCPUS_DEFAULT: &str = "2";

/// `katmate-generate-env`'s pattern; it stays the authority at start.
pub fn check_mem(s: &str) -> Result<(), String> {
    let b = s.as_bytes();
    let ok = b.len() >= 2 && b[..b.len() - 1].iter().all(u8::is_ascii_digit) && matches!(b[b.len() - 1], b'M' | b'G');
    if ok {
        Ok(())
    } else {
        Err(format!("--mem '{s}' must be a number with an M or G suffix (1G, 512M)"))
    }
}

/// `katmate-generate-env`'s pattern `^[1-9][0-9]*$`.
pub fn check_vcpus(s: &str) -> Result<(), String> {
    let b = s.as_bytes();
    if !b.is_empty() && b[0] != b'0' && b.iter().all(u8::is_ascii_digit) {
        Ok(())
    } else {
        Err(format!("--vcpus '{s}' must be a positive integer"))
    }
}

pub fn text(name: &str, p: &Props) -> String {
    format!(
        "# T1 instance properties of {name}, written by katmate-vm create (ADR-032 §1).\n\
         class = \"app\"\n\
         cid = {}\n\
         manifest = \"{}\"\n\
         netvm = \"{}\"\n\
         persistence = \"persistent\"\n\
         identity = false\n\
         disposable = false\n\
         mem = \"{}\"\n\
         vcpus = {}\n",
        p.cid, p.manifest, p.netvm, p.mem, p.vcpus
    )
}

/// What `katmate-t1-read` must answer for the file [`text`] wrote.
pub fn expected(p: &Props) -> BTreeMap<String, String> {
    [
        ("class", "app".to_string()),
        ("cid", p.cid.to_string()),
        ("manifest", p.manifest.clone()),
        ("netvm", p.netvm.clone()),
        ("persistence", "persistent".to_string()),
        ("identity", "false".to_string()),
        ("disposable", "false".to_string()),
        ("mem", p.mem.clone()),
        ("vcpus", p.vcpus.clone()),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v))
    .collect()
}

/// `katmate-t1-read <instance>` output: `key=value` per line, split at the
/// first `=`. A key twice is refused (the reader never prints one twice).
pub fn parse_kv(out: &str) -> Result<BTreeMap<String, String>, String> {
    let mut m = BTreeMap::new();
    for line in out.lines() {
        let Some((k, v)) = line.split_once('=') else {
            return Err(format!("katmate-t1-read answered a line without '=': '{line}'"));
        };
        if m.insert(k.to_string(), v.to_string()).is_some() {
            return Err(format!("katmate-t1-read answered key '{k}' twice"));
        }
    }
    Ok(m)
}

/// The differences between what was written and what was read, one line each.
pub fn diff(want: &BTreeMap<String, String>, got: &BTreeMap<String, String>) -> Vec<String> {
    let mut out = Vec::new();
    for (k, v) in want {
        match got.get(k) {
            Some(g) if g == v => {}
            Some(g) => out.push(format!("{k}: wrote '{v}', read '{g}'")),
            None => out.push(format!("{k}: wrote '{v}', read nothing")),
        }
    }
    for (k, g) in got {
        if !want.contains_key(k) {
            out.push(format!("{k}: not written, read '{g}'"));
        }
    }
    out
}
