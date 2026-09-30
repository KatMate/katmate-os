//! netlink.rs — the NETCFG mechanism: direct `AF_NETLINK` / `NETLINK_ROUTE`
//! programming of address, route and `IFF_UP` (set on ADD, cleared on
//! REMOVE), and one `NETLINK_NETFILTER` message, REMOVE's conntrack delete by
//! mark (ADR-035 §6, R107). Path B of ADR-025, resolved by
//! the E1-E5 gate of 2026-07-21 (no dbus-less networkd reload trigger exists:
//! bus call inert, varlink surface carries no mutator, `SIGRTMIN+1` kills
//! networkd rather than reloading it).
//!
//! WHY HAND-ROLLED, NOT A CRATE
//!
//! This module is the first thing in `netvm-agent` that could have pulled a
//! dependency, and the binary it lives in holds CAP_NET_ADMIN + CAP_KILL in the
//! most exposed VM in the system (r8169 + Realtek blob, and in v1 the WireGuard
//! key, share its address space). The netlink UAPI is frozen by kernel
//! contract; the crates that wrap it are not (`netlink-packet-route` broke API
//! across 0.17/0.19/0.21, `neli` across 0.6/0.7, `rtnetlink` is async-only and
//! drags a tokio runtime into a binary that serves one synchronous VSOCK
//! request at a time). A wrapper would therefore not remove the netlink
//! semantics one has to know — it would relocate them into someone else's type
//! system and add churn under a privileged capability set. Same reasoning as
//! the deliberately non-serde wire in `katmate-protocol`.
//!
//! WHAT MAKES THAT SAFE: GOLDEN FIXTURES
//!
//! Every rtnetlink message shape below was captured from iproute2 under
//! `strace -e trace=sendmsg` on a dummy interface (2026-07-23; the link-down
//! message on `lo` in an empty namespace, 2026-09-30) and is pinned by a unit
//! test comparing this module's output byte-for-byte against the decoded
//! capture. "Did I build the message correctly" is therefore PROVEN against a
//! reference implementation, not remembered from a header. This is the ADR-024
//! empirics-before-commitment method applied to code.
//!
//! The ONE exception is the ctnetlink delete by mark. conntrack(8), the
//! reference tool, never sends that message: it dumps, then deletes by tuple
//! (captured 2026-09-30). Its test therefore pins bytes written from the spec
//! and checks them against conntrack's captured dump request, which carries
//! the same header layout and the same two attributes (operator ruling,
//! 2026-09-30). That the kernel accepts it as a filtered flush is not proven
//! here.
//!
//! WHAT IS DELIBERATELY ABSENT
//!
//!   * No dump / multipart parsing. The one place netlink is genuinely hard
//!     (parsing an `RTM_GETLINK` dump to map MAC -> ifindex) is replaced by
//!     read-only sysfs — see `ifindex_by_mac`. iproute2 does the dump on a
//!     second socket; we do not need to.
//!   * No generic "netlink layer". One function per concrete message, each
//!     with its golden fixture. Nothing to grow.
//!   * No state. The kernel is driven, never read back: idempotence is decided
//!     against the record set in `RuntimeDirectory=`, per ADR-025.
//!
//! EMPIRICAL NOTE (2026-07-23), load-bearing for the caller and the gate:
//! adding a peer address installs a kernel route to the peer by itself
//! (`10.100.1.2 proto kernel scope link src 10.100.1.1`, metric 0). The
//! payload's explicit route is therefore ADDITIVE in v1, not the thing that
//! carries reachability, and it is distinguishable only by its `RTA_PRIORITY`.
//! A live gate that merely asserts "a route to the peer exists" would pass
//! without this module sending `RTM_NEWROUTE` at all.
//!
//! BYTE ORDER. Two different conventions meet here and must not be confused:
//!   * netlink headers and struct bodies are HOST byte order -> `to_ne_bytes`,
//!     written as such to state the intent rather than to rely on x86-64.
//!   * IPv4 addresses inside attributes are NETWORK byte order. The NETCFG
//!     payload carries them as raw `[u8; 4]` in network order already (the
//!     implementation reading of ADR-025: the LE-integer rule governs genuine
//!     integers — `link_id`, `metric` — while an address is a byte array, the
//!     same class as `match_mac`). They are copied through untouched; there is
//!     no conversion in this module, and therefore no conversion to get wrong.

use std::fs;
use std::os::fd::RawFd;

use katmate_protocol::error::{AgentError, Result};

// --- uapi constants -------------------------------------------------
// From linux/netlink.h, linux/rtnetlink.h, linux/if_addr.h, linux/if.h.
// Spelled out locally rather than taken from libc: this module is meant to be
// auditable against the headers without chasing which constants a given libc
// version happens to re-export.

const NLMSG_ERROR: u16 = 0x0002;

const NLM_F_REQUEST: u16 = 0x0001;
const NLM_F_ACK: u16 = 0x0004;
const NLM_F_EXCL: u16 = 0x0200;
const NLM_F_CREATE: u16 = 0x0400;

const RTM_NEWLINK: u16 = 16;
const RTM_NEWADDR: u16 = 20;
const RTM_DELADDR: u16 = 21;
const RTM_NEWROUTE: u16 = 24;
const RTM_DELROUTE: u16 = 25;

