/*
 * katmate-init.c  --  minimal PID 1 init for the Katmate app_web MicroVM appliance.
 *
 * Target: QEMU microvm machine type, no ACPI, custom monolithic kernel,
 *         no initrd (-kernel direct boot), Debian trixie rootfs.
 *
 * Responsibilities (and nothing more):
 *   1. Mount the pseudo-filesystems and the persistent /home rw LV.
 *   2. Set up XDG_RUNTIME_DIR for user 1000.
 *   3. Set the hostname from km.name= (R125), before the network, routed and
 *      offline alike; absent leaves the kernel's "(none)". Then configure the
 *      network from the typed km.* kernel parameters (ADR-038):
 *      lo up on every boot; with km.ip/km.gw/km.dns, the one device-backed
 *      link up, km.ip/32 on it, an on-link default route via km.gw, and
 *      /run/resolv.conf naming km.dns. Without km.*, offline: lo only. Any
 *      error exits the VM through the shutdown path; vm-agent never starts.
 *   4. Open a privileged-side control socket for shutdown requests.
 *   5. Launch vm-agent dropped to user 1000 (the agent does all app/waypipe/dbus work).
 *   6. Reap orphans (the inescapable PID 1 duty).
 *   7. On shutdown request (or agent death): kill children, unmount /home cleanly,
 *      sync, then reboot(RB_AUTOBOOT) -> triple-fault -> QEMU(-no-reboot) exits.
 *
 * Privilege model: this process is the ONLY root code in the guest. All protocol
 * parsing and application launching lives in vm-agent under uid 1000. The
 * network step (3) runs as this root PID 1 before vm-agent exists.
 *
 * Build (static, in trixie chroot):
 *   gcc -static -O2 -Wall -Wextra -std=gnu11 -o init katmate-init.c
 * (Alternatively musl-gcc for a cleaner static link. We deliberately make NO
 *  NSS calls -- getpwnam/initgroups/etc -- so static glibc is safe here.)
 * With -DKATMATE_INIT_NO_MAIN, main() is left out so init/tests/ can include
 * this file and drive the network functions against fixtures. The image build
 * never defines it.
 *
 * Bake to /sbin/init (kernel default search path; no init= cmdline needed).
 *
 * Host-side requirements (NOT handled here -- go into the launch / .con):
 *   - QEMU:           -no-reboot
 *   - kernel cmdline: reboot=t        (skip the ~5s "try other methods first" delay)
 *   - kernel cmdline, routed AppVM (ADR-038 §10):
 *                     km.ip=<addr> km.gw=10.100.1.1 km.dns=10.100.1.1 ipv6.disable=1
 *                     (all three km.* or none; none = offline)
 *   - kernel cmdline, any AppVM (R125): km.name=<instance>, 1-63 bytes of
 *                     [A-Za-z0-9_-]; optional
 *   - -drive order:   vda = qcow2 root delta, vdb = raw /home LV
 *   - image:          /etc/resolv.conf is the relative symlink ../run/resolv.conf
 *                     (ADR-038 §7; the layer builds put it there)
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <time.h>
#include <grp.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/signalfd.h>
#include <dirent.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>

/* ---- compile-time configuration ------------------------------------------ */

#define UID_USER       1000
#define GID_USER       1000

#define HOME_DEV       "/dev/vdb"          /* raw LV, second virtio-blk (vda=root) */
#define HOME_DIR       "/home"
#define HOME_FSTYPE    "ext4"

#define USER_HOME      "/home/user"
#define XDG_RUNTIME    "/run/user/1000"

#define VM_AGENT_PATH  "/usr/local/bin/vm-agent"   /* confirmed baked path         */

/* Only used when compiled with -DUSE_DBUS_SESSION (see spawn_agent). */
#define DBUS_RUN_SESSION_PATH "/usr/bin/dbus-run-session"

#define INIT_SOCK      "/run/katmate-init.sock"
#define SHUTDOWN_CMD   "SHUTDOWN"

#define GRACE_MS       5000                /* SIGTERM -> SIGKILL window            */

/* Network step inputs (ADR-038). Passed to km_net_step() as parameters so the
 * tests can substitute fixtures; these are the production values. */
#define KM_CMDLINE_PATH "/proc/cmdline"
#define KM_SYSFS_NET    "/sys/class/net"
#define KM_RESOLV_PATH  "/run/resolv.conf"  /* /etc/resolv.conf -> ../run/resolv.conf */

/* ---- diagnostics ---------------------------------------------------------- */

static void logmsg(const char *fmt, ...)
{
	va_list ap;
	fputs("[katmate-init] ", stderr);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
	fflush(stderr);
}

/* Fatal during boot: keep the error visible on the console forever.
 * PID 1 must never exit (that would panic the kernel). During bring-up we
 * pause rather than reboot so the failure stays on screen. */
static void fatal(const char *what)
{
	logmsg("FATAL: %s: %s", what, strerror(errno));
	logmsg("halting (PID 1 must not exit) -- inspect console");
	for (;;)
		pause();
}

/* ---- boot: filesystem setup ---------------------------------------------- */

