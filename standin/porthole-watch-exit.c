/* porthole-watch-exit LOCKFILE ID -- CMD [ARG...] -- run CMD once when application instance ID exits.
 *
 * ID is <pid>-<start second> (porthole-caller's instance id). One watcher per instance: LOCKFILE is
 * flock()ed for the watcher's life, so a second call while one watches returns 0 at once. An
 * instance already gone runs CMD now, with CMD's exit status. Otherwise the watcher detaches (new
 * session, fds 0-2 on /dev/null, every other inherited fd closed, so a caller's connection is never
 * held open) and the call returns 0; the watcher waits for NOTE_EXIT, runs CMD, removes LOCKFILE.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <unistd.h>

#include "caller_walk.h"

static int usage(void) {
  fprintf(stderr, "usage: porthole-watch-exit LOCKFILE ID -- CMD [ARG...]\n");
  return 100;
}

static int run(char **cmd) {
  pid_t p = fork();
  if (p < 0) return 111;
  if (p == 0) {
    execvp(cmd[0], cmd);
    fprintf(stderr, "porthole-watch-exit: exec %s: %s\n", cmd[0], strerror(errno));
    _exit(127);
  }
  int st;
  while (waitpid(p, &st, 0) < 0)
    if (errno != EINTR) return 111;
  return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}

static int parse_id(const char *id, pid_t *pid, long *start) {
  char *end;
  errno = 0;
  long p = strtol(id, &end, 10);
  if (errno || end == id || *end != '-' || p <= 0) return -1;
  const char *s = end + 1;
  *start = strtol(s, &end, 10);
  if (errno || end == s || *end) return -1;
  *pid = (pid_t)p;
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 5 || strcmp(argv[3], "--") != 0) return usage();
  const char *lockfile = argv[1];
  char **cmd = argv + 4;
  pid_t pid;
  long start;
  if (parse_id(argv[2], &pid, &start) != 0) {
    fprintf(stderr, "porthole-watch-exit: not an instance id: %s\n", argv[2]);
    return 100;
  }

  int lk = open(lockfile, O_RDWR | O_CREAT, 0600);
  if (lk < 0) {
    fprintf(stderr, "porthole-watch-exit: %s: %s\n", lockfile, strerror(errno));
    return 111;
  }
  if (flock(lk, LOCK_EX | LOCK_NB) != 0) return errno == EWOULDBLOCK ? 0 : 111;

  struct proc_info pi;
  if (proc_lookup_live(pid, &pi, NULL) != 0 || pi.start_sec != start) {
    int rc = run(cmd);
    unlink(lockfile);
    return rc;
  }

  pid_t w = fork();
  if (w < 0) return 111;
  if (w > 0) return 0;

  setsid();
  int dn = open("/dev/null", O_RDWR);
  if (dn >= 0) {
    dup2(dn, 0); dup2(dn, 1); dup2(dn, 2);
    if (dn > 2) close(dn);
  }
  int max = getdtablesize();
  for (int fd = 3; fd < max; fd++)
    if (fd != lk) close(fd);

  int kq = kqueue();
  struct kevent ev;
  EV_SET(&ev, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
  if (kq >= 0 && kevent(kq, &ev, 1, NULL, 0, NULL) == 0) {
    /* The instance may have exited, and its pid been reused, between the check above and this
     * registration: only wait if the pid still names this instance. */
    if (proc_lookup_live(pid, &pi, NULL) == 0 && pi.start_sec == start) {
      struct kevent got;
      while (kevent(kq, NULL, 0, &got, 1, NULL) < 0 && errno == EINTR) {}
    }
  } else if (kq < 0 || errno != ESRCH) {
    /* Cannot watch (not "it exited"): stopping a live application's stand-in would cost it a fresh
     * prompt. Give up; the bridge starts a watcher again on the next connection. */
    unlink(lockfile);
    return 111;
  }
  run(cmd);
  unlink(lockfile);
  return 0;
}
