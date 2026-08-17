# Arch Linux Manual Installation Guide

Manual (no archinstall) installation of Arch Linux, built step by step.
Target: encrypted btrfs root with snapshot support, GRUB, niri workspace on top.

## Assumptions

The walkthrough is written for a common laptop shape and uses concrete
values throughout; adjust them to the machine at hand:

- x86_64 laptop booting UEFI (the step 1 sanity check confirms this)
- A single NVMe disk, `/dev/nvme0n1` in every command — substitute your
  device from `lsblk` (SATA disks appear as `/dev/sda`)
- Intel CPU/GPU in the worked examples (`intel-ucode`, `mesa`,
  `vulkan-intel`); the AMD equivalents are noted where they differ
- Any existing OS on the disk will be wiped
- No hibernation wanted (zram swap only, step 6); plain suspend covers
  the laptop-lid use case

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
   sweep the current OS for everything else: SSH keys (`~/.ssh` — needed to
   push to this repo from the new system), GPG keys, browser profiles,
   `~/Documents`, any dotfiles not committed here.
2. **Disable Secure Boot.** Most preinstalled systems boot via a
   Microsoft-signed shim; the Arch ISO is unsigned and will not boot with
   Secure Boot enabled. Enter firmware setup (F1/F2/Del at power-on,
   vendor-dependent) → Security → Secure Boot → Disabled.
   Leave it off after the install (re-enabling later via `sbctl` with custom
   keys is possible but out of scope).

---

## Step 0.5 — ISO, USB stick, and SSH into the live environment

The install runs over SSH from a second laptop (copy-paste, scrollback,
docs open in a browser); only the bootstrap below and the LUKS passphrase
ever need the destination laptop's own keyboard.

### 0.5.1 Download and verify the ISO (on another machine)

Get `archlinux-x86_64.iso` and its checksum file from
<https://archlinux.org/download/>, then:

```sh
sha256sum -c --ignore-missing sha256sums.txt
```

### 0.5.2 Write the USB stick

```sh
lsblk -d -o NAME,SIZE,MODEL      # identify the stick — NOT a hard disk
sudo dd if=archlinux-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot the destination laptop from its firmware boot menu (F12 on many
laptops, vendor-dependent) and pick the **`UEFI:`-prefixed**
entry for the stick — a legacy/BIOS entry may be listed next to it and
would fail the UEFI check in step 1.

### 0.5.3 Bootstrap SSH at the destination laptop's console

sshd already runs on the live ISO, but root's password is empty and SSH
refuses empty passwords — set one, get online, note the IP:

```sh
passwd                          # root password for this live session only
iwctl                           # Wi-Fi (Ethernet needs nothing)
  station wlan0 scan
  station wlan0 get-networks
  station wlan0 connect "SSID"
  exit
ip -br addr                     # note the IP
```

### 0.5.4 Connect from the second laptop

```sh
ssh root@<ip>
tmux                            # long steps survive an SSH hiccup;
                                # reconnect with: tmux attach
```

Steps 1–4 run in this session. After the step 4 reboot: LUKS passphrase
and first login at the physical console, `nmtui` for Wi-Fi, then SSH back
in **as the user** (root SSH login is disabled on the installed system;
the IP may differ) for steps 5–7.

---

## Step 1 — Disk setup (partition, encrypt, btrfs, mount)

> **WARNING:** this wipes the entire disk, including whatever OS is on it.

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
| `nvme0n1p3` | rest of the disk | Linux | LUKS2 container |

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
- No sizes anywhere: all subvolumes share the one btrfs pool.
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
| `intel-ucode` | CPU microcode (swap for `amd-ucode` on AMD; GRUB picks either up automatically) |
| `sof-firmware` | Audio firmware for recent Intel laptops — without it, no sound there; harmless (droppable) elsewhere |
| `btrfs-progs cryptsetup` | Root filesystem tools + LUKS unlock in the initramfs |
| `e2fsprogs dosfstools` | fsck for ext4 `/boot` and the FAT32 ESP |
| `grub efibootmgr` | Bootloader (installed/configured in the chroot step) |
| `networkmanager` | Network after reboot (`nmtui`/`nm-applet`) |
| `base-devel git` | `git` clones the workspace repo; `base-devel` builds paru and any AUR package installed by hand later |
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
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime   # your timezone
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf
```

