# Keyboard Light

A Ryoku bar widget for the keyboard backlight. Click the keyboard mark on the bar
to open a panel with a slider, - / + steps, and OFF / 50% / MAX presets. The mark
is lit in the accent while the backlight is on.

Made for MacBooks on Asahi Linux: the Air's function row has no keyboard
brightness keys (macOS moved it to Control Center), and Ryoku's own sidebar only
has screen brightness. Works on any laptop that exposes a `*kbd_backlight*` LED.

## What it runs, reads and writes

- **Runs:** `brightnessctl` only, with argv arrays (no shell):
  `brightnessctl -m -d '*kbd_backlight*' info` to read, and
  `... set N%` to write. It polls every 1.5 s while the panel is open and every
  15 s otherwise, so keybind changes show up.
- **Reads/writes:** the LED's brightness through brightnessctl, which goes
  through systemd-logind for your active session. No files of its own.
- **Privileges:** none. No `sudo`, no `pkexec`: logind lets the active seat
  session set LED brightness. (It will not work from an SSH session.)
- **Network:** none.

## Settings

- *Step for the - / + buttons* (1-50, default 10)
- *Show the level beside the mark* (default off)

## Install

```sh
ryoku plugin add <this folder> --bar --yes
```
