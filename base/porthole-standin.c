/* porthole-standin SOCK TARGET -- a container-side stand-in for one Mac application.
 * porthole-standin --run PROG [ARG...] -- the same, for one program that names its PARENT.
 *
 * Run as the Mac application's own path (/Applications/Google Chrome.app, /opt/pkg/bin/tmux) by
 * porthole-standin-at, and started as a child of xpra. A Linux app that names its
 * callers by the connecting process's executable (1Password: "Allow <exe> to use SSH key") then sees
 * that Mac application: this one process listens on SOCK (mode 0600), connects to TARGET once per
 * accepted connection, and relays both directions itself, so every request the Mac application makes
 * arrives from the same pid and the same executable for as long as the stand-in lives. It never forks
 * or execs a relay: a relay process would be the one named (1Password named s6-ioconnect).
 *
 * Its pid goes to SOCK with ".sock" replaced by ".pid", written once it is listening, so a pid file
 * means "ready". SIGTERM/SIGINT/SIGHUP remove both files and exit 0.
 *
 * --run is for a program that names its caller by its parent instead (1Password's browser helper
 * verifies its parent's executable against the browser allowlist): the stand-in runs PROG as its
 * child with stdin, stdout and stderr passed straight through, forwards SIGTERM/SIGINT/SIGHUP to it,
 * and exits with its status.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define BUFSZ 65536

static char sock_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
static char pid_path[sizeof sock_path];
static struct sockaddr_un target;

/* One direction of one relayed connection: bytes read from `from`, waiting to be written to `to`. */
struct half {
  int from, to;
  char buf[BUFSZ];
  size_t len, off;
  int eof;  /* `from` reached EOF (or failed); `to` is shut down for writing once buf drains */
  int done; /* nothing more will flow this way */
};
struct conn {
  int fd[2]; /* 0: the Mac side (accepted), 1: TARGET */
  struct half h[2]; /* h[0]: fd0 -> fd1, h[1]: fd1 -> fd0 */
};

static struct conn **conns;
static size_t nconns, capconns;

static void die(const char *what) {
  fprintf(stderr, "porthole-standin: %s: %s\n", what, strerror(errno));
  unlink(sock_path);
  unlink(pid_path);
  exit(111);
}

static void on_term(int sig) {
  (void)sig;
  unlink(sock_path);
  unlink(pid_path);
  _exit(0);
}

static void add_conn(int c) {
  int u = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  /* connect() blocks this one loop -- every relay of this application -- while TARGET's backlog is
   * full: bound it. */
  struct timeval tv = {2, 0};
  if (u >= 0) setsockopt(u, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
  if (u < 0 || connect(u, (struct sockaddr *)&target, sizeof target) < 0) {
    fprintf(stderr, "porthole-standin: connect %s: %s\n", target.sun_path, strerror(errno));
    if (u >= 0) close(u);
    close(c);
    return;
  }
  fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK);
  fcntl(u, F_SETFL, fcntl(u, F_GETFL) | O_NONBLOCK);
  struct conn *k = calloc(1, sizeof *k);
  if (!k) { close(c); close(u); return; }
  k->fd[0] = c; k->fd[1] = u;
  k->h[0].from = c; k->h[0].to = u;
  k->h[1].from = u; k->h[1].to = c;
  if (nconns == capconns) {
    size_t cap = capconns ? capconns * 2 : 16;
    struct conn **n = realloc(conns, cap * sizeof *n);
    if (!n) { close(c); close(u); free(k); return; }
    conns = n; capconns = cap;
  }
  conns[nconns++] = k;
}

/* Move what can move without blocking; returns -1 when the connection must be torn down. */
static int pump(struct half *h, short rev_from, short rev_to) {
  if (h->done) return 0;
  if (!h->eof && h->len == 0 && (rev_from & (POLLIN | POLLHUP | POLLERR))) {
    ssize_t r = read(h->from, h->buf, sizeof h->buf);
    if (r > 0) { h->len = (size_t)r; h->off = 0; }
    else if (r == 0 || (errno != EAGAIN && errno != EINTR)) h->eof = 1;
  }
  if (h->len > 0 && (rev_to & (POLLOUT | POLLERR | POLLHUP))) {
    ssize_t w = write(h->to, h->buf + h->off, h->len);
    if (w > 0) { h->off += (size_t)w; h->len -= (size_t)w; }
    else if (w < 0 && errno != EAGAIN && errno != EINTR) return -1;
  }
  if (h->eof && h->len == 0) {
    shutdown(h->to, SHUT_WR);
    h->done = 1;
  }
  return 0;
}

static volatile pid_t run_child;

static void forward(int sig) {
  if (run_child > 0) kill(run_child, sig);
}

