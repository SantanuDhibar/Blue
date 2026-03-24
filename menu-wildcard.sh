#!/bin/bash
# =========================================
# Wildcard Domain Menu
# Manage wildcard SSL certificates via acme.sh DNS-01 challenge
# Supports: Manual DNS, Cloudflare API
# =========================================

BIBlack='\033[1;90m'
BIRed='\033[1;91m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BIPurple='\033[1;95m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'
NC='\e[0m'

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

WILDCARD_CONFIG="/etc/xray/wildcard.conf"
CERT_DIR="/etc/xray"
ACME="$HOME/.acme.sh/acme.sh"

# ================================================================
# Helper: read stored wildcard config
# ================================================================
load_wildcard_config() {
    if [ -f "$WILDCARD_CONFIG" ]; then
        source "$WILDCARD_CONFIG"
    fi
}

# ================================================================
# Helper: check whether a wildcard cert is installed
# ================================================================
check_wildcard_installed() {
    [ -f "$WILDCARD_CONFIG" ] && [ -f "$CERT_DIR/xray.crt" ] && [ -f "$CERT_DIR/xray.key" ]
}

# ================================================================
# Helper: display certificate expiry date
# ================================================================
get_cert_expiry() {
    local crt="$CERT_DIR/xray.crt"
    if [ -f "$crt" ]; then
        openssl x509 -enddate -noout -in "$crt" 2>/dev/null | sed 's/notAfter=//'
    else
        echo "N/A"
    fi
}

# ================================================================
# Helper: get wildcard cert subject / SAN
# ================================================================
get_cert_subject() {
    local crt="$CERT_DIR/xray.crt"
    if [ -f "$crt" ]; then
        openssl x509 -subject -noout -in "$crt" 2>/dev/null | sed 's/subject=//'
    else
        echo "N/A"
    fi
}

# ================================================================
# Install wildcard certificate
# ================================================================
install_wildcard() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m        INSTALL WILDCARD DOMAIN          \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    if check_wildcard_installed; then
        load_wildcard_config
        echo -e ""
        echo -e " ${YELLOW}Wildcard domain already configured: ${GREEN}*.${WILDCARD_BASE_DOMAIN}${NC}"
        echo -e " ${INFO} Use option [4] to remove the existing certificate first,"
        echo -e "         or option [3] to renew it."
        echo -e ""
        read -n 1 -s -r -p " Press any key to return to menu..."
        menu-wildcard
        return
    fi

    echo -e ""
    echo -e " ${BICyan}Enter the base domain for your wildcard certificate.${NC}"
    echo -e " ${BICyan}Example: if you want ${BIWhite}*.example.com${BICyan}, enter ${BIWhite}example.com${NC}"
    echo -e ""
    read -rp " Base domain (e.g. example.com): " BASE_DOMAIN
    BASE_DOMAIN="${BASE_DOMAIN// /}"

    if [ -z "$BASE_DOMAIN" ]; then
        echo -e ""
        echo -e " ${EROR} Base domain cannot be empty."
        read -n 1 -s -r -p " Press any key to return..."
        menu-wildcard
        return
    fi

    echo -e ""
    echo -e " ${BICyan}Select DNS provider for DNS-01 challenge:${NC}"
    echo -e ""
    echo -e "     ${BICyan}[${BIWhite}1${BICyan}]${NC} Manual DNS  (you add TXT record yourself)"
    echo -e "     ${BICyan}[${BIWhite}2${BICyan}]${NC} Cloudflare  (automatic via CF API token)"
    echo -e "     ${BICyan}[${BIWhite}0${BICyan}]${NC} Cancel"
    echo -e ""
    read -rp " Select DNS provider [1-2]: " DNS_CHOICE

    case "$DNS_CHOICE" in
        1) DNS_MODE="manual" ;;
        2) DNS_MODE="cloudflare" ;;
        0)
            menu-wildcard
            return
            ;;
        *)
            echo -e " ${EROR} Invalid choice."
            read -n 1 -s -r -p " Press any key to return..."
            menu-wildcard
            return
            ;;
    esac

    # Ensure acme.sh is available
    if [ ! -f "$ACME" ]; then
        echo -e ""
        echo -e " ${INFO} acme.sh not found. Installing..."
        curl -s https://get.acme.sh | sh -s -- email="admin@${BASE_DOMAIN}" 2>&1 | tail -5
        if [ ! -f "$ACME" ]; then
            echo -e " ${EROR} Failed to install acme.sh. Check internet connection."
            read -n 1 -s -r -p " Press any key to return..."
            menu-wildcard
            return
        fi
    fi

    "$ACME" --upgrade --auto-upgrade 2>/dev/null
    "$ACME" --set-default-ca --server letsencrypt 2>/dev/null

    mkdir -p "$CERT_DIR"

    if [ "$DNS_MODE" = "cloudflare" ]; then
        echo -e ""
        echo -e " ${BICyan}Enter your Cloudflare API Token:${NC}"
        echo -e " ${INFO} Token needs ${BIWhite}Zone:Read${NC} and ${BIWhite}DNS:Edit${NC} permissions."
        read -rp " CF_Token: " CF_TOKEN_INPUT

        if [ -z "$CF_TOKEN_INPUT" ]; then
            echo -e " ${EROR} API token cannot be empty."
            read -n 1 -s -r -p " Press any key to return..."
            menu-wildcard
            return
        fi

        export CF_Token="$CF_TOKEN_INPUT"

        echo -e ""
        echo -e " ${INFO} Issuing wildcard certificate via Cloudflare DNS-01..."
        "$ACME" --issue --dns dns_cf \
            -d "*.${BASE_DOMAIN}" \
            -d "${BASE_DOMAIN}" \
            -k ec-256 2>&1

        ISSUE_STATUS=$?
    else
        # Manual DNS mode
        echo -e ""
        echo -e " ${INFO} Issuing wildcard certificate via Manual DNS-01..."
        echo -e " ${YELLOW}acme.sh will print TXT record(s) that you must add to your DNS.${NC}"
        echo -e " ${YELLOW}After adding the records, wait for DNS propagation (1-5 minutes)${NC}"
        echo -e " ${YELLOW}before pressing Enter to continue the verification.${NC}"
        echo -e ""
        "$ACME" --issue --dns \
            -d "*.${BASE_DOMAIN}" \
            -d "${BASE_DOMAIN}" \
            -k ec-256 2>&1

        ISSUE_STATUS=$?
    fi

    if [ "$ISSUE_STATUS" -ne 0 ]; then
        echo -e ""
        echo -e " ${EROR} Failed to issue wildcard certificate."
        echo -e " ${INFO} Check DNS records and try again."
        read -n 1 -s -r -p " Press any key to return..."
        menu-wildcard
        return
    fi

    # Install certificate
    echo -e ""
    echo -e " ${INFO} Installing certificate files..."
    "$ACME" --installcert \
        -d "*.${BASE_DOMAIN}" \
        --fullchainpath "$CERT_DIR/xray.crt" \
        --keypath "$CERT_DIR/xray.key" \
        --ecc 2>&1

    if [ $? -ne 0 ]; then
        echo -e " ${EROR} Failed to install certificate files."
        read -n 1 -s -r -p " Press any key to return..."
        menu-wildcard
        return
    fi

    # Save wildcard configuration
    {
        echo "WILDCARD_BASE_DOMAIN=${BASE_DOMAIN}"
        echo "WILDCARD_DNS_MODE=${DNS_MODE}"
        if [ "$DNS_MODE" = "cloudflare" ] && [ -n "$CF_TOKEN_INPUT" ]; then
            echo "CF_Token=${CF_TOKEN_INPUT}"
        fi
        echo "WILDCARD_INSTALLED_DATE=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$WILDCARD_CONFIG"
    chmod 600 "$WILDCARD_CONFIG"

    # Update domain file
    echo "*.${BASE_DOMAIN}" > /etc/xray/domain

    # Restart services to apply new certificate
    systemctl restart xray 2>/dev/null
    systemctl restart nginx 2>/dev/null

    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e " ${OKEY} Wildcard certificate installed successfully!"
    echo -e ""
    echo -e " ${BICyan}Domain    : ${BIWhite}*.${BASE_DOMAIN}${NC}"
    echo -e " ${BICyan}Cert file : ${BIWhite}${CERT_DIR}/xray.crt${NC}"
    echo -e " ${BICyan}Key file  : ${BIWhite}${CERT_DIR}/xray.key${NC}"
    echo -e " ${BICyan}Expiry    : ${BIWhite}$(get_cert_expiry)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    read -n 1 -s -r -p " Press any key to return to menu..."
    menu-wildcard
}

