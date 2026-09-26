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
