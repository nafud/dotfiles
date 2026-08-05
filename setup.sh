#!/usr/bin/env bash
#
# setup.sh — one-shot, re-runnable bootstrap for the niri "Option B" desktop
# Target: Linux Mint 22.x (Ubuntu 24.04 base), fresh or existing install.
# v9: the waybar clock gains seconds (and the 1 s tick that requires); the
#     starship prompt drops its seconds (the bar is the clock now, the
#     prompt stamp only marks when a command ran); the prompt glyph becomes
#     "→" (U+2192) — JetBrains Mono carries U+276F "❯" but draws it as a
#     thin quotation chevron that reads as a stray paren at prompt size,
#     while U+2192 is a true arrow in the family, the same glyph its ->
#     ligature produces; GTK apps join the monospace look via the
#     interface font gsettings (note: dconf is shared, so a Cinnamon login
#     sees the same fonts until reset).
#
# Design rules:
#   - This file is the single source of truth: configs are written from here.
#     Hand-edit configs to experiment, then fold changes back into this file;
#     put() keeps a .prev copy of anything it overwrites that differed.
#   - Idempotent: safe to run repeatedly; every step checks before acting.
#   - Package-level problems are fixed at the level they were created
#     (e.g. globally-enabled units are globally disabled).
#
# Usage:  bash setup.sh
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

# put DEST [MODE] — write stdin to DEST (parent dirs created). A no-op when
# the content is already identical; when it overwrites differing content it
# keeps DEST.prev so a hand-edited experiment survives one run to be folded
# back into this file.
put() {
    local dest="$1" mode="${2:-644}" tmp="$WORK/staged"
    cat > "$tmp"
    if [ -f "$dest" ]; then
        cmp -s "$tmp" "$dest" && return 0
        cp -p "$dest" "$dest.prev"
        log "kept $dest.prev (local copy differed)"
    fi
    install -D -m "$mode" "$tmp" "$dest"
}

[ "$(id -u)" -eq 0 ] && die "run as your user, not root (sudo is used where needed)"

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
        alacritty fuzzel waybar mako-notifier swaybg \
        swaylock swayidle \
        brightnessctl btop jq unzip wget curl \
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

