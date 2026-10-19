#!/usr/bin/env bash
# ryoku-arm's test suite. Runs every command against a sandbox HOME with fake
# system commands (tests/fake: sudo never runs anything real), a local clone
# of the Ryoku checkout, and copies of the files the steps patch. Safe to run
# on a live machine: it reads /proc and the real checkout, writes only under
# its own temp dir.
#
#   tests/run.sh [ryoku checkout]     (default ~/src/ryoku)
set -uo pipefail

T=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ARM=$(dirname "$T")
UPSTREAM=${1:-$HOME/src/ryoku}
[[ -d $UPSTREAM/.git ]] || { echo "need a Ryoku checkout (arg 1)"; exit 2; }

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [[ -n ${2:-} && -n ${VERBOSE:-} ]] && printf '%s\n' "$2" | sed 's/^/       /'; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d" "${OUT:-}"; fi; }
has()  { grep -qF -- "$1" <<<"$OUT"; }
lacks() { ! grep -qF -- "$1" <<<"$OUT"; }

# ---------------------------------------------------------------- sandbox
S=$(mktemp -d "${TMPDIR:-/tmp}/ryoku-arm-test.XXXXXX")
trap 'rm -rf "$S"' EXIT
export HOME=$S/home XDG_CONFIG_HOME=$S/home/.config XDG_DATA_HOME=$S/home/.local/share \
       XDG_STATE_HOME=$S/home/.local/state XDG_CACHE_HOME=$S/home/.cache XDG_PICTURES_DIR=$S/home/Pictures
export FAKE_DIR=$S/fake FAKE_BIN=$S/fakebin FAKE_LOG=$S/fake/log
export RYOKU_ARM_SHARE=$ARM RYOKU_ARM_SELF_UPDATE=0 RYOKU_ARM_PACMAN_CONF=$S/pacman.conf
mkdir -p "$HOME/.local/bin" "$FAKE_DIR" "$FAKE_BIN" "$XDG_CONFIG_HOME/hypr"
for c in sudo pacman makepkg systemctl ryoku curl go loginctl yay usermod snapper locale-gen localectl update-desktop-database; do
  ln -s "$T/fake" "$FAKE_BIN/$c"
done
# drop the real ~/.local/bin (the live Ryoku tools) from PATH; fakes first
export PATH=$FAKE_BIN:$(tr ':' '\n' <<<"$PATH" | grep -vxF "$(getent passwd "$USER" | cut -d: -f6)/.local/bin" | paste -sd:)
: > "$FAKE_LOG"

# the deployed desktop: a fake ryoku CLI, the real clamshell script (patched
# by keep-awake-lid), hypr user.lua
ln -s "$T/fake" "$HOME/.local/bin/ryoku"
printf '#!/bin/sh\necho stock ryoku-shell\n' > "$HOME/.local/bin/ryoku-shell"; chmod +x "$HOME/.local/bin/ryoku-shell"
export RYOKU_ARM_GO=$FAKE_BIN/go
cp "$UPSTREAM/system/hardware/power/ryoku-clamshell" "$HOME/.local/bin/ryoku-clamshell"
[[ -x $UPSTREAM/system/hardware/power/ryoku-hw-laptop ]] && cp "$UPSTREAM/system/hardware/power/ryoku-hw-laptop" "$HOME/.local/bin/"
printf -- '-- your overrides\n' > "$XDG_CONFIG_HOME/hypr/user.lua"
EYE=$XDG_CONFIG_HOME/quickshell/shell/modules/bar/barstyles/qsbar/modules/IdleInhibitorWidget.qml
mkdir -p "${EYE%/*}"; cp "$UPSTREAM/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/IdleInhibitorWidget.qml" "$EYE"
printf '[options]\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' > "$S/pacman.conf"
# a clamshell lid that reads open
mkdir -p "$S/lid"; printf 'state:      open\n' > "$S/lid/state"
export RYOKU_LID_STATE_GLOB=$S/lid/state
# an Apple Silicon machine, whatever this one is
printf 'apple,j413\0apple,t8112\0' > "$S/compatible"; export RYOKU_ARM_DT_COMPAT=$S/compatible
# the Ryoku checkout: a local clone whose origin is the real one
git clone --quiet --shared "$UPSTREAM" "$S/ryoku"
git -C "$S/ryoku" fetch --quiet origin "+refs/heads/main:refs/remotes/origin/main"

ARMCMD=("$ARM/ryoku-arm")
arm() { OUT=$("${ARMCMD[@]}" "$@" 2>&1); RC=$?; }
tree_sum() { (cd "$HOME" && find . -type f -not -path './.cache/*' -print0 | sort -z | xargs -0 sha256sum) | sha256sum; }

