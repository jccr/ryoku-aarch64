# shellcheck shell=bash
step apps optional "Ryoku's preinstalled apps (base + dev lists) your repos carry" sudo

# Ryoku's preinstalled set (docs/preinstalled.md) is system/packages/
# base.packages (system + apps) and dev.packages (toolchains).
# hardware.packages (x86 GPU drivers, microcode) and aur.packages (the aur
# step) are not read. Never installed whatever the lists say: the generic
# kernel and headers (Asahi boots linux-asahi), the Limine/initramfs/boot chain
# and snapshot stack (snapshots-setup.sh), and network managers (switching
# would change how this machine gets online).
APPS_SKIP_RE='^(base|base-devel|linux|linux-firmware|linux-headers|linux-.*-headers|dkms|mkinitcpio|sudo|btrfs-progs|cryptsetup|dosfstools|efibootmgr|limine.*|plymouth|snapper|snap-pac|networkmanager|iwd|wpa_supplicant|xpadneo-dkms|broadcom-.*|.*-ucode)$'

step_apps() {
  on apps || return 0
  need_repo
  local want=() repo_apps=() any=() a
  mapfile -t want < <({ read_list upstream:base; read_list upstream:dev; } | sort -u | grep -vE "$APPS_SKIP_RE" || true)
  ((${#want[@]})) || { warn "could not read Ryoku's package lists from origin/$CHANNEL"; return 1; }
  # arch=any Ryoku packages in the lists are built, not looked up in pacman
  local -A is_any=()
  for a in $(read_list ryoku-any); do is_any[$a]=1; done
  for a in "${want[@]}"; do
    if [[ -n ${is_any[$a]:-} ]]; then any+=("$a"); else repo_apps+=("$a"); fi
  done
  # repo apps first: a failed source build must never block Chromium & co.
  install_missing "Ryoku apps" "${repo_apps[@]}" || warn "pacman could not install some apps"
  for a in "${any[@]}"; do build_any "$a"; done
}