### 3.2 Hostname & hosts

```sh
echo 'yourhostname' > /etc/hostname
cat >> /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   yourhostname
EOF
```

### 3.3 Accounts

```sh
passwd                          # root password
useradd -m -G wheel yourname
passwd yourname
EDITOR=vim visudo               # uncomment:  %wheel ALL=(ALL:ALL) ALL
```

### 3.4 GPU drivers

```sh
pacman -S mesa vulkan-intel intel-media-driver      # Intel
# AMD instead:  pacman -S mesa vulkan-radeon libva-mesa-driver
```

`mesa` = OpenGL, the vulkan package = Vulkan, the last = VA-API hardware
video decode (battery life). Do **not** install `xf86-video-intel`
(deprecated Xorg driver; niri is Wayland and uses mesa + the kernel
driver).

### 3.5 initramfs — the `encrypt` hook (CRITICAL)

Edit `/etc/mkinitcpio.conf` and set:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)
```

- `keyboard`/`keymap` before `encrypt` — so the passphrase prompt has a keyboard
- `microcode` — embeds the CPU microcode into the initramfs
- `kms` — early kernel modesetting for proper console graphics

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
- `linux-headers`/`linux-lts-headers` not needed unless DKMS modules
  enter the picture later.

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
free -h                       # all RAM visible
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

## Step 5 — Snapshots: snapper + snap-pac + grub-btrfs

Everything from here on runs on the installed system, as the regular user
with `sudo`.

### Snapshot strategy (decided)

Options considered, and where each landed:

- **Transaction-driven snapshots (snap-pac)** — **chosen as the only
  automatic trigger.** Every pacman transaction gets a pre/post pair.
  Why automatic: Arch updates the whole system in one transaction (partial
  upgrades are unsupported), so there is no minor-vs-major distinction to
  hang a manual habit on — whether an update was risky is only known in
  hindsight. Automatic pairs make the revert point exist by construction;
  snapshot count stays proportional to system changes, not to time.
- **Timeline snapshots (hourly/daily/…)** — rejected. Time-based snapshots
  of the root filesystem mostly capture nothing (root barely changes between
  transactions) while burying the meaningful pre-update snapshots in noise.
- **Boot snapshots (`snapper-boot.timer`)** — rejected, same noise argument;
  snap-pac already brackets every change that could make a boot differ.
- **Timeshift** — rejected on Arch: its pacman
  integration lives in the AUR, it fights snapper for `/.snapshots`-style
  layouts, and grub-btrfs needs a nonstandard daemon flag for it. snapper is
  the Arch-native path.
- **Ad-hoc snapshots** stay available for experiments outside pacman
  (config surgery, trying a dotfiles change):
  `sudo snapper create --description "before X"`.

Cleanup: `snapper-cleanup.timer` prunes by count (`NUMBER_LIMIT`), so disk
use is bounded and old pairs age out automatically. With `@log`, `@pkg` and
`@home` as separate subvolumes, snapshots cover exactly the system itself —
small under zstd, and a rollback never touches logs, package cache, or home.

### 5.1 Packages

```sh
sudo pacman -S snapper snap-pac grub-btrfs inotify-tools
```

- `snapper` — snapshot manager
- `snap-pac` — pacman hooks: automatic pre/post snapshot around **every**
  pacman transaction; zero config. Its pairs carry the `number` cleanup
  algorithm, so `snapper-cleanup.timer` disposes of them automatically
  under `NUMBER_LIMIT`
- `grub-btrfs` — generates GRUB menu entries for snapshots
- `inotify-tools` — needed by the grub-btrfs daemon to watch `/.snapshots`

### 5.2 Create the snapper config (the `.snapshots` dance)

`snapper create-config` insists on creating its own `.snapshots` subvolume
and fails if the path exists. We want snapshots to live in our top-level
`@snapshots` subvolume instead (so a root rollback never touches the
snapshots themselves). Hence this dance:

```sh
sudo umount /.snapshots
sudo rm -r /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots   # remove snapper's nested subvolume
sudo mkdir /.snapshots
sudo mount -a                             # remounts @snapshots per fstab
sudo chmod 750 /.snapshots
sudo chown :wheel /.snapshots
```

### 5.3 Tune the config

Edit `/etc/snapper/configs/root`:

```
ALLOW_GROUPS="wheel"          # snapper list without sudo
TIMELINE_CREATE="no"          # no hourly noise — snap-pac's pacman snapshots
                              # are the ones that matter for rollbacks
