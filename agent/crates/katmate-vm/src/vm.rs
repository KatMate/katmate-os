//! `create`, `delete` and `status` (cu4 rulings 1–7); `menu` (cu5).

use crate::host::Host;
use crate::t1::{self, Props};
use katmate_alloc::{check_name, cid, unit_live, unit_state, write_file, Pool};
use std::collections::BTreeSet;
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

pub type Result<T> = std::result::Result<T, String>;

/// The installer's `POOL`, `HOME_LV_SIZE` and `DELTA_SIZE`; after cu4 this is
/// their only holder (ruling 4).
pub const POOL: &str = "vm_pool";
pub const HOME_LV_SIZE: &str = "10G";
pub const DELTA_SIZE: &str = "10G";

/// A `class = app` instance is named `app_*` (cu4 ruling 3).
pub const NAME_PREFIX: &str = "app_";

pub struct Env {
    pub etc_vm: PathBuf,
    pub instances: PathBuf,
    pub run_dir: PathBuf,
    /// T2: the layer metas the menu reads.
    pub t2: PathBuf,
    /// The launcher's entries are `<desktop>/applications` (state, not `/usr`;
    /// cu5 ruling 1): km-menu's `DATA`.
    pub desktop: PathBuf,
    /// System binaries: LVM, mkfs, mount, qemu-img, systemctl.
    pub bin: PathBuf,
    /// T4 helpers beside this binary (R155: never a build tree).
    pub lib: PathBuf,
    pub lock_timeout: Duration,
}

impl Env {
    pub fn system() -> Env {
        Env {
            etc_vm: "/etc/katmate/vm".into(),
            instances: "/var/lib/katmate/instances".into(),
            run_dir: "/run/katmate".into(),
            t2: "/var/lib/katmate".into(),
            desktop: "/var/lib/katmate/desktop".into(),
            bin: "/usr/bin".into(),
            lib: "/usr/lib/katmate".into(),
            lock_timeout: Duration::from_secs(90),
        }
    }

    fn bin(&self, prog: &str) -> String {
        self.bin.join(prog).to_string_lossy().into_owned()
    }

    fn lib(&self, prog: &str) -> String {
        self.lib.join(prog).to_string_lossy().into_owned()
    }

    fn systemctl(&self) -> PathBuf {
        self.bin.join("systemctl")
    }

    pub fn t1_path(&self, name: &str) -> PathBuf {
        self.etc_vm.join(format!("{name}.toml"))
    }

    /// ADR-032's note of 2026-09-27: per-instance configuration beside T1.
    pub fn d_path(&self, name: &str) -> PathBuf {
        self.etc_vm.join(format!("{name}.d"))
    }

    pub fn delta_path(&self, name: &str) -> PathBuf {
        self.instances.join(format!("{name}.qcow2"))
    }
}

pub fn log(msg: impl std::fmt::Display) {
    println!("[katmate-vm] {msg}");
}

pub fn check_app_name(name: &str) -> Result<()> {
    check_name(name).map_err(|e| e.0)?;
    if !name.starts_with(NAME_PREFIX) || name.len() == NAME_PREFIX.len() {
        return Err(format!("'{name}' does not begin with {NAME_PREFIX}: an AppVM (class = app) is named {NAME_PREFIX}<name> (cu4 ruling 3)"));
    }
    Ok(())
}

pub fn home_lv(name: &str) -> String {
    format!("vm_{name}_home")
}

fn routed_unit(name: &str) -> String {
    format!("katmate-app-routed@{name}.service")
}

fn offline_unit(name: &str) -> String {
    format!("katmate-app-offline@{name}.service")
}

/// Present in any form, a dangling symlink included.
fn exists(p: &Path) -> Result<bool> {
    match fs::symlink_metadata(p) {
        Ok(_) => Ok(true),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(format!("cannot stat {}: {e}", p.display())),
    }
}

/// `katmate-launch`'s own lock (cu4 ruling 5): a launch or a `--stop` never
/// interleaves with a create or a delete. Dropped with the guard.
pub struct LaunchLock {
    _file: File,
}

pub fn launch_lock(env: &Env) -> Result<LaunchLock> {
    let dir = env.run_dir.join("launch");
    fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    // As `install -d -m 0700` in km_run_subdir: an existing directory is narrowed.
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).map_err(|e| format!("cannot chmod {}: {e}", dir.display()))?;
    let path = dir.join("lock");
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o644)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(&path)
        .map_err(|e| format!("cannot open {}: {e}", path.display()))?;
    let t0 = Instant::now();
    loop {
        // SAFETY: flock on an fd this function owns.
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
            return Ok(LaunchLock { _file: file });
        }
        let e = io::Error::last_os_error();
        if e.raw_os_error() != Some(libc::EWOULDBLOCK) && e.kind() != io::ErrorKind::Interrupted {
            return Err(format!("cannot lock {}: {e}", path.display()));
        }
        if t0.elapsed() >= env.lock_timeout {
            return Err(format!("another katmate-launch or katmate-vm has held {} for {} s", path.display(), env.lock_timeout.as_secs()));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// SIGINT, SIGTERM, SIGHUP and SIGQUIT blocked while the guard lives, so a
/// create or a delete is not cut between its first change and its last (or
/// its undo); a signal that arrives meanwhile is delivered at the drop (cu4
/// H2 ruling 3). Programs started inside inherit the mask.
pub struct SignalBlock {
    old: libc::sigset_t,
}

impl SignalBlock {
    pub fn new() -> Result<SignalBlock> {
        // SAFETY: sigset_t is plain data; the calls only read and write the
        // two sets on this stack frame and this thread's mask.
        unsafe {
            let mut set: libc::sigset_t = std::mem::zeroed();
            let mut old: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut set);
            for s in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP, libc::SIGQUIT] {
                libc::sigaddset(&mut set, s);
            }
            if libc::sigprocmask(libc::SIG_BLOCK, &set, &mut old) != 0 {
                return Err(format!("cannot block signals: {}", io::Error::last_os_error()));
            }
            Ok(SignalBlock { old })
        }
    }
}

