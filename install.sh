#!/usr/bin/env bash
set -e

# === Configuration ===
REPO_URL="https://github.com/Leriart/NothingLess.git"
INSTALL_PATH="$HOME/.local/src/nothingless"
AXCTL_REPO="https://github.com/leriart/axctl.c.git"
AXCTL_PATH="$HOME/.local/src/axctl.c"
BIN_DIR="/usr/local/bin"
QUICKSHELL_REPO="https://git.outfoxxed.me/outfoxxed/quickshell"

# === Helpers ===
GREEN='\033[0;32m' BLUE='\033[0;34m' YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'
log_info() { echo -e "${BLUE}ℹ  $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✔  $1${NC}" >&2; }
log_warn() { echo -e "${YELLOW}⚠  $1${NC}" >&2; }
log_error() { echo -e "${RED}✖  $1${NC}" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_theme() { [[ -d "/usr/share/themes/$1" ]] || [[ -d "$HOME/.themes/$1" ]] || [[ -d "/usr/share/themes/${1}-dark" ]]; }
has_font() { fc-list 2>/dev/null | grep -qi "$1"; }

[[ "$EUID" -eq 0 ]] && {
  log_error "Do not run as root. Use sudo where needed."
  exit 1
}

# === Distro Detection ===
detect_distro() {
  [[ -f /etc/NIXOS ]] && echo "nixos" && return
  has_cmd pacman && echo "arch" && return
  has_cmd dnf && echo "fedora" && return
  has_cmd apt && echo "debian" && return
  echo "unknown"
}

DISTRO=$(detect_distro)
log_info "Detected: $DISTRO"

# === Package Filtering ===
declare -A BINARY_CHECK=(
  ["matugen"]="matugen"
  ["quickshell"]="qs"
  ["kitty"]="kitty"
  ["tmux"]="tmux"
  ["fuzzel"]="fuzzel"
  ["brightnessctl"]="brightnessctl"
  ["ddcutil"]="ddcutil"
  ["grim"]="grim"
  ["slurp"]="slurp"
  ["jq"]="jq"
  ["playerctl"]="playerctl"
  ["wtype"]="wtype"
  ["gradia"]="gradia"
  ["pipx"]="pipx"
  ["python-pipx"]="pipx"
  ["zenity"]="zenity"
  ["gpu-screen-recorder"]="gpu-screen-recorder"
)

declare -A THEME_CHECK=(
  ["adw-gtk-theme"]="adw-gtk3"
  ["adw-gtk3-theme"]="adw-gtk3"
)

declare -A FONT_CHECK=(
  ["ttf-phosphor-icons"]="Phosphor"
  ["ttf-ndot"]="Ndot"
)

filter_packages() {
  local pkgs=("$@")
  local needed=()

  for pkg in "${pkgs[@]}"; do
    local skip=0

    if [[ -n "${BINARY_CHECK[$pkg]}" ]] && has_cmd "${BINARY_CHECK[$pkg]}"; then
      log_info "Skipping $pkg (${BINARY_CHECK[$pkg]} found)"
      skip=1
    elif [[ -n "${THEME_CHECK[$pkg]}" ]] && has_theme "${THEME_CHECK[$pkg]}"; then
      log_info "Skipping $pkg (theme ${THEME_CHECK[$pkg]} found)"
      skip=1
    elif [[ -n "${FONT_CHECK[$pkg]}" ]] && has_font "${FONT_CHECK[$pkg]}"; then
      log_info "Skipping $pkg (font ${FONT_CHECK[$pkg]} found)"
      skip=1
    fi

    [[ $skip -eq 0 ]] && needed+=("$pkg")
  done

  echo "${needed[@]}"
}

# === Dependency Installation ===
install_dependencies() {
  case "$DISTRO" in
  nixos)
    local FLAKE_URI="${1:-github:Leriart/NothingLess}"
    nix profile list | grep -q "ddcutil" && nix profile remove ddcutil 2>/dev/null || true

    if nix profile list | grep -q "NothingLess"; then
      log_info "Updating NothingLess..."
      nix profile upgrade NothingLess --refresh --impure
    else
      log_info "Installing NothingLess..."
      nix profile add "$FLAKE_URI" --impure
    fi
    ;;

  fedora)
    log_info "Enabling COPR repositories..."
    sudo dnf install -y --best --allowerasing --setopt=install_weak_deps=False dnf-plugins-core
    yes | sudo dnf copr enable errornointernet/quickshell
    yes | sudo dnf copr enable solopasha/hyprland
    yes | sudo dnf copr enable zirconium/packages
    yes | sudo dnf copr enable iucar/cran

    local PKGS=(
      kitty tmux fuzzel network-manager-applet blueman
      pipewire wireplumber easyeffects playerctl
      qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtsvg qt6-qttools
      qt6-qtimageformats qt6-qtmultimedia qt6-qtshadertools
      kf6-syntax-highlighting kf6-breeze-icons hicolor-icon-theme
      brightnessctl ddcutil fontconfig grim slurp ImageMagick jq sqlite upower
      wl-clipboard wlsunset wtype zbar glib2 pipx zenity power-profiles-daemon
      python3.12 libnotify flatpak
      tesseract tesseract-langpack-eng tesseract-langpack-spa tesseract-langpack-jpn
      tesseract-langpack-chi_sim tesseract-langpack-chi_tra tesseract-langpack-kor tesseract-langpack-lat
      google-roboto-fonts google-roboto-mono-fonts dejavu-sans-fonts liberation-fonts
      google-noto-fonts-common google-noto-cjk-fonts google-noto-emoji-fonts
      translate-shell songrec libqalculate
      uxplay gstreamer1-plugins-bad-free gstreamer1-plugin-libav
      gnome-network-displays
    )

    log_info "Installing dependencies..."
    # shellcheck disable=SC2046
    sudo dnf install -y --best --allowerasing --setopt=install_weak_deps=False $(filter_packages "${PKGS[@]}")

    log_info "Installing Gradia (Flatpak)..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub be.alexandervanhee.gradia 2>/dev/null || true

    install_phosphor_fonts
    install_ndot_font
    install_color_presets
    install_material_symbols_font
    ;;

  arch)
    if ! has_cmd git || ! has_cmd makepkg; then
      log_info "Installing git and base-devel..."
      sudo pacman -S --needed --noconfirm git base-devel
    fi

    AUR_HELPER=""
    if has_cmd yay; then
      AUR_HELPER="yay"
    elif has_cmd paru; then
      AUR_HELPER="paru"
    else
      log_info "Installing yay-bin..."
      local YAY_TMP
      YAY_TMP="$(mktemp -d)"
      git clone "https://aur.archlinux.org/yay-bin.git" "$YAY_TMP"
      (cd "$YAY_TMP" && makepkg -si --noconfirm)
      rm -rf "$YAY_TMP"
      AUR_HELPER="yay"
    fi

    local PKGS=(
      kitty tmux fuzzel network-manager-applet blueman
      pipewire wireplumber pavucontrol easyeffects ffmpeg x264 playerctl
      qt6-base qt6-declarative qt6-wayland qt6-svg qt6-tools qt6-imageformats qt6-multimedia qt6-shadertools
      libwebp libavif syntax-highlighting breeze-icons hicolor-icon-theme
      brightnessctl ddcutil fontconfig grim slurp imagemagick jq sqlite upower
      wl-clipboard wlsunset wtype zbar glib2 python-pipx zenity inetutils power-profiles-daemon
      python312 libnotify
      tesseract tesseract-data-eng tesseract-data-spa tesseract-data-jpn
      tesseract-data-chi_sim tesseract-data-chi_tra tesseract-data-kor tesseract-data-lat
      ttf-roboto ttf-roboto-mono ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji
      ttf-nerd-fonts-symbols
      quickshell ttf-phosphor-icons ttf-league-gothic adw-gtk-theme
      translate-shell songrec libqalculate
      json-c wayland
      uxplay gst-plugins-bad gst-libav
      gnome-network-displays miraclecast-git
    )

    log_info "Installing dependencies with $AUR_HELPER..."
    local FILTERED
    # shellcheck disable=SC2207
    FILTERED=($(filter_packages "${PKGS[@]}"))

    if [[ ${#FILTERED[@]} -gt 0 ]]; then
      $AUR_HELPER -S --needed --noconfirm "${FILTERED[@]}"
    else
      log_info "All packages already installed"
    fi
    install_color_presets

    install_ndot_font
    install_material_symbols_font
    ;;

  *)
    log_error "Unsupported distribution: $DISTRO"
    log_warn "Please install dependencies manually (see nix/packages/)."
    ;;
  esac
}

install_phosphor_fonts() {
  has_font "Phosphor" && return

  log_info "Installing Phosphor Icons..."
  local VERSION="2.1.2"
  local TEMP_DIR FONT_DIR
  TEMP_DIR="$(mktemp -d)"
  FONT_DIR="$HOME/.local/share/fonts/phosphor"

  curl -sL "https://github.com/phosphor-icons/web/archive/refs/tags/v${VERSION}.zip" -o "$TEMP_DIR/phosphor.zip"
  unzip -q "$TEMP_DIR/phosphor.zip" -d "$TEMP_DIR"
  mkdir -p "$FONT_DIR"
  find "$TEMP_DIR" -name "*.ttf" -exec cp {} "$FONT_DIR/" \;
  rm -rf "$TEMP_DIR"
  fc-cache -f "$FONT_DIR"
  log_success "Phosphor Icons installed"
}

install_color_presets() {
    log_info "Installing Nothing color theme..."
    local COLOR_DIR="$HOME/.config/nothingless/colors/Nothing"
    mkdir -p "$COLOR_DIR"
    
    local SRC_DIR="$INSTALL_PATH/assets/colors/Nothing"
    if [[ -d "$SRC_DIR" ]]; then
        cp -rn "$SRC_DIR"/* "$COLOR_DIR/" 2>/dev/null || true
        log_success "Nothing color theme installed"
    else
        log_warn "Nothing color theme not found in repo."
    fi
}

install_ndot_font() {
  has_font "Ndot" && return

  log_info "Installing Ndot font..."
  local FONT_DIR="$HOME/.local/share/fonts/ndot"
  mkdir -p "$FONT_DIR"

  local NDOT_SRC="$INSTALL_PATH/assets/fonts"
  if [[ -f "$NDOT_SRC/Ndot-57-Aligned.ttf" ]]; then
    cp "$NDOT_SRC/Ndot-57-Aligned.ttf" "$FONT_DIR/"
  else
    # Try from the script's location
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/assets/fonts/Ndot-57-Aligned.ttf" ]]; then
      cp "$SCRIPT_DIR/assets/fonts/Ndot-57-Aligned.ttf" "$FONT_DIR/"
    else
      log_warn "Ndot font not found in repo. Skipping."
      return
    fi
  fi

  fc-cache -f "$FONT_DIR"
  log_success "Ndot font installed"
}

install_material_symbols_font() {
  has_font "Material Symbols" && return

  log_info "Installing Material Symbols Variable font..."
  local FONT_DIR="$HOME/.local/share/fonts/material-symbols"
  mkdir -p "$FONT_DIR"

  local SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ -f "$SRC_DIR/assets/fonts/MaterialSymbolsRounded-Variable.ttf" ]]; then
    cp "$SRC_DIR/assets/fonts/MaterialSymbolsRounded-Variable.ttf" "$FONT_DIR/"
    log_success "Material Symbols font installed from repo"
  elif has_cmd pacman; then
    log_info "Material Symbols font not found in repo assets. Skipping."
    return
  fi

  fc-cache -f "$FONT_DIR" 2>/dev/null || true
}

# === Migration ===
migrate_old_paths() {
  log_info "Checking for old paths..."

  local OLD_CONFIG="$HOME/.config/nothingless"
  if [[ ! -d "$OLD_CONFIG" ]]; then
    mkdir -p "$OLD_CONFIG/config"

    # Copy default configs from the install path
    if [[ -d "$INSTALL_PATH/config/defaults" ]]; then
      cp -r "$INSTALL_PATH/config/defaults/"* "$OLD_CONFIG/config/" 2>/dev/null || true
    fi
  fi
}

# === Repository Setup ===
setup_repo() {
  [[ "$DISTRO" == "nixos" ]] && return

  if [[ ! -d "$INSTALL_PATH" ]]; then
    log_info "Cloning NothingLess to $INSTALL_PATH..."
    mkdir -p "$(dirname "$INSTALL_PATH")"
    git clone "$REPO_URL" "$INSTALL_PATH"
    return
  fi

  if [[ ! -d "$INSTALL_PATH/.git" ]]; then
    log_warn "$INSTALL_PATH exists but is not a git repository."
    log_info "Re-initializing repository..."
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    find "$INSTALL_PATH" -mindepth 1 -maxdepth 1 -exec mv -t "$TMP_DIR" {} +
    rm -rf "$INSTALL_PATH"
    git clone "$REPO_URL" "$INSTALL_PATH"
    log_info "Restoring files from old directory..."
    cp -rn "$TMP_DIR"/* "$INSTALL_PATH/" 2>/dev/null || true
    rm -rf "$TMP_DIR"
  fi

  log_info "Checking repository status..."
  git -C "$INSTALL_PATH" fetch origin --depth=1 2>/dev/null || true

  local BRANCH
  BRANCH=$(git -C "$INSTALL_PATH" rev-parse --abbrev-ref HEAD)

  if [[ "$BRANCH" != "main" ]]; then
    log_warn "On branch '$BRANCH', not 'main'. Skipping update."
    return
  fi

  # Compare commit hashes — skip if already up to date
  local REMOTE_HASH LOCAL_HASH
  REMOTE_HASH=$(git -C "$INSTALL_PATH" rev-parse origin/main 2>/dev/null || echo "")
  LOCAL_HASH=$(git -C "$INSTALL_PATH" rev-parse HEAD 2>/dev/null || echo "")

  if [[ -n "$REMOTE_HASH" && "$REMOTE_HASH" == "$LOCAL_HASH" ]]; then
    log_info "NothingLess already up to date ($(echo "$LOCAL_HASH" | cut -c1-8))"
    return
  fi

  local HAS_CHANGES=0
  [[ -n "$(git -C "$INSTALL_PATH" status --porcelain)" ]] && HAS_CHANGES=1
  [[ -n "$(git -C "$INSTALL_PATH" log origin/main..HEAD)" ]] && HAS_CHANGES=1

  if [[ "$HAS_CHANGES" -eq 1 ]]; then
    echo -e "${YELLOW}⚠  Local changes detected on 'main'.${NC}"
    echo -e "${RED}This will DISCARD all local changes.${NC}"
    read -r -p "Continue? [y/N] " response </dev/tty
    [[ ! "$response" =~ ^[Yy]$ ]] && {
      log_warn "Update aborted."
      exit 0
    }
  fi

  log_info "Syncing with remote..."
  git -C "$INSTALL_PATH" reset --hard origin/main
}

# === Quickshell Build ===
install_quickshell() {
  [[ "$DISTRO" == "nixos" || "$DISTRO" == "fedora" ]] && return

  if has_cmd qs; then
    # Check version compatibility: quickshell must be built against same Qt as system
    local QS_QT
    QS_QT=$(ldd "$(which qs)" 2>/dev/null | grep -oP 'libQt6Core\.so\.\K[\d.]+' | head -1 || echo "")
    local SYS_QT
    SYS_QT=$(pacman -Q qt6-base 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "")
    
    if [ -n "$QS_QT" ] && [ -n "$SYS_QT" ] && [ "$QS_QT" = "$SYS_QT" ]; then
      log_info "Quickshell already installed (Qt $QS_QT, compatible with system)"
      return
    elif [ "$DISTRO" = "arch" ]; then
      log_warn "Quickshell Qt ($QS_QT) differs from system Qt ($SYS_QT) — rebuilding"
      log_info "Reinstalling quickshell from AUR..."
      yay -S --noconfirm quickshell 2>/dev/null || \
        paru -S --noconfirm quickshell 2>/dev/null || \
        log_warn "Could not auto-rebuild quickshell; continuing anyway"
      return
    fi
  fi

  # On Arch, install from AUR rather than building from source
  if [ "$DISTRO" = "arch" ]; then
    log_info "Installing quickshell from AUR..."
    if has_cmd yay; then
      yay -S --noconfirm quickshell
    elif has_cmd paru; then
      paru -S --noconfirm quickshell
    else
      log_warn "No AUR helper found, building from source..."
      build_quickshell_from_source
    fi
    return
  fi

  build_quickshell_from_source
}

build_quickshell_from_source() {
  has_cmd qs && { log_info "Quickshell already installed"; return; }
  log_info "Building Quickshell from source..."
  local BUILD_DIR
  BUILD_DIR="$(mktemp -d)"
  git clone --recursive "$QUICKSHELL_REPO" "$BUILD_DIR"
  (
    cd "$BUILD_DIR"
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
    cmake --build build
    cmake --install build
  )
  rm -rf "$BUILD_DIR"
  log_success "Quickshell installed to ~/.local/bin/qs"
}

# === Python Tools ===
install_python_tools() {
  [[ "$DISTRO" == "nixos" ]] && return
  has_cmd pipx || {
    log_warn "pipx not found, skipping Python tools"
    return
  }

  log_info "Installing Python tools..."
  pipx ensurepath 2>/dev/null || true
}

# === Service Configuration ===
configure_services() {
  [[ "$DISTRO" == "nixos" ]] && return

  if has_cmd systemctl; then
    log_info "Configuring systemd services..."

    if systemctl is-enabled --quiet iwd 2>/dev/null || systemctl is-active --quiet iwd 2>/dev/null; then
      log_warn "Disabling iwd (conflicts with NetworkManager)..."
      sudo systemctl stop iwd
      sudo systemctl disable iwd
    fi

    systemctl is-enabled --quiet NetworkManager 2>/dev/null || {
      log_info "Enabling NetworkManager..."
      sudo systemctl enable --now NetworkManager
    }

    systemctl is-enabled --quiet bluetooth 2>/dev/null || {
      log_info "Enabling Bluetooth..."
      sudo systemctl enable --now bluetooth
    }

  elif has_cmd rc-service; then
    log_info "Configuring OpenRC services..."
    sudo rc-update add NetworkManager default 2>/dev/null || true
    sudo rc-service NetworkManager start 2>/dev/null || true
    sudo rc-update add bluetooth default 2>/dev/null || true
    sudo rc-service bluetooth start 2>/dev/null || true

  elif has_cmd sv; then
    log_info "Configuring runit services..."
    local SV_DIR="/var/service"
    [[ -d "/etc/sv/NetworkManager" && ! -L "$SV_DIR/NetworkManager" ]] && sudo ln -s /etc/sv/NetworkManager "$SV_DIR/"
    [[ -d "/etc/sv/bluetooth" && ! -L "$SV_DIR/bluetooth" ]] && sudo ln -s /etc/sv/bluetooth "$SV_DIR/"

  else
    log_warn "Unknown init system. Please enable NetworkManager and Bluetooth manually."
  fi
}

# === Launcher Setup ===
setup_launcher() {
  [[ "$DISTRO" == "nixos" ]] && return

  [[ -f "$HOME/.local/bin/nothingless" ]] && rm -f "$HOME/.local/bin/nothingless"

  sudo mkdir -p "$BIN_DIR"
  local LAUNCHER="$BIN_DIR/nothingless"

  log_info "Creating launcher at $LAUNCHER..."
  sudo tee "$LAUNCHER" >/dev/null <<-EOF
		#!/usr/bin/env bash
		# Prepend paths only if not already present (avoids ARG_MAX issues)
		case ":\$PATH:" in
		  *:"$HOME/.local/bin":*) ;;
		  *) export PATH="$HOME/.local/bin:\$PATH" ;;
		esac
		case ":\$QML2_IMPORT_PATH:" in
		  *:"$HOME/.local/lib/qml":*) ;;
		  *) export QML2_IMPORT_PATH="$HOME/.local/lib/qml:\$QML2_IMPORT_PATH" ;;
		esac
		export QML_IMPORT_PATH="\$QML2_IMPORT_PATH"
		exec "$INSTALL_PATH/cli.sh" "\$@"
	EOF
  sudo chmod +x "$LAUNCHER"
  log_success "Launcher created"

  # Symlink companion scripts for FPS monitoring and window resizing
  local script_src script_dst
  for script in nothing-fps nothingless-resize; do
    script_src="$INSTALL_PATH/scripts/$script"
    script_dst="$BIN_DIR/$script"
    if [[ -f "$script_src" ]]; then
      sudo ln -sf "$script_src" "$script_dst"
      log_info "  Linked $script → $script_dst"
    fi
  done
}

# === Axctl Installation ===
install_axctl() {
  [[ "$DISTRO" == "nixos" ]] && return

  # Ensure repo exists
  if [[ ! -d "$AXCTL_PATH" ]]; then
    log_info "Cloning axctl.c to $AXCTL_PATH..."
    mkdir -p "$(dirname "$AXCTL_PATH")"
    git clone "$AXCTL_REPO" "$AXCTL_PATH"
  fi

  # Fetch latest and get remote commit hash
  git -C "$AXCTL_PATH" fetch origin --depth=1 2>/dev/null || true
  local remote_commit
  remote_commit="$(git -C "$AXCTL_PATH" rev-parse origin/main 2>/dev/null || echo "")"
  local local_commit
  local_commit="$(git -C "$AXCTL_PATH" rev-parse HEAD 2>/dev/null || echo "")"

  log_info "Building axctl.c ($(echo "$remote_commit" | cut -c1-8))..."

  # Update to remote
  git -C "$AXCTL_PATH" reset --hard "$remote_commit" 2>/dev/null || git -C "$AXCTL_PATH" reset --hard origin/main

  log_info "Building axctl.c ($(echo "$remote_commit" | cut -c1-8))..."
  (cd "$AXCTL_PATH" && make clean && make) || {
    log_error "axctl.c build failed"
    return
  }

  # Kill any running daemon that may hold the binary busy
  # Use SIGKILL (-9) because SIGTERM may not release the file immediately
  log_info "Stopping axctl daemon..."
  sudo pkill -9 -f "axctl.*daemon" 2>/dev/null || true
  sudo pkill -9 -f "axctl.*subscribe" 2>/dev/null || true
  # Also try fuser as a fallback if pkill missed something
  local AXCTL_PID
  AXCTL_PID="$(fuser "$BIN_DIR/axctl" 2>/dev/null | head -1)"
  if [[ -n "$AXCTL_PID" ]]; then
    sudo kill -9 "$AXCTL_PID" 2>/dev/null || true
  fi
  sleep 1
  # Verify the binary is free
  if fuser "$BIN_DIR/axctl" >/dev/null 2>&1; then
    log_warn "axctl binary still busy, waiting..."
    sleep 2
  fi

  log_info "Installing axctl to $BIN_DIR/axctl..."
  sudo install -Dm755 "$AXCTL_PATH/axctl" "$BIN_DIR/axctl"
  log_success "axctl.c installed ($(/usr/local/bin/axctl --version 2>/dev/null || echo "unknown"))"

  log_info "Restarting axctl daemon..."
  (axctl -c "$HOME/.local/share/nothingless/axctl.toml" daemon >/dev/null 2>&1 &)
}

# === Udev Rule for Battery Charge Limit ===
setup_udev_rules() {
  [[ "$DISTRO" == "nixos" ]] && return 0

  local UDEV_RULE="/etc/udev/rules.d/99-nothingless-charge-threshold.rules"
  local RULE_CONTENT='SUBSYSTEM=="power_supply", ATTR{charge_control_end_threshold}="80"'

  if [[ -f "$UDEV_RULE" ]] && grep -qF "99-nothingless-charge-threshold" "$UDEV_RULE"; then
    log_info "udev rule for charge threshold already present"
    return 0
  fi

  log_info "Installing udev rule for battery charge control..."
  echo "$RULE_CONTENT" | sudo tee "$UDEV_RULE" >/dev/null
  sudo udevadm control --reload-rules 2>/dev/null || true
  sudo udevadm trigger 2>/dev/null || true
  log_success "udev rule installed at $UDEV_RULE"
}

# === Main ===
migrate_old_paths
install_dependencies "$1"
setup_repo
install_axctl
install_quickshell
install_ndot_font
install_python_tools
configure_services
setup_launcher
setup_udev_rules

echo ""
log_success "Installation complete!"
[[ "$DISTRO" != "nixos" ]] && echo -e "Run ${GREEN}nothingless${NC} to start."
