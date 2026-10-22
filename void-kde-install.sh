#!/bin/bash
# =============================================================================
# Void Linux (glibc, x86_64) - post-install: KDE Plasma + Runit
# Hardware: Ryzen 9 5950X | RX 6800 XT | Gigabyte X570 Gaming X | 64 GB RAM
#
# Usage:  bash void_kde_installer_en.sh [-y|--yes] [--no-nm]
#   -y, --yes   no prompts: enable SDDM and reboot the computer at the end
#   --no-nm     do not switch networking from dhcpcd to NetworkManager
# Log: /var/log/void-kde-setup.log
# =============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "Bash shell not found. Install it with: xbps-install -Sy bash" >&2
        exit 1
    fi
fi

set -uo pipefail

# --- Colors ------------------------------------------------------------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

STEP=0
TOTAL_STEPS=9
FAILED_PKGS=()
FAILED_ACTIONS=()
LOG="/var/log/void-kde-setup.log"
AUTO_YES=0
SWITCH_NM=1

step()  { STEP=$((STEP+1)); echo -e "\n${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} ${CYAN}$*${NC}"; }
info()  { echo -e "    ${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "    ${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "    ${RED}[ERROR]${NC} $*" >&2; }

# --- Privileges --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        warn "Not running as root - restarting via sudo..."
        exec sudo bash "$0" "$@"
    else
        fail "The script must be run as root (log in with: su -)."
        exit 1
    fi
fi

# --- Arguments ---------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        -y|--yes) AUTO_YES=1 ;;
        --no-nm)  SWITCH_NM=0 ;;
        -h|--help)
            echo "Usage: bash $0 [-y|--yes] [--no-nm]"
            exit 0 ;;
        *) warn "Unknown argument: $arg (ignoring)" ;;
    esac
done

# --- Preparation -------------------------------------------------------------
: >> "$LOG" 2>/dev/null || LOG="/tmp/void-kde-setup.log"
echo "=== $(date) === void-kde-setup start" >> "$LOG"

# Polish characters in the text console
if [[ "$(tty 2>/dev/null)" == /dev/tty* ]]; then
    setfont Lat2-Terminus16 2>/dev/null || true
fi

# Virtual machine detection
IS_VM=0
grep -q '^flags.*hypervisor' /proc/cpuinfo 2>/dev/null && IS_VM=1

# Detect the regular user (no prompt)
MAIN_USER="${SUDO_USER:-}"
if [[ -z "$MAIN_USER" || "$MAIN_USER" == "root" ]]; then
    MAIN_USER="$(getent passwd 1000 | cut -d: -f1)"
fi

# --- Helper functions --------------------------------------------------------

pkg_installed() { xbps-query "$1" >/dev/null 2>&1; }
pkg_in_repo()   { xbps-query -R "$1" >/dev/null 2>&1; }

# Install packages one by one; a failure of one does not block the rest
install_pkgs() {
    local pkg
    for pkg in "$@"; do
        if pkg_installed "$pkg"; then
            info "$pkg - already installed"
            continue
        fi
        if ! pkg_in_repo "$pkg"; then
            fail "Package does not exist in the repository: $pkg"
            FAILED_PKGS+=("$pkg (not in repo)")
            continue
        fi
        if xbps-install -y "$pkg" >>"$LOG" 2>&1; then
            info "Installed: $pkg"
        else
            fail "Failed to install: $pkg (details in $LOG)"
            FAILED_PKGS+=("$pkg")
        fi
    done
}

# Install the first existing package from a list of alternatives
install_one_of() {
    local p
    for p in "$@"; do
        if pkg_installed "$p" || pkg_in_repo "$p"; then
            install_pkgs "$p"
            return 0
        fi
    done
    fail "None of these packages exist in the repository: $*"
    FAILED_PKGS+=("$* (not in repo)")
    return 1
}

# Safely create a runit service symlink
enable_service() {
    local svc="$1"
    if [[ ! -d "/etc/sv/${svc}" ]]; then
        fail "Service ${svc} does not exist in /etc/sv/ (package not installed?)"
        FAILED_ACTIONS+=("service ${svc}")
        return 1
    fi
    if [[ -L "/var/service/${svc}" ]]; then
        if [[ "$(readlink -f "/var/service/${svc}")" == "/etc/sv/${svc}" ]]; then
            info "Service ${svc} - already enabled"
            return 0
        fi
        rm -f "/var/service/${svc}"
    elif [[ -e "/var/service/${svc}" ]]; then
        fail "/var/service/${svc} exists and is not a symlink - skipping"
        FAILED_ACTIONS+=("service ${svc}")
        return 1
    fi
    if ln -s "/etc/sv/${svc}" "/var/service/${svc}"; then
        info "Enabled service: ${svc}"
    else
        fail "Failed to enable service: ${svc}"
        FAILED_ACTIONS+=("service ${svc}")
        return 1
    fi
}

