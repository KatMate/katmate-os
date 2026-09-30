//! netcfg.rs — the NETCFG opcode: total payload validation, the boot-scoped
//! record set, and the two convergent flows (ADD / REMOVE). ADR-025.
//!
//! DIVISION OF LABOUR
//!
//!   netcfg.rs   decides WHAT the desired state is (parse + validate + record)
//!   netlink.rs  makes the kernel match it (mechanism only, no state)
//!   main.rs     owns the wire (reply after the act — see below)
//!
//! WHAT VALIDATION IS AND IS NOT (ADR-025, privilege honesty)
//!
//! This is NOT a trust boundary against the host: by ADR-003 the host is the
//! more-trusted side, and it already holds the whole graph. What total
//! validation buys is (a) decode totality — every byte sequence either maps to
//! exactly one desired state or is rejected, never partially applied — and (b)
//! blast-radius limiting for launch-daemon BUGS. The rules below are therefore
//! written to be exhaustive rather than adversarial.
//!
//! Two of them are structural rather than cosmetic:
//!
//!   * `match_mac` must be unicast AND locally-administered. Physical NICs
//!     carry globally-administered OUI addresses, so this makes the RTL8125
//!     uplink unreachable BY CONSTRUCTION — without this binary having to know
//!     which MAC the uplink has. The image stays generic; one bit test buys the
//!     guarantee.
//!   * `local_addr` is pinned to the single legal v1 value. A proxy netVM will
//!     loosen this per-binary CONSTANT; it will never loosen the wire.
//!
//! WIRE (fixed binary layout, no TLV, no serialisation library)
//!
//!   off  size  field
//!     0     1  op            0x01 ADD | 0x02 REMOVE
//!     1     4  link_id       u32 LE, != 0, host-allocated, opaque here
//!    -- REMOVE ends here: total length == 5 --
//!     5     6  match_mac     unicast + locally-administered
//!    11     4  local_addr    == INTERNAL_LOCAL
//!    15     4  peer_addr     in INTERNAL_SEGMENT/24, not network/broadcast/local
//!    19     1  peer_prefix   == 32
//!    20     1  route_count   1..=4
//!    21   9*n  routes        dest[4] + prefix[1] + metric[4]
//!
//!   ADD total length == 21 + 9n (30..=57), exact match or ERR.
//!
//! BYTE ORDER. The frame convention (`katmate-protocol::frame`) is
//! little-endian, and it governs genuine INTEGERS: `link_id` and `metric`.
//! Addresses and the MAC are byte arrays in network order, the same class of
//! field as `match_mac` itself — carried through untouched into the netlink
//! attribute. There is therefore no address byte-swap anywhere in the
//! privileged path, and none to get wrong.
//!
//! STATE (ADR-025: "state is the filesystem; the process is stateless")
//!
//! One record per link, named `link-<id:08x>` under `RUNTIME_DIR`, containing
//! the validated ADD payload VERBATIM. Consequences that fall out of that
//! choice rather than being coded for: identical-ADD is a byte comparison;
//! REMOVE reconstructs what to withdraw by re-parsing the record (the 5-byte
//! REMOVE payload does not carry it); an agent restart loses nothing. The
//! directory is `/run` — volatile by design, because the launch daemon must
//! re-issue every link after a netVM restart anyway (a hotplugged appVM netdev
//! does not survive one either).
//!
//! CONVERGENCE, NOT ROLLBACK. Every operation is a full idempotent pass. ERR
//! means "re-issue or escalate", never "nothing was touched" — there is no
//! rollback code, because it would be a second failure surface buying only what
//! idempotent retry already provides. The one ordering rule that is NOT
//! symmetric, and the reason it is not:
//!
//!   ADD:    write record -> drive mechanism   (a crash leaves a record the
//!                                              retry completes)
//!   REMOVE: drive mechanism -> delete record  (a crash leaves a record the
//!                                              retry re-deletes)
//!
//! The inverse of either can orphan live kernel state with no record pointing
//! at it — the one unrecoverable shape, hence forbidden.

