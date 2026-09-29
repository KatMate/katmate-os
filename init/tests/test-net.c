/*
 * test-net.c  --  behavioural tests for katmate-init's network step (ADR-038).
 *
 * Includes the production source with main() left out (R88), so what is tested
 * is the code foundation.sh compiles, not a copy. Built and run by run.sh; never
 * baked into an image.
 *
 * Groups (argv[1]):
 *   parse               the km.* parser (R86), pure
 *   inet                measures which dotted-quad forms inet_pton(AF_INET)
 *                       refuses; a reading, not a test (no expectations)
 *   select <tmpdir>     NIC selection (R85) against sysfs-shaped fixtures
 *   resolver <tmpdir>   the resolver file: content, mode, O_EXCL, O_NOFOLLOW
 *   ack                 unprivileged, in the caller's own network namespace:
 *                       the kernel refuses the first request, and the refusal
 *                       must come back as an error (the ack path, not apply)
 *   apply <tmpdir>      inside a private network namespace holding link km0
 *                       (run.sh sets that up): the netlink calls themselves
 *
 * Every case states its expected outcome. Exit 0 = all cases passed.
 */

/* The production file's boot-time helpers (setup_filesystems, spawn_agent, ...)
 * are only called from main(), which KATMATE_INIT_NO_MAIN leaves out. */
#pragma GCC diagnostic ignored "-Wunused-function"
/* Inlined into these tests, the fixture paths have a known 512-byte bound and
 * gcc then warns that err[] may truncate them. Truncating a bounded message is
 * the intended behaviour; the production build (literal paths) is clean. */
#pragma GCC diagnostic ignored "-Wformat-truncation"
#include "../katmate-init.c"

static int failures;

static void check(int ok, const char *name, const char *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name,
	       detail && *detail ? "  -- " : "", detail ? detail : "");
	if (!ok)
		failures++;
}

/* ---- parse ------------------------------------------------------------------ */

enum { X_OFFLINE, X_ROUTED, X_ERROR };

struct parse_case {
	const char *name;
	const char *cmdline;
	int         expect;
	const char *ip, *gw, *dns;          /* X_ROUTED */
	const char *errsub;                 /* X_ERROR: err[] must contain this */
};

#define GOOD "km.ip=10.100.1.17 km.gw=10.100.1.1 km.dns=10.100.1.1"

