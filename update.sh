#!/bin/bash
# =========================================
# Update Script - Blue VPN Script
# Edition : Stable Edition V1.0
# Author  : LamonLind
# (C) Copyright 2024
# =========================================
#
# Changelog:
# - Fixed bandwidth quota tracking: Now tracks upload normally and download/3 for accuracy
#   Root cause: Only downlink has 3x overcounting bug from multiple inbound configs
#   Fix: Track uplink (normal) + downlink/3 for accurate total bandwidth measurement
#   Enhancement: Now displays upload and download traffic separately for better visibility
#   Formula: uplink + (downlink / 3)
#   The /3 division only applies to downlink due to ws/grpc/xhttp aggregation
#   Affected files: xray-quota-manager, xray-traffic-monitor, menu-bandwidth.sh
#
# - Enhanced host capture system: Now captures more hostname patterns
#   Added patterns: tcp: prefixed hosts (tcp:bug.cloudflare.com:443)
#   Added patterns: ws:// and wss:// URL hosts
#   Added patterns: Bug hosts, fronting hosts, CDN hosts
#   Enhanced: SNI capture with tls_sni pattern
#   Enhanced: Proxy host capture with bug_host pattern
#   Affected files: capture-host.sh
#
# - Added user quota reset feature: Reset bandwidth usage and re-enable users
#   New script: reset-user-quota.sh for interactive quota reset
#   Enhanced: xray-quota-manager with 'reset' command
#   Enhanced: menu-bandwidth.sh with reset option
#   Feature: Automatic Xray service restart after reset
#   Feature: Statistics clearing via Xray API
#   Affected files: xray-quota-manager, menu-bandwidth.sh, reset-user-quota.sh
#
# - Added host capture service daemon for continuous monitoring
#   New service: host-capture.service (systemd service)
#   New daemon: capture-host-daemon.sh (continuous loop with 2s interval)
#   Feature: Full root access for comprehensive log monitoring
#   Feature: Automatic startup and restart on failure
#   Affected files: host-capture.service, capture-host-daemon.sh
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

# Export GitHub repository URL
REPO_URL="raw.githubusercontent.com/LamonLind/Blue/main"

# Self-update function
self_update() {
    echo -e "${YELLOW}[INFO]${NC} Checking for update script updates..."
    
    # Download latest update.sh to temporary location
    local temp_update="/tmp/update.sh.new"
    if wget -q -O "$temp_update" "https://${REPO_URL}/update.sh"; then
        # Check if the downloaded file is different
        if ! cmp -s "$temp_update" "/usr/bin/update" 2>/dev/null && ! cmp -s "$temp_update" "$0" 2>/dev/null; then
            echo -e "${GREEN}[INFO]${NC} Update script has new version, updating..."
            chmod +x "$temp_update"
            cp "$temp_update" "/usr/bin/update"
            rm -f "$temp_update"
            echo -e "${GREEN}[DONE]${NC} Update script updated! Restarting with new version..."
            exec /usr/bin/update "$@"
        else
            echo -e "${GREEN}[INFO]${NC} Update script is already up to date."
            rm -f "$temp_update"
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} Could not check for update script updates."
        rm -f "$temp_update" 2>/dev/null
    fi
}

