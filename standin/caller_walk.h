/* Which Mac application is behind a process: walk its parents up to the one just under launchd. */
#ifndef PORTHOLE_CALLER_WALK_H
#define PORTHOLE_CALLER_WALK_H
#include <limits.h>
#include <sys/types.h>

struct proc_info { pid_t ppid; long start_sec; char path[PATH_MAX]; };
/* 0 ok, -1 gone or unreadable */
typedef int (*proc_lookup_fn)(pid_t, struct proc_info *, void *ctx);
struct caller { pid_t top; long start_sec; char app[PATH_MAX]; };

/* 0 with *out filled, or -1 with *why saying what could not be followed (a static buffer). */
int caller_from_pid(pid_t pid, proc_lookup_fn lookup, void *ctx, struct caller *out, const char **why);
/* The live process table: sysctl KERN_PROC_PID for parent and start time, proc_pidpath for the path. */
int proc_lookup_live(pid_t pid, struct proc_info *out, void *ctx);

#endif