static void mkdir_q(const char *path, mode_t mode)
{
	if (mkdir(path, mode) != 0 && errno != EEXIST)
		logmsg("warn: mkdir %s: %s", path, strerror(errno));
}

static void mount_q(const char *src, const char *tgt, const char *type,
                    unsigned long flags, const char *data, int fatal_on_fail)
{
	if (mount(src, tgt, type, flags, data) != 0) {
		if (errno == EBUSY) /* e.g. devtmpfs already auto-mounted by kernel */
			return;
		if (fatal_on_fail)
			fatal(tgt);
		logmsg("warn: mount %s on %s: %s", type, tgt, strerror(errno));
	}
}

static void setup_filesystems(void)
{
	/* pseudo-fs */
	mount_q("proc",     "/proc",    "proc",     0, NULL, 1);
	mount_q("sysfs",    "/sys",     "sysfs",    0, NULL, 1);
	mount_q("devtmpfs", "/dev",     "devtmpfs", 0, NULL, 0); /* tolerate auto-mount */

	/* mountpoints under /dev may not exist on a fresh devtmpfs */
	mkdir_q("/dev/pts", 0755);
	mkdir_q("/dev/shm", 1777);
	mount_q("devpts",   "/dev/pts", "devpts",   0, "gid=5,mode=620", 1);
	mount_q("shm",      "/dev/shm", "tmpfs",    MS_NOSUID | MS_NODEV, "mode=1777", 1);

	mount_q("run",      "/run",     "tmpfs",    MS_NOSUID | MS_NODEV, "mode=0755", 1);
	mount_q("tmp",      "/tmp",     "tmpfs",    MS_NOSUID | MS_NODEV, NULL, 0);

	/* persistent per-VM storage: the rw LV mounted as /home.
	 * This is architectural, not dev-convenience -- it MUST mount, and MUST
	 * be unmounted cleanly at shutdown (see do_shutdown). */
	mount_q(HOME_DEV,   HOME_DIR,   HOME_FSTYPE, MS_NOSUID | MS_NODEV, NULL, 1);

	/* XDG_RUNTIME_DIR for user 1000 (plain dir on the /run tmpfs is sufficient) */
	mkdir_q("/run/user", 0755);
	if (mkdir(XDG_RUNTIME, 0700) != 0 && errno != EEXIST)
		fatal("mkdir " XDG_RUNTIME);
	if (chown(XDG_RUNTIME, UID_USER, GID_USER) != 0)
		fatal("chown " XDG_RUNTIME);
}

/* Reopen the console on 0/1/2 so our logging reliably reaches ttyS0. */
static void reopen_console(void)
{
	int fd = open("/dev/console", O_RDWR | O_NOCTTY);
	if (fd < 0)
		return; /* not fatal: kernel usually already wired 0/1/2 to console */
	dup2(fd, 0);
	dup2(fd, 1);
	dup2(fd, 2);
	if (fd > 2)
		close(fd);
}

/* ---- network (ADR-038) ---------------------------------------------------- */
/*
 * The guest's address, default route and resolver come from three typed
 * kernel parameters, km.ip= km.gw= km.dns=. They are dotted, so the kernel
 * withholds them from PID 1's argv and environment; they are read from
 * /proc/cmdline. Parsing is syntactic only (ADR-038 §3): the image does not
 * know the pool layout, and the host's generator is where the address is
 * derived and checked.
 *
 * Every function here takes its inputs as parameters and reports failure as
 * -1 with a message in err[] -- never through fatal(), and never by exiting.
 * main() turns a failure into the shutdown exit (ADR-038 §9, R87).
 */

#define KM_ERR_MAX      256
#define KM_VALUE_MAX    15                  /* strlen("255.255.255.255") (R86) */
#define KM_CMDLINE_MAX  4096

enum { KM_NET_OFFLINE = 0, KM_NET_ROUTED = 1 };

struct km_net {
	int            state;               /* KM_NET_OFFLINE or KM_NET_ROUTED */
	struct in_addr ip, gw, dns;         /* valid when routed */
};

struct km_nic {
	int  ifindex;
	char name[IFNAMSIZ];
};

/* Read a whole small file (/proc/cmdline) into buf, NUL-terminated. */
static int km_read_text(const char *path, char *buf, size_t size,
                        char *err, size_t errlen)
{
	size_t len = 0;
	ssize_t n;
	int fd = open(path, O_RDONLY | O_CLOEXEC);

	if (fd < 0) {
		snprintf(err, errlen, "cannot read %s: %s", path, strerror(errno));
		return -1;
	}
	for (;;) {
		if (len == size - 1) {
			close(fd);
			snprintf(err, errlen, "%s is longer than %zu bytes", path, size - 1);
			return -1;
		}
		n = read(fd, buf + len, size - 1 - len);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			snprintf(err, errlen, "cannot read %s: %s", path, strerror(errno));
			close(fd);
			return -1;
		}
		if (n == 0)
			break;
		len += (size_t)n;
	}
	close(fd);
	buf[len] = '\0';
	return 0;
}

