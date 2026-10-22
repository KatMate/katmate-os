//! Fixtures: a temp tree with the alpha's T1 templates, the real
//! `katmate-lib.sh` and `katmate-t1-read` with their path constants rewritten
//! into it (the method of host/tests/test-layer-run.sh), the real
//! `katmate-generate-menu` beside them with three layer metas, a stub
//! `systemctl`, and a recording [`Fake`] host for LVM, mkfs, mount and qemu-img.

use crate::host::{reason, Host, RealHost};
use crate::t1::{self, Props};
use crate::vm::{self, CreateOpts, Env};
use katmate_alloc::{write_file, Owner};
use std::cell::RefCell;
use std::collections::{BTreeSet, VecDeque};
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

/// Literal replacement that must match, as `rw` in test-layer-run.sh.
fn rw(text: &str, from: &str, to: &str) -> String {
    assert!(text.contains(from), "rewrite target absent: {from}");
    text.replace(from, to)
}

fn exe(path: &Path, text: &str) {
    let tmp = path.with_extension("new");
    fs::write(&tmp, text).unwrap();
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755)).unwrap();
    fs::rename(&tmp, path).unwrap();
}

struct Fixture {
    root: PathBuf,
    env: Env,
}

impl Fixture {
    fn new() -> Fixture {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!("katmate-vm-test.{}.{}", std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)));
        for d in ["etc/katmate/vm", "var/lib/katmate/instances", "run/katmate", "lib", "bin", "units"] {
            fs::create_dir_all(root.join(d)).unwrap();
        }
        let k = repo().join("host/usr/lib/katmate");
        let lib = fs::read_to_string(k.join("katmate-lib.sh")).unwrap();
        let lib = rw(&lib, "KM_ETC_VM=\"/etc/katmate/vm\"", &format!("KM_ETC_VM=\"{}\"", root.join("etc/katmate/vm").display()));
        fs::write(root.join("lib/katmate-lib.sh"), lib).unwrap();
        let reader = fs::read_to_string(k.join("katmate-t1-read")).unwrap();
        let reader = rw(&reader, "source /usr/lib/katmate/katmate-lib.sh", &format!("source {}", root.join("lib/katmate-lib.sh").display()));
        exe(&root.join("lib/katmate-t1-read"), &reader);
        exe(&root.join("lib/katmate-generate-menu"), &fs::read_to_string(k.join("katmate-generate-menu")).unwrap());
        for (layer, run) in [("web", "firefox-esr foot pcmanfm"), ("office", "libreoffice foot pcmanfm"), ("vault", "keepassxc foot pcmanfm")] {
            fs::write(root.join(format!("var/lib/katmate/app-{layer}.meta")), format!("KATMATE_META_VERSION=1\nRUN={run}\n")).unwrap();
        }
        exe(
            &root.join("bin/systemctl"),
            &format!("#!/bin/sh\nf='{}'/\"$2\"\nif [ -f \"$f\" ]; then cat \"$f\"; else echo inactive; fi\nexit 3\n", root.join("units").display()),
        );
        for f in fs::read_dir(repo().join("installer/t1")).unwrap() {
            let f = f.unwrap().path();
            let stem = f.file_name().unwrap().to_string_lossy().trim_end_matches(".toml.in").to_string();
            fs::copy(&f, root.join("etc/katmate/vm").join(format!("{stem}.toml"))).unwrap();
        }
        let env = Env {
            etc_vm: root.join("etc/katmate/vm"),
            instances: root.join("var/lib/katmate/instances"),
            run_dir: root.join("run/katmate"),
            t2: root.join("var/lib/katmate"),
            desktop: root.join("var/lib/katmate/desktop"),
            bin: root.join("bin"),
            lib: root.join("lib"),
            lock_timeout: Duration::from_millis(300),
        };
        Fixture { root, env }
    }

    fn unit(&self, unit: &str, state: &str) {
        fs::write(self.root.join("units").join(unit), format!("{state}\n")).unwrap();
    }

    fn owner(&self, netvm: &str, slot: &str, instance: &str, link_id: u32) {
        let d = self.env.run_dir.join("link").join(netvm);
        for s in katmate_alloc::SLOTS {
            fs::create_dir_all(d.join(s)).unwrap();
        }
        write_file(&d.join(slot).join("owner"), &Owner { instance: instance.into(), link_id }.text(), true).unwrap();
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

/// Runs the helpers for real; records and answers everything else. `lvs`
/// holds the LV set as `vg/lv`.
struct Fake {
    calls: RefCell<Vec<String>>,
    lvs: RefCell<BTreeSet<String>>,
    fail_on: Option<String>,
    check_image: Result<String, String>,
    blkid: String,
    tty: bool,
    /// One per prompt, in order; a prompt beyond them is a test failure.
    answers: RefCell<VecDeque<String>>,
    /// The errno `flush_input` fails with.
    flush_errno: Option<i32>,
    /// Rewrites one instance read's output: what a parser disagreeing with
    /// the writer would answer.
    tamper: Option<(&'static str, &'static str)>,
    /// Raises SIGHUP at the call starting with this, and records how many
    /// SIGHUPs had been handled right after the raise.
    hup_at: Option<&'static str>,
    hups_seen_at_raise: RefCell<Option<usize>>,
}

static HUPS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

extern "C" fn on_hup(_: libc::c_int) {
    HUPS.fetch_add(1, Ordering::SeqCst);
}

impl Fake {
    fn new() -> Fake {
        Fake {
            calls: RefCell::new(Vec::new()),
            lvs: RefCell::new(["vg0/vm_tpl_foundation", "vg0/vm_app_web", "vg0/vm_app_web_home"].map(String::from).into()),
            fail_on: None,
            check_image: Ok("[katmate-check-image] layer 'web' OK\nAPP_LV=vg0/vm_app_web\n".into()),
            blkid: "ext4\n".into(),
            tty: true,
            answers: RefCell::new(VecDeque::new()),
            flush_errno: None,
            tamper: None,
            hup_at: None,
            hups_seen_at_raise: RefCell::new(None),
        }
    }

    fn calls(&self) -> Vec<String> {
        self.calls.borrow().clone()
    }

    fn called(&self, prefix: &str) -> bool {
        self.calls.borrow().iter().any(|c| c.starts_with(prefix))
    }
}

impl Host for Fake {
    fn run(&self, argv: &[&str]) -> Result<String, String> {
        let prog = Path::new(argv[0]).file_name().unwrap().to_string_lossy().into_owned();
        let line = std::iter::once(prog.as_str()).chain(argv[1..].iter().copied()).collect::<Vec<_>>().join(" ");
        self.calls.borrow_mut().push(line.clone());
        if self.hup_at.is_some_and(|h| line.starts_with(h)) {
            // raise(3) targets this thread, whose mask SignalBlock sets.
            unsafe { libc::raise(libc::SIGHUP) };
            *self.hups_seen_at_raise.borrow_mut() = Some(HUPS.load(Ordering::SeqCst));
        }
        if self.fail_on.as_deref().is_some_and(|f| line.starts_with(f)) {
            return Err(format!("{line}: injected failure"));
        }
        match prog.as_str() {
            "katmate-t1-read" => match (self.tamper, argv[1]) {
                (Some((from, to)), a) if a != "--pairs" => RealHost.run(argv).map(|o| o.replace(from, to)),
                _ => RealHost.run(argv),
            },
            "katmate-check-image" => self.check_image.clone(),
            "katmate-generate-menu" => RealHost.run(argv),
            "lvs" if argv.contains(&"vg_name,lv_name") => Ok(self.lvs.borrow().iter().map(|l| format!("  {l}\n")).collect()),
            "lvs" => Ok("  Vwi-a-tz--\n".into()),
            "lvcreate" => {
                let vg = argv[argv.iter().position(|a| *a == "-T").unwrap() + 1].split('/').next().unwrap();
                let lv = argv[argv.iter().position(|a| *a == "-n").unwrap() + 1];
                self.lvs.borrow_mut().insert(format!("{vg}/{lv}"));
                Ok(String::new())
            }
            "lvremove" => {
                assert!(self.lvs.borrow_mut().remove(*argv.last().unwrap()), "lvremove of an absent LV");
                Ok(String::new())
            }
            "stat" => Ok("1000:1000 700\n".into()),
            "blkid" => Ok(self.blkid.clone()),
            "qemu-img" => {
                fs::write(argv[argv.len() - 2], b"QFI\xfb").unwrap();
                Ok(String::new())
            }
            _ => Ok(String::new()),
        }
    }

    fn stdin_is_tty(&self) -> bool {
        self.tty
    }

    fn flush_input(&self) -> std::io::Result<()> {
        self.calls.borrow_mut().push("flush".into());
        self.flush_errno.map_or(Ok(()), |e| Err(std::io::Error::from_raw_os_error(e)))
    }

    fn ask(&self, prompt: &str) -> Result<String, String> {
        self.calls.borrow_mut().push(format!("ask {prompt}"));
        Ok(self.answers.borrow_mut().pop_front().unwrap_or_else(|| panic!("a prompt with no answer scripted: {prompt}")))
    }
}

fn answers(a: &[&str]) -> RefCell<VecDeque<String>> {
    RefCell::new(a.iter().map(|s| s.to_string()).collect())
}

fn opts(name: &str) -> CreateOpts {
    CreateOpts {
        name: name.into(),
        layer: "web".into(),
        mem: t1::MEM_DEFAULT.into(),
        vcpus: t1::VCPUS_DEFAULT.into(),
        offline: false,
        reuse_home: false,
    }
}

fn mode(p: &Path) -> u32 {
    fs::metadata(p).unwrap().permissions().mode() & 0o7777
}

// --- T1 text ------------------------------------------------------------------

#[test]
fn t1_text_is_the_template_key_set() {
    let p = Props { cid: 32, manifest: "web".into(), netvm: "netvm".into(), mem: "2G".into(), vcpus: "2".into() };
    assert_eq!(
        t1::text("app_x", &p),
        "# T1 instance properties of app_x, written by katmate-vm create (ADR-032 §1).\n\
         class = \"app\"\ncid = 32\nmanifest = \"web\"\nnetvm = \"netvm\"\npersistence = \"persistent\"\n\
         identity = false\ndisposable = false\nmem = \"2G\"\nvcpus = 2\n"
    );
    // The same nine keys as installer/t1/app_sandbox.toml.in, the template it follows.
    let tpl = fs::read_to_string(repo().join("installer/t1/app_sandbox.toml.in")).unwrap();
    let keys = |s: &str| -> Vec<String> { s.lines().filter(|l| !l.starts_with('#') && l.contains('=')).map(|l| l.split('=').next().unwrap().trim().to_string()).collect() };
    assert_eq!(keys(&t1::text("app_x", &p)), keys(&tpl));
    assert_eq!(t1::expected(&p).len(), 9);
}

#[test]
fn mem_and_vcpus_patterns() {
    for ok in ["2G", "512M", "16G"] {
        assert!(t1::check_mem(ok).is_ok(), "{ok}");
    }
    for bad in ["", "G", "2", "2g", "2GB", "-2G", "2 G"] {
        assert!(t1::check_mem(bad).is_err(), "{bad}");
    }
    for ok in ["1", "2", "16"] {
        assert!(t1::check_vcpus(ok).is_ok(), "{ok}");
    }
    for bad in ["", "0", "02", "-1", "2x"] {
        assert!(t1::check_vcpus(bad).is_err(), "{bad}");
    }
}

#[test]
fn kv_parse_and_diff() {
    let m = t1::parse_kv("a=1\nb=x=y\nc=\n").unwrap();
    assert_eq!(m.get("b").unwrap(), "x=y");
    assert_eq!(m.get("c").unwrap(), "");
    assert!(t1::parse_kv("a=1\na=2\n").is_err());
    assert!(t1::parse_kv("novalue\n").is_err());
    let w = t1::parse_kv("a=1\nb=2\n").unwrap();
    let g = t1::parse_kv("a=1\nb=3\nc=4\n").unwrap();
    assert_eq!(t1::diff(&w, &g), vec!["b: wrote '2', read '3'", "c: not written, read '4'"]);
}

#[test]
fn app_lv_line() {
    assert_eq!(vm::parse_app_lv("x\nAPP_LV=vg0/vm_app_web\n").unwrap(), ("vg0".into(), "vm_app_web".into()));
    for bad in ["", "APP_LV=\n", "APP_LV=vm_app_web\n", "APP_LV=vg0/\n", "APP_LV=vg0/a b\n", "APP_LV=-x/y\n", "APP_LV=vg0/x\nmore\n"] {
        assert!(vm::parse_app_lv(bad).is_err(), "{bad:?}");
    }
}

#[test]
fn names() {
    assert!(vm::check_app_name("app_cu4a").is_ok());
    for bad in ["cu4a", "app_", "netvm", "gw_w2", "App_x", "app-x", "../app_x", ""] {
        assert!(vm::check_app_name(bad).is_err(), "{bad}");
    }
    assert!(vm::check_app_name("cu4a").unwrap_err().contains("does not begin with app_"));
}

#[test]
fn failure_reason_prefers_fatal_lines() {
    assert_eq!(reason("log\n", "[x] FATAL: one\nnoise\n[x] FATAL: two\n"), "[x] FATAL: one | [x] FATAL: two");
    assert_eq!(reason("out\n", "a\nlast\n\n"), "last");
    assert_eq!(reason("first\nlast out\n", ""), "last out");
}

// --- create -------------------------------------------------------------------

#[test]
fn create_writes_t1_home_and_delta_in_order() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_cu4a")).unwrap();

    let t1p = f.env.t1_path("app_cu4a");
    let want = Props { cid: 32, manifest: "web".into(), netvm: "netvm".into(), mem: "2G".into(), vcpus: "2".into() };
    assert_eq!(fs::read_to_string(&t1p).unwrap(), t1::text("app_cu4a", &want));
    assert_eq!(mode(&t1p), 0o644);
    let delta = f.env.delta_path("app_cu4a");
    assert_eq!(mode(&delta), 0o644);
    assert!(h.lvs.borrow().contains("vg0/vm_app_cu4a_home"));

    let calls = h.calls();
    let order: Vec<&str> = calls
        .iter()
        .map(|c| c.split(' ').next().unwrap())
        .filter(|p| !matches!(*p, "lvs" | "logger"))
        .collect();
    assert_eq!(
        order,
        [
            "katmate-check-image", "katmate-activate-lvs", "katmate-t1-read", "katmate-t1-read", "lvcreate", "udevadm", "mkfs.ext4",
            "mount", "install", "stat", "umount", "qemu-img", "katmate-generate-menu"
        ]
    );
    // The menu is rewritten under the lock, before the outcome line.
    let pos = |p: &str| calls.iter().position(|c| c.starts_with(p)).unwrap();
    assert!(pos("qemu-img") < pos("katmate-generate-menu") && pos("katmate-generate-menu") < pos("logger"));
    assert!(h.called("lvcreate -q -V 10G -T vg0/vm_pool -n vm_app_cu4a_home"));
    assert!(h.called("katmate-t1-read app_cu4a"));
    assert!(h.called(&format!("qemu-img create -q -f qcow2 -F raw -b /dev/vg0/vm_app_web {} 10G", delta.display())));
    assert!(h.called(&format!("install -d -o 1000 -g 1000 -m 0700 {}/user", f.env.run_dir.join("katmate-vm/app_cu4a").display())));
    // The mount point is gone, its parent is root-only.
    assert!(!f.env.run_dir.join("katmate-vm/app_cu4a").exists());
    assert_eq!(mode(&f.env.run_dir.join("katmate-vm")), 0o700);
    assert_eq!(mode(&f.env.run_dir.join("launch")), 0o700);
}

