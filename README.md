# ryoku-aarch64

Installs the [Ryoku](https://github.com/Ryoku-dev/ryoku) desktop on an aarch64
Arch (Asahi ALARM) box by building it from source, and keeps it current.
Upstream ships x86_64 packages only.

```sh
curl -fsSLO https://raw.githubusercontent.com/jccr/ryoku-aarch64/main/ryoku-aarch64.sh
bash ryoku-aarch64.sh --dry-run   # the plan; changes nothing
bash ryoku-aarch64.sh             # install (choices below, e.g. --no-sddm)
```

`ryoku-aarch64.sh` is only a bootstrap: it gets git, clones this repo to
`~/.local/share/ryoku-aarch64`, puts `ryoku-arm` on your PATH and runs
`ryoku-arm install`. From then on:

```sh
ryoku-arm update             # bring everything current
ryoku-arm update --system    # same, plus pacman -Syu (passed to `ryoku update`)
ryoku-arm status             # `ryoku status`, aarch64 checks, your saved choices
ryoku-arm snapshots          # snapper snapshots of /
ryoku-arm rollback 3         # preview making snapshot 3 the root; --apply does it
```

Everything else (`ryoku reload`, `ryoku doctor`, `ryoku version`, ...) is
Ryoku's own CLI and works as-is. Don't use `ryoku rollback`: it drives the
Limine boot menu, which Asahi doesn't have.

## One idempotent path

`install` and `update` run the same ordered steps. Each one checks the machine
and acts only where it differs from what you chose, so running either again
changes nothing on a current box. Both take `--dry-run`. `update` first pulls
this repo and restarts itself, so new steps apply in the same run.

| step | what it makes true |
|---|---|
| preflight | aarch64, a normal user, pacman, systemd |
| pacman-repo | pacman's `[ryoku]` points at an empty local repo (see below) |
| source | the Ryoku checkout (`~/src/ryoku`) exists, on a real `main` branch, fetched |
| deps | everything Ryoku's desktop PKGBUILDs need, plus `packages/session.packages` |
| ryoku-any | Ryoku's arch=any packages (cursors, UI fonts, gpk) at their PKGBUILD versions |
| desktop | the desktop is deployed: `deploy.sh` the first time, `ryoku update` after |
| asahi-desktop | `asahi-desktop-meta` on Asahi (speaker safety, asahi-audio, Vulkan) |
| services | bluetooth, rtkit, power-profiles-daemon enabled |
| login-screen | SDDM with Ryoku's greeter |
| login-shell | `~/.local/bin` on the login PATH; fish as login shell |
| console | a UTF-8 locale and a readable TTY font, when none is set |
| seed | configs a checkout deploy misses; Ryoku's session units enabled |
| apps | Ryoku's preinstalled apps your repos carry |
| aur | Ryoku's AUR set that builds on aarch64 |
| kbd-light | Keyboard Light on MacBooks |
| asahi-fixes | upstream Asahi fixes not yet released |
| lid | the laptop's real lid switch drives Ryoku's lid policy |
| keep-awake-lid | Keep awake also holds a lid close awake |

A failed critical step (preflight through desktop) stops the run; any other
failure is reported at the end and the rest still runs.

### Choices

Set on the command line of `install` or `update` and saved in
`~/.config/ryoku-aarch64/choices`, so every later run honours them. Each on/off
choice is on by default. `--no-X` turns it off and `--X` turns it back on. Turning
off kbd-light, lid or keep-awake-lid also undoes what those steps did; the other
choices only stop the step from running. `ryoku-arm help` lists them all:
`--no-fish`, `--no-sddm`, `--no-asahi-desktop`, `--no-kbd-light`, `--no-apps`,
`--no-aur`, `--no-lid`, `--no-keep-awake-lid`, and `--locale X`,
`--tty-font X` (or `none`), `--dir X`, `--ref X`.

A box installed before choices were saved has them read off the machine on its
first run (fish as your shell? SDDM enabled? a browser installed? yay
present?), printed, and saved, so an update never switches on what you skipped.

### Debugging

```sh
ryoku-arm debug steps                    # the ordered step list
ryoku-arm debug step lid --dry-run       # run one or more steps
ryoku-arm debug choices                  # saved (or inferred) choices
ryoku-arm debug self-update              # pull this repo
```

## Layout

```
ryoku-aarch64.sh   bootstrap (the one file you curl)
ryoku-arm          the CLI: argument parsing and dispatch only
lib/               shared helpers: log, env, choices, upstream, pkg, blocks, steps
steps/NN-name.sh   one step per file; NN is the run order
packages/          package lists (data): session, ryoku-any, desktop-pkgbuilds
fragments/         text inserted into Ryoku's files (marker-delimited)
plugins/           bundled Ryoku shell plugins
tests/run.sh       the test suite (sandboxed; fake sudo, never touches the system)
snapshots-setup.sh, snapshot-rollback.sh   btrfs snapshots (standalone)
```

A new fix is a new `steps/NN-name.sh`: register it with `step name kind "doc"`,
define `step_name`, make it a no-op where it doesn't apply and when the machine
already matches, route every change through `run` (so `--dry-run` works), and
add a choice in `lib/choices.sh` if it should be optional. Then `tests/run.sh`.

## Snapshots first (optional, btrfs root)

```sh
curl -fsSLO https://raw.githubusercontent.com/jccr/ryoku-aarch64/main/snapshots-setup.sh
bash snapshots-setup.sh           # report + plan, changes nothing
bash snapshots-setup.sh --apply   # snapper + snap-pac (+ grub-btrfs if GRUB boots you)
```

`ryoku-arm rollback N [--apply]` (or `snapshot-rollback.sh`) makes snapshot N
the root again. It keeps the old root as `@.pre-rollback-<timestamp>`; `/home`
is untouched. Works from the normal system or from a snapshot booted via GRUB.

## Why each step exists

### pacman-repo
deploy.sh adds `Server = https://repo.ryoku.dev/stable/$arch` when pacman.conf
has no `[ryoku]`. That repo has no aarch64 database, so every later `pacman
-Syu` would fail. The step points `[ryoku]` at an empty local repo
(`/var/lib/ryoku-local`) and backs up `/etc/pacman.conf` to
`/etc/pacman.conf.pre-ryoku-aarch64`.

### deps
Read live from the checkout's PKGBUILDs on `origin/main` (what `ryoku update`
is about to deploy), so the list never drifts from upstream. Never installed,
whatever they say: Ryoku's own packages (deploy.sh builds them into `~/.local`),
`linux-headers`/`dkms` (Asahi boots `linux-asahi`), x86-only bits, and snapper
(`snapshots-setup.sh` owns snapshots). `packages/session.packages` adds what
the session runs that no PKGBUILD names (fish, kitty, the terminal tools the
shell configs call, the TTY font). Installs go through `pacman -Syu --needed`,
never a partial upgrade.