const IFA_ADDRESS: u16 = 1;
const IFA_LOCAL: u16 = 2;

const RTA_DST: u16 = 1;
const RTA_OIF: u16 = 4;
const RTA_PRIORITY: u16 = 6;

const RT_TABLE_MAIN: u8 = 254;

const RTPROT_UNSPEC: u8 = 0;
const RTPROT_BOOT: u8 = 3;

const RT_SCOPE_UNIVERSE: u8 = 0;
const RT_SCOPE_LINK: u8 = 253;
const RT_SCOPE_NOWHERE: u8 = 255;

const RTN_UNSPEC: u8 = 0;
const RTN_UNICAST: u8 = 1;

const IFF_UP: u32 = 0x1;

// From linux/netfilter/nfnetlink.h, nfnetlink_conntrack.h.
const NFNL_SUBSYS_CTNETLINK: u16 = 1;
const IPCTNL_MSG_CT_DELETE: u16 = 2;
const NFNETLINK_V0: u8 = 0;
const CTA_MARK: u16 = 8;
const CTA_MARK_MASK: u16 = 21;

const NLMSG_HDRLEN: usize = 16;

/// Reply buffer. Our largest request is 52 bytes; an ACK carries `nlmsgerr`
/// (4 + the echoed header) plus, under `NETLINK_EXT_ACK`, optional string
/// attributes. 8 KiB is generous by two orders of magnitude and fixed, so no
/// reply length can drive an allocation — the same rule `frame.rs` applies to
/// the VSOCK side.
const REPLY_BUF: usize = 8192;

// --- message builder ------------------------------------------------
// Builders emit `nlmsg_seq = 0`; `send_and_ack` patches in the real sequence
// number together with `nlmsg_len`. That keeps the builders pure and unit
// testable without a socket, exactly as `encode_request` is in `frame.rs`.

fn put_u16(b: &mut Vec<u8>, v: u16) {
    b.extend_from_slice(&v.to_ne_bytes());
}

fn put_u32(b: &mut Vec<u8>, v: u32) {
    b.extend_from_slice(&v.to_ne_bytes());
}

/// Start a message: 16-byte `nlmsghdr` with a placeholder length.
fn hdr(msg_type: u16, flags: u16) -> Vec<u8> {
    let mut b = Vec::with_capacity(64);
    put_u32(&mut b, 0); // nlmsg_len, patched by finish()
    put_u16(&mut b, msg_type);
    put_u16(&mut b, flags);
    put_u32(&mut b, 0); // nlmsg_seq, patched by send_and_ack()
    put_u32(&mut b, 0); // nlmsg_pid: 0 = let the kernel assign our port
    b
}

/// Append one `rtattr`: `{u16 len, u16 type}` + payload, padded to 4.
/// Every attribute this module emits is 4 bytes of data, so the padding branch
/// is never taken in practice — it is written out anyway so the helper is
/// correct if a later attribute is not.
fn put_attr(b: &mut Vec<u8>, attr_type: u16, data: &[u8]) {
    let len = 4 + data.len();
    put_u16(b, len as u16);
    put_u16(b, attr_type);
    b.extend_from_slice(data);
    while b.len() % 4 != 0 {
        b.push(0);
    }
}

/// Patch `nlmsg_len` now that the body is complete.
fn finish(mut b: Vec<u8>) -> Vec<u8> {
    let len = b.len() as u32;
    b[0..4].copy_from_slice(&len.to_ne_bytes());
    b
}

// --- the five messages ----------------------------------------------

/// `ip addr add <local> peer <peer>/<prefix> dev <if>` (or the DELADDR mirror).
///
/// The p2p form is the one the NETCFG payload describes directly:
/// `IFA_LOCAL` = our address, `IFA_ADDRESS` = the PEER, `ifa_prefixlen` = the
/// peer prefix. Captured from iproute2; note that the alternative (`local/24`
/// plus an explicit route, as used in the ADR-025 E5 dry run) would install a
/// connected route for the whole internal segment and break "REMOVE -> state
/// gone" for every other link.
fn msg_addr(msg_type: u16, flags: u16, ifindex: u32, local: &[u8; 4], peer: &[u8; 4], prefix: u8) -> Vec<u8> {
    let mut b = hdr(msg_type, flags);
    // struct ifaddrmsg
    b.push(libc::AF_INET as u8); // ifa_family
    b.push(prefix); // ifa_prefixlen
    b.push(0); // ifa_flags
    b.push(RT_SCOPE_UNIVERSE); // ifa_scope
    put_u32(&mut b, ifindex); // ifa_index
    put_attr(&mut b, IFA_LOCAL, local);
    put_attr(&mut b, IFA_ADDRESS, peer);
    finish(b)
}

/// `ip link set <if> up`. No attributes at all — `ifi_flags` carries the bit
/// and `ifi_change` masks which bits the request is allowed to alter, so this
/// touches `IFF_UP` and nothing else.
fn msg_link_up(ifindex: u32) -> Vec<u8> {
    let mut b = hdr(RTM_NEWLINK, NLM_F_REQUEST | NLM_F_ACK);
    // struct ifinfomsg
    b.push(libc::AF_UNSPEC as u8); // ifi_family
    b.push(0); // padding
    put_u16(&mut b, 0); // ifi_type
    put_u32(&mut b, ifindex); // ifi_index
    put_u32(&mut b, IFF_UP); // ifi_flags
    put_u32(&mut b, IFF_UP); // ifi_change: only IFF_UP is in scope
    finish(b)
}