# Function to show header
show_header() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}           Blue VPN Script - Update Tool${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to remove deprecated/old files
remove_deprecated() {
    echo -e "${YELLOW}[INFO]${NC} Checking for deprecated files..."
    
    # List of deprecated files to remove
    local deprecated_files=(
        # Add any old/deprecated scripts here
        # Example: "/usr/bin/old-script"
    )
    
    local removed_count=0
    for file in "${deprecated_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${YELLOW}[REMOVE]${NC} Removing deprecated file: $file"
            rm -f "$file"
            ((removed_count++))
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        echo -e "${GREEN}[INFO]${NC} Removed $removed_count deprecated file(s)"
    else
        echo -e "${GREEN}[INFO]${NC} No deprecated files found"
    fi
}

# Function to install/update required services
manage_services() {
    echo -e "${YELLOW}[INFO]${NC} Managing system services..."
    
    # Download and install xray-quota-monitor service file
    echo -ne "${CYAN}Updating xray-quota-monitor.service...${NC}"
    if wget -q -O /etc/systemd/system/xray-quota-monitor.service "https://${REPO_URL}/xray-quota-monitor.service"; then
        echo -e " ${GREEN}✓${NC}"
    else
        echo -e " ${RED}✗${NC}"
    fi
    
    # Download and install host-capture service file (runtime VPN host capture)
    echo -ne "${CYAN}Updating host-capture.service...${NC}"
    if wget -q -O /etc/systemd/system/host-capture.service "https://${REPO_URL}/host-capture.service"; then
        echo -e " ${GREEN}✓${NC}"
    else
        echo -e " ${RED}✗${NC}"
    fi
    
    # Remove old daemon artifacts no longer needed
    rm -f /usr/local/bin/capture-host-daemon.sh
    rm -f /etc/cron.d/capture_host
    rm -f /etc/logrotate.d/host-capture

    # Ensure hosts file and state file exist
    mkdir -p /etc/myvpn 2>/dev/null
    touch /etc/myvpn/hosts.log 2>/dev/null
    touch /etc/myvpn/.capture-state 2>/dev/null

    # Apply nginx proxy_capture logging to existing xray.conf if not already there
    if [ -f /etc/nginx/conf.d/xray.conf ]; then
        if ! grep -q "proxy-capture.log" /etc/nginx/conf.d/xray.conf; then
            echo -e "${YELLOW}[INFO]${NC} Adding proxy_capture logging to nginx..."
            sed -i 's|root /home/vps/public_html;[[:space:]]*$|root /home/vps/public_html;\n             access_log /var/log/nginx/proxy-capture.log proxy_capture;|' \
                /etc/nginx/conf.d/xray.conf 2>/dev/null
            nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null && \
                echo -e "${GREEN}[INFO]${NC} nginx reloaded with proxy_capture logging" || \
                echo -e "${RED}[WARN]${NC} nginx reload failed; check config manually"
        fi
    fi

    # Ensure host-capture service is running
    systemctl daemon-reload
    systemctl enable host-capture 2>/dev/null
    if ! systemctl is-active --quiet host-capture 2>/dev/null; then
        systemctl start host-capture 2>/dev/null
        echo -e "${GREEN}[INFO]${NC} Started host-capture service"
    else
        systemctl restart host-capture 2>/dev/null
        echo -e "${GREEN}[INFO]${NC} Restarted host-capture service"
    fi
    
    # Ensure xray-quota-monitor service is properly configured
    if [ -f /etc/systemd/system/xray-quota-monitor.service ]; then
        systemctl daemon-reload
        systemctl enable xray-quota-monitor 2>/dev/null
        systemctl restart xray-quota-monitor 2>/dev/null
        echo -e "${GREEN}[INFO]${NC} Restarted xray-quota-monitor service"
    fi
    
    echo -e "${GREEN}[INFO]${NC} Services managed successfully"
}

# Function to create necessary directories
ensure_directories() {
    local dirs=(
        "/etc/myvpn"
        "/etc/myvpn/usage"
        "/etc/myvpn/blocked_users"
        "/var/log"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
        fi
    done
}

# Function to update all scripts
update_all_scripts() {
    echo -e "${YELLOW}[INFO]${NC} Updating all scripts..."
    
    # Ensure necessary directories exist
    ensure_directories
    
    # List of all scripts to update
    local scripts=(
        "add-ws" "add-ssws" "add-socks" "add-vless" "add-tr" "add-trgo"
        "autoreboot" "restart" "tendang" "clearlog" "running"
        "cek-trafik" "cek-speed" "cek-ram" "limit-speed"
        "realtime-hosts" "reset-user-quota"
        "menu-vless" "menu-vmess" "menu-socks" "menu-ss" "menu-trojan"
        "menu-trgo" "menu-ssh" "menu-slowdns" "menu-captured-hosts" "menu-bandwidth"
        "capture-host" "menu-bckp" "usernew" "menu" "wbm" "xp"
        "dns" "netf" "bbr" "backup" "restore"
        "xray-quota-manager" "xray-traffic-monitor"
    )
    
    local success_count=0
    local fail_count=0
    
    for script in "${scripts[@]}"; do
        echo -ne "${CYAN}Updating ${script}...${NC}"
        
        # Determine the correct filename with extension
        local filename="${script}.sh"
        if [ "$script" == "menu" ]; then
            filename="menu4.sh"
        elif [ "$script" == "cek-speed" ]; then
            filename="speedtest_cli.py"
        elif [ "$script" == "xray-quota-manager" ] || [ "$script" == "xray-traffic-monitor" ]; then
            filename="${script}"
        fi
        
        if wget -q -O "/usr/bin/${script}" "https://${REPO_URL}/${filename}"; then
            chmod +x "/usr/bin/${script}"
            echo -e " ${GREEN}✓${NC}"
            ((success_count++))
        else
            echo -e " ${RED}✗${NC}"
            ((fail_count++))
        fi
    done
    
    # Remove deprecated files
    remove_deprecated
    
    # Manage services
    manage_services
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Update Summary:${NC}"
    echo -e "  ${GREEN}Success: ${success_count}${NC}"
    echo -e "  ${RED}Failed: ${fail_count}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ $success_count -gt 0 ]; then
        echo -e "${GREEN}[INFO]${NC} All necessary features installed and services configured!"
    fi
}

# Function to update specific component
update_component() {
    echo ""
    echo -e "${CYAN}Select component to update:${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} SSH/WS Scripts"
    echo -e "  ${CYAN}[2]${NC} XRAY Scripts (VMESS, VLESS, Trojan, Shadowsocks)"
    echo -e "  ${CYAN}[3]${NC} Menu Scripts"
    echo -e "  ${CYAN}[4]${NC} System Utilities"
    echo -e "  ${CYAN}[5]${NC} Update ALL Components"
    echo -e "  ${CYAN}[0]${NC} Back to Menu"
    echo ""
    read -p "Select option: " component_choice
    
    case $component_choice in
        1)
            echo -e "${YELLOW}[INFO]${NC} Updating SSH/WS scripts..."
            wget -q -O /usr/bin/usernew "https://${REPO_URL}/usernew.sh" && chmod +x /usr/bin/usernew
            wget -q -O /usr/bin/menu-ssh "https://${REPO_URL}/menu-ssh.sh" && chmod +x /usr/bin/menu-ssh
            wget -q -O /usr/bin/tendang "https://${REPO_URL}/tendang.sh" && chmod +x /usr/bin/tendang
            echo -e "${GREEN}[DONE]${NC} SSH/WS scripts updated!"
            ;;
        2)
            echo -e "${YELLOW}[INFO]${NC} Updating XRAY scripts..."
            wget -q -O /usr/bin/add-ws "https://${REPO_URL}/add-ws.sh" && chmod +x /usr/bin/add-ws
            wget -q -O /usr/bin/add-vless "https://${REPO_URL}/add-vless.sh" && chmod +x /usr/bin/add-vless
            wget -q -O /usr/bin/add-tr "https://${REPO_URL}/add-tr.sh" && chmod +x /usr/bin/add-tr
            wget -q -O /usr/bin/add-ssws "https://${REPO_URL}/add-ssws.sh" && chmod +x /usr/bin/add-ssws
            wget -q -O /usr/bin/menu-vmess "https://${REPO_URL}/menu-vmess.sh" && chmod +x /usr/bin/menu-vmess
            wget -q -O /usr/bin/menu-vless "https://${REPO_URL}/menu-vless.sh" && chmod +x /usr/bin/menu-vless
            wget -q -O /usr/bin/menu-trojan "https://${REPO_URL}/menu-trojan.sh" && chmod +x /usr/bin/menu-trojan
            wget -q -O /usr/bin/menu-ss "https://${REPO_URL}/menu-ss.sh" && chmod +x /usr/bin/menu-ss
            echo -e "${GREEN}[DONE]${NC} XRAY scripts updated!"
            ;;
        3)
            echo -e "${YELLOW}[INFO]${NC} Updating menu scripts..."
            wget -q -O /usr/bin/menu "https://${REPO_URL}/menu4.sh" && chmod +x /usr/bin/menu
            echo -e "${GREEN}[DONE]${NC} Menu scripts updated!"
            ;;
        4)
            echo -e "${YELLOW}[INFO]${NC} Updating system utilities..."
            wget -q -O /usr/bin/restart "https://${REPO_URL}/restart.sh" && chmod +x /usr/bin/restart
            wget -q -O /usr/bin/autoreboot "https://${REPO_URL}/autoreboot.sh" && chmod +x /usr/bin/autoreboot
            wget -q -O /usr/bin/clearlog "https://${REPO_URL}/clearlog.sh" && chmod +x /usr/bin/clearlog
            wget -q -O /usr/bin/running "https://${REPO_URL}/running.sh" && chmod +x /usr/bin/running
            wget -q -O /usr/bin/cek-trafik "https://${REPO_URL}/cek-trafik.sh" && chmod +x /usr/bin/cek-trafik
            wget -q -O /usr/bin/xp "https://${REPO_URL}/xp.sh" && chmod +x /usr/bin/xp
            wget -q -O /usr/bin/backup "https://${REPO_URL}/backup.sh" && chmod +x /usr/bin/backup
            wget -q -O /usr/bin/restore "https://${REPO_URL}/restore.sh" && chmod +x /usr/bin/restore
            wget -q -O /usr/bin/xray-quota-manager "https://${REPO_URL}/xray-quota-manager" && chmod +x /usr/bin/xray-quota-manager
            wget -q -O /usr/bin/xray-traffic-monitor "https://${REPO_URL}/xray-traffic-monitor" && chmod +x /usr/bin/xray-traffic-monitor
            wget -q -O /usr/bin/capture-host "https://${REPO_URL}/capture-host.sh" && chmod +x /usr/bin/capture-host
            wget -q -O /usr/local/bin/capture-host.sh "https://${REPO_URL}/capture-host.sh" && chmod +x /usr/local/bin/capture-host.sh
            wget -q -O /usr/bin/realtime-hosts "https://${REPO_URL}/realtime-hosts.sh" && chmod +x /usr/bin/realtime-hosts
            wget -q -O /usr/bin/menu-captured-hosts "https://${REPO_URL}/menu-captured-hosts.sh" && chmod +x /usr/bin/menu-captured-hosts
            wget -q -O /usr/bin/menu-bandwidth "https://${REPO_URL}/menu-bandwidth.sh" && chmod +x /usr/bin/menu-bandwidth
            wget -q -O /usr/bin/reset-user-quota "https://${REPO_URL}/reset-user-quota.sh" && chmod +x /usr/bin/reset-user-quota
            # Manage services and directories
            ensure_directories
            manage_services
            echo -e "${GREEN}[DONE]${NC} System utilities updated!"
            ;;
        5)
            update_all_scripts
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Invalid option!"
            ;;
    esac
    
    if [ "$component_choice" != "0" ] && [ "$component_choice" != "5" ]; then
        echo ""
        echo -e "${GREEN}Component update completed!${NC}"
    fi
}

