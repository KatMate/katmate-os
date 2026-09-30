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
//! One record per INTERFACE, named `mac-<12 lowercase hex>` after the
//! `match_mac` that selects it (ADR-035 §6, R105), under `RUNTIME_DIR`,
//! containing the validated ADD payload VERBATIM. An interface has one link:
//! an ADD with a new `link_id` on a recorded MAC supersedes the old record by
//! one rename over it, and a late REMOVE of the old id then finds nothing and
//! is absorbed. An id is found by scanning the records' contents (R114): a
//! recorded id with a byte-identical payload is re-driven, and with any other
//! payload, on its own interface or another, is ERR (ADR-025, ADR-023 no
//! `modify`). Consequences that fall out of that choice rather than being
//! coded for: identical-ADD is a byte comparison; REMOVE reconstructs what to
//! withdraw by re-parsing the record (the 5-byte REMOVE payload does not carry
//! it); an agent restart loses nothing. The directory is `/run` — volatile by
//! design, because the launch daemon must re-issue every link after a netVM
//! restart anyway (a hotplugged appVM netdev does not survive one either). The
//! `link-<id>` records of earlier builds are not read: they are on tmpfs and do
//! not survive the reboot that installs this build.
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

/// The pool's slot MAC prefix and size (ADR-035 §2): slot `k` carries
/// `52:54:01:00:00:kk`, `k` < 16. The two middle octets are reserved zero.
const POOL_MAC_PREFIX: [u8; 5] = [0x52, 0x54, 0x01, 0x00, 0x00];
const POOL_SLOTS: u8 = 16;
/// The pool's peer block, `10.100.1.16/28` (ADR-035 §4): slot `k`'s peer is
/// `10.100.1.(16 + k)`.
const POOL_PEER_BASE: u8 = 16;

// --- parsing --------------------------------------------------------

/// The pool slot a MAC names, if it is a pool MAC at all.
fn pool_slot(mac: &[u8; 6]) -> Option<u8> {
    (mac[0..5] == POOL_MAC_PREFIX && mac[5] < POOL_SLOTS).then_some(mac[5])
}

/// R103 (ADR-035's note of 2026-09-29; open problem #49): a pool MAC pairs
/// with exactly its own slot's peer, and no other MAC may name a peer in the
/// pool's block. Without it an ADD pairing slot `k` with another slot's peer
/// is accepted here and its traffic then dropped by the ruleset's slot_guard
/// silently. MAC and peer are both views of `k` (§1), so this relates two
/// views of one index; it adds no carrier. Decode-time and pure, like every
/// rule above; the wire answer is a bare ERR, and the reason is this text in
/// the journal.
fn check_pool_pairing(mac: &[u8; 6], peer: &[u8; 4]) -> Result<()> {
    let in_block = (POOL_PEER_BASE..POOL_PEER_BASE + POOL_SLOTS).contains(&peer[3]);
    match pool_slot(mac) {
        Some(k) if peer[3] != POOL_PEER_BASE + k => Err(AgentError::Rejected(
            "netcfg: a pool MAC 52:54:01:00:00:kk requires the peer 10.100.1.(16+k) (R103)",
        )),
        None if in_block => Err(AgentError::Rejected(
            "netcfg: a non-pool MAC may not name a peer in the pool block .16-.31 (R103)",
        )),
        _ => Ok(()),
    }
}

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
            check_pool_pairing(&mac, &peer)?;

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

const RECORD_PREFIX: &str = "mac-";

/// `mac-<12 lowercase hex>`: one record per interface, keyed by the MAC the
/// payload selects it by (R105).
fn record_name(mac: &[u8; 6]) -> String {
    let hex: String = mac.iter().map(|b| format!("{b:02x}")).collect();
    format!("{RECORD_PREFIX}{hex}")
}

fn record_path(mac: &[u8; 6]) -> PathBuf {
    PathBuf::from(RUNTIME_DIR).join(record_name(mac))
}