/// `ip link set <if> down`: the same message with `IFF_UP` cleared in
/// `ifi_flags` and still the only bit in `ifi_change`. Captured 2026-09-30
/// (s4c-a W0, iproute2 7.2.0, in an empty network namespace).
fn msg_link_down(ifindex: u32) -> Vec<u8> {
    let mut b = hdr(RTM_NEWLINK, NLM_F_REQUEST | NLM_F_ACK);
    // struct ifinfomsg
    b.push(libc::AF_UNSPEC as u8); // ifi_family
    b.push(0); // padding
    put_u16(&mut b, 0); // ifi_type
    put_u32(&mut b, ifindex); // ifi_index
    put_u32(&mut b, 0); // ifi_flags: IFF_UP clear
    put_u32(&mut b, IFF_UP); // ifi_change: only IFF_UP is in scope
    finish(b)
}

/// `ip route add|del <dest>/<prefix> dev <if> metric <metric>`.
///
/// ADD and DEL differ in the body, not only in the message type: iproute2 sends
/// a DEL with `RTPROT_UNSPEC` / `RT_SCOPE_NOWHERE` / `RTN_UNSPEC` — wildcards
/// that widen the match rather than describing a route. Mirrored exactly.
fn msg_route(msg_type: u16, flags: u16, ifindex: u32, dest: &[u8; 4], prefix: u8, metric: u32) -> Vec<u8> {
    let del = msg_type == RTM_DELROUTE;
    let mut b = hdr(msg_type, flags);
    // struct rtmsg
    b.push(libc::AF_INET as u8); // rtm_family
    b.push(prefix); // rtm_dst_len
    b.push(0); // rtm_src_len
    b.push(0); // rtm_tos
    b.push(RT_TABLE_MAIN); // rtm_table
    b.push(if del { RTPROT_UNSPEC } else { RTPROT_BOOT }); // rtm_protocol
    b.push(if del { RT_SCOPE_NOWHERE } else { RT_SCOPE_LINK }); // rtm_scope
    b.push(if del { RTN_UNSPEC } else { RTN_UNICAST }); // rtm_type
    put_u32(&mut b, 0); // rtm_flags
    put_attr(&mut b, RTA_DST, dest);
    put_attr(&mut b, RTA_PRIORITY, &metric.to_ne_bytes());
    put_attr(&mut b, RTA_OIF, &ifindex.to_ne_bytes());
    finish(b)
}

/// ctnetlink: delete every conntrack entry whose mark is `mark` (R107), IPv4.
///
/// ONE request, and NOT the shape `conntrack -D --mark N` sends. conntrack
/// 1.4.9 dumps the table filtered by mark and then deletes each entry by its
/// full tuple (captured 2026-09-30, s4c-a W0); that needs multipart parsing,
/// which this module excludes. This is the tuple-less form: a DELETE carrying
/// only `CTA_MARK` and `CTA_MARK_MASK`, which the kernel treats as a flush
/// filtered by mark. That the kernel does so is recall, not measured; it is
/// part B's gate. What the capture does fix is the encoding: the message type
/// `NFNL_SUBSYS_CTNETLINK << 8 | msg`, the 4-byte `nfgenmsg` (family,
/// `NFNETLINK_V0`, `res_id` 0 big-endian), and both attributes as 4-byte
/// BIG-endian values with plain type numbers (no `NLA_F_NET_BYTEORDER` bit).
/// The capture's dump request carries exactly these two attributes, so this
/// message is that request with only the type and flags changed.
fn msg_ct_delete_by_mark(mark: u32) -> Vec<u8> {
    let mut b = hdr(
        (NFNL_SUBSYS_CTNETLINK << 8) | IPCTNL_MSG_CT_DELETE,
        NLM_F_REQUEST | NLM_F_ACK,
    );
    // struct nfgenmsg
    b.push(libc::AF_INET as u8); // nfgen_family
    b.push(NFNETLINK_V0); // version
    b.extend_from_slice(&0u16.to_be_bytes()); // res_id, network order
    put_attr(&mut b, CTA_MARK, &mark.to_be_bytes());
    put_attr(&mut b, CTA_MARK_MASK, &u32::MAX.to_be_bytes());
    finish(b)
}

// --- socket ---------------------------------------------------------

/// An `AF_NETLINK` / `NETLINK_ROUTE` socket with its own sequence counter.
///
/// Deliberately unbound: the kernel assigns a port id on first send, and we
/// never subscribe to multicast groups (we drive the kernel, we do not watch
/// it). Replies are validated on two axes — the source must be the kernel
/// (`nl_pid == 0`) and the sequence must be ours — so another local process
/// that guessed our port id cannot forge an ACK.
pub struct NlSocket {
    fd: RawFd,
    seq: u32,
}

impl NlSocket {
    /// `NETLINK_ROUTE`: address, route, link.
    pub fn open() -> Result<NlSocket> {
        NlSocket::open_family(libc::NETLINK_ROUTE)
    }

    /// `NETLINK_NETFILTER`: the one ctnetlink delete of REMOVE (R107). Same
    /// ACK discipline; nothing is ever dumped on it.
    pub fn open_netfilter() -> Result<NlSocket> {
        NlSocket::open_family(libc::NETLINK_NETFILTER)
    }

