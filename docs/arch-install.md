# Arch Linux Manual Installation Guide

Manual (no archinstall) installation of Arch Linux, built step by step.
Target: encrypted btrfs root with snapshot support, GRUB, niri workspace on top.

## Hardware

- Lenovo ThinkBook 14 G2 ITL (20VD)
- Intel Core i7-1165G7 (Tiger Lake, 4c/8t) — Intel Iris Xe graphics (`i915`)
- 8 GB RAM
- 477 GB NVMe SSD (`/dev/nvme0n1`)
- UEFI, Secure Boot **off**
- Intel Wi-Fi (iwlwifi)

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Filesystem | btrfs on LUKS2 (no LVM) | Subvolumes replace fixed-size volumes; snapshots before updates (snapper + grub-btrfs) on a rolling release |
| Bootloader | GRUB | Required for grub-btrfs boot-into-snapshot entries |
| `/boot` | Separate unencrypted ext4 partition | GRUB never has to unlock LUKS; LUKS2/argon2id defaults stay |
| Kernels | `linux` + `linux-lts` | Snapshots don't cover `/boot`; LTS kernel is the fallback for kernel breakage |
| Swap | zram (post-install) | Effective at 8 GB RAM; no swap partition needed. Hibernation swapfile: TBD |
| Encryption TRIM | via kernel cmdline / crypttab later | SSD discard passthrough, handled in the chroot step |

---

## Step 1 — Disk setup (partition, encrypt, btrfs, mount)

> **WARNING:** this wipes the entire disk, including the existing Windows 11 install.

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

## Step 2 — TBD

*(next steps land here as they are agreed)*