impl Drop for SignalBlock {
    fn drop(&mut self) {
        // SAFETY: restores the mask saved by new().
        unsafe {
            libc::sigprocmask(libc::SIG_SETMASK, &self.old, std::ptr::null_mut());
        }
    }
}

/// One journal line per outcome, `katmate-launch`'s form (cu4 H2 ruling 4),
/// also on stdout: in a chroot there is no journal, and the installer's log
/// must carry it (ruling after C6, 3). A failing logger fails nothing.
fn journal(env: &Env, host: &dyn Host, line: &str) {
    log(line);
    if let Err(e) = host.run(&[&env.bin("logger"), "-t", "katmate-vm", "--", line]) {
        eprintln!("[katmate-vm] WARNING: logger failed ({e}); this outcome is not in the journal");
    }
}

fn invoked_by() -> String {
    std::env::var("SUDO_USER").unwrap_or_else(|_| "<no SUDO_USER>".to_string())
}

/// Every LV as `(vg, lv)`.
fn list_lvs(env: &Env, host: &dyn Host) -> Result<Vec<(String, String)>> {
    let out = host.run(&[&env.bin("lvs"), "--noheadings", "--separator", "/", "-o", "vg_name,lv_name"])?;
    out.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(|l| {
            l.split_once('/')
                .map(|(vg, lv)| (vg.to_string(), lv.to_string()))
                .ok_or_else(|| format!("lvs answered '{l}', not <vg>/<lv>"))
        })
        .collect()
}

/// The instance's home as `vg/lv`, in whichever volume group holds it.
fn find_home(lvs: &[(String, String)], name: &str) -> Result<Option<String>> {
    let want = home_lv(name);
    let found: Vec<String> = lvs.iter().filter(|(_, lv)| *lv == want).map(|(vg, lv)| format!("{vg}/{lv}")).collect();
    match found.len() {
        0 => Ok(None),
        1 => Ok(found.into_iter().next()),
        _ => Err(format!("{want} exists in more than one volume group: {}", found.join(" "))),
    }
}

fn lvm_name_ok(s: &str) -> bool {
    !s.is_empty() && !s.starts_with('-') && s.bytes().all(|c| c.is_ascii_alphanumeric() || b"+_.-".contains(&c))
}

/// `katmate-check-image --layer`'s last line: `APP_LV=<vg>/<lv>`.
pub fn parse_app_lv(out: &str) -> Result<(String, String)> {
    let last = out.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("");
    let v = last.strip_prefix("APP_LV=").ok_or_else(|| format!("katmate-check-image --layer ended with '{last}', not APP_LV=<vg>/<lv>"))?;
    match v.split_once('/') {
        Some((vg, lv)) if lvm_name_ok(vg) && lvm_name_ok(lv) => Ok((vg.to_string(), lv.to_string())),
        _ => Err(format!("katmate-check-image --layer answered APP_LV='{v}', not <vg>/<lv>")),
    }
}

/// The netVM pool slot that names `name`, in any pool under `<run>/link/`.
fn held_slot(env: &Env, name: &str) -> Result<Option<(String, &'static str, u32)>> {
    let link = env.run_dir.join("link");
    let rd = match fs::read_dir(&link) {
        Ok(rd) => rd,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("cannot read {}: {e}", link.display())),
    };
    let mut netvms = BTreeSet::new();
    for ent in rd {
        let ent = ent.map_err(|e| format!("cannot read {}: {e}", link.display()))?;
        if ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            netvms.insert(ent.file_name().to_string_lossy().into_owned());
        }
    }
    for netvm in netvms {
        let pool = Pool::new(&env.run_dir, &netvm).map_err(|e| format!("{}: {e}", link.join(&netvm).display()))?;
        let l = pool.lock().map_err(|e| e.0)?;
        if let Some((slot, owner)) = l.find(name).map_err(|e| e.0)? {
            return Ok(Some((netvm, slot, owner.link_id)));
        }
    }
    Ok(None)
}

// --- create -------------------------------------------------------------------

pub struct CreateOpts {
    pub name: String,
    pub layer: String,
    pub mem: String,
    pub vcpus: String,
    pub offline: bool,
    pub reuse_home: bool,
}

