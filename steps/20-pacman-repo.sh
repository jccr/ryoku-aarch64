# shellcheck shell=bash
step pacman-repo critical "point pacman's [ryoku] at an empty local repo"

# deploy.sh adds Server = https://repo.ryoku.dev/stable/$arch when pacman.conf
# has no [ryoku], and leaves one that points anywhere else alone. That repo has
# no aarch64 db, so every later `pacman -Syu` would fail. Give it a local,
# empty repo instead. Both the db and the files db must exist, or pacman -Fy
# fails "failed retrieving file 'ryoku.files'".
LOCAL_REPO=/var/lib/ryoku-local
PACMAN_CONF=${RYOKU_ARM_PACMAN_CONF:-/etc/pacman.conf}

step_pacman_repo() {
  local changed=0 kind
  if grep -q '^\[ryoku\]' "$PACMAN_CONF"; then
    if awk '/^\[ryoku\]/{f=1;next} /^\[/{f=0} f && /repo\.ryoku\.dev/{hit=1} END{exit !hit}' "$PACMAN_CONF"; then
      say "repointing the [ryoku] stanza at $LOCAL_REPO"
      run sudo cp "$PACMAN_CONF" "$PACMAN_CONF.pre-ryoku-aarch64"
      run sudo sed -i "/^\[ryoku\]/,/^\[/ { s|^SigLevel *=.*|SigLevel = Never|; s|^Server *=.*|Server = file://$LOCAL_REPO| }" "$PACMAN_CONF"
      changed=1
    fi
  else
    say "adding a local [ryoku] stanza ($LOCAL_REPO)"
    run sudo cp "$PACMAN_CONF" "$PACMAN_CONF.pre-ryoku-aarch64"
    run sudo bash -c "printf '\n[ryoku]\nSigLevel = Never\nServer = file://%s\n' '$LOCAL_REPO' >> '$PACMAN_CONF'"
    changed=1
  fi
  for kind in db files; do
    [[ -e $LOCAL_REPO/ryoku.$kind ]] && continue
    run sudo install -d "$LOCAL_REPO"
    run sudo tar -czf "$LOCAL_REPO/ryoku.$kind.tar.gz" --files-from /dev/null
    run sudo ln -sf "ryoku.$kind.tar.gz" "$LOCAL_REPO/ryoku.$kind"
    changed=1
  done
  if ((changed)); then
    say "undo with: sudo cp $PACMAN_CONF.pre-ryoku-aarch64 $PACMAN_CONF"
  fi
}
