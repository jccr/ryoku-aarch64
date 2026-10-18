#!/usr/bin/env bash
# snapshot-rollback.sh — make a snapper snapshot the permanent root again, for
# a flat btrfs layout that boots `subvol=@` by name (Asahi ALARM default).
# `snapper rollback` does not apply here: it needs the default-subvolume layout.
#
#   ./snapshot-rollback.sh               list snapshots
#   ./snapshot-rollback.sh N             report + exact commands (changes nothing)
#   ./snapshot-rollback.sh N --apply     do it (asks you to type "rollback")
#
# N is a number from `snapper list`. Works from the normal system or from a
# snapshot booted via the GRUB "snapshots" submenu.
#
# What --apply does, on the btrfs top level (subvolid=5):
#   1. rename @  ->  @.pre-rollback-<timestamp>      (kept, nothing deleted)
#   2. writable snapshot of .snapshots/N/snapshot    ->  @
#   3. move the .snapshots subvolume (and .snapshots-manual) into the new @
# /home (@home) is not touched. Reboot afterwards, then: grub-mkconfig.
# Undo before rebooting: mv @ @.rolled-back && mv @.pre-rollback-<ts> @
# (moving .snapshots back too) — the report prints it.
set -uo pipefail

R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[1m' N=$'\033[0m'
die() { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
kv()  { printf '%-16s %s\n' "$1" "$2"; }

[[ $EUID -ne 0 ]] || die "run as your normal user (sudo is used where needed)"
# booted from a snapshot via grub-btrfs-overlayfs, / is an overlay: find the
# btrfs device from any btrfs mount (/home is on the same filesystem)
dev=$(findmnt -nt btrfs -o SOURCE / 2>/dev/null || findmnt -nt btrfs -o SOURCE | head -1)
dev=${dev%%\[*}
[[ -n $dev ]] || die "no btrfs filesystem mounted"
command -v snapper >/dev/null || die "snapper is not installed"

if [[ $# -eq 0 ]]; then
  sudo snapper -c root list
  echo; echo "pick a number and run: $0 N"
  exit 0
fi

num=$1; apply=0
[[ ${2:-} == --apply ]] && apply=1
[[ $num =~ ^[0-9]+$ ]] && ((num > 0)) || die "N must be a snapshot number from 'snapper list' (not 0)"

sudo -v || exit 1
top=$(mktemp -d /tmp/btrfs-top.XXXX)
cleanup() { sudo umount "$top" 2>/dev/null; rmdir "$top" 2>/dev/null; }
trap cleanup EXIT
sudo mount -o subvolid=5 "$dev" "$top" || die "could not mount the btrfs top level of $dev"

ts=$(date +%Y%m%d-%H%M%S)
old="@.pre-rollback-$ts"
src="$top/@/.snapshots/$num/snapshot"

printf '%s== rollback report ==%s\n' "$B" "$N"
kv device "$dev"
kv booted-from "$(findmnt -no SOURCE /)"
kv top-level "$(sudo ls -A "$top" | tr '\n' ' ')"

blockers=()
sudo test -d "$top/@" || blockers+=("no subvolume named @ at the top level")
sudo test -d "$src" || blockers+=("snapshot $num not found at @/.snapshots/$num/snapshot")
if sudo test -f "$top/@/.snapshots/$num/info.xml"; then
  kv snapshot "#$num  $(sudo sed -n 's:.*<date>\(.*\)</date>.*:\1:p' "$top/@/.snapshots/$num/info.xml")  \"$(sudo sed -n 's:.*<description>\(.*\)</description>.*:\1:p' "$top/@/.snapshots/$num/info.xml")\""
fi

# the rename trick only works if everything finds root by NAME, not by id
fstab_root=$(sudo awk '$2=="/" {print $4}' "$top/@/etc/fstab" 2>/dev/null)
kv fstab-root-opts "${fstab_root:-?}"
[[ $fstab_root == *subvolid=* ]] && blockers+=("/etc/fstab mounts / by subvolid; renaming @ would not take effect")
[[ $fstab_root == *subvol=* ]] || blockers+=("/etc/fstab does not name subvol=@ for /; layout not recognised")
gcfg="$top/@/boot/grub/grub.cfg"
if sudo test -f "$gcfg"; then
  gflags=$(sudo grep -om1 'rootflags=[^ ]*' "$gcfg")
  kv grub-rootflags "${gflags:-none}"
  [[ $gflags == *subvolid=* ]] && blockers+=("grub.cfg boots by subvolid; renaming @ would not take effect")
fi
avail=$(sudo btrfs filesystem usage -b "$top" 2>/dev/null | awk '/Free \(estimated\)/{printf "%.1f GiB", $3/1073741824}')
kv free "${avail:-?}"

sudo btrfs subvolume show "$top/@/.snapshots" >/dev/null 2>&1 \
  || blockers+=("@/.snapshots is not a subvolume; moving it would copy every snapshot")
manual=0; sudo test -d "$top/@/.snapshots-manual" && manual=1
mapfile -t manual_subs < <( ((manual)) && sudo find "$top/@/.snapshots-manual" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' )

cmds=(
  "mv $top/@ $top/$old"
  "btrfs subvolume snapshot $top/$old/.snapshots/$num/snapshot $top/@"
  "rmdir $top/@/.snapshots   (empty placeholder in the snapshot)"
  "mv $top/$old/.snapshots $top/@/.snapshots"
)
for m in "${manual_subs[@]}"; do
  cmds+=("mv $top/$old/.snapshots-manual/$m $top/@/.snapshots-manual/$m   (subvolume, moved alone)")
done

printf '\n%s== commands --apply runs ==%s\n' "$B" "$N"
for c in "${cmds[@]}"; do printf '  %s+%s %s\n' "$G" "$N" "$c"; done
printf '\n%s== undo (before reboot) ==%s\n' "$B" "$N"
echo "  mv $top/@/.snapshots $top/$old/.snapshots"
echo "  mv $top/@ $top/@.rolled-back-$ts && mv $top/$old $top/@"
for b in "${blockers[@]}"; do printf '  %sX%s %s\n' "$R" "$N" "$b"; done

if ((!apply)); then
  echo; echo "report only. Re-run with: $0 $num --apply"
  exit 0
fi
((${#blockers[@]} == 0)) || die "refusing: resolve the X items first"

echo
printf '%sThis replaces your root (@) with snapshot #%s. The current root is kept as %s.%s\n' "$Y" "$num" "$old" "$N"
read -r -p 'Type "rollback" to continue: ' ans
[[ $ans == rollback ]] || die "aborted, nothing changed"

set -e
sudo mv "$top/@" "$top/$old"
if ! sudo btrfs subvolume snapshot "$top/$old/.snapshots/$num/snapshot" "$top/@"; then
  sudo mv "$top/$old" "$top/@"
  die "snapshot failed; @ restored, nothing changed"
fi
# a snapshot shows a nested subvolume as an empty directory; clear it, then
# move the real .snapshots subvolume (with all snapper history) across
sudo test -d "$top/@/.snapshots" && sudo rmdir "$top/@/.snapshots"
sudo mv "$top/$old/.snapshots" "$top/@/.snapshots"
# .snapshots-manual is a plain directory: renaming it across subvolumes fails
# and mv would fall back to COPYING the snapshots inside. Move each subvolume
# on its own (subvolume renames across subvolumes are allowed) instead.
for m in "${manual_subs[@]}"; do
  if sudo btrfs subvolume show "$top/$old/.snapshots-manual/$m" >/dev/null 2>&1; then
    sudo mkdir -p "$top/@/.snapshots-manual"
    sudo test -d "$top/@/.snapshots-manual/$m" && sudo rmdir "$top/@/.snapshots-manual/$m" 2>/dev/null
    if sudo test -e "$top/@/.snapshots-manual/$m"; then
      echo "${Y}left .snapshots-manual/$m in $old (target exists)${N}"
    else
      sudo mv "$top/$old/.snapshots-manual/$m" "$top/@/.snapshots-manual/$m"
    fi
  else
    echo "${Y}left .snapshots-manual/$m in $old (not a subvolume)${N}"
  fi
done

printf '\n%sdone.%s Root is now snapshot #%s; the previous root is %s.\n' "$G" "$N" "$num" "$old"
cat <<EOF
Next:
  1. sudo reboot              (do NOT run pacman before rebooting)
  2. sudo grub-mkconfig -o /boot/grub/grub.cfg
  3. when happy, delete the old root:
       sudo mount -o subvolid=5 $dev /mnt
       sudo btrfs subvolume delete /mnt/$old
       sudo umount /mnt
EOF