# ================================================================
# Show wildcard status
# ================================================================
show_wildcard_status() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m         WILDCARD DOMAIN STATUS          \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""

    if ! check_wildcard_installed; then
        echo -e " ${BIYellow}No wildcard certificate configured.${NC}"
        echo -e " ${INFO} Use option [1] to install a wildcard domain."
        echo -e ""
        read -n 1 -s -r -p " Press any key to return to menu..."
        menu-wildcard
        return
    fi

    load_wildcard_config

    echo -e " ${BICyan}Base Domain    : ${BIWhite}${WILDCARD_BASE_DOMAIN}${NC}"
    echo -e " ${BICyan}Wildcard Domain: ${BIWhite}*.${WILDCARD_BASE_DOMAIN}${NC}"
    echo -e " ${BICyan}DNS Mode       : ${BIWhite}${WILDCARD_DNS_MODE}${NC}"
    echo -e " ${BICyan}Installed      : ${BIWhite}${WILDCARD_INSTALLED_DATE}${NC}"
    echo -e ""

    local expiry
    expiry=$(get_cert_expiry)
    echo -e " ${BICyan}Certificate    : ${BIWhite}${CERT_DIR}/xray.crt${NC}"
    echo -e " ${BICyan}Key            : ${BIWhite}${CERT_DIR}/xray.key${NC}"
    echo -e " ${BICyan}Expires        : ${BIWhite}${expiry}${NC}"
    echo -e " ${BICyan}Subject        : ${BIWhite}$(get_cert_subject)${NC}"
    echo -e ""

    # Check certificate validity
    if openssl x509 -checkend 86400 -noout -in "$CERT_DIR/xray.crt" 2>/dev/null; then
        echo -e " ${OKEY} Certificate is valid (more than 1 day remaining)."
    else
        echo -e " ${EROR} Certificate is expired or expires within 24 hours!"
        echo -e " ${INFO} Use option [3] to renew the certificate."
    fi

    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    read -n 1 -s -r -p " Press any key to return to menu..."
    menu-wildcard
}

