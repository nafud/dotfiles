# niri

One-shot bootstrap for my Linux Mint 22.x workspace: the [niri](https://github.com/YaLTeR/niri)
scrollable-tiling Wayland compositor and the terminal stack around it
(alacritty, zellij, yazi, waybar, fuzzel, mako, starship), everything in
JetBrains Mono.

## Usage

```
bash setup.sh
```

Idempotent, safe to re-run. The script is the single source of truth: every
config is written from it. Hand-edit a config to experiment, then fold the
change back into the script; a re-run keeps any overwritten edit as a `.prev`
copy next to the file. When it finishes, log out and choose the **niri**
session at the greeter. It prints a probed component summary at the end, so
what it reports installed is what is actually on disk.
