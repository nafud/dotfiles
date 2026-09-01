# CLAUDE.md

Arch Linux workspace dotfiles around the niri compositor — one palette,
one face, from the first boot frame to the desktop. The repository
layout is the source of truth; setup.sh's header comment describes it
precisely. Read it first.

## The machine underneath

The base system is Arch per the Kiln guide (linked in the README):
GRUB on an encrypted btrfs root, snapper snapshots with grub-btrfs
entries, the LTS kernel as the fallback. That layer — partitioning,
crypttab, snapper — belongs to the guide, **not** this repo; this repo
owns everything under `system/` and everything in the user's session.
paru is bootstrapped from source (the prebuilt paru-bin links a libalpm
soname that lags pacman's bumps — `install_paru` in setup.sh carries
the whole story) but nothing here installs from the AUR; herdr is the
one release-binary download. End-user applications (browser, VPN,
messengers, media) are installed by hand afterwards and deliberately
absent from setup.sh's one pacman transaction.

## Boot to desktop, the whole chain

1. **GRUB** — `system/etc/default/grub.d/10-dotfiles.cfg`: menu hidden
   behind a 2s Esc/Shift window, `splash` on the kernel line, appended
   to (never replacing) the machine's own cmdline.
2. **plymouth** — the mkinitcpio drop-in slots the hook right after
   udev/systemd so the LUKS passphrase goes through the splash;
   `plymouthd.conf` names the mono theme
   (`system/usr/share/plymouth/themes/mono/`), packed into the
   initramfs with the font. `plymouth quit --retain-splash`
   (the plymouth-quit drop-in) leaves the last frame up until the
   greeter paints over it. Escape hatch: `plymouth.enable=0` on the
   kernel line.
3. **greetd** on VT1 runs a greeter niri (`system/etc/greetd/niri.kdl`)
   whose one job is `monogreet` fullscreen; the compositor quits when
   the greeter exits, and greetd starts the chosen session.
4. **The session** — niri (`config/niri/`, one `config.kdl` including
   six topic files). No spawns in the compositor config: the daemons
   (waybar, mako, swaybg, swayidle, cliphist×2, battwatch) are systemd
   user units bound to `graphical-session.target`. The environment
   flows one way: `config/bash/profile` (PATH with `~/.local/bin`,
   EDITOR) is imported whole by niri-session into the user manager;
   `config/environment.d/` adds what a login shell doesn't set;
   binds name `bin/` scripts bare, units spell the path out.

## Deployment model — what is live when

- `config/` and `bin/` are **live symlinks** (`~/.config`, `~/.local/bin`):
  an edit in the repo is on disk at once. niri and starship re-read on
  save; daemons are systemd user units (`systemctl --user restart …`);
  the shell's config (`config/bash/`) applies to the next shell.
- `system/` mirrors `/` and is **installed, not linked** — root-owned
  copies land only via `sudo bash setup.sh system`, which re-installs
  on a content *or mode* change (`SYSTEM_MODES` names the directories
  whose readers insist on a stricter mode: `/etc/sudoers.d` 0440, its
  files parsed by `visudo -cf` first), rebuilds the initramfs when
  anything under plymouth/mkinitcpio/modprobe.d changed, and prunes
  files the repo dropped from mirrored dirs (the plymouth theme dir).
  It runs no package
  transaction and needs no network (that is `install`'s bootstrap
  step): a config fix must be able to land while a misconfigured
  daemon holds the network. Editing `system/…` does
  nothing to the running machine until that command runs; say so when
  you finish such a change.
- `bash setup.sh link` = the user half (links, units, MIME, shell hooks,
  `niri validate`, session reload). Both halves are idempotent.
- btop and micro are deliberately part-linked (`PARTIALLY_LINKED` in
  setup.sh): they write live state beside their config. Do not link
  their whole dirs.
- `config/systemd/user/*.wants/` is per-machine enablement state that
  `systemctl --user enable` writes through the symlinked dir into the
  repo; it is gitignored on purpose, never committed.

## The design in one paragraph

