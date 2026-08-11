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

## Step 3 — Configure the system (chroot)

```sh
arch-chroot /mnt
```

### 3.1 Time & locale

```sh
ln -sf /usr/share/zoneinfo/Asia/Baku /etc/localtime   # adjust if needed
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf
```

### 3.2 Hostname & hosts

```sh
echo 'thinkbook' > /etc/hostname
cat >> /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   thinkbook
EOF
```

### 3.3 Accounts

```sh
passwd                          # root password
useradd -m -G wheel yourname
passwd yourname
EDITOR=vim visudo               # uncomment:  %wheel ALL=(ALL:ALL) ALL
```

### 3.4 GPU (Intel Iris Xe)

```sh
pacman -S mesa vulkan-intel intel-media-driver
```

`mesa` = OpenGL, `vulkan-intel` = Vulkan, `intel-media-driver` = VA-API
hardware video decode (battery life). Do **not** install `xf86-video-intel`
(deprecated Xorg driver; niri is Wayland and uses mesa + kernel i915).

### 3.5 initramfs — the `encrypt` hook (CRITICAL)

Edit `/etc/mkinitcpio.conf` and set:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)
```

- `keyboard`/`keymap` before `encrypt` — so the passphrase prompt has a keyboard
- `microcode` — embeds intel-ucode into the initramfs
- `kms` — early i915 for proper console graphics

Then regenerate for both kernels:

```sh
mkinitcpio -P
```

### 3.6 GRUB (CRITICAL: cryptdevice)

```sh
blkid -s UUID -o value /dev/nvme0n1p3     # UUID of the raw LUKS partition
```

Edit `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX="cryptdevice=UUID=<that-uuid>:cryptroot:allow-discards root=/dev/mapper/cryptroot"
```

- UUID of the **raw partition** `nvme0n1p3`, *not* the mapper device
- `:allow-discards` — TRIM passthrough for the SSD

```sh
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg      # generates entries for linux + linux-lts
```

### 3.7 Services

```sh
systemctl enable NetworkManager
systemctl enable fstrim.timer            # weekly SSD TRIM
systemctl enable systemd-timesyncd
systemctl enable sshd                    # optional: continue post-install work over SSH
```

Notes:

- No display manager enabled here — that decision (greetd vs gdm) belongs to
  the niri deployment step.
- No GNOME: niri is the session. A fallback DE can be added any time later.
- `linux-headers`/`linux-lts-headers` not needed — no DKMS modules on this
  hardware.

---

## Step 4 — Exit, reboot, first boot

```sh
exit                          # leave the chroot
umount -R /mnt
cryptsetup close cryptroot    # also confirms nothing still holds the fs open
reboot                        # remove the USB stick when the screen goes dark
```

> The SSH session to the live ISO ends here. The LUKS passphrase is a
> pre-boot prompt — it must be typed at the physical console. If `sshd` was
> enabled in 3.7, post-install work can continue over SSH after logging in
> and bringing up the network (log in as the user; root SSH login is
> disabled by default).

### First-boot checklist

1. GRUB menu shows entries for **both** `linux` and `linux-lts`.
2. Initramfs prompts for the `cryptroot` passphrase (the `encrypt` hook at work).
3. Console login as the user, then network:
   `nmtui` or `nmcli device wifi connect "SSID" password "..."`.
4. Sanity sweep:

```sh
ping -c3 archlinux.org
timedatectl                   # NTP synced
free -h                       # 24 GB visible
findmnt /                     # /dev/mapper/cryptroot, subvol=/@, compress=zstd
```

### If it doesn't boot

Bare `grub>` prompt or rescue shell → boot the ISO again and repair; do not
reinstall:

```sh
cryptsetup open /dev/nvme0n1p3 cryptroot
# remount everything per step 1.6, then:
arch-chroot /mnt
# fix step 3.5 (mkinitcpio hooks) or 3.6 (GRUB cryptdevice=), regenerate,
# exit, umount -R /mnt, reboot
```

---

**Base install complete.** Remaining post-install layer, in order:

1. snapper + grub-btrfs (snapshot-before-update workflow)
2. zram swap
3. niri workspace deployment from this repo

## Step 5 — TBD

*(next steps land here as they are agreed)*