# ------------------------------------------------------------- 6. configs ---
write_niri() {
    put "$CFG/niri/config.kdl" <<'EOF'
include "input.kdl"
include "workspaces.kdl"
include "layout.kdl"
include "animations.kdl"
include "misc.kdl"
include "binds.kdl"
include "decorations.kdl"
EOF

    put "$CFG/niri/input.kdl" <<'EOF'
input {
    keyboard {
        xkb {
            options "ctrl:nocaps"
        }
        repeat-delay 500
        repeat-rate 30
        numlock
    }
    touchpad {
        tap
        natural-scroll
        accel-speed 0.4
    }
    focus-follows-mouse max-scroll-amount="0%"
}
EOF

    put "$CFG/niri/workspaces.kdl" <<'EOF'
workspace "term"
workspace "web"
EOF

    put "$CFG/niri/layout.kdl" <<'EOF'
layout {
    focus-ring {
        width 2
        active-color "#e8e8e8"
        inactive-color "transparent"
    }
    border {
        on
        width 1
        active-color "#33333388"
        inactive-color "#33333388"
    }
    shadow { off; }
    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
    gaps 8
}
EOF

    put "$CFG/niri/animations.kdl" <<'EOF'
animations {
    window-movement {
        spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
    }
}
EOF

    put "$CFG/niri/misc.kdl" <<'EOF'
prefer-no-csd

environment {
    _JAVA_AWT_WM_NONREPARENTING "1"
    MOZ_ENABLE_WAYLAND "1"
}

spawn-at-startup "waybar"
spawn-at-startup "mako"
spawn-at-startup "sh" "-c" "swaybg -i ~/Pictures/wallpaper.jpg -m fill || swaybg -c '#0d0d0d'"
spawn-at-startup "swayidle" "-w" "timeout" "600" "swaylock -f" "timeout" "630" "niri msg action power-off-monitors" "resume" "niri msg action power-on-monitors" "before-sleep" "swaylock -f"
spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store"
spawn-at-startup "sh" "-c" "$HOME/.local/bin/battwatch.sh"
EOF

    put "$CFG/niri/decorations.kdl" <<'EOF'
window-rule {
    match app-id="^Alacritty$"
    match app-id="^Alacritty-floating$"
    draw-border-with-background false
}

window-rule {
    match app-id="^Alacritty-floating$"
    open-floating true
}

window-rule {
    match app-id="^btop-float$"
    open-floating true
    default-column-width { proportion 0.7; }
}

window-rule {
    match app-id="firefox"
    open-on-workspace "web"
}
EOF

    put "$CFG/niri/binds.kdl" <<'EOF'
binds {
    Mod+Shift+Slash { show-hotkey-overlay; }

    Mod+T { spawn "alacritty"; }
    Mod+Return { spawn "alacritty" "--class" "Alacritty-floating"; }
    Mod+D { spawn "fuzzel"; }
    Mod+B { spawn "alacritty" "--class" "btop-float" "-e" "btop"; }
    // Dedicated yazi terminal. The cwd-following y() wrapper is for
    // interactive shells; here the shell would die with the window anyway.
    Mod+E { spawn "alacritty" "-e" "yazi"; }
    Mod+Shift+T { spawn "alacritty" "-e" "zellij" "attach" "-c" "main"; }
    Mod+W { spawn "alacritty" "-e" "sh" "-c" "zellij attach files 2>/dev/null || zellij -s files --layout files"; }
    Mod+V { spawn "sh" "-c" "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"; }
    Mod+Shift+L { spawn "swaylock" "-f"; }

    Mod+O { toggle-overview; }

    Mod+Q { close-window; }

    // Cycle columns with wrap-around; niri has no whole-window next/previous
    // cycling ("next-window" is not a niri action). For MRU alt-tab behavior
    // instead, bind focus-window-previous.
    Mod+Tab { focus-column-right-or-first; }
    Mod+Shift+Tab { focus-column-left-or-last; }

    Mod+H { focus-column-left; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }
    Mod+L { focus-column-right; }
    Mod+Left  { focus-column-left; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }
    Mod+Right { focus-column-right; }

    Mod+Ctrl+H { move-column-left; }
    Mod+Ctrl+J { move-window-down; }
    Mod+Ctrl+K { move-window-up; }
    Mod+Ctrl+L { move-column-right; }

    Mod+Home { focus-column-first; }
    Mod+End  { focus-column-last; }

    Mod+R { switch-preset-column-width; }
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }
    Mod+Comma { consume-window-into-column; }
    Mod+Period { expel-window-from-column; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+Ctrl+1 { move-column-to-workspace 1; }
    Mod+Ctrl+2 { move-column-to-workspace 2; }
    Mod+Ctrl+3 { move-column-to-workspace 3; }
    Mod+Ctrl+4 { move-column-to-workspace 4; }

    XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-"; }
    XF86AudioMute allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "set" "5%+"; }
    XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "set" "5%-"; }

    Mod+Shift+E { quit; }
    Print { screenshot; }
    Ctrl+Print { screenshot-screen; }
    Alt+Print { screenshot-window; }
}
EOF
}

write_terminal_stack() {
    put "$CFG/alacritty/alacritty.toml" <<'EOF'
[window]
padding = { x = 2, y = 2 }
dynamic_padding = true
opacity = 0.92

[font]
size = 11
normal.family = "JetBrainsMono Nerd Font"

[colors.primary]
background = "#0d0d0d"
foreground = "#c0c0c0"

[colors.cursor]
text = "#0d0d0d"
cursor = "#c0c0c0"

[colors.normal]
black = "#1a1a1a"
red = "#b5626a"
green = "#7f9f7f"
yellow = "#b0a06a"
blue = "#7a91a8"
magenta = "#9a86a8"
cyan = "#7fa8a0"
white = "#c0c0c0"

[colors.bright]
black = "#666666"
red = "#c87e85"
green = "#98b898"
yellow = "#c8ba86"
blue = "#93aabf"
magenta = "#b19fc0"
cyan = "#98bfb8"
white = "#e8e8e8"

[[hints.enabled]]
regex = "(https:|http:|file:|git:|ssh:|ftp:|mailto:)[^\\u0000-\\u001F\\u007F-\\u009F<>\"\\s{-}\\^⟨⟩`]+"
hyperlinks = true
command = "xdg-open"
post_processing = true
binding = { key = "T", mods = "Control|Shift" }
EOF

    put "$CFG/fuzzel/fuzzel.ini" <<'EOF'
[main]
font=JetBrainsMono Nerd Font:size=12
terminal=alacritty
layer=overlay
lines=12
width=44

[colors]
background=0d0d0df2
text=c0c0c0ff
prompt=666666ff
placeholder=666666ff
input=e8e8e8ff
match=ffffffff
selection=262626ff
selection-text=ffffffff
selection-match=ffffffff
counter=666666ff
border=666666ff

[border]
width=1
radius=0
EOF

    # Event-driven: one line now, then one line per workspace event from the
    # niri IPC stream — no polling. Repo waybar (0.9.x) has no niri module;
    # when it ships one (upstream "niri/workspaces", waybar >= 0.11), this
    # script and the custom module can be retired as a simplification.
    put "$CFG/waybar/workspaces.sh" 755 <<'EOF'
#!/bin/bash
render() {
    niri msg --json workspaces \
        | jq -r 'sort_by(.idx) | map(if .is_focused then "[\(.idx)]" else " \(.idx) " end) | join("")'
}
render
niri msg --json event-stream | while IFS= read -r event; do
    case "$event" in
        *Workspace*) render ;;
    esac