# Symlink a config file (as per the Void documentation)
safe_link() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        if ln -sf "$src" "$dst"; then
            info "Linked: $(basename "$src") -> $dst"
        else
            fail "Failed to link $src -> $dst"
            FAILED_ACTIONS+=("link $(basename "$src")")
        fi
    else
        fail "Source file missing: $src"
        FAILED_ACTIONS+=("missing file $(basename "$src")")
    fi
}

# Switch networking from dhcpcd to NetworkManager (called right before reboot)
switch_to_networkmanager() {
    if [[ ! -d /etc/sv/NetworkManager ]]; then
        warn "NetworkManager is not installed - keeping dhcpcd"
        return 1
    fi
    rm -f /var/service/dhcpcd /var/service/wpa_supplicant
    sleep 2
    enable_service NetworkManager
}

echo -e "${CYAN}=============================================================${NC}"
echo -e "${CYAN}  Void Linux -> KDE Plasma | Ryzen 9 5950X / RX 6800 XT${NC}"
echo -e "${CYAN}=============================================================${NC}"
(( IS_VM )) && warn "Virtual machine detected - skipping hardware sensor modules"
[[ -n "$MAIN_USER" ]] && info "Detected user: $MAIN_USER" || warn "No regular user found (UID 1000)"

FREE_GB="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"
if [[ -n "$FREE_GB" && "$FREE_GB" -lt 12 ]]; then
    warn "Low disk space (${FREE_GB} GB free) - KDE needs about 8-12 GB"
fi

# =============================================================================
# 1. System update + nonfree repository
# =============================================================================
step "System update and nonfree repository installation"

if ! xbps-install -Syu xbps; then
    warn "Updating xbps itself failed - trying a full update"
fi

if xbps-install -Suy; then
    info "System updated"
else
    fail "Full system update failed - aborting"
    exit 1
fi

install_pkgs void-repo-nonfree
if xbps-install -Suy >>"$LOG" 2>&1; then
    info "Repositories synchronized (including nonfree)"
else
    warn "Synchronization after adding nonfree reported a warning (see $LOG)"
fi

# =============================================================================
# 2. AMD firmware
# =============================================================================
step "Installing firmware for AMD hardware"
install_pkgs linux-firmware-amd

# =============================================================================
# 3. GPU drivers
# =============================================================================
step "Installing GPU drivers (AMDGPU / Mesa / Vulkan / VA-API)"
install_pkgs xorg-minimal xf86-video-amdgpu mesa-dri mesa-vulkan-radeon mesa-vaapi vulkan-loader

# =============================================================================
# 4. System services
# =============================================================================
step "Installing system services (dbus, elogind, polkit)"
install_pkgs dbus elogind polkit

# =============================================================================
# 5. KDE Plasma and applications
# =============================================================================
step "Installing the KDE Plasma environment and basic applications"
install_one_of kde5 kde-plasma
install_one_of kde5-baseapps kde-baseapps
install_pkgs sddm konsole kate dolphin ark spectacle gwenview okular \
    kscreen plasma-pa plasma-nm NetworkManager \
    polkit-kde-agent xdg-desktop-portal-kde xdg-user-dirs \
    qt5-wayland qt6-wayland noto-fonts-ttf noto-fonts-emoji

# =============================================================================
# 6. Monitoring tools
# =============================================================================
step "Installing monitoring tools (CPU / GPU / X570 board)"
install_pkgs lm_sensors ksystemstats plasma-systemmonitor radeontop fastfetch

if command -v sensors-detect >/dev/null 2>&1; then
    echo -e "    ${CYAN}Unattended sensor configuration (sensors-detect)...${NC}"
    yes | sensors-detect >>"$LOG" 2>&1
    if [[ ${PIPESTATUS[1]} -eq 0 ]]; then
        info "sensors-detect finished"
    else
        fail "sensors-detect failed (see $LOG)"
        FAILED_ACTIONS+=("sensors-detect")
    fi

    if (( IS_VM )); then
        info "Skipped k10temp / it87 modules (virtual machine)"
    else
        mkdir -p /etc/modules-load.d
        MODFILE="/etc/modules-load.d/lm_sensors.conf"
        for mod in k10temp it87; do
            if ! modinfo "$mod" >/dev/null 2>&1; then
                warn "Module $mod is not available in this kernel - skipping"
                continue
            fi
            grep -qx "$mod" "$MODFILE" 2>/dev/null || echo "$mod" >> "$MODFILE"
            if modprobe "$mod" >>"$LOG" 2>&1; then
                info "Loaded sensor module: $mod"
            else
                warn "Module $mod failed to load (for it87 on Gigabyte boards the kernel parameter acpi_enforce_resources=lax may help)"
            fi
        done
    fi
