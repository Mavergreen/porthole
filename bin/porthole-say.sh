# platform: host-agnostic
# porthole-say.sh -- how the launcher and `porthole up` talk to the app's launch window. Sourced.
# Under the viewer (PORTHOLE_PROTOCOL=1) each message is one JSON line on stdout and answers arrive
# on stdin; otherwise text goes to stderr and a question takes its default.

# A JSON string of $1. Invalid UTF-8 is dropped (iconv -c) and control characters other than tab and
# newline are removed, so docker's colored or truncated output can't make the line unreadable.
json_str() {
  printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null | LC_ALL=C tr -d '\000-\010\013-\037\177' |
    awk 'BEGIN { ORS = ""; printf "\"" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t")
      if (NR > 1) printf "\\n"; printf "%s", $0 }
    END { printf "\"" }'
}

_say_json() { [ "${PORTHOLE_PROTOCOL:-}" = 1 ]; }

# Messages go to fd 7, a copy of stdout taken when this library is loaded, so they reach the viewer
# even from inside $(...) -- `case $(say_ask ...)` must not swallow the question it asks.
exec 7>&1

# A build's steps and progress are also kept in $PORTHOLE_PROGRESS_FILE (porthole up sets it), so a
# launch waiting for that build can show where it has got to.
_say_keep() { [ -z "${PORTHOLE_PROGRESS_FILE:-}" ] || printf '%s\n' "$1" >> "$PORTHOLE_PROGRESS_FILE" 2>/dev/null || true; }

# A line in the system log naming the app ($PORTHOLE_LOG_NAME), so a slow launch can be timed
# afterwards from the log's timestamps. Every step shown is marked too.
say_mark() { logger -t porthole "${PORTHOLE_LOG_NAME:-porthole}: $1" 2>/dev/null || true; }

say_step() {
  say_mark "step: $1"
  _ss_line=$(printf '{"t":"step","text":%s}' "$(json_str "$1")")
  _say_keep "$_ss_line"
  if _say_json; then printf '%s\n' "$_ss_line" >&7; else printf '%s\n' "$1" >&2; fi
}

say_progress() {
  _say_keep "{\"t\":\"progress\",\"fraction\":$1}"
  _say_json && printf '{"t":"progress","fraction":%s}\n' "$1" >&7
  return 0
}

# Nothing to show for now: another window (an install's) is already showing this app's progress.
say_quiet() {
  _say_json && printf '{"t":"quiet"}\n' >&7
  return 0
}

say_error() {
  say_mark "error: $1"
  if _say_json; then
    printf '{"t":"error","text":%s,"detail":%s}\n' "$(json_str "$1")" "$(json_str "${2:-}")" >&7
  else
    printf '%s\n' "$1" >&2; [ -z "${2:-}" ] || printf '%s\n' "$2" >&2
  fi
}

say_ready() {  # SOCKET ICON IMAGE (the image the app's container runs)
  say_mark ready
  _say_json && printf '{"t":"ready","socket":%s,"icon":%s,"image":%s}\n' \
    "$(json_str "$1")" "$(json_str "${2:-}")" "$(json_str "${3:-}")" >&7
  return 0
}

# The app is ready to launch (--prepare): built, and nothing started.
say_prepared() {
  say_mark prepared
  _say_json && printf '{"t":"prepared"}\n' >&7
  return 0
}

say_ask() {  # ID TEXT DEFAULT CHOICE... -> prints the answer
  _aid=$1 _atext=$2 _adef=$3; shift 3
  if _say_json; then
    _ach=
    for _x in "$@"; do _ach="$_ach${_ach:+,}$(json_str "$_x")"; done
    printf '{"t":"ask","id":%s,"text":%s,"choices":[%s]}\n' "$(json_str "$_aid")" "$(json_str "$_atext")" "$_ach" >&7
    while IFS= read -r _line; do
      _lid=$(printf '%s' "$_line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
      [ "$_lid" = "$_aid" ] || continue
      _lc=$(printf '%s' "$_line" | sed -n 's/.*"choice":"\([^"]*\)".*/\1/p')
      printf '%s' "${_lc:-$_adef}"; return 0
    done
  fi
  printf '%s' "$_adef"
}