use std::fs;
use std::io::Write;
use std::os::unix::fs::DirBuilderExt;
use std::path::PathBuf;

use katmate_protocol::error::{AgentError, Result};
use katmate_protocol::frame::RawRequest;

use crate::netlink;

// --- v1 constants ---------------------------------------------------
// These are the per-binary constants ADR-025 says a future proxy agent
// loosens. The WIRE they are validated against is not per-binary.

const OP_ADD: u8 = 0x01;
const OP_REMOVE: u8 = 0x02;

/// The netVM's own address on every internal p2p link (ADR-022 segment).
const INTERNAL_LOCAL: [u8; 4] = [10, 100, 1, 1];
/// The first three octets of the internal segment, 10.100.1.0/24.
const INTERNAL_SEGMENT: [u8; 3] = [10, 100, 1];
/// The only legal peer prefix: a link is a pair of /32s, never a subnet.
const PEER_PREFIX: u8 = 32;

/// Parser hygiene, not a trust boundary: a small constant instead of the
/// full u8 range, for a capability v1 has no use for.
const MAX_ROUTES: usize = 4;
/// Agent-side cap on concurrently installed links. Hygiene likewise.
const MAX_LINKS: usize = 128;

const REMOVE_LEN: usize = 5;
const ADD_FIXED_LEN: usize = 21;
const ROUTE_LEN: usize = 9;

/// systemd `RuntimeDirectory=netvm-agent`. Created if missing so the binary is
/// also runnable outside the unit during development.
const RUNTIME_DIR: &str = "/run/netvm-agent";

// --- parsed forms ---------------------------------------------------

#[derive(Debug, PartialEq, Eq)]
struct Route {
    dest: [u8; 4],
    prefix: u8,
    metric: u32,
}

#[derive(Debug, PartialEq, Eq)]
struct Link {
    link_id: u32,
    mac: [u8; 6],
    local: [u8; 4],
    peer: [u8; 4],
    peer_prefix: u8,
    routes: Vec<Route>,
}

#[derive(Debug, PartialEq, Eq)]
enum Cmd {
    Add(Link),
    Remove(u32),
}

// --- parsing --------------------------------------------------------

fn u32_le(b: &[u8]) -> u32 {
    u32::from_le_bytes([b[0], b[1], b[2], b[3]])
}

