/*
 * katmate-init.c  --  minimal PID 1 init for the Katmate app_web MicroVM appliance.
 *
 * Target: QEMU microvm machine type, no ACPI, custom monolithic kernel,
 *         no initrd (-kernel direct boot), Debian trixie rootfs.
 *
 * Responsibilities (and nothing more):
 *   1. Mount the pseudo-filesystems and the persistent /home rw LV.
 *   2. Set up XDG_RUNTIME_DIR for user 1000.
 *   3. Open a privileged-side control socket for shutdown requests.
 *   4. Launch vm-agent dropped to user 1000 (the agent does all app/waypipe/dbus work).
 *   5. Reap orphans (the inescapable PID 1 duty).
 *   6. On shutdown request (or agent death): kill children, unmount /home cleanly,
 *      sync, then reboot(RB_AUTOBOOT) -> triple-fault -> QEMU(-no-reboot) exits.
 *
 * Privilege model: this process is the ONLY root code in the guest. All protocol
 * parsing and application launching lives in vm-agent under uid 1000.
 *
 * Build (static, in trixie chroot):
 *   gcc -static -O2 -Wall -Wextra -std=gnu11 -o init katmate-init.c
 * (Alternatively musl-gcc for a cleaner static link. We deliberately make NO
 *  NSS calls -- getpwnam/initgroups/etc -- so static glibc is safe here.)
 *
 * Bake to /sbin/init (kernel default search path; no init= cmdline needed).
 *
 * Host-side requirements (NOT handled here -- go into the launch / .con):
 *   - QEMU:           -no-reboot
 *   - kernel cmdline: reboot=t        (skip the ~5s "try other methods first" delay)
 *   - -drive order:   vda = qcow2 root delta, vdb = raw /home LV
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

static void do_shutdown(int listen_fd)
{
	int waited;
	int status;
	pid_t p;

	logmsg("shutting down");

	close(listen_fd);
	unlink(INIT_SOCK);

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

int main(void)
{
	int sfd, listen_fd;
	sigset_t mask;
	pid_t agent_pid;
	int want_shutdown = 0;

	umask(0);

	logmsg("starting (pid %ld)", (long)getpid());
	if (getpid() != 1)
		logmsg("warn: not running as PID 1");

	setup_filesystems();
	reopen_console();

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
