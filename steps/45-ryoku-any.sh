# shellcheck shell=bash
step ryoku-any optional "build Ryoku's arch=any and source-portable packages (fonts, gpk, prowl)" sudo

step_ryoku_any() {
  need_repo
  local p
  for p in $(read_list ryoku-any); do build_any "$p"; done
  for p in $(read_list ryoku-ported); do build_any "$p" --ignorearch; done
}
