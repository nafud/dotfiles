#!/usr/bin/env bash
#
# setup.sh — bootstrap for the niri desktop dotfiles
# Target: Arch Linux (base install per the Kiln guide linked in the
# README), fresh or existing.
#
# The repository layout is the source of truth:
#   config/   mirrors ~/.config and is symlinked there, entry by entry —
#             edits in the repo are live (niri and starship reload on save)
#   bin/      mirrors ~/.local/bin, symlinked the same way
#   system/   mirrors / and is installed there, file by file (root-owned
#             copies, not links): the boot chain (GRUB and mkinitcpio
#             drop-ins, plymouth and its theme, the plymouth-quit
#             hand-off) and the login page (greetd, the greeter niri,
#             monogreet) — what the desktop needs below the user
#   tools/    generators for committed assets (the plymouth theme's
#             images); not installed anywhere
#   setup.sh  everything a config file cannot express: packages, system
#             glue (units, the initramfs and grub.cfg rebuilds, the
#             greeter's state dirs and background, MIME defaults,
#             gsettings, the ~/.bashrc block, the btop setting), the
#             linking itself, session reloads, and the final summary
#
# Everything installs from the official repositories — the workspace
# alone, no end-user applications (browsers, VPN, messengers, media
# apps are installed by hand afterwards). paru is bootstrapped as the
# tool for those later AUR installs, and the bar's updates module
# upgrades through it, but this script installs nothing from the AUR.
# No other third-party builds, and one release-binary download: herdr,
# the agent workspace manager, through its official installer (2b).
#
# A real file or directory found where a link belongs is moved aside once
# as <name>.pre-dotfiles. Version history lives in git log.
#
# Usage:  bash setup.sh          full run: install everything + link configs
#         bash setup.sh link     (re)link configs + validate + reload only
#         bash setup.sh system   packages + the system/ tree + boot and
#                                greeter glue only (sudo; the user half
#                                untouched)
#         bash setup.sh summary  print the probed component summary
#
set -euo pipefail