/*
 * Parse the command line text (R86). Every whitespace-separated token is
 * considered, including any after "--". A token beginning "km." must be
 * km.<key>=<value> with <key> one of ip, gw, dns, each at most once, and
 * <value> at most 15 characters and accepted by inet_pton(AF_INET). The set
 * is all three (routed) or none (offline); one or two is an error (§3).
 * km.name= is also a known key (R125); it is km_name_parse()'s, and is
 * skipped here.
 */
static int km_net_parse(const char *cmdline, struct km_net *net,
                        char *err, size_t errlen)
{
	static const char *const keys[3] = { "ip", "gw", "dns" };
	struct in_addr *dst[3];
	int seen[3] = { 0, 0, 0 };
	const char *p = cmdline;
	int i, nseen;

	memset(net, 0, sizeof *net);
	dst[0] = &net->ip;
	dst[1] = &net->gw;
	dst[2] = &net->dns;

	for (;;) {
		const char *tok, *eq;
		size_t len, keylen, vlen;
		char value[KM_VALUE_MAX + 1];
		int which = -1;

		while (*p == ' ' || *p == '\t' || *p == '\n')
			p++;
		if (*p == '\0')
			break;
		tok = p;
		while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\n')
			p++;
		len = (size_t)(p - tok);

		if (len < 3 || strncmp(tok, "km.", 3) != 0)
			continue;                   /* not ours: ignored */

		eq = memchr(tok, '=', len);
		if (eq == NULL) {
			snprintf(err, errlen, "malformed km.* token (no '='): '%.*s'",
			         (int)len, tok);
			return -1;
		}
		keylen = (size_t)(eq - (tok + 3));
		if (keylen == 4 && strncmp(tok + 3, "name", 4) == 0)
			continue;                   /* km_name_parse()'s (R125) */
		for (i = 0; i < 3; i++) {
			if (keylen == strlen(keys[i]) &&
			    strncmp(tok + 3, keys[i], keylen) == 0) {
				which = i;
				break;
			}
		}
		if (which < 0) {
			snprintf(err, errlen, "unknown km.* key: '%.*s'", (int)len, tok);
			return -1;
		}
		if (seen[which]) {
			snprintf(err, errlen, "duplicate km.%s: '%.*s'", keys[which],
			         (int)len, tok);
			return -1;
		}
		vlen = len - (size_t)(eq + 1 - tok);
		if (vlen > KM_VALUE_MAX) {
			snprintf(err, errlen,
			         "km.%s value longer than %d characters: '%.*s'",
			         keys[which], KM_VALUE_MAX, (int)len, tok);
			return -1;
		}
		memcpy(value, eq + 1, vlen);
		value[vlen] = '\0';
		if (inet_pton(AF_INET, value, dst[which]) != 1) {
			snprintf(err, errlen,
			         "km.%s value is not an IPv4 dotted quad: '%.*s'",
			         keys[which], (int)len, tok);
			return -1;
		}
		seen[which] = 1;
	}

	nseen = seen[0] + seen[1] + seen[2];
	if (nseen == 0) {
		net->state = KM_NET_OFFLINE;
		return 0;
	}
	if (nseen != 3) {
		snprintf(err, errlen,
		         "partial km.* set (all three or none): km.ip %s, km.gw %s, km.dns %s",
		         seen[0] ? "given" : "MISSING", seen[1] ? "given" : "MISSING",
		         seen[2] ? "given" : "MISSING");
		return -1;
	}
	net->state = KM_NET_ROUTED;
	return 0;
}

/* ---- hostname (R125) ------------------------------------------------------ */
/*
 * km.name=<instance> names the guest: the host passes its systemd instance
 * name (%i), and init sets it with sethostname(2) on every boot, routed and
 * offline alike, independent of km.ip. Validated in ADR-038's style: at most
 * once, 1-63 bytes of [A-Za-z0-9_-]; anything else is an error and exits the
 * VM like a malformed km.* (ADR-038 §9). Absent is not an error: the hostname
 * is left as the kernel's "(none)".
 */

#define KM_NAME_MAX 63

/* Find and check km.name= in the command line text. *present is 1 and name[]
 * holds the value when it was given, 0 when it was absent. */
static int km_name_parse(const char *cmdline, char name[KM_NAME_MAX + 1],
                         int *present, char *err, size_t errlen)
{
	static const char key[] = "km.name=";
	const size_t klen = sizeof key - 1;
	const char *p = cmdline;
	size_t i;

	*present = 0;
	name[0] = '\0';
	for (;;) {
		const char *tok, *val;
		size_t len, vlen;

		while (*p == ' ' || *p == '\t' || *p == '\n')
			p++;
		if (*p == '\0')
			break;
		tok = p;
		while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\n')
			p++;
		len = (size_t)(p - tok);

		if (len < klen || strncmp(tok, key, klen) != 0)
			continue;                   /* not km.name=: ignored here */

		if (*present) {
			snprintf(err, errlen, "duplicate km.name: '%.*s'", (int)len, tok);
			return -1;
		}
		val = tok + klen;
		vlen = len - klen;
		if (vlen == 0 || vlen > KM_NAME_MAX) {
			snprintf(err, errlen,
			         "km.name value is not 1-%d bytes: '%.*s'",
			         KM_NAME_MAX, (int)(len > 80 ? 80 : len), tok);
			return -1;
		}
		for (i = 0; i < vlen; i++) {
			unsigned char c = (unsigned char)val[i];
			if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
			      (c >= '0' && c <= '9') || c == '_' || c == '-')) {
				snprintf(err, errlen,
				         "km.name value is not [A-Za-z0-9_-]: '%.*s'",
				         (int)len, tok);
				return -1;
			}
		}
		memcpy(name, val, vlen);
		name[vlen] = '\0';
		*present = 1;
	}
	return 0;
}

