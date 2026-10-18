#!/usr/bin/env bash
# ryoku-aarch64.sh — install the Ryoku desktop on an aarch64 Arch (Asahi ALARM)
# box by building it from source, bypassing the x86_64-only [ryoku] repo and
# the installer's arch gate.
#
# What it does:
#   1. installs Ryoku's runtime + build deps from your normal repos (ALARM/extra)
#   2. points a [ryoku] pacman stanza at an EMPTY local repo, so deploy.sh's
#      "add the official [ryoku] repo" step leaves pacman alone (the official
#      one 404s on aarch64 and would break every later `pacman -Syu`)
#   3. clones ryoku and runs ryoku/shell/deploy.sh, which builds every Go
#      program, the Ryoku.Blobs QML plugin and the Hyprland plugins into
#      ~/.local and lays the configs into ~/.config
#
# It does NOT touch your bootloader (no Limine, no ryoku.conf HOOKS drop-in).
# deploy.sh will run `mkinitcpio -P` once for the plymouth theme; that is the
# same rebuild a kernel update does.
#
# Usage:  ./ryoku-aarch64.sh [--ref main] [--dir ~/src/ryoku] [--dry-run]
# Update later:  cd ~/src/ryoku && git pull && ryoku/shell/deploy.sh
# (do NOT use `ryoku update` — it pulls from the x86_64 repo)
set -euo pipefail

ref=main
dir="$HOME/src/ryoku"
dry=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --ref) ref=$2; shift 2 ;;
    --dir) dir=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if ((dry)); then printf '  DRY: %s\n' "$*"; else "$@"; fi; }

# ---------------------------------------------------------------- preflight
[[ $(uname -m) == aarch64 ]] || die "this script is for aarch64; on x86_64 use the official installer"
[[ $EUID -ne 0 ]] || die "run as your normal user; sudo is used where needed"
command -v pacman >/dev/null || die "pacman not found"
[[ -d /run/systemd/system ]] || die "Ryoku needs systemd"
if pacman -Qq linux-asahi >/dev/null 2>&1 || grep -qa apple /proc/device-tree/compatible 2>/dev/null; then
  say "Apple Silicon / Asahi detected"
fi

# ---------------------------------------------------------------- packages
# Union of depends/makedepends of ryoku-desktop, ryoku-desktop-hyprland,
# ryoku-shell, ryogami and ryoku-blobs, minus:
#   - ryoku's own packages (deploy.sh builds those into ~/.local)
#   - dkms / linux-headers (would pull the generic kernel's headers, not
#     linux-asahi's)
#   - x86-only hardware bits (asusctl, xpadneo, broadcom firmware, limine stack)
# plus a few session basics from base.packages.
pkgs=(
  # build
  base-devel git go cmake ninja pkgconf wayland wayland-protocols
  qt6-base qt6-declarative qt6-shadertools qt6-multimedia qt6-multimedia-ffmpeg
  # compositor + shell
  hyprland hypridle hyprpicker hyprpolkitagent hyprsunset
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xorg-xwayland weston
  quickshell qt6-wayland qt5-wayland qt6-5compat qt6-svg qt6-imageformats
  # desktop tools
  brightnessctl playerctl mpv mpv-mpris yt-dlp wl-clipboard wl-clip-persist
  cliphist grim slurp cava wf-recorder gpu-screen-recorder wtype zenity
  python uv jq imagemagick matugen ffmpeg curl inotify-tools libqalculate
  tesseract tesseract-data-eng zbar ddcutil syntax-highlighting
  pipewire pipewire-pulse wireplumber rtkit upower power-profiles-daemon
  bluez bluez-utils iw nftables pam-u2f polkit gnome-keyring libnotify
  # look
  adw-gtk-theme gnome-themes-extra papirus-icon-theme
  noto-fonts noto-fonts-cjk noto-fonts-emoji inter-font
  ttf-jetbrains-mono-nerd ttf-material-symbols-variable
  # shells + apps the default binds expect
  zsh zsh-autosuggestions zsh-history-substring-search zsh-syntax-highlighting
  fish kitty nautilus nautilus-python fuzzel plymouth
)

say "refreshing package databases"
run sudo pacman -Sy

mapfile -t avail < <(pacman -Slq | sort -u)
have=() missing=()
for p in "${pkgs[@]}"; do
  if printf '%s\n' "${avail[@]}" | grep -qxF -- "$p"; then have+=("$p"); else missing+=("$p"); fi
done
((${#missing[@]})) && warn "not in your repos (skipped; try the AUR): ${missing[*]}"

say "installing ${#have[@]} packages"
run sudo pacman -Su --needed --noconfirm "${have[@]}"

# ---------------------------------------------------------------- [ryoku] stanza
# deploy.sh adds Server = https://repo.ryoku.dev/stable/$arch when no [ryoku]
# exists, and leaves a [ryoku] that points anywhere else alone. Give it a local,
# empty repo so nothing ever fetches the (nonexistent) aarch64 db.
localrepo=/var/lib/ryoku-local
if grep -q '^\[ryoku\]' /etc/pacman.conf; then
  if awk '/^\[ryoku\]/{f=1;next} /^\[/{f=0} f' /etc/pacman.conf | grep -q 'repo.ryoku.dev'; then
    say "repointing the existing [ryoku] stanza at $localrepo"
    run sudo cp /etc/pacman.conf /etc/pacman.conf.pre-ryoku-aarch64
    run sudo sed -i "/^\[ryoku\]/,/^\[/ { s|^SigLevel *=.*|SigLevel = Never|; s|^Server *=.*|Server = file://$localrepo| }" /etc/pacman.conf
  else
    say "[ryoku] stanza already points somewhere else; leaving it"
  fi
else
  say "adding a local [ryoku] stanza ($localrepo)"
  run sudo cp /etc/pacman.conf /etc/pacman.conf.pre-ryoku-aarch64
  run sudo bash -c "printf '\n[ryoku]\nSigLevel = Never\nServer = file://%s\n' '$localrepo' >> /etc/pacman.conf"
fi
if [[ ! -e $localrepo/ryoku.db ]]; then
  run sudo install -d "$localrepo"
  run sudo tar -czf "$localrepo/ryoku.db.tar.gz" --files-from /dev/null
  run sudo ln -sf ryoku.db.tar.gz "$localrepo/ryoku.db"
fi
run sudo pacman -Sy

# ---------------------------------------------------------------- source
if [[ -d $dir/.git ]]; then
  say "updating $dir"
  run git -C "$dir" fetch --depth 1 origin "$ref"
  run git -C "$dir" checkout -q FETCH_HEAD
else
  say "cloning ryoku ($ref) into $dir"
  run mkdir -p "$(dirname "$dir")"
  run git clone --depth 1 --branch "$ref" https://github.com/Ryoku-dev/ryoku.git "$dir"
fi

# ---------------------------------------------------------------- build + deploy
mode=--no-reload
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && mode=
say "building and deploying the desktop (several minutes on first run)"
run bash "$dir/ryoku/shell/deploy.sh" $mode

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  warn "~/.local/bin is not on PATH; add it before logging into Hyprland"
fi

say "done. Log into a Hyprland session (TTY or a display manager)."
say "update with:  git -C $dir pull && $dir/ryoku/shell/deploy.sh"
say "undo pacman.conf with:  sudo cp /etc/pacman.conf.pre-ryoku-aarch64 /etc/pacman.conf"