#[test]
fn create_offline_and_options_read_back() {
    let f = Fixture::new();
    let h = Fake::new();
    let mut o = opts("app_off");
    o.offline = true;
    o.mem = "512M".into();
    o.vcpus = "1".into();
    vm::create(&f.env, &h, &o).unwrap();
    let out = RealHost.run(&[f.env.lib.join("katmate-t1-read").to_str().unwrap(), "app_off"]).unwrap();
    assert_eq!(out, "cid=32\nclass=app\ndisposable=false\nidentity=false\nmanifest=web\nmem=512M\nnetvm=\npersistence=persistent\nvcpus=1\n");
}

#[test]
fn cid_is_the_lowest_free_over_the_tree() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_a")).unwrap();
    vm::create(&f.env, &h, &opts("app_b")).unwrap();
    fs::remove_file(f.env.t1_path("app_a")).unwrap();
    fs::remove_file(f.env.delta_path("app_a")).unwrap();
    h.lvs.borrow_mut().remove("vg0/vm_app_a_home");
    vm::create(&f.env, &h, &opts("app_c")).unwrap();
    let cid = |n: &str| t1::parse_kv(&RealHost.run(&[f.env.lib.join("katmate-t1-read").to_str().unwrap(), n]).unwrap()).unwrap()["cid"].clone();
    assert_eq!((cid("app_b"), cid("app_c")), ("33".to_string(), "32".to_string()));
}