/// Total decode: either a fully valid `Cmd`, or a rejection. Nothing partial
/// escapes this function, so no caller can act on a half-understood payload.
fn parse(p: &[u8]) -> Result<Cmd> {
    let op = *p
        .first()
        .ok_or(AgentError::Rejected("netcfg: empty payload"))?;

    match op {
        OP_REMOVE => {
            if p.len() != REMOVE_LEN {
                return Err(AgentError::Rejected("netcfg: REMOVE length must be 5"));
            }
            let link_id = u32_le(&p[1..5]);
            if link_id == 0 {
                return Err(AgentError::Rejected("netcfg: link_id 0 is reserved"));
            }
            Ok(Cmd::Remove(link_id))
        }

        OP_ADD => {
            // route_count sits at offset 20, so the fixed part must be present
            // before the exact total length can even be computed.
            if p.len() < ADD_FIXED_LEN {
                return Err(AgentError::Rejected("netcfg: ADD shorter than fixed header"));
            }

            let route_count = p[20] as usize;
            if route_count == 0 || route_count > MAX_ROUTES {
                return Err(AgentError::Rejected("netcfg: route_count out of range"));
            }
            if p.len() != ADD_FIXED_LEN + route_count * ROUTE_LEN {
                return Err(AgentError::Rejected("netcfg: ADD length does not match route_count"));
            }

            let link_id = u32_le(&p[1..5]);
            if link_id == 0 {
                return Err(AgentError::Rejected("netcfg: link_id 0 is reserved"));
            }

            let mut mac = [0u8; 6];
            mac.copy_from_slice(&p[5..11]);
            // Bit 0 of octet 0 = multicast; bit 1 = locally administered.
            // Both tests together are what fences the payload away from any
            // physical NIC, the uplink included.
            if mac[0] & 0x01 != 0 {
                return Err(AgentError::Rejected("netcfg: match_mac is not unicast"));
            }
            if mac[0] & 0x02 == 0 {
                return Err(AgentError::Rejected(
                    "netcfg: match_mac is not locally administered",
                ));
            }

            let mut local = [0u8; 4];
            local.copy_from_slice(&p[11..15]);
            if local != INTERNAL_LOCAL {
                return Err(AgentError::Rejected("netcfg: local_addr is not the v1 constant"));
            }

            let mut peer = [0u8; 4];
            peer.copy_from_slice(&p[15..19]);
            if peer[0..3] != INTERNAL_SEGMENT {
                return Err(AgentError::Rejected("netcfg: peer_addr outside the internal segment"));
            }
            if peer[3] == 0 || peer[3] == 255 {
                return Err(AgentError::Rejected("netcfg: peer_addr is network or broadcast"));
            }
            if peer == INTERNAL_LOCAL {
                return Err(AgentError::Rejected("netcfg: peer_addr equals local_addr"));
            }

            let peer_prefix = p[19];
            if peer_prefix != PEER_PREFIX {
                return Err(AgentError::Rejected("netcfg: peer_prefix must be 32"));
            }

            let mut routes = Vec::with_capacity(route_count);
            for i in 0..route_count {
                let off = ADD_FIXED_LEN + i * ROUTE_LEN;
                let mut dest = [0u8; 4];
                dest.copy_from_slice(&p[off..off + 4]);
                let prefix = p[off + 4];
                let metric = u32_le(&p[off + 5..off + 9]);

                // v1 driver-domain tightness. The WIRE can already express a
                // proxy uplink (default route via peer); this validator admits
                // only the single peer/32 route the v1 graph has a use for.
                if dest != peer || prefix != PEER_PREFIX {
                    return Err(AgentError::Rejected("netcfg: v1 admits only a peer/32 route"));
                }
                routes.push(Route { dest, prefix, metric });
            }

            Ok(Cmd::Add(Link {
                link_id,
                mac,
                local,
                peer,
                peer_prefix,
                routes,
            }))
        }

        _ => Err(AgentError::Rejected("netcfg: unknown sub-opcode")),
    }
}

// --- record set -----------------------------------------------------

fn ensure_dir() -> Result<()> {
    match fs::DirBuilder::new().mode(0o700).create(RUNTIME_DIR) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => Ok(()),
        Err(e) => Err(AgentError::Io(e)),
    }
}

fn record_path(link_id: u32) -> PathBuf {
    PathBuf::from(RUNTIME_DIR).join(format!("link-{link_id:08x}"))
}

fn read_record(link_id: u32) -> Result<Option<Vec<u8>>> {
    match fs::read(record_path(link_id)) {
        Ok(b) => Ok(Some(b)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(AgentError::Io(e)),
    }
}

/// Write atomically: a temp file plus rename, so no reader (including a
/// restarted agent) can ever observe a half-written record. No fsync — the
/// directory is tmpfs and the whole record set is boot-scoped by design.
/// The temp name deliberately does NOT start with `link-`, so it is invisible
/// to `count_links`.
fn write_record(link_id: u32, bytes: &[u8]) -> Result<()> {
    let tmp = PathBuf::from(RUNTIME_DIR).join(format!(".tmp-{link_id:08x}"));
    {
        let mut f = fs::File::create(&tmp).map_err(AgentError::Io)?;
        f.write_all(bytes).map_err(AgentError::Io)?;
    }
    fs::rename(&tmp, record_path(link_id)).map_err(AgentError::Io)
}

fn remove_record(link_id: u32) -> Result<()> {
    match fs::remove_file(record_path(link_id)) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(AgentError::Io(e)),
    }
}