enum Undo {
    T1(PathBuf),
    Home(String),
    Delta(PathBuf),
}

/// Undoes `done` in reverse; one line per step, a failed one marked.
fn undo(env: &Env, host: &dyn Host, done: Vec<Undo>) -> Vec<String> {
    let rm = |p: &Path| match fs::remove_file(p) {
        Ok(()) => format!("removed {}", p.display()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => format!("{} was not there", p.display()),
        Err(e) => format!("FAILED to remove {}: {e}", p.display()),
    };
    done.into_iter()
        .rev()
        .map(|step| match step {
            Undo::T1(p) | Undo::Delta(p) => rm(&p),
            Undo::Home(spec) => match host.run(&[&env.bin("lvremove"), "-q", "-y", &spec]) {
                Ok(_) => format!("lvremove {spec}"),
                Err(e) => format!("FAILED lvremove {spec}: {e}"),
            },
        })
        .collect()
}

/// `Ok(Some(reason))`: created, but the menu was not updated (exit 3; cu5
/// ruling 5). The instance stays.
pub fn create(env: &Env, host: &dyn Host, o: &CreateOpts) -> Result<Option<String>> {
    let (mut cid, mut window, mut undone, mut lock) = (None, None, false, None);
    let r = create_inner(env, host, o, &mut lock, &mut cid, &mut window, &mut undone);
    let menu = r.is_ok().then(|| menu_update(env, host).err()).flatten();
    let result = match &r {
        Ok(()) => format!("created{}", not_updated(&menu)),
        Err(e) if undone => format!("undone: {e}"),
        Err(e) => format!("refused: {e}"),
    };
    let cid = cid.map_or_else(|| "-".to_string(), |c: u32| c.to_string());
    journal(env, host, &format!("create {} (CID {cid}, invoked by {}): {result}", o.name, invoked_by()));
    drop(window);
    drop(lock);
    r.map(|()| menu)
}

fn not_updated(menu: &Option<String>) -> String {
    menu.as_ref().map(|e| format!("; menu not updated: {e}")).unwrap_or_default()
}

#[allow(clippy::too_many_arguments)]
fn create_inner(
    env: &Env,
    host: &dyn Host,
    o: &CreateOpts,
    lock: &mut Option<LaunchLock>,
    cid_out: &mut Option<u32>,
    window: &mut Option<SignalBlock>,
    undone: &mut bool,
) -> Result<()> {
    check_app_name(&o.name)?;
    t1::check_mem(&o.mem)?;
    t1::check_vcpus(&o.vcpus)?;
    *lock = Some(launch_lock(env)?);

    let t1_path = env.t1_path(&o.name);
    if exists(&t1_path)? {
        return Err(format!("{} exists: instance '{}' is there already", t1_path.display(), o.name));
    }
    let d = env.d_path(&o.name);
    if exists(&d)? {
        return Err(format!("{} exists without a T1 file; nothing is created beside it", d.display()));
    }
    let delta = env.delta_path(&o.name);
    if exists(&delta)? {
        return Err(format!("{} exists without a T1 file: a leftover, which qemu-img create would overwrite", delta.display()));
    }

    // The layer's payload and generation (cu2), from the T4 that checks them.
    let out = host.run(&[&env.lib("katmate-check-image"), "--layer", &o.layer]).map_err(|e| format!("layer '{}' refused: {e}", o.layer))?;
    let (vg, app_lv) = parse_app_lv(&out)?;
    log(format!("layer '{}': payload present, not stale, APP_LV={vg}/{app_lv}", o.layer));

    let home = format!("{vg}/{}", home_lv(&o.name));
    match (find_home(&list_lvs(env, host)?, &o.name)?, o.reuse_home) {
        (Some(h), false) => {
            return Err(format!(
                "{h} exists: a kept home. --reuse-home attaches it as it is; 'katmate-vm delete {} --purge' removes it",
                o.name
            ))
        }
        (None, true) => return Err(format!("--reuse-home: there is no home LV {} to attach", home_lv(&o.name))),
        (Some(h), true) if h != home => return Err(format!("--reuse-home: {h} is not in the layer's volume group {vg}")),
        (Some(_), true) => {
            let t = host.run(&[&env.bin("blkid"), "-o", "value", "-s", "TYPE", &format!("/dev/{home}")])?;
            if t.trim() != "ext4" {
                return Err(format!("--reuse-home: /dev/{home} carries TYPE '{}', not ext4", t.trim()));
            }
            log(format!("home {home}: present, ext4"));
        }
        (None, false) => {}
    }

    host.run(&[&env.lib("katmate-activate-lvs"), "--layer", &o.layer]).map_err(|e| format!("layer '{}' refused: {e}", o.layer))?;
    log(format!("layer '{}': chain active and frozen", o.layer));

    let entries = cid::parse_pairs(&host.run(&[&env.lib("katmate-t1-read"), "--pairs"])?).map_err(|e| e.0)?;
    let cid = cid::next(&entries).map_err(|e| e.0)?;
    *cid_out = Some(cid);
    log(format!("CID {cid}: the lowest free in {}-{} over {} T1 files", cid::USER_FIRST, cid::USER_LAST, entries.len()));

    let props = Props {
        cid,
        manifest: o.layer.clone(),
        netvm: if o.offline { String::new() } else { t1::NETVM_DEFAULT.to_string() },
        mem: o.mem.clone(),
        vcpus: o.vcpus.clone(),
    };
    let mut done = Vec::new();
    *window = Some(SignalBlock::new()?);
    match create_steps(env, host, o, &props, &home, &format!("{vg}/{app_lv}"), &mut done) {
        Ok(()) => {
            log(format!("created {}: CID {cid}, layer {}, {}", o.name, o.layer, if o.offline { "offline" } else { "netvm" }));
            Ok(())
        }
        Err(e) => {
            *undone = true;
            let steps = undo(env, host, done);
            Err(format!("{e}. Undone, in reverse: {}", if steps.is_empty() { "nothing".to_string() } else { steps.join("; ") }))
        }
    }
}

fn create_steps(env: &Env, host: &dyn Host, o: &CreateOpts, p: &Props, home: &str, app_lv: &str, done: &mut Vec<Undo>) -> Result<()> {
    let path = env.t1_path(&o.name);
    write_file(&path, &t1::text(&o.name, p), false).map_err(|e| e.0)?;
    done.push(Undo::T1(path.clone()));
    let m = fs::symlink_metadata(&path).map_err(|e| format!("cannot stat {}: {e}", path.display()))?;
    // SAFETY: geteuid cannot fail.
    let euid = unsafe { libc::geteuid() };
    if !m.is_file() || m.uid() != euid || m.mode() & 0o7777 != 0o644 {
        return Err(format!("{} is not a regular file of uid {euid}, mode 0644, after the write", path.display()));
    }
    let got = t1::parse_kv(&host.run(&[&env.lib("katmate-t1-read"), &o.name])?)?;
    let want = t1::expected(p);
    let diff = t1::diff(&want, &got);
    if !diff.is_empty() {
        return Err(format!("{} does not read back as written: {}", path.display(), diff.join("; ")));
    }
    log(format!("T1 {}: written, mode 0644; read back through katmate-t1-read, {} of {} keys as written", path.display(), got.len(), want.len()));

    if o.reuse_home {
        log(format!("home {home}: kept, attached as it is (no mkfs)"));
    } else {
        make_home(env, host, &o.name, home, done)?;
    }
    make_delta(env, host, &o.name, app_lv, done)
}

/// The home LV in the form of record (docs/DEV-ENV.md); undone by `lvremove`
/// once `lvcreate` has succeeded.
fn make_home(env: &Env, host: &dyn Host, name: &str, home: &str, done: &mut Vec<Undo>) -> Result<()> {
    let (vg, lv) = home.split_once('/').unwrap_or_default();
    host.run(&[&env.bin("lvcreate"), "-q", "-V", HOME_LV_SIZE, "-T", &format!("{vg}/{POOL}"), "-n", lv])?;
    done.push(Undo::Home(home.to_string()));
    host.run(&[&env.bin("udevadm"), "settle"])?;
    let attr = host.run(&[&env.bin("lvs"), "--noheadings", "-o", "lv_attr", home])?.trim().to_string();
    let a = attr.as_bytes();
    if a.len() < 10 || a[4] != b'a' || a[9] == b'k' {
        return Err(format!("{home} has lv_attr '{attr}' after lvcreate: not active, or skip-activation set"));
    }
    host.run(&[&env.bin("mkfs.ext4"), "-q", &format!("/dev/{home}")])?;
    make_user_dir(env, host, name, home)?;
    log(format!("home {home}: {HOME_LV_SIZE} thin in {POOL}, ext4, user/ 1000:1000 0700 (lv_attr {attr})"));
    Ok(())
}

/// The instance delta over the layer; undone by removal (it did not exist:
/// every caller refuses an existing one first).
fn make_delta(env: &Env, host: &dyn Host, name: &str, app_lv: &str, done: &mut Vec<Undo>) -> Result<()> {
    let delta = env.delta_path(name);
    let delta_s = delta.to_string_lossy().into_owned();
    done.push(Undo::Delta(delta.clone()));
    host.run(&[&env.bin("qemu-img"), "create", "-q", "-f", "qcow2", "-F", "raw", "-b", &format!("/dev/{app_lv}"), &delta_s, DELTA_SIZE])?;
    fs::set_permissions(&delta, fs::Permissions::from_mode(0o644)).map_err(|e| format!("cannot chmod {delta_s}: {e}"))?;
    let m = fs::symlink_metadata(&delta).map_err(|e| format!("cannot stat {delta_s}: {e}"))?;
    if !m.is_file() {
        return Err(format!("{delta_s} is not a regular file after qemu-img create"));
    }
    log(format!("delta {delta_s}: qcow2 over /dev/{app_lv}, {DELTA_SIZE}, mode 0644"));
    Ok(())
}

/// Mounts the new home under `<run>/katmate-vm/`, the tree a T4 writes, and
/// makes `user/` 1000:1000 0700 (the form of record, docs/DEV-ENV.md).
fn make_user_dir(env: &Env, host: &dyn Host, name: &str, home: &str) -> Result<()> {
    let base = env.run_dir.join("katmate-vm");
    fs::create_dir_all(&base).map_err(|e| format!("cannot create {}: {e}", base.display()))?;
    fs::set_permissions(&base, fs::Permissions::from_mode(0o700)).map_err(|e| format!("cannot chmod {}: {e}", base.display()))?;
    let mnt = base.join(name);
    fs::create_dir(&mnt).map_err(|e| format!("cannot create the mount point {}: {e}", mnt.display()))?;
    let m = mnt.to_string_lossy().into_owned();
    let user = format!("{m}/user");
    let r = host.run(&[&env.bin("mount"), &format!("/dev/{home}"), &m]).and_then(|_| {
        let made = host.run(&[&env.bin("install"), "-d", "-o", "1000", "-g", "1000", "-m", "0700", &user]).and_then(|_| {
            let st = host.run(&[&env.bin("stat"), "-c", "%u:%g %a", &user])?;
            if st.trim() == "1000:1000 700" {
                Ok(())
            } else {
                Err(format!("{user} reads back as '{}', not 1000:1000 700", st.trim()))
            }
        });
        let unmounted = host.run(&[&env.bin("umount"), &m]);
        made.and(unmounted.map(|_| ()))
    });
    if let Err(e) = fs::remove_dir(&mnt) {
        return Err(format!("{}cannot remove the mount point {m}: {e}", r.err().map(|x| format!("{x}; ")).unwrap_or_default()));
    }
    r
}

// --- provision ----------------------------------------------------------------

/// Home and delta for an instance whose T1 file exists (the installer seeds
/// it, then calls this inside `arch-chroot`; cu4 ruling 9). The T1 file is
/// never written or removed here; the undo removes only what this run made.
pub fn provision(env: &Env, host: &dyn Host, name: &str) -> Result<()> {
    let (mut cid, mut window, mut undone) = (None, None, false);
    let r = provision_inner(env, host, name, &mut cid, &mut window, &mut undone);
    let result = match &r {
        Ok(()) => "provisioned".to_string(),
        Err(e) if undone => format!("undone: {e}"),
        Err(e) => format!("refused: {e}"),
    };
    let cid = cid.unwrap_or_else(|| "-".to_string());
    journal(env, host, &format!("provision {name} (CID {cid}, invoked by {}): {result}", invoked_by()));
    drop(window);
    r
}

fn provision_inner(env: &Env, host: &dyn Host, name: &str, cid_out: &mut Option<String>, window: &mut Option<SignalBlock>, undone: &mut bool) -> Result<()> {
    check_app_name(name)?;
    let _lock = launch_lock(env)?;

    let t1_path = env.t1_path(name);
    if !exists(&t1_path)? {
        return Err(format!("no T1 file {}: provision sets up an instance that has one; 'katmate-vm create' writes one", t1_path.display()));
    }
    let kv = t1::parse_kv(&host.run(&[&env.lib("katmate-t1-read"), name])?)?;
    *cid_out = kv.get("cid").cloned();
    let get = |k: &str| kv.get(k).map(String::as_str).unwrap_or("");
    if get("class") != "app" {
        return Err(format!("{}: class = '{}'; katmate-vm provisions AppVMs (class = app) only", t1_path.display(), get("class")));
    }
    if get("persistence") != "persistent" {
        return Err(format!("{}: persistence = '{}'; only a persistent home is provisioned (ADR-030 §7)", t1_path.display(), get("persistence")));
    }
    let layer = get("manifest").to_string();
    let d = env.d_path(name);
    if exists(&d)? {
        return Err(format!("{} exists beside the T1 file; not provisioned", d.display()));
    }
    let entries = cid::parse_pairs(&host.run(&[&env.lib("katmate-t1-read"), "--pairs"])?).map_err(|e| e.0)?;
    let report = cid::check(&entries);
    if !report.errors.is_empty() {
        return Err(format!("the CID set is not valid: {}", report.errors.join("; ")));
    }
    let delta = env.delta_path(name);
    if exists(&delta)? {
        return Err(format!("{} exists; provision makes a new delta and overwrites none", delta.display()));
    }

    let out = host.run(&[&env.lib("katmate-check-image"), "--layer", &layer]).map_err(|e| format!("layer '{layer}' refused: {e}"))?;
    let (vg, app_lv) = parse_app_lv(&out)?;
    log(format!("layer '{layer}': payload present, not stale, APP_LV={vg}/{app_lv}"));
    if let Some(h) = find_home(&list_lvs(env, host)?, name)? {
        return Err(format!("{h} exists; provision makes a new home and attaches none"));
    }
    host.run(&[&env.lib("katmate-activate-lvs"), "--layer", &layer]).map_err(|e| format!("layer '{layer}' refused: {e}"))?;
    log(format!("layer '{layer}': chain active and frozen"));

    let home = format!("{vg}/{}", home_lv(name));
    let mut done = Vec::new();
    *window = Some(SignalBlock::new()?);
    match make_home(env, host, name, &home, &mut done).and_then(|_| make_delta(env, host, name, &format!("{vg}/{app_lv}"), &mut done)) {
        Ok(()) => Ok(()),
        Err(e) => {
            *undone = true;
            let steps = undo(env, host, done);
            Err(format!("{e}. Undone, in reverse: {}", if steps.is_empty() { "nothing".to_string() } else { steps.join("; ") }))
        }
    }
}

// --- delete -------------------------------------------------------------------

/// As [`create`]: `Ok(Some(reason))` is deleted, menu not updated. The menu
/// is rewritten whenever the T1 file is gone at the end, a delete that failed
/// after its first removal included (cu5 ruling 4).
pub fn delete(env: &Env, host: &dyn Host, name: &str, purge: bool) -> Result<Option<String>> {
    let (mut cid, mut window, mut removing, mut lock) = (None, None, false, None);
    let r = delete_inner(env, host, name, purge, &mut lock, &mut cid, &mut window, &mut removing);
    let gone = removing && matches!(exists(&env.t1_path(name)), Ok(false));
    let menu = gone.then(|| menu_update(env, host).err()).flatten();
    let result = match &r {
        Ok(()) if purge => format!("purged{}", not_updated(&menu)),
        Ok(()) => format!("deleted{}", not_updated(&menu)),
        Err(e) if removing => format!("failed after the first removal: {e}{}", not_updated(&menu)),
        Err(e) => format!("refused: {e}"),
    };
    let cid = cid.unwrap_or_else(|| "-".to_string());
    journal(env, host, &format!("delete {name} (CID {cid}, invoked by {}): {result}", invoked_by()));
    drop(window);
    drop(lock);
    r.map(|()| menu)
}

#[allow(clippy::too_many_arguments)]
fn delete_inner(
    env: &Env,
    host: &dyn Host,
    name: &str,
    purge: bool,
    lock: &mut Option<LaunchLock>,
    cid_out: &mut Option<String>,
    window: &mut Option<SignalBlock>,
    removing: &mut bool,
) -> Result<()> {
    check_app_name(name)?;
    *lock = Some(launch_lock(env)?);

    let t1_path = env.t1_path(name);
    let has_t1 = exists(&t1_path)?;
    let delta = env.delta_path(name);
    let has_delta = exists(&delta)?;
    if has_t1 {
        let kv = t1::parse_kv(&host.run(&[&env.lib("katmate-t1-read"), name])?)?;
        *cid_out = kv.get("cid").cloned();
        let class = kv.get("class").map(String::as_str).unwrap_or("");
        if class != "app" {
            return Err(format!("{}: class = '{class}'; katmate-vm deletes AppVMs (class = app) only", t1_path.display()));
        }
        let d = env.d_path(name);
        if exists(&d)? {
            return Err(format!("{} exists: per-instance configuration beside the T1 file (ADR-032's note of 2026-09-27); not deleted", d.display()));
        }
    } else if !purge {
        return Err(format!("no T1 file {}: there is no instance '{name}'. A kept home is removed with 'katmate-vm delete {name} --purge'", t1_path.display()));
    } else if has_delta {
        return Err(format!("{} exists without a T1 file; --purge removes a kept home only", delta.display()));
    }

    let stop = format!("stop it first: katmate-launch --stop {name}");
    for unit in [routed_unit(name), offline_unit(name)] {
        if unit_live(&env.systemctl(), &unit).map_err(|e| e.0)? {
            let st = unit_state(&env.systemctl(), &unit).map_err(|e| e.0)?;
            return Err(format!("{unit} is '{st}'; {stop}"));
        }
    }
    if let Some((netvm, slot, link_id)) = held_slot(env, name)? {
        return Err(format!("{name} holds slot {slot} of netVM '{netvm}' (LINK_ID {link_id}); {stop}"));
    }

    let lvs = list_lvs(env, host)?;
    let home = find_home(&lvs, name)?;
    if purge {
        let Some(h) = &home else {
            return Err(format!("--purge: there is no home LV {}; nothing was removed", home_lv(name)));
        };
        if !host.stdin_is_tty() {
            return Err("--purge asks for the instance name on a terminal, and stdin is not one; nothing was removed".to_string());
        }
        confirm_purge(host, name, h)?;
    }

    *window = Some(SignalBlock::new()?);
    *removing = true;
    if has_t1 {
        fs::remove_file(&t1_path).map_err(|e| format!("cannot remove {}: {e}", t1_path.display()))?;
        log(format!("removed {}", t1_path.display()));
    }
    if has_delta {
        fs::remove_file(&delta).map_err(|e| format!("cannot remove {}: {e}", delta.display()))?;
        log(format!("removed {}", delta.display()));
    } else if has_t1 {
        log(format!("no delta {}; nothing to remove", delta.display()));
    }
    match (&home, purge) {
        (Some(h), true) => {
            host.run(&[&env.bin("lvremove"), "-q", "-y", h])?;
            log(format!("removed home {h}"));
        }
        (Some(h), false) => log(format!(
            "home {h} kept: 'katmate-vm create {name} --layer <layer> --reuse-home' attaches it, 'katmate-vm delete {name} --purge' removes it"
        )),
        (None, _) => log(format!("no home LV {}", home_lv(name))),
    }
    Ok(())
}

const PURGE_PROMPTS: usize = 3;

/// `--purge`'s confirmation (cu5f rulings 1, 2, 4): typeahead discarded
/// before every prompt; an empty answer asks again, up to [`PURGE_PROMPTS`]
/// prompts in all; a non-empty mismatch is refused at once.
fn confirm_purge(host: &dyn Host, name: &str, home: &str) -> Result<()> {
    for _ in 0..PURGE_PROMPTS {
        if let Some(w) = flush_warning(host.flush_input()) {
            eprintln!("[katmate-vm] WARNING: {w}");
        }
        let answer = host.ask(&format!("This removes {home}, the /home of {name}, for good. Type the instance name to confirm: "))?;
        if answer == name {
            return Ok(());
        }
        if !answer.is_empty() {
            return Err(format!("'{answer}' is not '{name}'; nothing was removed"));
        }
    }
    Err(format!("{PURGE_PROMPTS} empty answers to the prompt; nothing was removed"))
}

/// A flush never blocks a delete: `ENOTTY` is silent, any other error one
/// warning (cu5f ruling 5).
pub fn flush_warning(r: io::Result<()>) -> Option<String> {
    match r {
        Err(e) if e.raw_os_error() != Some(libc::ENOTTY) => Some(format!("cannot discard typeahead before the prompt ({e}); asking anyway")),
        _ => None,
    }
}

// --- menu ---------------------------------------------------------------------

/// `katmate-vm menu`: the entries regenerated under the launch lock, for
/// recovery after a create or delete that exited 3.
pub fn menu(env: &Env, host: &dyn Host) -> Result<()> {
    let r = launch_lock(env).and_then(|_lock| menu_update(env, host));
    let result = match &r {
        Ok(summary) => format!("updated: {summary}"),
        Err(e) => format!("not updated: {e}"),
    };
    journal(env, host, &format!("menu (invoked by {}): {result}", invoked_by()));
    r.map(|_| ())
}

fn rename_exchange(a: &Path, b: &Path) -> io::Result<()> {
    let a = CString::new(a.as_os_str().as_bytes())?;
    let b = CString::new(b.as_os_str().as_bytes())?;
    // SAFETY: two NUL-terminated paths that outlive the call.
    if unsafe { libc::renameat2(libc::AT_FDCWD, a.as_ptr(), libc::AT_FDCWD, b.as_ptr(), libc::RENAME_EXCHANGE) } == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

/// Generates `<desktop>/applications.new` and swaps it with the live
/// directory in one `renameat2(RENAME_EXCHANGE)` (cu5 ruling 3), so a path
/// lookup finds the old set or the new one, never a missing or partial
/// directory; a failure before the swap leaves the live set as it was. The
/// old set is kept as `applications.old` until the next update, so a reader
/// that opened it before the swap reads it whole (H2 ruling 1). The caller
/// holds the launch lock. Answers the generator's summary line.
pub fn menu_update(env: &Env, host: &dyn Host) -> Result<String> {
    let base = &env.desktop;
    fs::create_dir_all(base).map_err(|e| format!("cannot create {}: {e}", base.display()))?;
    let m = fs::symlink_metadata(base).map_err(|e| format!("cannot stat {}: {e}", base.display()))?;
    if !m.is_dir() {
        return Err(format!("{} is not a directory", base.display()));
    }
    fs::set_permissions(base, fs::Permissions::from_mode(0o755)).map_err(|e| format!("cannot chmod {}: {e}", base.display()))?;
    let live = base.join("applications");
    let new = base.join("applications.new");
    let old = base.join("applications.old");
    let remove = |p: &Path| match fs::remove_dir_all(p) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("cannot remove {}: {e}", p.display())),
    };
    if exists(&new)? {
        remove(&new)?;
        log(format!("removed {}, left by an interrupted run", new.display()));
    }
    remove(&old)?;

    let gen = host.run(&[
        &env.lib("katmate-generate-menu"),
        &env.etc_vm.to_string_lossy(),
        &env.t2.to_string_lossy(),
        &new.to_string_lossy(),
    ]);
    let swapped = gen.and_then(|out| {
        let exchanged = match fs::symlink_metadata(&live) {
            Ok(m) if m.is_dir() => {
                rename_exchange(&new, &live).map_err(|e| format!("cannot exchange {} with {}: {e}", new.display(), live.display()))?;
                true
            }
            Ok(_) => return Err(format!("{} is not a directory; not replaced", live.display())),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                fs::rename(&new, &live).map_err(|e| format!("cannot rename {} to {}: {e}", new.display(), live.display()))?;
                false
            }
            Err(e) => return Err(format!("cannot stat {}: {e}", live.display())),
        };
        Ok((exchanged, out.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("").trim().to_string()))
    });
    // The live set is right from here on, so what is left beside it is only
    // a warning; the next update removes it.
    let leftover = match &swapped {
        Ok((true, _)) => fs::rename(&new, &old).map_err(|e| format!("cannot rename {} to {}: {e}", new.display(), old.display())),
        _ => remove(&new),
    };
    if let Err(e) = leftover {
        eprintln!("[katmate-vm] WARNING: {e}; the next menu update removes it");
    }
    let (_, summary) = swapped?;
    log(format!("menu: {summary}; swapped in as {}", live.display()));
    Ok(summary)
}

