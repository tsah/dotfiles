#!/bin/bash

set -euo pipefail

log() {
    printf '%s\n' "$1"
}

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

if [ "$(uname -s)" != "Linux" ]; then
    fail "This script is intended for Linux hosts."
fi

if ! command -v sudo >/dev/null 2>&1; then
    fail "sudo is required."
fi

install_base_packages() {
    if command -v dnf >/dev/null 2>&1; then
        log "Installing base packages with dnf..."
        sudo dnf install -y \
            git \
            zsh \
            tmux \
            curl-minimal \
            wget \
            tar \
            gzip \
            unzip \
            xz \
            python3 \
            jq \
            xclip \
            procps-ng \
            util-linux-user
        return
    fi

    if command -v apt-get >/dev/null 2>&1; then
        log "Installing base packages with apt..."
        sudo apt-get update
        sudo apt-get install -y \
            git \
            fish \
            zsh \
            tmux \
            curl \
            wget \
            tar \
            gzip \
            unzip \
            xz-utils \
            python3 \
            jq \
            xclip \
            procps \
            util-linux
        return
    fi

    fail "Unsupported package manager. Expected dnf or apt-get."
}

github_release_asset_url() {
    local repo="$1"
    local release_ref="$2"
    local suffix="$3"

    python3 - "$repo" "$release_ref" "$suffix" <<'PY'
import json
import sys
import urllib.request

repo = sys.argv[1]
release_ref = sys.argv[2]
suffix = sys.argv[3]
url = f"https://api.github.com/repos/{repo}/releases/{release_ref}"
req = urllib.request.Request(
    url,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "dotfiles-install-server-packages"
    }
)

with urllib.request.urlopen(req, timeout=30) as response:
    data = json.load(response)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(suffix):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit(f"No release asset found for {repo} ({release_ref}) with suffix: {suffix}")
PY
}

github_asset_url() {
    local repo="$1"
    local suffix="$2"

    github_release_asset_url "$repo" "latest" "$suffix"
}

github_tag_asset_url() {
    local repo="$1"
    local tag="$2"
    local suffix="$3"

    github_release_asset_url "$repo" "tags/${tag}" "$suffix"
}

install_binary_from_tar() {
    local repo="$1"
    local suffix="$2"
    local binary_name="$3"
    local url=""
    local tmp_dir=""
    local archive_path=""
    local binary_path=""

    url="$(github_asset_url "$repo" "$suffix")"
    tmp_dir="$(mktemp -d)"
    archive_path="${tmp_dir}/archive"

    log "Installing ${binary_name} from ${repo}..."
    curl -fsSL "$url" -o "$archive_path"
    tar -xf "$archive_path" -C "$tmp_dir"

    binary_path="$(python3 - "$tmp_dir" "$binary_name" <<'PY'
import os
import sys

root = sys.argv[1]
binary_name = sys.argv[2]

for current_root, _, files in os.walk(root):
    if binary_name in files:
        print(os.path.join(current_root, binary_name))
        break
else:
    raise SystemExit(1)
PY
)" || fail "Could not locate ${binary_name} in downloaded archive for ${repo}."

    sudo install -m 755 "$binary_path" "/usr/local/bin/${binary_name}"
    rm -rf "$tmp_dir"
}

install_fish() {
    local suffix="$1"

    if command -v fish >/dev/null 2>&1; then
        log "fish is already installed."
        return
    fi

    install_binary_from_tar "fish-shell/fish-shell" "$suffix" "fish"
}

install_neovim() {
    local suffix="$1"
    local channel="${2:-nightly}"
    local url=""
    local tmp_dir=""
    local archive_path=""
    local extracted_dir=""

    case "$channel" in
        nightly)
            url="$(github_tag_asset_url "neovim/neovim" "nightly" "$suffix")"
            ;;
        stable)
            url="$(github_asset_url "neovim/neovim" "$suffix")"
            ;;
        *)
            fail "Unsupported NEOVIM_CHANNEL: ${channel} (use nightly or stable)"
            ;;
    esac

    tmp_dir="$(mktemp -d)"
    archive_path="${tmp_dir}/nvim.tar.gz"

    log "Installing neovim (${channel}) from neovim/neovim..."
    curl -fsSL "$url" -o "$archive_path"
    tar -xzf "$archive_path" -C "$tmp_dir"

    extracted_dir="$(python3 - "$tmp_dir" <<'PY'
import os
import sys

root = sys.argv[1]

for entry in os.listdir(root):
    candidate = os.path.join(root, entry)
    if os.path.isdir(candidate) and entry.startswith("nvim-linux-"):
        print(candidate)
        break
else:
    raise SystemExit(1)
PY
)" || fail "Could not locate extracted neovim directory."

    sudo rm -rf /opt/nvim
    sudo mv "$extracted_dir" /opt/nvim
    sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
    rm -rf "$tmp_dir"
}

install_fzf_tmux_wrapper() {
    local tmp_file=""
    tmp_file="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux" -o "$tmp_file"
    sudo install -m 755 "$tmp_file" /usr/local/bin/fzf-tmux
    rm -f "$tmp_file"
}