/// Count installed links by scanning the directory rather than caching.
/// ADR-025 makes the filesystem the state; an in-memory counter would be a
/// second source of truth that diverges on restart. 128 dirents is nothing.
fn count_links() -> Result<usize> {
    let mut n = 0usize;
    for entry in fs::read_dir(RUNTIME_DIR).map_err(AgentError::Io)? {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        if entry.file_name().to_string_lossy().starts_with("link-") {
            n += 1;
        }
    }
    Ok(n)
}

// --- mechanism drivers ----------------------------------------------

/// The two lookup outcomes that are not one interface, as refusals. Kept
/// distinct from each other and from every other `Rejected` by their text,
/// which is what reaches the journal (the wire answer is a bare ERR).
const NO_INTERFACE: &str = "netcfg: no interface matches the requested MAC";
const DUPLICATE_MAC: &str =
    "netcfg: more than one interface carries the requested MAC (ADR-035 §7), refusing to choose";

/// Bring the link up, install the p2p address, then every route.
/// Order matters: a route on a down interface does not take.
///
/// ADD refuses both non-unique outcomes before anything is programmed: no
/// interface (the device is not there yet; retryable) and a duplicate (ADR-035
/// §7, R104).
fn drive_add(link: &Link) -> Result<()> {
    let ifindex = match netlink::ifindex_by_mac(&link.mac)? {
        netlink::MacMatch::One(i) => i,
        netlink::MacMatch::None => return Err(AgentError::Rejected(NO_INTERFACE)),
        netlink::MacMatch::Many(_) => return Err(AgentError::Rejected(DUPLICATE_MAC)),
    };
    let mut sock = netlink::NlSocket::open()?;

    netlink::link_up(&mut sock, ifindex)?;
    netlink::addr_add(&mut sock, ifindex, &link.local, &link.peer, link.peer_prefix)?;
    for r in &link.routes {
        netlink::route_add(&mut sock, ifindex, &r.dest, r.prefix, r.metric)?;
    }
    Ok(())
}

/// Exact reverse: routes first, then the address.
///
/// `IFF_UP` is deliberately NOT cleared. "Down" is not part of the state the
/// payload describes, a shared netdev would be broken by it, and ADD raises it
/// again idempotently anyway.
///
/// Removing the address also removes the kernel's own implicit `proto kernel`
/// route to the peer — the one the peer address installs by itself (verified
/// 2026-07-23). Teardown is therefore complete without asking for it.
///
/// Takes the ifindex its caller resolved: what a REMOVE does with each lookup
/// outcome is the flow's decision (`do_remove`), not the mechanism's.
fn drive_remove(link: &Link, ifindex: u32) -> Result<()> {
    let mut sock = netlink::NlSocket::open()?;

    for r in &link.routes {
        netlink::route_del(&mut sock, ifindex, &r.dest, r.prefix, r.metric)?;
    }
    netlink::addr_del(&mut sock, ifindex, &link.local, &link.peer, link.peer_prefix)?;
    Ok(())
}

// --- flows ----------------------------------------------------------

fn do_add(payload: &[u8], link: &Link) -> Result<()> {
    ensure_dir()?;

    match read_record(link.link_id)? {
        // Identical re-ADD: OK, and the mechanism is still re-driven — the
        // record proves intent, not that the kernel currently agrees.
        Some(prev) if prev == payload => {}
        // A live id may not be redefined in place: a mutable link is a
        // boundary that moves without anyone deciding to move it (ADR-023,
        // no `modify`). Withdraw it explicitly, then add the new one.
        Some(_) => {
            return Err(AgentError::Rejected(
                "netcfg: link_id already installed with a different payload",
            ))
        }
        None => {
            if count_links()? >= MAX_LINKS {
                return Err(AgentError::Rejected("netcfg: link table full"));
            }
            // Record BEFORE mechanism: a crash here leaves a record that the
            // retry completes, never live state nobody knows about.
            write_record(link.link_id, payload)?;
        }
    }

    drive_add(link)
}

