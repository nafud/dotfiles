#!/usr/bin/env bash
#
# setup.sh — bootstrap for the niri desktop dotfiles
# Target: Arch Linux (base install per docs/arch-install.md), fresh or
# existing.
#
# The repository layout is the source of truth:
#   config/   mirrors ~/.config and is symlinked there, entry by entry —
#             edits in the repo are live (niri and starship reload on save)
#   bin/      mirrors ~/.local/bin, symlinked the same way
#   setup.sh  everything a config file cannot express: packages, system
#             glue (greetd, units, MIME defaults, gsettings, the ~/.bashrc
#             block, the btop setting), the linking itself, session
#             reloads, and the final summary
#
# Nearly everything installs from the official repositories; the one
# exception is a small AUR set (Mullvad VPN, Chrome, Mullvad Browser)
# built with paru, which this script bootstraps. No other third-party
# builds, no release-binary downloads.
#
# A real file or directory found where a link belongs is moved aside once
# as <name>.pre-dotfiles. Version history lives in git log.
#
# Usage:  bash setup.sh          full run: install everything + link configs
#         bash setup.sh link     (re)link configs + validate + reload only
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

WORK="$(mktemp -d -t niri-setup.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# Match the full family name: a vanilla "JetBrains Mono" install also greps
# true for bare "JetBrainsMono" and would skip the Nerd Font glyphs.
font_ok() { fc-match "$MONO_FONT" | grep -q "JetBrainsMono Nerd Font"; }

# ------------------------------------------------------------- 1. packages ---
# One transaction, official repos only. --needed keeps reruns cheap and
# never reinstalls; the full-system upgrade first is the supported way to
# install on Arch (partial upgrades are not).
install_packages() {
    log "pacman packages"
    sudo pacman -Syu --needed --noconfirm \
        niri xwayland-satellite \
        alacritty waybar mako swaybg swayidle swaylock hyprlock rofi \
        yazi zellij cliphist starship chafa micro btop \
        zathura zathura-pdf-poppler imv mpv firefox \
        grim slurp ksnip imagemagick brightnessctl pulsemixer \
        fzf zoxide wl-clipboard fd ripgrep eza bat git-delta jq \
        p7zip unzip xdg-user-dirs \
        libnotify gnome-keyring qt5-wayland \
        gsettings-desktop-schemas adwaita-icon-theme \
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \
        pipewire pipewire-pulse pipewire-alsa wireplumber \
        greetd greetd-tuigreet \
        ttf-jetbrains-mono-nerd pacman-contrib

    [ -f /usr/share/wayland-sessions/niri.desktop ] \
        || die "niri.desktop missing from wayland-sessions — session not registered"
    font_ok || die "ttf-jetbrains-mono-nerd installed but fc-match does not resolve it"
    log "font ok: $(fc-match "$MONO_FONT")"

    # X11 apps (Steam, Discord, ...): niri >= 25.08 spawns xwayland-satellite
    # on demand, exports $DISPLAY, and restarts it if it dies — the binary in
    # $PATH is the whole requirement. No spawn-at-startup, no env plumbing.
}

# ------------------------------------------------------------------ 2. AUR ---
# The AUR set: Mullvad VPN (the bar's vpn module), Chrome, and Mullvad
# Browser — none are in the official repos. paru-bin bootstraps without
# a Rust compile; from then on `paru -Syu` upgrades repos and AUR alike.
# Mullvad Browser note: the AUR package tracks the stable channel; the
# alpha channel is Mullvad's own tarball with its built-in updater.
install_aur() {
    if ! have paru; then
        log "bootstrapping paru (AUR helper)"
        git clone -q https://aur.archlinux.org/paru-bin.git "$WORK/paru-bin"
        (cd "$WORK/paru-bin" && makepkg -si --noconfirm)
        have paru || die "paru bootstrap failed"
    fi
    log "AUR packages"
    paru -S --needed --noconfirm mullvad-vpn-bin google-chrome mullvad-browser-bin
}

# ----------------------------------------------------------- 3. system units ---
# mullvad-daemon: the AUR package installs but does not enable the unit
# the CLI and bar module talk to. paccache: bound the pacman cache (the
# @pkg subvolume is excluded from snapshots but nothing else limits it).
enable_system_units() {
    sudo systemctl enable mullvad-daemon 2>/dev/null \
        || warn "could not enable mullvad-daemon"
    sudo systemctl enable paccache.timer 2>/dev/null \
        || warn "could not enable paccache.timer"
}

