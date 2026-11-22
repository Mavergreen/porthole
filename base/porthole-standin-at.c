/* porthole-standin-at MACPATH ARG... -- run the stand-in (porthole-standin) as MACPATH: seen there
 * from outside, by the Linux app that names its callers by path, while the container's own files
 * stay as they are.
 * porthole-standin-at --as UID:GID MACPATH ARG... -- the same, started as root, ending as UID:GID.
 * porthole-standin-at --check -- exit 0 iff this container can do that.
 *
 * In this one process: a user namespace mapping the caller's own uid and gid to themselves (so the
 * stand-in runs as exactly who started it) and a private mount namespace; the stand-in made to
 * appear at MACPATH; then exec MACPATH ARG..., so the pid and the parent (xpra, or docker exec) stay
 * the same and the exec drops the namespace's capabilities.
 *
 * Placement. If every directory on MACPATH is a real directory in the container and its last
 * component a regular file, the stand-in is bound over that file. Otherwise the first component
 * that is missing, a symlink or the wrong type is made fresh in a mirror of its parent A: a tmpfs
 * holding A's entries as bind mounts (recursive for directories), symlinks recreated. A mirror of /
 * becomes the namespace's root by pivot_root (a chroot would leave the stand-in seen at the mirror's
 * own path); any other mirror is moved over A.
 *
 * --as. A namespace mapping only the caller's own ids holds no other user or group, and the kernel
 * ignores a set-group-ID bit whose group it doesn't hold: 1Password's browser helper, which insists
 * its group really changed, quits. Started as root, a helper process still outside the namespace maps
 * every uid and gid to itself (only a process privileged outside may), so the namespace is the
 * container's own ids. After placing the stand-in, the process becomes UID:GID (groups just GID, as
 * docker exec -u UID:GID) and checks it can't become root again, before exec. UID 0 is refused.
 * First, still outside the namespace, it hard-links the stand-in at MACPATH in the container itself
 * if nothing is there: 1Password's app opens its browser helper's parent by the path that parent's
 * exe reads, from outside, where a path the namespace alone holds doesn't exist. So --as leaves one
 * root-owned file per browser in the container; a stand-in started without it never writes there.
 *
 * Exit: 2 a refused path or usage; 3 no user namespaces here (one line, saying so); 4 any other
 * setup failure, naming the step.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sched.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <grp.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static const char me[] = "porthole-standin-at";
static const char STANDIN[] = "/usr/local/bin/porthole-standin";
static const char MNT[] = "/usr/local/lib/porthole-standin/mnt";
static const char OLDROOT[] = ".porthole-oldroot";

static void failf(int code, const char *fmt, ...) {
  int e = errno;
  va_list ap;
  fprintf(stderr, "%s: ", me);
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  if (code != 2) fprintf(stderr, ": %s", strerror(e));
  fputc('\n', stderr);
  exit(code);
}

static void unavailable(const char *step) {
  fprintf(stderr, "%s: caller identity is unavailable: this container cannot create user namespaces "
          "(%s: %s)\n", me, step, strerror(errno));
  exit(3);
}

static int put(const char *path, const char *s) {
  int fd = open(path, O_WRONLY | O_CLOEXEC);
  if (fd < 0) return -1;
  ssize_t n = write(fd, s, strlen(s));
  int e = errno;
  close(fd);
  errno = e;
  return n == (ssize_t)strlen(s) ? 0 : -1;
}

static void mounts(void) {
  if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) unavailable("private mounts");
  if (mount("none", MNT, "tmpfs", 0, "size=1m,mode=755") != 0) failf(4, "mount a tmpfs on %s", MNT);
}

/* A namespace holding only the caller's own uid and gid: no privilege needed. */
static void enter(void) {
  char map[64];
  uid_t u = getuid();
  gid_t g = getgid();
  if (unshare(CLONE_NEWUSER | CLONE_NEWNS) != 0) unavailable("unshare");
  if (put("/proc/self/setgroups", "deny") != 0) unavailable("setgroups");
  snprintf(map, sizeof map, "%u %u 1", (unsigned)u, (unsigned)u);
  if (put("/proc/self/uid_map", map) != 0) unavailable("uid_map");
  snprintf(map, sizeof map, "%u %u 1", (unsigned)g, (unsigned)g);
  if (put("/proc/self/gid_map", map) != 0) unavailable("gid_map");
  mounts();
}

/* --as: a namespace holding every uid and gid, mapped by a child still outside it (as root). */
static void enter_all(void) {
  static const char all[] = "0 0 4294967295";
  char path[64];
  int p[2], st;
  pid_t self = getpid(), h;
  if (pipe(p) != 0) failf(4, "pipe");
  if ((h = fork()) < 0) failf(4, "fork");
  if (h == 0) {
    char b;
    const char *step = "uid_map";
    close(p[1]);
    if (read(p[0], &b, 1) != 1) _exit(1);   /* the parent could not unshare: it says why */
    snprintf(path, sizeof path, "/proc/%d/uid_map", (int)self);
    if (put(path, all) == 0) {
      step = "gid_map";
      snprintf(path, sizeof path, "/proc/%d/gid_map", (int)self);
      if (put(path, all) == 0) _exit(0);
    }
    fprintf(stderr, "%s: map every user and group (%s): %s\n", me, step, strerror(errno));
    _exit(1);
  }
  close(p[0]);
  if (unshare(CLONE_NEWUSER | CLONE_NEWNS) != 0) unavailable("unshare");
  if (write(p[1], "x", 1) != 1) failf(4, "signal the mapper");
  close(p[1]);
  if (waitpid(h, &st, 0) != h || !WIFEXITED(st) || WEXITSTATUS(st) != 0) exit(4);
  mounts();
}