fn read_record(mac: &[u8; 6]) -> Result<Option<Vec<u8>>> {
    match fs::read(record_path(mac)) {
        Ok(b) => Ok(Some(b)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(AgentError::Io(e)),
    }
}

/// Write atomically: a temp file plus rename, so no reader (including a
/// restarted agent) can ever observe a half-written record. No fsync — the
/// directory is tmpfs and the whole record set is boot-scoped by design.
/// The temp name deliberately does NOT start with `mac-`, so it is invisible
/// to the scans below. The rename is also what makes a supersession one step:
/// it replaces the interface's previous record in place (R105).
fn write_record(mac: &[u8; 6], bytes: &[u8]) -> Result<()> {
    let tmp = PathBuf::from(RUNTIME_DIR).join(format!(".tmp-{}", record_name(mac)));
    {
        let mut f = fs::File::create(&tmp).map_err(AgentError::Io)?;
        f.write_all(bytes).map_err(AgentError::Io)?;
    }
    fs::rename(&tmp, record_path(mac)).map_err(AgentError::Io)
}

fn remove_record(mac: &[u8; 6]) -> Result<()> {
    match fs::remove_file(record_path(mac)) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(AgentError::Io(e)),
    }
}

/// Parse a stored record back into the link it describes. Only ADD payloads
/// are ever written, under the name of their own MAC; anything else means the
/// record set was tampered with, which is not something to converge on.
fn parse_record(name: &str, bytes: &[u8]) -> Result<Link> {
    match parse(bytes) {
        Ok(Cmd::Add(l)) if record_name(&l.mac) == name => Ok(l),
        _ => Err(AgentError::Rejected("netcfg: corrupt record")),
    }
}

/// Every record in the set, as (payload bytes, parsed link). A scan, not a
/// cache: ADR-025 makes the filesystem the state, and an index kept in memory
/// or in a second file would be a second source of truth that diverges on
/// restart. At most one record per interface, and 128 at most: nothing.
fn scan_records() -> Result<Vec<(Vec<u8>, Link)>> {
    let mut out = Vec::new();
    for entry in fs::read_dir(RUNTIME_DIR).map_err(AgentError::Io)? {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        if !name.starts_with(RECORD_PREFIX) {
            continue;
        }
        let bytes = match fs::read(entry.path()) {
            Ok(b) => b,
            // Removed between the listing and the read: not a record now.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(AgentError::Io(e)),
        };
        let link = parse_record(&name, &bytes)?;
        out.push((bytes, link));
    }
    Ok(out)
}

/// The record holding `link_id`, wherever it sits (R114). The key is the MAC,
/// so an id is found by content; two records naming one id cannot arise from
/// the flows below and is treated as corruption.
fn find_link_id(link_id: u32) -> Result<Option<(Vec<u8>, Link)>> {
    let mut hits = scan_records()?
        .into_iter()
        .filter(|(_, l)| l.link_id == link_id);
    let first = hits.next();
    if hits.next().is_some() {
        return Err(AgentError::Rejected(
            "netcfg: corrupt record set: link_id recorded twice",
        ));
    }
    Ok(first)
}

// --- mechanism drivers ----------------------------------------------

/// The two lookup outcomes that are not one interface, as refusals. Kept
/// distinct from each other and from every other `Rejected` by their text,
/// which is what reaches the journal (the wire answer is a bare ERR).
const NO_INTERFACE: &str = "netcfg: no interface matches the requested MAC";
const DUPLICATE_MAC: &str =
    "netcfg: more than one interface carries the requested MAC (ADR-035 §7), refusing to choose";

/// ADD refuses both non-unique lookup outcomes before anything is programmed:
/// no interface (the device is not there yet; retryable) and a duplicate
/// (ADR-035 §7, R104).
fn ifindex_for_add(mac: &[u8; 6]) -> Result<u32> {
    match netlink::ifindex_by_mac(mac)? {
        netlink::MacMatch::One(i) => Ok(i),
        netlink::MacMatch::None => Err(AgentError::Rejected(NO_INTERFACE)),
        netlink::MacMatch::Many(_) => Err(AgentError::Rejected(DUPLICATE_MAC)),
    }
}

