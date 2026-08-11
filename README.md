# niri dotfiles

![check](https://github.com/nafud/niri/actions/workflows/check.yml/badge.svg)

My Arch Linux workspace: the [niri](https://github.com/YaLTeR/niri)
scrollable-tiling Wayland compositor and a keyboard-driven terminal stack
(alacritty, zellij, yazi, waybar, rofi, mako, starship), everything in
JetBrains Mono. Nearly everything comes from the official repositories;
a small AUR set (Mullvad VPN, Chrome, Mullvad Browser) installs through
paru, which setup.sh bootstraps.

## Fresh machine

Base system first: [docs/arch-install.md](docs/arch-install.md) (encrypted
btrfs, snapshots, zram). Then one command:

```
curl -fsSL https://raw.githubusercontent.com/nafud/niri/main/bootstrap.sh | bash
```

It clones this repo into `~/niri` (HTTPS — no SSH key needed to receive;
the push URL is set to SSH for when the key is restored) and hands off to
`setup.sh`. Equivalent by hand:

```
git clone https://github.com/nafud/niri.git ~/niri
bash ~/niri/setup.sh
```

Then reboot (or log out) and pick the **niri** session in tuigreet. Both
paths are idempotent (safe to run again at any time) and end with a probed
component summary, so what it reports installed is what is actually on disk.

## Layout

| Path | Purpose |
|---|---|
| `config/` | Mirrors `~/.config`; symlinked there by setup.sh |
| `bin/` | Mirrors `~/.local/bin`; symlinked the same way |
| `setup.sh` | Packages (official repos), system glue (greetd, units, MIME, shell block), linking |

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

## Key bindings (selection)

| Keys | Action |
|---|---|
| `Mod+T` / `Mod+Return` | terminal / floating terminal |
| `Mod+D` | app launcher (rofi, fuzzy) |
| `Mod+Space` | window switcher (rofi) |
| `Mod+E` | file manager (yazi) |
| `Mod+B` / `Mod+N` / `Mod+A` | btop / network / audio popups |
| `Mod+V` | clipboard history |
| `Mod+Escape` | power menu |
| `Mod+Shift+D` | dismiss notifications |
| `Mod+Shift+L` | lock |
| `Print` / `Mod+Print` | screenshot / annotate region |
| `Mod+Shift+Slash` | full binding overlay |

## Commands

```
bash setup.sh          # full run: install everything + link configs
bash setup.sh link     # (re)link configs + validate + reload only
bash setup.sh summary  # print the probed component summary
```
