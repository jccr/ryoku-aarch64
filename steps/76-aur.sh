# shellcheck shell=bash
step aur optional "Ryoku's AUR set that builds on aarch64, via yay" sudo

# system/packages/aur.packages, installed after the desktop like
# ryoku-shell-installer's stepAUR: bootstrap yay-bin, then build each package
# best-effort. Each one's PKGBUILD arch=() decides, so x86-only entries
# (nvibrant-bin, pam-fprint-grosshack) are skipped without a hand-kept list.

ensure_yay() {
  command -v yay >/dev/null && return 0
  say "bootstrapping yay (AUR helper)"
  dry && { echo "  DRY: build yay-bin from the AUR, sudo pacman -U"; return 0; }
  local tmp; tmp=$(mktemp -d)
  if git clone --quiet --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
     && ( cd "$tmp/yay-bin" && makepkg -cf --noconfirm >/dev/null ) \
     && sudo pacman -U --noconfirm "$tmp"/yay-bin/yay-bin-*.pkg.tar.*; then
    rm -rf "$tmp"; return 0
  fi
  rm -rf "$tmp"; warn "could not bootstrap yay"; return 1
}

# 0 builds on aarch64/any, 1 x86-only, 2 not in the AUR. The AUR API has no
# architecture field, and `yay -Gp` finds no PKGBUILD for a split package
# (ttf-fraunces-variable, pkgbase fraunces-font): the RPC gives the
# PackageBase, a shallow clone of it gives the PKGBUILD, and arch=() decides.
aur_arch_ok() { # pkg
  local base dir arch cache=$CACHE/aur
  base=$(curl -fsS --max-time 20 "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=$1" 2>/dev/null \
    | jq -r '.results[0].PackageBase // empty' 2>/dev/null) || base=""
  [[ -n $base ]] || return 2
  dir="$cache/$base"
  rm -rf "$dir"; mkdir -p "$cache"
  git clone --quiet --depth 1 "https://aur.archlinux.org/$base.git" "$dir" 2>/dev/null || return 0
  arch=$(sed -n 's/^arch=//p' "$dir/PKGBUILD" 2>/dev/null | head -1) || arch=""
  [[ -n $arch ]] || return 0                  # unparseable: let the build decide
  [[ $arch =~ (^|[^a-z0-9_])(aarch64|any)([^a-z0-9_]|$) ]]
}

step_aur() {
  on aur || return 0
  need_repo
  local want=() p rc todo=() noarch=() gone=() failed=()
  mapfile -t want < <(read_list upstream:aur)
  ((${#want[@]})) || { warn "could not read Ryoku's aur.packages"; return 1; }
  for p in "${want[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 && continue
    rc=0; aur_arch_ok "$p" || rc=$?
    case $rc in 0) todo+=("$p") ;; 2) gone+=("$p") ;; *) noarch+=("$p") ;; esac
  done
  ((${#noarch[@]})) && say "x86-only in the AUR (skipped): ${noarch[*]}"
  ((${#gone[@]})) && warn "not in the AUR (skipped): ${gone[*]}"
  ((${#todo[@]})) || return 0
  say "Ryoku AUR packages to install (${#todo[@]}): ${todo[*]}"
  ensure_yay || return 1
  for p in "${todo[@]}"; do
    # one at a time and best-effort, as Ryoku's installer does
    run yay -S --needed --noconfirm --sudoloop "$p" || failed+=("$p")
  done
  ((${#failed[@]} == 0)) || { warn "did not build: ${failed[*]} (retry: yay -S ${failed[*]})"; return 1; }
}