# ================================================================
# Renew wildcard certificate
# ================================================================
renew_wildcard() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m          RENEW WILDCARD CERTIFICATE     \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""

    if ! check_wildcard_installed; then
        echo -e " ${EROR} No wildcard certificate configured."
        echo -e " ${INFO} Use option [1] to install a wildcard domain first."
        echo -e ""
        read -n 1 -s -r -p " Press any key to return to menu..."
        menu-wildcard
        return
    fi

    load_wildcard_config

    echo -e " ${INFO} Renewing wildcard certificate for ${BIWhite}*.${WILDCARD_BASE_DOMAIN}${NC}..."
    echo -e ""

    # Re-export CF_Token if using Cloudflare
    if [ "$WILDCARD_DNS_MODE" = "cloudflare" ] && [ -n "$CF_Token" ]; then
        export CF_Token
    fi

    "$ACME" --renew \
        -d "*.${WILDCARD_BASE_DOMAIN}" \
        --ecc --force 2>&1

    RENEW_STATUS=$?

    if [ "$RENEW_STATUS" -ne 0 ]; then
        echo -e ""
        echo -e " ${EROR} Renewal failed. Check the output above for details."
        read -n 1 -s -r -p " Press any key to return to menu..."
        menu-wildcard
        return
    fi

    # Reinstall certificate files
    "$ACME" --installcert \
        -d "*.${WILDCARD_BASE_DOMAIN}" \
        --fullchainpath "$CERT_DIR/xray.crt" \
        --keypath "$CERT_DIR/xray.key" \
        --ecc 2>&1

    # Restart services
    systemctl restart xray 2>/dev/null
    systemctl restart nginx 2>/dev/null

    echo -e ""
    echo -e " ${OKEY} Wildcard certificate renewed successfully!"
    echo -e " ${BICyan}New expiry: ${BIWhite}$(get_cert_expiry)${NC}"
    echo -e ""
    read -n 1 -s -r -p " Press any key to return to menu..."
    menu-wildcard
}

