use super::*;
use std::collections::BTreeSet;
use std::sync::{Arc, Barrier};

/// A pool tree under the temp directory, removed on drop.
struct Fixture {
    root: PathBuf,
}

impl Fixture {
    fn new() -> Fixture {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "katmate-alloc-test.{}.{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        for s in SLOTS {
            fs::create_dir_all(root.join("link/netvm").join(s)).unwrap();
        }
        Fixture { root }
    }

    fn pool(&self) -> Pool {
        Pool::new(&self.root, "netvm").unwrap()
    }

    fn owner_path(&self, slot: &str) -> PathBuf {
        self.root.join("link/netvm").join(slot).join("owner")
    }

    fn put_owner(&self, slot: &str, instance: &str, link_id: u32) {
        let o = Owner { instance: instance.into(), link_id };
        write_file(&self.owner_path(slot), &o.text(), true).unwrap();
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn live(_: &str) -> bool {
    true
}

fn claimed(c: Claim) -> (&'static str, Owner) {
    match c {
        Claim::Claimed { slot, owner } => (slot, owner),
        other => panic!("expected Claimed, got {other:?}"),
    }
}

#[test]
fn lowest_free_skips_reserved() {
    let f = Fixture::new();
    let pool = f.pool();
    let l = pool.lock().unwrap();
    let got: Vec<&str> = ["a", "b", "c", "d", "e", "f"].iter().map(|i| claimed(l.claim(i, &live).unwrap()).0).collect();
    assert_eq!(got, ["00", "01", "02", "03", "04", "07"]);
}

#[test]
fn reserved_slots_never_handed_out() {
    let f = Fixture::new();
    let pool = f.pool();
    let l = pool.lock().unwrap();
    for i in 0..14 {
        claimed(l.claim(&format!("i{i}"), &live).unwrap());
    }
    let e = l.claim("one_more", &live).unwrap_err();
    assert!(e.0.contains("no free slot"), "{e}");
    assert!(l.read("05").unwrap().is_none());
    assert!(l.read("06").unwrap().is_none());
    // A stale owner never makes a reserved slot reclaimable either.
    f.put_owner("06", "layer_builder", 206);
    let e = l.reclaim("06", &Owner { instance: "layer_builder".into(), link_id: 206 }, &|_| false).unwrap_err();
    assert!(e.0.contains("reserved"), "{e}");
    assert!(l.read("06").unwrap().is_some());
}

#[test]
fn own_owner_is_kept() {
    let f = Fixture::new();
    let pool = f.pool();
    let l = pool.lock().unwrap();
    let (slot, owner) = claimed(l.claim("app_web", &live).unwrap());
    assert_eq!(l.claim("app_web", &live).unwrap(), Claim::Kept { slot, owner });
}

#[test]
fn link_ids_are_a_monotonic_counter_from_1000() {
    let f = Fixture::new();
    let pool = f.pool();
    let l = pool.lock().unwrap();
    let a = claimed(l.claim("a", &live).unwrap()).1.link_id;
    let b = claimed(l.claim("b", &live).unwrap()).1.link_id;
    assert_eq!((a, b), (1000, 1001));
    assert_eq!(l.release("a", 1000).unwrap(), Released::Removed { slot: "00" });
    let (slot, o) = claimed(l.claim("a", &live).unwrap());
    assert_eq!((slot, o.link_id), ("00", 1002), "a released slot is reused, its LINK_ID is not");
}

#[test]
fn link_id_skips_a_value_in_use() {
    let f = Fixture::new();
    f.put_owner("00", "hand", 1000);
    let pool = f.pool();
    let l = pool.lock().unwrap();
    assert_eq!(claimed(l.claim("a", &live).unwrap()), ("01", Owner { instance: "a".into(), link_id: 1001 }));
}

#[test]
fn owner_file_form() {
    let f = Fixture::new();
    let pool = f.pool();
    let l = pool.lock().unwrap();
    claimed(l.claim("app_web", &live).unwrap());
    let p = f.owner_path("00");
    assert_eq!(fs::read_to_string(&p).unwrap(), "KATMATE_OWNER_VERSION=1\nINSTANCE=app_web\nLINK_ID=1000\n");
    assert_eq!(fs::metadata(&p).unwrap().mode() & 0o7777, 0o644);
    let stray: Vec<_> = fs::read_dir(p.parent().unwrap()).unwrap().map(|e| e.unwrap().file_name()).collect();
    assert_eq!(stray, ["owner"], "no temporary file is left behind");
}

#[test]
fn stale_owner_is_reported_then_reclaimed() {
    let f = Fixture::new();
    f.put_owner("00", "dead", 1000);
    f.put_owner("01", "alive", 1001);
    let pool = f.pool();
    let l = pool.lock().unwrap();
    let is_live = |i: &str| i == "alive";
    let stale = Owner { instance: "dead".into(), link_id: 1000 };
    assert_eq!(l.claim("new", &is_live).unwrap(), Claim::Stale { slot: "00", owner: stale.clone() });
    assert!(l.read("00").unwrap().is_some(), "claim writes nothing for a stale slot");
    l.reclaim("00", &stale, &is_live).unwrap();
    assert_eq!(claimed(l.claim("new", &is_live).unwrap()), ("00", Owner { instance: "new".into(), link_id: 1002 }));
}

#[test]
fn reclaim_refuses_a_changed_or_live_owner() {
    let f = Fixture::new();
    f.put_owner("00", "dead", 1000);
    let pool = f.pool();
    let l = pool.lock().unwrap();
    let wrong = Owner { instance: "dead".into(), link_id: 999 };
    assert!(l.reclaim("00", &wrong, &|_| false).unwrap_err().0.contains("not reclaimed"));
    let stale = Owner { instance: "dead".into(), link_id: 1000 };
    assert!(l.reclaim("00", &stale, &|_| true).unwrap_err().0.contains("running again"));
    assert_eq!(l.read("00").unwrap(), Some(stale));
}

#[test]
fn foreign_owner_never_overwritten_or_released() {
    let f = Fixture::new();
    f.put_owner("00", "other", 1000);
    let pool = f.pool();
    let l = pool.lock().unwrap();
    let before = fs::read_to_string(f.owner_path("00")).unwrap();
    assert_eq!(claimed(l.claim("me", &live).unwrap()).0, "01");
    assert_eq!(l.release("nobody", 1000).unwrap(), Released::Absent);
    assert!(l.release("other", 1001).unwrap_err().0.contains("not removed"));
    assert_eq!(fs::read_to_string(f.owner_path("00")).unwrap(), before);
    // The no-replace rename refuses an owner that appears between the scan
    // and the write (one written by hand, outside the lock).
    assert!(write_file(&f.owner_path("00"), "x", false).is_err());
    assert_eq!(fs::read_to_string(f.owner_path("00")).unwrap(), before);
}

#[test]
fn malformed_pool_stops_the_claim() {
    let cases: [(&str, &str); 5] = [
        ("KATMATE_OWNER_VERSION=2\nINSTANCE=a\nLINK_ID=1\n", "version 1"),
        ("KATMATE_OWNER_VERSION=1\nINSTANCE=A\nLINK_ID=1\n", "INSTANCE"),
        ("KATMATE_OWNER_VERSION=1\nINSTANCE=a\nLINK_ID=01\n", "LINK_ID"),
        ("KATMATE_OWNER_VERSION=1\nINSTANCE=a\nINSTANCE=b\nLINK_ID=1\n", "duplicate"),
        ("KATMATE_OWNER_VERSION=1\nINSTANCE=a\nLINK_ID=1\nSLOT=00\n", "unknown key"),
    ];
    for (text, want) in cases {
        let f = Fixture::new();
        write_file(&f.owner_path("09"), text, true).unwrap();
        let pool = f.pool();
        let e = pool.lock().unwrap().claim("me", &live).unwrap_err();
        assert!(e.0.contains(want), "{text:?}: {e}");
    }
    let f = Fixture::new();
    std::os::unix::fs::symlink("/etc/hostname", f.owner_path("03")).unwrap();
    assert!(f.pool().lock().unwrap().claim("me", &live).unwrap_err().0.contains("symlink"));
    let f = Fixture::new();
    f.put_owner("03", "a", 1);
    fs::set_permissions(f.owner_path("03"), fs::Permissions::from_mode(0o664)).unwrap();
    assert!(f.pool().lock().unwrap().claim("me", &live).unwrap_err().0.contains("writable"));
}

#[test]
fn absent_pool_is_named() {
    let f = Fixture::new();
    let e = Pool::new(&f.root, "netvm2").unwrap().lock().err().unwrap();
    assert!(e.0.contains("has not started on this boot"), "{e}");
    assert!(Pool::new(&f.root, "../x").is_err());
}

#[test]
fn instance_named_twice_is_refused() {
    let f = Fixture::new();
    f.put_owner("00", "a", 1);
    f.put_owner("01", "a", 2);
    let e = f.pool().lock().unwrap().claim("a", &live).unwrap_err();
    assert!(e.0.contains("more than one slot: 00 01"), "{e}");
}

/// Many parallel claims on one pool, each through its own open of the lock
/// file (one open file description each, as separate processes have), never
/// yield one slot twice: 32 claimants for 14 usable slots, twenty rounds.
#[test]
fn concurrent_claims_never_share_a_slot() {
    for round in 0..20 {
        let f = Fixture::new();
        let n = 32;
        let barrier = Arc::new(Barrier::new(n));
        let root = f.root.clone();
        let handles: Vec<_> = (0..n)
            .map(|i| {
                let (barrier, root) = (barrier.clone(), root.clone());
                std::thread::spawn(move || {
                    let pool = Pool::new(&root, "netvm").unwrap();
                    barrier.wait();
                    let l = pool.lock().unwrap();
                    l.claim(&format!("c{i}"), &live)
                })
            })
            .collect();
        let results: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        let slots: Vec<&str> = results.iter().filter_map(|r| r.as_ref().ok()).map(|c| claimed(c.clone()).0).collect();
        let ids: BTreeSet<u32> = results.iter().filter_map(|r| r.as_ref().ok()).map(|c| claimed(c.clone()).1.link_id).collect();
        let distinct: BTreeSet<&str> = slots.iter().copied().collect();
        assert_eq!(slots.len(), 14, "round {round}: 14 claims succeed");
        assert_eq!(distinct.len(), 14, "round {round}: no slot twice");
        assert_eq!(ids, (1000..1014).collect(), "round {round}: no LINK_ID twice");
        assert!(!distinct.contains("05") && !distinct.contains("06"), "round {round}");
        let refused = results.iter().filter(|r| matches!(r, Err(e) if e.0.contains("no free slot"))).count();
        assert_eq!(refused, n - 14, "round {round}");
        // What the pool holds on disk agrees with what the claimants were told.
        let l = f.pool();
        let l = l.lock().unwrap();
        let on_disk: BTreeSet<&str> = l.owners().unwrap().into_iter().filter(|(_, o)| o.is_some()).map(|(s, _)| s).collect();
        assert_eq!(on_disk, distinct, "round {round}");
    }
}

#[test]
fn unit_live_states() {
    let f = Fixture::new();
    let stub = f.root.join("systemctl");
    for (answer, want) in [("active", true), ("activating", true), ("deactivating", true), ("reloading", true), ("inactive", false), ("failed", false), ("", false)] {
        let tmp = f.root.join("systemctl.new");
        fs::write(&tmp, format!("#!/bin/sh\necho '{answer}'\nexit 3\n")).unwrap();
        fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755)).unwrap();
        fs::rename(&tmp, &stub).unwrap();
        assert_eq!(unit_live(&stub, "x.service").unwrap(), want, "answer '{answer}'");
    }
    assert!(unit_live(&f.root.join("absent"), "x.service").unwrap_err().0.contains("cannot run"));
}

