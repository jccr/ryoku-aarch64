# shellcheck shell=bash
# Marker-delimited blocks the port adds to files it does not own, so each
# change is idempotent, findable, and removable:
#   <comment> ryoku-aarch64 <name> begin ... <comment> ryoku-aarch64 <name> end
# plus single lines tagged "<comment> ryoku-aarch64 <name>" at the end.

block_begin() { printf '%s ryoku-aarch64 %s begin' "$1" "$2"; }   # comment name
block_end()   { printf '%s ryoku-aarch64 %s end' "$1" "$2"; }

# Remove every block and tagged line for name from file (in place).
block_strip() { # file comment name
  local b e
  b=$(block_begin "$2" "$3"); e=$(block_end "$2" "$3")
  sed -i -e "\\|$b|,\\|$e|d" -e "\\|$2 ryoku-aarch64 $3\$|d" "$1"
}

# Print the current block for name (empty when none).
block_get() { # file comment name
  [[ -f $1 ]] || return 0
  sed -n "\\|^$(block_begin "$2" "$3")|,\\|^$(block_end "$2" "$3")\$|p" "$1"
}

# Set file's trailing block for name to the text on stdin, or remove it when
# stdin is empty. Returns 0 when the file changed, 1 when it was current.
block_set_trailing() { # file comment name
  local f=$1 want have tmp
  want=$(cat)
  have=$(block_get "$f" "$2" "$3")
  [[ $have == "$want" ]] && return 1
  dry && { echo "  DRY: rewrite the ryoku-aarch64 $3 block in $(tilde "$f")"; return 0; }
  mkdir -p "${f%/*}"; touch "$f"
  tmp=$(mktemp "${f%/*}/.ryoku-arm.XXXXXX")
  cp -p "$f" "$tmp"; block_strip "$tmp" "$2" "$3"
  if [[ -n $want ]]; then
    { [[ -s $tmp && -n $(tail -c1 "$tmp") ]] && echo; echo; printf '%s\n' "$want"; } >> "$tmp"
  fi
  replace_file "$tmp" "$f"
}
