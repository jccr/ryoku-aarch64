# shellcheck shell=bash
step services optional "enable bluetooth, rtkit and power-profiles-daemon"

# What Ryoku's ISO enables, minus NetworkManager: switching network managers
# would cut an SSH session and override how this machine already gets online.
step_services() {
  local unit
  for unit in bluetooth.service rtkit-daemon.service power-profiles-daemon.service; do
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || continue
    systemctl is-enabled --quiet "$unit" 2>/dev/null && continue
    say "enabling $unit"
    run sudo systemctl enable --now "$unit" || warn "could not enable $unit"
  done
}
