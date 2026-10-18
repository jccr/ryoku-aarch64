#!/usr/bin/env bash
# snapshots-setup.sh — set up snapper (+ snap-pac, + grub-btrfs boot menu when
# GRUB is in the boot chain) on an Asahi ALARM btrfs root, BEFORE running
# ryoku-aarch64.sh, so the Ryoku install gets pre/post snapshots.
#
#   ./snapshots-setup.sh           report + plan only (changes nothing)
#   ./snapshots-setup.sh --apply   carry out the plan
#
# The report is sized to fit one screen so it can be photographed.
# --apply refuses on anything it does not recognise instead of guessing.
set -uo pipefail

apply=0
[[ ${1:-} == --apply ]] && apply=1

B=$'\033[1m' Y=$'\033[33m' R=$'\033[31m' G=$'\033[32m' N=$'\033[0m'
kv()   { printf '%-14s %s\n' "$1" "$2"; }
hdr()  { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
blockers=() plan=() notes=()
block() { blockers+=("$*"); }
step()  { plan+=("$*"); }
note()  { notes+=("$*"); }

[[ $EUID -ne 0 ]] || { echo "run as your normal user (sudo is used where needed)"; exit 1; }
sudo -v || exit 1

# ------------------------------------------------------------------ gather
hdr "system"
kv arch "$(uname -m)  kernel $(uname -r)"
kv kernel-pkg "$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null || echo '?')"
kv boot-pkgs "$(pacman -Qq 2>/dev/null | grep -E '^(grub|uboot.*|u-boot.*|m1n1|asahi-.*|efibootmgr|systemd-boot.*|limine)$' | tr '\n' ' ')"

hdr "root fs"
root_fs=$(findmnt -no FSTYPE /)
root_src=$(findmnt -no SOURCE /)
root_opts=$(findmnt -no OPTIONS /)
root_subvol=$(sed -n 's/.*subvol=\([^,]*\).*/\1/p' <<<"$root_opts")
kv fstype "$root_fs"
kv source "$root_src"
kv subvol "${root_subvol:-(none)}"
[[ $root_fs == btrfs ]] || block "root is $root_fs, not btrfs: snapshots are impossible"

home_fs=$(findmnt -no FSTYPE /home 2>/dev/null)
if [[ -n $home_fs ]]; then
  kv /home "$home_fs $(findmnt -no SOURCE /home)"
else
  kv /home "(part of /)"
fi

if [[ $root_fs == btrfs ]]; then
  kv free "$(sudo btrfs filesystem usage -b / 2>/dev/null | awk '/Free \(estimated\)/{printf "%.1f GiB", $3/1073741824}')"
  echo "subvolumes:"
  sudo btrfs subvolume list / 2>/dev/null | awk '{print "  " $NF}' | head -12
fi

hdr "/.snapshots"
snapcfg=0
[[ -f /etc/snapper/configs/root ]] && snapcfg=1
if [[ ! -e /.snapshots ]]; then
  snapstate=absent
elif sudo btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  snapstate=subvolume
elif [[ -d /.snapshots ]] && [[ -z $(sudo ls -A /.snapshots) ]]; then
  snapstate=empty-dir
elif [[ -d /.snapshots ]]; then
  snapstate=dir-with-content
else
  snapstate=other
fi
kv state "$snapstate"
kv snapper-cfg "$([[ $snapcfg == 1 ]] && echo 'root config exists' || echo none)"
[[ $snapstate == dir-with-content ]] && kv contents "$(sudo ls -A /.snapshots | head -5 | tr '\n' ' ')"
grep -qE '^[^#]*[[:space:]]/\.snapshots[[:space:]]' /etc/fstab && kv fstab "/.snapshots has its own fstab entry"

hdr "boot chain"
grubcfg=""
for c in /boot/grub/grub.cfg /boot/efi/grub/grub.cfg /efi/grub/grub.cfg; do
  [[ -f $c ]] && { grubcfg=$c; break; }
done
has_grub=0; command -v grub-mkconfig >/dev/null && [[ -n $grubcfg ]] && has_grub=1
kv /boot "$(findmnt -no FSTYPE,SOURCE /boot 2>/dev/null || echo '(on /)')"
kv grub.cfg "${grubcfg:-none}"
kv grub "$([[ $has_grub == 1 ]] && echo yes || echo no)"
hooks=$(bash -c 'source /etc/mkinitcpio.conf 2>/dev/null; for f in /etc/mkinitcpio.conf.d/*.conf; do [ -f "$f" ] && source "$f"; done; echo "${HOOKS[*]}"' 2>/dev/null)
kv HOOKS "$hooks"
systemd_initrd=0; [[ " $hooks " == *" systemd "* ]] && systemd_initrd=1

hdr "repos"
avail() { pacman -Si "$1" >/dev/null 2>&1 && echo yes || echo no; }
for p in snapper snap-pac grub-btrfs inotify-tools; do
  kv "$p" "$(avail "$p")$(pacman -Qq "$p" >/dev/null 2>&1 && echo ' (installed)')"
done

# ------------------------------------------------------------------ plan
if ((${#blockers[@]} == 0)); then
  [[ $(avail snapper) == yes ]] || block "snapper not in repos"
  [[ $(avail snap-pac) == yes ]] || block "snap-pac not in repos"
  step "pacman -S --needed snapper snap-pac"

  if ((snapcfg)); then
    note "snapper root config already exists; reusing it"
  else
    case $snapstate in
      absent)    ;;
      empty-dir) step "rmdir /.snapshots (empty; snapper must create it)" ;;
      dir-with-content)
        step "mv /.snapshots /.snapshots-manual (keeps your manual snapshots)"
        note "manual snapshots kept under /.snapshots-manual; delete them later with btrfs subvolume delete" ;;
      subvolume) block "/.snapshots is a subvolume but there is no snapper config (custom layout: send me the report)" ;;
      *)         block "/.snapshots is something unexpected" ;;
    esac
    step "snapper -c root create-config /"
  fi
  step "snapper: TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 ALLOW_USERS=$USER"
  step "systemctl enable --now snapper-cleanup.timer"

  if ((has_grub)); then
    if [[ $(avail grub-btrfs) == yes ]]; then
      step "pacman -S --needed grub-btrfs inotify-tools"
      step "systemctl enable --now grub-btrfsd (menu refreshes on every snapshot)"
      if ((systemd_initrd)); then
        note "systemd initramfs: skipping grub-btrfs-overlayfs; snapshots boot read-only"
      else
        step "mkinitcpio drop-in: append grub-btrfs-overlayfs to HOOKS, mkinitcpio -P"
      fi
      step "grub-mkconfig -o $grubcfg"
    else
      note "grub-btrfs not in repos: no boot-menu entries (snapshots still taken)"
    fi
  else
    note "no GRUB found: snapshots work, but no boot menu; rollback = manual subvolume swap"
  fi
  step "snapper create -d pre-ryoku (important)"
