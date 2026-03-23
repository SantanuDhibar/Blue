#!/bin/bash
# =========================================
# Host Capture Menu
# Shows hosts captured from:
#   - Runtime: actual client connections (Host header + SNI via nginx, xray access log)
#   - Config:  hosts from config files and client link files
# =========================================

BICyan='\033[1;96m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIWhite='\033[1;97m'
BIRed='\033[1;91m'
NC='\e[0m'

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export CYAN='\033[0;36m'
export NC='\033[0m'

export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

HOSTS_FILE="/etc/myvpn/hosts.log"
DOMAIN_FILE="/etc/xray/domain"

get_main_domain() {
    [ -f "$DOMAIN_FILE" ] && cat "$DOMAIN_FILE" || echo "N/A"
}

get_vps_ip() {
    [ -f /etc/myipvps ] && cat /etc/myipvps && return
    timeout 5 curl -s https://ipinfo.io/ip 2>/dev/null || echo "N/A"
}

service_status() {
    if systemctl is-active --quiet host-capture 2>/dev/null; then
        echo -e "${BIGreen}RUNNING${NC}"
    else
        echo -e "${BIRed}STOPPED${NC}"
    fi
}

# ================================================================
# Display captured hosts
# ================================================================
display_hosts() {
    clear
    local MAIN_DOMAIN VPS_IP
    MAIN_DOMAIN=$(get_main_domain)
    VPS_IP=$(get_vps_ip)

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                     ⇱ VPN HOST CAPTURE RESULTS ⇲                            \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${BICyan}Server Domain  : ${NC}${BIYellow}${MAIN_DOMAIN}${NC}"
    echo -e " ${BICyan}Server IP      : ${NC}${BIYellow}${VPS_IP}${NC}"
    echo -e " ${BICyan}Capture Service: ${NC}$(service_status)"
    echo -e ""

    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e " ${BIYellow}No hosts captured yet.${NC}"
        echo -e " ${INFO} Run capture-host or start the host-capture service."
    else
        local runtime_count=0 config_count=0

        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        echo -e " ${BIGreen}▌ RUNTIME CAPTURED${NC} — hosts used by clients when they connected"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        echo -e " ${BIWhite}HOST                          TYPE          CLIENT IP             FIRST SEEN${NC}"
        echo -e ""

        # Read hosts file once and filter by type using grep for efficiency
        while IFS='|' read -r host type source_ip timestamp; do
            local color
            case "$type" in
                Host-Header)    color="$BIYellow" ;;
                SNI)            color="$BICyan"   ;;
                Xray-Dest)      color="$BIGreen"  ;;
                Proxy-Host)     color="$BIWhite"  ;;
                Target-Addr)    color="$BIRed"    ;;
                CDN-Proxy)      color="$BIRed"    ;;
                Fwd-Host)       color="$BIGreen"  ;;
                CF-Client)      color="$BICyan"   ;;
                Vercel-Client)  color="$BICyan"   ;;
                NF-Client)      color="$BICyan"   ;;
                Render-Client)  color="$BICyan"   ;;
                *)              continue           ;;
            esac
            printf " ${color}%-28s${NC}  ${BIWhite}%-14s${NC}  %-20s  ${BICyan}%s${NC}\n" \
                "$host" "$type" "${source_ip:0:20}" "$timestamp"
            ((runtime_count++))
        done < <(grep -E '\|(Host-Header|SNI|Xray-Dest|Proxy-Host|Target-Addr|CDN-Proxy|Fwd-Host|CF-Client|Vercel-Client|NF-Client|Render-Client)\|' "$HOSTS_FILE" 2>/dev/null)

        [ "$runtime_count" -eq 0 ] && echo -e " ${BIYellow}  (none yet — clients connect to start capturing)${NC}"

        echo -e ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        echo -e " ${BICyan}▌ CONFIG BASED${NC} — hosts from config files and client link files"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        echo -e " ${BIWhite}HOST                          TYPE          SOURCE                FOUND${NC}"
        echo -e ""

        while IFS='|' read -r host type source_ip timestamp; do
            local color label
            case "$type" in
                Config-SNI)  color="$BICyan";   label="SNI"     ;;
                Config-Host) color="$BIYellow"; label="Host"    ;;
                Config-Addr) color="$BIGreen";  label="Address" ;;
                *)           continue                            ;;
            esac
            printf " ${color}%-28s${NC}  ${BIWhite}%-12s${NC}  %-20s  ${BICyan}%s${NC}\n" \
                "$host" "$label" "${source_ip:0:20}" "$timestamp"
            ((config_count++))
        done < <(grep -E '\|(Config-SNI|Config-Host|Config-Addr)\|' "$HOSTS_FILE" 2>/dev/null)

        [ "$config_count" -eq 0 ] && echo -e " ${BIYellow}  (none — run option [1] to scan config files)${NC}"

        echo -e ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        local total=$(( runtime_count + config_count ))
        echo -e " ${BICyan}Total:${NC} ${BIWhite}${total}${NC} entries  (${BIGreen}${runtime_count}${NC} runtime, ${BICyan}${config_count}${NC} from config)"
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
}

