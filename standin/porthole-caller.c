/* porthole-caller -- name the Mac application behind a connection or a process.
 *
 *   porthole-caller peer      the client on the other end of fd 0 (a Unix socket)
 *   porthole-caller pid PID   the process PID
 *   porthole-caller alive ID  exit 0 iff instance ID (<pid>-<start second>) still runs
 *
 * peer and pid print "<toppid>-<start second>\t<application path>\n", where the top process is the
 * one just under launchd; or exit 1 with "porthole-caller: <why>" on stderr.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "caller_walk.h"

static int refuse(const char *why) {
  fprintf(stderr, "porthole-caller: %s\n", why);
  return 1;
}

static int parse_pid(const char *s, pid_t *out) {
  char *end;
  errno = 0;
  long v = strtol(s, &end, 10);
  if (errno || end == s || *end || v <= 0 || v > 0x7fffffff) return -1;
  *out = (pid_t)v;
  return 0;
}

static int print_caller(pid_t pid) {
  struct caller c;
  const char *why = "unknown";
  if (caller_from_pid(pid, proc_lookup_live, NULL, &c, &why) != 0) return refuse(why);
  printf("%ld-%ld\t%s\n", (long)c.top, c.start_sec, c.app);
  return fflush(stdout) == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "peer") == 0) {
    pid_t pid = 0;
    socklen_t len = sizeof pid;
    if (getsockopt(0, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) != 0 || pid <= 0) {
      char why[128];
      snprintf(why, sizeof why, "no peer on fd 0: %s", strerror(errno ? errno : ESRCH));
      return refuse(why);
    }
    return print_caller(pid);
  }
  if (argc == 3 && strcmp(argv[1], "pid") == 0) {
    pid_t pid;
    if (parse_pid(argv[2], &pid) != 0) return refuse("not a pid");
    return print_caller(pid);
  }
  if (argc == 3 && strcmp(argv[1], "alive") == 0) {
    const char *dash = strchr(argv[2], '-');
    pid_t pid;
    char head[16];
    if (!dash || (size_t)(dash - argv[2]) >= sizeof head) return 2;
    memcpy(head, argv[2], (size_t)(dash - argv[2]));
    head[dash - argv[2]] = '\0';
    char *end;
    long start = strtol(dash + 1, &end, 10);
    if (parse_pid(head, &pid) != 0 || end == dash + 1 || *end) return 2;
    struct proc_info p;
    return proc_lookup_live(pid, &p, NULL) == 0 && p.start_sec == start ? 0 : 1;
  }
  fprintf(stderr, "usage: porthole-caller peer | pid PID | alive ID\n");
  return 100;
}