# ---------------------------------------------------------------- helpers ---
log()  { printf '\033[1m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[setup] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -eq 0 ] && die "run as your user, not root (sudo is used where needed)"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config"
MONO_FONT="JetBrainsMono Nerd Font"

WORK="$(mktemp -d -t dotfiles-setup.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# Match the full family name: a vanilla "JetBrains Mono" install also greps
# true for bare "JetBrainsMono" and would skip the Nerd Font glyphs.
font_ok() { fc-match "$MONO_FONT" | grep -q "JetBrainsMono Nerd Font"; }

# ------------------------------------------------------------- 1. packages ---
# One transaction, official repos only. --needed keeps reruns cheap and
# never reinstalls; the full-system upgrade first is the supported way to
# install on Arch (partial upgrades are not). noto-fonts and
# noto-fonts-emoji stand behind JetBrains Mono for the scripts and emoji
# it lacks — without a fallback those render as hex boxes (in
# notifications first: chat apps).
install_packages() {
    log "pacman packages"
    sudo pacman -Syu --needed --noconfirm \
        niri xwayland-satellite \
        alacritty waybar mako swaybg swayidle swaylock hyprlock rofi \
        yazi zellij cliphist starship chafa micro btop \
        zathura zathura-pdf-poppler imv mpv \
        tlp \
        grim slurp ksnip imagemagick brightnessctl pulsemixer \
        fzf zoxide wl-clipboard fd ripgrep eza bat git-delta jq \
        p7zip unzip xdg-user-dirs \
        libnotify gcr-4 qt5-wayland \
        gsettings-desktop-schemas adwaita-icon-theme \
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \
        pipewire pipewire-pulse pipewire-alsa wireplumber \
        plymouth greetd python-gobject gtk4 \
        ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji pacman-contrib

    [ -f /usr/share/wayland-sessions/niri.desktop ] \
        || die "niri.desktop missing from wayland-sessions — session not registered"
    font_ok || die "ttf-jetbrains-mono-nerd installed but fc-match does not resolve it"
    log "font ok: $(fc-match "$MONO_FONT")"

    # X11 apps (Steam, Discord, ...): niri >= 25.08 spawns xwayland-satellite
    # on demand, exports $DISPLAY, and restarts it if it dies — the binary in
    # $PATH is the whole requirement. No spawn-at-startup, no env plumbing.
}

# ------------------------------------------------------------------ 2. AUR ---
# paru is the tool, not a package source: this script installs nothing
# from the AUR. It is bootstrapped so the bar's updates module can
# upgrade repos and AUR alike (`paru -Syu`, plain pacman before paru
# exists) and so applications chosen later (a browser, a VPN, music)
# install by hand with `paru -S <pkg>`. paru-bin skips the Rust
# compile, but its prebuilt binary hard-links a libalpm soname and
# lags pacman's soname bumps (broken against pacman >= 7.1 when this
# was written) — a binary that exists but cannot load looks installed
# to `command -v`. So the probe is `paru --version` actually running,
# and the fallback builds the paru source package, which links
# whatever libalpm the system really has.
paru_ok() { paru --version >/dev/null 2>&1; }

aur_build() {
    git clone -q "https://aur.archlinux.org/$1.git" "$WORK/$1"
    # -s pulls makedeps from the repos (cargo/rust for the source paru;
    # rust stays installed — paru's own self-updates recompile with it)
    (cd "$WORK/$1" && makepkg -si --noconfirm)
}

install_paru() {
    paru_ok && return 0
    log "bootstrapping paru (AUR helper)"
    # makepkg needs the base-devel group; --needed makes this free
    # on systems that already carry it
    sudo pacman -S --needed --noconfirm base-devel
    if have paru; then
        # present but not runnable: a stale prebuilt against an older
        # libalpm — drop whichever package owns it before rebuilding
        warn "installed paru does not run — replacing with source build"
        sudo pacman -R --noconfirm "$(pacman -Qoq "$(command -v paru)")"
    else
        aur_build paru-bin
        paru_ok && return 0
        warn "paru-bin links an older libalpm — building paru from source"
        sudo pacman -R --noconfirm paru-bin
    fi
    aur_build paru
    paru_ok || die "paru bootstrap failed"
}

# --------------------------------------------------------------- 2b. herdr ---
# herdr (herdr.dev) — terminal workspace manager for coding agents,
# alongside zellij. It is the one release-binary download here: no repo
# package, and the AUR herdr-bin would land in /usr/bin where herdr's
# own updater (`herdr update`) cannot write and refuses to run. The
# official installer fetches the release manifest, verifies the asset's
# SHA-256, and drops the static binary in ~/.local/bin (the PATH entry
# write_shell adds). From then on `herdr update` keeps it current, so
# an existing binary is left alone — this step is install-once.
HERDR_INSTALLER="https://herdr.dev/install.sh"

install_herdr() {
    have herdr && return 0
    log "installing herdr (agent workspace manager) into ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    # fetched to a file first: a truncated download must not run half a script
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
        "$HERDR_INSTALLER" -o "$WORK/herdr-install.sh" \
        || die "can't fetch $HERDR_INSTALLER"
    HERDR_INSTALL_DIR="$HOME/.local/bin" sh "$WORK/herdr-install.sh"
    [ -x "$HOME/.local/bin/herdr" ] || die "herdr install failed"
}

# --------------------------------------------------------- 3. system units ---
# paccache: bound the pacman cache (the @pkg subvolume is excluded from
# snapshots but nothing else limits it). tlp: battery-side runtime power
# tuning, stock defaults (machines that expose a charge-threshold
# interface can set thresholds in /etc/tlp.conf; nothing else needs
# configuring).
enable_system_units() {
    sudo systemctl enable paccache.timer 2>/dev/null \
        || warn "could not enable paccache.timer"
    sudo systemctl enable tlp 2>/dev/null \
        || warn "could not enable tlp"
}

# ---------------------------------------------------------- 4. system tree ---
# system/ mirrors /: every file under it is installed to the same path,
# root-owned, the way config/ mirrors ~/.config — one tree, one rule;
# a file executable in the repo (monogreet) is executable in place.
# Files already identical in place are left alone, so a rerun is quiet;
# the paths that did change are collected for the stages below, which
# rebuild only what those files feed (the initramfs, grub.cfg).
SYSTEM_CHANGED=()

install_system_files() {
    local src dest mode
    while IFS= read -r -d '' src; do
        dest="${src#"$REPO/system"}"
        cmp -s "$src" "$dest" && continue
        mode=644
        [ -x "$src" ] && mode=755
        log "installing $dest"
        sudo install -D -m "$mode" "$src" "$dest"
        SYSTEM_CHANGED+=("$dest")
    done < <(find "$REPO/system" -type f -print0 | sort -z)
}

system_changed_under() {
    local path
    for path in "${SYSTEM_CHANGED[@]}"; do
        [[ $path == "$1"* ]] && return 0
    done
    return 1
}

# ----------------------------------------------------------------- 5. boot ---
# The boot chain is plymouth from the initramfs to the greeter: the
# mkinitcpio drop-in puts the hook in, plymouthd.conf names the theme,
# the GRUB drop-in hides the menu and adds `splash`. Those files only
# take effect inside the images they feed, so the initramfs is rebuilt
# when anything plymouth or mkinitcpio changed (the theme and its font
# are packed into it) and grub.cfg when the GRUB drop-in did. A fresh
# plymouth install is caught the same way: its drop-in is new then.
# Should a splash ever misbehave, `plymouth.enable=0` on the kernel
# line (Esc at boot, e on the entry) boots with the text prompt.
configure_boot() {
    if system_changed_under /etc/mkinitcpio.conf.d \
        || system_changed_under /etc/plymouth \
        || system_changed_under /usr/share/plymouth; then
        log "rebuilding the initramfs (plymouth + theme)"
        sudo mkinitcpio -P
    fi
    if system_changed_under /etc/default/grub.d; then
        log "regenerating grub.cfg"
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
    # the plymouth-quit drop-in is read at the next boot; reload so a
    # `systemctl cat` shows it now
    if system_changed_under /etc/systemd/system; then
        sudo systemctl daemon-reload
    fi
}

# -------------------------------------------------------------- 6. greeter ---
# greetd runs the greeter niri (system/etc/greetd/niri.kdl), which runs
# monogreet (system/usr/local/bin). monogreet keeps the last user and
# session under /var/lib/monogreet, owned by the greeter user the greetd
# package creates. Its background is the wallpaper sunk to glass
# (bin/glass), rendered here because only setup runs with the privilege
# to place it; it is refreshed whenever the wallpaper is newer than the
# copy. Enable only writes symlinks — greetd takes the VT at the next
# boot, never mid-session.
configure_greeter() {
    sudo install -d -o greeter -g greeter -m 0755 /var/lib/monogreet
    local wall="$HOME/Pictures/wallpaper.jpg" bg=/usr/share/backgrounds/greeter.jpg
    if [ -f "$wall" ] && have magick; then
        if [ ! -f "$bg" ] || [ "$wall" -nt "$bg" ] || [ "$REPO/bin/glass" -nt "$bg" ]; then
            log "rendering the login page background from the wallpaper"
            "$REPO/bin/glass" "$wall" "$WORK/greeter.jpg"
            sudo install -Dm644 "$WORK/greeter.jpg" "$bg"
        fi
    fi
    sudo systemctl enable greetd 2>/dev/null \
        || warn "could not enable greetd"
}

configure_git() {
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
}

# ---------------------------------------------------- 7. MIME associations ---
# xdg-mime records an association even for a desktop file that does not
# exist, silently breaking xdg-open; only associate what is actually shipped.
set_mime_default() {
    local desk="$1"; shift
    if [ -f "/usr/share/applications/$desk" ]; then
        xdg-mime default "$desk" "$@"
    else
        warn "$desk not installed; MIME defaults for $* left unchanged"
    fi
}

set_default_apps() {
    log "MIME defaults (zathura for PDFs, imv for images)"
    set_mime_default org.pwmt.zathura.desktop application/pdf

    # the imv package's desktop file name has varied; pick the one shipped
    local d imv_desk=""
    for d in imv-dir.desktop imv.desktop; do
        if [ -f "/usr/share/applications/$d" ]; then imv_desk="$d"; break; fi
    done
    if [ -n "$imv_desk" ]; then
        xdg-mime default "$imv_desk" image/png image/jpeg image/webp image/gif
    else
        warn "no imv desktop file found; image MIME defaults left unchanged"
    fi
}

# ------------------------------------------------------------ 8. link tree ---
# Symlink each top-level entry of config/ into ~/.config and each file in
# bin/ into ~/.local/bin. Directory-level links keep the mapping obvious:
# one entry in the repo, one link on disk. A real file or directory already
# in the way is moved aside once as <name>.pre-dotfiles.
link_one() {
    local src="$1" dest="$2"
    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$src" ]; then
        return 0
    fi
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        mv "$dest" "$dest.pre-dotfiles"
        log "moved existing $dest aside as $dest.pre-dotfiles"
    else
        rm -f "$dest"
    fi
    ln -s "$src" "$dest"
    log "linked $dest"
}

link_configs() {
    local src link
    mkdir -p "$CFG" "$HOME/.local/bin"
    for src in "$REPO/config"/*; do
        # btop rewrites btop.conf on every exit — linking its whole dir
        # would point that rewrite into the repo. configure_btop links
        # the read-only themes/ dir and enforces the intent lines.
        [ "$(basename "$src")" = "btop" ] && continue
        # micro keeps live state (buffers/) beside its config — a whole
        # dir link would write that state into the repo. configure_micro
        # links the actual configuration files only.
        [ "$(basename "$src")" = "micro" ] && continue
        link_one "$src" "$CFG/$(basename "$src")"
    done
    for src in "$REPO/bin"/*; do
        link_one "$src" "$HOME/.local/bin/$(basename "$src")"
    done
    # prune links left behind by entries removed from the repo
    for link in "$CFG"/* "$HOME/.local/bin"/*; do
        if [ -L "$link" ] && [[ "$(readlink "$link")" == "$REPO"/* ]] && [ ! -e "$link" ]; then
            rm "$link"
            log "pruned stale link $link"
        fi
    done
}

# The repo ships user units (config/systemd/user — linked into place by
# link_configs like any other entry); enabling them is the glue only
# setup can do. waybar-updates.path pokes the bar's updates module
# whenever the pacman database changes.
enable_units() {
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now waybar-updates.path 2>/dev/null \
        || warn "could not enable waybar-updates.path (no user session?)"
    # gcr-4 ships the ssh agent (gnome-keyring, which once carried it, is
    # not part of this desktop); the bashrc block exports its socket path
    systemctl --user enable --now gcr-ssh-agent.socket 2>/dev/null \
        || warn "could not enable gcr-ssh-agent.socket (no user session?)"
}

# ---------------------------------------------------------- 9. shell setup ---
# ~/.bashrc is shared with the system's own content, so it is not linked;
# only the marked block is owned, and it is replaced in place on every run
# so edits here reach existing installs.
write_shell() {
    local rc="$HOME/.bashrc"
    local body="$WORK/bashrc"
    [ -f "$rc" ] || touch "$rc"

    log "writing managed block into ~/.bashrc"
    # the niri-setup marker is the block's pre-rename name — stripping
    # it too migrates existing installs to the dotfiles marker
    printf '%s\n\n' "$(awk '
        /^# >>> dotfiles managed block >>>$/,/^# <<< dotfiles managed block <<<$/ { next }
        /^# >>> niri-setup managed block >>>$/,/^# <<< niri-setup managed block <<<$/ { next }
        /^# >>> terminal-readability block >>>$/,/^# <<< terminal-readability block <<<$/ { next }
        { print }
    ' "$rc")" > "$body"

    cat >> "$body" <<'EOF'
# >>> dotfiles managed block >>>
# yazi wrapper: on quit the shell follows yazi's last directory
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
}

alias ls='eza --group-directories-first'
alias ll='eza -l --group-directories-first --git'
alias la='eza -la --group-directories-first'
alias tree='eza --tree'
alias cat='bat --style=plain --paging=never'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -c'

export EDITOR=micro
export VISUAL=micro
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# gcr's ssh agent — gnome-keyring dropped its own, gcr-4 carries it
# now, socket-activated by the user unit setup enables. The user-unit
# environment doesn't reach a greetd-launched shell, hence the export;
# never clobbers an agent already set (e.g. one forwarded over ssh)
[ -z "${SSH_AUTH_SOCK:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/gcr/ssh" ] \
    && export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/gcr/ssh"

[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash
eval "$(zoxide init bash)"
eval "$(starship init bash)"
# <<< dotfiles managed block <<<
EOF

    cat "$body" > "$rc"
}

# btop rewrites its whole config file on every clean exit, so linking it
# would put btop's runtime state under git. Like ~/.bashrc it stays a
# real file owned by the program; only the intended settings are
# enforced in place: theme_background False lets the terminal's glass
# show through instead of btop painting an opaque ground. The themes
# dir is read-only to btop and links normally (excluded from
# link_configs, owned here).
configure_btop() {
    local conf="$CFG/btop/btop.conf"
    mkdir -p "$CFG/btop"
    link_one "$REPO/config/btop/themes" "$CFG/btop/themes"
    btop_set() {
        if grep -qs "^$1\b" "$conf"; then
            sed -i "s|^$1\b.*|$1 = $2|" "$conf"
        else
            printf '%s = %s\n' "$1" "$2" >> "$conf"
        fi
    }
    btop_set theme_background False
    btop_set color_theme '"mono"'
    btop_set vim_keys True
}

# micro's config dir carries live state (buffers/) next to the real
# configuration, so only the configuration links into the repo. The
# settings.json symlink is safe and deliberate: micro rewrites the file
# through the link on every exit in a stable normal form (alphabetical
# keys, 4-space indent) — the committed file is kept in that form, so
# the routine rewrite is byte-identical and the repo stays clean, while
# an interactive `set` lands in the repo as a visible diff to commit or
# revert (all verified on micro 2.0.13).
configure_micro() {
    mkdir -p "$CFG/micro"
    link_one "$REPO/config/micro/settings.json" "$CFG/micro/settings.json"
    link_one "$REPO/config/micro/colorschemes" "$CFG/micro/colorschemes"
}

# ------------------------------------------------------------- 10. desktop ---
apply_desktop_prefs() {
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark 2>/dev/null || true
    # GTK apps follow the one-typeface rule and the compositor's cursor
    # choice (cursor block in config/niri/input.kdl).
    gsettings set org.gnome.desktop.interface font-name "'$MONO_FONT 10'" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface monospace-font-name "'$MONO_FONT 11'" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme "'Adwaita'" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
}

# -------------------------------------------------------------- 11. reload ---
# The live niri session's IPC socket: NIRI_SOCKET inside the session,
# discovered under XDG_RUNTIME_DIR otherwise — so a run over ssh still
# reaches the desktop. Empty output means no session is up.
niri_socket() {
    if [ -n "${NIRI_SOCKET:-}" ]; then
        printf '%s' "$NIRI_SOCKET"
        return
    fi
    find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" -maxdepth 1 \
         -name 'niri.wayland-*.sock' 2>/dev/null | head -n1
}

# niri reloads its own config on save and starship re-reads per prompt,
# but waybar and mako hold config in memory, and a git pull can change
# their files without any link changing — so reload deterministically on
# every run. Waybar is respawned through niri's IPC, never exec'd
# directly: only the compositor holds the session environment
# (WAYLAND_DISPLAY) that a bar spawned from an ssh shell would lack.
reload_session() {
    local sock
    sock="$(niri_socket)"
    [ -n "$sock" ] || return 0
    log "restarting waybar, reloading mako"
    # stop the old bar and wait until it is gone, so the liveness check
    # below can only ever see the new one
    local _
    pkill -x -u "$(id -u)" waybar 2>/dev/null || true
    for _ in $(seq 1 20); do
        pgrep -x -u "$(id -u)" waybar >/dev/null || break
        sleep 0.1
    done
    NIRI_SOCKET="$sock" niri msg action spawn -- \
        sh -c "$HOME/.local/bin/bar-session" >/dev/null 2>&1 || true
    # a respawn that silently fails looks like a broken setup; verify the
    # bar is up and name the log that holds the reason when it is not
    for _ in $(seq 1 15); do
        pgrep -x -u "$(id -u)" waybar >/dev/null && break
        sleep 0.2
    done
    if pgrep -x -u "$(id -u)" waybar >/dev/null; then
        log "waybar is up"
    else
        warn "waybar did not come up — see ~/.cache/waybar.log"
    fi
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}" \
        makoctl reload >/dev/null 2>&1 || true
}

# ------------------------------------------------------------- 12. summary ---
portals_ok() {
    pacman -Qq xdg-desktop-portal-gtk >/dev/null 2>&1 \
        && pacman -Qq xdg-desktop-portal-gnome >/dev/null 2>&1
}

configs_linked() {
    [ -L "$CFG/niri" ] && [ "$(readlink -f "$CFG/niri")" = "$REPO/config/niri" ]
}

summary_row() {
    local label="$1" desc="$2"; shift 2
    if "$@" >/dev/null 2>&1; then
        printf '  \033[1;32m[ + ]\033[0m %-14s %s\n' "$label" "$desc"
    else
        printf '  \033[1;31m[ - ]\033[0m %-14s %s\n' "$label" "$desc"
    fi
}

print_summary() {
    printf '\n\033[1m[setup] installed components\033[0m\n'
    summary_row "Niri"          "scrollable-tiling Wayland compositor"   have niri
    summary_row "Dotfiles"      "config/ linked into ~/.config"          configs_linked
    summary_row "Xwayland-sat." "X11 bridge, auto-spawned by niri"       have xwayland-satellite
    summary_row "Plymouth"      "boot splash (mono theme)"               have plymouthd
    summary_row "Greetd"        "login page (monogreet on niri)"         have monogreet
    summary_row "PipeWire"      "audio server (pulse shim)"              have pipewire
    summary_row "Portals"       "xdg-desktop-portal gtk + gnome"         portals_ok
    summary_row "SSH agent"     "gcr-ssh-agent (gcr-4)"                  test -x /usr/lib/gcr-ssh-agent
    summary_row "Alacritty"     "terminal emulator"                      have alacritty
    summary_row "Rofi"          "application launcher (wayland 2.0)"     have rofi
    summary_row "Waybar"        "status bar"                             have waybar
    summary_row "Mako"          "notification daemon"                    have mako
    summary_row "Swaybg"        "wallpaper daemon"                       have swaybg
    summary_row "Hyprlock"      "screen locker (swaylock fallback)"      have hyprlock
    summary_row "Swayidle"      "idle manager"                           have swayidle
    summary_row "Yazi"          "terminal file manager (+ ya)"           have yazi
    summary_row "Zellij"        "terminal multiplexer"                   have zellij
    summary_row "Herdr"         "agent workspace manager (herdr.dev)"    have herdr
    summary_row "Cliphist"      "clipboard history"                      have cliphist
    summary_row "Starship"      "shell prompt"                           have starship
    summary_row "Btop"          "system monitor"                         have btop
    summary_row "Micro"         "text editor"                            have micro
    summary_row "Zathura"       "PDF viewer"                             have zathura
    # the imv package ships imv-wayland/imv-x11 plus a wrapper for its
    # desktop file — probe the wayland binary, not a bare `imv`
    summary_row "Imv"           "image viewer"                           have imv-wayland
    summary_row "Mpv"           "media player"                           have mpv
    summary_row "Paru"          "AUR helper (manual installs, updates)"  paru_ok
    summary_row "TLP"           "battery power tuning"                   have tlp
    summary_row "Chafa"         "terminal image renderer (yazi preview)" have chafa
    summary_row "Fzf"           "fuzzy finder"                           have fzf
    summary_row "Zoxide"        "directory jumper"                       have zoxide
    summary_row "Eza"           "ls replacement"                         have eza
    summary_row "Bat"           "cat with highlighting"                  have bat
    summary_row "Fd"            "find replacement"                       have fd
    summary_row "Ripgrep"       "grep replacement (rg)"                  have rg
    summary_row "Delta"         "git diff pager"                         have delta
    summary_row "Checkupdates"  "update probe (bar's updates module)"    have checkupdates
    summary_row "Wl-clipboard"  "Wayland clipboard (wl-copy/wl-paste)"   have wl-copy
    summary_row "Brightnessctl" "backlight control"                      have brightnessctl
    summary_row "Pulsemixer"    "audio mixer popup"                      have pulsemixer
    summary_row "Ksnip"         "screenshot annotator"                   have ksnip
    summary_row "Nerd Font"     "JetBrainsMono Nerd Font"                font_ok
    printf '\n'
}

# ---------------------------------------------------------------- 13. main ---
main() {
    case "${1:-install}" in
        install)
            install_packages
            install_paru
            install_herdr
            enable_system_units
            install_system_files
            configure_boot
            configure_greeter
            configure_git
            set_default_apps
            link_configs
            enable_units
            write_shell
            configure_btop
            configure_micro
            apply_desktop_prefs

            niri validate
            log "ALL OK — niri config valid"
            reload_session
            print_summary
            log "wallpaper: put an image at ~/Pictures/wallpaper.jpg (optional)"
            log "reboot: plymouth asks the passphrase, monogreet the login"
            ;;
        system)
            install_packages
            enable_system_units
            install_system_files
            configure_boot
            configure_greeter
            print_summary
            log "reboot: plymouth asks the passphrase, monogreet the login"
            ;;
        link|configure)
            link_configs
            enable_units
            # MIME defaults are re-applied here too: any hand-installed
            # app (a browser most of all) can rewrite mimeapps.list and
            # silently take the PDF and image types with it
            set_default_apps
            write_shell
            configure_btop
            configure_micro
            apply_desktop_prefs

            niri validate
            log "ALL OK — niri config valid"
            reload_session
            log "configs are live symlinks — edits apply on save; commit in the repo when happy"
            ;;
        summary)
            print_summary
            ;;
        *)
            die "unknown command: $1 (usage: bash setup.sh [link|system|summary])"
            ;;
    esac
}

# Run only when executed, not when sourced (keeps functions testable).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
