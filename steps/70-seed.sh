# shellcheck shell=bash
step seed optional "lay what a checkout deploy misses; enable Ryoku's session units"

# What a packaged Ryoku box gets that a checkout's deploy.sh never lays: the
# ryoku-desktop PKGBUILD stages nvim (LazyVim), starship.toml, yazi.toml and the
# fastfetch emblem for
# `ryoku materialize`, and ryoku-shell-installer seeds wallpapers, ~/.npmrc and
# a few .desktop entries. Ryoku-owned files are refreshed only while they still
# match what was laid last time (a sha in the state dir), so a file you edited
# is never clobbered; seeds are copied only when absent.
SEED_STATE=$STATE/seeded

lay_owned() { # src dst: copy if absent, or if unchanged since we last laid it
  local src=$1 dst=$2 rec cur new
  [[ -f $src ]] || return 0
  rec="$SEED_STATE/${dst#"$HOME"/}.sha"
  new=$(sha256sum < "$src" | cut -d' ' -f1)
  if [[ -e $dst ]]; then
    cur=$(sha256sum < "$dst" | cut -d' ' -f1)
    if [[ $cur == "$new" ]]; then
      dry || { mkdir -p "${rec%/*}"; echo "$new" > "$rec"; }
      return 0
    fi
    if [[ ! -f $rec || $(cat "$rec") != "$cur" ]]; then
      warn "kept your edited $(tilde "$dst") (Ryoku's version: $src)"
      return 0
    fi
  fi
  say "laying $(tilde "$dst")"
  dry && return 0
  mkdir -p "${dst%/*}" "${rec%/*}"
  cp -f "$src" "$dst"; echo "$new" > "$rec"
}

seed_nvim() { # r
  local r=$1 f entries=()
  # LazyVim only into an empty ~/.config/nvim or one Ryoku already owns
  # (.ryoku-lazyvim marker); never over someone else's Neovim config
  [[ -d $CFG/nvim ]] && mapfile -t entries < <(find "$CFG/nvim" -mindepth 1 -maxdepth 1)
  if [[ -e $CFG/nvim && ! -f $CFG/nvim/.ryoku-lazyvim && ${#entries[@]} -gt 0 ]]; then
    return 0
  fi
  lay_owned "$r/apps/nvim/init.lua" "$CFG/nvim/init.lua"
  lay_owned "$r/apps/nvim/.ryoku-lazyvim" "$CFG/nvim/.ryoku-lazyvim"
  while IFS= read -r -d '' f; do
    lay_owned "$f" "$CFG/nvim/${f#"$r/apps/nvim/"}"
  done < <(find "$r/apps/nvim/lua" -type f -print0 2>/dev/null)
}

seed_once() { # r: installer seeds, only when absent
  local r=$1 wp=${XDG_PICTURES_DIR:-$HOME/Pictures}/Wallpapers
  if [[ ! -e $HOME/.npmrc ]]; then say "seeding ~/.npmrc"; run cp "$r/apps/npm/npmrc" "$HOME/.npmrc"; fi
  if [[ ! -d $wp || -z $(ls -A "$wp" 2>/dev/null) ]]; then
    say "seeding Ryoku's wallpapers -> $(tilde "$wp")"
    run mkdir -p "$wp"; run cp -a "$r/assets/wallpapers/." "$wp/"
  fi
}

# ryoku-session.target only starts units that are ENABLED with
# WantedBy=ryoku-session.target (ryoku-shell, ryogami, ryoku-idle,
# ryoku-clamshell). deploy.sh lays them but never enables them (the package
# and `ryoku doctor` do), so on a checkout box idle lock and lid handling
# were off.
session_units() {
  local udir=$CFG/systemd/user u units=() off=()
  [[ -d $udir ]] || return 0
  for u in "$udir"/*.service; do
    [[ -f $u ]] && grep -qE '^WantedBy=.*\bryoku-session\.target\b' "$u" && units+=("${u##*/}")
  done
  ((${#units[@]})) || return 0
  for u in "${units[@]}"; do
    [[ $(systemctl --user is-enabled "$u" 2>/dev/null) == enabled ]] || off+=("$u")
  done
  ((${#off[@]})) || return 0
  say "enabling Ryoku session units: ${off[*]}"
  run systemctl --user daemon-reload || true
  run systemctl --user enable "${off[@]}" || { warn "could not enable ${off[*]}"; return 0; }
  if systemctl --user is-active --quiet ryoku-session.target; then
    run systemctl --user start "${off[@]}" || warn "enabled; some did not start now (they will at the next login)"
  fi
}

step_seed() {
  need_repo
  local r=$(repo)/ryoku apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
  seed_nvim "$r"
  lay_owned "$r/apps/starship/starship.toml" "$CFG/starship.toml"
  lay_owned "$r/apps/yazi/yazi.toml" "$CFG/yazi/yazi.toml"
  # the readout's emblem: without it fastfetch silently draws the Arch logo
  lay_owned "$r/assets/brand/fastfetch-emblem.png" "$CFG/fastfetch/fastfetch-emblem.png"
  # launcher entries the package ships system-wide
  lay_owned "$r/apps/nvim/ryoku-nvim.desktop" "$apps/ryoku-nvim.desktop"
  lay_owned "$r/apps/tools/compress-video.desktop" "$apps/compress-video.desktop"
  lay_owned "$r/apps/tools/install-app.desktop" "$apps/install-app.desktop"
  seed_once "$r"
  if ! dry && command -v update-desktop-database >/dev/null; then
    update-desktop-database -q "$apps" 2>/dev/null || true
  fi
  session_units
}