One palette everywhere: ground `#0d0d0d`, rest `#c0c0c0`, lit `#e8e8e8`,
edges/muted `#333333`/`#666666`, accent `#98b898`, one face (JetBrains
Mono Nerd Font, 0.9 glass on every translucent surface).
Three screens share it: the **lock**
(`config/hypr/hyprlock.conf`) is the reference — a 300px ring (3px edge
inside the 300), the hour centred in it, hidden input as one randomly
lit quadrant per keystroke, the field appearing on the first keystroke
and fading `fade_timeout` (2s) + 800ms after it empties; the **login
page** (`system/usr/local/bin/monogreet`, a GTK4 greetd greeter) copies
all of that, drawing in the output's physical pixels with text sizes in
points at 96 dpi so the two match on the 1.25-scale panel; the **boot
splash** (`system/usr/share/plymouth/themes/mono/`) has no ring — only
a two-line block on the screen's centre: the typed characters as a row
of dots on the line 15px above it, the passphrase prompt on the line
15px below (one 30px pitch apart, mirrored about the centre). Every
line under the ring — the marks, the feedback, the splash's prompt — is
one size, 16pt (21.3px); only the hour is 60. Feedback is **words, not
colours**: "caps lock" and "wrong password" on the line under the ring,
the failure standing for 2s — hyprlock's own `fail_timeout` convention
(lock: a `cmd[update:200]` label running `bin/lock-line`, which reads
the keyboards' caps-lock LEDs in sysfs and the `$ATTEMPTS` count,
remembering in `$XDG_RUNTIME_DIR` when it grew; login page: GDK's
`caps-lock-state` and greetd's auth_error, cleared by the next
keystroke too). The only colour
event is the ring lit `e8e8e8` while a password is checked — the
check's only sign on both screens; the hour stays. The edge moves to
the lit and back over 800ms, linear, lerped in OkLab (hyprlock's
`inputFieldColors` default, written out in hyprlock.conf; monogreet's
`oklab_lerp`/`update_edge`), so a refused password is the ring lit and
fading back, then the field going 2s on. hyprlock has
no off-switch for its fail colour, so `fail_color` equals the outline
colour — that is the configuration meaning "no change", not a leftover.

## Invariants that span files

- The keyboard layout list lives in three places that cannot share one:
  `config/niri/input.kdl`, `system/etc/greetd/niri.kdl`, and the
  `$LAYOUT[…]` marks in `config/hypr/hyprlock.conf`. `tools/check`
  fails if they disagree.
- Geometry numbers (ring 300, edge 3, line at 185, feedback line +30,
  fonts 60/16pt) are duplicated by design across hyprlock.conf,
  monogreet, mono.script and tools/ring-screens-test — change one,
  change all. `tests/check-python` pins the pairs it can read
  statically; `tools/ring-screens-test` measures the truth live.
- Committed generated images (`system/…/mono/bullet.png`, `icons/mono/`)
  come from `tools/render-plymouth-mono` and `tools/mono-icons`; rerun
  the tool rather than editing pixels. The PNGs are written without date
  chunks, so an unchanged rerun is byte-identical.
- Condition modules on the bar (updates, privacy, failed units,
  temperature, bluetooth, recording) render empty when there is nothing
  to say and the bar collapses them; a new one follows the same rule,
  its icon span measured by `tools/waybar-icon-span`.
- `bin/` scripts are called bare from niri binds (the login shell puts
  `~/.local/bin` on PATH and niri-session imports it); systemd units and
  hyprlock.conf spell the path out instead — they must not depend on a
  login shell's environment.
- One palette definition per program, all agreeing: alacritty's
  `mono.toml` is the reference table; gtk.css, mako, rofi's mono.rasi,
  newt, zathura, zellij and the waybar CSS restate it. A palette change
  touches them all.

## Verification — measure, don't eyeball