### seed
Ryoku's `deploy.sh` doesn't lay everything a packaged install gets: the
`ryoku-desktop` package stages LazyVim, `starship.toml` and `yazi.toml`, and
Ryoku's installer seeds wallpapers, `~/.npmrc` and a few launcher entries.
Ryoku-owned files are refreshed only while they still match what was laid last
time, so your edits are kept; LazyVim goes only into an empty `~/.config/nvim`
or one Ryoku already owns.

It also enables Ryoku's session units. `ryoku-session.target` starts only units
enabled with `WantedBy=ryoku-session.target` (ryoku-shell, ryogami, ryoku-idle,
ryoku-clamshell); deploy.sh lays them but never enables them, so idle lock and
lid handling were off on a checkout box.

### apps, aur
Ryoku's preinstalled set from its `docs/preinstalled.md`, read live from
`system/packages/base.packages` and `dev.packages` (Chromium, Firefox, mpv, dev
toolchains, flatpak, qemu, docker, ...). Never installed from those lists: the
generic kernel and headers, Limine and the boot chain, network managers.
Anything listed but missing from your repos is reported, not forced. Services
are installed, not enabled.

The AUR set (`aur.packages`) is built like Ryoku's ISO does: bootstrap `yay`,
read each package's PKGBUILD `arch=()` (AUR RPC for the package base, then a
shallow clone), build only `aarch64`/`any` ones, one at a time, best-effort.
Today: yay, Zen browser (which `Mod+B` then prefers over Chromium), LocalSend,
voxtype, the Fraunces font, three cursor themes. `nvibrant-bin` and
`pam-fprint-grosshack` are x86-only and skipped.

