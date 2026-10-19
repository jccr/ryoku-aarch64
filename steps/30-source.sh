# shellcheck shell=bash
step source critical "clone or fetch the Ryoku checkout, on a real branch"

step_source() {
  local dir
  dir=$(repo)
  if ! have_repo; then
    say "cloning Ryoku ($CHANNEL) into $(tilde "$dir")"
    run mkdir -p "${dir%/*}"
    run git clone --depth 1 --branch "$CHANNEL" https://github.com/Ryoku-dev/ryoku.git "$dir"
    return 0
  fi
  ensure_branch
  fetch_upstream
  # Before the first deploy nothing else moves the checkout; afterwards
  # `ryoku update` fast-forwards it itself (the desktop step).
  if ! ryoku_deployed; then
    run git -C "$dir" checkout -q -B "$CHANNEL" "origin/$CHANNEL"
  fi
}