# ---------------------------------------------------------------- tests
echo "== commands"
arm help;            check "help exits 0"                 test "$RC" -eq 0
check "help lists choices"  has "--no-keep-awake-lid"
arm debug steps;     check "debug steps lists 21 steps"   test "$(grep -c '^  [a-z]' <<<"$OUT")" -eq 21
arm frobnicate;      check "unknown command fails"        test "$RC" -ne 0
arm install --bogus; check "unknown option fails"         test "$RC" -ne 0

echo "== dry run changes nothing"
before=$(tree_sum)
arm install --dir "$S/ryoku" --dry-run --no-aur
check "dry install exits 0" test "$RC" -eq 0
check "dry install prints a plan" has "DRY:"
check "dry install leaves HOME untouched" test "$(tree_sum)" == "$before"
check "dry install saves no choices" test ! -e "$XDG_CONFIG_HOME/ryoku-aarch64/choices"

echo "== choices on a box installed before they were saved"
printf '%s\n' firefox chromium > "$FAKE_DIR/missing"
arm debug choices
check "no browser installed: apps inferred off" grep -qE '^  apps +0$' <<<"$OUT"
check "inference is announced" has "read these off this machine"

echo "== install on a deployed box"
printf '%s\n' firefox > "$FAKE_DIR/missing"
arm install --dir "$S/ryoku" --no-aur --no-sddm --apps
check "install exits 0" test "$RC" -eq 0
check "choices saved" grep -qx 'aur=0' "$XDG_CONFIG_HOME/ryoku-aarch64/choices"
check "deps/apps: missing firefox installed with -Syu" grep -q 'pacman -Syu --needed --noconfirm.*firefox' "$FAKE_LOG"
check "desktop: ryoku update ran" grep -qx 'ryoku update' "$FAKE_LOG"
check "pacman-repo: [ryoku] stanza planned via sudo" grep -q 'sudo bash -c printf.*ryoku' "$FAKE_LOG"
check "ryoku-any: arch=any packages built" grep -q '^makepkg ' "$FAKE_LOG"
check "seed: starship.toml laid" test -f "$XDG_CONFIG_HOME/starship.toml"
check "seed: fastfetch emblem laid" test -f "$XDG_CONFIG_HOME/fastfetch/fastfetch-emblem.png"
check "ryoku-any: prowl-agent built with --ignorearch" grep -q '^makepkg .*--ignorearch' "$FAKE_LOG"
check "lid: user.lua has the lid block" grep -q 'ryoku-aarch64 lid begin' "$XDG_CONFIG_HOME/hypr/user.lua"
check "lid: user's own lines kept" grep -qx -- '-- your overrides' "$XDG_CONFIG_HOME/hypr/user.lua"
check "keep-awake-lid: clamshell patched" grep -q 'keep_awake_on; then keep_awake_close' "$HOME/.local/bin/ryoku-clamshell"
check "keep-awake-lid: patched clamshell parses" bash -n "$HOME/.local/bin/ryoku-clamshell"
check "shell-suspend-fix: ryoku-shell rebuilt from patched source" grep -q 'fixed=yes' "$HOME/.local/bin/ryoku-shell"
check "eye-keep-awake: eye toggles Keep awake" grep -q 'Toggles.toggleCaffeine()' "$EYE"
check "eye-keep-awake: shows Keep awake state" grep -q 'property bool on: Toggles.keepAwake' "$EYE"
check "shell-suspend-fix: checkout left untouched" test -z "$(git -C "$S/ryoku" status --porcelain)"
check "login-screen skipped (--no-sddm)" bash -c "! grep -qE '^sudo .*(sddm|qylock)' '$FAKE_LOG'"
check "aur skipped (--no-aur)" bash -c "! grep -q '^curl' '$FAKE_LOG'"

echo "== a second run is a no-op"
: > "$FAKE_DIR/missing"
sum=$(tree_sum); : > "$FAKE_LOG"
arm update
check "update exits 0" test "$RC" -eq 0
check "update honours saved --no-aur" bash -c "! grep -q '^curl' '$FAKE_LOG'"
check "no files changed" test "$(tree_sum)" == "$sum"
check "nothing rebuilt" bash -c "! grep -q '^makepkg' '$FAKE_LOG'"
check "no package installs" bash -c "! grep -q 'pacman -Syu' '$FAKE_LOG'"

echo "== deploy re-lays ryoku-shell: the fix is rebuilt"
printf '#!/bin/sh\necho stock ryoku-shell\n' > "$HOME/.local/bin/ryoku-shell"
arm debug step shell-suspend-fix
check "rebuilt after a deploy replaced it" grep -q 'fixed=yes' "$HOME/.local/bin/ryoku-shell"
: > "$FAKE_LOG"; arm debug step shell-suspend-fix
check "our build in place: no rebuild" bash -c "! grep -q '^go ' '$FAKE_LOG'"