# ================================================================
# Service control
# ================================================================
start_service() {
    systemctl daemon-reload 2>/dev/null
    systemctl enable host-capture 2>/dev/null
    systemctl start host-capture 2>/dev/null
    if systemctl is-active --quiet host-capture 2>/dev/null; then
        echo -e " ${OKEY} host-capture service started. Hosts will be captured automatically."
    else
        echo -e " ${EROR} Failed to start service. Try running: systemctl status host-capture"
    fi
}

stop_service() {
    systemctl stop host-capture 2>/dev/null
    systemctl disable host-capture 2>/dev/null
    echo -e " ${INFO} host-capture service stopped."
}

restart_service() {
    systemctl restart host-capture 2>/dev/null
    echo -e " ${OKEY} host-capture service restarted."
}

# ================================================================
# Run capture once manually
# ================================================================
run_capture_once() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m              ⇱ RUNNING HOST CAPTURE NOW ⇲                \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${INFO} Scanning nginx connection log and xray access log..."
    echo -e " ${INFO} Also scanning config files and client link files..."
    echo -e ""

    if command -v capture-host &>/dev/null; then
        capture-host
    elif [ -f /usr/bin/capture-host ]; then
        /usr/bin/capture-host
    else
        echo -e " ${EROR} capture-host script not found!"
    fi

    echo -e ""
    echo -e " ${INFO} Done. Use option [2] to view results."
}

# ================================================================
# Clear saved hosts
# ================================================================
clear_hosts() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                   ⇱ CLEAR HOST LIST ⇲                     \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    read -p " Clear captured host list and reset state? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        > /etc/myvpn/hosts.log
        > /etc/myvpn/.capture-state 2>/dev/null
        echo -e ""
        echo -e " ${OKEY} Host list and state cleared."
    else
        echo -e ""
        echo -e " ${INFO} Operation cancelled."
    fi
    echo -e ""
}

# ================================================================
# Main Menu
# ================================================================
show_menu() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m               ⇱ VPN HOST CAPTURE MENU ⇲                   \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${BICyan}Captures hosts used by clients when connecting to VPN:${NC}"
    echo -e " ${BIGreen} Host-Header${NC}    = HTTP Host header from client connection"
    echo -e " ${BICyan} SNI${NC}            = TLS Server Name Indication from handshake"
    echo -e " ${BIGreen} Xray-Dest${NC}     = destination accessed via VPN tunnel"
    echo -e " ${BIWhite} Proxy-Host${NC}    = reverse proxy destination host (nginx \$proxy_host)"
    echo -e " ${BIRed} Target-Addr${NC}   = upstream target address (nginx \$upstream_addr)"
    echo -e " ${BIRed} CDN-Proxy${NC}     = CDN entry-point IP (last hop in X-Forwarded-For chain)"
    echo -e " ${BIGreen} Fwd-Host${NC}      = X-Forwarded-Host forwarded by CDN (reverse proxy host)"
    echo -e " ${BICyan} CF/Vercel/NF/Render-Client${NC} = real client IP reported by CDN"
    echo -e ""
    echo -e " ${BICyan}Capture Service: ${NC}$(service_status)"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e "     ${BICyan}[${BIWhite}1${BICyan}]${NC} Run Host Capture Now (once)"
    echo -e "     ${BICyan}[${BIWhite}2${BICyan}]${NC} View Captured Hosts"
    echo -e "     ${BICyan}[${BIWhite}3${BICyan}]${NC} Start Auto-Capture Service (every 60s)"
    echo -e "     ${BICyan}[${BIWhite}4${BICyan}]${NC} Stop Auto-Capture Service"
    echo -e "     ${BICyan}[${BIWhite}5${BICyan}]${NC} Restart Auto-Capture Service"
    echo -e "     ${BICyan}[${BIWhite}6${BICyan}]${NC} Clear Host List & Reset State"
    echo -e "     ${BICyan}[${BIWhite}0${BICyan}]${NC} Back to Main Menu"
    echo -e "     ${BIYellow}Press x to Exit${NC}"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo ""
    read -p " Select menu : " opt
    echo -e ""
    case $opt in
        1)
            run_capture_once
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        2)
            display_hosts
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        3)
            start_service
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        4)
            stop_service
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        5)
            restart_service
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        6)
            clear_hosts
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        0)
            clear
            menu
            ;;
        x|X)
            exit 0
            ;;
        *)
            echo -e " ${INFO} Invalid option."
            read -n 1 -s -r
            show_menu
            ;;
    esac
}

show_menu
