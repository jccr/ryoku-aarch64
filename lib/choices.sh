# shellcheck shell=bash
# The install's choices (--no-sddm, --no-aur, ...), saved so every later
# install/update honours them instead of reverting to defaults. Stored as
# key=value lines and parsed, never sourced.

CHOICES_FILE=${RYOKU_ARM_CHOICES:-$CFG/ryoku-aarch64/choices}

# key -> default. Booleans are 0/1 and get --KEY / --no-KEY flags (key with
# _ written as -); the rest take a value (--KEY VALUE).
declare -A CHOICE_DEFAULT=(
  [ref]=main [dir]="$HOME/src/ryoku"
  [locale]=en_US.UTF-8 [tty_font]=ter-v32n
  [fish]=1 [sddm]=1 [asahi_desktop]=1 [kbd_light]=1
  [apps]=1 [aur]=1 [lid]=1 [keep_awake_lid]=1
)
declare -A CHOICE_DOC=(
  [ref]="Ryoku branch to build"
  [dir]="Ryoku checkout"
  [locale]="UTF-8 locale to set when the system has none"
  [tty_font]="TTY console font when none is set (none skips)"
  [fish]="fish as your login shell"
  [sddm]="SDDM + Ryoku's greeter as the login screen"
  [asahi_desktop]="asahi-desktop-meta on Asahi (audio, speaker safety, Vulkan)"
  [kbd_light]="Keyboard Light on MacBooks (bar plugin + quick-settings row)"
  [apps]="Ryoku's preinstalled apps (Chromium, Firefox, dev toolchains, ...)"
  [aur]="Ryoku's AUR set that builds on aarch64 (via yay)"
  [lid]="bind the laptop's real lid switch to Ryoku's lid policy"
  [keep_awake_lid]="Keep awake also holds a lid close awake"
)
declare -A CHOICE=()

choice_is_bool() { [[ ${CHOICE_DEFAULT[$1]} == [01] ]]; }
choice() { printf '%s' "${CHOICE[$1]:-${CHOICE_DEFAULT[$1]}}"; }
on() { [[ $(choice "$1") == 1 ]]; }

choices_load() {
  local k v
  [[ -f $CHOICES_FILE ]] || return 0
  while IFS='=' read -r k v; do
    [[ -n $k && $k != \#* && -n ${CHOICE_DEFAULT[$k]+x} ]] && CHOICE[$k]=$v
  done < "$CHOICES_FILE"
}

choices_save() {
  local k
  dry && return 0
  mkdir -p "${CHOICES_FILE%/*}"
  {
    echo "# ryoku-arm install choices; change with: ryoku-arm update --no-aur (etc.)"
    for k in $(printf '%s\n' "${!CHOICE_DEFAULT[@]}" | sort); do echo "$k=$(choice "$k")"; done
  } > "$CHOICES_FILE"
}

# Apply one choice flag at $1 ($2 = its value). Sets FLAG_ARGS to how many
# args it used; returns 1 when $1 is not a choice flag.
FLAG_ARGS=0
choice_flag() {
  local f=${1#--} k
  [[ $1 == --* ]] || return 1
  if [[ $f == no-* ]]; then
    k=${f#no-}; k=${k//-/_}
    [[ -n ${CHOICE_DEFAULT[$k]+x} ]] && choice_is_bool "$k" || return 1
    CHOICE[$k]=0; FLAG_ARGS=1
  else
    k=${f//-/_}
    [[ -n ${CHOICE_DEFAULT[$k]+x} ]] || return 1
    if choice_is_bool "$k"; then CHOICE[$k]=1; FLAG_ARGS=1; return 0; fi
    [[ -n ${2:-} ]] || die "--$f needs a value"
    CHOICE[$k]=$2; FLAG_ARGS=2
  fi
}

choices_help() {
  local k
  for k in $(printf '%s\n' "${!CHOICE_DEFAULT[@]}" | sort); do
    if choice_is_bool "$k"; then
      printf '  --no-%-18s skip: %s\n' "${k//_/-}" "${CHOICE_DOC[$k]}"
    else
      printf '  --%-21s %s (default: %s)\n' "${k//_/-} X" "${CHOICE_DOC[$k]}" "$(tilde "${CHOICE_DEFAULT[$k]}")"
    fi
  done
}

choices_print() {
  local k
  for k in $(printf '%s\n' "${!CHOICE_DEFAULT[@]}" | sort); do printf '  %-16s %s\n' "$k" "$(choice "$k")"; done
}

# A box installed before choices were saved: read its choices off the machine
# instead of applying the defaults, which would e.g. switch an SSH-only box to
# SDDM or pull in every app on the next update.
choices_infer() {
  [[ -f $CHOICES_FILE ]] && return 0
  ryoku_deployed || return 0
  local shell
  shell=$(getent passwd "$USER" | cut -d: -f7)
  [[ $shell == */fish ]] || CHOICE[fish]=0
  systemctl is-enabled --quiet sddm.service 2>/dev/null || CHOICE[sddm]=0
  pacman -Qq asahi-desktop-meta >/dev/null 2>&1 || CHOICE[asahi_desktop]=0
  ryoku plugin list --json 2>/dev/null | grep -q '"keyboard-backlight"' || CHOICE[kbd_light]=0
  { pacman -Qq chromium || pacman -Qq firefox; } >/dev/null 2>&1 || CHOICE[apps]=0
  command -v yay >/dev/null 2>&1 || CHOICE[aur]=0
  say "no saved choices yet; read these off this machine (saved to $(tilde "$CHOICES_FILE")):"
  choices_print
}