    fn open_family(protocol: libc::c_int) -> Result<NlSocket> {
        // SAFETY: plain socket(2) with constant arguments.
        let fd = unsafe {
            libc::socket(
                libc::AF_NETLINK,
                libc::SOCK_RAW | libc::SOCK_CLOEXEC,
                protocol,
            )
        };
        if fd < 0 {
            return Err(AgentError::Io(std::io::Error::last_os_error()));
        }
        Ok(NlSocket { fd, seq: 0 })
    }

    /// Send one request and wait for its ACK. Returns the kernel's errno as a
    /// non-negative value (0 = success), leaving the OK/ERR judgement to the
    /// caller — which errno counts as "postcondition already reached" depends
    /// on the direction, and that is ADR-025 convergence semantics, not
    /// transport.
    fn send_and_ack(&mut self, mut msg: Vec<u8>) -> Result<i32> {
        self.seq = self.seq.wrapping_add(1);
        let seq = self.seq;
        msg[8..12].copy_from_slice(&seq.to_ne_bytes());

        // SAFETY: zeroed sockaddr_nl is a valid all-zero struct; nl_pid = 0
        // and nl_groups = 0 address the kernel.
        let mut dst: libc::sockaddr_nl = unsafe { std::mem::zeroed() };
        dst.nl_family = libc::AF_NETLINK as u16;

        loop {
            // SAFETY: sending an owned buffer to a valid fd with a correctly
            // sized address.
            let n = unsafe {
                libc::sendto(
                    self.fd,
                    msg.as_ptr() as *const libc::c_void,
                    msg.len(),
                    0,
                    &dst as *const libc::sockaddr_nl as *const libc::sockaddr,
                    std::mem::size_of::<libc::sockaddr_nl>() as libc::socklen_t,
                )
            };
            if n < 0 {
                let err = std::io::Error::last_os_error();
                if err.raw_os_error() == Some(libc::EINTR) {
                    continue;
                }
                return Err(AgentError::Io(err));
            }
            if n as usize != msg.len() {
                // Netlink datagrams are all-or-nothing; a short send means
                // something is wrong enough not to guess about.
                return Err(AgentError::Rejected("netlink: short send"));
            }
            break;
        }

        self.recv_ack(seq)
    }

    fn recv_ack(&self, seq: u32) -> Result<i32> {
        let mut buf = [0u8; REPLY_BUF];
        loop {
            // SAFETY: zeroed sockaddr_nl, filled by the kernel.
            let mut src: libc::sockaddr_nl = unsafe { std::mem::zeroed() };
            let mut srclen = std::mem::size_of::<libc::sockaddr_nl>() as libc::socklen_t;

            // SAFETY: reading into an owned fixed buffer; srclen is initialised
            // to the real size of src.
            let n = unsafe {
                libc::recvfrom(
                    self.fd,
                    buf.as_mut_ptr() as *mut libc::c_void,
                    buf.len(),
                    0,
                    &mut src as *mut libc::sockaddr_nl as *mut libc::sockaddr,
                    &mut srclen,
                )
            };
            if n < 0 {
                let err = std::io::Error::last_os_error();
                if err.raw_os_error() == Some(libc::EINTR) {
                    continue;
                }
                return Err(AgentError::Io(err));
            }
            let n = n as usize;

            // Anything not from the kernel is not an answer to us.
            if src.nl_pid != 0 {
                continue;
            }

            let mut off = 0usize;
            while off + NLMSG_HDRLEN <= n {
                let len = u32::from_ne_bytes(buf[off..off + 4].try_into().unwrap()) as usize;
                let mtype = u16::from_ne_bytes(buf[off + 4..off + 6].try_into().unwrap());
                let mseq = u32::from_ne_bytes(buf[off + 8..off + 12].try_into().unwrap());

                if len < NLMSG_HDRLEN || off + len > n {
                    return Err(AgentError::Rejected("netlink: truncated reply"));
                }
                if mseq == seq && mtype == NLMSG_ERROR {
                    if len < NLMSG_HDRLEN + 4 {
                        return Err(AgentError::Rejected("netlink: short nlmsgerr"));
                    }
                    let e = i32::from_ne_bytes(
                        buf[off + NLMSG_HDRLEN..off + NLMSG_HDRLEN + 4].try_into().unwrap(),
                    );
                    // The kernel reports errno negated; 0 is a plain ACK.
                    return Ok(-e);
                }
                off += (len + 3) & !3; // NLMSG_ALIGN
            }
            // Nothing addressed to this request in this datagram: keep reading.
        }
    }
}

impl Drop for NlSocket {
    fn drop(&mut self) {
        // SAFETY: fd is owned by this struct and closed exactly once.
        unsafe { libc::close(self.fd) };
    }
}

// --- errno policy ---------------------------------------------------

