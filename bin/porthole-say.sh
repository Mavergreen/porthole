# porthole-say.sh -- how the launcher and `porthole up` talk to the app's launch window. Sourced.
# Under the viewer (PORTHOLE_PROTOCOL=1) each message is one JSON line on stdout and answers arrive
# on stdin; otherwise text goes to stderr and a question takes its default.

json_str() {
  printf '%s' "$1" | awk 'BEGIN { ORS = ""; printf "\"" }
    { gsub(/\r/, ""); gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t")
      if (NR > 1) printf "\\n"; printf "%s", $0 }
    END { printf "\"" }'
}

_say_json() { [ "${PORTHOLE_PROTOCOL:-}" = 1 ]; }

# Messages go to fd 7, a copy of stdout taken when this library is loaded, so they reach the viewer
# even from inside $(...) -- `case $(say_ask ...)` must not swallow the question it asks.
exec 7>&1

say_step() {
  if _say_json; then printf '{"t":"step","text":%s}\n' "$(json_str "$1")" >&7; else printf '%s\n' "$1" >&2; fi
}

say_progress() {
  _say_json && printf '{"t":"progress","fraction":%s}\n' "$1" >&7
  return 0
}

say_error() {
  if _say_json; then
    printf '{"t":"error","text":%s,"detail":%s}\n' "$(json_str "$1")" "$(json_str "${2:-}")" >&7
  else
    printf '%s\n' "$1" >&2; [ -z "${2:-}" ] || printf '%s\n' "$2" >&2
  fi
}

say_ready() {
  _say_json && printf '{"t":"ready","socket":%s,"icon":%s}\n' "$(json_str "$1")" "$(json_str "${2:-}")" >&7
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
