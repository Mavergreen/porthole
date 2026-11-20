#include "caller_walk.h"

#include <stdio.h>
#include <string.h>

#ifdef __APPLE__
#include <libproc.h>
#include <sys/sysctl.h>
#endif

#define MAX_DEPTH 64

static char why_buf[128];

static int fail(const char **why, const char *fmt, long n) {
  snprintf(why_buf, sizeof why_buf, fmt, n);
  if (why) *why = why_buf;
  return -1;
}

/* The application a path belongs to: through the outermost ".app" of a bundle executable, else the
 * path itself. */
static void app_of(const char *path, char *app, size_t size) {
  const char *macos = strstr(path, ".app/Contents/MacOS/");
  const char *first = macos ? strstr(path, ".app/") : NULL;
  if (first) {
    size_t n = (size_t)(first - path) + 4;
    if (n >= size) n = size - 1;
    memcpy(app, path, n);
    app[n] = '\0';
  } else {
    snprintf(app, size, "%s", path);
  }
}

/* The walk stops at the last process whose parent is pid <= 1, or whose parent is a launchd (10.9
 * runs one per user; a daemonized program's parent is pid 1). */
int caller_from_pid(pid_t pid, proc_lookup_fn lookup, void *ctx, struct caller *out, const char **why) {
  struct proc_info cur, parent;
  pid_t at = pid;
  if (lookup(at, &cur, ctx) != 0) return fail(why, "process %ld: gone or unreadable", (long)at);
  for (int depth = 0; depth < MAX_DEPTH; depth++) {
    int top = cur.ppid <= 1;
    if (!top) {
      if (lookup(cur.ppid, &parent, ctx) != 0)
        return fail(why, "process %ld: gone or unreadable", (long)cur.ppid);
      top = strcmp(parent.path, "/sbin/launchd") == 0;
    }
    if (top) {
      out->top = at;
      out->start_sec = cur.start_sec;
      app_of(cur.path, out->app, sizeof out->app);
      return 0;
    }
    at = cur.ppid;
    cur = parent;
  }
  return fail(why, "process chain deeper than %ld", MAX_DEPTH);
}

#ifdef __APPLE__
int proc_lookup_live(pid_t pid, struct proc_info *out, void *ctx) {
  (void)ctx;
  if (pid <= 0) return -1;
  struct kinfo_proc kp;
  size_t len = sizeof kp;
  int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
  memset(&kp, 0, sizeof kp);
  if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0 || kp.kp_proc.p_pid != pid) return -1;
  if (proc_pidpath(pid, out->path, sizeof out->path) <= 0) return -1;
  out->ppid = kp.kp_eproc.e_ppid;
  out->start_sec = (long)kp.kp_proc.p_starttime.tv_sec;
  return 0;
}
#endif