fn do_remove(link_id: u32) -> Result<()> {
    ensure_dir()?;

    let bytes = match read_record(link_id)? {
        Some(b) => b,
        // Absent id: the postcondition already holds.
        None => return Ok(()),
    };

    let link = match parse(&bytes)? {
        Cmd::Add(l) => l,
        // Only ADD payloads are ever written; anything else means the record
        // set was tampered with, which is not something to converge on.
        Cmd::Remove(_) => return Err(AgentError::Rejected("netcfg: corrupt record")),
    };

    match netlink::ifindex_by_mac(&link.mac)? {
        netlink::MacMatch::One(ifindex) => drive_remove(&link, ifindex)?,
        // The netdev is gone (hot-unplug, or the launcher changed): its kernel
        // state went with it, so the postcondition IS reached. Converge —
        // dropping the record is what keeps a vanished device from leaving an
        // id that can never be removed. This is the ONLY lookup outcome a
        // REMOVE absorbs, and no mechanism error is absorbed at all.
        netlink::MacMatch::None => {}
        // A duplicate is not a vanished device (ADR-035 §7, R104). Absorbing
        // it would delete the record and leave whatever the ADD programmed in
        // the kernel with no record naming it, the shape ADR-025 forbids. ERR,
        // and the record stays for a retry once the duplicate is gone.
        netlink::MacMatch::Many(_) => return Err(AgentError::Rejected(DUPLICATE_MAC)),
    }

    // Mechanism BEFORE record deletion.
    remove_record(link_id)
}

// --- entry point ----------------------------------------------------

/// Handle one NETCFG request. The caller replies OK on `Ok(())` and ERR on
/// `Err` — reply AFTER the act, the deliberate mirror of SHUTDOWN's
/// reply-first (ADR-024): there the reply must precede an act that kills the
/// agent; here the reply IS the postcondition report and the agent survives it.
pub fn handle(req: &RawRequest) -> Result<()> {
    // NETCFG carries its whole contract in the payload. Arguments would be a
    // second, unvalidated channel into a privileged handler.
    if !req.args.is_empty() {
        return Err(AgentError::Rejected("netcfg: takes no arguments"));
    }

    match parse(&req.payload)? {
        Cmd::Add(link) => {
            let payload = req.payload.clone();
            do_add(&payload, &link)
        }
        Cmd::Remove(id) => do_remove(id),
    }
}

// --- tests ----------------------------------------------------------
// Parser only: total validation is the part that must not drift, and it is
// testable without touching /run or the kernel.

#[cfg(test)]
mod tests {
    use super::*;

    const MAC: [u8; 6] = [0x52, 0x54, 0x0a, 0x64, 0x01, 0x01];
    const PEER: [u8; 4] = [10, 100, 1, 2];

    /// A well-formed single-route ADD, 30 bytes.
    fn add(mac: [u8; 6], local: [u8; 4], peer: [u8; 4], prefix: u8, routes: &[([u8; 4], u8, u32)]) -> Vec<u8> {
        let mut p = Vec::new();
        p.push(OP_ADD);
        p.extend_from_slice(&1u32.to_le_bytes());
        p.extend_from_slice(&mac);
        p.extend_from_slice(&local);
        p.extend_from_slice(&peer);
        p.push(prefix);
        p.push(routes.len() as u8);
        for (dest, pfx, metric) in routes {
            p.extend_from_slice(dest);
            p.push(*pfx);
            p.extend_from_slice(&metric.to_le_bytes());
        }
        p
    }

    fn good() -> Vec<u8> {
        add(MAC, INTERNAL_LOCAL, PEER, 32, &[(PEER, 32, 100)])
    }

