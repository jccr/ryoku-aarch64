# ryoku-aarch64

Installs the [Ryoku](https://github.com/Ryoku-dev/ryoku) desktop on an aarch64
Arch (Asahi ALARM) box by building it from source. Upstream ships x86_64 only.

```sh
curl -fsSLO https://raw.githubusercontent.com/jccr/ryoku-aarch64/main/ryoku-aarch64.sh
chmod +x ryoku-aarch64.sh
./ryoku-aarch64.sh --dry-run   # preview
./ryoku-aarch64.sh          # also sets fish as login shell (--no-fish) and a UTF-8 locale if none (--locale en_CA.UTF-8) and a readable TTY font if none (--tty-font ter-v24n / none), and SDDM with the Ryoku greeter as the login (--no-sddm)
```

Update later with `git -C ~/src/ryoku pull && ~/src/ryoku/ryoku/shell/deploy.sh`.
Don't use `ryoku update`; it pulls from the x86_64 repo.

## Snapshots first (optional, btrfs root)

```sh
curl -fsSLO https://raw.githubusercontent.com/jccr/ryoku-aarch64/main/snapshots-setup.sh
chmod +x snapshots-setup.sh
./snapshots-setup.sh           # report + plan, changes nothing
./snapshots-setup.sh --apply   # snapper + snap-pac (+ grub-btrfs if GRUB boots you)
```

## Rolling back to a snapshot

```sh
./snapshot-rollback.sh            # list snapshots
./snapshot-rollback.sh 3          # report + exact commands, changes nothing
./snapshot-rollback.sh 3 --apply  # swap @ for snapshot 3 (asks to type "rollback")
```

Keeps the old root as `@.pre-rollback-<timestamp>`; `/home` is untouched.
Works from the normal system or from a snapshot booted via GRUB.

## Updating: `ryoku-arm`

The installer puts `ryoku-arm` on your PATH. It fills the one gap a source-built
Ryoku box has on aarch64 (no `[ryoku]` packages to pull in new dependencies),
then hands off to Ryoku's own CLI.

```sh
ryoku-arm update            # deps + cursors/fonts from upstream, then `ryoku update`
ryoku-arm update --system   # same, plus `pacman -Syu` (passed through to ryoku)
ryoku-arm deps              # what Ryoku's PKGBUILDs want that you're missing
ryoku-arm status            # `ryoku status` + aarch64 checks (login type, packages)
ryoku-arm snapshots         # snapper snapshots of /
ryoku-arm rollback 3        # preview making snapshot 3 the root; add --apply to do it
ryoku-arm self-update       # refresh these scripts
```

Dependencies are read from Ryoku's PKGBUILDs on `origin/main` each run, so they
never drift from upstream. Everything else (`ryoku reload`, `ryoku doctor`,
`ryoku version`, …) is Ryoku's own CLI and works as-is. Don't use `ryoku
rollback`: it drives the Limine boot menu, which Asahi doesn't have.
