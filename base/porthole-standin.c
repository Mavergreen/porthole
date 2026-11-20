/* porthole-standin SOCK PROG [ARG...] -- a container-side stand-in for one Mac application.
 *
 * Installed as a hard link at the Mac application's path (/Applications/Google Chrome.app, or
 * /Mac/<path> for a plain program) and started as a child of xpra, so a Linux app that names its
 * callers by their process (1Password: the peer's parent and its executable) sees that application.
 * Listens on SOCK (mode 0600) and, per connection, forks a child with the connection on fds 0 and 1
 * that execs PROG -- `s6-ipcclient <agent.sock> s6-ioconnect` -- so every request this application
 * makes arrives from a child of the same stand-in. It stays the parent: it never execs itself away.
 *
 * Its pid goes to SOCK with ".sock" replaced by ".pid", written once it is listening, so a pid file
 * means "ready". SIGTERM/SIGINT/SIGHUP remove both files and exit 0.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static char sock_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
static char pid_path[sizeof sock_path];

static void die(const char *what) {
  fprintf(stderr, "porthole-standin: %s: %s\n", what, strerror(errno));
  exit(111);
}

static void on_term(int sig) {
  (void)sig;
  unlink(sock_path);
  unlink(pid_path);
  _exit(0);
}

static void on_chld(int sig) {
  int e = errno;
  (void)sig;
  while (waitpid(-1, NULL, WNOHANG) > 0) {}
  errno = e;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: porthole-standin SOCK PROG [ARG...]\n");
    return 100;
  }
  size_t n = strlen(argv[1]);
  if (n < 6 || n >= sizeof sock_path || strcmp(argv[1] + n - 5, ".sock") != 0) {
    fprintf(stderr, "porthole-standin: SOCK must end in .sock and fit a socket address: %s\n", argv[1]);
    return 100;
  }
  memcpy(sock_path, argv[1], n + 1);
  memcpy(pid_path, argv[1], n - 5);
  memcpy(pid_path + n - 5, ".pid", 5);

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sigemptyset(&sa.sa_mask);
  sa.sa_handler = SIG_IGN;
  sigaction(SIGPIPE, &sa, NULL);
  sa.sa_handler = on_chld;
  sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
  sigaction(SIGCHLD, &sa, NULL);
  sa.sa_flags = 0;
  sa.sa_handler = on_term;
  sigaddset(&sa.sa_mask, SIGTERM);
  sigaddset(&sa.sa_mask, SIGINT);
  sigaddset(&sa.sa_mask, SIGHUP);
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);

  int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (s < 0) die("socket");
  struct sockaddr_un a;
  memset(&a, 0, sizeof a);
  a.sun_family = AF_UNIX;
  memcpy(a.sun_path, sock_path, n + 1);
  unlink(sock_path);
  mode_t old = umask(0177);
  if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) die(sock_path);
  umask(old);
  if (listen(s, 64) < 0) die("listen");

  char buf[32];
  int len = snprintf(buf, sizeof buf, "%ld\n", (long)getpid());
  char tmp[sizeof pid_path + 8];
  snprintf(tmp, sizeof tmp, "%s.new", pid_path);
  int f = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (f < 0 || write(f, buf, (size_t)len) != len || close(f) < 0 || rename(tmp, pid_path) < 0) {
    unlink(sock_path);
    die(pid_path);
  }

  for (;;) {
    int c = accept4(s, NULL, NULL, SOCK_CLOEXEC);
    if (c < 0) {
      if (errno == EINTR || errno == ECONNABORTED) continue;
      die("accept");
    }
    pid_t p = fork();
    if (p == 0) {
      sa.sa_handler = SIG_DFL;
      sa.sa_flags = 0;
      sigemptyset(&sa.sa_mask);
      sigaction(SIGPIPE, &sa, NULL);
      sigaction(SIGCHLD, &sa, NULL);
      sigaction(SIGTERM, &sa, NULL);
      sigaction(SIGINT, &sa, NULL);
      sigaction(SIGHUP, &sa, NULL);
      if (dup2(c, 0) < 0 || dup2(c, 1) < 0) _exit(111);
      execvp(argv[2], argv + 2);
      fprintf(stderr, "porthole-standin: exec %s: %s\n", argv[2], strerror(errno));
      _exit(127);
    }
    if (p < 0) fprintf(stderr, "porthole-standin: fork: %s\n", strerror(errno));
    close(c);
  }
}