NUMBER_LIMIT="20"
NUMBER_LIMIT_IMPORTANT="10"
```

*(Optional: a second config for `/home` with `TIMELINE_CREATE="yes"` guards
against accidental file deletion — separate decision, not required.)*

### 5.4 Services

```sh
sudo systemctl enable --now snapper-cleanup.timer   # prunes per NUMBER_LIMIT
sudo systemctl enable --now grub-btrfsd             # watches /.snapshots,
                                                    # regenerates snapshot menu
```

### 5.5 Boot-into-snapshot support (overlayfs)

Snapper snapshots are read-only; to boot one cleanly, GRUB needs the
initramfs to lay a tmpfs overlay on top. Append `grub-btrfs-overlayfs` to
the **end** of HOOKS in `/etc/mkinitcpio.conf`:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck grub-btrfs-overlayfs)
```

```sh
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg   # picks up the snapshots submenu
```

Changes made inside a booted snapshot are ephemeral (overlay in RAM) — it's
an inspection/rescue environment, not a rollback by itself.

### 5.6 Verify

```sh
sudo pacman -S tree        # any small package
snapper list               # a pre/post pair should have appeared
```

Reboot once and confirm GRUB now shows an "Arch Linux snapshots" submenu.

### 5.7 Monthly checksum scrub

Snapshots protect against bad changes; scrubbing protects against bad
*disks*. A scrub reads everything and verifies btrfs checksums, surfacing
silent corruption instead of waiting for a read to stumble on it:

```sh
sudo systemctl enable --now btrfs-scrub@-.timer    # "-" is the escaped path "/"
```

### 5.8 Rollback recipes

**Small revert** (bad config change, one broken package) — revert file
changes between two snapshots:

```sh
snapper list
sudo snapper undochange <pre>..<post>
```

**Full rollback** (system won't work; boot a snapshot from GRUB to confirm
which one is good, or boot the live ISO). Because root is mounted by name
(`subvol=/@`), the rollback is swapping `@` out:

```sh
# from live ISO: cryptsetup open /dev/nvme0n1p3 cryptroot first
sudo mount -o subvolid=5 /dev/mapper/cryptroot /mnt   # top level
sudo mv /mnt/@ /mnt/@.broken
sudo btrfs subvolume snapshot /mnt/@snapshots/<N>/snapshot /mnt/@
sudo umount /mnt
reboot
# once satisfied: mount top level again and
#   btrfs subvolume delete /mnt/@.broken
```

After a full rollback, resync `/boot` with the rolled-back system (kernels
live outside btrfs): `sudo pacman -S linux linux-lts`.

---

## Step 6 — zram swap

Compressed swap in RAM — no partition, no swapfile (decided in step 1;
no hibernation).

### 6.1 Install and configure

```sh
sudo pacman -S zram-generator
```

Create `/etc/systemd/zram-generator.conf`:

```ini
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
```

`ram / 2` is the standard sizing. With zstd's typical 3:1 ratio on
swapped pages, a completely full device costs about a sixth of RAM while
extending effective memory well past physical — the right trade when swap
is occasional overflow, not a working set.

### 6.2 Kernel tuning for zram

zram inverts the usual swap cost model (swapping to it is cheap, readahead
is pointless), so the stock VM defaults are wrong for it. These are the
values recommended by the zram-generator/ArchWiki guidance — create
`/etc/sysctl.d/99-vm-zram.conf`:

```ini
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
```

(`swappiness > 100` deliberately prefers swapping cold anonymous pages to
zram over dropping file cache — correct when "swap" is RAM-speed;
`page-cluster = 0` disables swap readahead, which only made sense on disks.)

### 6.3 Activate and verify

```sh
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
sudo sysctl --system
zramctl                    # zram0, zstd, 12G
swapon --show              # /dev/zram0 active, prio 100
```

The generator creates the device on every boot from the config file — no
service to enable.

---

## Step 7 — Deploy the niri workspace

The workspace lives in this repository (`config/` → `~/.config`, `bin/` →
`~/.local/bin`), and `setup.sh` is Arch-native: every component installs
from the official repositories in one pacman transaction. The script
installs the workspace alone — no end-user applications; browsers, VPN
and the like are installed by hand afterwards (step 7.3). `paru` is
bootstrapped as the tool for those installs (this is what `base-devel`
from step 2 is for).

