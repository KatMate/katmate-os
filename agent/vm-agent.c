#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <linux/vm_sockets.h>
#include <sys/sendfile.h>
#include <sys/stat.h>
 
#define PORT 1025
#define BUF_SIZE 512
#define MAX_FILE_SIZE (100*1024*1024)
 
const char *whitelist[] = {
    "firefox-esr",
    "foot",
    "nautilus",
    NULL
};
 
int allowed_app(const char *app)
{
    for (int i = 0; whitelist[i]; i++)
        if (strcmp(app, whitelist[i]) == 0)
            return 1;
 
    return 0;
}
 
int allowed_path(const char *path)
{
    return strncmp(path, "/home/user/", 11) == 0;
}
 
ssize_t read_full(int fd, void *buf, size_t len)
{
    size_t done = 0;
 
    while (done < len) {
 
        ssize_t r = read(fd, (char*)buf + done, len - done);
 
        if (r <= 0)
            return -1;
 
        done += r;
    }
 
    return done;
}
 
ssize_t write_full(int fd, const void *buf, size_t len)
{
    size_t done = 0;
 
    while (done < len) {
 
        ssize_t r = write(fd, (char*)buf + done, len - done);
 
        if (r <= 0)
            return -1;
 
        done += r;
    }
 
    return done;
}
 
ssize_t read_line(int fd, char *buf, size_t maxlen)
{
    size_t i = 0;
    char c;
 
    while (i < maxlen - 1) {
 
        ssize_t r = read(fd, &c, 1);
 
        if (r <= 0)
            return -1;
 
        if (c == '\n')
            break;
 
        buf[i++] = c;
    }
 
    buf[i] = 0;
 
    return i;
}
 
void cmd_ping(int fd)
{
    write(fd, "OK\n", 3);
}
 
void cmd_run(int fd, char *app)
{
    if (!allowed_app(app)) {
        write(fd, "ERR\n", 4);
        return;
    }
 
    pid_t pid = fork();
 
    if (pid == 0) {
 
        char *argv[] = {
            "waypipe",
            "--vsock",
            "--socket",
            "2:1024",
            "server",
            app,
            NULL
        };
 
        setenv("WAYLAND_DISPLAY", "wayland-1", 1);
        setenv("XDG_RUNTIME_DIR", "/run/user/1000", 1);
 
        int devnull = open("/dev/null", O_WRONLY);
 
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
 
        execvp("waypipe", argv);
 
        _exit(1);
    }
 
    write(fd, "OK\n", 3);
}
 
void cmd_fileget(int fd, char *path)
{
    if (!allowed_path(path)) {
        write(fd, "ERR\n", 4);
        return;
    }
 
    int f = open(path, O_RDONLY);
 
    if (f < 0) {
        write(fd, "ERR\n", 4);
        return;
    }
 
    struct stat st;
 
    if (fstat(f, &st) < 0) {
        close(f);
        write(fd, "ERR\n", 4);
        return;
    }
 
    if (st.st_size > MAX_FILE_SIZE) {
        close(f);
        write(fd, "ERR\n", 4);
        return;
    }
 
    char hdr[64];
 
    snprintf(hdr, sizeof(hdr), "OK %ld\n", (long)st.st_size);
 
    write(fd, hdr, strlen(hdr));
 
    off_t offset = 0;
 
    while (offset < st.st_size) {
 
        ssize_t sent = sendfile(fd, f, &offset, st.st_size - offset);
 
        if (sent <= 0)
            break;
    }
 
    close(f);
}
 
void cmd_fileput(int fd, char *path, char *size_str)
{
    if (!allowed_path(path)) {
        write(fd, "ERR\n", 4);
        return;
    }
 
    long size = atol(size_str);
 
    if (size <= 0 || size > MAX_FILE_SIZE) {
        write(fd, "ERR\n", 4);
        return;
    }
 
    int f = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
 
    if (f < 0) {
        write(fd, "ERR\n", 4);
        return;
    }
 
    write(fd, "OK\n", 3);
 
    char buffer[4096];
    long remaining = size;
 
    while (remaining > 0) {
 
        ssize_t chunk = remaining > sizeof(buffer)
                        ? sizeof(buffer)
                        : remaining;
 
        ssize_t rr = read_full(fd, buffer, chunk);
 
        if (rr <= 0)
            break;
 
        if (write_full(f, buffer, rr) < 0)
            break;
 
        remaining -= rr;
    }
 
    close(f);
}
 
void cmd_shutdown(int fd)
{
    write(fd, "OK\n", 3);
 
    pid_t pid = fork();
 
    if (pid == 0) {
 
	execl("/usr/local/sbin/vm-power-helper",
		"vm-power-helper",
		NULL);
      
        _exit(1);
    }
}
 
void handle_client(int fd)
{
    char line[BUF_SIZE];
    char cmd[16];
    char arg1[256];
    char arg2[64];
 
    while (1) {
 
        if (read_line(fd, line, sizeof(line)) <= 0)
            break;
 
        memset(cmd, 0, sizeof(cmd));
        memset(arg1, 0, sizeof(arg1));
        memset(arg2, 0, sizeof(arg2));
 
        int n = sscanf(line, "%15s %255s %63s", cmd, arg1, arg2);
 
        if (n < 1)
            continue;
 
        if (strcmp(cmd, "PING") == 0) {
            cmd_ping(fd);
        }
 
        else if (strcmp(cmd, "RUN") == 0) {
            cmd_run(fd, arg1);
        }
 
        else if (strcmp(cmd, "FILEGET") == 0) {
            cmd_fileget(fd, arg1);
        }
 
        else if (strcmp(cmd, "FILEPUT") == 0) {
            cmd_fileput(fd, arg1, arg2);
        }
 
        else if (strcmp(cmd, "SHUTDOWN") == 0) {
            cmd_shutdown(fd);
        }
 
        else {
            write(fd, "ERR\n", 4);
        }
    }
}
 
int main()
{
    int sock;
 
    struct sockaddr_vm addr = {0};
    struct sockaddr_vm peer = {0};
 
    socklen_t peer_len = sizeof(peer);
 
    sock = socket(AF_VSOCK, SOCK_STREAM, 0);
 
    addr.svm_family = AF_VSOCK;
    addr.svm_port = PORT;
    addr.svm_cid = VMADDR_CID_ANY;
 
    bind(sock, (struct sockaddr*)&addr, sizeof(addr));
 
    listen(sock, 5);
 
    while (1) {
 
        int client = accept(sock, (struct sockaddr*)&peer, &peer_len);
 
        if (client < 0)
            continue;
 
        /* dovoljen samo host */
 
        if (peer.svm_cid != VMADDR_CID_HOST) {
 
            close(client);
            continue;
        }
 
        handle_client(client);
 
        close(client);
    }
}
 
