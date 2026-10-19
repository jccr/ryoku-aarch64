# shellcheck shell=bash
step shell-suspend-fix optional "rebuild ryoku-shell with the suspend-after-release race fixed"

# Ryoku's lid suspend (and every other secure suspend) goes ryoku-shell ->
# login1 Suspend. ryoku-shell holds its own sleep BLOCK inhibitor and drops it
# just before calling Suspend. logind forgets a released inhibitor only when it
# dispatches the inhibitor FIFO's hang-up, at SD_EVENT_PRIORITY_IDLE-10, after
# the D-Bus calls already queued: the Suspend often still sees ryoku-shell's
# own block and is refused ("Operation denied due to active block inhibitor").
# Measured on this machine: 12 of 20 calls right after a release saw the stale
# lock; with the lid shut every lid suspend lost the race, so a closed MacBook
# locked and stayed awake.
#
# fragments/ryoku-shell/suspend-after-release.patch retries Suspend briefly
# while that is the refusal (and only then). This step builds ryoku-shell from
# the deployed checkout (HEAD) with the patch, the way deploy.sh builds it
# (`go build` in ryoku/shell/ipc), and swaps the binary in by rename. The
# checkout is never modified. deploy.sh rebuilds ryoku-shell on every update,
# so this runs after the desktop step; once upstream carries a fix it skips.
SSF_PATCH=$ARM_DIR/fragments/ryoku-shell/suspend-after-release.patch
SSF_BIN=$BIN/ryoku-shell
SSF_STATE=$STATE/ryoku-shell-fixed.sha

step_shell_suspend_fix() {
  need_repo
  ryoku_deployed && [[ -x $SSF_BIN ]] || return 0
  local have src tmp
  have=$(sha256sum < "$SSF_BIN" | cut -d' ' -f1)
  [[ -f $SSF_STATE && $(<"$SSF_STATE") == "$have" ]] && return 0   # our build is in place
  src=$CACHE/ryoku-shell-fix
  [[ -d $src ]] && chmod -R u+w "$src"
  rm -rf "$src"; mkdir -p "$src"
  git -C "$(repo)" archive HEAD ryoku/shell/ipc | tar -x -C "$src"
  if grep -q 'suspendAfterRelease' "$src/ryoku/shell/ipc/sleepwake.go"; then
    return 0                                                       # fixed upstream
  fi
  if ! git -C "$src" apply --check -p1 "$SSF_PATCH" 2>/dev/null; then
    warn "ryoku-shell's sleepwake.go changed upstream; suspend race fix not applied (lid suspend may fail)"
    return 1
  fi
  say "rebuilding ryoku-shell with the suspend race fix"
  if dry; then echo "  DRY: patch + go build ryoku/shell/ipc, replace $(tilde "$SSF_BIN")"; return 0; fi
  git -C "$src" apply -p1 "$SSF_PATCH"
  tmp=$(mktemp "$BIN/.ryoku-shell.XXXXXX")
  if ! ( cd "$src/ryoku/shell/ipc" && "${RYOKU_ARM_GO:-go}" build -o "$tmp" . ) >"$CACHE/ryoku-shell-fix.log" 2>&1; then
    rm -f "$tmp"; warn "ryoku-shell build failed; see $CACHE/ryoku-shell-fix.log"; return 1
  fi
  chmod 755 "$tmp"
  replace_file "$tmp" "$SSF_BIN"
  sha256sum < "$SSF_BIN" | cut -d' ' -f1 > "$SSF_STATE"
  # The running daemon keeps the old code until it restarts. Restarting it
  # restarts the shell; never while the session is locked or the lid is shut.
  systemctl --user is-active --quiet ryoku-shell 2>/dev/null || return 0
  if lid_shut_undocked || [[ $(timeout 3 ryoku-shell lock status 2>/dev/null) != unlocked ]]; then
    warn "ryoku-shell fix installed; it takes effect when the shell next restarts (next login)"
    return 0
  fi
  systemctl --user restart ryoku-shell && say "restarted the Ryoku shell (suspend fix live)"
}