#[test]
fn create_refusals_leave_nothing() {
    let f = Fixture::new();
    let before = fs::read_dir(&f.env.etc_vm).unwrap().count();
    let refuse = |h: &Fake, o: &CreateOpts, want: &str| {
        let e = vm::create(&f.env, h, o).unwrap_err();
        assert!(e.contains(want), "{e}");
        assert!(!f.env.t1_path(&o.name).exists() || o.name == "app_web", "{e}");
        assert!(!h.called("lvcreate") && !h.called("qemu-img"), "{e}");
    };
    refuse(&Fake::new(), &opts("cu4a"), "does not begin with app_");
    refuse(&Fake::new(), &opts("app_web"), "is there already");
    let mut o = opts("app_x");
    o.mem = "2GB".into();
    refuse(&Fake::new(), &o, "--mem");

    fs::write(f.env.delta_path("app_x"), b"").unwrap();
    refuse(&Fake::new(), &opts("app_x"), "a leftover");
    fs::remove_file(f.env.delta_path("app_x")).unwrap();
    fs::create_dir(f.env.d_path("app_x")).unwrap();
    refuse(&Fake::new(), &opts("app_x"), "exists without a T1 file");
    fs::remove_dir(f.env.d_path("app_x")).unwrap();

    let mut h = Fake::new();
    h.check_image = Err("katmate-check-image --layer web exited 1: [katmate-check-image] FATAL: layer 'web' is stale".into());
    refuse(&h, &opts("app_x"), "layer 'web' refused: katmate-check-image --layer web exited 1: [katmate-check-image] FATAL: layer 'web' is stale");
    h.check_image = Ok("APP_LV=vg0/vm_app_web\n".into());
    h.fail_on = Some("katmate-activate-lvs".into());
    refuse(&h, &opts("app_x"), "layer 'web' refused");

    h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_x_home".into());
    refuse(&h, &opts("app_x"), "vg0/vm_app_x_home exists: a kept home");
    let mut o = opts("app_y");
    o.reuse_home = true;
    refuse(&Fake::new(), &o, "no home LV vm_app_y_home");
    h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_y_home".into());
    h.blkid = "xfs\n".into();
    refuse(&h, &o, "TYPE 'xfs', not ext4");
    h.lvs.borrow_mut().insert("vg1/vm_app_y_home".into());
    refuse(&h, &o, "more than one volume group");

    // A CID carried twice in the tree stops the choice.
    fs::write(f.env.t1_path("app_dup"), "class = \"app\"\ncid = 21\n").unwrap();
    refuse(&Fake::new(), &opts("app_x"), "cid 21 is carried by more than one T1 file");
    fs::remove_file(f.env.t1_path("app_dup")).unwrap();

    assert_eq!(fs::read_dir(&f.env.etc_vm).unwrap().count(), before);
    assert_eq!(fs::read_dir(&f.env.instances).unwrap().count(), 0);
}

/// Each step after the T1 write fails in turn; what was made is undone in
/// reverse, and the tree is as before.
#[test]
fn create_rolls_back_in_reverse() {
    let cases: [(&str, &[&str]); 8] = [
        ("katmate-t1-read app_r", &["removed T1"]),
        ("lvcreate", &["removed T1"]),
        ("udevadm", &["lvremove", "removed T1"]),
        ("mkfs.ext4", &["lvremove", "removed T1"]),
        ("mount", &["lvremove", "removed T1"]),
        ("install", &["lvremove", "removed T1"]),
        ("umount", &["lvremove", "removed T1"]),
        ("qemu-img", &["removed delta", "lvremove", "removed T1"]),
    ];
    for (step, want) in cases {
        let f = Fixture::new();
        let mut h = Fake::new();
        h.fail_on = Some(step.into());
        let e = vm::create(&f.env, &h, &opts("app_r")).unwrap_err();
        let undone = e.split("Undone, in reverse: ").nth(1).unwrap_or_else(|| panic!("{step}: {e}"));
        let got: Vec<&str> = undone
            .split("; ")
            .map(|s| {
                if s.starts_with("lvremove vg0/vm_app_r_home") {
                    "lvremove"
                } else if s.contains("app_r.toml") {
                    "removed T1"
                } else if s.contains("app_r.qcow2") {
                    "removed delta"
                } else {
                    s
                }
            })
            .collect();
        assert_eq!(got, want, "{step}: {e}");
        assert!(!f.env.t1_path("app_r").exists(), "{step}");
        assert!(!f.env.delta_path("app_r").exists(), "{step}");
        assert!(!h.lvs.borrow().contains("vg0/vm_app_r_home"), "{step}");
        assert!(!f.env.run_dir.join("katmate-vm/app_r").exists(), "{step}: mount point left");
        if matches!(step, "install" | "umount") {
            assert!(h.called("umount"), "{step}: not unmounted");
        }
    }
}

