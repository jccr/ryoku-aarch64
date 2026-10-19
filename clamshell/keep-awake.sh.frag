# ryoku-aarch64 keep-awake begin (laid by ryoku-arm lid; see its README)
# Keep awake (the bar/quick-settings toggle, ryoku-cmd-caffeine) holds an
# idle:sleep inhibitor, but logind ignores a user's own inhibitors when that
# user asks to suspend, so Ryoku's lid suspend went straight through it. While
# Keep awake is on, a non-docked lid close locks the session and turns the
# display off instead; the matching open turns it back on.
KEEP_AWAKE_STATE="${RYOKU_CLAMSHELL_KEEP_AWAKE_STATE:-$RUNTIME_DIR/ryoku-clamshell-${UID:-$(id -u)}.keep-awake}"
keep_awake_on() { command -v ryoku-cmd-caffeine >/dev/null 2>&1 && ryoku-cmd-caffeine status >/dev/null 2>&1; }
keep_awake_close() {
  (umask 077; : >"$KEEP_AWAKE_STATE")
  log "Keep awake is on: lid closed, locking and turning the display off instead of suspending"
  timeout 5 ryoku-shell lock >/dev/null 2>&1 || log "Keep awake: could not lock the session" >&2
  [[ -n $ryoku_bin && -x $ryoku_bin ]] &&
    RYOKU_WM_CALL_TIMEOUT="$WM_CALL_TIMEOUT" "$ryoku_bin" wm act output.power off >/dev/null 2>&1 ||
    log "Keep awake: could not turn the display off" >&2
  return 0
}
keep_awake_open() {
  [[ -e $KEEP_AWAKE_STATE ]] || return 0
  rm -f "$KEEP_AWAKE_STATE"
  [[ -n $ryoku_bin && -x $ryoku_bin ]] &&
    RYOKU_WM_CALL_TIMEOUT="$WM_CALL_TIMEOUT" "$ryoku_bin" wm act output.power on >/dev/null 2>&1 ||
    log "Keep awake: could not turn the display back on" >&2
  return 0
}
# ryoku-aarch64 keep-awake end
