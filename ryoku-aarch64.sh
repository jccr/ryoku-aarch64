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
# Usage:  ./ryoku-aarch64.sh [--ref main] [--dir ~/src/ryoku] [--no-fish] [--dry-run]
#   By default fish becomes your login shell (Ryoku's default shell), after the
#   build succeeds. --no-fish keeps your current shell.
#   Undo later: sudo usermod -s /bin/bash $USER
#   --locale L  UTF-8 locale to generate and set when the system has none
#               (default en_US.UTF-8; e.g. en_CA.UTF-8). An existing UTF-8
#               LANG in /etc/locale.conf is left alone.
#   --tty-font F  console font for the text TTY when none is set (default
#               ter-v32n, sized for Retina panels; ter-v24n is smaller;
#               "none" skips). An existing FONT= in /etc/vconsole.conf wins.
#   --no-sddm   skip the SDDM login screen (by default SDDM + Ryoku's greeter
#               theme become the login, the way a stock Ryoku box boots).
#               Starting Hyprland from a TTY instead leaves logind treating the
#               session as type=tty, and polkit then denies the shell's
#               sleep/lid inhibitors and its auth agent.
#   --no-asahi-desktop  on Asahi, skip asahi-desktop-meta (installed after the
#               desktop: speaker safety, asahi-audio, Asahi Vulkan, widevine).
#   --no-kbd-plugin  on a MacBook, skip the Keyboard Light bar plugin (a
#               keyboard-backlight slider; the Air has no backlight keys).
#   --no-apps   skip Ryoku's preinstalled apps (Chromium, Firefox, Kitty,
#               Nautilus, dev toolchains, ...; read from Ryoku's own lists).
#   --no-aur    skip Ryoku's AUR set (yay, Zen browser, LocalSend, voxtype
#               dictation, cursor themes; x86-only entries skipped).
# Update later:  cd ~/src/ryoku && git pull && ryoku/shell/deploy.sh
# (do NOT use `ryoku update` — it pulls from the x86_64 repo)
set -euo pipefail

ref=main
dir="$HOME/src/ryoku"
dry=0
fish=1
lang=en_US.UTF-8
ttyfont=ter-v32n
sddm=1
asahi_desktop=1
kbd_plugin=1
apps=1
aur=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --ref) ref=$2; shift 2 ;;
    --dir) dir=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --no-fish) fish=0; shift ;;
    --locale) lang=$2; shift 2 ;;
    --tty-font) ttyfont=$2; shift 2 ;;
    --no-sddm) sddm=0; shift ;;
    --no-asahi-desktop) asahi_desktop=0; shift ;;
    --no-kbd-plugin) kbd_plugin=0; shift ;;
    --no-apps) apps=0; shift ;;
    --no-aur) aur=0; shift ;;
    --fish) fish=1; shift ;;   # accepted for compatibility; already the default
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
is_asahi=0
if pacman -Qq linux-asahi asahi-meta >/dev/null 2>&1 || grep -qa apple /proc/device-tree/compatible 2>/dev/null; then
  is_asahi=1
  say "Apple Silicon / Asahi detected"
fi

# ---------------------------------------------------------------- sudo
# One password prompt up front, then keep the timestamp fresh: the builds and
# the deploy run longer than sudo's 5-minute cache, which otherwise re-prompts
# at every later sudo step. The refresher dies with this script.
if ((!dry)); then
  sudo -v || die "sudo is required"
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  sudo_keepalive=$!
  trap 'kill "$sudo_keepalive" 2>/dev/null' EXIT
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
  vulkan-headers libcanberra pixman libdrm
  # compositor + shell
  hyprland hypridle hyprpicker hyprpolkitagent hyprsunset
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xorg-xwayland weston
  quickshell qt6-wayland qt5-wayland qt6-5compat qt6-svg qt6-imageformats
  # desktop tools
  brightnessctl playerctl mpv mpv-mpris yt-dlp wl-clipboard wl-clip-persist
  cliphist grim slurp cava wf-recorder gpu-screen-recorder wtype zenity
  python uv jq imagemagick matugen ffmpeg curl inotify-tools libqalculate
  nodejs pacman-contrib
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
  # terminal tools Ryoku's fish/bash/zsh configs use (from base.packages);
  # ryoku-fastfetch runs at every login and errors without fastfetch
  fastfetch starship zoxide fzf fd eza bat btop neovim ripgrep lazygit yazi
  bash-completion
  # readable Unicode console font for the TTY (box drawing, prompt arrows)
  terminus-font
)

