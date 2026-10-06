# Backlog

Work worth doing that is not worth interrupting something else to do. Each entry carries the
**evidence**, not just the conclusion. Delete an entry when it lands.

---

## 2. Every Porthole release forces every app to re-pull the base and rebuild

**What happens:** the base image is tagged with the Porthole version, and materialize writes
`FROM …porthole-base:<version>`. So any Porthole release, even one that doesn't touch `base/`,
changes every app's recipe fingerprint. On next launch each app downloads ~1.4G, rebuilds, and
recreates its container, which relocks 1Password. On 2026-09-24 that happened three times in one
afternoon (.7, .9, .10) and filled the 18G Docker VM once (fixed since, `df9c39f`).

**Direction:** tag the base by a hash of its inputs (base/Dockerfile, the menu daemon, the fonts
conf, the xpra pin), so the tag changes only when the base does. Needs a decision on the tag scheme
before building (see the family's version conventions).

## 6. Retina: render apps at the Mac's backing scale

**Want:** on a Retina Mac (Mavericks runs on 2012–2013 Retina MacBook Pros), a Linux app looks as
sharp as a native one: text, windows, and its menu-bar extra.

**Why (2026-09-25):** the container renders at 1× and the viewer shows one pixel per point, so on a
2× screen macOS stretches everything 2×. Measured on the tray: Signal picks its tray art from the
display scale factor Electron sees (16 px at 1×, 32 px at 2×, … 256 px at 16×; `main.js`
`getAllDisplays().scaleFactor`), and the container reports 1×, so it sends 16 px. Resizing the
docked tray (xpra accepts a client `configure` geometry for trays, `seamless.py` `move_resize`) only
upscales that 16 px art, and forcing `--force-device-scale-factor=2` alone would double the app's UI
in points too.

**Direction:** tell the container the Mac's backing scale (xpra client DPI/scaling caps → Xft.dpi,
GDK_SCALE/Electron device scale), and have the viewer map pixels to points by that scale for windows,
input coordinates, resizes, and tray images (`PortholeTrayArtSize` already divides by scale, per the
menu-bar plan). Needs a Retina Mac to verify; this dev box's display is 1×.

## 7. A routine launch bounces in the Dock until the app is open, like a Mac app

**Want:** opening a prepared app looks like opening a native one that's slow to start: its Dock icon
keeps bouncing until the app's window appears, with no progress bar on the icon.

**Why (2026-10-06):** since `711f2af` a routine launch shows no launch window, just an indeterminate
bar sweeping across the Dock icon (`PortholeDockProgress`) until the first app window maps: about
4 s for 1Password, 8 s for Signal. It works, and the user called it decent, but bouncing is what a
Mac user expects there.

**Direction:** macOS stops the bounce when the app finishes launching. That happens early in
`applicationDidFinishLaunching:`, long before the launcher says ready. Find out on 10.9 what can keep
it going:
- Delay finishing launching until `ready`. Maybe run the launcher from `main()` before
  `NSApplicationMain`, or override `-[NSApplication finishLaunching]`. A question or an error still
  needs the launch window, so the app has to come up for those.
- `-[NSApp requestUserAttention:NSCriticalRequest]` bounces until cancelled, but only while the app
  is inactive, and a launched app is active.

Keep the window rules in `PortholeLaunchFeedback` unchanged. The sink's `feedbackDockProgress:` is
the one place to swap the bar for a bounce, and the bar is the fallback if bouncing can't be made
reliable.

## 8. Quiet launch: loose ends

**What's left (2026-10-06, final review of `711f2af`/`368b417`):**
- **A start with only a menu-bar item keeps the Dock bar going.** Only a real window ends Dock
  progress (`newWindowWid:`), so when 1Password starts to its menu-bar item, the bar sweeps for up
  to 10 more seconds, until the Windowless timer. Fix: `newTrayWid:` calls `[_feedback firstWindow]`
  too.
- **A second Dock click during a launch with no window shows nothing.** `applicationShouldHandleReopen:`
  calls `menuOpenMain:`, which has no session yet. Fix: a policy event that shows the launch window
  at once while the launcher hasn't said ready.
