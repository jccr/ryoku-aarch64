# shellcheck shell=bash
step desktop critical "deploy the desktop: deploy.sh the first time, then ryoku update" sudo

# UPDATE_ARGS (ryoku-arm update's pass-through, e.g. --system) go to `ryoku
# update`, which snapshots, fast-forwards the checkout, redeploys and runs the
# doctor. A first install has no ryoku CLI yet, so it runs deploy.sh directly.
UPDATE_ARGS=()

step_desktop() {
  need_repo
  # Outside a session Ryoku guesses the compositor from an existing
  # ~/.config/hypr; a first run has none ("no compositor payload for none").
  # RYOKU_WM is the override its detector checks first.
  export RYOKU_WM=${RYOKU_WM:-hyprland}
  if ryoku_deployed; then
    say "updating the desktop: ryoku update${UPDATE_ARGS[*]:+ ${UPDATE_ARGS[*]}}"
    run ryoku update "${UPDATE_ARGS[@]}"
    return
  fi
  local mode=--no-reload
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && mode=
  # upstream deploy.sh copies config.fish without creating the dir first; on
  # an account where fish never ran that aborts the deploy
  run mkdir -p "$CFG/fish"
  say "building and deploying the desktop (several minutes)"
  run bash "$(repo)/ryoku/shell/deploy.sh" $mode
}
