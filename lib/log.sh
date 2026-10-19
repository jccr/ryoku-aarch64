# shellcheck shell=bash
# Output, and the dry-run gate. Anything that changes the system goes through
# run() (or checks dry()), so --dry-run prints the plan and changes nothing.

DRY=${DRY:-0}

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
dry()  { ((DRY)); }
run()  { if dry; then printf '  DRY: %s\n' "$*"; else "$@"; fi; }

# ~ for $HOME in messages
tilde() { printf '%s' "${1/#"$HOME"/\~}"; }
