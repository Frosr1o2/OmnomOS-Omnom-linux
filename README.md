# Omnom Linux Minimal Requirements
## Minimum Hardware
###### This can be change in any version!

    CPU: x86_64 or ARM64, 1 GHz or faster

    RAM: 512 MB minimum (2 GB recommended)

    Storage: 16 GB minimum (32 GB recommended)

    Graphics: GPU with Wayland support (for Hyprland/Niri and kitty/alacritty)
    

### Build Dependencies

    Compiler: GCC 12+ or Clang 15+

    Make: GNU Make 4.0+

    Python: 3.10+ (for build scripts)

    Git: 2.30+ (for source fetching)

    CMake: 3.20+ (for some packages)

    Meson: 1.0+ (for some packages)

    Ninja: 1.10+ (for fast builds)

### Runtime Dependencies

    Kernel: Linux 6.0+ (with Wayland support)

    libc: glibc 2.35+ or musl 1.2+

    OpenRC: 0.45+ (init system)

    Wayland: 1.22+ (display server)

    Hyprland: 0.35+ or Niri 0.1+

    Kitty: 0.30+ (terminal)

    Fish: 3.6+ (shell)

### Package Manager Backends (Optional)

    DNF: 4.10+ (for RPM packages)

    Pacman: 6.0+ (for Arch packages)

    APT: 2.4+ (for Debian packages)

    Portage: 3.0+ (for Gentoo emerge)

    Yay/Paru: (for AUR support)

### Network

    Internet connection for package downloads

    Minimum 1 Mbps recommended

    Access to OUR repository (https://frosr1o2.github.io/OmnomOS-Omnom-linux)

 > This link changes some times

### Build Space

    /tmp: 2 GB minimum (for source compilation)

    /var/lib/omnom: 1 GB minimum (for generations)

    ~/.cache/omnom: 1 GB minimum (for build cache)

### Supported Architectures

    Primary: x86_64

    Secondary: ARM64 (aarch64)

    Experimental: RISC-V

### Display Requirements

    Resolution: 1024x768 minimum

    Color Depth: 24-bit (true color)

    GPU: Vulkan support recommended (for Hyprland)

    DRM: Kernel Mode Setting (KMS) support

### Description

A minimalist, source-based Linux distribution built from scratch with modern sensibilities.
Default Settings

    Base: Linux From Scratch (LFS) - custom built from source

    Init System: OpenRC - lightweight and fast

    Desktop Environment: Hyprland or Niri

    Default Shell: Fish - user-friendly with autosuggestions

    Default Terminal: Kitty - GPU-accelerated terminal emulator

    Package Management: NixOS-style generations with rollback support

    Resource Usage: Optimized for low RAM consumption

Package Management Commands
omnom-install - Intelligent Package Installer

Automatically detects and uses the best available package manager with fallback options:

Installation Priority Order:

    DNF (RPM-based)

    Pacman (Arch-based)

    AUR (Arch User Repository)

    OUR (Omnom User Repository)

    Source compilation (Gentoo-style emerge)

Usage Examples:

omnom-install firefox                    # Auto-detect best method
omnom-install firefox --emerge          # Force compile from source (Gentoo style)
omnom-install firefox --our             # Install from Omnom User Repository
omnom-install firefox --dnf             # Force use DNF
omnom-install firefox --pacman          # Force use Pacman
omnom-install firefox --aur             # Force install from AUR
omnom-install --our                     # Browse/search OUR repository
omnom-install --list                    # List all installed packages
omnom-install --search <term>           # Search across all repositories
omnom-install --remove <package>        # Remove installed package

omnom-upgrade - System Updater

Intelligent system update tool with rollback capabilities:

Usage Examples:

omnom-upgrade --all                     # Update everything (system + packages)
omnom-upgrade firefox                   # Update specific package only
omnom-upgrade our                       # Update Omnom User Repository
omnom-upgrade --check                   # Check for available updates without installing
omnom-upgrade --rollback                # Rollback to previous generation
omnom-upgrade --list-generations        # List all system generations
omnom-upgrade --switch <generation>     # Switch to specific generation

Key Features
1. NixOS-Style Generations

    Every install/upgrade creates a new system generation

    Easy rollback to any previous state

    Keep up to 10 generations by default (configurable)

2. Multi-Backend Support

    Seamlessly works with DNF, Pacman, APT, Emerge

    Unified interface across different package managers

    Automatic fallback if primary method fails

3. Omnom User Repository (OUR)

    Community-driven package repository

    Easy package submission

    Simple .pkg format for package definitions

    Local package creation support

4. Source Compilation

    Gentoo-style emerge support

    Automatic dependency resolution

    Optimized for the specific hardware

    Custom compiler flags support

5. Low Resource Usage

    Minimal memory footprint

    No unnecessary background services

    Efficient package management

    Optimized for older hardware

File Structure

/etc/omnom/
├── omnom.conf          # Main configuration
├── repos.conf          # Repository configuration
└── flags.conf          # Default compiler flags

/var/lib/omnom/
├── generations/        # All system generations
│   ├── gen-20240315_120000/
│   ├── gen-20240315_150000/
│   └── current -> gen-20240315_150000/
├── packages.list      # Currently installed packages
└── history.log        # Installation/upgrade history

~/.config/omnom/
├── our-repo/          # Local OUR packages
└── omnomrc           # User configuration

~/.cache/omnom/
└── builds/           # Temporary build files

Configuration Options

# /etc/omnom/omnom.conf

### Default installation method (auto/dnf/pacman/emerge/our)
DEFAULT_METHOD="auto"

### Keep generations count
GENERATIONS_KEEP=10

### Compiler flags for source compilation
CFLAGS="-O2 -march=native -pipe"
MAKEOPTS="-j$(nproc)"

### Repository settings
OUR_REPO_ENABLED=true
OUR_REPO_URL="https://frosr1o2.github.io/OmnomOS-Omnom-linux" -- our site can change sometimes

### Auto-cleanup
AUTO_CLEANUP=true

Example Workflows
Installing Firefox

### Try to install with auto-detection
omnom-install firefox

### If you want to compile from source for optimization
omnom-install firefox --emerge

### If you want to use a custom package from OUR
omnom-install firefox --our

Updating System

### Full system update
omnom-upgrade --all

### Check what updates are available
omnom-upgrade --check

### Something broke? Rollback!
omnom-upgrade --rollback

Managing Packages

### See what's installed
omnom-install --list

### Search for packages
omnom-install --search browser

### Remove a package
omnom-remove firefox

## Benefits Over Traditional Distros

    Flexibility: Mix and match package managers

    Safety: Automatic generations = easy rollback

    Control: Choose between binary or source compilation

    Simplicity: Single command for all package operations

    Efficiency: Low RAM usage optimized

    Modern: Wayland + Hyprland for smooth desktop experience

### Future Roadmap

    GUI package manager frontend
    
    First beta test iso release

    Flatpak/AppImage integration

    Container-based package isolation

    Distributed package compilation

    Automated performance benchmarking

    Package dependency visualization

    Binary cache for compiled packages
    
## Omnom Linux - Because package management should be delicious!

# When you got iso file?
I'm Trying work hard but i don't have so much time to this project so i'm thinking release date is 2027 year or 2026 ~9 November yes sorry but i'm do it alone
