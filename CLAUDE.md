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
  on a content *or mode* change, rebuilds the initramfs when anything
  under plymouth/mkinitcpio changed, and prunes files the repo dropped
  from mirrored dirs (the plymouth theme dir). Editing `system/…` does
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
  sandboxes, no sudo) and `tests/check-python` (monogreet's pure layer
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
- Snapshots/boot: GRUB + grub-btrfs + snapper are configured by the Kiln
  guide, not this repo; this repo owns what's under `system/`.
