#!/usr/bin/env bash

# Author: Aris Arjuna Noorsanto <exe.opcode@gmail.com>

# AI / AGI / AIM Unified Processing Tool
# Termux/Proot-Distro compatible with Ollama gemma3:1b

set -eu
IFS=$'\n\t'

# -----------------------
# CONFIG
# -----------------------
HOME_ROOT="/home/loop/CODERS-AI"
BACKUP_DIR="$HOME_ROOT/.ai_backups"
mkdir -p "$BACKUP_DIR"

UNIVERSAL_LAW=$(cat <<'EOF'
:bof:
redo complete layout and design an advanced symetrics to proximity accordance for dedicated info-quota alignments, which grant a better adjustment for leading besides subliminal range compliance promisings, that affair any competing content relations into a cognitive intuitition guidance comparison between space and gap implies, that are suggesting the viewer a subcoordinated experience alongside repetitive tasks and stoic context sortings, all cooperational aligned to timed subjects of importance accordingly to random capacity within builds of data statements, that prognose the grid reliability of a mockup as given optically acknowledged for a more robust but also as attractive rulership into golden-ratio item handling
:eof:
EOF
)

# -----------------------
# HELPER LOGGING
# -----------------------
log_info()    { printf '\033[34m[*] %s\033[0m\n' "$*"; }
log_success() { printf '\033[32m[+] %s\033[0m\n' "$*"; }
log_warn()    { printf '\033[33m[!] %s\033[0m\n' "$*"; }
log_error()   { printf '\033[31m[-] %s\033[0m\n' "$*"; }

backup_file() {
    local file="$1"
    [ -f "$file" ] || return
    local ts
    ts=$(date +%Y%m%d%H%M%S)
    cp "$file" "$BACKUP_DIR/$(basename "$file").$ts.bak"
    log_info "Backup created for $file -> $BACKUP_DIR"
}

fetch_url() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -sL "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$url"
    else
        log_error "curl or wget required to fetch URLs"
    fi
}

get_prompt() {
    local input="$1"
    case "$input" in
        http://*|https://*) fetch_url "$input" ;;
        *) [ -f "$input" ] && cat "$input" || echo "$input" ;;
    esac
}

# -----------------------
# HTML/JS/DOM ENHANCEMENT
# -----------------------
html_enhance() {
    local file="$1"
    [ -f "$file" ] || { log_warn "HTML file not found: $file"; return; }
    backup_file "$file"
    log_info "Enhancing HTML/JS/DOM for $file..."

    local content
    content=$(<"$file")

    # Inject simple neon theme if <head> exists
    if [[ "$content" == *"<head>"* && "$content" != *"--main-bg"* ]]; then
        content=$(echo "$content" | sed -E "s|<head>|<head><style>:root{--main-bg:#8B0000;--main-fg:#fff;--btn-color:#ff00ff;--link-color:#ffff00;}</style>|")
    fi

    # Add AI comment to JS functions (simple regex)
    if command -v perl >/dev/null 2>&1; then
        content=$(echo "$content" | perl -0777 -pe 's|function\s+([a-zA-Z0-9_]+)\s*\((.*?)\)\s*\{(?!\s*\/\*\s*AI:)|function \1(\2) { /* AI: optimize this function */ |g')
    fi

    # Event listener monitoring
    content=$(echo "$content" | sed -E "s|\.addEventListener\((['\"])(.*?)\1,(.*)\)|.addEventListener(\1\2\1, /* AI: monitored */\3)|g")

    # Replace div.section with semantic <section>
    content=$(echo "$content" | sed -E 's|<div class="section"|<section class="section"|g; s|</div><!-- .section -->|</section>|g')

    # Accessibility roles
    content=$(echo "$content" | sed -E 's|<nav|<nav role="navigation"|g; s|<header|<header role="banner"|g; s|<main|<main role="main"|g; s|<footer|<footer role="contentinfo"|g')

    echo "$content" > "$file.processed"
    log_success "Enhanced HTML saved as $file.processed"
}

# -----------------------
# OLLAMA GEMMA3:1B PROMPT
# -----------------------
ollama_run() {
    local prompt="$1"
    log_info "Running prompt on THE CUBE..."
    pkill -f 'ollama serve' 2>/dev/null || true
    ollama serve &
    sleep 2
    echo "$prompt" | ollama run cube:latest
}

# -----------------------
# AI MODES
# -----------------------
mode_file() { for f in "$@"; do html_enhance "$f"; done; }
mode_script() { log_info "Processing script content..."; }
mode_batch() { local pattern="$1"; shift; for f in $pattern; do html_enhance "$f"; done; }
mode_env() { log_info "Scanning environment..."; env | sort; df -h; ls -la "$HOME_ROOT"; ls -la /etc; }
mode_pipeline() { for f in "$@"; do html_enhance "$f"; done; }

# -----------------------
# AGI MODES
# -----------------------
agi_watch() { local folder="$1"; local pattern="${2:-*}"; log_info "Watching $folder for changes matching $pattern"; command -v inotifywait >/dev/null 2>&1 || { log_error "Install inotify-tools"; return; }; inotifywait -m -r -e modify,create,move --format '%w%f' "$folder" | while read file; do case "$file" in $pattern) log_info "Detected change: $file"; html_enhance "$file"; esac; done; }
agi_screenshot() { log_info "Screenshot disabled in Termux/Proot"; }

# -----------------------
# .bashrc ADAPTATION
# -----------------------
adapt_bashrc() {
    local bashrc="$HOME_ROOT/.bashrc"
    backup_file "$bashrc"
    log_info "Rewriting .bashrc with AI/AGI/AIM configuration..."
    cat > "$bashrc" <<'EOF'
# Auto-generated .bashrc by ~/bin/ai
export PATH="$HOME/bin:$PATH"
alias ai='~/bin/ai'
EOF
    log_success ".bashrc rewritten successfully."
    . "$bashrc"
}

# -----------------------
# INSTALLER MODE
# -----------------------
mode_init() {
    log_info "Installing AI/AGI/AIM tool..."
    mkdir -p "$HOME_ROOT/bin"
    cp -f "$0" "$HOME_ROOT/bin/ai"
    chmod +x "$HOME_ROOT/bin/ai"
    log_success "Script installed at $HOME_ROOT/bin/ai"
    adapt_bashrc
}

# -----------------------
# MAIN ARGUMENT PARSING
# -----------------------
if [ $# -eq 0 ]; then
    log_info "Usage: $0 <mode> [files/patterns] [prompt]"
    exit 0
fi

case "$1" in
    init) shift; mode_init "$@" ;;
    -) shift; mode_file "$@" ;;
    +) shift; mode_script "$@" ;;
    \*) shift; mode_batch "$@" ;;
    .) shift; mode_env "$@" ;;
    :) shift; IFS=':' read -r -a files <<< "$1"; mode_pipeline "${files[@]}" ;;
    agi) shift; case "$1" in +|~) shift; agi_watch "$@" ;; -) shift; agi_screenshot "$@" ;; *) shift; agi_watch "$@" ;; esac ;;
    *) PROMPT=$(get_prompt "$*"); ollama_run "$PROMPT" ;;
esac
