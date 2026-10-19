# shellcheck shell=bash
step asahi-desktop optional "asahi-desktop-meta: speaker safety, asahi-audio, Vulkan" sudo

# Asahi's hardware support for a desktop, not a desktop environment:
# speakersafetyd (protects the speakers), asahi-audio/bankstown, the Asahi
# Vulkan drivers, widevine, startup-disk. After the desktop so its own deps
# are settled first.
step_asahi_desktop() {
  on asahi_desktop && is_asahi || return 0
  pacman -Qq asahi-desktop-meta >/dev/null 2>&1 && return 0
  if ! pacman -Si asahi-desktop-meta >/dev/null 2>&1; then
    warn "asahi-desktop-meta not in your repos; skipped"; return 0
  fi
  say "installing asahi-desktop-meta"
  run sudo pacman -Syu --needed --noconfirm asahi-desktop-meta
}