/* The whole step: read, parse, sethostname, and one log line. */
static int km_name_step(const char *cmdline_path, char *err, size_t errlen)
{
	char cmdline[KM_CMDLINE_MAX];
	char name[KM_NAME_MAX + 1];
	int present;

	if (km_read_text(cmdline_path, cmdline, sizeof cmdline, err, errlen) != 0)
		return -1;
	if (km_name_parse(cmdline, name, &present, err, errlen) != 0)
		return -1;
	if (!present) {
		logmsg("hostname: not set (no km.name)");
		return 0;
	}
	if (sethostname(name, strlen(name)) != 0) {
		snprintf(err, errlen, "sethostname(\"%s\"): %s", name, strerror(errno));
		return -1;
	}
	logmsg("hostname: %s", name);
	return 0;
}

/*
 * Select the NIC (R85): the one entry of <netdir> that has a "device" link,
 * i.e. is backed by a device. lo and virtual links (sit0 from a built-in
 * CONFIG_IPV6_SIT, dummy, tunnels, bonds) have none, are not counted and are
 * left alone. Zero or more than one device-backed link is an error. The
 * ifindex is read from <netdir>/<if>/ifindex.
 */
static int km_net_select(const char *netdir, struct km_nic *nic,
                         char *err, size_t errlen)
{
	DIR *d;
	struct dirent *de;
	char path[KM_ERR_MAX - 64];         /* bounded so err[] can quote it */
	char found[KM_ERR_MAX / 2];
	char text[32];
	struct stat st;
	size_t flen = 0;
	int count = 0;
	char *end;
	long idx;

	memset(nic, 0, sizeof *nic);
	found[0] = '\0';

	d = opendir(netdir);
	if (d == NULL) {
		snprintf(err, errlen, "cannot open %s: %s", netdir, strerror(errno));
		return -1;
	}
	while ((errno = 0, de = readdir(d)) != NULL) {
		if (de->d_name[0] == '.')
			continue;
		if ((size_t)snprintf(path, sizeof path, "%s/%s/device", netdir,
		                     de->d_name) >= sizeof path) {
			snprintf(err, errlen, "path too long under %s", netdir);
			closedir(d);
			return -1;
		}
		if (stat(path, &st) != 0) {
			if (errno == ENOENT || errno == ENOTDIR)
				continue;           /* not device-backed: not counted */
			snprintf(err, errlen, "cannot stat %s: %s", path, strerror(errno));
			closedir(d);
			return -1;
		}
		count++;
		if (count == 1) {
			if (strlen(de->d_name) >= sizeof nic->name) {
				snprintf(err, errlen, "link name too long: '%s'", de->d_name);
				closedir(d);
				return -1;
			}
			strcpy(nic->name, de->d_name);
		}
		if (flen < sizeof found)
			flen += (size_t)snprintf(found + flen, sizeof found - flen,
			                         "%s%s", count > 1 ? " " : "", de->d_name);
	}
	if (errno != 0) {
		snprintf(err, errlen, "cannot read %s: %s", netdir, strerror(errno));
		closedir(d);
		return -1;
	}
	closedir(d);

	if (count != 1) {
		snprintf(err, errlen,
		         "expected exactly one device-backed link in %s, counted %d%s%s",
		         netdir, count, count ? ": " : "", found);
		return -1;
	}

	if ((size_t)snprintf(path, sizeof path, "%s/%s/ifindex", netdir,
	                     nic->name) >= sizeof path) {
		snprintf(err, errlen, "path too long under %s", netdir);
		return -1;
	}
	if (km_read_text(path, text, sizeof text, err, errlen) != 0)
		return -1;
	errno = 0;
	idx = strtol(text, &end, 10);
	if (errno != 0 || end == text || (*end != '\n' && *end != '\0') ||
	    idx <= 0 || idx > 0x7fffffff) {
		snprintf(err, errlen, "%s: not an ifindex: '%s'", path, text);
		return -1;
	}
	nic->ifindex = (int)idx;
	return 0;
}

/* One rtnetlink request; room for the header, the family struct, two attrs. */
struct km_nlreq {
	struct nlmsghdr nh;
	union {
		struct ifinfomsg ifi;
		struct ifaddrmsg ifa;
		struct rtmsg     rtm;
	} u;
	char attrs[64];
};

static void km_nl_attr(struct km_nlreq *req, unsigned short type,
                       const void *data, size_t len)
{
	struct rtattr *rta = (struct rtattr *)((char *)req +
	                                       NLMSG_ALIGN(req->nh.nlmsg_len));
	rta->rta_type = type;
	rta->rta_len = (unsigned short)RTA_LENGTH(len);
	memcpy(RTA_DATA(rta), data, len);
	req->nh.nlmsg_len = NLMSG_ALIGN(req->nh.nlmsg_len) + RTA_ALIGN(rta->rta_len);
}

