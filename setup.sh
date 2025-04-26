#!/bin/bash
#
# Ubuntu System Setup Script
# 
# This script automates the installation of commonly used tools on Ubuntu 24.10+.
# It is designed to be idempotent and maintainable, allowing easy addition and 
# removal of tools.
#
# Copyright 2023 Your Name
# License: MIT
#
# Usage:
#   ./setup.sh              Run interactively
#   ./setup.sh --auto       Run in automatic mode (no prompts)
#   ./setup.sh --help       Show usage information
#   
# Examples:
#   sudo ./setup.sh                     Regular installation with prompts
#   sudo ./setup.sh --auto              Fully automated installation 
#   wget -qO- URL | sudo bash -s -- --auto   Remote execution

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Constants
AUTO_MODE="false"
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/${SCRIPT_NAME%.sh}_$(date +%Y%m%d_%H%M%S).log"
readonly LOG_MARKER=">>>"
readonly DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
readonly DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
readonly VSCODE_KEYRING="/etc/apt/keyrings/packages.microsoft.gpg"
readonly VSCODE_SOURCE_LIST="/etc/apt/sources.list.d/vscode.list"
readonly PODMAN_VERSION="v5.4.2"
readonly CRUN_VERSION="1.21"
readonly FLATHUB_REPO="https://flathub.org/repo/flathub.flatpakrepo"
readonly PYENV_INSTALLER="https://pyenv.run"
readonly MISE_INSTALLER="https://mise.run"
readonly CONTAINERS_REGISTRIES_CONF="/etc/containers/registries.conf"
readonly JETBRAINS_INSTALL_DIR="/home/$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")/.local/share/JetBrains/Toolbox/bin"
readonly JETBRAINS_SYMLINK_DIR="/home/$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")/.local/bin"

# Package arrays - customize these according to your needs
readonly SYSTEM_PACKAGES=(
 "apt-transport-https"
 "ca-certificates"
 "curl"
 "gnupg"
 "lsb-release"
 "software-properties-common"
 "libfuse2"  # Required for AppImage support and JetBrains Toolbox
 "wget"      # Required for several installations
)

readonly DEV_PACKAGES=(
 "build-essential"
 "git"
 "python3" 
 "python3-pip"
 "libreadline-dev"
)

# Pyenv build dependencies
readonly PYENV_DEPENDENCIES=(
 "build-essential"
 "libssl-dev"
 "zlib1g-dev"
 "libbz2-dev"
 "libreadline-dev"
 "libsqlite3-dev"
 "curl"
 "git"
 "libncursesw5-dev"
 "xz-utils"
 "tk-dev"
 "libxml2-dev"
 "libxmlsec1-dev"
 "libffi-dev"
 "liblzma-dev"
)

readonly UTIL_PACKAGES=(
 "htop"
 "tmux"
 "tree"
 "unzip"
 "fish"
)

# List of Snap apps to install
readonly SNAP_APPS=(
  #  "postman"  # API Development Environment
  #  "obs-studio" # OBS Studio Installation
  # "spotify"  # Music Streaming
  # Add other desired snap packages here
  # "code"   # Example: VS Code (consider conflicts if installing via .deb too)
)

# Flatpak packages
readonly FLATPAK_PACKAGES=(
 "flatpak"
 "gnome-software-plugin-flatpak"
)

# list of Flatpak apps to install
readonly FLATPAK_APPS=(
  "info.smplayer.SMPlayer"               # SMPlayer
  "com.discordapp.Discord"               # Discord
  "com.slack.Slack"                      # Slack
  "org.telegram.desktop"                 # Telegram
  "com.github.tchx84.Flatseal"           # Flatseal (Flatpak permissions manager)
  "org.gimp.GIMP"                        # GIMP
  "it.mijorus.gearlever"                 # Gear Lever
  "org.duckstation.DuckStation"          # DuckStation
  "org.DolphinEmu.dolphin-emu"           # Dolphin Emulator
  "net.pcsx2.PCSX2"                      # PCSX2
  "io.github.mhogomchungu.media-downloader" # Media Downloader
  
)

# Docker packages to install
readonly DOCKER_PACKAGES=(
 "docker-ce"
 "docker-ce-cli"
 "containerd.io"
 "docker-buildx-plugin"
 "docker-compose-plugin"
)

# Podman build dependencies
readonly PODMAN_DEPENDENCIES=(
 "make"
 "git"
 "gcc"
 "build-essential"
 "pkgconf"
 "libtool"
 "libsystemd-dev"
 "libprotobuf-c-dev"
 "libcap-dev"
 "libseccomp-dev"
 "libyajl-dev"
 "go-md2man"
 "autoconf"
 "python3"
 "automake"
 "golang"
 "libgpgme-dev"
 "man"
 "conmon"
 "passt"
 "uidmap"
 "netavark"
)

# Helper functions
#######################################
# Log a message to both stdout and the log file
# Globals:
#   LOG_FILE
#   LOG_MARKER
# Arguments:
#   Message to log
#######################################
log() {
 local timestamp
 timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
 echo "[${timestamp}] ${LOG_MARKER} $*" | tee -a "${LOG_FILE}"
}

#######################################
# Log an error message and exit
# Globals:
#   LOG_FILE
# Arguments:
#   Error message
#######################################
err() {
 local timestamp
 timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
 echo "[${timestamp}] ERROR: $*" | tee -a "${LOG_FILE}" >&2
 exit 1
}

#######################################
# Check if a command exists
# Arguments:
#   Command to check
# Returns:
#   0 if command exists, 1 otherwise
#######################################
command_exists() {
 command -v "$1" >/dev/null 2>&1
}