#[test]
fn read_back_mismatch_undoes_the_write() {
    for (from, to, want) in [
        ("cid=32\n", "cid=33\n", "cid: wrote '32', read '33'"),
        ("netvm=netvm\n", "", "netvm: wrote 'netvm', read nothing"),
        ("vcpus=2\n", "vcpus=2\nextra=1\n", "extra: not written, read '1'"),
    ] {
        let f = Fixture::new();
        let mut h = Fake::new();
        h.tamper = Some((from, to));
        let e = vm::create(&f.env, &h, &opts("app_m")).unwrap_err();
        assert!(e.contains("does not read back as written") && e.contains(want), "{e}");
        assert!(!f.env.t1_path("app_m").exists() && !h.called("lvcreate"), "{e}");
    }
}

#[test]
fn reuse_home_attaches_and_never_removes_it() {
    let f = Fixture::new();
    let mut h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_k_home".into());
    let mut o = opts("app_k");
    o.reuse_home = true;
    h.fail_on = Some("qemu-img".into());
    let e = vm::create(&f.env, &h, &o).unwrap_err();
    assert!(!e.contains("lvremove") && !h.called("lvremove"), "{e}");
    assert!(h.lvs.borrow().contains("vg0/vm_app_k_home"));
    assert!(!f.env.t1_path("app_k").exists());

    h.fail_on = None;
    vm::create(&f.env, &h, &o).unwrap();
    assert!(h.called("blkid -o value -s TYPE /dev/vg0/vm_app_k_home"));
    assert!(!h.called("lvcreate") && !h.called("mkfs.ext4") && !h.called("mount"));
}

#[test]
fn create_waits_for_the_launch_lock() {
    let f = Fixture::new();
    let _held = vm::launch_lock(&f.env).unwrap();
    let e = vm::create(&f.env, &Fake::new(), &opts("app_l")).unwrap_err();
    assert!(e.contains("has held") && e.contains("launch/lock"), "{e}");
    let e = vm::delete(&f.env, &Fake::new(), "app_web", false).unwrap_err();
    assert!(e.contains("has held"), "{e}");
}

/// A SIGHUP raised inside the window is handled only after it closes; one
/// raised before the window (the control) is handled at once. Subcases
/// run in sequence on one thread, so the counter is this test's alone.
#[test]
fn signals_inside_the_window_are_deferred() {
    // SAFETY: installs a handler that only bumps an atomic.
    unsafe { libc::signal(libc::SIGHUP, on_hup as extern "C" fn(libc::c_int) as libc::sighandler_t) };
    let f = Fixture::new();
    let run = |at: &'static str, fail: Option<&str>, del: bool| -> (usize, usize) {
        let mut h = Fake::new();
        h.hup_at = Some(at);
        h.fail_on = fail.map(String::from);
        h.answers = answers(&["app_s"]);
        let before = HUPS.load(Ordering::SeqCst);
        let _ = if del { vm::delete(&f.env, &h, "app_s", true) } else { vm::create(&f.env, &h, &opts("app_s")) };
        let seen = h.hups_seen_at_raise.borrow().unwrap_or_else(|| panic!("{at}: never raised"));
        (seen - before, HUPS.load(Ordering::SeqCst) - before)
    };
    assert_eq!(run("katmate-check-image", None, false), (1, 1), "control: before the window, handled at once");
    let _ = vm::delete(&f.env, &Fake::new(), "app_s", false);
    assert_eq!(run("mkfs.ext4", None, false), (0, 1), "create: deferred until create finished");
    let _ = vm::delete(&f.env, &Fake::new(), "app_s", false);
    assert_eq!(run("qemu-img", Some("qemu-img"), false), (0, 1), "create: deferred until the undo ran");
    let h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_s_home".into());
    vm::create(&f.env, &h, &{
        let mut o = opts("app_s");
        o.reuse_home = true;
        o
    })
    .unwrap();
    // delete --purge: the window is from the T1 removal to the lvremove.
    let mut h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_s_home".into());
    h.hup_at = Some("lvremove");
    h.answers = answers(&["app_s"]);
    let before = HUPS.load(Ordering::SeqCst);
    vm::delete(&f.env, &h, "app_s", true).unwrap();
    assert_eq!((h.hups_seen_at_raise.borrow().unwrap() - before, HUPS.load(Ordering::SeqCst) - before), (0, 1), "delete: deferred");
}

#[test]
fn one_journal_line_per_outcome() {
    let f = Fixture::new();
    let journal = |h: &Fake| -> Vec<String> { h.calls().into_iter().filter(|c| c.starts_with("logger")).collect() };
    let by = std::env::var("SUDO_USER").unwrap_or_else(|_| "<no SUDO_USER>".into());

    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_j")).unwrap();
    assert_eq!(journal(&h), [format!("logger -t katmate-vm -- create app_j (CID 32, invoked by {by}): created")]);

    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_j")).unwrap_err();
    let j = journal(&h);
    assert!(j.len() == 1 && j[0].starts_with(&format!("logger -t katmate-vm -- create app_j (CID -, invoked by {by}): refused: ")), "{j:?}");

    let mut h = Fake::new();
    h.fail_on = Some("mkfs.ext4".into());
    vm::create(&f.env, &h, &opts("app_u")).unwrap_err();
    let j = journal(&h);
    assert!(j.len() == 1 && j[0].contains("create app_u (CID 33, ") && j[0].contains("): undone: ") && j[0].contains("Undone, in reverse"), "{j:?}");

    let h = Fake::new();
    vm::delete(&f.env, &h, "app_j", false).unwrap();
    assert_eq!(journal(&h), [format!("logger -t katmate-vm -- delete app_j (CID 32, invoked by {by}): deleted")]);

    let mut h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_j_home".into());
    h.answers = answers(&["app_j"]);
    vm::delete(&f.env, &h, "app_j", true).unwrap();
    assert_eq!(journal(&h), [format!("logger -t katmate-vm -- delete app_j (CID -, invoked by {by}): purged")]);

    let h = Fake::new();
    vm::delete(&f.env, &h, "app_j", false).unwrap_err();
    let j = journal(&h);
    assert!(j.len() == 1 && j[0].contains("delete app_j (CID -, ") && j[0].contains("): refused: no T1 file"), "{j:?}");
}

// --- delete -------------------------------------------------------------------