mod cids {
    use crate::cid::*;

    fn pairs(text: &str) -> Vec<Entry> {
        parse_pairs(text).unwrap()
    }

    const SHIPPED: &str = "netvm 3\napp_web 21\napp_personal 22\napp_work 23\napp_vault 24\napp_sandbox 25\n";

    #[test]
    fn shipped_set_passes() {
        assert_eq!(check(&pairs(SHIPPED)), Report::default());
    }

    #[test]
    fn duplicate_cid_refused() {
        let r = check(&pairs(&format!("{SHIPPED}app_dup 22\n")));
        assert_eq!(r.errors, ["cid 22 is carried by more than one T1 file: app_personal app_dup"]);
    }

    #[test]
    fn reserved_row_refused() {
        let r = check(&pairs("app_x 30\n"));
        assert_eq!(r.errors.len(), 1);
        assert!(r.errors[0].contains("reserved for gw_w2"), "{:?}", r.errors);
        assert!(!check(&pairs("app_x 1\n")).errors.is_empty());
    }

    #[test]
    fn disposable_range_is_a_warning() {
        let r = check(&pairs("app_x 100\napp_y auto\napp_z auto\n"));
        assert!(r.errors.is_empty(), "{:?}", r.errors);
        assert_eq!(r.warnings.len(), 1);
        assert!(r.warnings[0].contains("app_x: cid 100"), "{:?}", r.warnings);
    }

    #[test]
    fn malformed_input_refused() {
        assert!(parse_pairs("app_x\n").is_err());
        assert!(parse_pairs("app_x 21 extra\n").is_err());
        assert!(!check(&pairs("app_x 021\n")).errors.is_empty());
        assert!(!check(&pairs("App 21\n")).errors.is_empty());
        assert!(!check(&pairs("a 21\na 22\n")).errors.is_empty());
    }

    #[test]
    fn next_is_lowest_free_user_cid() {
        assert_eq!(next(&pairs(SHIPPED)).unwrap(), 32);
        assert_eq!(next(&pairs(&format!("{SHIPPED}u1 32\nu2 34\n"))).unwrap(), 33);
        let full: String = (32..=99).map(|c| format!("u{c} {c}\n")).collect();
        assert!(next(&pairs(&full)).unwrap_err().0.contains("no free CID"));
        assert!(next(&pairs(&format!("{SHIPPED}app_dup 21\n"))).unwrap_err().0.contains("not valid"));
    }
}
