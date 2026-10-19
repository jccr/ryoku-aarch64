# shellcheck shell=bash
step lid optional "bind the laptop's real lid switch to Ryoku's lid policy"

# Hyprland's switch binds match an input device by NAME, and Ryoku's
# modules/lid.lua binds only "Lid Switch" (the ACPI lid button x86 laptops
# have). Apple Silicon's lid is the SMC input "Apple SMC power/lid events", so
# a close never reached ryoku-clamshell; meanwhile its daemon holds logind's
# handle-lid-switch inhibitor, so logind didn't act either: the panel stayed
# lit and nothing suspended. This binds every SW_LID device under its real
# name to the same clamshell commands, in a marked block at the end of
# hypr/user.lua (user-owned, loaded last, never touched by a deploy).
LID_USER_LUA=$CFG/hypr/user.lua

# Input devices whose SW bitmap has SW_LID (bit 0), minus Ryoku's own name.
lid_switch_names() {
  local line name='' w
  while IFS= read -r line; do
    case $line in
      'N: Name='*) name=${line#'N: Name="'}; name=${name%'"'} ;;
      'B: SW='*)
        w=${line##* }; w=${w#SW=}
        [[ $w =~ ^[0-9a-fA-F]+$ ]] && (( 16#$w & 1 )) && [[ -n $name && $name != 'Lid Switch' ]] \
          && printf '%s\n' "$name"
        true ;;
      '') name='' ;;
    esac
  done < "${RYOKU_ARM_INPUT_DEVICES:-/proc/bus/input/devices}" | sort -u
}

lid_block() { # names on stdin
  local n q cmd='command -v ryoku-clamshell >/dev/null 2>&1 && ryoku-clamshell lid'
  echo "$(block_begin -- lid) (ryoku-arm: this machine's lid switch, which Ryoku's"
  echo "-- modules/lid.lua misses: it binds only \"Lid Switch\". Same clamshell policy.)"
  while IFS= read -r n; do
    q=${n//\\/\\\\}; q=${q//\"/\\\"}
    printf 'hl.bind("switch:on:%s",  hl.dsp.exec_cmd("%s close"), { locked = true })\n' "$q" "$cmd"
    printf 'hl.bind("switch:off:%s", hl.dsp.exec_cmd("%s open"),  { locked = true })\n' "$q" "$cmd"
  done
  block_end -- lid
}

step_lid() {
  local names want=''
  names=$(lid_switch_names)
  if on lid && [[ -n $names ]]; then want=$(lid_block <<<"$names"); fi
  [[ $(block_get "$LID_USER_LUA" -- lid) == "$want" ]] && return 0
  # Hyprland reloads on the edit and a reload re-reads the lid: with it shut
  # and no dock that suspends the machine mid-run (and drops an SSH session).
  if lid_shut_undocked; then
    warn "lid is closed: skipped the lid-switch binds (the reload would suspend now); open it and run: ryoku-arm debug step lid"
    return 0
  fi
  if block_set_trailing "$LID_USER_LUA" -- lid <<<"$want" && ! dry; then
    if [[ -n $want ]]; then say "bound the lid switch ($(paste -sd, <<<"$names")) in $(tilde "$LID_USER_LUA")"
    else say "removed the lid-switch binds from $(tilde "$LID_USER_LUA")"; fi
  fi
}