// --- status -------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub name: String,
    pub cid: String,
    pub layer: String,
    pub netvm: String,
    pub unit: String,
    pub slot: String,
    pub link_id: String,
    pub home: String,
}

impl Row {
    fn kept(name: &str, home: &str) -> Row {
        let d = || "-".to_string();
        Row { name: name.to_string(), cid: d(), layer: d(), netvm: d(), unit: d(), slot: d(), link_id: d(), home: format!("{home} (kept home)") }
    }
}

pub fn header() -> String {
    fmt_row(&Row {
        name: "NAME".into(),
        cid: "CID".into(),
        layer: "LAYER".into(),
        netvm: "NETVM".into(),
        unit: "UNIT".into(),
        slot: "SLOT".into(),
        link_id: "LINK_ID".into(),
        home: "HOME".into(),
    })
}

pub fn fmt_row(r: &Row) -> String {
    format!("{:<20} {:>3} {:<8} {:<8} {:<12} {:<4} {:<7} {}", r.name, r.cid, r.layer, r.netvm, r.unit, r.slot, r.link_id, r.home)
}

fn t1_names(env: &Env) -> Result<Vec<String>> {
    let rd = fs::read_dir(&env.etc_vm).map_err(|e| format!("cannot read {}: {e}", env.etc_vm.display()))?;
    let mut names = BTreeSet::new();
    for ent in rd {
        let ent = ent.map_err(|e| format!("cannot read {}: {e}", env.etc_vm.display()))?;
        if let Some(stem) = ent.file_name().to_string_lossy().strip_suffix(".toml") {
            names.insert(stem.to_string());
        }
    }
    Ok(names.into_iter().collect())
}

