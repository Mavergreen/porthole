# Porthole for Mavericks

When there's a modern app you want to run on Mavericks, but the source code is unavailable and the macOS binary is too far gone for [Drydock](https://github.com/Mavergreen/drydock), what can you do?

Run the Linux version in Docker, that's what!

If you love Mac OS X enough to still be running Mavericks, yuck. That's not the UX you're looking for.

So wrap it up in a little purpose-specific Mac app that makes it feel as native as possible. Kinda like site-specific browsers, but for Linux apps instead of websites. "App-specific viewers", let's say.

Porthole makes those Mac apps for you.

## VM resources

Porthole runs GUI apps inside a VMware Fusion VM managed by Container Tools. The tested starting baseline is **2 GiB RAM and two vCPUs**; 4 GiB and two vCPUs offer additional headroom for heavier or concurrent use. Both Container Tools (at first create) and the launcher (each time you open an app) notify you once a day via a macOS notification if the VM falls below this baseline.

There is no established host minimum: a lightly loaded Mac can run below this baseline, but host RAM pressure, swap activity, and disk fill rate all affect smoothness.

**To adjust resources:**

1. Close any open Porthole apps.
2. Stop the Docker VM: Container Tools menu → **Stop Docker** (or `docker-machine-ctl stop`).
3. In VMware Fusion, open the **container-tools** VM settings and change Memory and Processors. Raising VM RAM also grows the VM's `.vmem` file on disk; **Start Docker** will refuse if the Mac lacks sufficient free space.
4. Verify: `docker-machine-ctl resource-status` (`source=vmx` confirms the VMX is current).
5. Start the VM: Container Tools menu → **Start Docker**.

**Container shared memory:** Porthole containers are configured with `--shm-size 512m` as an upper bound on `/dev/shm`; this does not reserve RAM. (256 MiB was tested as a reference value.) Changing this limit requires stopping and recreating the container while keeping its named volumes — an intentional step you control. Moving a monitor between displays does not restart apps.

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