#[test]
fn delete_keeps_the_home_by_default() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_d")).unwrap();
    vm::delete(&f.env, &h, "app_d", false).unwrap();
    assert!(!f.env.t1_path("app_d").exists());
    assert!(!f.env.delta_path("app_d").exists());
    assert!(h.lvs.borrow().contains("vg0/vm_app_d_home"));
    assert!(!h.called("lvremove"));

    // The kept home shows, then comes back with --reuse-home, then goes.
    let (rows, errors) = vm::status(&f.env, &h, None).unwrap();
    assert!(errors.is_empty());
    assert!(rows.iter().any(|r| r.name == "app_d" && r.home == "vg0/vm_app_d_home (kept home)"));
    let mut o = opts("app_d");
    o.reuse_home = true;
    vm::create(&f.env, &h, &o).unwrap();
    let mut h2 = Fake::new();
    h2.lvs = h.lvs;
    h2.answers = answers(&["app_d"]);
    vm::delete(&f.env, &h2, "app_d", true).unwrap();
    assert!(!h2.lvs.borrow().contains("vg0/vm_app_d_home"));
    assert!(h2.called("lvremove -q -y vg0/vm_app_d_home"));
}

#[test]
fn delete_refuses_a_running_or_linked_instance() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_run")).unwrap();
    let refuse = |want: &str| {
        let e = vm::delete(&f.env, &h, "app_run", false).unwrap_err();
        assert!(e.contains(want) && e.contains("katmate-launch --stop app_run"), "{e}");
        assert!(f.env.t1_path("app_run").exists() && f.env.delta_path("app_run").exists());
    };
    for st in ["active", "activating", "deactivating", "reloading"] {
        f.unit("katmate-app-routed@app_run.service", st);
        refuse(&format!("katmate-app-routed@app_run.service is '{st}'"));
    }
    f.unit("katmate-app-routed@app_run.service", "failed");
    f.unit("katmate-app-offline@app_run.service", "active");
    refuse("katmate-app-offline@app_run.service is 'active'");
    f.unit("katmate-app-offline@app_run.service", "inactive");
    // A stale owner (unit not running) still holds the link: --stop withdraws it.
    f.owner("netvm", "03", "app_run", 1007);
    refuse("holds slot 03 of netVM 'netvm' (LINK_ID 1007)");
    fs::remove_file(f.env.run_dir.join("link/netvm/03/owner")).unwrap();
    f.owner("netvm2", "00", "app_run", 1000);
    refuse("holds slot 00 of netVM 'netvm2'");
    fs::remove_file(f.env.run_dir.join("link/netvm2/00/owner")).unwrap();
    vm::delete(&f.env, &h, "app_run", false).unwrap();
}

#[test]
fn delete_refusals() {
    let f = Fixture::new();
    let h = Fake::new();
    let e = |name: &str, purge: bool, h: &Fake| vm::delete(&f.env, h, name, purge).unwrap_err();
    assert!(e("netvm", false, &h).contains("does not begin with app_"));
    assert!(e("gw_w2", true, &h).contains("does not begin with app_"));
    assert!(e("app_none", false, &h).contains("there is no instance 'app_none'"));
    assert!(e("app_none", true, &h).contains("no home LV vm_app_none_home"));

    fs::write(f.env.t1_path("app_sys"), "class = \"sys\"\ncid = 9\n").unwrap();
    assert!(e("app_sys", false, &h).contains("class = 'sys'"));
    fs::remove_file(f.env.t1_path("app_sys")).unwrap();

    fs::create_dir(f.env.d_path("app_web")).unwrap();
    assert!(e("app_web", false, &h).contains("app_web.d exists"));
    fs::remove_dir(f.env.d_path("app_web")).unwrap();

    // --purge: a terminal and the exact name, or nothing is removed.
    let mut h = Fake::new();
    h.tty = false;
    assert!(e("app_web", true, &h).contains("stdin is not one"));
    h.tty = true;
    h.answers = answers(&["app_we"]);
    assert!(e("app_web", true, &h).contains("'app_we' is not 'app_web'"));
    assert!(f.env.t1_path("app_web").exists());
    assert!(h.lvs.borrow().contains("vg0/vm_app_web_home") && !h.called("lvremove"));

    // A kept home with a leftover delta is not --purge's to clean.
    h.lvs.borrow_mut().insert("vg0/vm_app_left_home".into());
    fs::write(f.env.delta_path("app_left"), b"").unwrap();
    assert!(e("app_left", true, &h).contains("app_left.qcow2 exists without a T1 file"));
}

#[test]
fn purge_of_a_kept_home_without_t1() {
    let f = Fixture::new();
    let mut h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_app_kept_home".into());
    h.lvs.borrow_mut().insert("vg0/vm_gw_w2_home".into());
    h.answers = answers(&["app_kept"]);
    vm::delete(&f.env, &h, "app_kept", true).unwrap();
    assert!(!h.lvs.borrow().contains("vg0/vm_app_kept_home"));
    assert!(h.lvs.borrow().contains("vg0/vm_gw_w2_home"));
}

#[test]
fn purge_flushes_before_every_prompt_and_asks_again_on_empty() {
    let f = Fixture::new();
    let by = std::env::var("SUDO_USER").unwrap_or_else(|_| "<no SUDO_USER>".into());
    let prompt = "ask This removes vg0/vm_app_q_home, the /home of app_q, for good. Type the instance name to confirm: ";
    let tty = |h: &Fake| -> Vec<String> { h.calls().into_iter().filter(|c| c == "flush" || c.starts_with("ask ")).collect() };
    let fp = |n: usize| -> Vec<String> { (0..n).flat_map(|_| ["flush".to_string(), prompt.to_string()]).collect() };
    let journal = |h: &Fake| -> Vec<String> { h.calls().into_iter().filter(|c| c.starts_with("logger")).collect() };
    let purge = |script: &[&str], errno: Option<i32>| {
        let mut h = Fake::new();
        vm::create(&f.env, &h, &opts("app_q")).unwrap();
        h.calls.borrow_mut().clear();
        h.answers = answers(script);
        h.flush_errno = errno;
        let r = vm::delete(&f.env, &h, "app_q", true);
        (h, r)
    };
    let intact = |h: &Fake| {
        assert!(f.env.t1_path("app_q").exists() && f.env.delta_path("app_q").exists());
        assert!(h.lvs.borrow().contains("vg0/vm_app_q_home") && !h.called("lvremove"));
        vm::delete(&f.env, &Fake::new(), "app_q", false).unwrap();
    };

    let (h, r) = purge(&["app_q"], None);
    r.unwrap();
    assert_eq!(tty(&h), fp(1));
    assert!(h.called("lvremove -q -y vg0/vm_app_q_home") && !f.env.t1_path("app_q").exists());

    let (h, r) = purge(&["", "", "app_q"], None);
    r.unwrap();
    assert_eq!(tty(&h), fp(3));
    assert!(h.called("lvremove -q -y vg0/vm_app_q_home"));

    let (h, r) = purge(&["", "", ""], None);
    let e = r.unwrap_err();
    assert_eq!(e, "3 empty answers to the prompt; nothing was removed");
    assert_eq!(tty(&h), fp(3));
    assert_eq!(journal(&h), [format!("logger -t katmate-vm -- delete app_q (CID 32, invoked by {by}): refused: {e}")]);
    intact(&h);

    let (h, r) = purge(&["app_x"], None);
    assert_eq!(r.unwrap_err(), "'app_x' is not 'app_q'; nothing was removed");
    assert_eq!(tty(&h), fp(1));
    intact(&h);

    let (h, r) = purge(&["", "app_x"], None);
    assert!(r.unwrap_err().contains("'app_x' is not 'app_q'"));
    assert_eq!(tty(&h), fp(2));
    intact(&h);

    // A failing flush never blocks the delete; only ENOTTY is silent.
    for errno in [libc::ENOTTY, libc::EIO] {
        let (h, r) = purge(&["", "app_q"], Some(errno));
        r.unwrap();
        assert_eq!(tty(&h), fp(2), "errno {errno}");
        assert!(h.called("lvremove -q -y vg0/vm_app_q_home"));
    }
    assert_eq!(vm::flush_warning(Ok(())), None);
    assert_eq!(vm::flush_warning(Err(std::io::Error::from_raw_os_error(libc::ENOTTY))), None);
    let w = vm::flush_warning(Err(std::io::Error::from_raw_os_error(libc::EIO))).unwrap();
    assert!(w.starts_with("cannot discard typeahead before the prompt (") && w.ends_with("); asking anyway"), "{w}");
}