fn instance_row(env: &Env, host: &dyn Host, name: &str, lvs: &[(String, String)]) -> Result<Option<Row>> {
    let kv = t1::parse_kv(&host.run(&[&env.lib("katmate-t1-read"), name])?)?;
    if kv.get("class").map(String::as_str) != Some("app") {
        return Ok(None);
    }
    let get = |k: &str| kv.get(k).cloned().unwrap_or_else(|| "?".to_string());
    let netvm = kv.get("netvm").cloned().unwrap_or_default();
    let unit = if netvm.is_empty() { offline_unit(name) } else { routed_unit(name) };
    let state = unit_state(&env.systemctl(), &unit).map_err(|e| e.0)?;
    let (mut slot, mut link_id) = ("-".to_string(), "-".to_string());
    if !netvm.is_empty() && env.run_dir.join("link").join(&netvm).is_dir() {
        let pool = Pool::new(&env.run_dir, &netvm).map_err(|e| e.0)?;
        if let Some((s, o)) = pool.lock().and_then(|l| l.find(name)).map_err(|e| e.0)? {
            slot = s.to_string();
            link_id = o.link_id.to_string();
        }
    }
    Ok(Some(Row {
        name: name.to_string(),
        cid: get("cid"),
        layer: get("manifest"),
        netvm: if netvm.is_empty() { "offline".to_string() } else { netvm },
        unit: state,
        slot,
        link_id,
        home: find_home(lvs, name)?.unwrap_or_else(|| "absent".to_string()),
    }))
}