else
    fail "sensors-detect command not available"
    FAILED_ACTIONS+=("sensors-detect")
fi

# =============================================================================
# 7. PipeWire
# =============================================================================
step "Installing and configuring PipeWire"
install_pkgs pipewire wireplumber alsa-pipewire pavucontrol

PW_CONF_DIR="/etc/pipewire/pipewire.conf.d"
ALSA_CONF_DIR="/etc/alsa/conf.d"
mkdir -p "$PW_CONF_DIR" "$ALSA_CONF_DIR" /etc/xdg/autostart

safe_link /usr/share/examples/wireplumber/10-wireplumber.conf "$PW_CONF_DIR/10-wireplumber.conf"
safe_link /usr/share/examples/pipewire/20-pipewire-pulse.conf "$PW_CONF_DIR/20-pipewire-pulse.conf"
safe_link /usr/share/applications/pipewire.desktop /etc/xdg/autostart/pipewire.desktop
safe_link /usr/share/alsa/alsa.conf.d/50-pipewire.conf "$ALSA_CONF_DIR/50-pipewire.conf"
safe_link /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf "$ALSA_CONF_DIR/99-pipewire-default.conf"

# =============================================================================
# 8. Runit services and user groups
# =============================================================================
step "Enabling Runit services (dbus, elogind, polkitd) and configuring the user"
mkdir -p /var/service
for svc in dbus elogind polkitd; do
    enable_service "$svc"
done

if [[ -n "$MAIN_USER" ]] && id "$MAIN_USER" >/dev/null 2>&1; then
    for grp in network audio video; do
        if getent group "$grp" >/dev/null; then
            if usermod -aG "$grp" "$MAIN_USER" >>"$LOG" 2>&1; then
                info "Added $MAIN_USER to group: $grp"
            else
                warn "Failed to add $MAIN_USER to group $grp"
            fi
        fi
    done
fi

# =============================================================================
# 9. Cleanup: initramfs with firmware, package cache
# =============================================================================
step "Final cleanup (initramfs, package cache)"
echo -e "    ${CYAN}Rebuilding initramfs (xbps-reconfigure -fa) - this may take a few minutes...${NC}"
if xbps-reconfigure -fa >>"$LOG" 2>&1; then
    info "Rebuilt initramfs and reconfigured packages"
else
    warn "xbps-reconfigure reported an error (see $LOG)"
fi
if xbps-remove -yO >>"$LOG" 2>&1; then
    info "Package cache cleaned"
fi

# =============================================================================
# Summary
# =============================================================================
echo -e "\n${CYAN}=============================================================${NC}"
if [[ ${#FAILED_PKGS[@]} -eq 0 && ${#FAILED_ACTIONS[@]} -eq 0 ]]; then
    echo -e "${GREEN}Installation completed successfully - no errors.${NC}"
else
    echo -e "${YELLOW}Installation finished with problems:${NC}"
    if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
        echo -e "${RED}  Packages that failed to install:${NC}"
        for p in "${FAILED_PKGS[@]}"; do echo -e "    - $p"; done
    fi
    if [[ ${#FAILED_ACTIONS[@]} -gt 0 ]]; then
        echo -e "${RED}  Actions that failed:${NC}"
        for a in "${FAILED_ACTIONS[@]}"; do echo -e "    - $a"; done
    fi
    echo -e "  Details: ${LOG}"
fi
echo -e "${CYAN}=============================================================${NC}"

# =============================================================================
# SDDM, networking and reboot
# =============================================================================
DO_REBOOT=0
if (( AUTO_YES )); then
    DO_REBOOT=1
elif [[ -t 0 ]]; then
    read -r -p "$(echo -e "${YELLOW}Enable SDDM, switch networking to NetworkManager and reboot now? [Y/n]: ${NC}")" answer
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[YyTt]$ ]] && DO_REBOOT=1
fi

if (( DO_REBOOT )); then
    (( SWITCH_NM )) && switch_to_networkmanager
    enable_service "sddm"
    echo -e "${GREEN}Rebooting the system...${NC}"
    sleep 2
    reboot
else
    echo -e "${YELLOW}SDDM and NetworkManager have not been enabled yet (to avoid interrupting the session and network).${NC}"
    echo -e "${GREEN}Run the following manually before rebooting:${NC}"
    echo -e "  rm -f /var/service/dhcpcd /var/service/wpa_supplicant"
    echo -e "  ln -s /etc/sv/NetworkManager /var/service/"
    echo -e "  ln -s /etc/sv/sddm /var/service/"
    echo -e "  reboot"
fi