/// Bring the link up, install the p2p address, then every route.
/// Order matters: a route on a down interface does not take.
fn drive_add(link: &Link, ifindex: u32) -> Result<()> {
    let mut sock = netlink::NlSocket::open()?;

    netlink::link_up(&mut sock, ifindex)?;
    netlink::addr_add(&mut sock, ifindex, &link.local, &link.peer, link.peer_prefix)?;
    for r in &link.routes {
        netlink::route_add(&mut sock, ifindex, &r.dest, r.prefix, r.metric)?;
    }
    Ok(())
}

/// What a superseded record carried that its successor does not (R105): each
/// route the new payload does not carry, and the address only if the new
/// payload's differs. Nothing the successor carries is touched, so the
/// address the two share stays (ADR-035's 2026-09-12 note, finding 1: the
/// withdrawal of an old record took the new link's address with it).
///
/// What this can contain in practice. Both records name the same interface.
/// For a pool MAC, R103 fixes the peer, and `local` is the v1 constant, so the
/// address is identical and never withdrawn: the set is at most routes to
/// that peer at metrics the new payload does not list. Only a non-pool MAC
/// could change its peer, and the image carries no locally-administered
/// interface but the sixteen slots.
fn superseded_leftovers(old: &Link, new: &Link) -> (Vec<Route>, bool) {
    let routes = old
        .routes
        .iter()
        .filter(|r| !new.routes.contains(r))
        .map(|r| Route {
            dest: r.dest,
            prefix: r.prefix,
            metric: r.metric,
        })
        .collect();
    let address = (old.local, old.peer, old.peer_prefix) != (new.local, new.peer, new.peer_prefix);
    (routes, address)
}

fn withdraw_superseded(old: &Link, new: &Link, ifindex: u32) -> Result<()> {
    let (routes, address) = superseded_leftovers(old, new);
    if routes.is_empty() && !address {
        return Ok(());
    }
    let mut sock = netlink::NlSocket::open()?;
    for r in &routes {
        netlink::route_del(&mut sock, ifindex, &r.dest, r.prefix, r.metric)?;
    }
    if address {
        netlink::addr_del(&mut sock, ifindex, &old.local, &old.peer, old.peer_prefix)?;
    }
    Ok(())
}

/// Exact reverse: routes first, then the address, then the link down, then
/// the slot's conntrack entries.
///
/// Then `IFF_UP` is cleared (ADR-035 §6: FREE is DOWN; R102, R106). It used
/// to be left set, on the grounds that "down" was not state the payload
/// described and that a shared netdev would be broken by it. Under the pool a
/// slot interface is one link's alone (R105), and DOWN is what empties it:
/// taking the link down flushes the slot's own neighbour entries, so no
/// `RTM_DELNEIGH` is sent (R106), and with IPv6 disabled on netVM's kernel
/// (R102) there is no link-local left behind to clear (open problem #45). A
/// late or hostile frame into a released slot is then dropped by the kernel.
/// The next ADD raises it again.
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
    netlink::link_down(&mut sock, ifindex)?;

    // Last, once the slot is down and no new flow can start on it: flush the
    // slot's conntrack entries with ONE ctnetlink delete by mark (ADR-035 §6;
    // R107). The ruleset's slot_mark chain marks every new flow arriving on
    // slot k with k+1 (R116). A NON-POOL MAC has no slot, hence no mark and
    // no flush: nothing in the ruleset marks its flows, and a flush by any
    // mark would reach another slot's entries.
    if let Some(k) = pool_slot(&link.mac) {
        let mut ct = netlink::NlSocket::open_netfilter()?;
        netlink::ct_flush_mark(&mut ct, u32::from(k) + 1)?;
    }
    Ok(())
}

// --- flows ----------------------------------------------------------

