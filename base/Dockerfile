# Porthole shared BASE image -- the app-agnostic, redistributable runtime every viewer needs:
# xpra (pinned), Xvfb, the common desktop/runtime libs, the menu daemon, and the Mac-font alias.
# NO vendor application and NO vendor icon live here -- those install from the vendor on the user's
# Mac (Porthole redistributes nothing vendor-owned). Built in CI, pushed to
# ghcr.io/mavergreen/porthole-base:<porthole-version>; per-app recipes FROM it, so the heavy
# common layer is pulled (shared across all apps) instead of rebuilt on every user's machine.
#
# Both third-party inputs are pinned where Renovate can see them: this FROM (the built-in dockerfile
# manager -- digest AND a numeric tag, so the next Debian major is proposed and not just a digest
# refresh) and XPRA_VERSION at the repo root (a custom manager on the deb datasource).

# The container side of every Porthole bridge: s6-ipcclient connects a Unix socket and s6-ioconnect
# relays it to stdin/stdout, so `docker exec -i <c> s6-ipcclient <sock> s6-ioconnect` is the whole
# relay. Built from the SAME skalibs/s6 commits as the Mac transport (SKALIBS_REF, S6_REF, passed
# by build/build-base-image.sh), so one Renovate PR moves both ends. Fetched by commit: git verifies
# the checkout hashes to it, so no separate checksum. Configured like the Mac build (build/fetch-s6.sh):
# libskarnet is linked in statically; glibc stays dynamic, and both stages FROM the same pinned
# Debian, so the copied binaries always meet the glibc they were built against.
FROM debian:13-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad AS s6
ARG SKALIBS_REF
ARG S6_REF
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && fetch() { git init -q "$1" && cd "$1" && git fetch -q --depth 1 "$2" "$3" \
         && git -c advice.detachedHead=false checkout -q "$3"; } \
    && fetch /src/skalibs https://github.com/skarnet/skalibs.git "${SKALIBS_REF:?the skalibs commit: build via build/build-base-image.sh}" \
    && ./configure --disable-shared --enable-static --prefix=/stage \
    && make -j"$(nproc)" && make install \
    && fetch /src/s6 https://github.com/skarnet/s6.git "${S6_REF:?the s6 commit: build via build/build-base-image.sh}" \
    && ./configure --enable-static --disable-shared --enable-allstatic --disable-execline \
         --with-include=/stage/include --with-lib=/stage/lib \
         --with-sysdeps=/stage/lib/skalibs/sysdeps --prefix=/stage \
    && make -j"$(nproc)" && make install

FROM debian:13-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

# The xpra pin, passed from XPRA_VERSION by build/build-base-image.sh. Deliberately no default:
# an unpinned xpra is not a base image we would ship, so the build must fail rather than float.
ARG XPRA_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg \
      dbus dbus-x11 util-linux \
      python3-dbus python3-lz4 \
      gnome-keyring libsecret-1-0 \
      at-spi2-core python3-pyatspi \
    # xpra (the display server the Porthole client speaks to) is not in Debian; pull from xpra.org
    # and PIN it -- the native client is written against a specific xpra wire protocol, so an
    # unpinned install could drift to an incompatible xpra. xpra.org's trixie repo retains old
    # versions, so the pin is stable. Renovate bumps XPRA_VERSION and it ships-if-green like any
    # other dependency; the runtime canary for a protocol break is the launcher's check_xpra_compat,
    # which compares this against what the VIEWER speaks (PortholeClient.m's hello).
    && curl -sS https://xpra.org/xpra.asc -o /usr/share/keyrings/xpra.asc \
    && echo 'deb [signed-by=/usr/share/keyrings/xpra.asc] https://xpra.org/ trixie main' \
       > /etc/apt/sources.list.d/xpra.list \
    # Pin the whole SET, not the meta-package. `apt-get install xpra=<v>` versions only `xpra`; apt
    # resolves xpra-common/-client/-server/-codecs to its own candidate, so the day xpra.org
    # published 6.5.3 the candidate collided with xpra 6.5.2's strict `Depends: ... (= 6.5.2-r0-1)`
    # and the build died in "held broken packages". Retaining old versions upstream does not help a
    # pin that names only one package. Priority 1001 beats the candidate and permits the downgrade
    # that implies; a glob with no matching version (xpra-html5, versioned on its own) is unaffected.
    && printf 'Package: xpra* python3-xpra\nPin: version %s\nPin-Priority: 1001\n' \
       "${XPRA_VERSION:?the xpra pin: build via build/build-base-image.sh, which reads XPRA_VERSION}" \
       > /etc/apt/preferences.d/xpra \
    && apt-get update \
    && apt-get install -y xpra xvfb \
    && rm -rf /var/lib/apt/lists/*

# The AT-SPI menu daemon (ours) + the Mac/CSS system-font alias (no font data). Present in every
# viewer; a per-app recipe only enables the daemon (MENU_PRODUCER) -- it does not re-ship these.
COPY porthole-menu-daemon.py /usr/local/bin/porthole-menu-daemon.py
RUN chmod 755 /usr/local/bin/porthole-menu-daemon.py
COPY mac-fonts.conf /etc/fonts/conf.d/09-mac-fonts.conf
COPY --from=s6 /stage/bin/s6-ipcclient /stage/bin/s6-ioconnect /usr/local/bin/
