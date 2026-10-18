//! katmate-alloc — the netVM slot pool and the fixed-CID space (#58).
//!
//! **Slots** ([ADR-035] §5–6, [ADR-037] R62, R63). A routed AppVM holds a slot
//! of its netVM's pool for one run: the lowest slot that is free or stale,
//! never a reserved one. The `owner` file under
//! `/run/katmate/link/<netvm>/<kk>/` is the record and the only one; no T1
//! key carries a slot. Every read-modify-write of a pool happens under one
//! `flock` on `<pool>/alloc.lock`, and every write is a temporary file plus
//! `rename(2)`, so a reader sees an old owner or a new one, never a half.
//! The pool is on tmpfs: after a host reboot no AppVM runs and no slot is held.
//!
//! **Stale.** An owner is stale when the unit of the instance it names is not
//! running (the caller's `is_live`; the binary asks systemd). A stale owner
//! is not reclaimed by [`Locked::claim`]: it is reported, so the caller can
//! withdraw its link in netVM (NETCFG REMOVE of its `LINK_ID`) first, and
//! [`Locked::reclaim`] then removes it under the lock if it is still the same
//! owner and still stale.
//!
//! **LINK_ID** (ADR-035 §6): an opaque counter with no slot structure, the
//! next value at every claim, from `<pool>/link-id` on the same tmpfs. The
//! first value is 1000, which never coincides with the alpha's 201–206.
//!
//! **CIDs** ([ADR-022], [ADR-017]): unique across all T1 files and the reserved
//! rows of `docs/PARAMETERS.md`; new fixed CIDs come from 32–99. This crate
//! never reads T1 (R150): callers read it with `km_t1_read` and pass
//! `(instance, cid)` pairs.
//!
//! Slot faces (netVM's slot MAC, the guest address) are not here: they are
//! computed only in `katmate-generate-env`.

use std::ffi::CString;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::fd::AsRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

/// The pool's sixteen slots, as a literal list: the pool size is a constant
/// of the netVM template, and a directory entry that is not a slot is not
/// something to iterate.
pub const SLOTS: [&str; 16] = [
    "00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "0a", "0b", "0c", "0d", "0e", "0f",
];

/// Never handed out: 05 holds `win_w1`'s leftovers, 06 the layer builder
/// (`docs/PARAMETERS.md`, allocation map; ADR-043 §3).
pub const RESERVED_SLOTS: [&str; 2] = ["05", "06"];

pub const LINK_ID_FIRST: u32 = 1000;

const LOCK_FILE: &str = "alloc.lock";
const LINK_ID_FILE: &str = "link-id";
const OWNER_FILE: &str = "owner";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub String);

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

fn fail<T>(msg: impl Into<String>) -> Result<T> {
    Err(Error(msg.into()))
}

fn io_fail<T>(what: &str, path: &Path, e: io::Error) -> Result<T> {
    fail(format!("{what} {}: {e}", path.display()))
}

/// `km_check_instance`'s rule: `[a-z][a-z0-9_]*`, at most 63 bytes.
pub fn check_name(name: &str) -> Result<()> {
    let b = name.as_bytes();
    let ok = !b.is_empty()
        && b.len() <= 63
        && b[0].is_ascii_lowercase()
        && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_');
    if ok {
        Ok(())
    } else {
        fail(format!("'{name}' is not an instance name [a-z][a-z0-9_]* of at most 63 bytes"))
    }
}

pub fn check_slot(slot: &str) -> Result<&'static str> {
    match SLOTS.iter().find(|s| **s == slot) {
        Some(s) => Ok(s),
        None => fail(format!("'{slot}' is not a slot (00-0f, two lowercase hex digits)")),
    }
}

pub fn is_reserved(slot: &str) -> bool {
    RESERVED_SLOTS.contains(&slot)
}

/// Canonical decimal u32: no sign, no leading zero, at most ten digits.
fn parse_u32(s: &str) -> Option<u32> {
    let b = s.as_bytes();
    if b.is_empty() || b.len() > 10 || !b.iter().all(u8::is_ascii_digit) || (b.len() > 1 && b[0] == b'0') {
        return None;
    }
    s.parse().ok()
}

/// One `owner` file: `KATMATE_OWNER_VERSION=1`, `INSTANCE=`, `LINK_ID=`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Owner {
    pub instance: String,
    pub link_id: u32,
}

