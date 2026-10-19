# shellcheck shell=bash
step keep-awake-lid optional "while Keep awake is on, a lid close locks and blanks instead of sleeping"

# Ryoku's Keep awake toggle (bar and quick settings, ryoku-cmd-caffeine) holds
# a systemd idle:sleep inhibitor, but logind skips a user's own inhibitors when
# that same user asks to suspend, and the lid policy (ryoku-clamshell ->
# ryoku-shell suspend -> login1 Suspend) runs as you: a lid close slept anyway.
# ryoku-clamshell has no hook, so fragments/clamshell/keep-awake.sh.frag goes
# inline into the deployed copy, plus one hook line at the top of
# suspend_while_closed (every lid-driven suspend: the close edge, the
# startup/reload sync, the daemon's undock-while-shut path) and one in
# cancel_current_suspend (both open paths). deploy.sh re-lays the script on
# every update; this step runs after it.
KA_CLAMSHELL=${RYOKU_ARM_CLAMSHELL:-$BIN/ryoku-clamshell}

ka_render() { # src -> stdout: src stripped, plus the fragment when wanted
  local frag=$ARM_DIR/fragments/clamshell/keep-awake.sh.frag t
  t=$(mktemp); cp "$1" "$t"; block_strip "$t" "#" keep-awake
  if on keep_awake_lid; then
    if ! grep -q '^suspend_while_closed() {$' "$t" || ! grep -q '^cancel_current_suspend() {$' "$t"; then
      rm -f "$t"; return 3
    fi
    awk -v frag="$frag" -v m="# ryoku-aarch64 keep-awake" '
      /^suspend_while_closed\(\) \{$/ {
        while ((getline l < frag) > 0) print l; close(frag)
        print; print "  if keep_awake_on; then keep_awake_close; return 0; fi  " m; next }
      /^cancel_current_suspend\(\) \{$/ { print; print "  keep_awake_open  " m; next }
      { print }' "$t"
  else
    cat "$t"
  fi
  rm -f "$t"
}

step_keep_awake_lid() {
  local f=$KA_CLAMSHELL tmp rc=0
  [[ -f $f ]] || return 0
  "$f" is-laptop >/dev/null 2>&1 || return 0
  tmp=$(mktemp "${f%/*}/.ryoku-clamshell.XXXXXX")
  ka_render "$f" > "$tmp" || rc=$?
  if ((rc == 3)); then
    warn "ryoku-clamshell changed upstream (no suspend_while_closed/cancel_current_suspend); skipped"
    rm -f "$tmp"; return 0
  fi
  bash -n "$tmp" || { warn "patched ryoku-clamshell failed bash -n; left it unchanged"; rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  if dry; then echo "  DRY: patch $(tilde "$f") for Keep awake"; rm -f "$tmp"; return 0; fi
  # rename, never rewrite in place: the running daemon is reading this script
  replace_file "$tmp" "$f"
  if on keep_awake_lid; then say "ryoku-clamshell: Keep awake now holds a lid close awake (lock + display off)"
  else say "ryoku-clamshell: removed the Keep awake lid change"; fi
  # Lid edges run the new file at once. The daemon (undock-while-shut path)
  # needs a restart, which briefly hands the lid back to logind: only when open.
  systemctl --user is-active --quiet ryoku-clamshell.service 2>/dev/null || return 0
  if lid_shut_undocked; then
    warn "lid is closed: the clamshell daemon picks this up at its next restart (login, or ryoku-arm debug step keep-awake-lid with the lid open)"
  else
    systemctl --user restart ryoku-clamshell.service && say "restarted the clamshell daemon"
  fi
}