echo "== choices flip both ways"
arm debug step lid keep-awake-lid --dry-run
check "debug step dry run exits 0" test "$RC" -eq 0
arm update --no-lid --no-keep-awake-lid
check "--no-lid removes the block" bash -c "! grep -q 'ryoku-aarch64' '$XDG_CONFIG_HOME/hypr/user.lua'"
check "--no-keep-awake-lid restores clamshell exactly" cmp -s "$HOME/.local/bin/ryoku-clamshell" "$UPSTREAM/system/hardware/power/ryoku-clamshell"
arm update --lid --keep-awake-lid
check "--lid puts it back" grep -q 'ryoku-aarch64 lid begin' "$XDG_CONFIG_HOME/hypr/user.lua"
arm update --no-eye-keep-awake
check "--no-eye-keep-awake restores the shipped widget exactly" cmp -s "$EYE" "$UPSTREAM/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/IdleInhibitorWidget.qml"
arm update --eye-keep-awake
check "--eye-keep-awake puts it back" grep -q 'Toggles.toggleCaffeine()' "$EYE"

echo "== lid-closed safety"
printf 'state:      closed\n' > "$S/lid/state"
arm update --no-lid
check "closed lid: user.lua left alone" grep -q 'ryoku-aarch64 lid begin' "$XDG_CONFIG_HOME/hypr/user.lua"
check "closed lid: says why" has "lid is closed"
printf 'state:      open\n' > "$S/lid/state"
arm update --lid

echo "== the doctor's shipped apps"
L=$XDG_STATE_HOME/ryoku/provisioned
mkdir -p "${L%/*}"; printf '%s\n' kitty mangohud > "$L"       # mangohud: the doctor's own record
printf '%s\n' ryomotion mangohud > "$FAKE_DIR/unavailable"
arm debug step doctor-apps
check "doctor-apps exits 0" test "$RC" -eq 0
check "unavailable app declined (ryomotion)" grep -qx ryomotion "$L"
check "x86-only release declined (ryotunes)" grep -qx ryotunes "$L"
check "Asahi-pointless app declined (gamescope)" grep -qx gamescope "$L"
check "installable app left to the doctor (songrec)" bash -c "! grep -qx songrec '$L'"
check "existing ledger kept (kitty)" grep -qx kitty "$L"
check "no duplicate for the doctor's own record" test "$(grep -cx mangohud "$L")" -eq 1
sum=$(sha256sum < "$L"); arm debug step doctor-apps
check "second run leaves the ledger alone" test "$(sha256sum < "$L")" == "$sum"
# ryomotion & mangohud reach your repos (still not installed)
: > "$FAKE_DIR/unavailable"; printf '%s\n' ryomotion mangohud > "$FAKE_DIR/missing"
arm debug step doctor-apps
check "now-installable app handed back (ryomotion)" bash -c "! grep -qx ryomotion '$L'"
check "the doctor's own record stays (mangohud)" grep -qx mangohud "$L"
check "listed declines stay (ryotunes)" grep -qx ryotunes "$L"
: > "$FAKE_DIR/missing"

echo "== Keep awake in the patched clamshell"
K=$S/ka; mkdir -p "$K/run" "$K/ps/AC" "$K/drm" "$K/bin"
echo Mains > "$K/ps/AC/type"; echo 0 > "$K/ps/AC/online"
printf '#!/bin/sh\necho "ryoku-shell $*" >> "%s/log"\n' "$K" > "$K/bin/ryoku-shell"
printf '#!/bin/sh\necho "ryoku $*" >> "%s/log"\n' "$K" > "$K/bin/ryoku"
printf '#!/bin/sh\n[ "$1" = status ] && [ -e "%s/caf" ]\n' "$K" > "$K/bin/ryoku-cmd-caffeine"
chmod +x "$K"/bin/*
clam() { ( unset XDG_SESSION_ID; PATH=$K/bin:$PATH RYOKU_BIN=$K/bin/ryoku XDG_RUNTIME_DIR=$K/run \
           RYOKU_POWER_SUPPLY_DIR=$K/ps RYOKU_DRM_DIR=$K/drm RYOKU_CLAMSHELL_RETRY=0.1 \
           timeout 5 "$HOME/.local/bin/ryoku-clamshell" "$@" >/dev/null 2>&1 ); }
printf 'state:      closed\n' > "$S/lid/state"; touch "$K/caf"; : > "$K/log"
clam lid close
check "Keep awake on: close locks and blanks" grep -qx 'ryoku wm act output.power off' "$K/log"
check "Keep awake on: close does not suspend" bash -c "! grep -q 'suspend' '$K/log'"
printf 'state:      open\n' > "$S/lid/state"; : > "$K/log"; clam lid open
check "Keep awake on: open turns the display on" grep -qx 'ryoku wm act output.power on' "$K/log"
printf 'state:      closed\n' > "$S/lid/state"; rm -f "$K/caf"; : > "$K/log"; clam lid close
check "Keep awake off: close suspends" grep -q 'ryoku-shell suspend transaction' "$K/log"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
