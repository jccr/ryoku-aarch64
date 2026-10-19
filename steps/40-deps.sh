# shellcheck shell=bash
step deps critical "install what Ryoku's desktop PKGBUILDs and the session need"

# Read live from the checkout's PKGBUILDs (origin/<channel>, what is about to
# be deployed), so this never drifts the way a hand-kept list does; plus the
# port's packages/session.packages. Never installed whatever the PKGBUILDs
# say: Ryoku's own packages (deploy.sh builds them into ~/.local), the generic
# kernel's headers/dkms (Asahi runs linux-asahi), x86-only bits, virtual
# provides, and snapper (snapshots-setup.sh owns snapshots).
DEPS_SKIP_RE='^(linux-headers|dkms|ryoku-desktop-compositor|limine.*|asusctl|snapper)$'

wanted_deps() {
  local own p
  own=$(upstream_packages) || own=""
  for p in $(read_list desktop-pkgbuilds); do pkgbuild_field "$p" depends makedepends; done \
    | sed 's/[<>=].*//' | grep . | sort -u \
    | grep -vxF -f <(printf '%s\n' "$own") | grep -vE "$DEPS_SKIP_RE" || true
  read_list session
}

step_deps() {
  need_repo
  local want=()
  mapfile -t want < <(wanted_deps | sort -u)
  ((${#want[@]} > 20)) || die "read only ${#want[@]} dependencies from $(repo) origin/$CHANNEL; is the checkout fetched?"
  install_missing "Ryoku dependencies" "${want[@]}"
}