impl Owner {
    pub fn text(&self) -> String {
        format!("KATMATE_OWNER_VERSION=1\nINSTANCE={}\nLINK_ID={}\n", self.instance, self.link_id)
    }

    /// Strict: the three keys once each and nothing else. An owner decides
    /// which address a VM gets (ADR-037 R78), so one this cannot read stops
    /// the pool rather than counting as free.
    pub fn parse(path: &Path, text: &str) -> Result<Owner> {
        let (mut version, mut instance, mut link_id) = (None, None, None);
        for line in text.lines() {
            let Some((k, v)) = line.split_once('=') else {
                return fail(format!("{}: not a KEY=VALUE line: '{line}'", path.display()));
            };
            let field = match k {
                "KATMATE_OWNER_VERSION" => &mut version,
                "INSTANCE" => &mut instance,
                "LINK_ID" => &mut link_id,
                _ => return fail(format!("{}: unknown key '{k}'", path.display())),
            };
            if field.replace(v.to_string()).is_some() {
                return fail(format!("{}: duplicate key '{k}'", path.display()));
            }
        }
        match version.as_deref() {
            Some("1") => {}
            Some(v) => return fail(format!("{}: KATMATE_OWNER_VERSION={v}; only version 1 is understood", path.display())),
            None => return fail(format!("{}: no KATMATE_OWNER_VERSION", path.display())),
        }
        let Some(instance) = instance else {
            return fail(format!("{}: no INSTANCE", path.display()));
        };
        check_name(&instance).map_err(|e| Error(format!("{}: INSTANCE: {e}", path.display())))?;
        let Some(link_id) = link_id.as_deref().and_then(parse_u32) else {
            return fail(format!("{}: LINK_ID '{}' is not a decimal u32", path.display(), link_id.unwrap_or_default()));
        };
        Ok(Owner { instance, link_id })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Claim {
    /// A free slot was taken, with a new LINK_ID.
    Claimed { slot: &'static str, owner: Owner },
    /// The instance already held this slot (an earlier start that never
    /// stopped cleanly); its owner says exactly what would be written.
    Kept { slot: &'static str, owner: Owner },
    /// The lowest usable slot holds a stale owner. Nothing was written.
    Stale { slot: &'static str, owner: Owner },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Released {
    Removed { slot: &'static str },
    /// No slot names the instance.
    Absent,
}

/// One netVM's pool: `<run_dir>/link/<netvm>`.
pub struct Pool {
    dir: PathBuf,
}

impl Pool {
    pub fn new(run_dir: &Path, netvm: &str) -> Result<Pool> {
        check_name(netvm).map_err(|e| Error(format!("netVM: {e}")))?;
        Ok(Pool { dir: run_dir.join("link").join(netvm) })
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Takes the pool lock, blocking. Everything that reads or writes the
    /// pool goes through the returned guard; the lock is dropped with it.
    pub fn lock(&self) -> Result<Locked<'_>> {
        match fs::symlink_metadata(&self.dir) {
            Ok(m) if m.is_dir() => {}
            Ok(_) => return fail(format!("{} is not a directory", self.dir.display())),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return fail(format!(
                    "the slot pool {} does not exist: its netVM has not started on this boot (ADR-035 §5)",
                    self.dir.display()
                ))
            }
            Err(e) => return io_fail("cannot stat", &self.dir, e),
        }
        let path = self.dir.join(LOCK_FILE);
        let file = match OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(&path)
        {
            Ok(f) => f,
            Err(e) => return io_fail("cannot open the pool lock", &path, e),
        };
        loop {
            // SAFETY: flock on an fd this function owns.
            if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } == 0 {
                break;
            }
            let e = io::Error::last_os_error();
            if e.kind() != io::ErrorKind::Interrupted {
                return io_fail("cannot lock", &path, e);
            }
        }
        Ok(Locked { pool: self, _lock: file })
    }
}

pub struct Locked<'a> {
    pool: &'a Pool,
    _lock: File,
}

impl Locked<'_> {
    fn slot_dir(&self, slot: &str) -> PathBuf {
        self.pool.dir.join(slot)
    }

    /// The owner of one slot, or `None` when the slot is free.
    pub fn read(&self, slot: &str) -> Result<Option<Owner>> {
        let slot = check_slot(slot)?;
        let path = self.slot_dir(slot).join(OWNER_FILE);
        let meta = match fs::symlink_metadata(&path) {
            Ok(m) => m,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return io_fail("cannot stat", &path, e),
        };
        if meta.file_type().is_symlink() {
            return fail(format!("{} is a symlink; an owner is read only as a regular file (ADR-037 R78)", path.display()));
        }
        if !meta.is_file() {
            return fail(format!("{} is not a regular file (ADR-037 R78)", path.display()));
        }
        // SAFETY: geteuid cannot fail.
        let euid = unsafe { libc::geteuid() };
        if meta.uid() != euid {
            return fail(format!("{} is owned by uid {}, not {euid}: not an assignment this allocator made (ADR-037 R78)", path.display(), meta.uid()));
        }
        if meta.mode() & 0o022 != 0 {
            return fail(format!("{} has mode {:o}: group- or world-writable (ADR-037 R78)", path.display(), meta.mode() & 0o7777));
        }
        let text = match fs::read_to_string(&path) {
            Ok(t) => t,
            Err(e) => return io_fail("cannot read", &path, e),
        };
        Owner::parse(&path, &text).map(Some)
    }

    /// All sixteen slots in order, every owner read and checked.
    pub fn owners(&self) -> Result<Vec<(&'static str, Option<Owner>)>> {
        SLOTS.iter().map(|s| Ok((*s, self.read(s)?))).collect()
    }

    /// The slot whose owner names `instance`. More than one is an error: an
    /// instance holds one link.
    pub fn find(&self, instance: &str) -> Result<Option<(&'static str, Owner)>> {
        check_name(instance)?;
        Self::find_in(&self.owners()?, instance)
    }

    fn find_in(owners: &[(&'static str, Option<Owner>)], instance: &str) -> Result<Option<(&'static str, Owner)>> {
        let mine: Vec<_> = owners
            .iter()
            .filter_map(|(s, o)| o.as_ref().filter(|o| o.instance == instance).map(|o| (*s, o.clone())))
            .collect();
        match mine.len() {
            0 => Ok(None),
            1 => Ok(mine.into_iter().next()),
            _ => fail(format!(
                "instance '{instance}' is named by the owner of more than one slot: {}",
                mine.iter().map(|(s, _)| *s).collect::<Vec<_>>().join(" ")
            )),
        }
    }

    /// Claims a slot for `instance`. See [`Claim`] for the three outcomes.
    pub fn claim(&self, instance: &str, is_live: &dyn Fn(&str) -> bool) -> Result<Claim> {
        check_name(instance)?;
        let owners = self.owners()?;
        if let Some((slot, owner)) = Self::find_in(&owners, instance)? {
            return Ok(Claim::Kept { slot, owner });
        }
        for (slot, current) in &owners {
            if is_reserved(slot) {
                continue;
            }
            match current {
                Some(o) if is_live(&o.instance) => continue,
                Some(o) => return Ok(Claim::Stale { slot, owner: o.clone() }),
                None => {
                    let dir = self.slot_dir(slot);
                    if !fs::symlink_metadata(&dir).map(|m| m.is_dir()).unwrap_or(false) {
                        return fail(format!("{} is not a directory: the netVM unit creates all sixteen (ADR-035 §5)", dir.display()));
                    }
                    let in_use: Vec<u32> = owners.iter().filter_map(|(_, o)| o.as_ref().map(|o| o.link_id)).collect();
                    let owner = Owner { instance: instance.to_string(), link_id: self.next_link_id(&in_use)? };
                    write_file(&dir.join(OWNER_FILE), &owner.text(), false)?;
                    return Ok(Claim::Claimed { slot, owner });
                }
            }
        }
        let held: Vec<String> = owners
            .iter()
            .filter_map(|(s, o)| o.as_ref().map(|o| format!("{s}={}", o.instance)))
            .collect();
        fail(format!(
            "no free slot in {}: reserved {}, held {}",
            self.pool.dir.display(),
            RESERVED_SLOTS.join(" "),
            held.join(" ")
        ))
    }

    /// Removes the stale owner [`Locked::claim`] reported, if the slot still
    /// holds exactly that owner and it is still stale.
    pub fn reclaim(&self, slot: &str, stale: &Owner, is_live: &dyn Fn(&str) -> bool) -> Result<()> {
        let slot = check_slot(slot)?;
        if is_reserved(slot) {
            return fail(format!("slot {slot} is reserved; it is never reclaimed"));
        }
        match self.read(slot)? {
            Some(o) if o == *stale => {}
            Some(o) => return fail(format!("slot {slot} now names {} with LINK_ID {}, not {} with {}; not reclaimed", o.instance, o.link_id, stale.instance, stale.link_id)),
            None => return Ok(()),
        }
        if is_live(&stale.instance) {
            return fail(format!("the unit of {} is running again; slot {slot} is not reclaimed", stale.instance));
        }
        let path = self.slot_dir(slot).join(OWNER_FILE);
        fs::remove_file(&path).or_else(|e| io_fail("cannot remove", &path, e))
    }

    /// Removes the owner naming `instance`, only if it carries `link_id`. An
    /// owner naming another instance is never touched.
    pub fn release(&self, instance: &str, link_id: u32) -> Result<Released> {
        let Some((slot, owner)) = self.find(instance)? else {
            return Ok(Released::Absent);
        };
        if owner.link_id != link_id {
            return fail(format!("slot {slot} names {instance} with LINK_ID {}, not {link_id}; not removed", owner.link_id));
        }
        let path = self.slot_dir(slot).join(OWNER_FILE);
        fs::remove_file(&path).or_else(|e| io_fail("cannot remove", &path, e))?;
        Ok(Released::Removed { slot })
    }

    fn next_link_id(&self, in_use: &[u32]) -> Result<u32> {
        let path = self.pool.dir.join(LINK_ID_FILE);
        let last = match fs::symlink_metadata(&path) {
            Err(e) if e.kind() == io::ErrorKind::NotFound => None,
            Err(e) => return io_fail("cannot stat", &path, e),
            Ok(m) if !m.is_file() => return fail(format!("{} is not a regular file", path.display())),
            Ok(_) => {
                let text = fs::read_to_string(&path).or_else(|e| io_fail("cannot read", &path, e))?;
                match parse_u32(text.trim_end_matches('\n')) {
                    Some(v) => Some(v),
                    None => return fail(format!("{}: '{}' is not a decimal u32", path.display(), text.trim())),
                }
            }
        };
        // Above every value the counter or a present owner has carried: a
        // value reused after a reclaim would let the old tenant's late REMOVE
        // withdraw the new tenant's link (ADR-035 §6).
        let next = last
            .into_iter()
            .chain(in_use.iter().copied())
            .max()
            .map(|v| v.checked_add(1).ok_or_else(|| Error(format!("{}: the LINK_ID counter is exhausted", path.display()))))
            .transpose()?
            .map_or(LINK_ID_FIRST, |v| v.max(LINK_ID_FIRST));
        // The counter is written before the owner, so a crash between the two
        // skips a value and never hands one out twice.
        write_file(&path, &format!("{next}\n"), true)?;
        Ok(next)
    }
}

static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

/// Writes `text` to `path` mode 0644 through a temporary file in the same
/// directory and `rename(2)`. With `replace` false the rename is
/// `RENAME_NOREPLACE`, so an existing file is never overwritten.
fn write_file(path: &Path, text: &str, replace: bool) -> Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let tmp = dir.join(format!(".{name}.{}.{}", std::process::id(), TMP_SEQ.fetch_add(1, Ordering::Relaxed)));
    let result = (|| {
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o644)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(&tmp)
            .or_else(|e| io_fail("cannot create", &tmp, e))?;
        f.set_permissions(fs::Permissions::from_mode(0o644)).or_else(|e| io_fail("cannot chmod", &tmp, e))?;
        f.write_all(text.as_bytes()).or_else(|e| io_fail("cannot write", &tmp, e))?;
        drop(f);
        if replace {
            fs::rename(&tmp, path).or_else(|e| io_fail("cannot rename onto", path, e))
        } else {
            rename_noreplace(&tmp, path)
        }
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

fn rename_noreplace(from: &Path, to: &Path) -> Result<()> {
    let c = |p: &Path| CString::new(p.as_os_str().as_bytes()).map_err(|_| Error(format!("{} contains a NUL byte", p.display())));
    let (f, t) = (c(from)?, c(to)?);
    // SAFETY: two valid NUL-terminated paths, both relative to the cwd fd.
    let rc = unsafe { libc::renameat2(libc::AT_FDCWD, f.as_ptr(), libc::AT_FDCWD, t.as_ptr(), libc::RENAME_NOREPLACE) };
    if rc == 0 {
        Ok(())
    } else {
        io_fail("cannot rename (no-replace) onto", to, io::Error::last_os_error())
    }
}

/// The fixed-CID space: uniqueness (#58) and the next free user CID.
pub mod cid {
    use super::{check_name, parse_u32, Error, Result};
    use std::collections::BTreeMap;

    /// New fixed CIDs (cu4's `create`) come from here: inside ADR-022's band
    /// for fixed persistent AppVMs (20–99), above every recorded row.
    pub const USER_FIRST: u32 = 32;
    pub const USER_LAST: u32 = 99;
    /// ADR-017's disposable pool (`katmate-cid`) starts here.
    pub const DISPOSABLE_FLOOR: u32 = 100;
    /// Rows `docs/PARAMETERS.md` reserves without a T1 file.
    pub const RESERVED: &[(u32, &str)] = &[(30, "gw_w2, w2's gateway (docs/PARAMETERS.md, allocation map)")];

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct Entry {
        pub instance: String,
        /// As written in T1: a decimal, or `auto` (ADR-017).
        pub cid: String,
    }

    /// `<instance> <cid>` per line; blank lines are skipped.
    pub fn parse_pairs(text: &str) -> Result<Vec<Entry>> {
        let mut out = Vec::new();
        for (i, line) in text.lines().enumerate() {
            let words: Vec<&str> = line.split_whitespace().collect();
            match words.as_slice() {
                [] => {}
                [instance, cid] => out.push(Entry { instance: instance.to_string(), cid: cid.to_string() }),
                _ => return Err(Error(format!("input line {}: expected '<instance> <cid>', got '{line}'", i + 1))),
            }
        }
        Ok(out)
    }

    #[derive(Debug, Default, Clone, PartialEq, Eq)]
    pub struct Report {
        pub errors: Vec<String>,
        pub warnings: Vec<String>,
    }

    pub fn check(entries: &[Entry]) -> Report {
        let mut r = Report::default();
        let mut by_cid: BTreeMap<u32, Vec<&str>> = BTreeMap::new();
        let mut names: BTreeMap<&str, usize> = BTreeMap::new();
        for e in entries {
            if let Err(err) = check_name(&e.instance) {
                r.errors.push(err.0);
                continue;
            }
            *names.entry(&e.instance).or_default() += 1;
            if e.cid == "auto" {
                continue;
            }
            let Some(cid) = parse_u32(&e.cid) else {
                r.errors.push(format!("{}: cid '{}' is neither a decimal nor \"auto\"", e.instance, e.cid));
                continue;
            };
            if cid <= 2 {
                r.errors.push(format!("{}: cid {cid} is reserved by vsock (0-2)", e.instance));
            }
            if let Some((_, who)) = RESERVED.iter().find(|(c, _)| *c == cid) {
                r.errors.push(format!("{}: cid {cid} is reserved for {who}", e.instance));
            }
            if cid >= DISPOSABLE_FLOOR {
                r.warnings.push(format!(
                    "{}: cid {cid} is in ADR-017's disposable range (>= {DISPOSABLE_FLOOR}); a manual pin, which katmate-cid does not see",
                    e.instance
                ));
            }
            by_cid.entry(cid).or_default().push(&e.instance);
        }
        for (name, n) in names {
            if n > 1 {
                r.errors.push(format!("instance {name} is listed {n} times"));
            }
        }
        for (cid, who) in by_cid {
            if who.len() > 1 {
                r.errors.push(format!("cid {cid} is carried by more than one T1 file: {}", who.join(" ")));
            }
        }
        r
    }

    /// The lowest CID in [`USER_FIRST`]..=[`USER_LAST`] that no entry and no
    /// reserved row carries. Refuses when [`check`] finds an error.
    pub fn next(entries: &[Entry]) -> Result<u32> {
        let r = check(entries);
        if !r.errors.is_empty() {
            return Err(Error(format!("the CID set is not valid: {}", r.errors.join("; "))));
        }
        let used: Vec<u32> = entries.iter().filter_map(|e| parse_u32(&e.cid)).chain(RESERVED.iter().map(|(c, _)| *c)).collect();
        (USER_FIRST..=USER_LAST)
            .find(|c| !used.contains(c))
            .ok_or_else(|| Error(format!("no free CID in {USER_FIRST}-{USER_LAST}")))
    }
}

#[cfg(test)]
mod tests;