#######################################
# Check if a package is installed
# Arguments:
#   Package name
# Returns:
#   0 if package is installed, 1 otherwise
#######################################
package_installed() {
 dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

#######################################
# Install packages if they are not already installed
# Arguments:
#   List of packages to install
#######################################
install_packages() {
 local packages=("$@")
 local packages_to_install=()
 local pkg

 # Check which packages need to be installed
 for pkg in "${packages[@]}"; do
   if ! package_installed "${pkg}"; then
     packages_to_install+=("${pkg}")
   else
     log "Package ${pkg} is already installed"
   fi
 done

 # Install missing packages if any
 if (( ${#packages_to_install[@]} > 0 )); then
   log "Installing packages: ${packages_to_install[*]}"
   if ! apt-get install -y "${packages_to_install[@]}"; then
     err "Failed to install packages: ${packages_to_install[*]}"
   fi
   log "Successfully installed: ${packages_to_install[*]}"
 else
   log "All packages already installed, skipping"
 fi
}

#######################################
# Update apt repositories and upgrade system
# Globals:
#   None
# Arguments:
#   None
#######################################
update_system() {
 log "Updating apt repositories"
 if ! apt-get update; then
   err "Failed to update apt repositories"
 fi

 log "Upgrading system packages"
 if ! apt-get upgrade -y; then
   err "Failed to upgrade system packages"
 fi
}

#######################################
# Install snap applications
# Globals:
#   SNAP_APPS
# Arguments:
#   None
#######################################
function install_snap_apps() {
  log "Installing Snap applications"
  
  # Verify snapd is working
  if ! command_exists snap; then
    log "Warning: snap command not found. Attempting to install snapd."
    if ! apt-get update && apt-get install -y snapd; then
      err "Failed to install snapd. Cannot install snap applications."
    fi
    
    # Ensure snap service is running and enabled
    log "Ensuring snap service is running and enabled"
    systemctl enable --now snapd.service
  else
    log "Snapd is already installed and available"
  fi
  
  # Install each app in the SNAP_APPS array
  for app_spec in "${SNAP_APPS[@]}"; do
    # Extract app name (everything before any space)
    local app_name
    app_name=$(echo "${app_spec}" | cut -d' ' -f1)
    
    # Check if the app is already installed
    if snap list | grep -q "^${app_name} "; then
      log "Snap app ${app_name} is already installed"
    else
      log "Installing Snap app: ${app_name}"
      if ! snap install ${app_spec}; then
        log "Warning: Failed to install Snap app ${app_name}"
        # Continue with the next app instead of exiting
      else
        log "Snap app ${app_name} installed successfully"
      fi
    fi
  done
  
  log "Snap applications installation completed"
}

#######################################
# Install Steam dependencies
# Globals:
#   None
# Arguments:
#   None
#######################################
function install_steam_dependencies() {
  log "Installing Steam dependencies"
  
  # Enable multi-arch support if not already enabled
  if [ "$(dpkg --print-foreign-architectures | grep -c i386)" -eq 0 ]; then
    log "Enabling i386 architecture support"
    dpkg --add-architecture i386
    apt-get update
  fi
  
  # List of Steam dependencies - core dependencies
  local steam_core_deps=(
    "libc6:amd64"
    "libc6:i386"
    "libegl1:amd64"
    "libegl1:i386"
    "libgbm1:amd64"
    "libgbm1:i386"
    "libgl1-mesa-dri:amd64"
    "libgl1-mesa-dri:i386"
    "libgl1:amd64"
    "libgl1:i386"
  )
  
  # Video acceleration and rendering dependencies
  local steam_video_deps=(
    "i965-va-driver"
    "i965-va-driver:i386"
    "intel-media-va-driver"
    "intel-media-va-driver:i386"
    "libigdgmm12"
    "libigdgmm12:i386"
    "libva-drm2:i386"
    "libva-glx2"
    "libva-glx2:i386"
    "libva-x11-2:i386"
    "libva2:i386"
    "libvdpau1:i386"
    "mesa-va-drivers"
    "mesa-va-drivers:i386"
    "mesa-vdpau-drivers:i386"
    "va-driver-all"
    "va-driver-all:i386"
    "vdpau-driver-all:i386"
    "ocl-icd-libopencl1:i386"
  )
  
  # Audio-related dependencies
  local steam_audio_deps=(
    "libasound2-plugins"
    "libasound2-plugins:i386"
    "libasound2t64:i386"
    "libasyncns0:i386"
    "libflac14:i386"
    "libjack-jackd2-0:i386"
    "libmpg123-0t64:i386"
    "libogg0:i386"
    "libpulse0:i386"
    "libsamplerate0:i386"
    "libsndfile1:i386"
    "libsoxr0:i386"
    "libspeex1:i386"
    "libspeexdsp1:i386"
    "libvorbis0a:i386"
    "libvorbisenc2:i386"
  )
  
  # Video codec dependencies
  local steam_codec_deps=(
    "libaom3:i386"
    "libavcodec61:i386"
    "libavutil59:i386"
    "libcodec2-1.2:i386"
    "libdav1d7:i386"
    "libgsm1:i386"
    "libmp3lame0:i386"
    "libopus0:i386"
    "libshine3:i386"
    "libsharpyuv0:i386"
    "libsnappy1v5:i386"
    "libsvtav1enc2:i386"
    "libswresample5:i386"
    "libtheoradec1:i386"
    "libtheoraenc1:i386"
    "libtwolame0:i386"
    "libvpx9:i386"
    "libwebp7:i386"
    "libwebpmux3:i386"
    "libx264-164:i386"
    "libx265-215:i386"
    "libxvidcore4:i386"
    "libzvbi0t64:i386"
  )
  
  # Graphics and rendering dependencies
  local steam_graphics_deps=(
    "libcairo-gobject2:i386"
    "libcairo2:i386"
    "libfontconfig1:i386"
    "libfreetype6:i386"
    "libgdk-pixbuf-2.0-0:i386"
    "libharfbuzz0b:i386"
    "libjbig0:i386"
    "libjpeg-turbo8:i386"
    "libjpeg8:i386"
    "libopenjp2-7:i386"
    "libpango-1.0-0:i386"
    "libpangocairo-1.0-0:i386"
    "libpangoft2-1.0-0:i386"
    "libpixman-1-0:i386"
    "libpng16-16t64:i386"
    "librsvg2-2:i386"
    "librsvg2-common:i386"
    "libtiff6:i386"
    "libxcb-render0:i386"
    "libxrender1:i386"
  )
  
  # System and misc dependencies
  local steam_system_deps=(
    "libapparmor1:i386"
    "libblkid1:i386"
    "libbrotli1:i386"
    "libbz2-1.0:i386"
    "libcap2:i386"
    "libcrypt1:i386"
    "libdatrie1:i386"
    "libdb5.3t64:i386"
    "libdbus-1-3:i386"
    "libdeflate0:i386"
    "libfribidi0:i386"
    "libglib2.0-0t64:i386"
    "libgmp10:i386"
    "libgnutls30t64:i386"
    "libgomp1:i386"
    "libgpg-error0:i386"
    "libgraphite2-3:i386"
    "libhogweed6t64:i386"
    "libmount1:i386"
    "libnettle8t64:i386"
    "libnm0:i386"
    "libnuma1:i386"
    "libp11-kit0:i386"
    "libpcre2-8-0:i386"
    "libselinux1:i386"
    "libsystemd0:i386"
    "libtasn1-6:i386"
    "libthai0:i386"
    "libudev1:i386"
    "libxcb-xkb1:i386"
    "libxfixes3:i386"
    "libxinerama1:i386"
    "libxkbcommon-x11-0:i386"
    "libxkbcommon0:i386"
    "libxss1:i386"
  )
  
  # Combine all dependency arrays
  local all_steam_deps=(
    "${steam_core_deps[@]}"
    "${steam_video_deps[@]}"
    "${steam_audio_deps[@]}"
    "${steam_codec_deps[@]}"
    "${steam_graphics_deps[@]}"
    "${steam_system_deps[@]}"
  )
  
  # Install dependencies in groups
  log "Installing Steam core dependencies"
  apt-get install -y "${steam_core_deps[@]}" || log "Warning: Some core dependencies may have failed"
  
  log "Installing Steam video dependencies"
  apt-get install -y "${steam_video_deps[@]}" || log "Warning: Some video dependencies may have failed"
  
  log "Installing Steam audio dependencies"
  apt-get install -y "${steam_audio_deps[@]}" || log "Warning: Some audio dependencies may have failed"
  
  log "Installing Steam codec dependencies"
  apt-get install -y "${steam_codec_deps[@]}" || log "Warning: Some codec dependencies may have failed"
  
  log "Installing Steam graphics dependencies"
  apt-get install -y "${steam_graphics_deps[@]}" || log "Warning: Some graphics dependencies may have failed"
  
  log "Installing Steam system dependencies"
  apt-get install -y "${steam_system_deps[@]}" || log "Warning: Some system dependencies may have failed"
  
  # Verify installation
  local missing_deps=()
  for dep in "${all_steam_deps[@]}"; do
    # Extract package name without architecture specifier
    local pkg_name
    pkg_name=$(echo "${dep}" | cut -d':' -f1)
    
    if ! package_installed "${pkg_name}"; then
      missing_deps+=("${dep}")
    fi
  done
  
  if [ ${#missing_deps[@]} -eq 0 ]; then
    log "All Steam dependencies installed successfully"
  else
    log "Warning: The following Steam dependencies may not have installed correctly: ${missing_deps[*]}"
    log "Continuing with Steam installation anyway, as these might be installed during the Steam setup"
  fi
}

#######################################
# Install Steam
# Globals:
#   None
# Arguments:
#   None
#######################################
function install_steam() {
  local steam_deb="/tmp/steam.deb"
  local steam_url="https://cdn.fastly.steamstatic.com/client/installer/steam.deb"
  
  # Check if Steam is already installed
  if package_installed "steam" || package_installed "steam-launcher"; then
    log "Steam is already installed"
    return 0
  fi
  
  log "Installing Steam"
  
  # Install Steam dependencies first
  install_steam_dependencies
  
  # Download the Steam package
  log "Downloading Steam package"
  if ! wget -q -O "${steam_deb}" "${steam_url}"; then
    err "Failed to download Steam package"
  fi
  
  # Install the package
  log "Installing Steam package"
  if ! dpkg -i "${steam_deb}"; then
    # If there are dependency issues, try to fix them
    log "Fixing dependencies"
    apt-get install -f -y
    
    # Try the installation again
    if ! dpkg -i "${steam_deb}"; then
      err "Failed to install Steam package"
    fi
  fi
  
  # Clean up the downloaded package
  rm -f "${steam_deb}"
  
  # Verify the installation
  if package_installed "steam" || package_installed "steam-launcher"; then
    log "Steam installed successfully"
  else
    log "Warning: Steam installation may have failed. Please verify manually."
  fi
}

#######################################
# Remove conflicting Docker packages
# Globals:
#   None
# Arguments:
#   None
#######################################
remove_conflicting_packages() {
 log "Removing conflicting packages"
 # List of conflicting packages mentioned in the Docker documentation
 local conflicting_packages=(
   "docker.io"
   "docker-doc"
   "docker-compose"
   "docker-compose-v2"
   "podman-docker"
   "containerd"
   "runc"
 )
 
 for pkg in "${conflicting_packages[@]}"; do
   if package_installed "${pkg}"; then
     log "Removing conflicting package: ${pkg}"
     apt-get remove -y "${pkg}" || log "Package ${pkg} not installed or could not be removed"
   fi
 done
}

#######################################
# Check and wait for dpkg/apt locks with thorough detection
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if locks are released, exits with error otherwise
#######################################
check_package_locks() {
  log "Checking for package management locks"
  
  local lock_files=(
    "/var/lib/dpkg/lock-frontend"
    "/var/lib/dpkg/lock"
  )
  
  local max_wait_time=300  # 5 minutes max wait time
  local start_time=$(date +%s)
  local current_time
  local elapsed_time
  
  while true; do
    local locks_held=false
    
    # Check if apt or dpkg processes are running (only exact matches)
    if pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      locks_held=true
      current_time=$(date +%s)
      elapsed_time=$((current_time - start_time))
      
      log "Package management process is running (${elapsed_time}s elapsed)"
      
      if [ "$elapsed_time" -gt "$max_wait_time" ]; then
        log "Timed out after waiting ${max_wait_time} seconds for package processes to complete"
        log "You may need to manually check running apt/dpkg processes"
        err "Cannot proceed due to package management locks"
      fi
      
      log "Waiting 10 seconds for package processes to complete..."
      sleep 10
      continue
    fi
    
    # Check for actual locks on critical files
    for lock_file in "${lock_files[@]}"; do
      if fuser "$lock_file" >/dev/null 2>&1; then
        locks_held=true
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        log "Lock on $lock_file detected (${elapsed_time}s elapsed)"
        
        if [ "$elapsed_time" -gt "$max_wait_time" ]; then
          log "Timed out after waiting ${max_wait_time} seconds for lock on $lock_file to be released"
          err "Cannot proceed due to package management locks"
        fi
        
        log "Waiting 10 seconds for lock to be released..."
        sleep 10
        break
      fi
    done
    
    # If no locks are held, we can proceed
    if [ "$locks_held" = false ]; then
      log "Package management system is available"
      return 0
    fi
  done
}

#######################################
# Add Docker repository and install Docker
# Globals:
#   DOCKER_PACKAGES
#   DOCKER_KEYRING
#   DOCKER_SOURCE_LIST
# Arguments:
#   None
#######################################
install_docker() {
 if command_exists docker && docker --version >/dev/null 2>&1; then
   log "Docker is already installed"
   return 0
 fi

 log "Setting up Docker repository"
 
 # Ensure required packages are installed
 apt-get update
 apt-get install -y ca-certificates curl

 # Create directory for Docker keyring if it doesn't exist
 install -m 0755 -d /etc/apt/keyrings
 
 # Add Docker's official GPG key
 if [ ! -f "${DOCKER_KEYRING}" ]; then
   log "Adding Docker's GPG key"
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${DOCKER_KEYRING}"
   chmod a+r "${DOCKER_KEYRING}"
 fi

 # Add the repository to Apt sources
 log "Adding Docker repository to apt sources"
 echo \
   "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEYRING}] https://download.docker.com/linux/ubuntu \
   $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
   tee "${DOCKER_SOURCE_LIST}" > /dev/null

 # Update apt repository with the new Docker source
 apt-get update

 # Install Docker packages
 log "Installing Docker packages"
 install_packages "${DOCKER_PACKAGES[@]}"

 # Start and enable Docker service
 log "Enabling Docker service to start on boot"
 systemctl enable --now docker.service
 systemctl enable containerd.service
}

#######################################
# Configure Docker post-installation
# Globals:
#   None
# Arguments:
#   None
#######################################
configure_docker_post_install() {
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")

 # Create docker group if it doesn't exist
 if ! getent group docker >/dev/null; then
   log "Creating docker group"
   groupadd docker
 fi

 # Add user to docker group if not already a member
 if ! getent group docker | grep -q "\b${current_user}\b"; then
   log "Adding user ${current_user} to docker group"
   usermod -aG docker "${current_user}"
   log "User added to docker group. Please log out and back in for changes to take effect."
   log "Alternatively, run 'newgrp docker' to activate the changes immediately."
 else
   log "User ${current_user} is already in the docker group"
 fi

 # Configure Docker to start on boot (already done in install_docker, but including here for clarity)
 if ! systemctl is-enabled docker.service >/dev/null 2>&1; then
   log "Enabling Docker service to start on boot"
   systemctl enable docker.service
   systemctl enable containerd.service
 fi

 # Verify Docker installation
 if docker run --rm hello-world >/dev/null 2>&1; then
   log "Docker installation verified successfully"
 else
   err "Docker installation verification failed. Please check your installation."
 fi
}

#######################################
# Install Visual Studio Code
# Globals:
#   VSCODE_KEYRING
#   VSCODE_SOURCE_LIST
# Arguments:
#   None
#######################################
install_vscode() {
 if command_exists code; then
   log "Visual Studio Code is already installed"
   return 0
 fi

 log "Installing Visual Studio Code"
 
 # Set Microsoft repo preference automatically
 log "Setting VS Code repository preference"
 echo "code code/add-microsoft-repo boolean true" | debconf-set-selections
 
 # Install dependencies
 apt-get install -y wget gpg apt-transport-https
 
 # Create directory for Microsoft keyring if it doesn't exist
 install -m 0755 -d /etc/apt/keyrings
 
 # Add Microsoft GPG key
 log "Adding Microsoft GPG key"
 wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
 install -D -o root -g root -m 644 packages.microsoft.gpg "${VSCODE_KEYRING}"
 
 # Add VS Code repository
 log "Adding VS Code repository"
 echo "deb [arch=$(dpkg --print-architecture) signed-by=${VSCODE_KEYRING}] https://packages.microsoft.com/repos/code stable main" | tee "${VSCODE_SOURCE_LIST}" > /dev/null
 
 # Clean up
 rm -f packages.microsoft.gpg
 
 # Update package cache and install VS Code
 apt-get update
 apt-get install -y code
 
 log "Visual Studio Code has been installed successfully"
}

#######################################
# Install JetBrains Toolbox
# Globals:
#   JETBRAINS_INSTALL_DIR
#   JETBRAINS_SYMLINK_DIR
# Arguments:
#   None
#######################################
install_jetbrains_toolbox() {
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 local tmp_dir="/tmp"
 
 # Check if JetBrains Toolbox is already installed
 if [ -f "${JETBRAINS_SYMLINK_DIR}/jetbrains-toolbox" ]; then
   log "JetBrains Toolbox is already installed"
   return 0
 fi
 
 log "Installing JetBrains Toolbox"
 
 # Ensure libfuse2 is installed (required for AppImage)
 if ! package_installed "libfuse2"; then
   log "Installing libfuse2 (required for JetBrains Toolbox)"
   apt-get install -y libfuse2
 fi
 
 # Fetch the URL of the latest version
 log "Fetching the URL of the latest JetBrains Toolbox version"
 local archive_url
 archive_url=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | grep -Po '"linux":.*?[^\\]",' | awk -F ':' '{print $3,":"$4}'| sed 's/[", ]//g')
 local archive_filename
 archive_filename=$(basename "$archive_url")
 
 # Download the archive
 log "Downloading $archive_filename"
 rm -f "$tmp_dir/$archive_filename" 2>/dev/null || true
 wget -q --show-progress -cO "$tmp_dir/$archive_filename" "$archive_url"
 
 # Extract to the install directory
 log "Extracting to $JETBRAINS_INSTALL_DIR"
 mkdir -p "$JETBRAINS_INSTALL_DIR"
 rm -f "$JETBRAINS_INSTALL_DIR/jetbrains-toolbox" 2>/dev/null || true
 tar -xzf "$tmp_dir/$archive_filename" -C "$JETBRAINS_INSTALL_DIR" --strip-components=1
 rm -f "$tmp_dir/$archive_filename"
 chmod +x "$JETBRAINS_INSTALL_DIR/jetbrains-toolbox"
 
 # Create symlink
 log "Creating symlink to $JETBRAINS_SYMLINK_DIR/jetbrains-toolbox"
 mkdir -p "$JETBRAINS_SYMLINK_DIR"
 rm -f "$JETBRAINS_SYMLINK_DIR/jetbrains-toolbox" 2>/dev/null || true
 ln -s "$JETBRAINS_INSTALL_DIR/jetbrains-toolbox" "$JETBRAINS_SYMLINK_DIR/jetbrains-toolbox"
 
 # Fix ownership for the JetBrains directories
 chown -R "${current_user}:${current_user}" "$(dirname "$JETBRAINS_INSTALL_DIR")"
 chown -R "${current_user}:${current_user}" "$JETBRAINS_SYMLINK_DIR"
 
 log "JetBrains Toolbox has been installed successfully"
 log "You can run it by executing 'jetbrains-toolbox' (make sure $JETBRAINS_SYMLINK_DIR is in your PATH)"
 log "For the first run, you may need to launch it manually as the current user (not as root)"
}

#######################################
# Install Google Chrome Beta
# Globals:
#   None
# Arguments:
#   None
#######################################
install_chrome_beta() {
  local chrome_deb="/tmp/google-chrome-beta_current_amd64.deb"
  
  # Check if Chrome Beta is already installed
  if package_installed "google-chrome-beta"; then
    log "Google Chrome Beta is already installed"
    return 0
  fi
  
  log "Installing Google Chrome Beta"
  
  # Download the latest Chrome Beta package
  log "Downloading Google Chrome Beta package"
  if ! wget -q -O "${chrome_deb}" "https://dl.google.com/linux/direct/google-chrome-beta_current_amd64.deb"; then
    err "Failed to download Google Chrome Beta package"
  fi
  
  # Install the package
  log "Installing Google Chrome Beta package"
  if ! dpkg -i "${chrome_deb}"; then
    # If there are dependency issues, try to fix them
    log "Fixing dependencies"
    apt-get install -f -y
    
    # Try the installation again
    if ! dpkg -i "${chrome_deb}"; then
      err "Failed to install Google Chrome Beta package"
    fi
  fi
  
  # Clean up the downloaded package
  rm -f "${chrome_deb}"
  
  log "Google Chrome Beta installed successfully"
}

#######################################
# Install mise for the current user
# Globals:
#   MISE_INSTALLER
# Arguments:
#   None
#######################################
install_mise() {
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 local home_dir="/home/${current_user}"
 local fish_config_dir="${home_dir}/.config/fish"
 local fish_completions_dir="${fish_config_dir}/completions"
 
 log "Installing mise for user ${current_user}"
 
 # Check if mise is already installed
 if su -l "${current_user}" -c "command -v mise" >/dev/null 2>&1; then
   log "mise is already installed for user ${current_user}"
 else
   # Run the mise installer as the current user
   log "Running the mise installer script"
   su -l "${current_user}" -c "curl -fsSL ${MISE_INSTALLER} | sh"
   
   # Make sure the fish config directories exist
   if [ ! -d "${fish_completions_dir}" ]; then
     log "Creating fish completions directory"
     su -l "${current_user}" -c "mkdir -p '${fish_completions_dir}'"
   fi
   
   # Add mise activation to fish config
   local fish_config_file="${fish_config_dir}/config.fish"
   if [ -f "${fish_config_file}" ]; then
     if ! grep -q "mise activate" "${fish_config_file}"; then
       log "Adding mise activation to fish config"
       su -l "${current_user}" -c "echo '~/.local/bin/mise activate fish | source' >> '${fish_config_file}'"
     else
       log "mise activation already configured in fish config"
     fi
   else
     log "Creating fish config with mise activation"
     su -l "${current_user}" -c "mkdir -p '${fish_config_dir}'"
     su -l "${current_user}" -c "echo '~/.local/bin/mise activate fish | source' > '${fish_config_file}'"
   fi
   
   # Setup global usage
   log "Setting up mise global usage"
   su -l "${current_user}" -c "~/.local/bin/mise use -g usage"
   
   # Generate mise completions for fish
   log "Generating mise completions for fish"
   su -l "${current_user}" -c "~/.local/bin/mise completion fish > '${fish_completions_dir}/mise.fish'"
   
   log "mise has been successfully installed and configured for user ${current_user}"
 fi
}

#######################################
# Install Neovim from unstable PPA for kickstart.nvim
# Globals:
#   None
# Arguments:
#   None
#######################################
install_neovim() {
  local current_user
  current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
  
  # Check if Neovim is already installed from the PPA
  if command_exists nvim && grep -q "neovim-ppa/unstable" /etc/apt/sources.list.d/* 2>/dev/null; then
    log "Neovim (unstable) is already installed"
  else
    log "Installing Neovim from unstable PPA for kickstart.nvim compatibility"
    
    # Add the Neovim unstable PPA
    log "Adding Neovim unstable PPA"
    if ! add-apt-repository ppa:neovim-ppa/unstable -y; then
      err "Failed to add Neovim unstable PPA"
    fi
    
    # Update package lists
    log "Updating package lists"
    if ! apt-get update; then
      err "Failed to update package lists"
    fi
    
    # Install Neovim and dependencies
    log "Installing Neovim and dependencies"
    if ! apt-get install -y make gcc ripgrep unzip git xclip neovim fonts-noto-color-emoji; then
      err "Failed to install Neovim and dependencies"
    fi
    
    # Check installation
    if command_exists nvim; then
      local nvim_version
      nvim_version=$(nvim --version | head -n 1)
      log "Neovim installed successfully: ${nvim_version}"
    else
      err "Neovim installation failed"
    fi
  fi
  
  # Set up kickstart.nvim configuration
  local nvim_config_dir="/home/${current_user}/.config/nvim"
  
  # Check if kickstart.nvim is already set up
  if [ -d "${nvim_config_dir}" ] && [ -f "${nvim_config_dir}/init.lua" ]; then
    log "kickstart.nvim configuration already exists"
  else
    log "Setting up kickstart.nvim for user ${current_user}"
    
    # Clone kickstart.nvim repository
    su -l "${current_user}" -c "git clone https://github.com/nvim-lua/kickstart.nvim.git ~/.config/nvim"
    
    if [ -d "${nvim_config_dir}" ] && [ -f "${nvim_config_dir}/init.lua" ]; then
      log "kickstart.nvim configured successfully"
    else
      log "Warning: kickstart.nvim configuration may have failed, please check manually"
    fi
  fi

  # Add aliases for vim and vi to use neovim
  log "Setting up aliases for vim and vi to use neovim"

  # For fish shell
  local fish_config_dir="/home/${current_user}/.config/fish"
  local fish_config_file="${fish_config_dir}/config.fish"
  
  if [ -f "${fish_config_file}" ]; then
    if ! grep -q "alias vim='nvim'" "${fish_config_file}" && ! grep -q "alias vi='nvim'" "${fish_config_file}"; then
      log "Adding vim and vi aliases to fish config"
      cat >> "${fish_config_file}" << 'EOF'
      
# Neovim aliases
alias vim='nvim'
alias vi='nvim'
EOF
    chown "${current_user}:${current_user}" "${fish_config_file}"
    else
      log "vim and vi aliases already exist in fish config"
    fi
  fi

  # For bash shell
  local bash_rc="/home/${current_user}/.bashrc"
  
  if [ -f "${bash_rc}" ]; then
    if ! grep -q "alias vim='nvim'" "${bash_rc}" && ! grep -q "alias vi='nvim'" "${bash_rc}"; then
      log "Adding vim and vi aliases to bash config"
      cat >> "${bash_rc}" << 'EOF'

# Neovim aliases
alias vim='nvim'
alias vi='nvim'
EOF
    else
      log "vim and vi aliases already exist in bash config"
    fi
  fi
  
  log "Neovim aliases have been set up successfully"
}

#######################################
# Install Lua and LuaRocks from source
# Globals:
#   None
# Arguments:
#   None
#######################################
install_lua_and_luarocks() {
  local current_user
  current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
  local tmp_dir="/tmp/lua_build"
  local lua_version="5.4.7"
  local luarocks_version="3.11.1"
  local lua_tarball="lua-${lua_version}.tar.gz"
  local luarocks_tarball="luarocks-${luarocks_version}.tar.gz"
  
  log "Installing Lua ${lua_version} and LuaRocks ${luarocks_version} from source"
  
  # Check if Lua is already installed
  if command_exists lua && [ "$(lua -v 2>&1 | grep -o "${lua_version}")" = "${lua_version}" ]; then
    log "Lua ${lua_version} is already installed"
  else
    log "Building Lua ${lua_version} from source"
    
    # Install build dependencies
    log "Installing build dependencies"
    apt-get install -y build-essential libreadline-dev
    
    # Create build directory
    mkdir -p "${tmp_dir}"
    cd "${tmp_dir}" || err "Failed to enter build directory"
    
    # Download Lua source
    log "Downloading Lua ${lua_version} source"
    wget -q "https://www.lua.org/ftp/${lua_tarball}" -O "${lua_tarball}"
    
    # Extract tarball
    log "Extracting Lua source"
    tar -xzf "${lua_tarball}"
    cd "lua-${lua_version}" || err "Failed to enter Lua source directory"
    
    # Build and install Lua
    log "Building Lua"
    if ! make all test; then
      err "Failed to build Lua"
    fi
    
    log "Installing Lua"
    if ! make install; then
      err "Failed to install Lua"
    fi
    
    # Verify Lua installation
    if command_exists lua; then
      log "Lua $(lua -v 2>&1) installed successfully"
    else
      err "Lua installation failed"
    fi
  fi
  
  # Check if LuaRocks is already installed
  if command_exists luarocks && luarocks --version | grep -q "${luarocks_version}"; then
    log "LuaRocks ${luarocks_version} is already installed"
  else
    log "Building LuaRocks ${luarocks_version} from source"
    
    # Create build directory if not exists
    mkdir -p "${tmp_dir}"
    cd "${tmp_dir}" || err "Failed to enter build directory"
    
    # Download LuaRocks source
    log "Downloading LuaRocks ${luarocks_version} source"
    wget -q "https://luarocks.github.io/luarocks/releases/${luarocks_tarball}" -O "${luarocks_tarball}"
    
    # Extract tarball
    log "Extracting LuaRocks source"
    tar -xzf "${luarocks_tarball}"
    cd "luarocks-${luarocks_version}" || err "Failed to enter LuaRocks source directory"
    
    # Configure, build and install LuaRocks
    log "Configuring LuaRocks"
    if ! ./configure --with-lua-include=/usr/local/include; then
      err "Failed to configure LuaRocks"
    fi
    
    log "Building LuaRocks"
    if ! make; then
      err "Failed to build LuaRocks"
    fi
    
    log "Installing LuaRocks"
    if ! make install; then
      err "Failed to install LuaRocks"
    fi
    
    # Verify LuaRocks installation
    if command_exists luarocks; then
      log "LuaRocks $(luarocks --version) installed successfully"
    else
      err "LuaRocks installation failed"
    fi
  fi
  
  # Clean up build directory
  log "Cleaning up build files"
  rm -rf "${tmp_dir}"
  
  log "Lua and LuaRocks installation completed successfully"
}

#######################################
# Install latest Podman from source
# Globals:
#   PODMAN_VERSION
#   PODMAN_DEPENDENCIES
# Arguments:
#   None
#######################################
install_podman() {
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 local build_dir="/tmp/podman_build"
 
 # Check if podman is already installed with the required version
 if command_exists podman; then
   local installed_version
   installed_version=$(podman -v | awk '{print $3}')
   if [[ "${installed_version}" == "${PODMAN_VERSION#v}" ]]; then
     log "Podman ${PODMAN_VERSION} is already installed"
     return 0
   else
     log "Podman is installed, but version ${installed_version} does not match required ${PODMAN_VERSION#v}"
   fi
 fi

 log "Installing Podman dependencies"
 install_packages "${PODMAN_DEPENDENCIES[@]}"

 # Create build directory
 mkdir -p "${build_dir}"
 cd "${build_dir}" || err "Failed to enter ${build_dir} directory"

 # Clone and build Podman
 log "Cloning Podman repository"
 if [ ! -d "${build_dir}/podman" ]; then
   git clone https://github.com/containers/podman.git
 fi
 
 cd podman || err "Failed to enter podman directory"
 git fetch --all --tags
 git checkout "${PODMAN_VERSION}"
 
 log "Building Podman ${PODMAN_VERSION}"
 make clean || true  # Ignore if this fails
 make
 
 log "Installing Podman"
 make install

 # Verify installation
 if command_exists podman; then
   local new_version
   new_version=$(podman -v | awk '{print $3}')
   log "Podman ${new_version} installed successfully"
 else
   err "Podman installation failed"
 fi
}

#######################################
# Fix Podman AppArmor and unprivileged user namespace restrictions
# Globals:
#   None
# Arguments:
#   None
#######################################
fix_podman_userns() {
  log "Configuring system to allow Podman to use unprivileged user namespaces"
  
  # 1. First fix the Podman AppArmor profile path
  if [ -f "/etc/apparmor.d/podman" ]; then
    log "Updating Podman AppArmor profile"
    
    # Create backup of original file
    cp "/etc/apparmor.d/podman" "/etc/apparmor.d/podman.bak"
    
    # Create updated profile with pattern matching for both locations
    cat > "/etc/apparmor.d/podman" << 'EOF'
# This profile allows everything and only exists to give the
# application a name instead of having the label "unconfined"

abi <abi/4.0>,
include <tunables/global>

profile podman /usr/{bin,local/bin}/podman flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/podman>
}
EOF
    
    log "Podman AppArmor profile updated to use pattern matching for binary location"
  fi
  
  # 2. Disable the unprivileged user namespace restrictions
  log "Disabling AppArmor unprivileged user namespace restrictions"
  
  # Create sysctl config file
  cat > "/etc/sysctl.d/99-podman-userns.conf" << 'EOF'
# Allow unprivileged user namespaces for Podman
kernel.apparmor_restrict_unprivileged_unconfined=0
kernel.apparmor_restrict_unprivileged_userns=0
EOF
  
  # Apply sysctl settings
  log "Applying sysctl settings"
  sysctl -p /etc/sysctl.d/99-podman-userns.conf
  
  # 3. Reload AppArmor profiles
  log "Reloading AppArmor profiles"
  if command_exists apparmor_parser; then
    apparmor_parser -r "/etc/apparmor.d/podman" || log "Warning: Failed to reload AppArmor profile"
    log "AppArmor profile reloaded"
  else
    log "AppArmor parser not found, skipping profile reload"
  fi
  
  log "Podman AppArmor and unprivileged user namespace configuration completed"
}

#######################################
# Install latest crun from source
# Globals:
#   CRUN_VERSION
# Arguments:
#   None
#######################################
install_crun() {
 local build_dir="/tmp/crun_build"
 
 # Check if crun is already installed with the required version
 if command_exists crun; then
   local installed_version
   installed_version=$(crun -v | head -n 1 | awk '{print $3}')
   if [[ "${installed_version}" == "${CRUN_VERSION}" ]]; then
     log "crun ${CRUN_VERSION} is already installed"
     return 0
   else
     log "crun is installed, but version ${installed_version} does not match required ${CRUN_VERSION}"
   fi
 fi

 # Create build directory
 mkdir -p "${build_dir}"
 cd "${build_dir}" || err "Failed to enter ${build_dir} directory"

 # Clone and build crun
 log "Cloning crun repository"
 if [ ! -d "${build_dir}/crun" ]; then
   git clone https://github.com/containers/crun.git
 fi
 
 cd crun || err "Failed to enter crun directory"
 git fetch --all --tags
 git checkout "${CRUN_VERSION}"
 
 log "Building crun ${CRUN_VERSION}"
 ./autogen.sh
 ./configure
 make
 
 log "Installing crun"
 make install

 # Verify installation
 if command_exists crun; then
   local new_version
   new_version=$(crun -v | head -n 1 | awk '{print $3}')
   log "crun ${new_version} installed successfully"
 else
   err "crun installation failed"
 fi
}

#######################################
# Configure Podman policy.json and registries
# Globals:
#   CONTAINERS_REGISTRIES_CONF
# Arguments:
#   None
#######################################
#######################################
# Configure Podman policy.json and registries
# Globals:
#   CONTAINERS_REGISTRIES_CONF
# Arguments:
#   None
#######################################
configure_podman() {
 local system_config_dir="/etc/containers"
 local policy_file="${system_config_dir}/policy.json"
 
 # Create system-wide containers config directory if it doesn't exist
 if [ ! -d "${system_config_dir}" ]; then
   log "Creating system-wide containers config directory: ${system_config_dir}"
   mkdir -p "${system_config_dir}"
 fi
 
 # Create system-wide policy.json if it doesn't exist
 if [ ! -f "${policy_file}" ]; then
   log "Creating system-wide Podman policy.json file at ${policy_file}"
   cat > "${policy_file}" << 'EOF'
{
 "default": [
   {
     "type": "insecureAcceptAnything"
   }
 ]
}
EOF
   # Ownership should be root:root by default when run with sudo
   log "System-wide Podman policy.json created at ${policy_file}"
 else
   log "System-wide Podman policy.json already exists at ${policy_file}"
 fi
 
 # Configure unqualified search registries (remains system-wide)
 log "Configuring Podman unqualified search registries in ${CONTAINERS_REGISTRIES_CONF}"
 
 # Add unqualified search registries configuration if not already present
 if [ -f "${CONTAINERS_REGISTRIES_CONF}" ]; then
   if ! grep -q "unqualified-search-registries" "${CONTAINERS_REGISTRIES_CONF}"; then
     log "Adding unqualified search registries to ${CONTAINERS_REGISTRIES_CONF}"
     echo "unqualified-search-registries = ['docker.io', 'quay.io']" | tee -a "${CONTAINERS_REGISTRIES_CONF}" > /dev/null
   else
     log "Unqualified search registries already configured in ${CONTAINERS_REGISTRIES_CONF}"
   fi
 else
   log "Creating ${CONTAINERS_REGISTRIES_CONF} with unqualified search registries"
   echo "unqualified-search-registries = ['docker.io', 'quay.io']" | tee "${CONTAINERS_REGISTRIES_CONF}" > /dev/null
 fi
 
 # Verify Podman configuration
 if command_exists podman; then
   podman info --debug > "${LOG_FILE}.podman_info" 2>&1
   log "Podman configuration verified. Debug output saved to ${LOG_FILE}.podman_info"
 else
   log "Skipping Podman verification as it doesn't appear to be installed correctly"
 fi
}


#######################################
# Install 1Password desktop and CLI
# Globals:
#   None
# Arguments:
#   None
#######################################
install_1password() {
  local password_deb="/tmp/1password-latest.deb"
  
  log "Installing 1Password desktop and CLI"
  
  # Check if 1Password is already installed
  if package_installed "1password"; then
    log "1Password desktop is already installed"
  else
    # Download the latest 1Password package
    log "Downloading 1Password desktop package"
    if ! wget -q -O "${password_deb}" "https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb"; then
      err "Failed to download 1Password package"
    fi
    
    # Install the package
    log "Installing 1Password desktop package"
    if ! dpkg -i "${password_deb}"; then
      # If there are dependency issues, try to fix them
      log "Fixing dependencies"
      apt-get install -f -y
      
      # Try the installation again
      if ! dpkg -i "${password_deb}"; then
        err "Failed to install 1Password desktop package"
      fi
    fi
    
    # Clean up the downloaded package
    rm -f "${password_deb}"
    
    log "1Password desktop installed successfully"
  fi
  
  # Check if 1Password CLI is already installed
  if command_exists op; then
    log "1Password CLI is already installed"
  else
    # Update package database to recognize the repository added by 1Password
    log "Updating package database"
    apt-get update
    
    # Install 1Password CLI
    log "Installing 1Password CLI package"
    if ! apt-get install -y 1password-cli; then
      err "Failed to install 1Password CLI"
    fi
    
    # Verify installation
    if command_exists op; then
      local version
      version=$(op --version)
      log "1Password CLI version ${version} installed successfully"
    else
      err "1Password CLI installation verification failed"
    fi
  fi
  
  log "1Password desktop and CLI installation completed"
}

#######################################
# Install and configure Flatpak
# Globals:
#   FLATPAK_PACKAGES
#   FLATHUB_REPO
# Arguments:
#   None
#######################################
install_flatpak() {
 log "Installing Flatpak packages"
 install_packages "${FLATPAK_PACKAGES[@]}"
 
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 
 # Add Flathub repository for the current user (not root)
 log "Adding Flathub repository for user ${current_user}"
 
 # We need to run the flatpak command as the current user, not as root
 su -l "${current_user}" -c "flatpak remote-add --user --if-not-exists flathub ${FLATHUB_REPO}"
 
 log "Flatpak installation and configuration completed successfully"
}

#######################################
# Install Flatpak apps for the current user
# Globals:
#   FLATPAK_APPS
# Arguments:
#   None
#######################################
install_flatpak_apps() {
  local current_user
  current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
  
  log "Installing Flatpak applications for user ${current_user}"
  
  # Make sure Flatpak is installed before proceeding
  if ! command_exists flatpak; then
    log "Flatpak is not installed. Installing it first."
    install_flatpak
  fi
  
  # Install each app in the FLATPAK_APPS array
  for app in "${FLATPAK_APPS[@]}"; do
    # Extract app name for logging (remove everything before the last dot)
    local app_name
    app_name=$(echo "$app" | sed 's/.*\.//')
    
    # Check if the app is already installed
    if su -l "${current_user}" -c "flatpak list --app | grep -q ${app}"; then
      log "Flatpak app ${app_name} is already installed"
    else
      log "Installing Flatpak app: ${app_name}"
      if ! su -l "${current_user}" -c "flatpak install --user -y flathub ${app}"; then
        log "Warning: Failed to install Flatpak app ${app_name}"
        # Continue with the next app instead of exiting
      else
        log "Flatpak app ${app_name} installed successfully"
      fi
    fi
  done
  
  log "Flatpak applications installation completed"
}

#######################################
# Install pyenv for the current user
# Globals:
#   PYENV_DEPENDENCIES
#   PYENV_INSTALLER
# Arguments:
#   None
#######################################
install_pyenv() {
 log "Installing pyenv dependencies"
 install_packages "${PYENV_DEPENDENCIES[@]}"
 
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 
 log "Installing pyenv for user ${current_user}"
 
 # Check if pyenv is already installed
 if su -l "${current_user}" -c "command -v pyenv" >/dev/null 2>&1; then
   log "pyenv is already installed for user ${current_user}"
 else
   log "Installing pyenv using the installer script"
   su -l "${current_user}" -c "curl -fsSL ${PYENV_INSTALLER} | bash"
   
   # Set up shell integration for bash
   if [ -f "/home/${current_user}/.bashrc" ]; then
     if ! grep -q "pyenv init" "/home/${current_user}/.bashrc"; then
       log "Setting up pyenv in .bashrc"
       cat >> "/home/${current_user}/.bashrc" << 'EOF'

# pyenv setup
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
     fi
   fi
   
   # Set up shell integration for fish
   local fish_config_dir="/home/${current_user}/.config/fish"
   local fish_config_file="${fish_config_dir}/config.fish"
   
   if [ ! -d "${fish_config_dir}" ]; then
     mkdir -p "${fish_config_dir}"
     chown "${current_user}:${current_user}" "${fish_config_dir}"
   fi
   
   if [ -f "${fish_config_file}" ]; then
     if ! grep -q "pyenv init" "${fish_config_file}"; then
       log "Setting up pyenv in fish config"
       cat >> "${fish_config_file}" << 'EOF'

# pyenv setup
set -gx PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin
pyenv init - | source
status --is-interactive; and pyenv virtualenv-init - | source
EOF
       chown "${current_user}:${current_user}" "${fish_config_file}"
     fi
   else
     log "Creating fish config with pyenv setup"
     cat > "${fish_config_file}" << 'EOF'
# pyenv setup
set -gx PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin
pyenv init - | source
status --is-interactive; and pyenv virtualenv-init - | source
EOF
     chown "${current_user}:${current_user}" "${fish_config_file}"
   fi
   
   log "pyenv installed successfully for user ${current_user}"
 fi
}

#######################################
# Install and configure fish shell as default
# Globals:
#   None
# Arguments:
#   None
#######################################
configure_fish_shell() {
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 
 # Check if fish is already installed
 if ! command_exists fish; then
   log "Installing fish shell"
   install_packages "fish"
 else
   log "Fish shell is already installed"
 fi
 
 # Get fish shell path
 local fish_path
 fish_path=$(which fish)
 
 # Set fish as default shell for the current user
 if ! grep -q "${fish_path}" "/etc/passwd" | grep "${current_user}"; then
   log "Setting fish as the default shell for user ${current_user}"
   chsh -s "${fish_path}" "${current_user}"
 else
   log "Fish shell is already the default for user ${current_user}"
 fi
 
 # Create fish config directory if it doesn't exist
 local fish_config_dir="/home/${current_user}/.config/fish"
 if [ ! -d "${fish_config_dir}" ]; then
   log "Creating fish config directory"
   mkdir -p "${fish_config_dir}"
   chown "${current_user}:${current_user}" "${fish_config_dir}"
 fi
 
 # Create initial fish config if it doesn't exist
 local fish_config_file="${fish_config_dir}/config.fish"
 if [ ! -f "${fish_config_file}" ]; then
   log "Creating initial fish config file"
   cat > "${fish_config_file}" << 'EOF'
# Fish shell configuration

# Add user's private bin to PATH if it exists
if test -d "$HOME/bin"
   fish_add_path "$HOME/bin"
end

if test -d "$HOME/.local/bin"
   fish_add_path "$HOME/.local/bin"
end

# Set environment variables
set -gx EDITOR nvim

# Custom aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Fish greeting
function fish_greeting
   echo "Welcome to Fish shell!"
end

# Load local config if exists
if test -f "$HOME/.config/fish/local.fish"
   source "$HOME/.config/fish/local.fish"
end
EOF
   chown "${current_user}:${current_user}" "${fish_config_file}"
 fi
 
 log "Fish shell has been configured successfully"
}

#######################################
# Install and configure KVM with libvirt
# Globals:
#   None
# Arguments:
#   None
#######################################
install_kvm_libvirt() {
  local current_user
  current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
  
  log "Installing KVM and libvirt packages"
  
  # Install KVM and libvirt packages
  apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
  
  # Enable and start the libvirtd service
  log "Enabling and starting libvirtd service"
  systemctl enable libvirtd
  systemctl start libvirtd
  
  # Add user to the kvm and libvirt groups
  log "Adding user ${current_user} to kvm and libvirt groups"
  if ! getent group kvm | grep -q "\b${current_user}\b"; then
    usermod -aG kvm "${current_user}"
  fi
  
  if ! getent group libvirt | grep -q "\b${current_user}\b"; then
    usermod -aG libvirt "${current_user}"
  fi
  
  # Start and enable default NAT network
  log "Starting and enabling default NAT network"
  if ! virsh net-info default | grep -q "Active:.*yes"; then
    virsh net-start default || log "Default network may already be running"
  fi
  virsh net-autostart default
  
  # Verify installation
  if command_exists virsh && virsh -c qemu:///system list >/dev/null 2>&1; then
    log "KVM and libvirt installed and configured successfully"
  else
    log "Warning: KVM and libvirt installation may not be complete. Please check manually."
  fi
}

#######################################
# Perform final system update and upgrade
# Globals:
#   None
# Arguments:
#   None
#######################################
function perform_final_update() {
  log "Performing final system update and upgrade"
  
  # Update package index
  log "Updating package repositories one last time"
  if ! apt-get update; then
    log "Warning: Final apt update failed, but continuing anyway"
  fi
  
  # Upgrade all packages to their latest versions
  log "Upgrading all installed packages to their latest versions"
  if ! apt-get upgrade -y; then
    log "Warning: Final apt upgrade encountered some issues"
  fi
  
  # Perform dist-upgrade to handle package dependencies properly
  log "Performing distribution upgrade to handle changed dependencies"
  if ! apt-get dist-upgrade -y; then
    log "Warning: Final apt dist-upgrade encountered some issues"
  fi
  
  # Clean up any unnecessary packages
  log "Removing unnecessary packages"
  if ! apt-get autoremove -y; then
    log "Warning: Package autoremoval encountered some issues"
  fi
  
  # Clean up apt cache
  log "Cleaning apt cache"
  if ! apt-get clean; then
    log "Warning: Apt cache cleanup encountered issues"
  fi
  
  log "Final system update and upgrade completed"
}


#######################################
# Prompt for system restart unless auto mode is enabled
# Globals:
#   AUTO_MODE
# Arguments:
#   None
#######################################
prompt_for_restart() {
  if [[ "${AUTO_MODE}" == "true" ]]; then
    log "Running in automatic mode. System will restart in 10 seconds."
    log "Press Ctrl+C to cancel restart."
    sleep 10
    reboot
    return 0
  fi
  
  local response
  
  log "All installations and configurations are complete."
  log "It is recommended to restart your system to ensure all changes take effect."
  
  read -p "Would you like to restart now? (y/n): " -r response
  
  if [[ "${response,,}" =~ ^(y|yes)$ ]]; then
    log "System will restart in 10 seconds. Press Ctrl+C to cancel."
    sleep 10
    reboot
  else
    log "Restart skipped. Remember to restart your system later for all changes to take effect."
  fi
}

#######################################
# Check if the script is being run as root
# Arguments:
#   None
# Returns:
#   0 if script is run as root, exits otherwise
#######################################
check_root() {
 if [[ $EUID -ne 0 ]]; then
   err "This script must be run as root. Please use sudo."
 fi
}

#######################################
# Main function
# Globals:
#   SYSTEM_PACKAGES
#   DEV_PACKAGES
#   UTIL_PACKAGES
# Arguments:
#   None
#######################################
main() {
 log "Starting system setup script"
 
 check_root
 
 # Parse command line options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto|-a)
        AUTO_MODE="true"
        log "Automatic mode enabled - no interactive prompts will be shown"
        shift
        ;;
      --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --auto, -a    Run in automatic mode (no interactive prompts)"
        echo "  --help, -h    Show this help message"
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
  
  # Now make AUTO_MODE readonly after argument parsing
  readonly AUTO_MODE

  # Check for package management locks before proceeding
  check_package_locks
 
 # Update and upgrade system
 update_system
 
 # Install system packages
 log "Installing system packages"
 install_packages "${SYSTEM_PACKAGES[@]}"
 
 # Install development packages
 log "Installing development packages"
 install_packages "${DEV_PACKAGES[@]}"

 # Install Neovim from unstable PPA
 install_neovim

 # Install Lua and LuaRocks
 install_lua_and_luarocks

 # Install KVM and libvirt
 install_kvm_libvirt
 
 # Install utility packages
 log "Installing utility packages"
 install_packages "${UTIL_PACKAGES[@]}"
 
 # Install VS Code
 install_vscode
 
 # Install JetBrains Toolbox
 install_jetbrains_toolbox

 # Install Google Chrome Beta
 install_chrome_beta

 # Install Steam
 install_steam

 # Install 1Password
 install_1password
 
 # Install Flatpak
 install_flatpak

 # Install Flatpak apps
 install_flatpak_apps

 # Install Snap apps
 install_snap_apps
 
 # Remove conflicting Docker packages
 remove_conflicting_packages
 
 # Install Docker
 install_docker
 
 # Configure Docker post-installation
 configure_docker_post_install
 
 # Install Podman from source
 install_podman
 
 # Install crun from source
 install_crun
 
 # Configure Podman
 configure_podman

 # Fix Podman AppArmor and unprivileged user namespaces
 fix_podman_userns
 
 # Install pyenv
 install_pyenv
 
 # Install mise
 install_mise
 
 # Configure fish shell
 configure_fish_shell

 # Perform final system update and upgrade
 perform_final_update
 
 log "System setup completed successfully"
 log "Note: You may need to log out and back in for the following changes to take effect:"
 log "- Docker group membership"
 log "- pyenv initialization"
 log "- mise initialization"
 log "- Default shell change to fish"
 log "Alternatively, run 'newgrp docker' for Docker group and 'exec fish' to start using fish shell immediately"
 log "To launch JetBrains Toolbox, run 'jetbrains-toolbox' as your normal user (not as root)"

 # Prompt for restart
  prompt_for_restart
}

# Execute main function
main "$@"
