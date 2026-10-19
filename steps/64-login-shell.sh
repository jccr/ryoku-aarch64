# shellcheck shell=bash
step login-shell optional "~/.local/bin on the login PATH; fish as the login shell"

# deploy.sh puts every Ryoku binary in ~/.local/bin; a Hyprland started from a
# TTY inherits the login shell's PATH, so the profile must carry it.
login_path() {
  local line='export PATH="$HOME/.local/bin:$PATH"' prof profiles=("$HOME/.bash_profile")
  [[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]] && profiles+=("$HOME/.zprofile")
  for prof in "${profiles[@]}"; do
    grep -qsF '.local/bin' "$prof" && continue
    say "adding ~/.local/bin to PATH in $(tilde "$prof")"
    if dry; then echo "  DRY: append $line to $prof"
    else printf '\n# added by ryoku-arm\n%s\n' "$line" >> "$prof"; fi
  done
}

login_fish() {
  on fish || return 0
  local cur
  cur=$(getent passwd "$USER" | cut -d: -f7)
  [[ $cur == */fish ]] && return 0
  # never point the login shell at a binary that is not installed and
  # registered: that locks you out of the next login
  if ! grep -qxF /usr/bin/fish /etc/shells; then
    warn "fish is not installed (or not in /etc/shells); keeping $cur"; return 0
  fi
  say "switching your login shell to fish (was $cur; undo: sudo usermod -s $cur $USER)"
  run sudo usermod -s /usr/bin/fish "$USER"
}

step_login_shell() {
  login_path
  login_fish
}
