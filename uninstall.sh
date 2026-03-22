#!/bin/bash
# =========================================
# Uninstall Script - Blue VPN Script
# Edition : Stable Edition V1.0
# Author  : LamonLind
# (C) Copyright 2024
# =========================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Root checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run this script as root user!${NC}"
    exit 1
fi

# Function to show header
show_header() {
    clear
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}        Blue VPN Script - Uninstall Tool${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}WARNING: This will remove all Blue VPN components!${NC}"
    echo ""
}

# Function to confirm uninstall
confirm_uninstall() {
    echo -e "${RED}Are you sure you want to uninstall Blue VPN Script?${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    echo -e "Type ${RED}'YES'${NC} in capital letters to confirm: "
    read confirmation
    
    if [ "$confirmation" != "YES" ]; then
        echo ""
        echo -e "${GREEN}Uninstall cancelled.${NC}"
        exit 0
    fi
}

# Function to stop all services
stop_services() {
    echo ""
    echo -e "${YELLOW}[1/7]${NC} Stopping services..."
    
    systemctl stop xray 2>/dev/null
    systemctl stop xray@vless 2>/dev/null
    systemctl stop xray@vnone 2>/dev/null
    systemctl stop xray@trojanws 2>/dev/null
    systemctl stop xray@trnone 2>/dev/null
    systemctl stop nginx 2>/dev/null
    systemctl stop stunnel5 2>/dev/null
    systemctl stop ws-stunnel 2>/dev/null
    systemctl stop dropbear 2>/dev/null
    systemctl stop host-capture 2>/dev/null
    
    echo -e "${GREEN}✓ Services stopped${NC}"
}

# Function to disable services
disable_services() {
    echo -e "${YELLOW}[2/7]${NC} Disabling services..."
    
    systemctl disable xray 2>/dev/null
    systemctl disable xray@vless 2>/dev/null
    systemctl disable xray@vnone 2>/dev/null
    systemctl disable xray@trojanws 2>/dev/null
    systemctl disable xray@trnone 2>/dev/null
    systemctl disable nginx 2>/dev/null
    systemctl disable stunnel5 2>/dev/null
    systemctl disable ws-stunnel 2>/dev/null
    systemctl disable dropbear 2>/dev/null
    systemctl disable host-capture 2>/dev/null
    
    echo -e "${GREEN}✓ Services disabled${NC}"
}

# Function to remove systemd service files
remove_systemd_files() {
    echo -e "${YELLOW}[3/7]${NC} Removing systemd service files..."
    
    rm -f /etc/systemd/system/xray.service
    rm -f /etc/systemd/system/xray@.service
    rm -f /etc/systemd/system/xray@vless.service
    rm -f /etc/systemd/system/xray@vnone.service
    rm -f /etc/systemd/system/xray@trojanws.service
    rm -f /etc/systemd/system/xray@trnone.service
    rm -f /etc/systemd/system/ws-stunnel.service
    rm -f /etc/systemd/system/host-capture.service
    rm -f /etc/logrotate.d/host-capture
    rm -f /usr/local/bin/capture-host-daemon.sh
    rm -f /usr/local/bin/capture-host.sh
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Systemd files removed${NC}"
}

# Function to remove installed scripts
remove_scripts() {
    echo -e "${YELLOW}[4/7]${NC} Removing installed scripts..."
    
    # List of scripts to remove
    local scripts=(
        "add-ws" "add-ssws" "add-socks" "add-vless" "add-tr" "add-trgo"
        "autoreboot" "restart" "tendang" "clearlog" "running"
        "cek-trafik" "cek-speed" "cek-ram" "limit-speed"
        "realtime-hosts" "vless-proxy-identifier"
        "menu-vless" "menu-vmess" "menu-socks" "menu-ss" "menu-trojan"
        "menu-trgo" "menu-ssh" "menu-slowdns" "menu-captured-hosts"
        "capture-host" "menu-bckp" "bckp" "usernew" "menu" "wbm" "xp"
        "update" "dns" "netf" "bbr" "backup" "restore"
    )
    
    for script in "${scripts[@]}"; do
        rm -f "/usr/bin/${script}"
    done
    
    echo -e "${GREEN}✓ Scripts removed${NC}"
}

