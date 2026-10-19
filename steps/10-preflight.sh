# shellcheck shell=bash
step preflight critical "aarch64, a normal user, pacman and systemd"

step_preflight() {
  [[ $(uname -m) == aarch64 ]] || die "this is for aarch64; on x86_64 use Ryoku's own installer"
  [[ $EUID -ne 0 ]] || die "run as your normal user; sudo is used where needed"
  command -v pacman >/dev/null || die "pacman not found"
  [[ -d /run/systemd/system ]] || die "Ryoku needs systemd"
  if is_asahi; then say "Apple Silicon / Asahi"; fi
}