/// Map a kernel errno onto ADR-025's convergence contract: OK means "the
/// postcondition holds", not "this call changed something". `tolerated` is the
/// per-direction list of errnos that already satisfy the postcondition.
fn settle(errno: i32, tolerated: &[i32], ctx: &'static str) -> Result<()> {
    if errno == 0 || tolerated.contains(&errno) {
        Ok(())
    } else {
        Err(AgentError::Io(std::io::Error::from_raw_os_error(errno)))
            .map_err(|e| match e {
                // Keep the errno for the log, but carry the operation name so
                // a NETCFG failure says which of the five steps failed.
                AgentError::Io(io) => {
                    AgentError::Io(std::io::Error::new(io.kind(), format!("{ctx}: {io}")))
                }
                other => other,
            })
    }
}

// --- public operations ----------------------------------------------

/// Bring the interface up. Idempotent in the kernel (setting `IFF_UP` on an
/// already-up link returns 0). `ENODEV` is NOT tolerated: a missing device is
/// exactly the retryable ERR ADR-025 describes, and hiding it would let the
/// launch daemon believe a link exists that does not.
pub fn link_up(sock: &mut NlSocket, ifindex: u32) -> Result<()> {
    let e = sock.send_and_ack(msg_link_up(ifindex))?;
    settle(e, &[], "link up")
}

/// Take the interface down (REMOVE, ADR-035 §6: FREE is DOWN; R102, R106).
/// Clearing `IFF_UP` on a down link returns 0; `ENODEV` is tolerated here,
/// because a device that is gone is down, and REMOVE converges on absence.
pub fn link_down(sock: &mut NlSocket, ifindex: u32) -> Result<()> {
    let e = sock.send_and_ack(msg_link_down(ifindex))?;
    settle(e, &[libc::ENODEV], "link down")
}

/// Flush the conntrack entries of one slot, by its mark (R107, R116). No errno
/// is tolerated: a filtered flush that matches nothing succeeds (recall; B
/// reads it), and a missing ctnetlink subsystem must be an ERR that keeps the
/// record, not a silent success (R115 loads the module at boot for that
/// reason).
pub fn ct_flush_mark(sock: &mut NlSocket, mark: u32) -> Result<()> {
    let e = sock.send_and_ack(msg_ct_delete_by_mark(mark))?;
    settle(e, &[], "conntrack flush by mark")
}

/// Install the p2p address. `EEXIST` means an identical address is already
/// present — the postcondition, reached by an earlier pass (ADR-025: identical
/// ADD is OK and the mechanism is still re-driven).
pub fn addr_add(sock: &mut NlSocket, ifindex: u32, local: &[u8; 4], peer: &[u8; 4], prefix: u8) -> Result<()> {
    let msg = msg_addr(
        RTM_NEWADDR,
        NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL,
        ifindex,
        local,
        peer,
        prefix,
    );
    let e = sock.send_and_ack(msg)?;
    settle(e, &[libc::EEXIST], "addr add")
}

/// Withdraw the p2p address. Absence is the postcondition, so the "not there"
/// errnos are success. Note that this also removes the kernel's own
/// `proto kernel` route to the peer, which the address installed implicitly.
pub fn addr_del(sock: &mut NlSocket, ifindex: u32, local: &[u8; 4], peer: &[u8; 4], prefix: u8) -> Result<()> {
    let msg = msg_addr(
        RTM_DELADDR,
        NLM_F_REQUEST | NLM_F_ACK,
        ifindex,
        local,
        peer,
        prefix,
    );
    let e = sock.send_and_ack(msg)?;
    settle(e, &[libc::EADDRNOTAVAIL, libc::ENOENT, libc::ENODEV], "addr del")
}

/// Install one route from the payload's bounded route array.
pub fn route_add(sock: &mut NlSocket, ifindex: u32, dest: &[u8; 4], prefix: u8, metric: u32) -> Result<()> {
    let msg = msg_route(
        RTM_NEWROUTE,
        NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL,
        ifindex,
        dest,
        prefix,
        metric,
    );
    let e = sock.send_and_ack(msg)?;
    settle(e, &[libc::EEXIST], "route add")
}

/// Withdraw one route. The kernel answers `ESRCH` for a route it cannot find.
pub fn route_del(sock: &mut NlSocket, ifindex: u32, dest: &[u8; 4], prefix: u8, metric: u32) -> Result<()> {
    let msg = msg_route(
        RTM_DELROUTE,
        NLM_F_REQUEST | NLM_F_ACK,
        ifindex,
        dest,
        prefix,
        metric,
    );
    let e = sock.send_and_ack(msg)?;
    settle(e, &[libc::ESRCH, libc::ENOENT, libc::ENODEV], "route del")
}

// --- interface resolution (no netlink) ------------------------------

/// Resolve `match_mac` to an ifindex through read-only sysfs.
///
/// This is what keeps the module small: the only genuinely hard part of
/// netlink is parsing a multipart `RTM_GETLINK` dump, and sysfs answers the
/// same question with `read_dir` + two file reads, no privilege and no parser.
/// The resolution is inherently a snapshot — if the device disappears between
/// here and the first message the kernel answers `ENODEV`, which ADR-025
/// already classifies as a retryable ERR. That is the whole TOCTOU story.
///
/// It COUNTS (ADR-035 §7, R104). Two interfaces carrying the requested MAC is
/// not resolved by directory order: G3 measured a first-match lookup program a
/// dummy carrying a slot's MAC while the slot itself stayed down. The three
/// outcomes are distinct values, not one error, because the caller treats them
/// differently: none on a REMOVE is a vanished device and converges; more than
/// one is refused in both directions.
///
/// A MAC that matches nothing is not an error of the payload (ADR-025: device
/// presence is not payload validity); it is a failed operation on ADD.
#[derive(Debug, PartialEq, Eq)]
pub enum MacMatch {
    /// Exactly one interface carries the MAC.
    One(u32),
    /// No interface carries it.
    None,
    /// This many interfaces (two or more) carry it.
    Many(usize),
}

