# shellcheck shell=bash
# Paths and machine facts every step shares. ARM_DIR (this checkout of the
# port, set by ryoku-arm) is where data files and fragments are read from.

SHARE=${RYOKU_ARM_SHARE:-${XDG_DATA_HOME:-$HOME/.local/share}/ryoku-aarch64}
CFG=${XDG_CONFIG_HOME:-$HOME/.config}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/ryoku-aarch64
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/ryoku-aarch64
BIN=$HOME/.local/bin
CHANNEL=main

# Ryoku's tools call each other by bare name (ryoku-hub -> ryoku-wm-hyprland),
# so ~/.local/bin must be on PATH for the deploy and everything after it.
[[ ":$PATH:" == *":$BIN:"* ]] || export PATH="$BIN:$PATH"

is_apple() { grep -qa apple "${RYOKU_ARM_DT_COMPAT:-/proc/device-tree/compatible}" 2>/dev/null; }
is_asahi() { is_apple || pacman -Qq linux-asahi >/dev/null 2>&1; }
is_laptop() { command -v ryoku-clamshell >/dev/null 2>&1 && ryoku-clamshell is-laptop >/dev/null 2>&1; }

# Ryoku is deployed once its CLI is in ~/.local/bin: from then on `ryoku
# update` (snapshots, fast-forward, deploy, doctor) owns the desktop.
ryoku_deployed() { [[ -x $BIN/ryoku ]]; }

# The lid is shut with no dock: any Hyprland reload (which a hypr config edit
# triggers) or a clamshell daemon restart would suspend the machine now.
lid_shut_undocked() {
  local s
  s=$(ryoku-clamshell status 2>/dev/null) || return 1
  grep -qx 'lid=closed' <<<"$s" && ! grep -qx 'clamshell=active' <<<"$s"
}

restart_shell_if_live() {
  if systemctl --user is-active --quiet ryoku-shell 2>/dev/null; then
    run systemctl --user restart ryoku-shell && say "restarted the Ryoku shell"
  fi
}

# Replace dst with tmp by rename (new inode): a running bash script reading
# dst keeps its old copy instead of executing a half-rewritten file.
replace_file() { # tmp dst
  chmod --reference="$2" "$1" 2>/dev/null || true
  mv -f "$1" "$2"
}