static const struct parse_case parse_cases[] = {
	{ "no km.* -> offline",
	  "console=ttyS0 reboot=t root=/dev/vda rw\n", X_OFFLINE, 0, 0, 0, 0 },
	{ "empty cmdline -> offline", "", X_OFFLINE, 0, 0, 0, 0 },
	{ "the three -> routed",
	  "console=ttyS0 reboot=t " GOOD " ipv6.disable=1\n",
	  X_ROUTED, "10.100.1.17", "10.100.1.1", "10.100.1.1", 0 },
	{ "the three, other order -> routed",
	  "km.dns=10.100.1.1 km.ip=10.100.1.17 km.gw=10.100.1.1",
	  X_ROUTED, "10.100.1.17", "10.100.1.1", "10.100.1.1", 0 },
	{ "tab and newline separate tokens -> routed",
	  "km.ip=10.100.1.17\tkm.gw=10.100.1.1\nkm.dns=10.100.1.1\n",
	  X_ROUTED, "10.100.1.17", "10.100.1.1", "10.100.1.1", 0 },
	{ "15-character value accepted -> routed",
	  "km.ip=255.255.255.255 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ROUTED, "255.255.255.255", "10.100.1.1", "10.100.1.1", 0 },
	{ "km.* after -- counted -> routed",
	  "console=ttyS0 -- " GOOD,
	  X_ROUTED, "10.100.1.17", "10.100.1.1", "10.100.1.1", 0 },
	{ "km.ipx= -> error naming the token",
	  "km.ipx=10.100.1.17 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "'km.ipx=10.100.1.17'" },
	{ "km.ip alone -> partial set",
	  "km.ip=10.100.1.17", X_ERROR, 0, 0, 0, "km.gw MISSING" },
	{ "km.ip + km.gw without km.dns -> partial set",
	  "km.ip=10.100.1.17 km.gw=10.100.1.1",
	  X_ERROR, 0, 0, 0, "km.dns MISSING" },
	{ "km.gw alone -> partial set, not offline (G2 refusal half)",
	  "km.gw=10.100.1.1", X_ERROR, 0, 0, 0, "km.ip MISSING" },
	{ "duplicate km.ip -> error naming the token",
	  GOOD " km.ip=10.100.1.18",
	  X_ERROR, 0, 0, 0, "duplicate km.ip: 'km.ip=10.100.1.18'" },
	{ "leading-zero octet 10.100.1.017 -> error",
	  "km.ip=10.100.1.017 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "'km.ip=10.100.1.017'" },
	{ "three-part 10.100.1 -> error",
	  "km.ip=10.100.1 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "'km.ip=10.100.1'" },
	{ "octet 256 -> error",
	  "km.ip=10.100.1.256 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "'km.ip=10.100.1.256'" },
	{ "hex 0x0a.100.1.17 -> error",
	  "km.ip=0x0a.100.1.17 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "'km.ip=0x0a.100.1.17'" },
	{ "km.ip= empty -> error",
	  "km.ip= km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "'km.ip='" },
	{ "km.ip without = -> error",
	  "km.ip km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "no '='): 'km.ip'" },
	{ "16-character value -> error (length)",
	  "km.ip=10.100.100.10000 km.gw=10.100.1.1 km.dns=10.100.1.1",
	  X_ERROR, 0, 0, 0, "longer than 15 characters: 'km.ip=10.100.100.10000'" },
	{ "km. alone -> error",
	  "console=ttyS0 km.", X_ERROR, 0, 0, 0, "'km.'" },
	{ "km.=x (empty key) -> error",
	  "km.=10.100.1.1", X_ERROR, 0, 0, 0, "unknown km.* key: 'km.=10.100.1.1'" },
	{ "km.ipx= after -- counted -> error",
	  "console=ttyS0 -- km.ipx=1.2.3.4", X_ERROR, 0, 0, 0, "'km.ipx=1.2.3.4'" },
	{ "dotted non-km tokens ignored -> offline",
	  "ipv6.disable=1 console=ttyS0 foo.bar=km.ip=1.2.3.4 xkm.ip=1.2.3.4 KM.ip=1.2.3.4",
	  X_OFFLINE, 0, 0, 0, 0 },
	{ "dotted non-km tokens beside the three -> routed",
	  "ipv6.disable=1 console=ttyS0 " GOOD " virtio_net.napi_tx=1",
	  X_ROUTED, "10.100.1.17", "10.100.1.1", "10.100.1.1", 0 },
};

static int addr_is(const struct in_addr *a, const char *want)
{
	char buf[INET_ADDRSTRLEN];
	inet_ntop(AF_INET, a, buf, sizeof buf);
	return strcmp(buf, want) == 0;
}

static void group_parse(void)
{
	size_t i;

	for (i = 0; i < sizeof parse_cases / sizeof parse_cases[0]; i++) {
		const struct parse_case *c = &parse_cases[i];
		struct km_net net;
		char err[KM_ERR_MAX] = "";
		char detail[KM_ERR_MAX + 64];
		int rc = km_net_parse(c->cmdline, &net, err, sizeof err);
		int ok;

		switch (c->expect) {
		case X_OFFLINE:
			ok = rc == 0 && net.state == KM_NET_OFFLINE;
			snprintf(detail, sizeof detail, "rc=%d state=%d %s", rc,
			         net.state, err);
			break;
		case X_ROUTED:
			ok = rc == 0 && net.state == KM_NET_ROUTED &&
			     addr_is(&net.ip, c->ip) && addr_is(&net.gw, c->gw) &&
			     addr_is(&net.dns, c->dns);
			snprintf(detail, sizeof detail, "rc=%d state=%d %s", rc,
			         net.state, err);
			break;
		default:
			ok = rc == -1 && strstr(err, c->errsub) != NULL;
			snprintf(detail, sizeof detail, "rc=%d err=\"%s\"", rc, err);
			break;
		}
		check(ok, c->name, detail);
	}
}

/* ---- inet (a reading) ----------------------------------------------------- */

static void group_inet(void)
{
	static const char *const forms[] = {
		"10.100.1.17", "0.0.0.0", "255.255.255.255", "10.100.1.017",
		"010.100.1.17", "10.100.1.0", "10.100.1.00", "10.100.1",
		"10.100.1.17.", ".10.100.1.17", "10.100.1.256", "0x0a.100.1.17",
		"10.100.1.17 ", " 10.100.1.17", "10.100.1.+17", "10.100.1.-1",
		"1.2.3.4a", "10..1.17", "167772433", "",
	};
	size_t i;
	struct in_addr a;

	for (i = 0; i < sizeof forms / sizeof forms[0]; i++)
		printf("inet_pton(AF_INET, \"%s\") = %d\n", forms[i],
		       inet_pton(AF_INET, forms[i], &a));
}

/* ---- fixtures --------------------------------------------------------------- */

static void xmkdir(const char *base, const char *rel)
{
	char p[512], *s;
	snprintf(p, sizeof p, "%s/%s", base, rel);
	for (s = p + strlen(base) + 1; *s; s++) {
		if (*s == '/') {
			*s = '\0';
			mkdir(p, 0755);
			*s = '/';
		}
	}
	mkdir(p, 0755);
}

static void xwrite(const char *base, const char *rel, const char *text)
{
	char p[512];
	FILE *f;
	snprintf(p, sizeof p, "%s/%s", base, rel);
	f = fopen(p, "w");
	if (f == NULL || fputs(text, f) < 0 || fclose(f) != 0) {
		perror(p);
		exit(99);
	}
}

static void xlink(const char *base, const char *rel, const char *target)
{
	char p[512];
	snprintf(p, sizeof p, "%s/%s", base, rel);
	if (symlink(target, p) != 0) {
		perror(p);
		exit(99);
	}
}

/*
 * A sysfs-shaped tree under <root>: class/net/<if> is a symlink into
 * devices/..., a device-backed link has <if>/device -> its device directory,
 * a virtual one has none. Mirrors /sys/class/net/eth0 ->
 * ../../devices/.../virtio0/net/eth0 and eth0/device -> ../../../virtio0.
 */
static void fx_virtual(const char *root, const char *ifname, const char *idx)
{
	char rel[256], tgt[256];
	snprintf(rel, sizeof rel, "devices/virtual/net/%s", ifname);
	xmkdir(root, rel);
	snprintf(rel, sizeof rel, "devices/virtual/net/%s/ifindex", ifname);
	xwrite(root, rel, idx);
	xmkdir(root, "class/net");
	snprintf(rel, sizeof rel, "class/net/%s", ifname);
	snprintf(tgt, sizeof tgt, "../../devices/virtual/net/%s", ifname);
	xlink(root, rel, tgt);
}

static void fx_device(const char *root, const char *dev, const char *ifname,
                      const char *idx)
{
	char rel[256], tgt[256];
	snprintf(rel, sizeof rel, "devices/pci0000:00/%s/net/%s", dev, ifname);
	xmkdir(root, rel);
	snprintf(rel, sizeof rel, "devices/pci0000:00/%s/net/%s/ifindex", dev, ifname);
	xwrite(root, rel, idx);
	snprintf(rel, sizeof rel, "devices/pci0000:00/%s/net/%s/device", dev, ifname);
	snprintf(tgt, sizeof tgt, "../../../%s", dev);
	xlink(root, rel, tgt);
	xmkdir(root, "class/net");
	snprintf(rel, sizeof rel, "class/net/%s", ifname);
	snprintf(tgt, sizeof tgt, "../../devices/pci0000:00/%s/net/%s", dev, ifname);
	xlink(root, rel, tgt);
}

/* ---- select ----------------------------------------------------------------- */

static void select_case(const char *name, const char *root, int want_ok,
                        const char *want_name, int want_idx, const char *errsub)
{
	char netdir[512], err[KM_ERR_MAX] = "", detail[KM_ERR_MAX + 64];
	struct km_nic nic;
	int rc, ok;

	snprintf(netdir, sizeof netdir, "%s/class/net", root);
	rc = km_net_select(netdir, &nic, err, sizeof err);
	if (want_ok) {
		ok = rc == 0 && strcmp(nic.name, want_name) == 0 &&
		     nic.ifindex == want_idx;
		snprintf(detail, sizeof detail, "rc=%d nic=%s ifindex=%d %s", rc,
		         nic.name, nic.ifindex, err);
	} else {
		ok = rc == -1 && strstr(err, errsub) != NULL;
		snprintf(detail, sizeof detail, "rc=%d err=\"%s\"", rc, err);
	}
	check(ok, name, detail);
}

static void group_select(const char *tmp)
{
	char r[512];

	snprintf(r, sizeof r, "%s/s1", tmp);
	xmkdir(tmp, "s1");
	fx_virtual(r, "lo", "1\n");
	fx_device(r, "virtio0", "eth0", "2\n");
	select_case("lo + one device-backed -> that one", r, 1, "eth0", 2, 0);

	snprintf(r, sizeof r, "%s/s2", tmp);
	xmkdir(tmp, "s2");
	fx_virtual(r, "lo", "1\n");
	fx_device(r, "virtio0", "eth0", "3\n");
	fx_virtual(r, "dummy0", "2\n");
	fx_virtual(r, "sit0", "4\n");
	select_case("lo + one device-backed + dummy0 + sit0 -> still that one",
	            r, 1, "eth0", 3, 0);

	snprintf(r, sizeof r, "%s/s3", tmp);
	xmkdir(tmp, "s3");
	fx_virtual(r, "lo", "1\n");
	fx_virtual(r, "dummy0", "2\n");
	select_case("zero device-backed -> error", r, 0, 0, 0, "counted 0");

	snprintf(r, sizeof r, "%s/s4", tmp);
	xmkdir(tmp, "s4");
	fx_virtual(r, "lo", "1\n");
	fx_device(r, "virtio0", "eth0", "2\n");
	fx_device(r, "virtio1", "eth1", "3\n");
	select_case("two device-backed -> error", r, 0, 0, 0, "counted 2: eth");

	snprintf(r, sizeof r, "%s/s5", tmp);
	select_case("class/net absent -> error", r, 0, 0, 0, "cannot open");

	snprintf(r, sizeof r, "%s/s6", tmp);
	xmkdir(tmp, "s6");
	fx_virtual(r, "lo", "1\n");
	fx_device(r, "virtio0", "eth0", "zero\n");
	select_case("unreadable ifindex -> error", r, 0, 0, 0, "not an ifindex");
}

/* ---- resolver ----------------------------------------------------------------- */

static void group_resolver(const char *tmp)
{
	struct km_net net;
	char path[512], other[512], buf[64] = "", err[KM_ERR_MAX] = "";
	char detail[KM_ERR_MAX + 64];
	struct stat st;
	FILE *f;
	size_t n = 0;
	int rc;

	memset(&net, 0, sizeof net);
	net.state = KM_NET_ROUTED;
	inet_pton(AF_INET, "10.100.1.1", &net.dns);

	umask(0);                           /* as PID 1 runs it (main: umask(0)) */
	snprintf(path, sizeof path, "%s/resolv.conf", tmp);
	rc = km_net_resolver(path, &net, err, sizeof err);
	f = fopen(path, "r");
	if (f) {
		n = fread(buf, 1, sizeof buf - 1, f);
		fclose(f);
	}
	buf[n] = '\0';
	stat(path, &st);
	snprintf(detail, sizeof detail, "rc=%d mode=%03o content=\"%s\"", rc,
	         (unsigned)(st.st_mode & 07777), buf);
	check(rc == 0 && strcmp(buf, "nameserver 10.100.1.1\n") == 0 &&
	      (st.st_mode & 07777) == 0644 && S_ISREG(st.st_mode),
	      "writes one line, regular file, mode 0644", detail);

	rc = km_net_resolver(path, &net, err, sizeof err);
	snprintf(detail, sizeof detail, "rc=%d err=\"%s\"", rc, err);
	check(rc == -1 && strstr(err, "File exists") != NULL,
	      "existing file -> error (O_EXCL), not overwritten", detail);

	snprintf(path, sizeof path, "%s/link.conf", tmp);
	snprintf(other, sizeof other, "%s/target.conf", tmp);
	xlink(tmp, "link.conf", "target.conf");
	rc = km_net_resolver(path, &net, err, sizeof err);
	snprintf(detail, sizeof detail, "rc=%d err=\"%s\" target %s", rc, err,
	         access(other, F_OK) == 0 ? "CREATED" : "absent");
	check(rc == -1 && access(other, F_OK) != 0,
	      "dangling symlink at the path -> error, nothing written through it",
	      detail);
}

/* ---- ack (unprivileged control) ------------------------------------------- */

static void group_ack(void)
{
	struct km_net net;
	struct km_nic nic;
	char err[KM_ERR_MAX] = "", detail[KM_ERR_MAX + 64];
	int rc;

	if (geteuid() == 0) {
		check(0, "ack group must not run as root (it would reach the host's lo)", 0);
		return;
	}
	memset(&net, 0, sizeof net);
	memset(&nic, 0, sizeof nic);
	net.state = KM_NET_OFFLINE;
	rc = km_net_apply(&net, &nic, err, sizeof err);
	snprintf(detail, sizeof detail, "rc=%d err=\"%s\"", rc, err);
	check(rc == -1 && strstr(err, "link up lo") != NULL &&
	      strstr(err, "Operation not permitted") != NULL,
	      "unprivileged lo up -> kernel's EPERM reported as an error", detail);
}

/* ---- apply (inside a private network namespace) -------------------------- */

static void group_apply(const char *tmp)
{
	struct km_net net;
	struct km_nic nic, bogus;
	char err[KM_ERR_MAX] = "", detail[KM_ERR_MAX + 64], path[512];
	int rc;

	memset(&net, 0, sizeof net);
	net.state = KM_NET_ROUTED;
	inet_pton(AF_INET, "10.100.1.17", &net.ip);
	inet_pton(AF_INET, "10.100.1.1", &net.gw);
	inet_pton(AF_INET, "10.100.1.1", &net.dns);

	memset(&bogus, 0, sizeof bogus);
	bogus.ifindex = 999999;
	strcpy(bogus.name, "nosuch");
	rc = km_net_apply(&net, &bogus, err, sizeof err);
	snprintf(detail, sizeof detail, "rc=%d err=\"%s\"", rc, err);
	check(rc == -1 && strstr(err, "link up nosuch (ifindex 999999)") != NULL &&
	      strstr(err, "No such device") != NULL,
	      "non-existent ifindex -> the netlink error is reported", detail);

	memset(&nic, 0, sizeof nic);
	strcpy(nic.name, "km0");
	nic.ifindex = (int)if_nametoindex("km0");
	err[0] = '\0';
	rc = km_net_apply(&net, &nic, err, sizeof err);
	snprintf(detail, sizeof detail, "rc=%d km0 ifindex=%d %s", rc, nic.ifindex, err);
	check(nic.ifindex > 0 && rc == 0, "apply on km0 -> success", detail);

	snprintf(path, sizeof path, "%s/resolv.conf", tmp);
	rc = km_net_resolver(path, &net, err, sizeof err);
	snprintf(detail, sizeof detail, "rc=%d %s", rc, err);
	check(rc == 0, "resolver written to the temp dir", detail);
}

int main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc == 2 && strcmp(argv[1], "parse") == 0)
		group_parse();
	else if (argc == 2 && strcmp(argv[1], "inet") == 0)
		group_inet();
	else if (argc == 3 && strcmp(argv[1], "select") == 0)
		group_select(argv[2]);
	else if (argc == 3 && strcmp(argv[1], "resolver") == 0)
		group_resolver(argv[2]);
	else if (argc == 2 && strcmp(argv[1], "ack") == 0)
		group_ack();
	else if (argc == 3 && strcmp(argv[1], "apply") == 0)
		group_apply(argv[2]);
	else {
		fprintf(stderr, "usage: %s parse|inet|ack|select <tmp>|resolver <tmp>|apply <tmp>\n",
		        argv[0]);
		return 2;
	}
	return failures ? 1 : 0;
}