install_ghostty_terminfo() {
    if infocmp -x xterm-ghostty >/dev/null 2>&1; then
        log "xterm-ghostty terminfo is already installed."
        return
    fi

    if ! command -v tic >/dev/null 2>&1; then
        log "Skipping xterm-ghostty terminfo install (tic not found)."
        return
    fi

    log "Installing xterm-ghostty terminfo shim..."

    local src_file
    src_file="$(mktemp)"
    cat > "$src_file" <<'EOF'
xterm-ghostty|Ghostty terminal emulator,
    use=xterm-256color,
EOF

    mkdir -p "$HOME/.terminfo"
    tic -x -o "$HOME/.terminfo" "$src_file"
    rm -f "$src_file"
}

install_opencode() {
    if command -v opencode >/dev/null 2>&1; then
        log "OpenCode is already installed."
        return
    fi

    log "Installing OpenCode..."
    if curl -fsSL https://opencode.ai/install | bash; then
        log "OpenCode installation complete."
    else
        log "OpenCode installation skipped (installer unavailable)."
    fi
}

print_versions() {
    log ""
    log "Installed tool versions:"

    for cmd in fish zsh tmux nvim rg fd delta lazygit starship zoxide atuin jj sesh gh uv; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  - %s: %s\n' "$cmd" "$("$cmd" --version 2>/dev/null | head -1)"
        else
            printf '  - %s: not found\n' "$cmd"
        fi
    done

    if command -v opencode >/dev/null 2>&1; then
        printf '  - opencode: %s\n' "$(opencode --version 2>/dev/null | head -1)"
    else
        printf '  - opencode: not found\n'
    fi
}

install_base_packages

NEOVIM_CHANNEL="${NEOVIM_CHANNEL:-nightly}"

ARCH="$(uname -m)"

case "$ARCH" in
    aarch64|arm64)
        GH_SUFFIX="linux_arm64.tar.gz"
        UV_SUFFIX="aarch64-unknown-linux-gnu.tar.gz"
        FISH_SUFFIX="linux-aarch64.tar.xz"
        NEOVIM_SUFFIX="nvim-linux-arm64.tar.gz"
        FZF_SUFFIX="linux_arm64.tar.gz"
        RIPGREP_SUFFIX="aarch64-unknown-linux-gnu.tar.gz"
        FD_SUFFIX="aarch64-unknown-linux-musl.tar.gz"
        DELTA_SUFFIX="aarch64-unknown-linux-gnu.tar.gz"
        LAZYGIT_SUFFIX="linux_arm64.tar.gz"
        STARSHIP_SUFFIX="aarch64-unknown-linux-musl.tar.gz"
        ZOXIDE_SUFFIX="aarch64-unknown-linux-musl.tar.gz"
        ATUIN_SUFFIX="atuin-aarch64-unknown-linux-gnu.tar.gz"
        JJ_SUFFIX="aarch64-unknown-linux-musl.tar.gz"
        SESH_SUFFIX="sesh_Linux_arm64.tar.gz"
        ;;
    x86_64|amd64)
        GH_SUFFIX="linux_amd64.tar.gz"
        UV_SUFFIX="x86_64-unknown-linux-gnu.tar.gz"
        FISH_SUFFIX="linux-x86_64.tar.xz"
        NEOVIM_SUFFIX="nvim-linux-x86_64.tar.gz"
        FZF_SUFFIX="linux_amd64.tar.gz"
        RIPGREP_SUFFIX="x86_64-unknown-linux-musl.tar.gz"
        FD_SUFFIX="x86_64-unknown-linux-musl.tar.gz"
        DELTA_SUFFIX="x86_64-unknown-linux-gnu.tar.gz"
        LAZYGIT_SUFFIX="linux_x86_64.tar.gz"
        STARSHIP_SUFFIX="x86_64-unknown-linux-musl.tar.gz"
        ZOXIDE_SUFFIX="x86_64-unknown-linux-musl.tar.gz"
        ATUIN_SUFFIX="atuin-x86_64-unknown-linux-gnu.tar.gz"
        JJ_SUFFIX="x86_64-unknown-linux-musl.tar.gz"
        SESH_SUFFIX="sesh_Linux_x86_64.tar.gz"
        ;;
    *)
        fail "Unsupported architecture: ${ARCH}"
        ;;
esac

install_fish "$FISH_SUFFIX"
install_neovim "$NEOVIM_SUFFIX" "$NEOVIM_CHANNEL"
install_binary_from_tar "junegunn/fzf" "$FZF_SUFFIX" "fzf"
install_fzf_tmux_wrapper
install_binary_from_tar "BurntSushi/ripgrep" "$RIPGREP_SUFFIX" "rg"
install_binary_from_tar "sharkdp/fd" "$FD_SUFFIX" "fd"
install_binary_from_tar "dandavison/delta" "$DELTA_SUFFIX" "delta"
install_binary_from_tar "jesseduffield/lazygit" "$LAZYGIT_SUFFIX" "lazygit"
install_binary_from_tar "starship/starship" "$STARSHIP_SUFFIX" "starship"
install_binary_from_tar "ajeetdsouza/zoxide" "$ZOXIDE_SUFFIX" "zoxide"
install_binary_from_tar "atuinsh/atuin" "$ATUIN_SUFFIX" "atuin"
install_binary_from_tar "martinvonz/jj" "$JJ_SUFFIX" "jj"
install_binary_from_tar "joshmedeski/sesh" "$SESH_SUFFIX" "sesh"
install_binary_from_tar "cli/cli" "$GH_SUFFIX" "gh"
install_binary_from_tar "astral-sh/uv" "$UV_SUFFIX" "uv"
install_ghostty_terminfo

install_opencode
print_versions

log ""
log "Package installation complete."
