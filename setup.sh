#!/usr/bin/env bash
#
# setup.sh — bootstrap for the niri desktop dotfiles
# Target: Linux Mint 22.x (Ubuntu 24.04 base), fresh or existing install.
#
# The repository layout is the source of truth:
#   config/   mirrors ~/.config and is symlinked there, entry by entry —
#             edits in the repo are live (niri and starship reload on save)
#   bin/      mirrors ~/.local/bin, symlinked the same way
#   setup.sh  everything a config file cannot express: packages, the niri
#             build, fonts, release binaries, system glue (units, MIME
#             defaults, gsettings, the ~/.bashrc managed block), the
#             linking itself, session reloads, and the final summary
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

# fetch DEST URL — download with a loud failure; an empty file is a failure.
fetch() {
    wget -qO "$1" "$2" || die "download failed: $2"
    [ -s "$1" ] || die "empty download: $2"
}

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
install_packages() {
    log "apt packages"
    sudo apt-get update -qq
    sudo apt-get install -y \
        alacritty waybar mako-notifier swaybg \
        swaylock swayidle \
        brightnessctl btop jq unzip wget curl build-essential \
        fzf zoxide wl-clipboard fd-find ripgrep \
        eza bat git-delta \
        zathura zathura-pdf-poppler imv mpv micro \
        libnotify-bin \
        xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \
        gnome-keyring
}

# ------------------------------------------------- 2. niri (via pacstall) ---
install_niri() {
    if ! have pacstall; then
        log "installing pacstall"
        fetch "$WORK/pacstall-install.sh" https://pacstall.dev/q/install
        sudo bash "$WORK/pacstall-install.sh" </dev/null
        have pacstall || die "pacstall installer ran but produced no pacstall binary"
    fi
    if have niri; then
        log "niri present: $(niri --version)"
    else
        log "installing niri (pacstall build — takes a while)"
        pacstall -P -I niri
    fi
    [ -f /usr/share/wayland-sessions/niri.desktop ] \
        || die "niri.desktop missing from wayland-sessions — session not registered"

    # X11 apps (Steam, Discord, ...): niri >= 25.08 spawns xwayland-satellite
    # on demand, exports $DISPLAY, and restarts it if it dies — the binary in
    # $PATH is the whole requirement. No spawn-at-startup, no env plumbing.
    if ! have xwayland-satellite; then
        log "installing xwayland-satellite (pacstall build — takes a while)"
        pacstall -P -I xwayland-satellite
    fi
}

# -------------------------------------------- 3. undo packaging surprises ---
fix_units() {
    # waybar ships an enabled-by-packaging user service (global scope); our
    # niri config owns the bar, so remove the enablement where it was made.
    if systemctl --global is-enabled waybar.service >/dev/null 2>&1; then
        log "disabling globally-enabled waybar.service"
        sudo systemctl --global disable waybar.service
    fi

    # ibus autostart leaks into niri via xdg-autostart-generator; hide it for
    # this user with the XDG-specified per-user override.
    if [ -f /etc/xdg/autostart/ibus-daemon.desktop ]; then
        mkdir -p "$CFG/autostart"
        if ! grep -qs '^Hidden=true' "$CFG/autostart/ibus-daemon.desktop"; then
            log "hiding ibus autostart for this user"
            cp /etc/xdg/autostart/ibus-daemon.desktop "$CFG/autostart/"
            echo "Hidden=true" >> "$CFG/autostart/ibus-daemon.desktop"
        fi
    fi
}

# ----------------------------------------------------------------- 4. font ---
install_font() {
    if ! font_ok; then
        log "installing JetBrainsMono Nerd Font"
        mkdir -p "$HOME/.local/share/fonts"
        fetch "$WORK/jbm.zip" \
            https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
        unzip -qo "$WORK/jbm.zip" -d "$HOME/.local/share/fonts/JetBrainsMonoNerd"
        fc-cache -f
    fi
    font_ok || die "font install failed"
    log "font ok: $(fc-match "$MONO_FONT")"
}

# ---------------------------------------------- 5. github-release binaries ---
install_binaries() {
    if ! have yazi; then
        log "installing yazi + ya"
        fetch "$WORK/yazi.zip" \
            https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip
        unzip -qo "$WORK/yazi.zip" -d "$WORK/yazi"
        local tool path
        for tool in ya yazi; do
            path=$(find "$WORK/yazi" -type f -name "$tool" | head -n1)
            [ -n "$path" ] || die "$tool missing from yazi archive"
            sudo install -m 755 "$path" /usr/local/bin/
        done
    fi

    if ! have zellij; then
        log "installing zellij"
        fetch "$WORK/zellij.tar.gz" \
            https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz
        tar xzf "$WORK/zellij.tar.gz" -C "$WORK" zellij
        [ -f "$WORK/zellij" ] || die "zellij missing from archive"
        sudo install -m 755 "$WORK/zellij" /usr/local/bin/
    fi

    if ! have cliphist; then
        log "installing cliphist"
        local url
        url=$(curl -fsSL https://api.github.com/repos/sentriz/cliphist/releases/latest \
              | jq -r '.assets[] | select(.name|test("linux-amd64$")) | .browser_download_url' \
              | head -n1)
        [ -n "$url" ] || die "could not resolve cliphist download URL"
        fetch "$WORK/cliphist" "$url"
        sudo install -m 755 "$WORK/cliphist" /usr/local/bin/cliphist
    fi
}