/* Becomes U:G for good: no root ids, no capabilities, groups just G. */
static void drop(uid_t u, gid_t g) {
  uid_t r, e, s;
  gid_t gr, ge, gs, gl[2];
  if (setgroups(1, &g) != 0) failf(4, "set groups");
  if (setresgid(g, g, g) != 0) failf(4, "set gid %u", (unsigned)g);
  if (setresuid(u, u, u) != 0) failf(4, "set uid %u", (unsigned)u);
  if (getresuid(&r, &e, &s) != 0 || r != u || e != u || s != u) failf(4, "uid is not %u", (unsigned)u);
  if (getresgid(&gr, &ge, &gs) != 0 || gr != g || ge != g || gs != g) failf(4, "gid is not %u", (unsigned)g);
  if (getgroups(2, gl) != 1 || gl[0] != g) failf(4, "groups are not just %u", (unsigned)g);
  if (setresuid(0, 0, 0) == 0 || setgroups(0, NULL) == 0) { errno = EPERM; failf(4, "root could be regained"); }
}

/* "UID:GID", both decimal, UID not 0. */
static int ids(const char *a, uid_t *u, gid_t *g) {
  unsigned long x, y;
  char *end;
  if (*a < '0' || *a > '9') return -1;
  errno = 0;
  x = strtoul(a, &end, 10);
  if (errno || *end != ':' || end[1] < '0' || end[1] > '9') return -1;
  y = strtoul(end + 1, &end, 10);
  if (errno || *end || x == 0 || x >= 4294967295UL || y >= 4294967295UL) return -1;
  *u = (uid_t)x;
  *g = (gid_t)y;
  return 0;
}

/* Splits PATH into its components (at most 64), refusing what a Mac application path never is. */
static int split(char *path, char **comp) {
  int n = 0;
  if (path[0] != '/') failf(2, "not an absolute path: '%s'", path);
  if (strlen(path) >= PATH_MAX - sizeof MNT - 1) failf(2, "a path too long");
  for (char *p = path + 1;;) {
    char *slash = strchr(p, '/');
    if (slash) *slash = '\0';
    if (!*p) failf(2, "a path with an empty component or a trailing /");
    if (!strcmp(p, ".") || !strcmp(p, "..")) failf(2, "a path with a . or .. component");
    if (n == 64) failf(2, "a path too deep");
    comp[n++] = p;
    if (!slash) return n;
    p = slash + 1;
  }
}

static void bind(const char *src, const char *dst, unsigned long rec) {
  if (mount(src, dst, NULL, MS_BIND | rec, NULL) != 0) failf(4, "bind %s on %s", src, dst);
}

/* The entries of directory A, except SKIP, into MNT: directories bound recursively, symlinks
 * recreated, anything else bound onto an empty file. */