#[test]
fn exit_3_message_has_one_full_stop() {
    let tail = ". The instance stays as it is; recover with 'katmate-vm menu'";
    for why in ["katmate-generate-menu exited 1: no meta.", "katmate-generate-menu exited 1: no meta"] {
        let m = crate::menu_not_updated(why);
        assert_eq!(m, format!("[katmate-vm] MENU: the launcher's entries were not updated: katmate-generate-menu exited 1: no meta{tail}"));
        assert!(!m.contains(".."), "{m}");
    }
}

// --- provision ----------------------------------------------------------------

#[test]
fn provision_makes_home_and_delta_and_never_touches_t1() {
    let f = Fixture::new();
    let h = Fake::new();
    let t1p = f.env.t1_path("app_sandbox");
    let before = fs::read(&t1p).unwrap();
    vm::provision(&f.env, &h, "app_sandbox").unwrap();
    assert_eq!(fs::read(&t1p).unwrap(), before);
    assert_eq!(mode(&f.env.delta_path("app_sandbox")), 0o644);
    assert!(h.lvs.borrow().contains("vg0/vm_app_sandbox_home"));
    assert!(h.called("lvcreate -q -V 10G -T vg0/vm_pool -n vm_app_sandbox_home"));
    assert!(h.called("katmate-check-image --layer web") && h.called("katmate-activate-lvs --layer web"));
    let by = std::env::var("SUDO_USER").unwrap_or_else(|_| "<no SUDO_USER>".into());
    let j: Vec<String> = h.calls().into_iter().filter(|c| c.starts_with("logger")).collect();
    assert_eq!(j, [format!("logger -t katmate-vm -- provision app_sandbox (CID 25, invoked by {by}): provisioned")]);
}

#[test]
fn provision_refusals() {
    let f = Fixture::new();
    let e = |name: &str, h: &Fake| {
        let e = vm::provision(&f.env, h, name).unwrap_err();
        assert!(!h.called("lvcreate") && !h.called("qemu-img"), "{e}");
        e
    };
    assert!(e("netvm", &Fake::new()).contains("does not begin with app_"));
    assert!(e("app_none", &Fake::new()).contains("no T1 file"));
    assert!(e("app_web", &Fake::new()).contains("vg0/vm_app_web_home exists"));
    fs::write(f.env.t1_path("app_sys"), "class = \"sys\"\ncid = 9\n").unwrap();
    assert!(e("app_sys", &Fake::new()).contains("class = 'sys'"));
    fs::remove_file(f.env.t1_path("app_sys")).unwrap();
    fs::write(f.env.t1_path("app_eph"), "class = \"app\"\ncid = 40\nmanifest = \"web\"\npersistence = \"ephemeral\"\n").unwrap();
    assert!(e("app_eph", &Fake::new()).contains("persistence = 'ephemeral'"));
    fs::remove_file(f.env.t1_path("app_eph")).unwrap();
    fs::create_dir(f.env.d_path("app_sandbox")).unwrap();
    assert!(e("app_sandbox", &Fake::new()).contains("app_sandbox.d exists"));
    fs::remove_dir(f.env.d_path("app_sandbox")).unwrap();
    fs::write(f.env.delta_path("app_sandbox"), b"").unwrap();
    assert!(e("app_sandbox", &Fake::new()).contains("overwrites none"));
    fs::remove_file(f.env.delta_path("app_sandbox")).unwrap();
    fs::write(f.env.t1_path("app_dup"), "class = \"app\"\ncid = 25\n").unwrap();
    assert!(e("app_sandbox", &Fake::new()).contains("cid 25 is carried by more than one T1 file"));
    fs::remove_file(f.env.t1_path("app_dup")).unwrap();
    let mut h = Fake::new();
    h.check_image = Err("katmate-check-image --layer web exited 1: [katmate-check-image] FATAL: layer 'web' is stale".into());
    assert!(e("app_sandbox", &h).contains("layer 'web' refused"));
}

#[test]
fn provision_undoes_only_what_it_made() {
    for (step, want_lvremove) in [("mkfs.ext4", true), ("qemu-img", true), ("lvcreate", false)] {
        let f = Fixture::new();
        let mut h = Fake::new();
        h.fail_on = Some(step.into());
        let before = fs::read(f.env.t1_path("app_sandbox")).unwrap();
        let e = vm::provision(&f.env, &h, "app_sandbox").unwrap_err();
        assert!(e.contains("Undone, in reverse"), "{step}: {e}");
        assert_eq!(h.called("lvremove -q -y vg0/vm_app_sandbox_home"), want_lvremove, "{step}: {e}");
        assert!(!h.lvs.borrow().contains("vg0/vm_app_sandbox_home"), "{step}");
        assert!(!f.env.delta_path("app_sandbox").exists(), "{step}");
        assert_eq!(fs::read(f.env.t1_path("app_sandbox")).unwrap(), before, "{step}: T1 changed");
        let j: Vec<String> = h.calls().into_iter().filter(|c| c.starts_with("logger")).collect();
        assert!(j.len() == 1 && j[0].contains("provision app_sandbox (CID 25, ") && j[0].contains("): undone: "), "{j:?}");
    }
}

#[test]
fn a_failing_logger_fails_nothing() {
    let f = Fixture::new();
    let mut h = Fake::new();
    h.fail_on = Some("logger".into());
    vm::create(&f.env, &h, &opts("app_nolog")).unwrap();
    vm::provision(&f.env, &h, "app_sandbox").unwrap();
    vm::delete(&f.env, &h, "app_nolog", false).unwrap();
    assert_eq!(h.calls().iter().filter(|c| c.starts_with("logger")).count(), 3);
}

// --- status -------------------------------------------------------------------

