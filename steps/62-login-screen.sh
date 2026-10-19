# shellcheck shell=bash
step login-screen optional "SDDM with Ryoku's greeter as the login screen" sudo

# Mirrors ryoku-shell-installer's stepSession: Ryoku's sddm/setup (enable sddm,
# graphical target, keyring PAM, Wayland greeter, cursor fallback), then the
# greeter half of install-qylock (theme + selection). deploy.sh stages the
# in-session lock half, and install-qylock refuses to re-stage it outside
# Ryoku's generation guard, so it is not rerun. Logging in from a TTY instead
# leaves logind treating the session as type=tty, and polkit then denies the
# shell's sleep/lid inhibitors and its auth agent.
#
# Re-runs refresh the greeter theme from the checkout; the wiring is
# idempotent. The theme is replaced only when it differs.
step_login_screen() {
  on sddm || return 0
  need_repo
  local src=$(repo)/ryoku/lockscreen
  pacman -Qq sddm >/dev/null 2>&1 || run sudo pacman -Syu --needed --noconfirm sddm
  if ! systemctl is-enabled --quiet sddm.service 2>/dev/null; then
    say "setting up SDDM (Ryoku's sddm/setup)"
    run sudo -v    # sddm/setup uses sudo -n
    if dry; then bash "$src/sddm/setup" --dry-run; else bash "$src/sddm/setup"; fi
    warn "SDDM starts at the next boot; reboot and log in through it"
  fi
  if ! diff -rq "$src/qylock" /usr/share/ryoku/qylock >/dev/null 2>&1 \
     || [[ ! -d /usr/share/sddm/themes/ryoku ]] \
     || ! grep -qx 'Current=ryoku' /etc/sddm.conf.d/99-ryoku.conf 2>/dev/null; then
    say "installing Ryoku's greeter theme"
    run sudo install -d /usr/share/ryoku /usr/share/sddm/themes /etc/sddm.conf.d
    run sudo rm -rf /usr/share/ryoku/qylock /usr/share/sddm/themes/ryoku
    run sudo cp -a "$src/qylock" /usr/share/ryoku/qylock
    run sudo cp -a /usr/share/ryoku/qylock/themes/clockwork/orbital /usr/share/sddm/themes/ryoku
    run sudo bash -c "printf '[Theme]\\nCurrent=ryoku\\n' > /etc/sddm.conf.d/99-ryoku.conf"
  fi
}
