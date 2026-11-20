/* caller_from_pid against a fake process table: which Mac application is behind a pid. */
#include <stdio.h>
#include <string.h>
#include "caller_walk.h"

struct fake { pid_t pid, ppid; long start; const char *path; };

static int fake_lookup(pid_t pid, struct proc_info *out, void *ctx) {
  for (const struct fake *f = ctx; f->pid; f++)
    if (f->pid == pid) {
      out->ppid = f->ppid;
      out->start_sec = f->start;
      snprintf(out->path, sizeof out->path, "%s", f->path);
      return 0;
    }
  return -1;
}

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

static const struct fake table[] = {
  {1, 0, 1, "/sbin/launchd"},
  {240, 1, 5, "/sbin/launchd"}, /* the per-user launchd */
  {300, 240, 100, "/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"},
  {301, 300, 101, "/usr/bin/login"},
  {302, 301, 102, "/opt/pkg/bin/zsh"},
  {303, 302, 103, "/usr/bin/ssh"},
  {400, 1, 200, "/opt/pkg/bin/tmux"}, /* daemonized: parent pid 1 */
  {401, 400, 201, "/opt/pkg/bin/zsh"},
  {402, 401, 202, "/usr/bin/git"},
  {500, 1, 300, "/usr/local/bin/lonely"},
  {600, 240, 400, "/Applications/Foo.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"},
  {700, 701, 500, "/usr/bin/ssh"}, /* parent 701 is gone */
  {800, 801, 1, "/a"}, {801, 800, 1, "/b"}, /* a cycle */
  {0, 0, 0, NULL}
};

int main(void) {
  struct caller c;
  const char *why = NULL;

  CHECK(caller_from_pid(303, fake_lookup, (void *)table, &c, &why) == 0);
  CHECK(c.top == 300 && c.start_sec == 100);
  CHECK(strcmp(c.app, "/Applications/Utilities/Terminal.app") == 0);

  CHECK(caller_from_pid(402, fake_lookup, (void *)table, &c, &why) == 0);
  CHECK(c.top == 400 && c.start_sec == 200);
  CHECK(strcmp(c.app, "/opt/pkg/bin/tmux") == 0);

  CHECK(caller_from_pid(500, fake_lookup, (void *)table, &c, &why) == 0);
  CHECK(c.top == 500 && strcmp(c.app, "/usr/local/bin/lonely") == 0);

  CHECK(caller_from_pid(600, fake_lookup, (void *)table, &c, &why) == 0);
  CHECK(strcmp(c.app, "/Applications/Foo.app") == 0);

  why = NULL;
  CHECK(caller_from_pid(700, fake_lookup, (void *)table, &c, &why) == -1);
  CHECK(why && strstr(why, "701"));

  why = NULL;
  CHECK(caller_from_pid(999, fake_lookup, (void *)table, &c, &why) == -1);
  CHECK(why && strstr(why, "999"));

  why = NULL;
  CHECK(caller_from_pid(800, fake_lookup, (void *)table, &c, &why) == -1);
  CHECK(why != NULL);

  if (failures) return 1;
  puts("caller_walk: ok");
  return 0;
}
