# shellcheck shell=bash
step asahi-fixes optional "upstream Asahi fixes not yet released" sudo

# Each fix is the exact upstream change, so a fixed package release overwrites
# it with identical content.
#
# asahi-audio <= v5.0 labels each Mac's processed mic output "AUX0".
# Quickshell's level meter (the quick-settings mic row) can't map AUX0 to its
# stereo capture stream and drops every buffer with "pipewire.peak ... missing
# channels", flooding the shell log. Upstream ab1b469 (2026-10-07, unreleased)
# makes it MONO.
ASAHI_MIC_RE='"audio.position":[[:space:]]*\[[[:space:]]*"AUX0"[[:space:]]*\]'

step_asahi_fixes() {
  is_apple || return 0
  local files=()
  mapfile -t files < <(grep -lE "$ASAHI_MIC_RE" /usr/share/asahi-audio/*/mic*.json 2>/dev/null || true)
  ((${#files[@]})) || return 0
  say "asahi-audio mic fix (AUX0 -> MONO, upstream ab1b469) on ${#files[@]} file(s)"
  run sudo sed -i -E "s/$ASAHI_MIC_RE/\"audio.position\": [\"MONO\"]/" "${files[@]}"
  if systemctl --user is-active --quiet wireplumber 2>/dev/null; then
    run systemctl --user restart wireplumber pipewire pipewire-pulse && say "restarted PipeWire to load it"
  fi
}