pub fn ifindex_by_mac(mac: &[u8; 6]) -> Result<MacMatch> {
    ifindex_by_mac_in("/sys/class/net", mac)
}

/// The lookup over any directory laid out like `/sys/class/net`, so the count
/// is testable against a temporary tree without a second interface.
fn ifindex_by_mac_in(root: &str, mac: &[u8; 6]) -> Result<MacMatch> {
    let want = format!(
        "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
    );

    let mut found: Option<u32> = None;
    let mut count = 0usize;
    let dir = fs::read_dir(root).map_err(AgentError::Io)?;
    for entry in dir {
        let path = match entry {
            Ok(e) => e.path(),
            Err(_) => continue,
        };
        // Interfaces without a readable address (or that vanish mid-scan) are
        // simply not the one we are looking for.
        let addr = match fs::read_to_string(path.join("address")) {
            Ok(s) => s,
            Err(_) => continue,
        };
        if !addr.trim().eq_ignore_ascii_case(&want) {
            continue;
        }
        let idx = match fs::read_to_string(path.join("ifindex")) {
            Ok(s) => s,
            Err(_) => continue,
        };
        if let Ok(n) = idx.trim().parse::<u32>() {
            count += 1;
            found = Some(n);
        }
    }
    Ok(match (count, found) {
        (1, Some(n)) => MacMatch::One(n),
        (0, _) => MacMatch::None,
        (n, _) => MacMatch::Many(n),
    })
}

// --- golden fixture tests -------------------------------------------
//
// Captured 2026-07-23 with:
//   strace -x -s 1024 -e trace=sendmsg,sendto ip <cmd> ...
// on a dummy interface, local 10.100.1.1, peer 10.100.1.2/32, metric 100.
// The expected buffers below are the decoded capture re-encoded by hand; the
// total lengths (40 / 32 / 52) are exactly what iproute2 sent, so a wrong
// struct layout cannot pass. Builders emit seq 0; send_and_ack patches it.

#[cfg(test)]
mod tests {
    use super::*;

    const IFINDEX: u32 = 11;
    const LOCAL: [u8; 4] = [10, 100, 1, 1];
    const PEER: [u8; 4] = [10, 100, 1, 2];

    #[test]
    fn fixture_01_addr_add() {
        let got = msg_addr(
            RTM_NEWADDR,
            NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL,
            IFINDEX,
            &LOCAL,
            &PEER,
            32,
        );
        #[rustfmt::skip]
        let want: [u8; 40] = [
            0x28, 0x00, 0x00, 0x00,             // nlmsg_len = 40
            0x14, 0x00,                         // RTM_NEWADDR
            0x05, 0x06,                         // REQUEST|ACK|EXCL|CREATE
            0x00, 0x00, 0x00, 0x00,             // seq
            0x00, 0x00, 0x00, 0x00,             // pid
            0x02, 0x20, 0x00, 0x00,             // AF_INET, /32, flags 0, UNIVERSE
            0x0b, 0x00, 0x00, 0x00,             // ifa_index
            0x08, 0x00, 0x02, 0x00,             // IFA_LOCAL
            0x0a, 0x64, 0x01, 0x01,             // 10.100.1.1
            0x08, 0x00, 0x01, 0x00,             // IFA_ADDRESS
            0x0a, 0x64, 0x01, 0x02,             // 10.100.1.2 (the PEER)
        ];
        assert_eq!(got, want);
    }

    #[test]
    fn fixture_02_link_up() {
        let got = msg_link_up(IFINDEX);
        #[rustfmt::skip]
        let want: [u8; 32] = [
            0x20, 0x00, 0x00, 0x00,             // nlmsg_len = 32
            0x10, 0x00,                         // RTM_NEWLINK
            0x05, 0x00,                         // REQUEST|ACK
            0x00, 0x00, 0x00, 0x00,             // seq
            0x00, 0x00, 0x00, 0x00,             // pid
            0x00, 0x00, 0x00, 0x00,             // AF_UNSPEC, pad, ifi_type
            0x0b, 0x00, 0x00, 0x00,             // ifi_index
            0x01, 0x00, 0x00, 0x00,             // ifi_flags = IFF_UP
            0x01, 0x00, 0x00, 0x00,             // ifi_change = IFF_UP
        ];
        assert_eq!(got, want);
    }

