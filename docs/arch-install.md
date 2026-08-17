# Arch Linux Install

The canonical installation guide lives in Kiln:
**[Arch Linux](https://nafud.github.io/kiln/guides/arch-linux/)** —
ISO verification, disk layout (LUKS2 + btrfs), base system, system
configuration, first boot, snapshots, zram swap, the workspace
bootstrap that lands back in this repo, and post-install Secure Boot.
It is maintained against the ArchWiki and updated as the field teaches;
this file deliberately no longer duplicates it.

What stays here is the pre-ISO checklist — the only part that runs on
the outgoing OS, before the disk is wiped.

## Before booting the ISO

1. **Back up what dies with the disk.** The workspace config is in this
   repo, but sweep the current OS for everything else: SSH keys
   (`~/.ssh` — needed to push to this repo from the new system), GPG
   keys, browser profiles, `~/Documents`, any dotfiles not committed
   here.
2. **Disable Secure Boot.** The Arch ISO's bootloader carries no Secure
   Boot signature and will not boot with it enabled. Enter firmware
   setup (F1/F2/Del at power-on, vendor-dependent) → Security →
   Secure Boot → Disabled. The Kiln guide's closing section covers
   re-enabling it with custom keys after the install.