- `tools/check` before every push: shellcheck + bash -n, python
  compiles, JSON/TOML/unit files parse, layout lists agree, and the
  hermetic suites run — `tests/check-shell` (setup.sh's functions,
  bin/lock-line, the waybar scripts against PATH shims, all in
  sandboxes, no sudo), `tests/check-system` (bootkeep against a fake
  /boot, the pacman hooks, every `system/etc` drop-in read as text,
  `nft -c` in a user namespace, setup.sh's service decisions through a
  sudo shim), `tests/check-session` (the capture, recording, web-app
  and netmenu scripts against PATH shims, the bar and bind config) and
  `tests/check-python` (monogreet's pure layer
  under a stubbed gi — sessions/users/state/greetd framing/easing/
  OkLab/quadrants — plus the static cross-file invariants). CI
  (`.github/workflows/check.yml`) runs exactly this plus
  `niri validate` in an Arch container; the suites therefore may not
  assume Arch, a session, a display, or PyGObject.
- `tools/ring-screens-test lock|login|splash|all` runs the three screens
  for real and measures frames (ring diameter/edge/centre, ink boxes,
  fade timing, the feedback words by ink width). It needs the host
  session unlocked and takes over the screen; the splash leg needs
  `DISPLAY` (xwayland-satellite). Timing anchors: the lock's verdict is
  polled from hyprlock's log (a nested grim costs ~1s — never use frame
  polls as a clock); caps lock is injected with `wtype -M/-m capslock`
  (the keysym route does nothing — wtype's generated keymap binds no
  Lock modifier); the lock's caps file is substituted in the config copy
  because a nested compositor drives no LEDs.
- UI claims in comments (pixel positions, sizes, behaviour of hyprlock/
  plymouth/GTK) are treated as facts: verify against source or
  measurement before writing them, and keep them true when code changes.

## Conventions

- Comments are prose that explains *why* and names the cross-references
  (`config/hypr/hyprlock.conf`, `bin/glass`, …). Keep them in step with
  the code; a stale sentence is a bug here.
- Don't add packages outside setup.sh's one pacman transaction (AUR is
  bootstrapped for later manual installs only; herdr is the one
  release-binary download).
- Robustness at the gates: the greeter, the lock and the splash are the
  screens that must never die on bad input — a malformed .desktop file,
  a missing LED, an absent wallpaper are all "skip and carry on with a
  word on stderr", never a crash.
- Snapshots/boot: GRUB + grub-btrfs + snapper + snap-pac (a snapshot
  around every pacman transaction) are configured by the Kiln guide,
  not this repo. What this repo adds is the rollback's missing piece:
  `/boot` is a separate ext4 partition (GRUB cannot open the argon2
  LUKS2 root), so a snapshot holds its kernel's modules but not its
  kernel — `system/usr/local/bin/bootkeep` and its pacman hooks keep
  the outgoing kernel on `/boot` under a version-suffixed name both
  generators pair (`vmlinuz-linux-<kver>` / `initramfs-linux-<kver>.img`)
  and mirror `/boot` into `/.bootbackup` ahead of each snapshot.
  Rolling back = the snapshot entry + the kernel with its version.
