# Porthole for Mavericks

When there's a modern app you want to run on Mavericks, but the source code is unavailable and the macOS binary is too far gone for [Drydock](https://github.com/Mavergreen/drydock), what can you do?

Run the Linux version in Docker, that's what!

If you love Mac OS X enough to still be running Mavericks, yuck. That's not the UX you're looking for.

So wrap it up in a little purpose-specific Mac app that makes it feel as native as possible. Kinda like site-specific browsers, but for Linux apps instead of websites. "App-specific viewers", let's say.

Porthole makes those Mac apps for you.

## Usage

Install
[Container Tools for Mavericks](https://github.com/Mavergreen/container-tools/releases/latest)
and start Docker.

Then try some Porthole presets:

- [1Password](https://github.com/Mavergreen/1password/releases/latest)
- [Signal Desktop](https://github.com/Mavergreen/signal-desktop/releases/latest)

## How it works

Docker, Xpra, key remappings, clipboard sharing, menu autodiscovery, and for most apps at least a little custom code.

## Help wanted

Porthole is aiming, almost certainly quixotically, for a
[fully Mac-assed](https://daringfireball.net/linked/2020/03/20/mac-assed-mac-apps)
experience. You'll find gaps. Please
[report them](https://github.com/Mavergreen/porthole/issues).

Many popular modern apps have not yet been backported to Mavericks. Please
[suggest the ones you miss most](https://github.com/Mavergreen/porthole/issues).
Porthole will often be an expedient way to get them running, and sometimes it'll be the only way.
