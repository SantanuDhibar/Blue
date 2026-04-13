#!/bin/bash
# =========================================
# Standalone Host Capture Installer
# Installs VPN Host Capture feature WITHOUT
# requiring the full VPN script setup.
#
# What it does:
#   - Installs capture-host script
#   - Installs menu-captured-hosts script
#   - Enables proxy_capture logging in nginx
#     so the Host header and SNI are logged
#     for every VPN client connection
#   - Installs and starts host-capture.service
#     which runs capture-host every 60 seconds
#
# Requirements:
#   - Debian/Ubuntu Linux with root access
#   - Existing nginx + xray/v2ray VPN server
#
# Usage:
#   wget -qO install-host-capture.sh https://raw.githubusercontent.com/SantanuDhibar/Blue/main/install-host-capture.sh
#   chmod +x install-host-capture.sh && ./install-host-capture.sh
# =========================================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export CYAN='\033[0;36m'
export NC='\033[0m'

export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

REPO_URL="raw.githubusercontent.com/SantanuDhibar/Blue/main"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "\E[44;1;39m          ⇱ VPN HOST CAPTURE - STANDALONE INSTALLER ⇲       \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e ""
echo -e " ${INFO} When clients connect to your VPN server, this feature"
echo -e " ${INFO} captures the hosts they used to connect:"
echo -e ""
echo -e "   ${GREEN}Host-Header${NC} — HTTP Host header sent by the client"
echo -e "   ${CYAN}SNI${NC}         — TLS Server Name (from handshake)"
echo -e "   ${GREEN}Xray-Dest${NC}  — destination accessed through the VPN"
echo -e ""
echo -e " ${INFO} nginx logs the Host+SNI per connection (proxy_capture format)."
echo -e " ${INFO} host-capture.service runs every 60s to process new connections."
echo -e ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo ""
read -p " Proceed with installation? (y/n): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo -e "\n ${INFO} Installation cancelled."; exit 0; }

echo ""

# Create directories
echo -ne " ${INFO} Creating directories..."
mkdir -p /etc/myvpn 2>/dev/null
echo -e " ${OKEY}"

# Initialize data files
echo -ne " ${INFO} Initializing data files..."
touch /etc/myvpn/hosts.log 2>/dev/null
touch /etc/myvpn/.capture-state 2>/dev/null
echo -e " ${OKEY}"

# Install capture-host script
echo -ne " ${INFO} Installing capture-host..."
if wget -q -O /usr/bin/capture-host "https://${REPO_URL}/capture-host.sh"; then
    chmod +x /usr/bin/capture-host
    echo -e " ${OKEY}"
else
    echo -e " ${EROR} Failed to download capture-host"
    exit 1
fi

# Install menu-captured-hosts script
echo -ne " ${INFO} Installing menu-captured-hosts..."
if wget -q -O /usr/bin/menu-captured-hosts "https://${REPO_URL}/menu-captured-hosts.sh"; then
    chmod +x /usr/bin/menu-captured-hosts
    echo -e " ${OKEY}"
else
    echo -e " ${EROR} Failed to download menu-captured-hosts"
    exit 1
fi

# Enable proxy_capture logging in nginx server block
echo -ne " ${INFO} Configuring nginx proxy_capture logging..."
if [ -f /etc/nginx/conf.d/xray.conf ]; then
    if ! grep -q "proxy-capture.log" /etc/nginx/conf.d/xray.conf; then
        sed -i 's|root /home/vps/public_html;[[:space:]]*$|root /home/vps/public_html;\n             access_log /var/log/nginx/proxy-capture.log proxy_capture;|' \
            /etc/nginx/conf.d/xray.conf 2>/dev/null
        if nginx -t 2>/dev/null; then
            systemctl reload nginx 2>/dev/null
            echo -e " ${OKEY}"
        else
            echo -e " ${EROR} nginx config test failed; please add proxy_capture log manually"
        fi
    else
        echo -e " ${OKEY} (already configured)"
    fi
else
    echo -e " ${YELLOW}[SKIP]${NC} /etc/nginx/conf.d/xray.conf not found"
fi

# Install and start host-capture service
echo -ne " ${INFO} Installing host-capture service..."
if wget -q -O /etc/systemd/system/host-capture.service "https://${REPO_URL}/host-capture.service"; then
    systemctl daemon-reload
    systemctl enable host-capture 2>/dev/null
    systemctl start host-capture 2>/dev/null
    if systemctl is-active --quiet host-capture 2>/dev/null; then
        echo -e " ${OKEY}"
    else
        echo -e " ${YELLOW}[WARN]${NC} service installed but not started; check: systemctl status host-capture"
    fi
else
    echo -e " ${EROR} Failed to download host-capture.service"
    exit 1
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e " ${OKEY} VPN Host Capture installed successfully!"
echo -e ""
echo -e " ${INFO} Usage:"
echo -e "   ${CYAN}menu-captured-hosts${NC}  — open the host capture menu"
echo -e "   ${CYAN}capture-host${NC}         — run capture once manually"
echo -e ""
echo -e " ${INFO} Hosts are saved to: /etc/myvpn/hosts.log"
echo -e " ${INFO} Service runs every 60 seconds automatically."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo ""
