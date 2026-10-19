# shellcheck shell=bash
step kbd-light optional "Keyboard Light on MacBooks: bar plugin + quick-settings row"

# The MacBook Air has no keyboard-brightness keys (macOS moved it to Control
# Center) and Ryoku's sidebar only has screen brightness. plugins/
# keyboard-backlight is a bar plugin with a slider; the quick-settings row is
# inserted inline into the deployed QuickSettingsHome.qml after its
# screen-brightness control (plugins cannot extend quick settings, a user_edits
# fork would freeze the whole file, and a separate .qml file is not registered
# as a type of that folder). deploy.sh re-lays the shell on every update, so
# this is re-applied after each one.
KBD_PLUGIN=keyboard-backlight

qs_home() { echo "$CFG/quickshell/shell/modules/bar/framebars/menus/quicksettings/QuickSettingsHome.qml"; }

kbd_applies() { is_apple && compgen -G '/sys/class/leds/*kbd_backlight*' >/dev/null; }

# `ryoku plugin add` refuses an installed id, so an upgrade is remove + add;
# that drops the bar placement back to the plugin's default lane.
kbd_plugin_install() {
  local dir=$ARM_DIR/plugins/$KBD_PLUGIN want have
  want=$(jq -r .version "$dir/manifest.json") || { warn "$KBD_PLUGIN: unreadable manifest"; return 1; }
  have=$(ryoku plugin list --json 2>/dev/null | jq -r --arg id "$KBD_PLUGIN" '.[]? | select(.id == $id) | .version' || true)
  [[ $have == "$want" ]] && return 0
  if [[ -n $have ]]; then
    say "upgrading plugin $KBD_PLUGIN $have -> $want"
    run ryoku plugin remove "$KBD_PLUGIN" >/dev/null
  else
    say "installing plugin $KBD_PLUGIN $want on the bar"
  fi
  run ryoku plugin add "$dir" --bar --yes
}

kbd_plugin_remove() {
  ryoku plugin list --json 2>/dev/null | grep -q "\"$KBD_PLUGIN\"" || return 0
  say "removing plugin $KBD_PLUGIN"
  run ryoku plugin remove "$KBD_PLUGIN" >/dev/null
}

# Every version of the row this port ever added (exact markers only).
qs_strip() { # file
  block_strip "$1" "//" kbd-row
  sed -i -e '/^import Quickshell\.Io \/\/ ryoku-aarch64$/d' -e '/KbdBacklightSlider {.*ryoku-aarch64/d' "$1"
}

# Rebuild the file from a stripped copy; replace it only when that differs.
# Returns 0 when the file changed.
qs_row_set() { # want(1|0)
  local home tmp frag=$ARM_DIR/fragments/quickshell/kbd-row.qml.frag awkf=$ARM_DIR/fragments/quickshell/insert-row.awk
  home=$(qs_home)
  [[ -f $home ]] || { (($1)) && warn "quick settings not found at $(tilde "$home"); row skipped"; return 1; }
  # temp copy outside the watched quickshell tree: Quickshell reloads on any
  # new file there
  tmp=$(mktemp "${TMPDIR:-/tmp}/ryoku-arm-qs.XXXXXX")
  cp -p "$home" "$tmp"; qs_strip "$tmp"
  if (($1)); then
    awk -v frag="$frag" -f "$awkf" "$tmp" "$tmp" > "$tmp.new" && cat "$tmp.new" > "$tmp"; rm -f "$tmp.new"
    if ! grep -q 'ryoku-aarch64 kbd-row begin' "$tmp" || ! grep -qE '^import[[:space:]]+Quickshell\.Io' "$tmp"; then
      warn "Ryoku's quick settings layout changed (no screen-brightness anchor); keyboard row skipped"
      rm -f "$tmp"; return 1
    fi
  fi
  if cmp -s "$tmp" "$home"; then rm -f "$tmp"; return 1; fi
  if dry; then echo "  DRY: rewrite $(tilde "$home")"; rm -f "$tmp"; return 0; fi
  replace_file "$tmp" "$home"
  if (($1)); then say "added the keyboard backlight row to quick settings"; else say "removed the keyboard row from quick settings"; fi
}

step_kbd_light() {
  kbd_applies || return 0
  local old; old="$(dirname "$(qs_home)")/KbdBacklightSlider.qml"   # left by the first, broken version
  [[ -e $old ]] && run rm -f "$old"
  if on kbd_light; then
    kbd_plugin_install
    if qs_row_set 1; then restart_shell_if_live; fi
  else
    kbd_plugin_remove
    if qs_row_set 0; then restart_shell_if_live; fi
  fi
}