static void mirror(const char *a, const char *skip) {
  char src[PATH_MAX], dst[PATH_MAX], link[PATH_MAX];
  DIR *d = opendir(a);
  struct dirent *e;
  struct stat st;
  if (!d) failf(4, "read %s", a);
  while ((errno = 0, e = readdir(d))) {
    if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..") || !strcmp(e->d_name, skip)) continue;
    snprintf(src, sizeof src, "%s/%s", strcmp(a, "/") ? a : "", e->d_name);
    snprintf(dst, sizeof dst, "%s/%s", MNT, e->d_name);
    if (lstat(src, &st) != 0) failf(4, "stat %s", src);
    if (S_ISLNK(st.st_mode)) {
      ssize_t n = readlink(src, link, sizeof link - 1);
      if (n < 0) failf(4, "read the link %s", src);
      link[n] = '\0';
      if (symlink(link, dst) != 0) failf(4, "link %s", dst);
    } else if (S_ISDIR(st.st_mode)) {
      if (mkdir(dst, 0755) != 0) failf(4, "make %s", dst);
      bind(src, dst, MS_REC);
    } else {
      int fd = open(dst, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
      if (fd < 0) failf(4, "make %s", dst);
      close(fd);
      bind(src, dst, 0);
    }
  }
  if (errno) failf(4, "read %s", a);
  closedir(d);
  /* A recursive bind of the directory holding MNT copied MNT's own tmpfs into the mirror. */
  size_t al = strcmp(a, "/") ? strlen(a) : 0;
  if (!strncmp(MNT, a, al) && MNT[al] == '/') {
    snprintf(dst, sizeof dst, "%s%s", MNT, MNT + al);
    if (umount2(dst, MNT_DETACH) != 0 && errno != EINVAL && errno != ENOENT) failf(4, "unmount %s", dst);
  }
}

static void place(const char *macpath) {
  char buf[PATH_MAX], *comp[64], pre[PATH_MAX], a[PATH_MAX], dst[PATH_MAX];
  struct stat st;
  int n, k;
  snprintf(buf, sizeof buf, "%s", macpath);
  n = split(buf, comp);

  pre[0] = '\0';
  for (k = 0; k < n; k++) {
    snprintf(a, sizeof a, "%s", pre[0] ? pre : "/");
    snprintf(pre + strlen(pre), sizeof pre - strlen(pre), "/%s", comp[k]);
    int r = lstat(pre, &st);
    if (k < n - 1 ? r == 0 && S_ISDIR(st.st_mode) : 0) continue;
    if (k == n - 1 && r == 0 && S_ISREG(st.st_mode)) {
      bind(STANDIN, pre, 0);
      return;
    }
    break;
  }

  /* comp[k] diverges; a is its parent. */
  mirror(a, comp[k]);
  snprintf(dst, sizeof dst, "%s", MNT);
  for (int i = k; i < n; i++) {
    snprintf(dst + strlen(dst), sizeof dst - strlen(dst), "/%s", comp[i]);
    if (i < n - 1) {
      if (mkdir(dst, 0755) != 0) failf(4, "make %s", dst);
    } else {
      int fd = open(dst, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0755);
      if (fd < 0) failf(4, "make %s", dst);
      close(fd);
      bind(STANDIN, dst, 0);
    }
  }

  if (strcmp(a, "/")) {
    if (mount(MNT, a, NULL, MS_MOVE, NULL) != 0) failf(4, "move the mirror over %s", a);
    return;
  }
  snprintf(dst, sizeof dst, "%s/%s", MNT, OLDROOT);
  if (mkdir(dst, 0700) != 0) failf(4, "make %s", dst);
  if (syscall(SYS_pivot_root, MNT, dst) != 0) failf(4, "pivot_root into the mirror");
  if (chdir("/") != 0) failf(4, "chdir /");
  snprintf(dst, sizeof dst, "/%s", OLDROOT);
  if (umount2(dst, MNT_DETACH) != 0) failf(4, "detach the old root");
  if (rmdir(dst) != 0) failf(4, "remove %s", dst);
}

/* --as, before the namespace: the stand-in hard-linked at MACPATH in the container itself, if nothing
 * is there (see --as above). Missing directories on the way are made root's, 0755. Nothing is made
 * under a directory root doesn't own or others may write, nor through a symlink: each step is opened
 * O_NOFOLLOW from the last, so none can be swapped in. Such a path is left as it is. */
static void stake(const char *macpath) {
  char buf[PATH_MAX], *comp[64];
  struct stat st;
  int n, d, c;
  snprintf(buf, sizeof buf, "%s", macpath);
  n = split(buf, comp);
  if ((d = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)) < 0) failf(4, "open /");
  for (int k = 0; k < n; k++) {
    if (fstat(d, &st) != 0) failf(4, "stat a directory on %s", macpath);
    if (st.st_uid != 0 || (st.st_mode & 022)) break;
    if (k == n - 1) {
      if (linkat(AT_FDCWD, STANDIN, d, comp[k], 0) != 0 && errno != EEXIST)
        failf(4, "link the stand-in at %s", macpath);
      break;
    }
    int made = mkdirat(d, comp[k], 0755) == 0;
    if (!made && errno != EEXIST) failf(4, "make a directory on %s", macpath);
    if ((c = openat(d, comp[k], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)) < 0) {
      if (made) failf(4, "open a directory made on %s", macpath);
      break;   /* a symlink, or not a directory */
    }
    if (made && fchmod(c, 0755) != 0) failf(4, "set the mode of a directory on %s", macpath);
    close(d);
    d = c;
  }
  close(d);
}

int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "--check")) {
    enter();
    return 0;
  }
  uid_t u = 0;
  gid_t g = 0;
  int as = argc >= 2 && !strcmp(argv[1], "--as");
  if (as) {
    if (argc < 4 || ids(argv[2], &u, &g) != 0) {
      fprintf(stderr, "%s: --as takes UID:GID, decimal, UID not 0\n", me);
      return 2;
    }
    if (geteuid() != 0) {
      fprintf(stderr, "%s: --as must be started as root\n", me);
      return 2;
    }
    argv += 2;
    argc -= 2;
  }
  if (argc < 2 || argv[1][0] == '-') {
    fprintf(stderr, "usage: %s [--as UID:GID] MACPATH ARG... | --check\n", me);
    return 2;
  }
  {
    char buf[PATH_MAX], *comp[64];
    snprintf(buf, sizeof buf, "%s", argv[1]);
    split(buf, comp);   /* refuse before touching anything */
  }
  if (as) {
    stake(argv[1]);
    enter_all();
  } else enter();
  place(argv[1]);
  if (as) drop(u, g);
  execv(argv[1], argv + 1);
  failf(4, "exec %s", argv[1]);
}