say "refreshing package databases"
run sudo pacman -Sy

# hash lookup, not `printf | grep -q`: under pipefail grep -q's early exit
# SIGPIPEs printf and the pipeline reports failure on a match.
declare -A avail=()
while IFS= read -r n; do avail[$n]=1; done < <(pacman -Slq)
have=() missing=()
for p in "${pkgs[@]}"; do
  if [[ -n ${avail[$p]:-} ]]; then have+=("$p"); else missing+=("$p"); fi
done
((${#avail[@]})) || die "pacman -Slq returned nothing; run 'sudo pacman -Sy' first"
((${#missing[@]})) && warn "not in your repos (skipped; try the AUR): ${missing[*]}"

say "installing ${#have[@]} packages"
run sudo pacman -Su --needed --noconfirm "${have[@]}"

# ---------------------------------------------------------------- [ryoku] stanza
# deploy.sh adds Server = https://repo.ryoku.dev/stable/$arch when no [ryoku]
# exists, and leaves a [ryoku] that points anywhere else alone. Give it a local,
# empty repo so nothing ever fetches the (nonexistent) aarch64 db.
localrepo=/var/lib/ryoku-local
if grep -q '^\[ryoku\]' /etc/pacman.conf; then
  if awk '/^\[ryoku\]/{f=1;next} /^\[/{f=0} f && /repo\.ryoku\.dev/{hit=1} END{exit !hit}' /etc/pacman.conf; then
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
# both the package db and the files db (pacman -F) must exist, or pacman -Fy
# fails "failed retrieving file 'ryoku.files'"
run sudo install -d "$localrepo"
for kind in db files; do
  if [[ ! -e $localrepo/ryoku.$kind ]]; then
    run sudo tar -czf "$localrepo/ryoku.$kind.tar.gz" --files-from /dev/null
    run sudo ln -sf "ryoku.$kind.tar.gz" "$localrepo/ryoku.$kind"
  fi
done
run sudo pacman -Sy

# ---------------------------------------------------------------- source
if [[ -d $dir/.git ]]; then
  say "updating $dir"
  run git -C "$dir" fetch --depth 1 --no-tags origin "+refs/heads/$ref:refs/remotes/origin/$ref"
  # stay on a real branch: Ryoku's updater only reconciles a rewritten upstream
  # when HEAD is the channel branch (a detached FETCH_HEAD checkout cannot)
  run git -C "$dir" checkout -q -B "$ref" "origin/$ref"
else
  say "cloning ryoku ($ref) into $dir"
  run mkdir -p "$(dirname "$dir")"
  run git clone --depth 1 --branch "$ref" https://github.com/Ryoku-dev/ryoku.git "$dir"
fi

# ---------------------------------------------------------------- arch=any extras
# Ryoku packages that are pure data (cursor themes, UI fonts) build fine on
# aarch64 from Ryoku's own PKGBUILDs: Bibata is the desktop's and the greeter's
# cursor; Space Grotesk / Maple Mono are the shell's UI fonts.
anypkgs=(ryoku-cursors ryoku-cursor-material otf-space-grotesk ttf-maple-mono-nf blesh game-devices-udev gpk ryoku-oh-my-zsh)
pkgcache="$HOME/.cache/ryoku-aarch64/pkgs"
for p in "${anypkgs[@]}"; do
  if pacman -Qq "$p" >/dev/null 2>&1; then
    continue
  fi
  say "building $p from Ryoku's PKGBUILD"
  if ((dry)); then printf '  DRY: makepkg -sci in %s\n' "$pkgcache/$p"; continue; fi
  rm -rf "${pkgcache:?}/$p"; mkdir -p "$pkgcache"
  cp -a "$dir/release/packages/$p" "$pkgcache/$p"
  # makepkg never touches privilege here (no -s/-i): it may authenticate its own
  # way (PACMAN_AUTH), which re-prompted on every package. Deps go in and the
  # result is installed through this script's sudo instead.
  pdeps=()
  while IFS= read -r d; do [[ -n $d ]] && pdeps+=("$d"); done < <(
    cd "$pkgcache/$p" && bash -c 'source ./PKGBUILD >/dev/null 2>&1
      printf "%s\n" "${depends[@]}" "${makedepends[@]}"' | sed 's/[<>=].*//')
  # shellcheck disable=SC2024  # the log is the user's file; only pacman needs root
  if ((${#pdeps[@]})) && ! sudo pacman -S --needed --noconfirm --asdeps "${pdeps[@]}" >>"$pkgcache/$p.log" 2>&1; then
    warn "$p: could not install its build deps (${pdeps[*]}); see $pkgcache/$p.log"
    continue
  fi
  if ( cd "$pkgcache/$p" && makepkg -cf --noconfirm ) >>"$pkgcache/$p.log" 2>&1; then
    built=("$pkgcache/$p"/*.pkg.tar.*)
    # shellcheck disable=SC2024
    sudo pacman -U --needed --noconfirm "${built[@]}" >>"$pkgcache/$p.log" 2>&1 \
      || warn "$p built but did not install; see $pkgcache/$p.log"
  else
    warn "$p did not build (non-fatal); see $pkgcache/$p.log"
  fi
done

# ---------------------------------------------------------------- build + deploy
mode=--no-reload
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && mode=
# Outside a session Ryoku guesses the compositor from an existing ~/.config/hypr;
# on a first run there is none, so deploy.sh reports "no compositor payload for
# none" and skips the Hyprland pass. RYOKU_WM is the override its detector
# checks first (ryoku/wm/detect.go).
export RYOKU_WM=${RYOKU_WM:-hyprland}
# Ryoku's tools call each other by bare name (ryoku-hub -> ryoku-wm-hyprland),
# so ~/.local/bin must be on PATH during the deploy itself, not just afterwards;
# otherwise the provider probe fails and plugin builds report "does not support
# this action: plugins".
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
# upstream deploy.sh copies config.fish without creating the dir first; on an
# account where fish never ran that aborts the deploy.
run mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fish"
say "building and deploying the desktop (several minutes on first run)"
run bash "$dir/ryoku/shell/deploy.sh" $mode

# ---------------------------------------------------------------- Asahi desktop
# asahi-desktop-meta is Asahi's hardware support for a desktop, not a desktop
# environment: speakersafetyd (protects the speakers), asahi-audio/bankstown,
# the Asahi Vulkan drivers, widevine, startup-disk. Installed after the Ryoku
# desktop so the desktop's own deps are settled first.
if ((asahi_desktop && is_asahi)); then
  if pacman -Si asahi-desktop-meta >/dev/null 2>&1; then
    say "installing asahi-desktop-meta (Asahi audio, speaker safety, Vulkan)"
    run sudo pacman -S --needed --noconfirm asahi-desktop-meta
  else
    warn "asahi-desktop-meta not in your repos; skipped"
  fi
fi

# ---------------------------------------------------------------- services
# What Ryoku's ISO enables (installation/backend/lib/bootloader.sh), minus
# NetworkManager: switching network managers here would cut an SSH session and
# override how this install already does Wi-Fi.
for unit in bluetooth.service rtkit-daemon.service power-profiles-daemon.service; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1 && ! systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    say "enabling $unit"
    run sudo systemctl enable --now "$unit" || warn "could not enable $unit"
  fi
done

# ---------------------------------------------------------------- SDDM login
# Mirrors ryoku-shell-installer's stepSession: Ryoku's own sddm/setup (enable
# sddm, graphical target, keyring PAM, Wayland greeter via weston kiosk, cursor
# fallback), then the greeter half of install-qylock (theme + selection). The
# in-session lock half was already staged by deploy.sh, and install-qylock
# refuses to re-stage it outside Ryoku's generation guard, so it is not rerun.
if ((sddm)); then
  say "setting up the SDDM login screen with Ryoku's greeter"
  run sudo pacman -S --needed --noconfirm sddm
  run sudo -v    # sddm/setup uses sudo -n
  if ((dry)); then
    run bash "$dir/ryoku/lockscreen/sddm/setup" --dry-run
  else
    bash "$dir/ryoku/lockscreen/sddm/setup"
  fi
  run sudo install -d /usr/share/ryoku /usr/share/sddm/themes /etc/sddm.conf.d
  run sudo rm -rf /usr/share/ryoku/qylock /usr/share/sddm/themes/ryoku
  run sudo cp -a "$dir/ryoku/lockscreen/qylock" /usr/share/ryoku/qylock
  run sudo cp -a /usr/share/ryoku/qylock/themes/clockwork/orbital /usr/share/sddm/themes/ryoku
  run sudo bash -c "printf '[Theme]\\nCurrent=ryoku\\n' > /etc/sddm.conf.d/99-ryoku.conf"
  warn "SDDM starts at the next boot; reboot and log in through it"
fi

# deploy.sh puts every Ryoku binary in ~/.local/bin; a Hyprland started from a
# TTY inherits the login shell's PATH, so make sure the profile carries it.
pathline='export PATH="$HOME/.local/bin:$PATH"'
profiles=("$HOME/.bash_profile")
[[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]] && profiles+=("$HOME/.zprofile")
for prof in "${profiles[@]}"; do
  if ! grep -qsF '.local/bin' "$prof"; then
    say "adding ~/.local/bin to PATH in $prof"
    if ((dry)); then printf '  DRY: append %s to %s\n' "$pathline" "$prof"
    else printf '\n# added by ryoku-aarch64.sh\n%s\n' "$pathline" >> "$prof"; fi
  fi
done
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "open a new login shell (or: source ~/.bash_profile) to pick up the PATH change"

if ((fish)); then
  cur=$(getent passwd "$USER" | cut -d: -f7)
  if [[ $cur == */fish ]]; then
    say "fish is already your login shell"
  elif ((!dry)) && ! grep -qxF /usr/bin/fish /etc/shells; then
    # never point the login shell at a binary that is not installed/registered:
    # that locks you out of the next login.
    warn "fish is not installed (or not in /etc/shells); keeping $cur"
  else
    say "switching your login shell to fish (was $cur)"
    run sudo usermod -s /usr/bin/fish "$USER"
    say "undo with:  sudo usermod -s $cur $USER"
  fi
fi

# ---------------------------------------------------------------- locale
# Qt (and the whole desktop) wants a UTF-8 locale; a fresh ALARM install has
# none and runs as "C". Only act when /etc/locale.conf has no UTF-8 LANG.
cur_lang=$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | tr -d '"')
if [[ $cur_lang == *UTF-8* || $cur_lang == *utf8* ]]; then
  say "system locale already $cur_lang"
else
  [[ $lang == *.UTF-8 ]] || die "--locale must be a UTF-8 locale, e.g. en_US.UTF-8"
  grep -qE "^#?[[:space:]]*${lang//./\\.}[[:space:]]+UTF-8" /etc/locale.gen \
    || die "$lang is not listed in /etc/locale.gen"
  say "setting the system locale to $lang (was ${cur_lang:-unset})"
  run sudo sed -i -E "s/^#[[:space:]]*(${lang//./\\.}[[:space:]]+UTF-8)/\\1/" /etc/locale.gen
  run sudo locale-gen
  if ! run sudo localectl set-locale "LANG=$lang"; then
    run sudo bash -c "printf 'LANG=%s\\n' '$lang' > /etc/locale.conf"
  fi
  warn "log out and back in for the new locale to apply"
fi

# ---------------------------------------------------------------- tty font
# The default kernel console font is tiny on a Retina panel and lacks the
# box-drawing glyphs Ryoku's fastfetch greeting and prompt use.
if [[ $ttyfont != none ]]; then
  if grep -qE '^[[:space:]]*FONT=' /etc/vconsole.conf 2>/dev/null; then
    say "console font already set ($(sed -n 's/^[[:space:]]*FONT=//p' /etc/vconsole.conf))"
  elif [[ ! -e /usr/share/kbd/consolefonts/$ttyfont.psf.gz ]] && ((!dry)); then
    warn "console font $ttyfont not found under /usr/share/kbd/consolefonts; skipped"
  else
    say "setting the TTY font to $ttyfont"
    run sudo bash -c "printf 'FONT=%s\\n' '$ttyfont' >> /etc/vconsole.conf"
    run sudo systemctl restart systemd-vconsole-setup.service || true
  fi
fi

# ---------------------------------------------------------------- ryoku-arm
# The companion CLI: `ryoku-arm update` keeps deps and arch=any packages in step
# with upstream, then runs Ryoku's own `ryoku update`.
share="${XDG_DATA_HOME:-$HOME/.local/share}/ryoku-aarch64"
if [[ -d $share/.git ]]; then
  run git -C "$share" pull --quiet --ff-only || warn "could not update $share"
else
  run git clone --quiet --depth 1 https://github.com/jccr/ryoku-aarch64.git "$share"
fi
run mkdir -p "$HOME/.local/bin"
run ln -sf "$share/ryoku-arm" "$HOME/.local/bin/ryoku-arm"
say "installed ryoku-arm (update with: ryoku-arm update)"

# Bundled shell plugins that apply to this machine: Keyboard Light on a MacBook
# with a kbd_backlight LED. ryoku-arm decides; it upgrades it on later updates.
if ((kbd_plugin && is_asahi)); then
  run "$share/ryoku-arm" plugins || warn "plugin install failed (retry: ryoku-arm plugins)"
fi
# configs and seeds a packaged box gets but a checkout deploy never lays
# (LazyVim, starship, yazi, wallpapers, .desktop entries)
run env RYOKU_REPO="$dir" "$share/ryoku-arm" seed || warn "seeding failed (retry: ryoku-arm seed)"
# Ryoku's preinstalled apps, read from its system/packages lists (minus the
# kernel, boot chain and network managers; see ryoku-arm)
if ((apps)); then
  run env RYOKU_REPO="$dir" "$share/ryoku-arm" apps --install || warn "app install failed (retry: ryoku-arm apps --install)"
fi
# Ryoku's AUR set, after the desktop (as Ryoku's installer does)
if ((aur)); then
  run env RYOKU_REPO="$dir" "$share/ryoku-arm" aur --install || warn "AUR step failed (retry: ryoku-arm aur --install)"
fi
# upstream Asahi fixes not yet in a release (asahi-audio mic channel position)
if ((is_asahi)); then
  run "$share/ryoku-arm" asahi-fixes || warn "asahi-fixes failed (retry: ryoku-arm asahi-fixes)"
fi

if ((sddm)); then
  say "done. Reboot; log in at the Ryoku login screen (session: Hyprland)."
else
  say "done. Log into a Hyprland session (TTY or a display manager)."
fi
say "update later with:  ryoku-arm update   (or: ryoku-arm update --system)"
say "undo pacman.conf with:  sudo cp /etc/pacman.conf.pre-ryoku-aarch64 /etc/pacman.conf"