fi

hdr "plan"
for s in "${plan[@]}"; do printf '  %s+%s %s\n' "$G" "$N" "$s"; done
for n in "${notes[@]}"; do printf '  %s*%s %s\n' "$Y" "$N" "$n"; done
for b in "${blockers[@]}"; do printf '  %sX%s %s\n' "$R" "$N" "$b"; done

if ((!apply)); then
  echo; echo "report only. Re-run with --apply to carry out the plan."
  exit 0
fi
((${#blockers[@]} == 0)) || { echo; echo "${R}refusing to apply: resolve the X items first${N}"; exit 1; }

# ------------------------------------------------------------------ apply
set -e
hdr "applying"
sudo pacman -S --needed --noconfirm snapper snap-pac

if ((!snapcfg)); then
  case $snapstate in
    empty-dir)        sudo rmdir /.snapshots ;;
    dir-with-content) sudo mv /.snapshots /.snapshots-manual ;;
  esac
  sudo snapper -c root create-config /
fi
sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 \
  NUMBER_LIMIT_IMPORTANT=5 "ALLOW_USERS=$USER" SYNC_ACL=yes
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl disable --now snapper-timeline.timer 2>/dev/null || true

if ((has_grub)) && [[ $(avail grub-btrfs) == yes ]]; then
  sudo pacman -S --needed --noconfirm grub-btrfs inotify-tools
  sudo systemctl enable --now grub-btrfsd.service
  if ((!systemd_initrd)) && [[ " $hooks " != *" grub-btrfs-overlayfs "* ]]; then
    printf '# added by snapshots-setup.sh: boot read-only snapshots via overlayfs\nHOOKS=(%s grub-btrfs-overlayfs)\n' "$hooks" \
      | sudo tee /etc/mkinitcpio.conf.d/90-grub-btrfs-overlayfs.conf >/dev/null
    sudo mkinitcpio -P
  fi
  sudo grub-mkconfig -o "$grubcfg"
fi

sudo snapper -c root create -d "pre-ryoku" --userdata important=yes
echo
snapper -c root list | tail -5
echo
echo "${G}done.${N} snap-pac now snapshots every pacman run, including the Ryoku install."
((has_grub)) && echo "GRUB menu: 'Arch Linux snapshots' submenu lists them."