    /// Captured 2026-09-30 (s4c-a W0): `strace -f -e trace=sendmsg,sendto -xx
    /// -s 256 ip link set dev lo down` under `unshare -n`, iproute2 7.2.0:
    /// `{nlmsg_len=32, nlmsg_type=RTM_NEWLINK, nlmsg_flags=NLM_F_REQUEST|
    /// NLM_F_ACK, …}, {ifi_family=AF_UNSPEC, ifi_type=ARPHRD_NETROM (0),
    /// ifi_index=if_nametoindex("lo"), ifi_flags=0, ifi_change=0x1}`. strace
    /// prints the index by name; `lo` is ifindex 1 in a fresh namespace.
    #[test]
    fn fixture_06_link_down() {
        let got = msg_link_down(1);
        #[rustfmt::skip]
        let want: [u8; 32] = [
            0x20, 0x00, 0x00, 0x00,             // nlmsg_len = 32
            0x10, 0x00,                         // RTM_NEWLINK
            0x05, 0x00,                         // REQUEST|ACK
            0x00, 0x00, 0x00, 0x00,             // seq
            0x00, 0x00, 0x00, 0x00,             // pid
            0x00, 0x00, 0x00, 0x00,             // AF_UNSPEC, pad, ifi_type
            0x01, 0x00, 0x00, 0x00,             // ifi_index (lo)
            0x00, 0x00, 0x00, 0x00,             // ifi_flags = 0 (IFF_UP clear)
            0x01, 0x00, 0x00, 0x00,             // ifi_change = IFF_UP
        ];
        assert_eq!(got, want);
    }

    /// R107's DELETE, spec bytes (ruling 4 of 2026-09-30: conntrack(8) sent no
    /// tuple-less DELETE to capture, so the test pins the spec).
    fn ct_delete_spec(mark: u8) -> [u8; 36] {
        #[rustfmt::skip]
        let want: [u8; 36] = [
            0x24, 0x00, 0x00, 0x00,             // nlmsg_len = 36
            0x02, 0x01,                         // CTNETLINK << 8 | CT_DELETE
            0x05, 0x00,                         // REQUEST|ACK
            0x00, 0x00, 0x00, 0x00,             // seq
            0x00, 0x00, 0x00, 0x00,             // pid
            0x02, 0x00, 0x00, 0x00,             // AF_INET, V0, res_id 0 (BE)
            0x08, 0x00, 0x08, 0x00,             // CTA_MARK
            0x00, 0x00, 0x00, mark,             // mark, big-endian
            0x08, 0x00, 0x15, 0x00,             // CTA_MARK_MASK
            0xff, 0xff, 0xff, 0xff,             // mask
        ];
        want
    }

    /// The dump request conntrack 1.4.9 sent for `-D -f ipv4 --mark N`,
    /// captured 2026-09-30 (s4c-a W0, strace -xx), seq and pid zeroed:
    /// `{nlmsg_len=36, nlmsg_type=NFNL_SUBSYS_CTNETLINK<<8|IPCTNL_MSG_CT_GET,
    /// nlmsg_flags=NLM_F_REQUEST|NLM_F_DUMP}, {nfgen_family=AF_INET,
    /// version=NFNETLINK_V0, res_id=htons(0)}, [{nla_len=8, nla_type=0x8},
    /// "\x00\x00\x00\x01"], [{nla_len=8, nla_type=0x15}, "\xff\xff\xff\xff"]`
    /// (and `\x00\x00\x00\x10` for mark 16).
    fn ct_get_captured(mark: u8) -> [u8; 36] {
        #[rustfmt::skip]
        let got: [u8; 36] = [
            0x24, 0x00, 0x00, 0x00,
            0x01, 0x01,                         // CTNETLINK << 8 | CT_GET
            0x01, 0x03,                         // REQUEST|DUMP
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x00,
            0x08, 0x00, 0x08, 0x00,
            0x00, 0x00, 0x00, mark,
            0x08, 0x00, 0x15, 0x00,
            0xff, 0xff, 0xff, 0xff,
        ];
        got
    }

    #[test]
    fn fixture_07_ct_delete_by_mark() {
        for mark in [1u8, 16] {
            let got = msg_ct_delete_by_mark(mark as u32);
            assert_eq!(got, ct_delete_spec(mark), "mark {mark}");

            // Against the capture: identical but for the message type and
            // the flags (bytes 4..8) — same length, same nfgenmsg, same two
            // attributes in the same encoding.
            let cap = ct_get_captured(mark);
            assert_eq!(got.len(), cap.len());
            assert_eq!(got[0..4], cap[0..4], "nlmsg_len, mark {mark}");
            assert_eq!(got[8..], cap[8..], "nfgenmsg and attributes, mark {mark}");
        }
    }

    #[test]
    fn fixture_03_route_add() {
        let got = msg_route(
            RTM_NEWROUTE,
            NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL,
            IFINDEX,
            &PEER,
            32,
            100,
        );
        #[rustfmt::skip]
        let want: [u8; 52] = [
            0x34, 0x00, 0x00, 0x00,             // nlmsg_len = 52
            0x18, 0x00,                         // RTM_NEWROUTE
            0x05, 0x06,                         // REQUEST|ACK|EXCL|CREATE
            0x00, 0x00, 0x00, 0x00,             // seq
            0x00, 0x00, 0x00, 0x00,             // pid
            0x02, 0x20, 0x00, 0x00,             // AF_INET, dst_len 32, src 0, tos 0
            0xfe, 0x03, 0xfd, 0x01,             // MAIN, RTPROT_BOOT, SCOPE_LINK, UNICAST
            0x00, 0x00, 0x00, 0x00,             // rtm_flags
            0x08, 0x00, 0x01, 0x00,             // RTA_DST
            0x0a, 0x64, 0x01, 0x02,             // 10.100.1.2
            0x08, 0x00, 0x06, 0x00,             // RTA_PRIORITY
            0x64, 0x00, 0x00, 0x00,             // metric 100
            0x08, 0x00, 0x04, 0x00,             // RTA_OIF
            0x0b, 0x00, 0x00, 0x00,             // ifindex
        ];
        assert_eq!(got, want);
    }

