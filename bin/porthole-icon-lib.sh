# porthole-icon-lib.sh -- measure, convert, choose and log app icons. Sourced, never run; every
# function returns a status and never exits, because icons are best-effort everywhere they're used.

icon_width() {
  _iw=$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/{print $2}')
  printf '%s\n' "${_iw:-0}"
}

icon_is_png() {
  [ "$(head -c 8 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ]
}

# Only representations no larger than the source, so an .icns's largest representation is the
# source's real size and "largest wins" can't be fooled by an upscale.
icon_png_to_icns() {
  _src=$1 _out=$2
  _w=$(icon_width "$_src")
  [ "$_w" -gt 0 ] 2>/dev/null || return 1
  mkdir -p "$(dirname "$_out")" || return 1
  _set=$(mktemp -d "${TMPDIR:-/tmp}/porthole-icon.XXXXXX") || return 1
  mkdir "$_set/icon.iconset"
  for _s in 16 32 128 256 512; do
    if [ "$_s" -le "$_w" ]; then
      sips -z "$_s" "$_s" "$_src" --out "$_set/icon.iconset/icon_${_s}x${_s}.png" >/dev/null 2>&1
    fi
    if [ $((_s * 2)) -le "$_w" ]; then
      sips -z $((_s * 2)) $((_s * 2)) "$_src" --out "$_set/icon.iconset/icon_${_s}x${_s}@2x.png" >/dev/null 2>&1
    fi
  done
  # iconutil insists the output name ends in .icns; the temp sits beside OUT so the mv is atomic.
  _tmp="${_out%.icns}.tmp.$$.icns"
  _rc=1
  if iconutil -c icns "$_set/icon.iconset" -o "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$_out" && _rc=0
  fi
  rm -rf "$_set" "$_tmp"
  return $_rc
}

icon_best() {
  _best= _bw=0
  for _f in "$@"; do
    [ -f "$_f" ] || continue
    _fw=$(icon_width "$_f")
    if [ "$_fw" -gt "$_bw" ]; then _best=$_f; _bw=$_fw; fi
  done
  printf '%s' "$_best"
}

icon_log() {
  logger -t porthole "$1: $2" 2>/dev/null || true
}