install_starship() {
    if ! have starship; then
        log "installing starship prompt"
        fetch "$WORK/starship-install.sh" https://starship.rs/install.sh
        sh "$WORK/starship-install.sh" -y
    fi
}

# Upstream rofi 2.0 runs natively on Wayland (lbonn's fork was merged);
# the Ubuntu archive still ships the X11-only 1.7, which under niri would
# run through xwayland-satellite and misplace its window. Pacstall builds
# 2.0, so rofi installs through the same channel as niri itself.
install_rofi() {
    if ! have rofi; then
        log "installing rofi (pacstall build — takes a while)"
        pacstall -P -I rofi
    fi
}

# hellwal: fast pywal-style palette generator, used by bin/wallset. Not
# in the Ubuntu archive; a small C build from source (build-essential).
# Output lands in ~/.cache/hellwal/, themes in ~/.config/hellwal/themes.
install_hellwal() {
    if ! have hellwal; then
        log "building hellwal"
        git clone -q --depth 1 https://github.com/danihek/hellwal "$WORK/hellwal"
        make -s -C "$WORK/hellwal"
        sudo install -m 755 "$WORK/hellwal/hellwal" /usr/local/bin/
    fi
}

configure_git() {
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
}

# --------------------------------------------------- 6. MIME associations ---
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

# ----------------------------------------------------------- 7. link tree ---
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

# --------------------------------------------------------- 8. shell setup ---
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
alias cat='batcat --style=plain --paging=never'
alias bat='batcat'
alias fd='fdfind'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -c'

export EDITOR=micro
export VISUAL=micro
export MANPAGER="sh -c 'col -bx | batcat -l man -p'"

[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash
eval "$(zoxide init bash)"
eval "$(starship init bash)"
# <<< niri-setup managed block <<<
EOF

    cat "$body" > "$rc"
}

# ------------------------------------------------------------- 9. desktop ---
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

# ------------------------------------------------------------ 10. reload ---
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
    pkill -x -u "$(id -u)" waybar 2>/dev/null || true
    NIRI_SOCKET="$sock" niri msg action spawn -- waybar >/dev/null 2>&1 || true
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}" \
        makoctl reload >/dev/null 2>&1 || true
}

# ------------------------------------------------------------ 11. summary ---
portals_ok() {
    dpkg -s xdg-desktop-portal-gtk >/dev/null 2>&1 \
        && dpkg -s xdg-desktop-portal-gnome >/dev/null 2>&1
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
    summary_row "Portals"       "xdg-desktop-portal gtk + gnome"         portals_ok
    summary_row "Keyring"       "gnome-keyring (Secret portal)"          have gnome-keyring-daemon
    summary_row "Alacritty"     "terminal emulator"                      have alacritty
    summary_row "Rofi"          "application launcher (wayland 2.0)"     have rofi
    summary_row "Hellwal"       "palette generator (see wallset)"        have hellwal
    summary_row "Waybar"        "status bar"                             have waybar
    summary_row "Mako"          "notification daemon"                    have mako
    summary_row "Swaybg"        "wallpaper daemon"                       have swaybg
    summary_row "Swaylock"      "screen locker"                          have swaylock
    summary_row "Swayidle"      "idle manager"                           have swayidle
    summary_row "Yazi"          "terminal file manager (+ ya)"           have yazi
    summary_row "Zellij"        "terminal multiplexer"                   have zellij
    summary_row "Cliphist"      "clipboard history"                      have cliphist
    summary_row "Starship"      "shell prompt"                           have starship
    summary_row "Btop"          "system monitor"                         have btop
    summary_row "Micro"         "text editor"                            have micro
    summary_row "Zathura"       "PDF viewer"                             have zathura
    summary_row "Imv"           "image viewer"                           have imv
    summary_row "Mpv"           "media player"                           have mpv
    summary_row "Fzf"           "fuzzy finder"                           have fzf
    summary_row "Zoxide"        "directory jumper"                       have zoxide
    summary_row "Eza"           "ls replacement"                         have eza
    summary_row "Bat"           "cat with highlighting (batcat)"         have batcat
    summary_row "Fd"            "find replacement (fdfind)"              have fdfind
    summary_row "Ripgrep"       "grep replacement (rg)"                  have rg
    summary_row "Delta"         "git diff pager"                         have delta
    summary_row "Wl-clipboard"  "Wayland clipboard (wl-copy/wl-paste)"   have wl-copy
    summary_row "Brightnessctl" "backlight control"                      have brightnessctl
    summary_row "Nerd Font"     "JetBrainsMono Nerd Font"                font_ok
    printf '\n'
}

# --------------------------------------------------------------- 12. main ---
main() {
    case "${1:-install}" in
        install)
            install_packages
            install_niri
            fix_units
            install_font
            install_binaries
            install_starship
            install_rofi
            install_hellwal
            configure_git
            set_default_apps
            link_configs
            write_shell
            apply_desktop_prefs

            niri validate
            log "ALL OK — niri config valid"
            reload_session
            print_summary
            log "wallpaper: put an image at ~/Pictures/wallpaper.jpg (optional)"
            log "log out of Cinnamon and choose the 'niri' session at the greeter"
            ;;
        link|configure)
            link_configs
            write_shell
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