# ================================================================
# Remove wildcard certificate
# ================================================================
remove_wildcard() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m          REMOVE WILDCARD CERTIFICATE    \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""

    if ! check_wildcard_installed; then
        echo -e " ${EROR} No wildcard certificate configured."
        echo -e ""
        read -n 1 -s -r -p " Press any key to return to menu..."
        menu-wildcard
        return
    fi

    load_wildcard_config

    echo -e " ${BIYellow}This will remove the wildcard certificate for ${BIWhite}*.${WILDCARD_BASE_DOMAIN}${BIYellow}.${NC}"
    echo -e " ${BIYellow}Certificate files (xray.crt / xray.key) will be deleted.${NC}"
    echo -e ""
    read -rp " Are you sure? (y/N): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e " ${INFO} Operation cancelled."
        read -n 1 -s -r -p " Press any key to return to menu..."
        menu-wildcard
        return
    fi

    # Revoke and remove from acme.sh
    "$ACME" --remove -d "*.${WILDCARD_BASE_DOMAIN}" --ecc 2>/dev/null

    # Remove certificate files
    rm -f "$CERT_DIR/xray.crt" "$CERT_DIR/xray.key"

    # Remove wildcard config
    rm -f "$WILDCARD_CONFIG"

    # Restore domain file to the base domain (without wildcard prefix)
    echo "$WILDCARD_BASE_DOMAIN" > /etc/xray/domain

    echo -e ""
    echo -e " ${OKEY} Wildcard certificate removed."
    echo -e " ${INFO} You may want to set a new domain via main menu option [11]"
    echo -e "         and regenerate a regular certificate via option [12]."
    echo -e ""
    read -n 1 -s -r -p " Press any key to return to menu..."
    menu-wildcard
}

# ================================================================
# Change wildcard domain (remove old + install new)
# ================================================================
change_wildcard_domain() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m          CHANGE WILDCARD DOMAIN         \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""

    # Remove old certificate if present
    if check_wildcard_installed; then
        load_wildcard_config
        echo -e " ${INFO} Current wildcard domain: ${BIWhite}*.${WILDCARD_BASE_DOMAIN}${NC}"
        echo -e " ${INFO} Removing old wildcard certificate..."
        "$ACME" --remove -d "*.${WILDCARD_BASE_DOMAIN}" --ecc 2>/dev/null
        rm -f "$WILDCARD_CONFIG"
        echo -e ""
    fi

    # Proceed to install new certificate (install_wildcard prompts for new domain)
    install_wildcard
}

# ================================================================
# Main Menu
# ================================================================
menu-wildcard() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m           ⇱ WILDCARD DOMAIN MENU ⇲      \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""

    if check_wildcard_installed; then
        load_wildcard_config
        echo -e " ${BICyan}Active wildcard: ${BIGreen}*.${WILDCARD_BASE_DOMAIN}${NC}"
        echo -e " ${BICyan}Expires        : ${BIWhite}$(get_cert_expiry)${NC}"
    else
        echo -e " ${BIYellow}No wildcard certificate configured.${NC}"
    fi

    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e "     ${BICyan}[${BIWhite}1${BICyan}]${NC} Install Wildcard Certificate"
    echo -e "     ${BICyan}[${BIWhite}2${BICyan}]${NC} Wildcard Status"
    echo -e "     ${BICyan}[${BIWhite}3${BICyan}]${NC} Renew Wildcard Certificate"
    echo -e "     ${BICyan}[${BIWhite}4${BICyan}]${NC} Remove Wildcard Certificate"
    echo -e "     ${BICyan}[${BIWhite}5${BICyan}]${NC} Change Wildcard Domain"
    echo -e "     ${BICyan}[${BIWhite}0${BICyan}]${NC} Back to Main Menu"
    echo -e "     ${BIYellow}Press x to Exit${NC}"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo ""
    read -rp " Select menu : " opt
    echo -e ""
    case $opt in
        1) install_wildcard ;;
        2) show_wildcard_status ;;
        3) renew_wildcard ;;
        4) remove_wildcard ;;
        5) change_wildcard_domain ;;
        0) clear ; menu ;;
        x|X) exit 0 ;;
        *) echo -e " ${INFO} Invalid option." ; sleep 1 ; menu-wildcard ;;
    esac
}

menu-wildcard