### 7.1 One command

```sh
curl -fsSL https://raw.githubusercontent.com/nafud/dotfiles/main/bootstrap.sh | bash
```

`bootstrap.sh` clones the repo into `~/dotfiles` over HTTPS (no SSH key needed
to receive), sets the push URL to SSH (for when the key from the step 0
backup is restored), and hands off to `setup.sh`. Equivalent by hand:

```sh
git clone https://github.com/nafud/dotfiles.git ~/dotfiles
bash ~/dotfiles/setup.sh
```

One idempotent run does all of it:

- **Packages** (single `pacman -Syu --needed` transaction): the niri stack
  (niri, xwayland-satellite, waybar, mako, rofi 2.0 wayland, alacritty, …),
  the terminal tools, the PipeWire audio stack (`pipewire-pulse`
  shim — `pulsemixer` talks to it unchanged), portals + gnome-keyring +
  `qt5-wayland` (ksnip runs native Wayland) + `gsettings-desktop-schemas`
  and `adwaita-icon-theme` (the gsettings dark theme and the Adwaita
  cursor from `input.kdl` actually resolve), `ttf-jetbrains-mono-nerd`,
  and `pacman-contrib` (the bar's updates module probes `checkupdates`).
  The workspace alone — no browsers, no VPN, no messengers, no media
  apps; those are step 7.3, by hand.
- **paru** bootstrapped from `paru-bin` if absent — the tool for the
  by-hand application installs, and what the bar's updates module runs
  (`paru -Syu`) so repo and AUR packages upgrade together. Nothing is
  installed from the AUR by the script itself.
- **Power**: `thermald` (proactive thermal limits on Intel — sustained
  boost instead of emergency throttling; inert on other CPUs) and `tlp`
  (battery-side runtime tuning, stock defaults) installed and enabled.
- **greetd + tuigreet** installed, configured (`/etc/greetd/config.toml`)
  and enabled — takes over the VT at next boot, never mid-session.
- **Maintenance**: `paccache.timer` enabled so the pacman cache stays
  bounded (the `@pkg` subvolume escapes snapshots, but nothing else
  limits its growth).
- **Defaults**: zathura for PDFs, imv for images. No browser default is
  recorded — that follows the by-hand browser install in step 7.3.
- **Linking**: `config/` → `~/.config`, `bin/` → `~/.local/bin`; anything
  in the way is preserved once as `<name>.pre-dotfiles`.
- **Glue**: MIME defaults, gsettings, the managed `~/.bashrc` block, the
  `waybar-updates.path` user unit (pokes the bar when the pacman DB
  changes), `niri validate` as the final gate.

Optional extra: a polkit authentication agent (e.g. `polkit-gnome`) if GUI
apps ever need privilege prompts — the terminal/sudo workflow doesn't.

### 7.2 First session checklist

1. Reboot → tuigreet → `niri` session.
2. Bar up (waybar), notifications (`notify-send test`), launcher (`Mod+D`),
   terminal (`Mod+T`), lock (`Mod+Shift+L`).
3. Audio: `pulsemixer` sees PipeWire sinks. Screenshots: `Print`.
4. Updates module: badge counts pending pacman + AUR updates; click runs
   the upgrade (`paru -Syu`) in a terminal.
5. `bash ~/dotfiles/setup.sh summary` — all rows green.

### 7.3 Applications, by hand

The script keeps the workspace pure; applications are deliberate,
per-machine choices installed afterwards. The configs already carry
their integration points, which sit dormant until the package appears:

- **Browser** — e.g. `paru -S firefox` (or any other), then record it
  as the default: `xdg-settings set default-web-browser firefox.desktop`.
- **Mullvad VPN** — `paru -S mullvad-vpn-bin`, then
  `sudo systemctl enable --now mullvad-daemon` and `mullvad account
  login`. The workspace configs carry nothing mullvad-specific; any
  status integration (a bar module, a window rule for the popup) is a
  per-user addition.
- **Anything else** (Spotify, Telegram, Obsidian, KeePassXC, …) —
  `paru -S <pkg>`; paru resolves official repos first and falls back to
  the AUR.
