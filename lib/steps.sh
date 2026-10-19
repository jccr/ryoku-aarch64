# shellcheck shell=bash
# The step registry and runner. Each steps/NN-name.sh file registers itself
# with `step name kind "doc"` and defines step_<name> (dashes as underscores).
# The NN prefix is the run order; install and update run the same list.
#
# kind: critical  a failure stops the run (later steps depend on it)
#       optional  a failure is reported at the end and the run goes on
#
# Every step must be safe to re-run: check the machine, act only on a gap.

STEPS=()
declare -A STEP_KIND=() STEP_DOC=()

step() { # name kind doc
  STEPS+=("$1"); STEP_KIND[$1]=$2; STEP_DOC[$1]=$3
}

load_steps() {
  local f
  for f in "$ARM_DIR"/steps/[0-9][0-9]-*.sh; do
    # shellcheck source=/dev/null
    source "$f"
  done
}

steps_list() {
  local s
  for s in "${STEPS[@]}"; do printf '  %-18s %-8s %s\n' "$s" "${STEP_KIND[$s]}" "${STEP_DOC[$s]}"; done
}

# Run steps in order. Each runs in a subshell with errexit on, so a failing
# command ends that step only (a function called in an `||` context would
# silently run with errexit off).
run_steps() { # names...
  local s rc failed=()
  for s in "$@"; do
    [[ -n ${STEP_KIND[$s]:-} ]] || die "unknown step: $s (ryoku-arm debug steps)"
    printf '\033[2m--- %s\033[0m\n' "$s"
    set +e
    ( set -e; "step_${s//-/_}" )
    rc=$?
    set -e
    ((rc == 0)) && continue
    if [[ ${STEP_KIND[$s]} == critical ]]; then
      die "step $s failed (exit $rc); fix it and re-run, or: ryoku-arm debug step $s"
    fi
    warn "step $s failed (exit $rc); continuing"
    failed+=("$s")
  done
  if ((${#failed[@]})); then
    warn "finished with failed steps: ${failed[*]} (retry one: ryoku-arm debug step <name>)"
    return 1
  fi
}
