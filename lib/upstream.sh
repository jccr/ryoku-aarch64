# shellcheck shell=bash
# The Ryoku checkout: its branch, its remote, and reading files from
# origin/<channel> without touching the working tree (deps must be read from
# what `ryoku update` is about to deploy, before it fast-forwards).

repo() { choice dir; }
have_repo() { [[ -d $(repo)/.git ]]; }
need_repo() { have_repo || die "no Ryoku checkout at $(repo) (ryoku-arm install, or --dir)"; }

# Keep the checkout on a real branch: Ryoku's updater only reconciles a
# rewritten upstream when HEAD is the channel branch, not a detached one.
ensure_branch() {
  local head
  head=$(git -C "$(repo)" symbolic-ref --short --quiet HEAD 2>/dev/null || true)
  if [[ $head != "$CHANNEL" ]]; then
    say "putting $(repo) back on branch $CHANNEL (was ${head:-detached})"
    run git -C "$(repo)" checkout -q -B "$CHANNEL"
  fi
  run git -C "$(repo)" config "branch.$CHANNEL.remote" origin
  run git -C "$(repo)" config "branch.$CHANNEL.merge" "refs/heads/$CHANNEL"
}

fetch_upstream() {
  dry && { echo "  DRY: git fetch origin $CHANNEL (reading the last fetched origin/$CHANNEL)"; return 0; }
  GIT_TERMINAL_PROMPT=0 git -C "$(repo)" fetch --quiet --no-tags origin \
    "+refs/heads/$CHANNEL:refs/remotes/origin/$CHANNEL" \
    || warn "could not reach origin; using the last fetched origin/$CHANNEL"
}

upstream_show() { git -C "$(repo)" show "origin/$CHANNEL:$1" 2>/dev/null; }

# Print PKGBUILD array fields of one of Ryoku's packages. PKGBUILDs are shell
# from the same repo deploy.sh already runs.
pkgbuild_field() { # pkg field...
  local pkg=$1; shift
  upstream_show "release/packages/$pkg/PKGBUILD" \
    | bash -c 'source /dev/stdin >/dev/null 2>&1; for f in "$@"; do eval "printf \"%s\\n\" \"\${$f[@]}\""; done' _ "$@"
}

upstream_packages() { git -C "$(repo)" ls-tree --name-only "origin/$CHANNEL:release/packages/" 2>/dev/null; }

# A package list (one name per line, # comments): from Ryoku's system/packages
# (upstream:<name>) or from this port's packages/ dir.
read_list() {
  case $1 in
    upstream:*) upstream_show "system/packages/${1#upstream:}.packages" ;;
    *) cat "$ARM_DIR/packages/$1.packages" 2>/dev/null ;;
  esac | sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep . || true
}