done
EOF

    put "$CFG/waybar/config.jsonc" <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 22,
    "modules-left": ["custom/workspaces"],
    "modules-center": [],
    "modules-right": ["cpu", "memory", "network", "pulseaudio", "battery", "clock"],

    "custom/workspaces": {
        "exec": "~/.config/waybar/workspaces.sh",
        "restart-interval": 3,
        "format": "{}"
    },
    "cpu": { "format": "cpu {usage}%", "interval": 3 },
    "memory": { "format": "mem {percentage}%", "interval": 5 },
    "network": {
        "format-wifi": "wifi {signalStrength}%",
        "format-ethernet": "eth up",
        "format-disconnected": "net down"
    },
    "pulseaudio": {
        "format": "vol {volume}%",
        "format-muted": "vol mute"
    },
    "battery": {
        "format": "bat {capacity}%",
        "format-charging": "bat {capacity}%+",
        "states": { "critical": 15 }
    },
    "clock": {
        "format": "{:%a %d %b  %H:%M:%S}",
        "interval": 1,
        "tooltip": false
    }
}
EOF

    put "$CFG/waybar/style.css" <<'EOF'
* {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 13px;
    border: none;
    border-radius: 0;
    min-height: 0;
}

window#waybar {
    background: #0d0d0d;
    color: #c0c0c0;
}

#custom-workspaces {
    color: #ffffff;
    padding: 0 8px;
}

#cpu, #memory, #network, #pulseaudio, #battery, #clock {
    color: #c0c0c0;
    padding: 0 10px;
}

#battery.critical {
    color: #ff5555;
}
EOF

    put "$CFG/mako/config" <<'EOF'
font=JetBrainsMono Nerd Font 11
background-color=#0d0d0d
text-color=#c0c0c0
border-color=#666666
border-size=1
border-radius=0
padding=8
default-timeout=5000
layer=top

[urgency=high]
default-timeout=0
border-color=#ff5555
layer=overlay
EOF

    put "$CFG/swaylock/config" <<'EOF'
color=0d0d0d
font=JetBrainsMono Nerd Font
indicator-radius=80
indicator-thickness=4
inside-color=0d0d0d
ring-color=666666
ring-ver-color=c0c0c0
ring-wrong-color=b5626a
inside-ver-color=0d0d0d
inside-wrong-color=0d0d0d
key-hl-color=e8e8e8
text-color=c0c0c0
text-ver-color=c0c0c0
text-wrong-color=b5626a
line-uses-inside
ignore-empty-password
show-failed-attempts
EOF

    put "$CFG/yazi/yazi.toml" <<'EOF'
[mgr]
ratio = [ 1, 3, 4 ]
linemode = "none"
show_symlink = false
EOF

    put "$CFG/zellij/config.kdl" <<'EOF'
theme "mono"

themes {
    mono {
        fg "#c0c0c0"
        bg "#0d0d0d"
        black "#1a1a1a"
        red "#b5626a"
        green "#7f9f7f"
        yellow "#b0a06a"
        blue "#7a91a8"
        magenta "#9a86a8"
        cyan "#7fa8a0"
        white "#e8e8e8"
        orange "#b0a06a"
    }
}

simplified_ui true
pane_frames true
EOF

    put "$CFG/zellij/layouts/files.kdl" <<'EOF'
layout {
    tab name="files" focus=true {
        pane split_direction="vertical" {
            pane command="bash" {
                args "-ic" "y; exec bash"
            }
            pane
        }
    }
}
EOF
}

write_scripts() {
    put "$HOME/.local/bin/battwatch.sh" 755 <<'EOF'
#!/bin/bash
while true; do
    bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    stat=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
    if [ -n "$bat" ] && [ "$stat" = "Discharging" ] && [ "$bat" -le 15 ]; then
        notify-send -u critical "battery ${bat}%" "plug in"
        sleep 300
    fi
    sleep 60
done
EOF
}