    #[test]
    fn fixture_04_route_del() {
        let got = msg_route(
            RTM_DELROUTE,
            NLM_F_REQUEST | NLM_F_ACK,
            IFINDEX,
            &PEER,
            32,
            100,
        );
        #[rustfmt::skip]
        let want: [u8; 52] = [
            0x34, 0x00, 0x00, 0x00,
            0x19, 0x00,                         // RTM_DELROUTE
            0x05, 0x00,                         // REQUEST|ACK
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x02, 0x20, 0x00, 0x00,
            0xfe, 0x00, 0xff, 0x00,             // MAIN, PROTO_UNSPEC, NOWHERE, RTN_UNSPEC
            0x00, 0x00, 0x00, 0x00,
            0x08, 0x00, 0x01, 0x00,
            0x0a, 0x64, 0x01, 0x02,
            0x08, 0x00, 0x06, 0x00,
            0x64, 0x00, 0x00, 0x00,
            0x08, 0x00, 0x04, 0x00,
            0x0b, 0x00, 0x00, 0x00,
        ];
        assert_eq!(got, want);
    }

    #[test]
    fn fixture_05_addr_del() {
        let got = msg_addr(RTM_DELADDR, NLM_F_REQUEST | NLM_F_ACK, IFINDEX, &LOCAL, &PEER, 32);
        #[rustfmt::skip]
        let want: [u8; 40] = [
            0x28, 0x00, 0x00, 0x00,
            0x15, 0x00,                         // RTM_DELADDR
            0x05, 0x00,                         // REQUEST|ACK
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x02, 0x20, 0x00, 0x00,
            0x0b, 0x00, 0x00, 0x00,
            0x08, 0x00, 0x02, 0x00,
            0x0a, 0x64, 0x01, 0x01,
            0x08, 0x00, 0x01, 0x00,
            0x0a, 0x64, 0x01, 0x02,
        ];
        assert_eq!(got, want);
    }

    /// The peer address is what carries reachability; the payload's route is
    /// additive. Pinning the distinguishing field here so a later refactor that
    /// drops RTA_PRIORITY cannot silently make our route indistinguishable from
    /// the kernel's own (which would also make the live gate untestable).
    #[test]
    fn route_carries_its_metric() {
        let m = msg_route(RTM_NEWROUTE, NLM_F_REQUEST, IFINDEX, &PEER, 32, 0xdead_beef);
        assert!(m.windows(4).any(|w| w == 0xdead_beefu32.to_ne_bytes()));
    }

    /// Loopback is present in every namespace we run in and has a MAC of all
    /// zeroes — a cheap end-to-end check of the sysfs resolution path that
    /// needs no privilege and no fixture.
    #[test]
    fn ifindex_by_mac_finds_loopback() {
        assert_eq!(
            ifindex_by_mac(&[0, 0, 0, 0, 0, 0]).unwrap(),
            MacMatch::One(1)
        );
    }

    /// A temporary tree shaped like /sys/class/net: one directory per
    /// interface with `address` and `ifindex`. Removed on drop.
    struct FakeSysNet(std::path::PathBuf);

    impl FakeSysNet {
        fn new(tag: &str, ifaces: &[(&str, &str, u32)]) -> FakeSysNet {
            let root =
                std::env::temp_dir().join(format!("netvm-agent-test-{}-{tag}", std::process::id()));
            let _ = fs::remove_dir_all(&root);
            for (name, addr, idx) in ifaces {
                let d = root.join(name);
                fs::create_dir_all(&d).unwrap();
                fs::write(d.join("address"), format!("{addr}\n")).unwrap();
                fs::write(d.join("ifindex"), format!("{idx}\n")).unwrap();
            }
            fs::create_dir_all(&root).unwrap();
            FakeSysNet(root)
        }
        fn lookup(&self, mac: &[u8; 6]) -> MacMatch {
            ifindex_by_mac_in(self.0.to_str().unwrap(), mac).unwrap()
        }
    }

    impl Drop for FakeSysNet {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    const SLOT3: [u8; 6] = [0x52, 0x54, 0x01, 0x00, 0x00, 0x03];

    /// ADR-035 §7 / G3's shape: a second interface carrying a slot's MAC is
    /// counted, not tie-broken by directory order.
    #[test]
    fn ifindex_by_mac_counts() {
        let one = FakeSysNet::new(
            "one",
            &[
                ("lo", "00:00:00:00:00:00", 1),
                ("km03", "52:54:01:00:00:03", 7),
            ],
        );
        assert_eq!(one.lookup(&SLOT3), MacMatch::One(7));

        let none = FakeSysNet::new("none", &[("lo", "00:00:00:00:00:00", 1)]);
        assert_eq!(none.lookup(&SLOT3), MacMatch::None);

        let dup = FakeSysNet::new(
            "dup",
            &[
                ("km03", "52:54:01:00:00:03", 7),
                ("g3dup", "52:54:01:00:00:03", 30),
            ],
        );
        assert_eq!(dup.lookup(&SLOT3), MacMatch::Many(2));
    }
}