fn do_add(payload: &[u8], link: &Link) -> Result<()> {
    ensure_dir()?;

    // The id first, wherever it is recorded (R114): the key is the MAC, so an
    // id is found by scanning.
    match find_link_id(link.link_id)? {
        // Identical re-ADD: OK, and the mechanism is still re-driven — the
        // record proves intent, not that the kernel currently agrees.
        Some((prev, _)) if prev == payload => {
            return drive_add(link, ifindex_for_add(&link.mac)?);
        }
        // A live id may not be redefined in place, on its own interface or on
        // another: a mutable link is a boundary that moves without anyone
        // deciding to move it (ADR-023, no `modify`; ADR-025 "ADD, id present,
        // different -> ERR"). Nothing is programmed and the record stays.
        Some(_) => {
            return Err(AgentError::Rejected(
                "netcfg: link_id already installed with a different payload (R114)",
            ))
        }
        None => {}
    }

    // A new id. Record BEFORE mechanism: a crash here leaves a record that the
    // retry completes, never live state nobody knows about.
    let superseded = match read_record(&link.mac)? {
        None => {
            if scan_records()?.len() >= MAX_LINKS {
                return Err(AgentError::Rejected("netcfg: link table full"));
            }
            write_record(&link.mac, payload)?;
            None
        }
        // The interface already carries a link under another id: the newer
        // assignment is the truth, and it SUPERSEDES the old record (ADR-035
        // §6, R105) in one rename over the interface's record. A late REMOVE
        // of the old id then finds nothing and is absorbed (`do_remove`).
        Some(old_bytes) => {
            let old = parse_record(&record_name(&link.mac), &old_bytes)?;
            write_record(&link.mac, payload)?;
            Some(old)
        }
    };

    let ifindex = ifindex_for_add(&link.mac)?;
    drive_add(link, ifindex)?;
    // Only after the new link is programmed, and only what the new payload
    // does not carry. A crash between the rename and this step leaves that
    // remainder in the kernel with no record naming it; an ERR from
    // drive_add above leaves it too, and an identical retry of the new ADD
    // does not come back here. Both are recorded in s4c-a's report, not
    // designed for here.
    match superseded {
        Some(old) => withdraw_superseded(&old, link, ifindex),
        None => Ok(()),
    }
}