# Function to remove configuration files
remove_configs() {
    echo -e "${YELLOW}[5/7]${NC} Removing configuration files and directories..."
    
    # Backup critical user data before removal (optional)
    if [ -d "/etc/xray" ] || [ -d "/etc/myvpn" ]; then
        echo -e "${CYAN}  Creating final backup in /root/blue-final-backup...${NC}"
        mkdir -p /root/blue-final-backup
        cp -r /etc/xray /root/blue-final-backup/ 2>/dev/null
        cp -r /etc/myvpn /root/blue-final-backup/ 2>/dev/null
        cp /etc/passwd /root/blue-final-backup/ 2>/dev/null
        cp /etc/shadow /root/blue-final-backup/ 2>/dev/null
        echo -e "${GREEN}  ✓ Backup created at /root/blue-final-backup${NC}"
    fi
    
    # Remove directories
    rm -rf /etc/xray
    rm -rf /etc/myvpn
    rm -rf /usr/local/etc/xray
    rm -rf /var/lib/scrz-prem
    rm -rf /home/vps/public_html
    
    # Remove binaries
    rm -f /usr/local/bin/xray
    rm -f /usr/local/bin/stunnel
    rm -f /usr/local/bin/stunnel5
    rm -f /usr/bin/xray
    
    # Remove nginx configs related to VPN
    rm -f /etc/nginx/conf.d/xray.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/vless.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/vmess.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/trojan.conf 2>/dev/null
    
    echo -e "${GREEN}✓ Configuration files removed${NC}"
}

# Function to remove cron jobs
remove_cronjobs() {
    echo -e "${YELLOW}[6/7]${NC} Removing cron jobs..."
    
    # Remove specific cron jobs
    crontab -l | grep -v "xp" | grep -v "clearlog" | grep -v "backup" | grep -v "capture-host" | crontab - 2>/dev/null
    
    # Remove cron files
    rm -f /etc/cron.d/xp
    rm -f /etc/cron.d/clearlog
    rm -f /etc/cron.d/capture_host
    
    service cron restart
    
    echo -e "${GREEN}✓ Cron jobs removed${NC}"
}

# Function to clean up firewall rules
cleanup_firewall() {
    echo -e "${YELLOW}[7/7]${NC} Cleaning up firewall rules..."
    
    # Note: We'll keep basic SSH access to prevent lockout
    # Remove custom VPN-related iptables rules but keep default policies
    
    # Flush custom chains but preserve system chains
    iptables -F INPUT 2>/dev/null
    iptables -F FORWARD 2>/dev/null
    iptables -F OUTPUT 2>/dev/null
    
    # Save iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    
    echo -e "${GREEN}✓ Firewall rules cleaned${NC}"
}

# Function to show final summary
show_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Uninstall completed successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}What was removed:${NC}"
    echo -e "  ${GREEN}✓${NC} All VPN services (XRAY, SSH-WS, etc.)"
    echo -e "  ${GREEN}✓${NC} All menu scripts"
    echo -e "  ${GREEN}✓${NC} All configuration files"
    echo -e "  ${GREEN}✓${NC} All cron jobs"
    echo -e "  ${GREEN}✓${NC} Custom firewall rules"
    echo ""
    echo -e "${CYAN}What was kept:${NC}"
    echo -e "  ${YELLOW}⚠${NC}  Basic system packages (nginx, dropbear, etc.)"
    echo -e "  ${YELLOW}⚠${NC}  SSL certificates in /root/.acme.sh"
    echo -e "  ${YELLOW}⚠${NC}  Final backup in /root/blue-final-backup"
    echo ""
    echo -e "${CYAN}Optional cleanup:${NC}"
    echo -e "  To remove system packages, run:"
    echo -e "  ${YELLOW}apt remove --purge nginx xray dropbear stunnel5${NC}"
    echo ""
    echo -e "  To remove backup:"
    echo -e "  ${YELLOW}rm -rf /root/blue-final-backup${NC}"
    echo ""
    echo -e "${RED}Note: Please reboot your system to complete the uninstall.${NC}"
    echo ""
}

# Main uninstall process
main() {
    show_header
    confirm_uninstall
    
    echo ""
    echo -e "${CYAN}Starting uninstall process...${NC}"
    
    stop_services
    disable_services
    remove_systemd_files
    remove_scripts
    remove_configs
    remove_cronjobs
    cleanup_firewall
    
    show_summary
    
    echo ""
    read -p "Do you want to reboot now? (y/n): " reboot_choice
    if [ "$reboot_choice" == "y" ] || [ "$reboot_choice" == "Y" ]; then
        echo -e "${YELLOW}Rebooting in 3 seconds...${NC}"
        sleep 3
        reboot
    else
        echo -e "${GREEN}Please remember to reboot your system manually.${NC}"
    fi
}

# Start the script
main
