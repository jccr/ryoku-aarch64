#!/usr/bin/env bash
# ryoku-aarch64.sh: install the Ryoku desktop on an aarch64 Arch (Asahi ALARM)
# box. A bootstrap only: it gets git, clones this port to
# ~/.local/share/ryoku-aarch64, puts ryoku-arm on your PATH, and runs
# `ryoku-arm install` with the same arguments. Safe to re-run; so is the
# install itself (every step checks before it acts).
#
#   curl -fsSLO https://raw.githubusercontent.com/jccr/ryoku-aarch64/main/ryoku-aarch64.sh
#   bash ryoku-aarch64.sh --dry-run     # the plan, changes nothing
#   bash ryoku-aarch64.sh [choices]     # e.g. --no-sddm --no-aur; see: ryoku-arm help
set -euo pipefail

share=${RYOKU_ARM_SHARE:-${XDG_DATA_HOME:-$HOME/.local/share}/ryoku-aarch64}
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $(uname -m) == aarch64 ]] || die "this is for aarch64; on x86_64 use Ryoku's own installer"
[[ $EUID -ne 0 ]] || die "run as your normal user; sudo is used where needed"

if ! command -v git >/dev/null; then
  [[ " $* " == *" --dry-run "* ]] && die "git is needed even for --dry-run: sudo pacman -S git"
  sudo pacman -S --needed --noconfirm git
fi
if [[ -d $share/.git ]]; then
  git -C "$share" pull --quiet --ff-only || echo "  ! could not update $share; using it as is" >&2
else
  git clone --quiet --depth 1 https://github.com/jccr/ryoku-aarch64.git "$share"
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$share/ryoku-arm" "$HOME/.local/bin/ryoku-arm"
exec "$share/ryoku-arm" install "$@"