- **Untested paths that work today:** quiet → workStep schedules ShowDelay; workStep → routineStep
  before the delay keeps the pending show; ask while ShowDelay is pending shows once and cancels it.
  Add them to `viewer/tests/test_launch_feedback.m`.
- **Dead code in `PortholeDockProgress`:** the running NSTimer retains its target, so the
  `[self stop]` in `dealloc` can never run while the bar is up. It's harmless, since the app
  delegate owns the object for the app's life. A weak-proxy target would make the cleanup real.
- **`PortholeLaunchFeedback`'s `watch` has no `_preparing` guard,** so "a prepare never uses Dock
  progress" holds only because a prepare never says a routine step after `quiet`. Add the one-line
  guard.

## 9. One build per app: lock and prepare edge cases

**What's left (2026-10-05, final review of the ready-before-launch work):**
- **`up_lock` writes `pid` before `shown`** (`bin/porthole:195-196`). A waiter checking in between
  shows "Waiting…" over the install's own window.
- **Two waiters could both reclaim the same stale lock:** each `rm -rf`s it, then both `mkdir`.
- **`wc -l < "$1/progress"` prints an error every second** while waiting on a headless build that has
  no progress file yet (`bin/porthole:183`). The `2>/dev/null` comes after the `<`, which fails first.
- **An open during a prepare that then fails is dropped.** The error says opening will retry, but
  `_openAfterPrepare` is acted on only in `launchSessionPrepared:`.
- **Cmd-Q during a prepare exits 0,** so the install log says "prepared", and the launcher keeps
  running.
- **The Restart to Update test has no upper time bound** (`viewer/tests/test_update_item.m`, the
  `PortholeRestartCommand` case): a hang would stall the suite instead of failing it.

## 10. Old xpra/menu bridges pile up

**What happens:** on 2026-10-05, `ps` showed two generations of 1Password `s6-ipcserverd` bridges,
from Oct 2 16:57 and from Oct 4 14:29, still running beside the current ones. A launch starts new
bridges whenever its pidfile check (`$TMPDIR/<slug>-xpra-tunnel.<port>.pid`) fails, removes the
socket, and never stops whatever was serving it before.

**Direction:** find what clears or invalidates the pidfile without stopping its process: the
recovery watcher's `RW_STOP_PIDS`, a different `TMPDIR`, a pid reused by another process. Then make a
new bridge replace the old one rather than add to it.

## 11. A failed base-image download says only "couldn't start its Linux container"

**What happens:** on 2026-10-05 a test pkg named a base tag that didn't exist (`20260802.15`).
Each app's install-time prepare stopped at "Downloading the Linux runtime" → "Building (1/13)" →
"Linux 1Password: couldn't start its Linux container." That message names neither the download nor
the missing image. The system log marks (`up: building image`, `up: done (1)`) were the only
clue.

**Direction:** when `_pull_base` fails, say that the Linux runtime couldn't be downloaded, and name
the image, rather than falling through to the build's generic failure.

## 12. Leftover mentions of the removed staleness nudge (in mavergreen-1password)

`81125ee` removed the launcher's staleness nudge, but mavergreen-1password still talks about it:
`1password.conf:18` ("staleness nudge is the honest policy") and `bin/op`'s header comment ("nudges
about staleness/xpra"). Correct them in that repo.

## 13. CI never runs the viewer's unit tests

**What happens:** `release.yml` builds only the `Porthole`, `porthole-updater` and `transport`
targets, and runs `run-repo-tests.sh`, which runs `tests/*.bats` and `tests/*.sh`. So none of
`viewer/tests/*.m`, registered with CTest in `viewer/CMakeLists.txt`, are built or run in CI. That
covers `launch_feedback`, `dock_progress`, `launch_wire`, `launch_window`, `protocol`, the menu
tests and the others. Seen in run 37504866218 (2026-10-06): its log has no CTest step, and only the
app's objects get compiled. Since then they have run only on a developer's Mac. Here, CMake can't
configure, so they're compiled by hand with the system clang.

**Direction:** build everything (or the test targets) and run `shipyard-ctest` in the build job,
for example `run-repo-tests.sh <ctest-preset>` or a separate step after the build. Check that each
test runs headless on the arm64 runner under Rosetta: they're x86_64 binaries, and some create
`NSApplication`.