/* Send one request with NLM_F_ACK and wait for its ack. Only a reply from the
 * kernel (nl_pid 0) carrying our sequence number counts. A non-zero error in
 * the ack is the request's failure, reported with its errno. */
static int km_nl_request(int fd, unsigned int *seq, struct km_nlreq *req,
                         const char *what, char *err, size_t errlen)
{
	struct sockaddr_nl sa;
	char buf[8192] __attribute__((aligned(NLMSG_ALIGNTO)));
	ssize_t n;

	req->nh.nlmsg_flags |= NLM_F_REQUEST | NLM_F_ACK;
	req->nh.nlmsg_seq = ++*seq;

	memset(&sa, 0, sizeof sa);
	sa.nl_family = AF_NETLINK;

	do
		n = sendto(fd, req, req->nh.nlmsg_len, 0,
		           (struct sockaddr *)&sa, sizeof sa);
	while (n < 0 && errno == EINTR);
	if (n < 0 || (size_t)n != req->nh.nlmsg_len) {
		snprintf(err, errlen, "%s: netlink send: %s", what,
		         n < 0 ? strerror(errno) : "short send");
		return -1;
	}

	for (;;) {
		struct sockaddr_nl from;
		socklen_t fromlen = sizeof from;
		struct nlmsghdr *nh;
		int len;

		n = recvfrom(fd, buf, sizeof buf, 0, (struct sockaddr *)&from, &fromlen);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			snprintf(err, errlen, "%s: netlink recv: %s", what, strerror(errno));
			return -1;
		}
		if (from.nl_pid != 0)
			continue;                   /* not from the kernel */

		len = (int)n;
		for (nh = (struct nlmsghdr *)buf; NLMSG_OK(nh, len);
		     nh = NLMSG_NEXT(nh, len)) {
			const struct nlmsgerr *e;

			if (nh->nlmsg_seq != *seq || nh->nlmsg_type != NLMSG_ERROR)
				continue;
			if (nh->nlmsg_len < NLMSG_LENGTH(sizeof *e)) {
				snprintf(err, errlen, "%s: netlink: short ack", what);
				return -1;
			}
			e = NLMSG_DATA(nh);
			if (e->error == 0)
				return 0;
			snprintf(err, errlen, "%s: netlink: %s", what, strerror(-e->error));
			return -1;
		}
	}
}

/* RTM_NEWLINK setting IFF_UP and nothing else. ifindex 0 selects by name. */
static int km_nl_link_up(int fd, unsigned int *seq, int ifindex,
                         const char *name, char *err, size_t errlen)
{
	struct km_nlreq req;
	char what[64];

	memset(&req, 0, sizeof req);
	req.nh.nlmsg_len = NLMSG_LENGTH(sizeof req.u.ifi);
	req.nh.nlmsg_type = RTM_NEWLINK;
	req.u.ifi.ifi_family = AF_UNSPEC;
	req.u.ifi.ifi_index = ifindex;
	req.u.ifi.ifi_flags = IFF_UP;
	req.u.ifi.ifi_change = IFF_UP;
	if (ifindex == 0)
		km_nl_attr(&req, IFLA_IFNAME, name, strlen(name) + 1);

	if (ifindex == 0)
		snprintf(what, sizeof what, "link up %s (by name)", name);
	else
		snprintf(what, sizeof what, "link up %s (ifindex %d)", name, ifindex);
	return km_nl_request(fd, seq, &req, what, err, errlen);
}

/*
 * Apply (ADR-038 §5, §6). One NETLINK_ROUTE socket, closed before returning.
 * In order: lo up (always); routed only: the NIC up, km.ip/32 on it
 * (IFA_LOCAL = IFA_ADDRESS = km.ip, scope universe), then the default route
 * (main table, unicast, universe) via km.gw, out of the NIC, RTNH_F_ONLINK --
 * with a /32 the gateway is not on any prefix, and onlink says it is reachable
 * on this link anyway. On the offline path the NIC is left down (§2).
 */
