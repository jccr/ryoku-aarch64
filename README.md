# ryoku-aarch64

Installs the [Ryoku](https://github.com/Ryoku-dev/ryoku) desktop on an aarch64
Arch (Asahi ALARM) box by building it from source. Upstream ships x86_64 only.

```sh
curl -fsSLO https://raw.githubusercontent.com/jccr/ryoku-aarch64/main/ryoku-aarch64.sh
chmod +x ryoku-aarch64.sh
./ryoku-aarch64.sh --dry-run   # preview
./ryoku-aarch64.sh          # add --fish to switch your login shell to fish (Ryoku's default)
```

Update later with `git -C ~/src/ryoku pull && ~/src/ryoku/ryoku/shell/deploy.sh`.
Don't use `ryoku update`; it pulls from the x86_64 repo.
