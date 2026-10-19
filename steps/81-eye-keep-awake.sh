# shellcheck shell=bash
step eye-keep-awake optional "the bar's eye icon toggles Keep awake (idle and lid)"

# Ryoku has two "stay awake" controls that look alike. Keep awake (quick
# settings, ryoku-cmd-caffeine) holds a systemd idle:sleep inhibitor, so the
# keep-awake-lid step can see it and hold a lid close awake. The bar's eye
# icon (IdleInhibitorWidget) only maps a Wayland idle inhibitor inside the
# shell: idle timers stop, nothing else can see it, and a lid close still
# sleeps. This makes the eye a Keep awake toggle: same state, same inhibitor,
# so one control covers idle and the lid.
#
# The deployed widget is laid from the checkout on every deploy. The step
# renders it from the checkout's copy, with four marked substitutions when the
# choice is on and unchanged when off, and replaces the deployed file only when
# that differs. If Ryoku reshapes the widget, the step skips with a warning.
EYE_REL=modules/bar/barstyles/qsbar/modules/IdleInhibitorWidget.qml
EYE_DST=$CFG/quickshell/shell/$EYE_REL

eye_src() { echo "$(repo)/ryoku/shell/quickshell/shell/$EYE_REL"; }

# The checkout's widget with the eye pointed at Keep awake. Fails (status 3)
# unless all four anchors were found.
eye_render() { # src -> stdout
  local m='// ryoku-aarch64 eye-keep-awake' out
  out=$(sed \
    -e "s|^import Ryoku.Ui.Singletons\$|&\nimport shell.services $m|" \
    -e "s|^\(\( *\)readonly property bool on: \)root\.idleInhibited\$|\1Toggles.keepAwake $m|" \
    -e "s|^\( *readonly property string tooltipText: \)on ? I18n.tr(\"Idle inhibited: ON\") : I18n.tr(\"Idle inhibited: OFF\")\$|\1I18n.tr(\"Keep awake\") + \": \" + (on ? I18n.tr(\"On\") : I18n.tr(\"Off\")) $m|" \
    -e "s|^\( *onClicked: { tip.hide(); \)root\.idleInhibited = !root\.idleInhibited }\$|\1Toggles.toggleCaffeine() } $m|" \
    "$1")
  [[ $(grep -c "$m" <<<"$out") -eq 4 ]] || return 3
  printf '%s\n' "$out"
}

step_eye_keep_awake() {
  need_repo
  local src dst=$EYE_DST tmp rc=0
  src=$(eye_src)
  [[ -f $src && -f $dst ]] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/ryoku-arm-eye.XXXXXX")
  if on eye_keep_awake; then
    eye_render "$src" > "$tmp" || rc=$?
    if ((rc == 3)); then
      warn "Ryoku's eye icon widget changed; it still only blocks idle (skipped)"
      rm -f "$tmp"; return 0
    fi
  else
    cp "$src" "$tmp"
  fi
  if cmp -s "$tmp" "$dst"; then rm -f "$tmp"; return 0; fi
  if dry; then echo "  DRY: rewrite $(tilde "$dst")"; rm -f "$tmp"; return 0; fi
  replace_file "$tmp" "$dst"
  if on eye_keep_awake; then say "the bar's eye icon now toggles Keep awake"; else say "the bar's eye icon is idle-only again"; fi
  restart_shell_if_live
}