static int km_net_apply(const struct km_net *net, const struct km_nic *nic,
                        char *err, size_t errlen)
{
	struct km_nlreq req;
	unsigned int seq = 0;
	int rc = -1;
	int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);

	if (fd < 0) {
		snprintf(err, errlen, "netlink socket: %s", strerror(errno));
		return -1;
	}

	if (km_nl_link_up(fd, &seq, 0, "lo", err, errlen) != 0)
		goto out;
	if (net->state != KM_NET_ROUTED) {
		rc = 0;
		goto out;
	}

	if (km_nl_link_up(fd, &seq, nic->ifindex, nic->name, err, errlen) != 0)
		goto out;

	memset(&req, 0, sizeof req);
	req.nh.nlmsg_len = NLMSG_LENGTH(sizeof req.u.ifa);
	req.nh.nlmsg_type = RTM_NEWADDR;
	req.nh.nlmsg_flags = NLM_F_CREATE | NLM_F_EXCL;
	req.u.ifa.ifa_family = AF_INET;
	req.u.ifa.ifa_prefixlen = 32;
	req.u.ifa.ifa_scope = RT_SCOPE_UNIVERSE;
	req.u.ifa.ifa_index = (unsigned int)nic->ifindex;
	km_nl_attr(&req, IFA_LOCAL, &net->ip, sizeof net->ip);
	km_nl_attr(&req, IFA_ADDRESS, &net->ip, sizeof net->ip);
	if (km_nl_request(fd, &seq, &req, "address add", err, errlen) != 0)
		goto out;

	memset(&req, 0, sizeof req);
	req.nh.nlmsg_len = NLMSG_LENGTH(sizeof req.u.rtm);
	req.nh.nlmsg_type = RTM_NEWROUTE;
	req.nh.nlmsg_flags = NLM_F_CREATE | NLM_F_EXCL;
	req.u.rtm.rtm_family = AF_INET;
	req.u.rtm.rtm_dst_len = 0;
	req.u.rtm.rtm_table = RT_TABLE_MAIN;
	req.u.rtm.rtm_protocol = RTPROT_BOOT;
	req.u.rtm.rtm_scope = RT_SCOPE_UNIVERSE;
	req.u.rtm.rtm_type = RTN_UNICAST;
	req.u.rtm.rtm_flags = RTNH_F_ONLINK;
	km_nl_attr(&req, RTA_GATEWAY, &net->gw, sizeof net->gw);
	km_nl_attr(&req, RTA_OIF, &nic->ifindex, sizeof nic->ifindex);
	if (km_nl_request(fd, &seq, &req, "default route add", err, errlen) != 0)
		goto out;

	rc = 0;
out:
	close(fd);
	return rc;
}

/* The resolver file (ADR-038 §7): one line, root:root 0644 (umask is 0 in
 * PID 1), created exclusively and never through a link. */
static int km_net_resolver(const char *path, const struct km_net *net,
                           char *err, size_t errlen)
{
	char line[32 + INET_ADDRSTRLEN];
	char dns[INET_ADDRSTRLEN];
	size_t len, off = 0;
	ssize_t n;
	int fd;

	inet_ntop(AF_INET, &net->dns, dns, sizeof dns);
	len = (size_t)snprintf(line, sizeof line, "nameserver %s\n", dns);

	fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
	if (fd < 0) {
		snprintf(err, errlen, "cannot create %s: %s", path, strerror(errno));
		return -1;
	}
	while (off < len) {
		n = write(fd, line + off, len - off);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			snprintf(err, errlen, "cannot write %s: %s", path, strerror(errno));
			close(fd);
			return -1;
		}
		off += (size_t)n;
	}
	if (close(fd) != 0) {
		snprintf(err, errlen, "cannot close %s: %s", path, strerror(errno));
		return -1;
	}
	return 0;
}

/* The whole step: read, parse, select (routed), apply, resolver (routed), and
 * the one log line of §11. Returns -1 with err[] set on any error; the caller
 * owns the exit. */
static int km_net_step(const char *cmdline_path, const char *netdir,
                       const char *resolv_path, char *err, size_t errlen)
{
	char cmdline[KM_CMDLINE_MAX];
	struct km_net net;
	struct km_nic nic;
	char ip[INET_ADDRSTRLEN], gw[INET_ADDRSTRLEN], dns[INET_ADDRSTRLEN];

	memset(&nic, 0, sizeof nic);
	if (km_read_text(cmdline_path, cmdline, sizeof cmdline, err, errlen) != 0)
		return -1;
	if (km_net_parse(cmdline, &net, err, errlen) != 0)
		return -1;
	if (net.state == KM_NET_ROUTED &&
	    km_net_select(netdir, &nic, err, errlen) != 0)
		return -1;
	if (km_net_apply(&net, &nic, err, errlen) != 0)
		return -1;

	if (net.state != KM_NET_ROUTED) {
		logmsg("net: offline (no km.ip), lo up");
		return 0;
	}
	if (km_net_resolver(resolv_path, &net, err, errlen) != 0)
		return -1;

	inet_ntop(AF_INET, &net.ip, ip, sizeof ip);
	inet_ntop(AF_INET, &net.gw, gw, sizeof gw);
	inet_ntop(AF_INET, &net.dns, dns, sizeof dns);
	logmsg("net: %s %s/32 via %s dns %s", nic.name, ip, gw, dns);
	return 0;
}

/* ---- control socket ------------------------------------------------------- */

static int open_control_socket(void)
{
	int fd;
	struct sockaddr_un sa;

	unlink(INIT_SOCK); /* clear any stale node (fresh tmpfs, but be safe) */

	fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
	if (fd < 0)
		fatal("socket");

	memset(&sa, 0, sizeof sa);
	sa.sun_family = AF_UNIX;
	strncpy(sa.sun_path, INIT_SOCK, sizeof sa.sun_path - 1);

	if (bind(fd, (struct sockaddr *)&sa, sizeof sa) != 0)
		fatal("bind " INIT_SOCK);

	/* Only root (owner) and uid 1000 (group) may connect. */
	if (chown(INIT_SOCK, 0, GID_USER) != 0)
		logmsg("warn: chown " INIT_SOCK ": %s", strerror(errno));
	if (chmod(INIT_SOCK, 0660) != 0)
		logmsg("warn: chmod " INIT_SOCK ": %s", strerror(errno));

	if (listen(fd, 4) != 0)
		fatal("listen");

	return fd;
}