# ------------------------------------------------------------- 6b. portals ---
write_portals_conf() {
    # niri ships /usr/share/xdg-desktop-portal/niri-portals.conf preferring
    # gnome;gtk. Portal config is whole-file precedence (user dir wins, no
    # per-key merge), so this copy restates niri's choices and adds one: the
    # file chooser goes to the GTK portal, because portal-gnome >= 47
    # delegates it to nautilus and Mint ships nemo instead. Diff against
    # niri's shipped file after a niri upgrade.
    put "$CFG/xdg-desktop-portal/niri-portals.conf" <<'EOF'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
org.freedesktop.impl.portal.FileChooser=gtk;
EOF
}

# --------------------------------------------------- 6c. MIME associations ---
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

# ---------------------------------------------------- 6d. prompt & colors ---
install_prompt() {
    if ! have starship; then
        log "installing starship prompt"
        fetch "$WORK/starship-install.sh" https://starship.rs/install.sh
        sh "$WORK/starship-install.sh" -y
    fi
    put "$CFG/starship.toml" <<'EOF'
add_newline = false
format = """
[┌─\\(](#5a6f5d)$time[\\)](#5a6f5d)$status[─\\(](#5a6f5d)$hostname[\\)─\\(](#5a6f5d)$directory[\\)](#5a6f5d)$git_branch
[└─](#5a6f5d)$character"""

[time]
disabled = false
format = "[$time]($style)"
time_format = "%H:%M"
style = "#666666"

[status]
disabled = false
format = "[─\\(](#5a6f5d)[$status]($style)[\\)](#5a6f5d)"
style = "#b5626a"

[hostname]
ssh_only = false
style = "#7f9f7f"
format = "[$hostname]($style)"

[directory]
style = "bold #93aabf"
format = "[$path]($style)"
truncation_length = 4
truncate_to_repo = false

[git_branch]
style = "#666666"
format = "[─\\[$branch\\]]($style)"

# U+2192, native to JetBrains Mono (the -> ligature glyph); U+276F renders
# as a thin quotation chevron in this family and reads as a stray paren.
[character]
success_symbol = "[→](#e8e8e8)"
error_symbol = "[→](#b5626a)"
EOF
}

configure_git() {
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
}

# --------------------------------------------------------- 7. shell setup ---
# ~/.bashrc is shared with the user, so put() (whole-file ownership) does not
# apply; only the marked block is owned and replaced.
write_shell() {
    local rc="$HOME/.bashrc"
    local body="$WORK/bashrc"
    [ -f "$rc" ] || touch "$rc"

    # Replace the block in place on every run (append-once would freeze the
    # first version forever, breaking the single-source-of-truth rule). The
    # awk pass also strips the two v6-era blocks, migrating old installs;
    # $(...) drops trailing newlines, so re-runs do not accumulate blanks.
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

# ------------------------------------------------------------ 8. desktop ---
apply_desktop_prefs() {
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark 2>/dev/null || true
    # GTK apps (file dialogs, portal choosers) follow these, completing the
    # one-typeface rule; dconf is shared across sessions, so a Cinnamon
    # login sees the same fonts until they are reset there.
    gsettings set org.gnome.desktop.interface font-name "'$MONO_FONT 10'" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface monospace-font-name "'$MONO_FONT 11'" 2>/dev/null || true
}

# ------------------------------------------------------------- 9. summary ---
portals_ok() {
    dpkg -s xdg-desktop-portal-gtk >/dev/null 2>&1 \
        && dpkg -s xdg-desktop-portal-gnome >/dev/null 2>&1
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
    summary_row "Xwayland-sat." "X11 bridge, auto-spawned by niri"       have xwayland-satellite
    summary_row "Portals"       "xdg-desktop-portal gtk + gnome"         portals_ok
    summary_row "Keyring"       "gnome-keyring (Secret portal)"          have gnome-keyring-daemon
    summary_row "Alacritty"     "terminal emulator"                      have alacritty
    summary_row "Fuzzel"        "application launcher"                   have fuzzel
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

# --------------------------------------------------------------- 10. main ---
main() {
    install_packages
    install_niri
    fix_units
    install_font
    install_binaries
    install_prompt
    configure_git
    set_default_apps
    write_niri
    write_terminal_stack
    write_scripts
    write_portals_conf
    write_shell
    apply_desktop_prefs

    niri validate
    log "ALL OK — niri config valid"
    print_summary
    log "wallpaper: put an image at ~/Pictures/wallpaper.jpg (optional)"
    log "log out of Cinnamon and choose the 'niri' session at the greeter"
}

# Run only when executed, not when sourced (keeps functions testable).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
