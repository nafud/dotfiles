<div align="center">

**A machine-neutral Arch Linux workspace built around the
[niri](https://github.com/YaLTeR/niri) tiling compositor and a
keyboard-driven terminal stack, everything in JetBrains Mono.**

<img src="assets/desk.jpg" alt="the desk at rest, the bar over the wallpaper" width="100%">

</div>

The base system comes from the
[Arch Linux guide](https://nafud.github.io/kiln/guides/arch-linux/),
whose installer closes with this table, here from a run on the test
machine.

```
[install] installed and configured
  [ + ] Disk           GPT on /dev/vda: 1G ESP, 1G ext4 /boot, LUKS2 root
  [ + ] Filesystem     btrfs @ @home @log @pkg @snapshots, zstd, noatime
  [ + ] Kernels        linux, linux-lts, intel-ucode
  [ + ] Initramfs      encrypt hook, snapshot overlay, both images
  [ + ] GRUB           EFI entry, cryptdevice line, mainline on top
  [ + ] Time, locale   Europe/Prague, en_US.UTF-8, keymap us
  [ + ] Identity       forge; root and smith in wheel, sudo
  [ + ] Graphics       mesa (no vendor package for this GPU)
  [ + ] First boot     NetworkManager, timesyncd, fstrim.timer
  [ + ] Snapshots      snapper on @snapshots, snap-pac, grub-btrfs, timers
  [ + ] zram           half of RAM, zstd; zswap off on the kernel line
  [ + ] Firewall       nftables, input and forward drop, enabled
  [ + ] Kernel         sysctl hardening, module refusals
  [ + ] Core, journal  no core storage, 1G journal, /boot root-only
  [ + ] sudo, logins   editor pinned, faillock five in fifteen
  [ + ] Privacy        NetworkManager identity, resolved without fallbacks
  [ + ] Boundaries     five drop-ins, mullvad-net-cls, sandbox-check
  [ + ] No sshd        installed for later, not enabled
  [ + ] Record         etckeeper: two commits, daily timer, package list
```

What one run of setup.sh installs and links, as it reports at the end.

```
[setup] installed components
  [ + ] Niri           scrollable-tiling Wayland compositor
  [ + ] Dotfiles       config, bin, icons, applications linked; templates copied
  [ + ] Session units  waybar, mako, wallpaper, swayidle, polkit-agent, udiskie, cliphist
  [ + ] Xwayland-sat.  X11 bridge, auto-spawned by niri
  [ + ] Plymouth       boot splash (mono theme)
  [ + ] Greetd         login page (monogreet on niri)
  [ + ] PipeWire       audio server (pulse shim)
  [ + ] Portals        xdg-desktop-portal gtk + gnome
  [ + ] SSH agent      gcr-ssh-agent (gcr-4)
  [ + ] Polkit agent   polkit-gnome (the password dialogs)
  [ + ] Bluetooth      bluez + bluetui (bar module, popup)
  [ + ] Alacritty      terminal emulator
  [ + ] Rofi           application launcher (wayland 2.0)
  [ + ] Waybar         status bar
  [ + ] Mako           notification daemon
  [ + ] Swaybg         wallpaper daemon
  [ + ] Hyprlock       screen locker
  [ + ] Swayidle       idle manager
  [ + ] Yazi           terminal file manager (+ ya)
  [ + ] Zellij         terminal multiplexer
  [ + ] Cliphist       clipboard history
  [ + ] Udiskie        removable-media automount
  [ + ] exFAT          exfatprogs (mounting exFAT media)
  [ + ] Starship       shell prompt
  [ + ] Btop           system monitor
  [ + ] Neovim         text editor
  [ + ] Files          GUI file manager (nautilus)
  [ + ] NetworkMgr     network stack (bar module, netmenu)
  [ + ] Zathura        PDF viewer
  [ + ] Imv            image viewer
  [ + ] Mpv            media player
  [ + ] Paru           AUR helper (manual installs, updates)
  [ + ] Chafa          terminal image renderer (yazi preview)
  [ + ] Archives       7zip + unzip (yazi preview and extract)
  [ + ] Fzf            fuzzy finder
  [ + ] Zoxide         directory jumper
  [ + ] Eza            ls replacement
  [ + ] Bat            cat with highlighting
  [ + ] Fd             find replacement
  [ + ] Ripgrep        grep replacement (rg)
  [ + ] Delta          git diff pager
  [ + ] Checkupdates   update probe (bar's updates module)
  [ + ] Wl-clipboard   Wayland clipboard (wl-copy/wl-paste)
  [ + ] Brightnessctl  backlight control
  [ + ] Pulsemixer     audio mixer popup
  [ + ] Ksnip          screenshot annotator
  [ + ] Screenshots    grim + slurp (shot-annotate, shot-ocr)
  [ + ] OCR            tesseract (shot-ocr)
  [ + ] Recorder       gpu-screen-recorder (record-toggle)
  [ + ] Nerd Font      JetBrainsMono Nerd Font
```

Install the base system with the
[Arch Linux guide](https://nafud.github.io/kiln/guides/arch-linux/),
then deploy the workspace with one command. The repository is the
workspace alone: the base system, its policy and its hardening are
chapters of the guide, applied on the machine and recorded there.

```
curl -fsSL https://raw.githubusercontent.com/nafud/dotfiles/main/bootstrap.sh | bash
```