static int run(char **prog) {
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sigemptyset(&sa.sa_mask);
  sa.sa_handler = forward;
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);
  /* Held from fork until each side is ready: the parent until it knows the child to forward to, the
   * child until its handlers are back to the defaults PROG expects. None is lost, only delayed. */
  sigset_t held, prev;
  sigemptyset(&held);
  sigaddset(&held, SIGTERM);
  sigaddset(&held, SIGINT);
  sigaddset(&held, SIGHUP);
  sigprocmask(SIG_BLOCK, &held, &prev);
  pid_t p = fork();
  if (p < 0) die("fork");
  if (p == 0) {
    sa.sa_handler = SIG_DFL;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigprocmask(SIG_SETMASK, &prev, NULL);
    execvp(prog[0], prog);
    fprintf(stderr, "porthole-standin: exec %s: %s\n", prog[0], strerror(errno));
    _exit(127);
  }
  run_child = p;
  sigprocmask(SIG_SETMASK, &prev, NULL);
  int st;
  while (waitpid(p, &st, 0) < 0)
    if (errno != EINTR) die("waitpid");
  return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}

int main(int argc, char **argv) {
  if (argc >= 2 && strcmp(argv[1], "--run") == 0) {
    if (argc < 3) {
      fprintf(stderr, "usage: porthole-standin --run PROG [ARG...]\n");
      return 100;
    }
    return run(argv + 2);
  }
  if (argc != 3) {
    fprintf(stderr, "usage: porthole-standin SOCK TARGET | --run PROG [ARG...]\n");
    return 100;
  }
  size_t n = strlen(argv[1]);
  if (n < 6 || n >= sizeof sock_path || strcmp(argv[1] + n - 5, ".sock") != 0) {
    fprintf(stderr, "porthole-standin: SOCK must end in .sock and fit a socket address: %s\n", argv[1]);
    return 100;
  }
  if (strlen(argv[2]) >= sizeof target.sun_path) {
    fprintf(stderr, "porthole-standin: TARGET does not fit a socket address: %s\n", argv[2]);
    return 100;
  }
  memcpy(sock_path, argv[1], n + 1);
  memcpy(pid_path, argv[1], n - 5);
  memcpy(pid_path + n - 5, ".pid", 5);
  target.sun_family = AF_UNIX;
  strcpy(target.sun_path, argv[2]);

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sigemptyset(&sa.sa_mask);
  sa.sa_handler = SIG_IGN;
  sigaction(SIGPIPE, &sa, NULL);
  sa.sa_handler = on_term;
  sigaddset(&sa.sa_mask, SIGTERM);
  sigaddset(&sa.sa_mask, SIGINT);
  sigaddset(&sa.sa_mask, SIGHUP);
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);

  int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
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
  if (f < 0 || write(f, buf, (size_t)len) != len || close(f) < 0 || rename(tmp, pid_path) < 0)
    die(pid_path);

  struct pollfd *pf = NULL;
  size_t cappf = 0;
  int backoff = 0; /* accept failed for want of resources: leave the listener out for a moment */
  for (;;) {
    size_t need = 1 + 2 * nconns;
    if (need > cappf) {
      struct pollfd *np = realloc(pf, need * 2 * sizeof *np);
      if (!np) die("realloc");
      pf = np; cappf = need * 2;
    }
    pf[0].fd = backoff ? -1 : s; pf[0].events = POLLIN; pf[0].revents = 0;
    for (size_t i = 0; i < nconns; i++) {
      struct conn *k = conns[i];
      for (int j = 0; j < 2; j++) {
        struct pollfd *p = &pf[1 + 2 * i + (size_t)j];
        p->fd = k->fd[j]; p->events = 0; p->revents = 0;
        /* fd j is the source of h[j] and the sink of h[1-j]. */
        if (!k->h[j].done && !k->h[j].eof && k->h[j].len == 0) p->events |= POLLIN;
        if (k->h[1 - j].len > 0) p->events |= POLLOUT;
        /* Nothing to wait for on this fd: leave it out. poll() reports POLLHUP whatever `events`
         * says, so a peer that hung up while the other side lingers would otherwise spin the loop. */
        if (p->events == 0) p->fd = -1;
      }
    }
    if (poll(pf, need, backoff ? 100 : -1) < 0) {
      if (errno == EINTR) continue;
      die("poll");
    }
    for (size_t i = 0; i < nconns;) {
      struct conn *k = conns[i];
      short r0 = pf[1 + 2 * i].revents, r1 = pf[2 + 2 * i].revents;
      int bad = pump(&k->h[0], r0, r1) < 0 || pump(&k->h[1], r1, r0) < 0;
      if (bad || (k->h[0].done && k->h[1].done)) {
        close(k->fd[0]); close(k->fd[1]); free(k);
        conns[i] = conns[--nconns];
        /* the last conn moves into this slot, revents and all: handle it in this same pass */
        pf[1 + 2 * i] = pf[1 + 2 * nconns]; pf[2 + 2 * i] = pf[2 + 2 * nconns];
        continue;
      }
      i++;
    }
    backoff = 0;
    if (pf[0].revents & POLLIN) {
      for (;;) {
        int c = accept4(s, NULL, NULL, SOCK_CLOEXEC);
        if (c < 0) {
          /* EMFILE, ENFILE, ENOBUFS...: the listener stays readable, so retry after a pause */
          if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR && errno != ECONNABORTED)
            backoff = 1;
          break;
        }
        add_conn(c);
      }
    }
  }
}