- System policy lives in `system/etc` as drop-ins, one concern per
  file, the reason in its header: memory pressure
  (`systemd/oomd.conf.d`, `user.slice.d`), the firewall
  (`nftables.conf` — only its own two tables are rebuilt; Mullvad's,
  tailscaled's and libvirt's tables must survive a reload, and a packet
  must pass every table on a hook, so the libvirt default network's
  DHCP/DNS and NAT are admitted here too), DNS (`systemd/resolved.conf.d/10-dns.conf`:
  no global resolver — the tunnel's own resolver and firewall rule the
  connected state, the link's DHCP resolver the disconnected one; a
  global Mullvad DNS-over-TLS pin was dropped because an ISP that
  blackholes 853 turned "VPN off" into "no DNS"; FallbackDNS empty,
  LLMNR and mDNS off), NetworkManager privacy defaults (random MAC,
  IPv6 privacy, no LLMNR/mDNS, no DHCP hostname, stable-uuid DUID),
  `faillock`, TLP's conservation-mode cap, bluez's `AutoEnable=false`
  and `Privacy = device`, the kernel sysctls (`sysctl.d/50-hardening.conf`,
  each absence explained in its header), the modules kept from loading
  (`modprobe.d/hardening.conf`; ksmbd is deliberately absent — kmod
  ignores an `install` rule for a module with softdeps, modprobe.d(5)),
  `coredump.conf.d` (Storage=none, the backtrace kept),
  `journald.conf.d` (1G cap), `tmpfiles.d/boot.conf` (/boot 0700),
  `sudoers.d/10-hardening` (visudo's editor pinned), and tailscaled's
  environment (`default/tailscaled`: `--no-logs-no-support`, port 41641).
  Remote access: sshd and tailscaled are enabled by `setup.sh`; sshd is
  key-only (`AuthenticationMethods publickey`, `AllowGroups wheel`) and
  the firewall admits port 22 from `tailscale0` alone — the LAN never
  sees it. The tailnet runs alongside Mullvad through the `inet tailnet`
  table: Mullvad's own split-tunnel marks (ct mark 0xf41, packet mark
  0x6d6f6c65, set from a table of one's own per Mullvad's advanced
  split-tunnelling guide) on traffic to 100.64.0.64–100.127.255.255 and
  fd7a:115c:a1e0::/48 and on what arrives from tailscale0; the IPv4
  interval starts at .64 because Mullvad's DNS blocker resolvers sit at
  100.64.0.1–63 inside the tunnel. tailscaled itself is not split off:
  its WireGuard travels inside the Mullvad tunnel. Secure Boot is out of
  scope by the user's decision (QEMU/KVM work). `setup.sh system`
  restarts exactly the services whose files changed
  (`configure_system_services`: sysctl re-applied, journald reloaded,
  sshd reloaded only after `sshd -t`, tmpfiles applied) and starts sshd
  and tailscaled last, after the firewall and drop-ins are on disk;
  `sudo tailscale up` (browser login) is the one manual step.
- Service boundaries: `system/etc/systemd/system/*.service.d/hardening.conf`
  gives each root daemon the machine runs (wpa_supplicant, the Mullvad
  units, thermald, grub-btrfsd, udisks2) an explicit scope — the
  capabilities, paths, devices, socket families and syscalls it
  actually uses, derived from its footprint and source, the reasoning
  in each header. Four rules shaped them and must survive edits: any
  mount-namespace directive (ProtectSystem, PrivateTmp, ReadWritePaths,
  the Protect* family, PrivateNetwork) hides the unit's own mounts from
  the host, so udisks2 and `mullvad-net-cls.service` carry none; a
  `DeviceAllow` (also the one `ProtectClock` implies) switches the
  device policy to an allow-list; a directory the daemon itself owns is
  granted as ConfigurationDirectory/LogsDirectory/CacheDirectory —
  systemd creates a missing one before the namespace, where a deleted
  ReadWritePaths target fails the unit at 226/NAMESPACE — and a path
  some other unit provides carries a leading dash so its absence
  degrades the feature, never the start; and the cgroup2 root and every
  v1 hierarchy root are mode 555, so a mkdir under /sys/fs/cgroup
  needs CAP_DAC_OVERRIDE — `mullvad-net-cls` carries it for the
  hierarchy, and the daemon's exclusions cgroup comes from an
  `ExecStartPre=+` (full privileges, outside the namespace) in its own
  drop-in, so the daemon itself never does. Deployment order is part of
  the boundary: the Mullvad package's post_install runs
  `systemctl enable --now mullvad-daemon`, so changed boundary files
  land (`setup.sh system`) *before* any install or start of the
  package — a daemon started against stale boundaries firewalled the
  machine off its own mirrors once. `tools/sandbox-check` measures them:
  `score` offline against the vendored unit files (a CI row), `learn` +
  `report` for the live learning-mode rollout (SystemCallLog, decoded
  seccomp records), `render` for the learning variant. Excluded on
  purpose: greetd (every session inherits its restrictions),
  NetworkManager and bluez (upstream-hardened), the bus and udev.