# --------------------------------------------------------------- 4. greetd ---
# tuigreet on VT1 answers the login; niri.desktop under wayland-sessions is
# what --sessions lists. Enable only writes symlinks — greetd takes the VT
# at the next boot, never mid-session.
configure_greetd() {
    local conf=/etc/greetd/config.toml want
    want="$(cat <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions"
user = "greeter"
EOF
)"
    if [ ! -f "$conf" ] || [ "$(cat "$conf")" != "$want" ]; then
        log "writing $conf"
        printf '%s\n' "$want" | sudo tee "$conf" >/dev/null
    fi
    sudo systemctl enable greetd 2>/dev/null \
        || warn "could not enable greetd"
}

configure_git() {
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
}

# --------------------------------------------------- 5. MIME associations ---
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

# ----------------------------------------------------------- 6. link tree ---
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
}

# --------------------------------------------------------- 7. shell setup ---
# ~/.bashrc is shared with the system's own content, so it is not linked;
# only the marked block is owned, and it is replaced in place on every run
# so edits here reach existing installs.
write_shell() {
    local rc="$HOME/.bashrc"
    local body="$WORK/bashrc"
    [ -f "$rc" ] || touch "$rc"

    log "writing managed block into ~/.bashrc"
    printf '%s\n\n' "$(awk '
        /^# >>> niri-setup managed block >>>$/,/^# <<< niri-setup managed block <<<$/ { next }
        /^# >>> terminal-readability block >>>$/,/^# <<< terminal-readability block <<<$/ { next }
        { print }
    ' "$rc")" > "$body"

    cat >> "$body" <<'EOF'
# >>> niri-setup managed block >>>
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

# gnome-keyring's ssh agent, unlocked with the login keyring; never
# clobbers an agent that is already set (e.g. one forwarded over ssh)
[ -z "${SSH_AUTH_SOCK:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/keyring/ssh" ] \
    && export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/keyring/ssh"

[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash
eval "$(zoxide init bash)"
eval "$(starship init bash)"
# <<< niri-setup managed block <<<
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

# ------------------------------------------------------------- 8. desktop ---
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

# -------------------------------------------------------------- 9. reload ---
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

# ------------------------------------------------------------ 10. summary ---
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
    summary_row "Greetd"        "login greeter (tuigreet)"               have tuigreet
    summary_row "PipeWire"      "audio server (pulse shim)"              have pipewire
    summary_row "Portals"       "xdg-desktop-portal gtk + gnome"         portals_ok
    summary_row "Keyring"       "gnome-keyring (Secret portal)"          have gnome-keyring-daemon
    summary_row "Alacritty"     "terminal emulator"                      have alacritty
    summary_row "Rofi"          "application launcher (wayland 2.0)"     have rofi
    summary_row "Waybar"        "status bar"                             have waybar
    summary_row "Mako"          "notification daemon"                    have mako
    summary_row "Swaybg"        "wallpaper daemon"                       have swaybg
    summary_row "Hyprlock"      "screen locker (swaylock fallback)"      have hyprlock
    summary_row "Swayidle"      "idle manager"                           have swayidle
    summary_row "Yazi"          "terminal file manager (+ ya)"           have yazi
    summary_row "Zellij"        "terminal multiplexer"                   have zellij
    summary_row "Cliphist"      "clipboard history"                      have cliphist
    summary_row "Starship"      "shell prompt"                           have starship
    summary_row "Btop"          "system monitor"                         have btop
    summary_row "Micro"         "text editor"                            have micro
    summary_row "Zathura"       "PDF viewer"                             have zathura
    # the imv package ships imv-wayland/imv-x11 plus a wrapper for its
    # desktop file — probe the wayland binary, not a bare `imv`
    summary_row "Imv"           "image viewer"                           have imv-wayland
    summary_row "Mpv"           "media player"                           have mpv
    summary_row "Mullvad VPN"   "tunnel (bar's vpn module)"              have mullvad
    summary_row "Firefox"       "browser"                                have firefox
    summary_row "Chrome"        "browser"                                have google-chrome-stable
    summary_row "Mullvad Brows." "browser (stable; alpha = own tarball)" have mullvad-browser
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

# --------------------------------------------------------------- 11. main ---
main() {
    case "${1:-install}" in
        install)
            install_packages
            install_aur
            enable_system_units
            configure_greetd
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
            log "reboot (or log out) and pick the 'niri' session in tuigreet"
            ;;
        link|configure)
            link_configs
            enable_units
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
            die "unknown command: $1 (usage: bash setup.sh [link|summary])"
            ;;
    esac
}

# Run only when executed, not when sourced (keeps functions testable).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
