# shellcheck shell=bash
step console optional "a UTF-8 system locale and a readable TTY font, when unset" sudo

# Qt (and the whole desktop) wants a UTF-8 locale; a fresh ALARM install has
# none and runs as "C". An existing UTF-8 LANG is left alone.
console_locale() {
  local cur lang
  lang=$(choice locale)
  cur=$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | tr -d '"')
  [[ $cur == *UTF-8* || $cur == *utf8* ]] && return 0
  [[ $lang == *.UTF-8 ]] || { warn "--locale must be a UTF-8 locale, e.g. en_US.UTF-8; skipped"; return 1; }
  grep -qE "^#?[[:space:]]*${lang//./\\.}[[:space:]]+UTF-8" /etc/locale.gen \
    || { warn "$lang is not listed in /etc/locale.gen; skipped"; return 1; }
  say "setting the system locale to $lang (was ${cur:-unset})"
  run sudo sed -i -E "s/^#[[:space:]]*(${lang//./\\.}[[:space:]]+UTF-8)/\\1/" /etc/locale.gen
  run sudo locale-gen
  run sudo localectl set-locale "LANG=$lang" \
    || run sudo bash -c "printf 'LANG=%s\\n' '$lang' > /etc/locale.conf"
  warn "log out and back in for the new locale to apply"
}

# The default kernel console font is tiny on a Retina panel and lacks the
# box-drawing glyphs Ryoku's login greeting and prompt use. An existing FONT=
# wins.
console_font() {
  local font
  font=$(choice tty_font)
  [[ $font != none ]] || return 0
  grep -qE '^[[:space:]]*FONT=' /etc/vconsole.conf 2>/dev/null && return 0
  if [[ ! -e /usr/share/kbd/consolefonts/$font.psf.gz ]]; then
    warn "console font $font not found under /usr/share/kbd/consolefonts; skipped"; return 0
  fi
  say "setting the TTY font to $font"
  run sudo bash -c "printf 'FONT=%s\\n' '$font' >> /etc/vconsole.conf"
  run sudo systemctl restart systemd-vconsole-setup.service || true
}

step_console() {
  local rc=0
  console_locale || rc=1
  console_font
  return "$rc"
}