### kbd-light
`plugins/keyboard-backlight` is a Ryoku shell plugin: a keyboard mark on the
bar with a slider for the keyboard backlight. The MacBook Air has no
keyboard-brightness keys and Ryoku's sidebar only has screen brightness. The
step also inserts a row into Ryoku's quick settings ("Sound & display", under
screen brightness) inline in the deployed `QuickSettingsHome.qml`: plugins
can't extend quick settings, and Quickshell doesn't register a new `.qml` file
as a type of that folder. Each deploy re-lays the shell, so every update
re-applies it. If Ryoku moves the brightness control, the row is skipped with a
warning instead of breaking the sidebar. Only on Apple laptops with a
`kbd_backlight` LED.

### asahi-fixes
Upstream fixes not yet released, each the exact upstream change (a fixed
package overwrites it with identical content).

- **asahi-audio mic channel position**
  ([`ab1b469`](https://github.com/AsahiLinux/asahi-audio/commit/ab1b46928d056bb02bb4ad72d522dab57dc9efe1),
  after v5.0): the processed mic output is labelled `AUX0`, which Quickshell's
  level meter can't map, so the quick-settings mic row floods the shell log
  with `pipewire.peak ... missing channels`. Relabelled `MONO`.

### lid
On a MacBook, closing the lid did nothing: the panel stayed on and the machine
never slept. Hyprland matches switch binds by device name, and Ryoku's
`modules/lid.lua` binds only `Lid Switch` (the ACPI lid button on x86). On
Asahi the lid is the SMC input `Apple SMC power/lid events`, so the close never
reached `ryoku-clamshell`, and since its daemon holds logind's
`handle-lid-switch` inhibitor, logind didn't suspend either.

The step binds every input device that reports a lid switch (`SW_LID` in
`/proc/bus/input/devices`) under another name to the same `ryoku-clamshell lid
close` / `lid open` commands, in a marked block at the end of
`~/.config/hypr/user.lua` (yours; deploys never touch it). The policy is
Ryoku's own: lock and suspend, or hand off to an external display when docked
on AC.

Hyprland reloads when `user.lua` changes, and a reload re-reads the lid: with
the lid shut and no dock, that suspends the machine at once (and drops an SSH
session). So while the lid is shut the step skips with a warning.

### keep-awake-lid
Ryoku's Keep awake toggle (the bar button and the quick-settings tile, both
`ryoku-cmd-caffeine`) holds a systemd `idle:sleep` inhibitor. That stops idle
timers but not the lid: logind ignores a user's own inhibitors when that same
user asks to suspend, and the lid policy (`ryoku-clamshell` -> `ryoku-shell
suspend` -> login1 `Suspend`) runs as you.

The step inserts `fragments/clamshell/keep-awake.sh.frag` into the deployed
`~/.local/bin/ryoku-clamshell` (between `ryoku-aarch64 keep-awake` markers; the
script has no hook). While Keep awake is on, a non-docked lid close locks the
session and turns the display off instead of suspending; opening the lid turns
it back on. That covers every lid-driven suspend: the close, the lid re-check
when Hyprland starts or reloads, and the daemon's suspend when a closed laptop
loses its dock. Docked behaviour is untouched. Turning Keep awake off while the
lid is shut doesn't suspend at once; the idle timers take over.

The file is replaced by rename, never rewritten in place, so the running
daemon isn't disturbed; the daemon is restarted only while the lid is open (a
restart briefly hands the lid to logind, which would suspend a closed laptop).
If Ryoku reshapes the script, the step is skipped with a warning.
