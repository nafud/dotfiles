# Arch Linux Manual Installation Guide

Manual (no archinstall) installation of Arch Linux, built step by step.
Target: encrypted btrfs root with snapshot support, GRUB, niri workspace on top.

## Hardware

- Lenovo ThinkBook 14 G2 ITL (20VD)
- Intel Core i7-1165G7 (Tiger Lake, 4c/8t) — Intel Iris Xe graphics (`i915`)
- 24 GB RAM
- 477 GB NVMe SSD (`/dev/nvme0n1`)
- UEFI; Secure Boot currently **on** (Linux Mint) — must be disabled before
  booting the Arch ISO (see Step 0)
- Intel Wi-Fi (iwlwifi)
- Currently running Linux Mint (will be wiped)

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Filesystem | btrfs on LUKS2 (no LVM) | Subvolumes replace fixed-size volumes; snapshots before updates (snapper + grub-btrfs) on a rolling release. ZFS considered and rejected: out-of-tree module on a rolling kernel, and its multi-disk strengths don't apply to a single-NVMe laptop |
| Bootloader | GRUB | Required for grub-btrfs boot-into-snapshot entries |
| `/boot` | Separate unencrypted ext4 partition | GRUB never has to unlock LUKS; LUKS2/argon2id defaults stay |
| Kernels | `linux` + `linux-lts` | Snapshots don't cover `/boot`; LTS kernel is the fallback for kernel breakage |
| Swap | zram only (post-install) | No swap partition or swapfile. Hibernation not wanted — plain suspend covers the use case |
| Secure Boot | Off for install and after | Arch ISO is unsigned. Optional later: re-enable with `sbctl` + custom keys (post-install project, not covered here) |
| Encryption TRIM | via kernel cmdline / crypttab later | SSD discard passthrough, handled in the chroot step |

---

## Step 0 — Before booting the ISO

1. **Back up what dies with the disk.** The niri config is in this repo, but
   sweep the Mint install for everything else: SSH keys (`~/.ssh` — needed to
   clone this repo from the new system), GPG keys, browser profiles,
   `~/Documents`, any dotfiles not committed here.
2. **Disable Secure Boot.** Mint boots via Microsoft-signed shim; the Arch ISO
   is unsigned and will not boot with Secure Boot enabled. Enter firmware
   setup (F1 at power-on on ThinkBooks) → Security → Secure Boot → Disabled.
   Leave it off after the install (re-enabling later via `sbctl` with custom
   keys is possible but out of scope).

---

## Step 1 — Disk setup (partition, encrypt, btrfs, mount)

> **WARNING:** this wipes the entire disk, including the existing Linux Mint install.

### 1.1 Sanity checks

```sh
cat /sys/firmware/efi/fw_platform_size    # should print 64 (UEFI mode)
lsblk -d -o NAME,SIZE,MODEL               # confirm the target disk is nvme0n1
```

### 1.2 Partition

```sh
fdisk /dev/nvme0n1
```

Inside fdisk: `g` (new GPT table), then `n` three times, `t` to set p1's type
to `1` (EFI System), `w` to write.

| Partition | Size | Type | Purpose |
|---|---|---|---|
| `nvme0n1p1` | 1G | EFI System | ESP, mounted at `/boot/efi` |
| `nvme0n1p2` | 1G | Linux | `/boot`, unencrypted ext4 |
| `nvme0n1p3` | rest (~475G) | Linux | LUKS2 container |

### 1.3 Format the plain partitions

```sh
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2
```

### 1.4 Encryption

```sh
cryptsetup luksFormat /dev/nvme0n1p3      # LUKS2 + argon2id defaults
cryptsetup open /dev/nvme0n1p3 cryptroot
```

### 1.5 btrfs + subvolumes

```sh
mkfs.btrfs -L arch /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@            # /
btrfs subvolume create /mnt/@home        # /home
btrfs subvolume create /mnt/@log         # /var/log      (excluded from rollbacks)
btrfs subvolume create /mnt/@pkg         # /var/cache/pacman/pkg (excluded)
btrfs subvolume create /mnt/@snapshots   # /.snapshots   (snapper home)
umount /mnt
```

### 1.6 Mount everything

```sh
o=compress=zstd,noatime
mount -o subvol=@,$o /dev/mapper/cryptroot /mnt
mount --mkdir -o subvol=@home,$o      /dev/mapper/cryptroot /mnt/home
mount --mkdir -o subvol=@log,$o       /dev/mapper/cryptroot /mnt/var/log
mount --mkdir -o subvol=@pkg,$o       /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount --mkdir -o subvol=@snapshots,$o /dev/mapper/cryptroot /mnt/.snapshots
mount --mkdir /dev/nvme0n1p2 /mnt/boot
mount --mkdir /dev/nvme0n1p1 /mnt/boot/efi
```

Notes:

- `compress=zstd` — transparent compression, typically 30–50% savings on
  system files, negligible CPU cost.
- No sizes anywhere: all subvolumes share the same ~473 G pool.
- Reminder for the chroot step: mkinitcpio needs the `encrypt` hook and GRUB
  needs a `cryptdevice=` kernel parameter for the `cryptroot` mapping.

---

## Step 2 — Install the base system and generate fstab

### 2.1 (Optional) Refresh mirrors

```sh
reflector --country <your-country> --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

### 2.2 pacstrap

```sh
pacstrap -K /mnt \
  base linux linux-lts linux-firmware intel-ucode sof-firmware \
  btrfs-progs cryptsetup e2fsprogs dosfstools \
  grub efibootmgr \
  networkmanager \
  base-devel sudo vim git man-db man-pages openssh
```

Why what:

| Packages | Reason |
|---|---|
| `base linux linux-firmware` | The core system |
| `linux-lts` | Fallback kernel — snapshots don't cover `/boot`, LTS covers kernel breakage |
| `intel-ucode` | CPU microcode for the i7-1165G7 (GRUB picks it up automatically) |
| `sof-firmware` | Tiger Lake audio (Sound Open Firmware) — without it, no sound |
| `btrfs-progs cryptsetup` | Root filesystem tools + LUKS unlock in the initramfs |
| `e2fsprogs dosfstools` | fsck for ext4 `/boot` and the FAT32 ESP |
| `grub efibootmgr` | Bootloader (installed/configured in the chroot step) |
| `networkmanager` | Network after reboot (same stack as on Mint; `nmtui`/`nm-applet`) |
| `base-devel git` | AUR baseline — needed for the niri workspace later |
| `sudo vim man-db man-pages openssh` | Quality of life; `base` ships no editor/sudo/man |

`-K` initializes a fresh pacman keyring in the target (recommended on
current archiso).

### 2.3 fstab

```sh
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
```

Verify before moving on:

- root is `/dev/mapper/cryptroot` with `subvol=/@`
- all four other subvolume mounts present (`@home`, `@log`, `@pkg`,
  `@snapshots`) with `compress=zstd` and `noatime` carried over
- `/boot` (ext4) and `/boot/efi` (vfat) entries present

---

## Step 3 — TBD

*(next steps land here as they are agreed)*
