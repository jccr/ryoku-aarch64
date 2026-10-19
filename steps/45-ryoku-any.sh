# shellcheck shell=bash
step ryoku-any optional "build Ryoku's arch=any packages (cursors, UI fonts, gpk)" sudo

step_ryoku_any() {
  need_repo
  local p
  for p in $(read_list ryoku-any); do build_any "$p"; done
}
