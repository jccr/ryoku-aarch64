# shellcheck shell=bash
step doctor-apps optional "decline Ryoku's shipped apps that can't run here, before the doctor"

# On every `ryoku update` Ryoku's doctor installs its "shipped apps"
# (ryoku-cli internal/ryokumanifest Apps(), plus ryotunes) in ONE pacman
# transaction. On aarch64 some don't exist (ryomotion is x86_64-only, mangohud
# isn't in ALARM, ryotunes' release is x86_64), so the whole transaction fails
# and even the apps that would work never land. Others install but can't do
# their job on Asahi (packages/doctor-declined.packages says why).
#
# The doctor's own opt-out: a name in its ledger ($XDG_STATE_HOME/ryoku/
# provisioned) that isn't installed reads as "you removed it", and it is never
# put back. This step adds the declined names there before the desktop step
# runs the doctor, and remembers which ones it added ($STATE/doctor-declined),
# so an app that later becomes installable here is handed back to the doctor.
# Delete a name from the ledger yourself to re-arm the doctor for it.
DOCTOR_LEDGER=${XDG_STATE_HOME:-$HOME/.local/state}/ryoku/provisioned
DOCTOR_OURS=$STATE/doctor-declined

doctor_apps() { # the doctor's shipped-app list, from the checkout
  upstream_show ryoku/cli/internal/ryokumanifest/manifest.go \
    | sed -n '/^func Apps() \[\]App {/,/^}/p' | grep -oE '^[[:space:]]*\{"[a-z0-9.+_-]+"' | tr -d '{" \t'
  echo ryotunes
}

declined_listed() { # names from doctor-declined.packages that apply here
  local name cond
  while read -r name cond _; do
    [[ -z $name || $name == \#* ]] && continue
    case $cond in
      aarch64) echo "$name" ;;
      asahi) is_asahi && echo "$name" ;;
    esac
    true
  done < "$ARM_DIR/packages/doctor-declined.packages"
}

doctor_declines() { # sorted: listed ones, plus apps neither installed nor in your repos
  local -A have=(); repo_index have
  local a
  {
    declined_listed
    for a in $(doctor_apps); do
      [[ $a == ryotunes ]] && continue          # its own release channel, listed above
      satisfied "$a" || [[ -n ${have[$a]:-} ]] || echo "$a"
    done
  } | sort -u
}

step_doctor_apps() {
  need_repo
  local apps want ours ledger tmp n
  apps=$(doctor_apps)
  [[ $(wc -l <<<"$apps") -gt 5 ]] || { warn "could not read the doctor's shipped-app list from the checkout"; return 1; }
  want=$(doctor_declines)
  ours=$(sort -u "$DOCTOR_OURS" 2>/dev/null || true)
  ledger=$(cat "$DOCTOR_LEDGER" 2>/dev/null || true)
  # the ledger after: drop names we added that no longer qualify (and are not
  # installed: an installed one is the doctor's own record), add what does
  local new=() drop=() keep=()
  while IFS= read -r n; do
    [[ -z $n ]] && continue
    if grep -qxF -- "$n" <<<"$ours" && ! grep -qxF -- "$n" <<<"$want" && ! pacman -Qq "$n" >/dev/null 2>&1; then
      drop+=("$n")
    else
      keep+=("$n")
    fi
  done <<<"$ledger"
  while IFS= read -r n; do
    [[ -n $n ]] && ! grep -qxF -- "$n" <<<"$ledger" && new+=("$n")
  done <<<"$want"
  ((${#new[@]} + ${#drop[@]})) || return 0
  ((${#new[@]})) && say "telling Ryoku's doctor not to install: ${new[*]}"
  ((${#drop[@]})) && say "handing back to Ryoku's doctor (installable here now): ${drop[*]}"
  if dry; then echo "  DRY: rewrite $(tilde "$DOCTOR_LEDGER")"; return 0; fi
  mkdir -p "${DOCTOR_LEDGER%/*}" "$STATE"
  tmp=$(mktemp "${DOCTOR_LEDGER%/*}/.provisioned.XXXXXX")
  { ((${#keep[@]})) && printf '%s\n' "${keep[@]}"; ((${#new[@]})) && printf '%s\n' "${new[@]}"; true; } > "$tmp"
  [[ -f $DOCTOR_LEDGER ]] && chmod --reference="$DOCTOR_LEDGER" "$tmp"
  mv -f "$tmp" "$DOCTOR_LEDGER"
  # ours: only names this step put there (one the doctor recorded itself, from
  # an install you later removed, stays yours and is never handed back)
  { grep -vxF -f <(printf '%s\n' "${drop[@]}" "") <<<"$ours"; ((${#new[@]})) && printf '%s\n' "${new[@]}"; true; } \
    | grep . | sort -u > "$DOCTOR_OURS" || true
}
