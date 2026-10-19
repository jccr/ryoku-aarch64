# shellcheck shell=bash
# pacman helpers. makepkg always runs unprivileged; build deps and results go
# in through sudo pacman (makepkg's own auth re-prompted on every package).

# One password prompt, then keep the timestamp fresh: builds and the deploy
# outlast sudo's 5-minute cache. The refresher dies with ryoku-arm.
sudo_begin() {
  dry && return 0
  sudo -v || die "sudo is required"
  # detached from stdout/stderr: a $(ryoku-arm ...) or a pipe would otherwise
  # wait on it until its next wake-up
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) >/dev/null 2>&1 &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT
}

# Names your sync repos carry, into the assoc array named by $1.
repo_index() { # arrayname
  local -n _idx=$1; local n
  while IFS= read -r n; do _idx[$n]=1; done < <(pacman -Slq 2>/dev/null)
}

satisfied() { pacman -T "$1" >/dev/null 2>&1; }   # installed, or provided

# Install what is missing from a want-list. Split into missing (in your repos)
# and unavailable (reported, never forced). -Syu, not -S: never a partial
# upgrade against a refreshed database.
install_missing() { # label names...
  local label=$1; shift
  local -A have=(); repo_index have
  ((${#have[@]})) || { warn "pacman -Slq returned nothing; skipped $label"; return 1; }
  local p missing=() unavailable=()
  for p in "$@"; do
    satisfied "$p" && continue
    if [[ -n ${have[$p]:-} ]]; then missing+=("$p"); else unavailable+=("$p"); fi
  done
  ((${#unavailable[@]})) && warn "$label not in your repos (skipped): ${unavailable[*]}"
  if ((${#missing[@]} == 0)); then say "$label: all $# installed"; return 0; fi
  say "$label: installing ${#missing[@]}: ${missing[*]}"
  run sudo pacman -Syu --needed --noconfirm "${missing[@]}"
}

# Build one of Ryoku's arch=any packages from its PKGBUILD on origin/<channel>
# when it is missing or its version moved.
build_any() { # pkg
  local p=$1 want have work log deps=()
  want="$(pkgbuild_field "$p" pkgver | head -1)-$(pkgbuild_field "$p" pkgrel | head -1)"
  [[ $want != - ]] || { warn "$p: no PKGBUILD on origin/$CHANNEL"; return 0; }
  # pacman -Q fails for a package not installed yet: keep set -e out of it
  have=$(pacman -Q "$p" 2>/dev/null | awk '{print $2}' | sed 's/^[0-9]*://') || have=""
  [[ $have == "$want" ]] && return 0
  say "building $p $want${have:+ (installed $have)}"
  dry && { echo "  DRY: makepkg $p, then sudo pacman -U"; return 0; }
  work="$CACHE/pkgs"; log="$work/$p.log"
  rm -rf "${work:?}/$p"; mkdir -p "$work"
  git -C "$(repo)" archive "origin/$CHANNEL" "release/packages/$p" | tar -x -C "$work" \
    && mv "$work/release/packages/$p" "$work/$p" && rm -rf "$work/release"
  mapfile -t deps < <(pkgbuild_field "$p" depends makedepends | sed 's/[<>=].*//' | grep . || true)
  # shellcheck disable=SC2024  # the log is the user's file
  if ((${#deps[@]})) && ! sudo pacman -S --needed --noconfirm --asdeps "${deps[@]}" >"$log" 2>&1; then
    warn "$p: build deps failed; see $log"; return 0
  fi
  if ( cd "$work/$p" && makepkg -cf --noconfirm ) >>"$log" 2>&1; then
    # shellcheck disable=SC2024
    sudo pacman -U --noconfirm "$work/$p"/*.pkg.tar.* >>"$log" 2>&1 || warn "$p did not install; see $log"
  else
    warn "$p did not build (non-fatal); see $log"
  fi
}
