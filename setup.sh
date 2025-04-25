#!/bin/bash
#
# Ubuntu System Setup Script
# 
# This script automates the installation of commonly used tools on Ubuntu 24.10+.
# It is designed to be idempotent and maintainable, allowing easy addition and 
# removal of tools.

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

# Flatpak packages
readonly FLATPAK_PACKAGES=(
 "flatpak"
 "gnome-software-plugin-flatpak"
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
    if ! apt-get install -y make gcc ripgrep unzip git xclip neovim; then
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
configure_podman() {
 local current_user
 current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
 local config_dir="/home/${current_user}/.config/containers"
 local policy_file="${config_dir}/policy.json"
 
 # Create containers config directory if it doesn't exist
 if [ ! -d "${config_dir}" ]; then
   log "Creating containers config directory"
   mkdir -p "${config_dir}"
   chown "${current_user}:${current_user}" "${config_dir}"
 fi
 
 # Create policy.json if it doesn't exist
 if [ ! -f "${policy_file}" ]; then
   log "Creating Podman policy.json file"
   cat > "${policy_file}" << 'EOF'
{
 "default": [
   {
     "type": "insecureAcceptAnything"
   }
 ]
}
EOF
   chown "${current_user}:${current_user}" "${policy_file}"
   log "Podman policy.json created at ${policy_file}"
 else
   log "Podman policy.json already exists at ${policy_file}"
 fi
 
 # Configure unqualified search registries
 log "Configuring Podman unqualified search registries"
 
 # Create containers directory if it doesn't exist
 if [ ! -d "/etc/containers" ]; then
   mkdir -p /etc/containers
 fi
 
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
 
 # Install utility packages
 log "Installing utility packages"
 install_packages "${UTIL_PACKAGES[@]}"
 
 # Install VS Code
 install_vscode
 
 # Install JetBrains Toolbox
 install_jetbrains_toolbox

 # Install Google Chrome Beta
 install_chrome_beta
 
 # Install Flatpak
 install_flatpak
 
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
 
 # Install pyenv
 install_pyenv
 
 # Install mise
 install_mise
 
 # Configure fish shell
 configure_fish_shell
 
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