/* Returns 1 if a valid shutdown request was received, else 0. */
static int handle_control_connection(int listen_fd)
{
	int cfd;
	struct ucred cred;
	socklen_t clen = sizeof cred;
	char buf[64];
	ssize_t n;
	int shutdown = 0;

	cfd = accept(listen_fd, NULL, NULL);
	if (cfd < 0)
		return 0;

	/* Defense in depth: the peer must be uid 1000 (the agent). */
	if (getsockopt(cfd, SOL_SOCKET, SO_PEERCRED, &cred, &clen) != 0 ||
	    cred.uid != UID_USER) {
		logmsg("rejected control peer uid=%ld", (long)cred.uid);
		close(cfd);
		return 0;
	}

	n = recv(cfd, buf, sizeof buf - 1, 0);
	if (n > 0) {
		buf[n] = '\0';
		if (strncmp(buf, SHUTDOWN_CMD, strlen(SHUTDOWN_CMD)) == 0) {
			logmsg("shutdown requested via control socket");
			shutdown = 1;
		} else {
			logmsg("unknown control command (ignored)");
		}
	}
	close(cfd);
	return shutdown;
}

/* ---- agent launch (drop to uid 1000) ------------------------------------- */

static pid_t spawn_agent(void)
{
	pid_t pid = fork();
	if (pid < 0)
		fatal("fork");

	if (pid > 0)
		return pid; /* parent */

	/* ---- child: become uid 1000 in a clean session ---- */

	/* Reset signal state inherited from PID 1 (we block signals there). */
	sigset_t empty;
	sigemptyset(&empty);
	sigprocmask(SIG_SETMASK, &empty, NULL);
	signal(SIGCHLD, SIG_DFL);
	signal(SIGTERM, SIG_DFL);
	signal(SIGINT,  SIG_DFL);

	if (setsid() < 0)
		_exit(127);

	/* Privilege drop -- order is security-critical. */
	if (setgroups(0, NULL) != 0)        /* clear root's supplementary groups */
		_exit(127);
	if (setgid(GID_USER) != 0)
		_exit(127);
	if (setuid(UID_USER) != 0)
		_exit(127);

	/* Paranoia: privileges must be irrevocably gone. */
	if (setuid(0) == 0 || geteuid() != UID_USER || getuid() != UID_USER)
		_exit(127);

	/* PID 1 runs with umask 0 (main). Without this, vm-agent and every
	 * application it starts inherit it: a file created in foot in the
	 * user session was 0666 (open problem #53; s4b-impl-B § P8). */
	umask(022);

	if (chdir(USER_HOME) != 0)
		_exit(127);

	{
		char *envp[] = {
			(char *)"HOME=" USER_HOME,
			(char *)"USER=user",
			(char *)"LOGNAME=user",
			(char *)"XDG_RUNTIME_DIR=" XDG_RUNTIME,
			(char *)"PATH=/usr/local/bin:/usr/bin:/bin",
			NULL
		};
#ifdef USE_DBUS_SESSION
		/* Optional: run the agent (and therefore every app it spawns)
		 * under a single session bus. Enable with -DUSE_DBUS_SESSION
		 * ONLY if the empirical RUN test shows apps need a session/a11y
		 * bus (e.g. nautilus Tracker timeouts). Verify the path:
		 * dbus-run-session ships in the `dbus-bin` package on trixie. */
		char *argv[] = { (char *)DBUS_RUN_SESSION_PATH, (char *)"--",
		                 (char *)VM_AGENT_PATH, NULL };
		execve(DBUS_RUN_SESSION_PATH, argv, envp);
#else
		char *argv[] = { (char *)VM_AGENT_PATH, NULL };
		execve(VM_AGENT_PATH, argv, envp);
#endif
	}
	_exit(127); /* execve failed */
}

/* ---- reaping -------------------------------------------------------------- */

/* Drain all reapable children. Returns 1 if the agent was among them. */
static int reap(pid_t agent_pid)
{
	int status, agent_died = 0;
	pid_t p;
	while ((p = waitpid(-1, &status, WNOHANG)) > 0) {
		if (p == agent_pid)
			agent_died = 1;
	}
	return agent_died;
}

/* ---- shutdown ------------------------------------------------------------- */

static void msleep(long ms)
{
	struct timespec ts;
	ts.tv_sec  = ms / 1000;
	ts.tv_nsec = (ms % 1000) * 1000000L;
	nanosleep(&ts, NULL);
}

/* listen_fd is -1 when the control socket was never opened: the network
 * step's error exit (ADR-038 §9, R87) takes this same tail before anything
 * else exists, so there is nothing to close and no node to unlink. */