fn do_remove(link_id: u32) -> Result<()> {
    ensure_dir()?;

    let link = match find_link_id(link_id)? {
        Some((_, l)) => l,
        // Absent id: the postcondition already holds. This is also where a
        // late REMOVE from a superseded tenant lands (ADR-035 §6).
        None => return Ok(()),
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

    // Mechanism BEFORE record deletion. The record is the one just found by
    // its id; the agent serves one request at a time, so nothing replaced it
    // in between.
    remove_record(&link.mac)
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

    fn pool_mac(k: u8) -> [u8; 6] {
        [0x52, 0x54, 0x01, 0x00, 0x00, k]
    }

    fn with_peer(mac: [u8; 6], last: u8) -> Vec<u8> {
        let peer = [10, 100, 1, last];
        add(mac, INTERNAL_LOCAL, peer, 32, &[(peer, 32, 100)])
    }

    /// R103: every pool slot with its own peer is accepted.
    #[test]
    fn pool_mac_with_its_peer_is_accepted() {
        for k in 0..16u8 {
            assert!(
                parse(&with_peer(pool_mac(k), 16 + k)).is_ok(),
                "slot {k:02x} with 10.100.1.{} must be accepted",
                16 + k
            );
        }
    }

    /// R103: a pool MAC with any other peer is rejected, another slot's peer
    /// and a non-pool peer alike.
    #[test]
    fn pool_mac_with_a_wrong_peer_is_rejected() {
        for k in 0..16u8 {
            for last in [2u8, 15, 32, 254] {
                assert!(parse(&with_peer(pool_mac(k), last)).is_err());
            }
            for j in 0..16u8 {
                if j != k {
                    assert!(
                        parse(&with_peer(pool_mac(k), 16 + j)).is_err(),
                        "slot {k:02x} with slot {j:02x}'s peer must be rejected"
                    );
                }
            }
        }
    }

    /// R103: a non-pool MAC may not name a peer in .16-.31. `52:54:01:00:00:10`
    /// is outside the pool (k < 16), so it counts as non-pool here.
    #[test]
    fn non_pool_mac_may_not_name_a_pool_peer() {
        for mac in [MAC, pool_mac(0x10), [0x52, 0x54, 0x00, 0x21, 0xb2, 0x08]] {
            for last in 16u8..32 {
                assert!(
                    parse(&with_peer(mac, last)).is_err(),
                    "{mac:02x?} with 10.100.1.{last} must be rejected"
                );
            }
        }
    }

    /// R103: a non-pool MAC naming a peer outside the block stays admissible
    /// (ADR-035 §4: .2-.15 are for links that are not pool slots).
    #[test]
    fn non_pool_mac_with_another_peer_is_accepted() {
        for mac in [MAC, pool_mac(0x10)] {
            for last in [2u8, 15, 32, 254] {
                assert!(
                    parse(&with_peer(mac, last)).is_ok(),
                    "{mac:02x?} with 10.100.1.{last} must be accepted"
                );
            }
        }
    }

    #[test]
    fn record_is_named_after_its_mac() {
        assert_eq!(record_name(&pool_mac(0x0b)), "mac-52540100000b");
        assert_eq!(record_name(&MAC), "mac-52540a640101");
    }

    /// A record whose name is not its own payload's MAC, or that is not an
    /// ADD, is corrupt and is not converged on.
    #[test]
    fn a_record_under_another_name_is_corrupt() {
        let p = with_peer(pool_mac(3), 19);
        assert!(parse_record("mac-525401000003", &p).is_ok());
        assert!(parse_record("mac-525401000004", &p).is_err());
        let mut rm = vec![OP_REMOVE];
        rm.extend_from_slice(&7u32.to_le_bytes());
        assert!(parse_record("mac-525401000003", &rm).is_err());
    }

    fn link_with_metrics(mac: [u8; 6], last: u8, metrics: &[u32]) -> Link {
        let peer = [10, 100, 1, last];
        let routes: Vec<([u8; 4], u8, u32)> = metrics.iter().map(|m| (peer, 32, *m)).collect();
        match parse(&add(mac, INTERNAL_LOCAL, peer, 32, &routes)).unwrap() {
            Cmd::Add(l) => l,
            other => panic!("expected Add, got {other:?}"),
        }
    }

    /// R105 on a pool slot: the superseding payload names the same peer (R103),
    /// so the address is never in the withdrawal set, and only routes the new
    /// payload does not carry are.
    #[test]
    fn supersession_on_a_slot_withdraws_only_missing_routes() {
        let old = link_with_metrics(pool_mac(2), 18, &[100, 200]);
        let new = link_with_metrics(pool_mac(2), 18, &[200, 300]);
        let (routes, address) = superseded_leftovers(&old, &new);
        assert!(!address, "the shared address must not be withdrawn");
        assert_eq!(
            routes,
            vec![Route {
                dest: [10, 100, 1, 18],
                prefix: 32,
                metric: 100
            }]
        );

        let (routes, address) = superseded_leftovers(&old, &old);
        assert!(
            routes.is_empty() && !address,
            "an identical successor withdraws nothing"
        );
    }

    /// Only a non-pool MAC can change its peer across a supersession; then the
    /// old address and all its routes are in the set.
    #[test]
    fn supersession_with_a_new_peer_withdraws_the_old_address() {
        let old = link_with_metrics(MAC, 2, &[100]);
        let new = link_with_metrics(MAC, 3, &[100]);
        let (routes, address) = superseded_leftovers(&old, &new);
        assert!(address);
        assert_eq!(
            routes,
            vec![Route {
                dest: [10, 100, 1, 2],
                prefix: 32,
                metric: 100
            }]
        );
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
