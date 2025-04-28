# Ubuntu Setup Automation

A comprehensive shell script to automatically set up an Ubuntu development environment with your favorite apps, tools, and configurations.

<img src="https://assets.ubuntu.com/v1/29985a98-ubuntu-logo32.png" alt="Ubuntu Logo" width="100" />

## 🚀 Quick Start

Run this command to automatically set up your Ubuntu system:

```bash
wget -qO- "https://raw.githubusercontent.com/Retrockit/ubuntu-setup/refs/heads/main/setup.sh" | sudo bash -s -- --auto
```

Or use shortened link version

```bash
wget -qO- "https://bit.ly/ubtusetup" | sudo bash -s -- --auto
```

This will install and configure everything with default settings, no interaction required.

## 📋 What Does It Install?

### Development Environment
- **Languages & Runtimes**: Python (with pyenv), Lua (with LuaRocks), mise runtime manager
- **Editors & IDEs**: VS Code, Neovim (with kickstart.nvim config), JetBrains Toolbox
- **Version Control**: Git and related tools
- **Containers**: Docker CE, Podman 5.4.2, crun 1.21
- **Virtualization**: KVM/QEMU with libvirt

### Applications
- **Browsers**: Google Chrome Beta
- **Password Manager**: 1Password (desktop + CLI)
- **Gaming**: Steam with all required dependencies
- **Plus**: Many useful Flatpak and Snap applications

### System Configuration
- **Shell**: Fish shell with developer-friendly configuration
- **Utilities**: Various CLI tools (htop, tmux, tree, etc.)
- **Security**: Configured with best practices

## 🛠️ Usage Options

### Interactive Mode
For step-by-step installation with prompts:

```bash
sudo ./setup.sh
```

### Automated Mode
For completely unattended installation:

```bash
sudo ./setup.sh --auto
```

### Help Information
To see all available options:

```bash
./setup.sh --help
```

## ✅ Requirements

- Ubuntu 24.10 or newer
- Sudo privileges
- Internet connection

## 🔧 Customizing the Installation

You can easily customize what gets installed to match your preferences:

### Method 1: Edit the Script

1. Clone the repository:
   ```bash
   git clone https://github.com/Retrockit/ubuntu-setup.git
   cd ubuntu-setup
   ```

2. Edit the package arrays at the top of the script:
   ```bash
   # Find and modify these arrays:
   readonly SYSTEM_PACKAGES=(...)
   readonly DEV_PACKAGES=(...)
   readonly UTIL_PACKAGES=(...)
   readonly FLATPAK_APPS=(...)
   readonly SNAP_APPS=(...)
   ```

3. Run the modified script:
   ```bash
   sudo ./setup.sh
   ```

### Method 2: Disable Components

To skip certain installations, open the script and comment out the corresponding function calls in the `main()` function:

```bash
function main() {
  # ...
  
  # Comment out what you don't want
  # install_docker
  # install_vscode
  
  # ...
}
```

### Method 3: Add Your Own Components

You can add custom installations by:

1. Creating a new function for your component:
   ```bash
   function install_my_app() {
     log "Installing my custom application"
     # Your installation commands here
   }
   ```

2. Adding a call to your function in the `main()` function:
   ```bash
   function main() {
     # ...
     install_my_app
     # ...
   }
   ```

## 📝 Logs

Installation logs are saved to:
```
/tmp/{script-name}_{timestamp}.log
```

These logs are helpful for troubleshooting if something goes wrong.

## ⚙️ Features

- **Idempotent**: Can be run multiple times without breaking your system
- **Distribution-aware**: Designed for Ubuntu 24.10+ but adaptable
- **Modular**: Easy to add or remove components
- **Comprehensive**: Sets up a complete development environment in one go
- **Well-documented**: Clear logging and feedback throughout the process

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues or pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Maintainer**: SolutionMonk
**GitHub**: [Retrockit/ubuntu-setup](https://github.com/Retrockit/ubuntu-setup)