static void do_shutdown(int listen_fd)
{
	int waited;
	int status;
	pid_t p;

	logmsg("shutting down");

	if (listen_fd >= 0) {
		close(listen_fd);
		unlink(INIT_SOCK);
	}

	/* Politely ask everything (except us) to terminate. */
	kill(-1, SIGTERM);

	/* Grace window: reap until no children remain, or timeout. */
	for (waited = 0; waited < GRACE_MS; waited += 100) {
		p = waitpid(-1, &status, WNOHANG);
		if (p == -1 && errno == ECHILD)
			break;            /* all children gone */
		if (p == 0)
			msleep(100);      /* some still alive, not yet exited */
		/* if p > 0 we reaped one; loop again immediately */
	}

	/* Hard kill any stragglers, then reap briefly (bounded -- reboot
	 * will tear everything down regardless). */
	kill(-1, SIGKILL);
	for (waited = 0; waited < 1000; waited += 50) {
		p = waitpid(-1, &status, WNOHANG);
		if (p == -1 && errno == ECHILD)
			break;
		if (p == 0)
			msleep(50);
	}

	/* /home is persistent: unmount cleanly now that no writers remain. */
	if (umount(HOME_DIR) != 0) {
		logmsg("warn: umount %s: %s -- trying lazy detach", HOME_DIR,
		       strerror(errno));
		umount2(HOME_DIR, MNT_DETACH);
	}

	sync();

	/* Flush the (disposable) root delta and mark it clean. */
	if (mount(NULL, "/", NULL, MS_REMOUNT | MS_RDONLY, NULL) != 0)
		logmsg("warn: remount-ro /: %s", strerror(errno));

	logmsg("reboot(RB_AUTOBOOT) -> triple-fault -> QEMU exits");
	reboot(RB_AUTOBOOT);

	/* Should never reach here. PID 1 must not exit. */
	for (;;)
		pause();
}

/* ---- main ----------------------------------------------------------------- */

#ifndef KATMATE_INIT_NO_MAIN
int main(void)
{
	int sfd, listen_fd;
	sigset_t mask;
	pid_t agent_pid;
	int want_shutdown = 0;

	umask(0);   /* PID 1 only; spawn_agent() sets 022 for vm-agent (#53) */

	logmsg("starting (pid %ld)", (long)getpid());
	if (getpid() != 1)
		logmsg("warn: not running as PID 1");

	setup_filesystems();
	reopen_console();

	/* Network (ADR-038), before anything else exists (R87): no signal mask,
	 * no control socket, no agent. An error leaves through the shutdown tail
	 * -- /home unmounted, reboot, QEMU exits under -no-reboot -- and never
	 * through fatal(): a halted guest keeps QEMU up with nothing answering. */
	{
		char err[KM_ERR_MAX];

		/* The hostname first (R125), so a failure here is logged with the
		 * rest of the km.* step and leaves the same way. */
		if (km_name_step(KM_CMDLINE_PATH, err, sizeof err) != 0) {
			logmsg("hostname: ERROR: %s", err);
			logmsg("net: vm-agent not started; exiting the VM (ADR-038 §9)");
			do_shutdown(-1);
		}
		if (km_net_step(KM_CMDLINE_PATH, KM_SYSFS_NET, KM_RESOLV_PATH,
		                err, sizeof err) != 0) {
			logmsg("net: ERROR: %s", err);
			logmsg("net: vm-agent not started; exiting the VM (ADR-038 §9)");
			do_shutdown(-1);
		}
	}

	/* Block the signals we will consume via signalfd. Children reset this
	 * mask before exec (see spawn_agent), so they are unaffected. */
	sigemptyset(&mask);
	sigaddset(&mask, SIGCHLD);
	sigaddset(&mask, SIGTERM);
	sigaddset(&mask, SIGINT);
	if (sigprocmask(SIG_BLOCK, &mask, NULL) != 0)
		fatal("sigprocmask");

	sfd = signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK);
	if (sfd < 0)
		fatal("signalfd");

	listen_fd = open_control_socket();

	agent_pid = spawn_agent();
	logmsg("vm-agent launched as uid %d (pid %ld)", UID_USER, (long)agent_pid);

	/* Main supervision loop. */
	while (!want_shutdown) {
		struct pollfd fds[2];
		fds[0].fd = sfd;       fds[0].events = POLLIN; fds[0].revents = 0;
		fds[1].fd = listen_fd; fds[1].events = POLLIN; fds[1].revents = 0;

		if (poll(fds, 2, -1) < 0) {
			if (errno == EINTR)
				continue;
			fatal("poll");
		}

		if (fds[0].revents & POLLIN) {
			struct signalfd_siginfo si;
			int need_reap = 0;
			ssize_t r;
			while ((r = read(sfd, &si, sizeof si)) == sizeof si) {
				switch (si.ssi_signo) {
				case SIGCHLD:
					need_reap = 1;
					break;
				case SIGTERM:
				case SIGINT:
					logmsg("received signal %u -> shutdown",
					       si.ssi_signo);
					want_shutdown = 1;
					break;
				default:
					break;
				}
			}
			if (need_reap && reap(agent_pid)) {
				logmsg("vm-agent exited -> shutdown");
				want_shutdown = 1;
			}
		}

		if (fds[1].revents & POLLIN) {
			if (handle_control_connection(listen_fd))
				want_shutdown = 1;
		}
	}

	do_shutdown(listen_fd);
	return 0; /* unreachable */
}
#endif /* KATMATE_INIT_NO_MAIN */
