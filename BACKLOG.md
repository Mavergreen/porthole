# Backlog

Work worth doing that is not worth interrupting something else to do. Each entry carries the
**evidence**, not just the conclusion. Delete an entry when it lands.

---

## 1. A progress window for launch-time setup, not a string of notifications

**Want:** when a Linux app launches and has setup or updates to do (pull a base, build its image,
recreate its container), the app shows one window with a progress bar and what it is doing, until
its real window is up.

**Why (2026-09-24):** today the launcher posts one Mac notification per Dockerfile step ("Setting
up… Step 4/7") via `notify()` in `templates/launcher.tmpl` and `_notify` in `bin/porthole` up. A
first launch or a post-upgrade rebuild takes minutes (a ~1.4G base pull, then the app's layer), and
a pile of notifications neither shows progress nor says "still working". A failure lands as a modal
dialog with a stderr tail, which is right, but should appear in the same window.

**Notes:** the engine binary (Contents/MacOS/Porthole) is already the app's process, so it could
host the window and have the launcher stream progress into it (docker's build/pull output). Pull
progress needs `docker pull` run separately before the build, since classic `docker build` output
doesn't show layer download progress.

## 2. Every Porthole release forces every app to re-pull the base and rebuild

**What happens:** the base image is tagged with the Porthole version, and materialize writes
`FROM …porthole-base:<version>`. So any Porthole release, even one that doesn't touch `base/`,
changes every app's recipe fingerprint. On next launch each app downloads ~1.4G, rebuilds, and
recreates its container, which relocks 1Password. On 2026-09-24 that happened three times in one
afternoon (.7, .9, .10) and filled the 18G Docker VM once (fixed since, `df9c39f`).

**Direction:** tag the base by a hash of its inputs (base/Dockerfile, the menu daemon, the fonts
conf, the xpra pin), so the tag changes only when the base does. Needs a decision on the tag scheme
before building (see the family's version conventions).

## 3. Re-materializing puts the penguin icon back for good

`porthole materialize` (now run by every Porthole and preset install) rewrites the bundle with the
penguin `AppIcon.icns`, but the launcher's "real icon already extracted" marker lives in
`~/.config/porthole/<slug>/icon-done`, so it never extracts again. Also the bundle is root-owned
(installed by a pkg), so the launcher, running as the user, probably can't write the icon anyway.
Key the check on the bundle's icon itself (is it still the penguin?) and find a writable home for
it.

## 4. Signal's menu bar icon looks terrible

Reported 2026-09-24 on Linux Signal Desktop: the tray icon the app forwards (xpra `new-tray`, 16x16)
renders badly in the Mac menu bar. See also the deferred 1Password glyph work (deriving a monochrome
template image from a forwarded color icon failed; drawing our own was the likely way forward).