# Main menu
main_menu() {
    # Self-update first
    self_update
    
    show_header
    echo -e "${CYAN}Select update mode:${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Update All Scripts (Recommended)"
    echo -e "  ${CYAN}[2]${NC} Update Specific Component"
    echo -e "  ${CYAN}[3]${NC} Check for Updates"
    echo -e "  ${CYAN}[0]${NC} Exit"
    echo ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            show_header
            update_all_scripts
            ;;
        2)
            show_header
            update_component
            ;;
        3)
            show_header
            echo -e "${YELLOW}[INFO]${NC} Checking for updates..."
            local_ver=$(cat /home/.ver 2>/dev/null || echo "Unknown")
            remote_ver=$(curl -s https://${REPO_URL}/test/versions || echo "Unknown")
            echo ""
            echo -e "  Current Version : ${CYAN}${local_ver}${NC}"
            echo -e "  Latest Version  : ${GREEN}${remote_ver}${NC}"
            echo ""
            if [ "$local_ver" != "$remote_ver" ] && [ "$remote_ver" != "Unknown" ]; then
                echo -e "${YELLOW}[INFO]${NC} New version available!"
                echo ""
                read -p "Do you want to update now? (y/n): " update_now
                if [ "$update_now" == "y" ] || [ "$update_now" == "Y" ]; then
                    update_all_scripts
                    echo "$remote_ver" > /home/.ver
                fi
            else
                echo -e "${GREEN}[INFO]${NC} You are running the latest version!"
            fi
            ;;
        0)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Invalid option!"
            sleep 2
            main_menu
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    main_menu
}

# Start the script
main_menu
