# niri dotfiles

![check](https://github.com/nafud/niri/actions/workflows/check.yml/badge.svg)

My Linux Mint 22.x workspace: the [niri](https://github.com/YaLTeR/niri)
scrollable-tiling Wayland compositor and a keyboard-driven terminal stack
(alacritty, zellij, yazi, waybar, fuzzel, mako, starship), everything in
JetBrains Mono.

## Fresh machine

```
git clone https://github.com/nafud/niri.git ~/niri
bash ~/niri/setup.sh
```

Then log out and choose the **niri** session at the greeter. The script is
idempotent (safe to run again at any time) and ends with a probed component
summary, so what it reports installed is what is actually on disk.

## Layout

| Path | Purpose |
|---|---|
| `config/` | Mirrors `~/.config`; symlinked there by setup.sh |
| `bin/` | Mirrors `~/.local/bin`; symlinked the same way |
| `setup.sh` | Packages, the niri build, fonts, release binaries, system glue, linking |

Because `~/.config` entries are symlinks into this repo, the repo is the
single source of truth and edits are live: change a file here and niri or
starship pick it up on save. Anything that was in the way when a link was
first made is kept next to it as `<name>.pre-dotfiles`.

## Daily changes

Edit the file under `~/niri/config/`, watch it apply, then record it:

```
git -C ~/niri add -A
git -C ~/niri commit -m "describe the change"
git -C ~/niri push
```

Run `bash ~/niri/setup.sh link` after a `git pull` that brings new files
(it relinks, validates the niri config, and restarts the bar if needed).
To add a new application's config, create `config/<app>/` and run the same
command.

## Commands

```
bash setup.sh          # full run: install everything + link configs
bash setup.sh link     # (re)link configs + validate + reload only
bash setup.sh update   # refresh pacstall builds, release binaries, hellwal
bash setup.sh summary  # print the probed component summary
```