#[test]
fn status_rows() {
    let f = Fixture::new();
    let h = Fake::new();
    h.lvs.borrow_mut().insert("vg0/vm_gw_w2_home".into());
    h.lvs.borrow_mut().insert("vg0/vm_app_kept_home".into());
    f.unit("katmate-app-routed@app_web.service", "active");
    f.owner("netvm", "00", "app_web", 1004);
    let (rows, errors) = vm::status(&f.env, &h, None).unwrap();
    assert!(errors.is_empty(), "{errors:?}");
    let names: Vec<&str> = rows.iter().map(|r| r.name.as_str()).collect();
    // Five class = app T1 files (netvm is class = sys), then the kept homes.
    assert_eq!(names, ["app_personal", "app_sandbox", "app_vault", "app_web", "app_work", "app_kept", "gw_w2"]);
    let web = &rows[3];
    assert_eq!(
        (web.cid.as_str(), web.layer.as_str(), web.netvm.as_str(), web.unit.as_str(), web.slot.as_str(), web.link_id.as_str(), web.home.as_str()),
        ("21", "web", "netvm", "active", "00", "1004", "vg0/vm_app_web_home")
    );
    let vault = &rows[2];
    assert_eq!((vault.netvm.as_str(), vault.unit.as_str(), vault.slot.as_str(), vault.home.as_str()), ("offline", "inactive", "-", "absent"));
    assert_eq!(rows[5].home, "vg0/vm_app_kept_home (kept home)");

    let (one, _) = vm::status(&f.env, &h, Some("app_web")).unwrap();
    assert_eq!(one, vec![web.clone()]);
    let (one, _) = vm::status(&f.env, &h, Some("app_kept")).unwrap();
    assert_eq!(one.len(), 1);
    assert!(vm::status(&f.env, &h, Some("app_none")).unwrap_err().contains("no instance 'app_none'"));
    assert!(vm::status(&f.env, &h, Some("netvm")).unwrap_err().contains("not an AppVM"));
    assert!(vm::header().starts_with("NAME"));

    // An unreadable T1 file is an error line; the others still show.
    fs::write(f.env.t1_path("app_bad"), "class = \"app\"\nclass = \"app\"\n").unwrap();
    let (rows, errors) = vm::status(&f.env, &h, None).unwrap();
    assert_eq!(rows.len(), 7);
    assert!(errors.len() == 1 && errors[0].contains("duplicate key 'class'"), "{errors:?}");
}

// --- menu (cu5) ---------------------------------------------------------------

fn apps(f: &Fixture) -> PathBuf {
    f.env.desktop.join("applications")
}

/// Each file of `d` as (name, mode, bytes), sorted.
fn snapshot(d: &Path) -> Vec<(String, u32, Vec<u8>)> {
    let mut v: Vec<_> = fs::read_dir(d)
        .unwrap()
        .map(|e| {
            let p = e.unwrap().path();
            (p.file_name().unwrap().to_string_lossy().into_owned(), mode(&p), fs::read(&p).unwrap())
        })
        .collect();
    v.sort();
    v
}

fn listing(d: &Path) -> Vec<String> {
    snapshot(d).into_iter().map(|(n, _, _)| n).collect()
}

fn journal_lines(h: &Fake) -> Vec<String> {
    h.calls().into_iter().filter(|c| c.starts_with("logger")).collect()
}

#[test]
fn menu_on_a_missing_directory_is_the_generator_set() {
    let f = Fixture::new();
    let h = Fake::new();
    assert!(!f.env.desktop.exists());
    vm::menu(&f.env, &h).unwrap();
    let d = apps(&f);
    assert_eq!((mode(&f.env.desktop), mode(&d)), (0o755, 0o755));
    let got = snapshot(&d);
    assert_eq!(got.len(), 16);
    assert!(got.iter().all(|(_, m, _)| *m == 0o644));
    assert!(!f.env.desktop.join("applications.new").exists());
    // The set the generator writes by hand, byte for byte.
    let by_hand = f.root.join("by-hand");
    let gen = f.env.lib.join("katmate-generate-menu");
    RealHost.run(&[gen.to_str().unwrap(), f.env.etc_vm.to_str().unwrap(), f.env.t2.to_str().unwrap(), by_hand.to_str().unwrap()]).unwrap();
    assert_eq!(got, snapshot(&by_hand));
    let j = journal_lines(&h);
    assert!(j.len() == 1 && j[0].contains("-- menu (invoked by ") && j[0].contains("): updated: [katmate-generate-menu] 15 entries for 5 instances"), "{j:?}");
}

#[test]
fn menu_replaces_an_existing_directory_whole() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::menu(&f.env, &h).unwrap();
    let first = snapshot(&apps(&f));
    let ino = fs::metadata(apps(&f)).unwrap().ino();
    let old = f.env.desktop.join("applications.old");
    assert!(!old.exists(), "no swap yet, so no old set");
    // A reader that opened the live directory before the swap.
    let opened = fs::read_dir(apps(&f)).unwrap();
    fs::remove_file(f.env.t1_path("app_work")).unwrap();
    vm::menu(&f.env, &h).unwrap();
    let names = listing(&apps(&f));
    assert_eq!(names.len(), 13);
    assert!(!names.iter().any(|n| n.contains("app_work")), "{names:?}");
    assert_ne!(fs::metadata(apps(&f)).unwrap().ino(), ino, "not a new directory");
    assert!(!f.env.desktop.join("applications.new").exists());
    // H2 ruling 1: the old set stays whole as applications.old until the next update.
    assert_eq!(fs::metadata(&old).unwrap().ino(), ino);
    assert_eq!(snapshot(&old), first);
    assert_eq!(opened.count(), 16, "the reader's directory was emptied under it");

    fs::remove_file(f.env.t1_path("app_vault")).unwrap();
    vm::menu(&f.env, &h).unwrap();
    assert_eq!(listing(&apps(&f)).len(), 10);
    assert_eq!(listing(&old).len(), 13, "the previous .old was not replaced");
    let base: Vec<String> = fs::read_dir(&f.env.desktop).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
    assert_eq!(base.len(), 2, "{base:?}");
}

#[test]
fn menu_removes_a_stale_new_directory() {
    for live_first in [false, true] {
        let f = Fixture::new();
        let h = Fake::new();
        if live_first {
            vm::menu(&f.env, &h).unwrap();
        }
        let stale = f.env.desktop.join("applications.new");
        fs::create_dir_all(stale.join("sub")).unwrap();
        fs::write(stale.join("km-00-app_old-foot.desktop"), b"stale").unwrap();
        vm::menu(&f.env, &h).unwrap();
        assert!(!stale.exists(), "live_first={live_first}");
        let names = listing(&apps(&f));
        assert!(names.len() == 16 && !names.iter().any(|n| n.contains("app_old")), "live_first={live_first}: {names:?}");
    }
}