/// Rows for one name, or for every `class = app` T1 file plus every kept home
/// without one. An instance whose T1 cannot be read is an error line.
pub fn status(env: &Env, host: &dyn Host, name: Option<&str>) -> Result<(Vec<Row>, Vec<String>)> {
    let lvs = list_lvs(env, host)?;
    let t1 = t1_names(env)?;
    let (mut rows, mut errors) = (Vec::new(), Vec::new());
    let wanted: Vec<String> = match name {
        Some(n) => {
            check_name(n).map_err(|e| e.0)?;
            t1.iter().filter(|t| *t == n).cloned().collect()
        }
        None => t1.clone(),
    };
    for n in &wanted {
        match instance_row(env, host, n, &lvs) {
            Ok(Some(r)) => rows.push(r),
            Ok(None) if name.is_some() => return Err(format!("{n} is not an AppVM (class = app)")),
            Ok(None) => {}
            Err(e) => errors.push(format!("{n}: {e}")),
        }
    }
    for (vg, lv) in &lvs {
        let Some(owner) = lv.strip_prefix("vm_").and_then(|s| s.strip_suffix("_home")) else { continue };
        if t1.iter().any(|t| t == owner) || name.is_some_and(|n| n != owner) {
            continue;
        }
        rows.push(Row::kept(owner, &format!("{vg}/{lv}")));
    }
    if let Some(n) = name {
        if rows.is_empty() && errors.is_empty() {
            return Err(format!("no instance '{n}': no T1 file and no home LV {}", home_lv(n)));
        }
    }
    Ok((rows, errors))
}
