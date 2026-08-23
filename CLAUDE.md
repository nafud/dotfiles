# CLAUDE.md

Arch Linux workspace dotfiles around the niri compositor. The repository
layout is the source of truth; setup.sh's header comment describes it
precisely. Read it first.

## Deployment model — what is live when

- `config/` and `bin/` are **live symlinks** (`~/.config`, `~/.local/bin`):
  an edit in the repo is on disk at once. niri and starship re-read on
  save; daemons are systemd user units (`systemctl --user restart …`);
  the shell's config (`config/bash/`) applies to the next shell.
- `system/` mirrors `/` and is **installed, not linked** — root-owned
  copies land only via `sudo bash setup.sh system`, which also rebuilds
  the initramfs when anything under plymouth/mkinitcpio changed and
  prunes files the repo dropped from mirrored dirs (the plymouth theme
  dir). Editing `system/…` does nothing to the running machine until
  that command runs; say so when you finish such a change.
- `bash setup.sh link` = the user half (links, units, MIME, shell hooks,
  `niri validate`, session reload). Both halves are idempotent.
- btop and micro are deliberately part-linked (`PARTIALLY_LINKED` in
  setup.sh): they write live state beside their config. Do not link
  their whole dirs.

## The design in one paragraph

One palette everywhere: ground `#0d0d0d`, rest `#c0c0c0`, lit `#e8e8e8`,
edges/muted `#333333`/`#666666`, one face (JetBrains Mono Nerd Font).
Three screens share it: the **lock**
(`config/hypr/hyprlock.conf`) is the reference — a 300px ring (3px edge
inside the 300), the hour centred in it, hidden input as one randomly
lit quadrant per keystroke, the field appearing on the first keystroke
and fading `fade_timeout` (2s) + 800ms after it empties; the **login
page** (`system/usr/local/bin/monogreet`, a GTK4 greetd greeter) copies
all of that, drawing in the output's physical pixels with text sizes in
points at 96 dpi so the two match on the 1.25-scale panel; the **boot
splash** (`system/usr/share/plymouth/themes/mono/`) has no ring — only
the passphrase prompt on the screen's centre, the typed characters as a
row of dots one line (30px) under it. Feedback is **words, not
colours**: "caps lock" and "wrong password" on the line under the ring
(lock: a `cmd[update:200]` label running `bin/lock-line`, which reads
the keyboards' caps-lock LEDs in sysfs and the `$ATTEMPTS` count; login
page: GDK's `caps-lock-state` and greetd's auth_error). The only colour
event is the ring lit `e8e8e8` while a password is checked. hyprlock has
no off-switch for its fail colour, so `fail_color` equals the outline
colour — that is the configuration meaning "no change", not a leftover.

## Invariants that span files

- The keyboard layout list lives in three places that cannot share one:
  `config/niri/input.kdl`, `system/etc/greetd/niri.kdl`, and the
  `$LAYOUT[…]` marks in `config/hypr/hyprlock.conf`. `tools/check`
  fails if they disagree.
- Geometry numbers (ring 300, edge 3, line at 185, feedback line +30,
  fonts 60/16/13pt) are duplicated by design across hyprlock.conf,
  monogreet, mono.script and tools/ring-screens-test — change one,
  change all, and the harness will measure the truth.
- Committed generated images (`system/…/mono/bullet.png`, `icons/mono/`)
  come from `tools/render-plymouth-mono` and `tools/mono-icons`; rerun
  the tool rather than editing pixels. The PNGs are written without date
  chunks, so an unchanged rerun is byte-identical.
- `bin/` scripts are called bare from niri binds (the login shell puts
  `~/.local/bin` on PATH and niri-session imports it); systemd units and
  hyprlock.conf spell the path out instead — they must not depend on a
  login shell's environment.

## Verification — measure, don't eyeball

- `tools/check` before every push: shellcheck + bash -n, python
  compiles, JSON/TOML/unit files parse, layout lists agree. CI
  (`.github/workflows/check.yml`) runs exactly this plus
  `niri validate` in an Arch container.
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
- Snapshots/boot: GRUB + grub-btrfs + snapper are configured by the Kiln
  guide, not this repo; this repo owns what's under `system/`.