/// A generation that fails before or after writing its first file, a live
/// path that is not a directory, a held lock: the live set stays as it was,
/// and no applications.new is left.
#[test]
fn menu_failures_leave_the_live_set() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::menu(&f.env, &h).unwrap();
    let before = snapshot(&apps(&f));
    let new = f.env.desktop.join("applications.new");

    fs::rename(f.env.t2.join("app-office.meta"), f.root.join("office.meta")).unwrap();
    let e = vm::menu(&f.env, &h).unwrap_err();
    assert!(e.contains("T2 image metadata not found"), "{e}");
    assert!(snapshot(&apps(&f)) == before && !new.exists());
    fs::rename(f.root.join("office.meta"), f.env.t2.join("app-office.meta")).unwrap();

    // Not app_*: the generator stops inside its write loop, a partial set.
    fs::write(f.env.t1_path("zz"), "class = \"app\"\ncid = 90\nmanifest = \"web\"\n").unwrap();
    let e = vm::menu(&f.env, &h).unwrap_err();
    assert!(e.contains("instance 'zz' does not begin with app_"), "{e}");
    assert!(snapshot(&apps(&f)) == before && !new.exists());
    fs::remove_file(f.env.t1_path("zz")).unwrap();

    let held = vm::launch_lock(&f.env).unwrap();
    assert!(vm::menu(&f.env, &h).unwrap_err().contains("has held"));
    drop(held);
    assert_eq!(snapshot(&apps(&f)), before);

    fs::remove_dir_all(apps(&f)).unwrap();
    fs::write(apps(&f), b"not a directory").unwrap();
    let e = vm::menu(&f.env, &h).unwrap_err();
    assert!(e.contains("is not a directory; not replaced"), "{e}");
    assert!(fs::read(apps(&f)).unwrap() == b"not a directory" && !new.exists());
    let j = journal_lines(&h);
    assert!(j.len() == 5 && j[1..].iter().all(|l| l.contains("): not updated: ")), "{j:?}");
}

#[test]
fn create_and_delete_rewrite_the_menu() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::menu(&f.env, &h).unwrap();
    assert_eq!(vm::create(&f.env, &h, &opts("app_m")).unwrap(), None);
    let names = listing(&apps(&f));
    for want in ["km-00-app_m-firefox-esr.desktop", "km-00-app_m-foot.desktop", "km-00-app_m-pcmanfm.desktop", "km-99-appvms.desktop"] {
        assert!(names.contains(&want.to_string()), "{want}: {names:?}");
    }
    assert_eq!(names.len(), 19);
    assert_eq!(vm::delete(&f.env, &h, "app_m", false).unwrap(), None);
    assert_eq!(listing(&apps(&f)).len(), 16);
    assert!(!listing(&apps(&f)).iter().any(|n| n.contains("app_m-")));

    // --reuse-home, then --purge.
    let mut o = opts("app_m");
    o.reuse_home = true;
    assert_eq!(vm::create(&f.env, &h, &o).unwrap(), None);
    assert_eq!(listing(&apps(&f)).len(), 19);
    let mut h2 = Fake::new();
    h2.lvs = h.lvs;
    h2.answers = answers(&["app_m"]);
    assert_eq!(vm::delete(&f.env, &h2, "app_m", true).unwrap(), None);
    assert_eq!(listing(&apps(&f)).len(), 16);
}

#[test]
fn refusals_and_provision_do_not_touch_the_menu() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::create(&f.env, &h, &opts("app_web")).unwrap_err();
    vm::delete(&f.env, &h, "app_none", false).unwrap_err();
    vm::delete(&f.env, &h, "app_none", true).unwrap_err();
    let mut u = Fake::new();
    u.fail_on = Some("mkfs.ext4".into());
    vm::create(&f.env, &u, &opts("app_u")).unwrap_err();
    vm::provision(&f.env, &h, "app_sandbox").unwrap();
    assert!(!h.called("katmate-generate-menu") && !u.called("katmate-generate-menu"));
    assert!(!f.env.desktop.exists());
}

#[test]
fn a_failed_menu_update_keeps_the_instance_and_the_live_set() {
    let f = Fixture::new();
    let h = Fake::new();
    vm::menu(&f.env, &h).unwrap();
    let before = snapshot(&apps(&f));
    // app_work's layer meta gone: every generation fails, create's own layer is fine.
    fs::rename(f.env.t2.join("app-office.meta"), f.root.join("office.meta")).unwrap();

    let why = vm::create(&f.env, &h, &opts("app_m")).unwrap().expect("a menu failure");
    assert!(why.contains("T2 image metadata not found"), "{why}");
    assert!(f.env.t1_path("app_m").exists() && f.env.delta_path("app_m").exists() && h.lvs.borrow().contains("vg0/vm_app_m_home"));
    assert_eq!(snapshot(&apps(&f)), before);
    assert!(!f.env.desktop.join("applications.new").exists());
    let j = journal_lines(&h);
    assert!(j.last().unwrap().contains("create app_m (CID 32, ") && j.last().unwrap().contains("): created; menu not updated: katmate-generate-menu "), "{j:?}");

    let why = vm::delete(&f.env, &h, "app_m", false).unwrap().expect("a menu failure");
    assert!(why.contains("T2 image metadata not found"), "{why}");
    assert!(!f.env.t1_path("app_m").exists() && !f.env.delta_path("app_m").exists());
    assert_eq!(snapshot(&apps(&f)), before);
    let j = journal_lines(&h);
    assert!(j.last().unwrap().contains("): deleted; menu not updated: "), "{j:?}");

    fs::rename(f.root.join("office.meta"), f.env.t2.join("app-office.meta")).unwrap();
    vm::menu(&f.env, &h).unwrap();
    assert_eq!(snapshot(&apps(&f)), before);
}

#[test]
fn a_delete_failing_after_the_first_removal_rewrites_the_menu() {
    let f = Fixture::new();
    let mut h = Fake::new();
    vm::create(&f.env, &h, &opts("app_p")).unwrap();
    assert_eq!(listing(&apps(&f)).len(), 19);
    h.fail_on = Some("lvremove".into());
    h.answers = answers(&["app_p"]);
    let e = vm::delete(&f.env, &h, "app_p", true).unwrap_err();
    assert!(e.contains("injected failure"), "{e}");
    assert!(!f.env.t1_path("app_p").exists());
    assert_eq!(listing(&apps(&f)).len(), 16);
    let j = journal_lines(&h);
    let last = j.last().unwrap();
    assert!(last.contains("): failed after the first removal: ") && !last.contains("menu not updated"), "{j:?}");
}

/// While `menu` runs repeatedly, a reader looking the live path up never
/// finds it missing. Only the lookup is checked: a reader that opened the old
/// directory before a swap can see it emptied (cu5 report, § 5).
#[test]
fn the_live_path_is_never_missing_during_a_swap() {
    use std::sync::atomic::AtomicBool;
    use std::sync::Arc;
    let f = Fixture::new();
    let h = Fake::new();
    vm::menu(&f.env, &h).unwrap();
    let (stop, live) = (Arc::new(AtomicBool::new(false)), apps(&f));
    let reader = {
        let stop = stop.clone();
        std::thread::spawn(move || {
            let (mut looks, mut missing) = (0u64, 0u64);
            while !stop.load(Ordering::Relaxed) {
                looks += 1;
                if !fs::symlink_metadata(&live).map(|m| m.is_dir()).unwrap_or(false) {
                    missing += 1;
                }
            }
            (looks, missing)
        })
    };
    for _ in 0..30 {
        vm::menu(&f.env, &h).unwrap();
    }
    stop.store(true, Ordering::Relaxed);
    let (looks, missing) = reader.join().unwrap();
    assert!(looks > 1000 && missing == 0, "looks {looks}, missing {missing}");
}
