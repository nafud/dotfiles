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
#             defaults, gsettings, the ~/.bashrc block, the btop setting),
#             the linking itself, session reloads, and the final summary
#
# A real file or directory found where a link belongs is moved aside once
# as <name>.pre-dotfiles. Version history lives in git log.
#
# Usage:  bash setup.sh          full run: install everything + link configs
#         bash setup.sh link     (re)link configs + validate + reload only
#         bash setup.sh update   refresh what apt does not manage: pacstall
#                                builds (niri, rofi, xwayland-satellite),
#                                swaylock-effects,
#                                release binaries, hellwal
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
        pulsemixer grim slurp ksnip imagemagick \
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
    # waybar and mako ship enabled-by-packaging user services (global
    # scope); our niri config spawns both itself, so remove the enablement
    # where it was made. Disabling only edits disk — the user manager
    # already running holds the old enablement in memory and would still
    # pull the unit up at the next login (a second bar on screen), so the
    # stop clears any duplicate and the reload drops the stale dependency.
    local unit
    for unit in waybar.service mako.service; do
        if systemctl --global is-enabled "$unit" >/dev/null 2>&1; then
            log "disabling globally-enabled $unit"
            sudo systemctl --global disable "$unit"
        fi
        systemctl --user stop "$unit" 2>/dev/null || true
    done
    systemctl --user daemon-reload 2>/dev/null || true

    # Cinnamon-desktop autostarts leak into niri via xdg-autostart-generator
    # (systemd runs /etc/xdg/autostart under any session): ibus is
    # Cinnamon's input method, blueman's applet and mintreport are tray
    # icons we don't keep, touchegg serves X11 gestures, nm-applet is
    # covered by the bar's network module and nmtui, geoclue's demo agent
    # and evolution's alarm notifier serve apps that aren't here. Hide
    # each for this user with the XDG-specified per-user override — never
    # system-wide, so the Cinnamon fallback session keeps its own behavior.
    local desk
    for desk in ibus-daemon.desktop blueman.desktop touchegg.desktop \
                nm-applet.desktop mintreport.desktop \
                geoclue-demo-agent.desktop \
                org.gnome.Evolution-alarm-notify.desktop; do
        if [ -f "/etc/xdg/autostart/$desk" ]; then
            mkdir -p "$CFG/autostart"
            if ! grep -qs '^Hidden=true' "$CFG/autostart/$desk"; then
                log "hiding ${desk%.desktop} autostart for this user"
                cp "/etc/xdg/autostart/$desk" "$CFG/autostart/"
                echo "Hidden=true" >> "$CFG/autostart/$desk"
            fi
        fi
    done
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
# The release URLs always point at latest, so `force` (the update path)
# reinstalls unconditionally; without it anything present is kept.
install_binaries() {
    local force="${1:-}"
    if [ -n "$force" ] || ! have yazi; then
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

    if [ -n "$force" ] || ! have zellij; then
        log "installing zellij"
        fetch "$WORK/zellij.tar.gz" \
            https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz
        tar xzf "$WORK/zellij.tar.gz" -C "$WORK" zellij
        [ -f "$WORK/zellij" ] || die "zellij missing from archive"
        sudo install -m 755 "$WORK/zellij" /usr/local/bin/
    fi

    if [ -n "$force" ] || ! have cliphist; then
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

# chafa: yazi's image-preview renderer in terminals without a graphics
# protocol (alacritty). The archive's 1.14 predates flags yazi passes
# (--probe; previews die with "chafa failed with status: exit status:
# 2"), so a pinned upstream release is built from source into
# /usr/local, which shadows any apt copy on PATH. Bump CHAFA_VER to
# move to a newer release; `setup.sh update` rebuilds it.
CHAFA_VER="1.18.2"
install_chafa() {
    local force="${1:-}"
    if [ -z "$force" ] && have chafa \
        && chafa --version | grep -qF "version $CHAFA_VER"; then
        return
    fi
    log "building chafa $CHAFA_VER"
    sudo apt-get install -y libglib2.0-dev libjpeg-dev libwebp-dev
    fetch "$WORK/chafa.tar.xz" \
        "https://github.com/hpjansson/chafa/releases/download/$CHAFA_VER/chafa-$CHAFA_VER.tar.xz"
    tar xf "$WORK/chafa.tar.xz" -C "$WORK"
    (cd "$WORK/chafa-$CHAFA_VER" && ./configure --quiet \
        && make -s -j"$(nproc)" && sudo make -s install)
    sudo ldconfig
}

# swaylock-effects: the lock screen with time at rest in the ring.
# Stock swaylock has no clock; this fork (packaged by Alpine and other
# distros) adds one with the same config format, CLI and PAM service
# name. Built from a pinned tag, only the binary installed — it shadows
# the archive's /usr/bin/swaylock on PATH while the archive package
# stays for /etc/pam.d/swaylock, which both binaries use. bin/lock
# detects the clock capability, so either binary locks correctly.
SLE_VER="v1.7.0.0"
install_swaylock_effects() {
    local force="${1:-}"
    if [ -z "$force" ] && have swaylock \
        && swaylock --help 2>&1 | grep -q -- --clock; then
        return
    fi
    log "building swaylock-effects $SLE_VER"
    sudo apt-get install -y meson ninja-build libpam0g-dev libcairo2-dev \
        libgdk-pixbuf-2.0-dev libxkbcommon-dev libwayland-dev wayland-protocols
    git clone -q --depth 1 -b "$SLE_VER" \
        https://github.com/jirutka/swaylock-effects "$WORK/swaylock-effects"
    (cd "$WORK/swaylock-effects" \
        && meson setup build --buildtype=release -Dman-pages=disabled >/dev/null \
        && ninja -C build >/dev/null)
    sudo install -m 755 "$WORK/swaylock-effects/build/swaylock" /usr/local/bin/swaylock
}

# hellwal: fast pywal-style palette generator, used by bin/wallset. Not
# in the Ubuntu archive; a small C build from source (build-essential).
# Output lands in ~/.cache/hellwal/, themes in ~/.config/hellwal/themes.
install_hellwal() {
    local force="${1:-}"
    if [ -n "$force" ] || ! have hellwal; then
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
# whenever dpkg, apt or flatpak state changes.
enable_units() {
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now waybar-updates.path 2>/dev/null \
        || warn "could not enable waybar-updates.path (no user session?)"
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

# gnome-keyring's ssh agent, unlocked with the login keyring; never
# clobbers an agent that is already set (e.g. one forwarded over ssh)
[ -z "${SSH_AUTH_SOCK:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/keyring/ssh" ] \
    && export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/keyring/ssh"

[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash
eval "$(zoxide init bash)"
eval "$(starship init bash)"
# <<< niri-setup managed block <<<
EOF

    cat "$body" > "$rc"
}

# btop rewrites its whole config file on every clean exit, so linking it
# would put btop's runtime state under git. Like ~/.bashrc it stays a
# real file owned by the program; only the one intended setting is
# enforced: theme_background False lets the terminal's glass show
# through instead of btop painting an opaque ground.
# btop owns btop.conf (rewritten on every exit), so only the intent
# lines are enforced in place; the themes dir is read-only to btop and
# links normally (excluded from link_configs, owned here).
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

# The alacritty config imports the hellwal palette cache; seed it empty
# so a machine that never ran wallset parses cleanly and stays mono.
configure_hellwal() {
    [ -f "$HOME/.cache/hellwal/alacritty-colors.toml" ] \
        || install -D -m 644 /dev/null "$HOME/.cache/hellwal/alacritty-colors.toml"
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

# ------------------------------------------------------------ 11. summary ---
portals_ok() {
    dpkg -s xdg-desktop-portal-gtk >/dev/null 2>&1 \
        && dpkg -s xdg-desktop-portal-gnome >/dev/null 2>&1
}

# true when the swaylock on PATH is the effects fork (has the clock)
swaylock_effects_ok() { swaylock --help 2>&1 | grep -q -- --clock; }

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
    summary_row "Swaylock"      "screen locker (clock fork)"             swaylock_effects_ok
    summary_row "Swayidle"      "idle manager"                           have swayidle
    summary_row "Yazi"          "terminal file manager (+ ya)"           have yazi
    summary_row "Zellij"        "terminal multiplexer"                   have zellij
    summary_row "Cliphist"      "clipboard history"                      have cliphist
    summary_row "Starship"      "shell prompt"                           have starship
    summary_row "Btop"          "system monitor"                         have btop
    summary_row "Micro"         "text editor"                            have micro
    summary_row "Zathura"       "PDF viewer"                             have zathura
    # the imv package ships imv-wayland/imv-x11 plus a libexec wrapper for
    # its desktop file — there is no bare `imv` command to probe
    summary_row "Imv"           "image viewer"                           have imv-wayland
    summary_row "Mpv"           "media player"                           have mpv
    summary_row "Chafa"         "terminal image renderer (yazi preview)" have chafa
    summary_row "Fzf"           "fuzzy finder"                           have fzf
    summary_row "Zoxide"        "directory jumper"                       have zoxide
    summary_row "Eza"           "ls replacement"                         have eza
    summary_row "Bat"           "cat with highlighting (batcat)"         have batcat
    summary_row "Fd"            "find replacement (fdfind)"              have fdfind
    summary_row "Ripgrep"       "grep replacement (rg)"                  have rg
    summary_row "Delta"         "git diff pager"                         have delta
    summary_row "Wl-clipboard"  "Wayland clipboard (wl-copy/wl-paste)"   have wl-copy
    summary_row "Brightnessctl" "backlight control"                      have brightnessctl
    summary_row "Pulsemixer"    "audio mixer popup"                      have pulsemixer
    summary_row "Ksnip"         "screenshot annotator"                   have ksnip
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
            install_swaylock_effects
            install_hellwal
            install_chafa
            configure_git
            set_default_apps
            link_configs
            enable_units
            write_shell
            configure_btop
            configure_micro
            configure_hellwal
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
            enable_units
            write_shell
            configure_btop
            configure_micro
            configure_hellwal
            apply_desktop_prefs

            niri validate
            log "ALL OK — niri config valid"
            reload_session
            log "configs are live symlinks — edits apply on save; commit in the repo when happy"
            ;;
        update)
            log "pacstall upgrades (niri, rofi, xwayland-satellite)"
            pacstall -P -Up
            install_binaries force
            install_hellwal force
            install_chafa force
            install_swaylock_effects force
            log "update complete"
            print_summary
            ;;
        summary)
            print_summary
            ;;
        *)
            die "unknown command: $1 (usage: bash setup.sh [link|update|summary])"
            ;;
    esac
}

# Run only when executed, not when sourced (keeps functions testable).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