    #[test]
    fn add_roundtrip() {
        let p = good();
        assert_eq!(p.len(), 30);
        match parse(&p).unwrap() {
            Cmd::Add(l) => {
                assert_eq!(l.link_id, 1);
                assert_eq!(l.mac, MAC);
                assert_eq!(l.peer, PEER);
                assert_eq!(l.routes, vec![Route { dest: PEER, prefix: 32, metric: 100 }]);
            }
            other => panic!("expected Add, got {other:?}"),
        }
    }

    #[test]
    fn remove_is_exactly_five_bytes() {
        let mut p = vec![OP_REMOVE];
        p.extend_from_slice(&7u32.to_le_bytes());
        assert_eq!(parse(&p).unwrap(), Cmd::Remove(7));

        p.push(0);
        assert!(parse(&p).is_err(), "6-byte REMOVE must be rejected");
    }

    #[test]
    fn length_is_exact_not_minimum() {
        let mut p = good();
        p.push(0);
        assert!(parse(&p).is_err(), "trailing byte must be rejected");
        let short = &good()[..29];
        assert!(parse(short).is_err(), "truncated ADD must be rejected");
    }

    /// The uplink fence: a globally-administered (OUI) MAC — which is what
    /// every physical NIC carries — cannot be named by a payload.
    #[test]
    fn mac_must_be_locally_administered_unicast() {
        let oui = add(
            [0x00, 0xe0, 0x4c, 0x68, 0x01, 0x01],
            INTERNAL_LOCAL,
            PEER,
            32,
            &[(PEER, 32, 100)],
        );
        assert!(parse(&oui).is_err(), "OUI MAC must be rejected");

        let mcast = add([0x53, 0x54, 0x0a, 0x64, 0x01, 0x01], INTERNAL_LOCAL, PEER, 32, &[(PEER, 32, 100)]);
        assert!(parse(&mcast).is_err(), "multicast MAC must be rejected");
    }

    #[test]
    fn local_is_pinned() {
        let p = add(MAC, [10, 100, 1, 9], PEER, 32, &[(PEER, 32, 100)]);
        assert!(parse(&p).is_err());
    }

    #[test]
    fn peer_must_be_a_usable_host_in_the_segment() {
        for bad in [[10, 100, 2, 5], [10, 100, 1, 0], [10, 100, 1, 255], INTERNAL_LOCAL] {
            let p = add(MAC, INTERNAL_LOCAL, bad, 32, &[(bad, 32, 100)]);
            assert!(parse(&p).is_err(), "peer {bad:?} must be rejected");
        }
    }

    #[test]
    fn peer_prefix_must_be_32() {
        let p = add(MAC, INTERNAL_LOCAL, PEER, 24, &[(PEER, 32, 100)]);
        assert!(parse(&p).is_err());
    }

    #[test]
    fn route_count_is_bounded() {
        let none = add(MAC, INTERNAL_LOCAL, PEER, 32, &[]);
        assert!(parse(&none).is_err(), "route_count 0 must be rejected");

        let five: Vec<([u8; 4], u8, u32)> = (0..5).map(|i| (PEER, 32, i)).collect();
        let many = add(MAC, INTERNAL_LOCAL, PEER, 32, &five);
        assert!(parse(&many).is_err(), "route_count 5 must be rejected");
    }

    /// v1 tightness: the wire could carry a default route for a proxy, but the
    /// driver-domain validator admits only peer/32.
    #[test]
    fn v1_admits_only_the_peer_route() {
        let default_route = add(MAC, INTERNAL_LOCAL, PEER, 32, &[([0, 0, 0, 0], 0, 100)]);
        assert!(parse(&default_route).is_err());
    }

    #[test]
    fn link_id_zero_and_unknown_opcode_are_rejected() {
        let mut p = good();
        p[1..5].copy_from_slice(&0u32.to_le_bytes());
        assert!(parse(&p).is_err());

        let mut q = good();
        q[0] = 0x03;
        assert!(parse(&q).is_err());

        assert!(parse(&[]).is_err());
    }
}
