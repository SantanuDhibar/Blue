#!/bin/bash
# =========================================
# VLESS Proxy Host Identifier
# Identifies the client-side proxy host (Address field) used in
# Xray-core VLESS setups behind Bunny/Vercel CDN.
#
# Connection chain:
#   Client -> Proxy Host (Address field) -> CDN (Vercel/Bunny) -> Origin Server
#
# Problem: Origin only sees CDN IPs and own domain in Host header.
# Solution: Parse CDN forwarding headers and Xray logs to reveal
#           the intermediate proxy host IP/domain used by the client.
#
# Features:
# - Parses X-Forwarded-For chains from nginx logs to extract proxy host IPs
# - Reads Xray access logs for VLESS destination and header metadata
# - Detects Bunny CDN and Vercel forwarding headers
# - Provides Xray policy and Nginx log format configuration
# - Real-time proxy host monitoring
# - Shows tcpdump commands for raw packet inspection
#
# Author: LamonLind
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
BIRed='\033[1;91m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'

EROR="[${RED} EROR ${NC}]"
INFO="[${YELLOW} INFO ${NC}]"
OKEY="[${GREEN} OKEY ${NC}]"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please run this script as root!"
    exit 1
fi

# Storage
PROXY_HOSTS_FILE="/etc/myvpn/proxy-hosts.log"
HOSTS_FILE="/etc/myvpn/hosts.log"
XRAY_LOG="/var/log/xray/access.log"
NGINX_LOG="/var/log/nginx/access.log"
NGINX_ERROR_LOG="/var/log/nginx/error.log"

mkdir -p /etc/myvpn 2>/dev/null

# IP regex helpers
IPV4_PATTERN='^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
HOSTNAME_PATTERN='[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]'

# ─────────────────────────────────────────────────────────────
# Helper: initialize proxy hosts file
# ─────────────────────────────────────────────────────────────
init_proxy_file() {
    if [ ! -f "$PROXY_HOSTS_FILE" ]; then
        touch "$PROXY_HOSTS_FILE"
    fi
}

# ─────────────────────────────────────────────────────────────
# Helper: add proxy host entry (deduplicated)
# Format: proxy_host|source_type|cdn_ip|timestamp
# ─────────────────────────────────────────────────────────────
add_proxy_host() {
    local proxy_host="$1"
    local source_type="$2"
    local cdn_ip="$3"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    [ -z "$proxy_host" ] && return
    # Skip IPs that belong to our server
    local vps_ip
    vps_ip=$(cat /etc/myipvps 2>/dev/null || timeout 3 curl -s https://ipinfo.io/ip 2>/dev/null)
    [ "$proxy_host" = "$vps_ip" ] && return
    # Skip localhost
    [[ "$proxy_host" =~ ^(127\.|::1|localhost) ]] && return

    init_proxy_file
    if ! grep -q "^${proxy_host}|" "$PROXY_HOSTS_FILE" 2>/dev/null; then
        echo "${proxy_host}|${source_type}|${cdn_ip:-N/A}|${timestamp}" >> "$PROXY_HOSTS_FILE"
        echo -e "${OKEY} Found proxy host: ${BIGreen}${proxy_host}${NC} (via ${source_type}, CDN: ${cdn_ip:-N/A})"
    fi
}

# ─────────────────────────────────────────────────────────────
# 1. Parse X-Forwarded-For chains from Nginx access log
#
# When the chain is: Client → Proxy Host → CDN → Origin,
# the CDN appends "Proxy Host IP" to X-Forwarded-For.
# Nginx log format must include "$http_x_forwarded_for".
# The SECOND-TO-LAST (or last before CDN adds its own) entry
# is the proxy host IP.
# ─────────────────────────────────────────────────────────────
parse_xforwardedfor_chain() {
    echo -e "${INFO} Scanning X-Forwarded-For chains in Nginx access log..."
    [ ! -f "$NGINX_LOG" ] && return

    tail -n 2000 "$NGINX_LOG" 2>/dev/null | while IFS= read -r line; do
        # Extract the CDN node IP (first field in default nginx log)
        local cdn_ip
        cdn_ip=$(echo "$line" | awk '{print $1}')

        # Extract X-Forwarded-For header value from the log line.
        # Assumes the nginx log format includes the header (e.g. via $http_x_forwarded_for).
        local xff
        xff=$(echo "$line" | grep -oP '"[^"]*,[^"]*"' | head -1 | tr -d '"')
        [ -z "$xff" ] && xff=$(echo "$line" | grep -oP 'XFF:\s*\K[^\s"]+' | head -1)
        [ -z "$xff" ] && continue

        # XFF format: "client_ip, proxy1_ip, proxy2_ip ..."
        # The CDN adds the last-hop IP. The first entry is closest to the real client.
        # In the chain Client→ProxyHost→CDN, XFF = "ClientIP, ProxyHostIP"
        # So the LAST IP in the XFF chain is the proxy host (entry point to CDN).
        local proxy_ip
        proxy_ip=$(echo "$xff" | awk -F',' '{print $NF}' | tr -d ' ')
        [ -z "$proxy_ip" ] && continue

        # Validate it looks like an IP or hostname, not CDN's own IP
        if echo "$proxy_ip" | grep -qP "${IPV4_PATTERN}"; then
            add_proxy_host "$proxy_ip" "XFF-Chain" "$cdn_ip"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# 2. Parse Bunny CDN forwarding headers
#    Bunny CDN passes: X-Forwarded-For, X-Real-Ip, Cdn-Requestcountrycode
#    The real upstream (proxy host) IP appears in X-Forwarded-For.
# ─────────────────────────────────────────────────────────────
parse_bunny_cdn_headers() {
    echo -e "${INFO} Scanning Bunny CDN headers..."
    [ ! -f "$NGINX_LOG" ] && return

    tail -n 2000 "$NGINX_LOG" 2>/dev/null | while IFS= read -r line; do
        local cdn_ip
        cdn_ip=$(echo "$line" | awk '{print $1}')

        # Bunny CDN header: Cdn-Requestcountrycode (indicates Bunny CDN traffic)
        echo "$line" | grep -qi "Cdn-Request\|bunny\|b-cdn" || continue

        local proxy_ip
        proxy_ip=$(echo "$line" | grep -oP 'X-Forwarded-For:\s*\K[^\s,]+' | head -1)
        [ -z "$proxy_ip" ] && proxy_ip=$(echo "$line" | grep -oP '"([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 | tr -d '"')
        [ -z "$proxy_ip" ] && continue

        if echo "$proxy_ip" | grep -qP "${IPV4_PATTERN}"; then
            add_proxy_host "$proxy_ip" "Bunny-CDN-XFF" "$cdn_ip"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# 3. Parse Vercel CDN forwarding headers
#    Vercel passes: X-Vercel-Forwarded-For, X-Forwarded-For
# ─────────────────────────────────────────────────────────────
parse_vercel_cdn_headers() {
    echo -e "${INFO} Scanning Vercel CDN headers..."
    [ ! -f "$NGINX_LOG" ] && return

    tail -n 2000 "$NGINX_LOG" 2>/dev/null | while IFS= read -r line; do
        local cdn_ip
        cdn_ip=$(echo "$line" | awk '{print $1}')

        echo "$line" | grep -qi "vercel\|x-vercel" || continue

        local proxy_ip
        proxy_ip=$(echo "$line" | grep -oP 'X-Vercel-Forwarded-For:\s*\K[^\s,]+' | head -1)
        [ -z "$proxy_ip" ] && proxy_ip=$(echo "$line" | grep -oP 'X-Forwarded-For:\s*\K[^\s,]+' | head -1)
        [ -z "$proxy_ip" ] && continue

        if echo "$proxy_ip" | grep -qP "${IPV4_PATTERN}"; then
            add_proxy_host "$proxy_ip" "Vercel-CDN-XFF" "$cdn_ip"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# 4. Parse Xray access log for VLESS connection metadata
#    Xray logs VLESS inbound connections with destination and email.
#    The "accepted" line shows where the connection is being forwarded.
#    Combined with X-Forwarded-For, we can reconstruct the proxy hop.
# ─────────────────────────────────────────────────────────────
parse_xray_vless_log() {
    echo -e "${INFO} Scanning Xray access log for VLESS proxy metadata..."
    [ ! -f "$XRAY_LOG" ] && return

    tail -n 3000 "$XRAY_LOG" 2>/dev/null | while IFS= read -r line; do
        # Only process VLESS lines
        echo "$line" | grep -qi "vless" || continue

        # Extract source IP (the CDN IP that connects to origin)
        local src_ip
        src_ip=$(echo "$line" | grep -oP 'from\s+\K[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

        # Extract X-Forwarded-For from Xray log (present in WS/XHTTP upgrades)
        local xff_ip
        xff_ip=$(echo "$line" | grep -oP '(X-Forwarded-For|x-forwarded-for)[=:\s]+\K[^\s,>"]+' | head -1)

        # Extract destination/proxy target logged by Xray
        local dest_host
        dest_host=$(echo "$line" | grep -oP '(tcp:|udp:)?\K'"${HOSTNAME_PATTERN}"'(?=:[0-9]+)' | head -1)

        # The proxy host is the XFF IP (the entry point seen by CDN)
        if [ -n "$xff_ip" ] && echo "$xff_ip" | grep -qP "${IPV4_PATTERN}"; then
            add_proxy_host "$xff_ip" "VLESS-XFF" "${src_ip:-N/A}"
        fi

        # Capture destination if it's a non-CDN domain (could be the proxy entry point)
        if [ -n "$dest_host" ] && echo "$dest_host" | grep -q '[a-zA-Z]'; then
            local main_domain
            main_domain=$(cat /etc/xray/domain 2>/dev/null || echo "")
            [ "$dest_host" != "$main_domain" ] && add_proxy_host "$dest_host" "VLESS-Dest" "${src_ip:-N/A}"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# 5. Display identified proxy hosts
# ─────────────────────────────────────────────────────────────
display_proxy_hosts() {
    clear
    local vps_ip
    vps_ip=$(cat /etc/myipvps 2>/dev/null || timeout 3 curl -s https://ipinfo.io/ip 2>/dev/null)
    local main_domain
    main_domain=$(cat /etc/xray/domain 2>/dev/null || echo "N/A")

    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[44;1;39m               ⇱ VLESS CLIENT PROXY HOST IDENTIFIER ⇲                          \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " ${BICyan}VPS IP:${NC}      ${BIYellow}${vps_ip}${NC}"
    echo -e " ${BICyan}CDN Domain:${NC}  ${BIYellow}${main_domain}${NC}"
    echo -e " ${BICyan}Description:${NC} Proxy Hosts are the 'Address' field IPs/domains"
    echo -e "              clients use to reach the CDN entry point."
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    init_proxy_file
    if [ ! -s "$PROXY_HOSTS_FILE" ]; then
        echo -e " ${BIYellow}No proxy hosts identified yet.${NC}"
        echo -e " ${BICyan}Run a scan first (option 1) or ensure nginx logs include${NC}"
        echo -e " ${BICyan}X-Forwarded-For headers (see option 4 for config).${NC}"
        echo ""
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        return
    fi

    printf " ${BIWhite}%-32s %-20s %-18s %s${NC}\n" "PROXY HOST (Client Address)" "DETECTION METHOD" "CDN NODE IP" "CAPTURED TIME"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

    local count=0
    while IFS='|' read -r proxy_host source_type cdn_ip timestamp; do
        [ -z "$proxy_host" ] && continue
        printf " ${BIGreen}%-32s${NC} ${BICyan}%-20s${NC} ${BIYellow}%-18s${NC} ${BIWhite}%s${NC}\n" \
            "$proxy_host" "$source_type" "${cdn_ip:-N/A}" "${timestamp:-N/A}"
        ((count++))
    done < "$PROXY_HOSTS_FILE"

    echo ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " ${BICyan}Total identified proxy hosts: ${BIWhite}${count}${NC}"
}

# ─────────────────────────────────────────────────────────────
# 6. Run full proxy host scan
# ─────────────────────────────────────────────────────────────
run_scan() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[44;1;39m          ⇱ SCANNING FOR VLESS PROXY HOSTS ⇲               \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    parse_xforwardedfor_chain
    parse_bunny_cdn_headers
    parse_vercel_cdn_headers
    parse_xray_vless_log
    echo ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "${OKEY} Scan complete. Use option 2 to view results."
}

# ─────────────────────────────────────────────────────────────
# 7. Show Xray access.log policy config snippet
# ─────────────────────────────────────────────────────────────
show_xray_config() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[44;1;39m    ⇱ XRAY ACCESS LOG CONFIGURATION FOR PROXY DETECTION ⇲   \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo -e " ${BIYellow}Add to /etc/xray/config.json to enable verbose access logging:${NC}"
    echo ""
    cat << 'XRAY_CONFIG'
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "bufferSize": 4
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  }
}
XRAY_CONFIG
    echo ""
    echo -e " ${BIYellow}After applying, grep the access log for proxy entries:${NC}"
    echo -e "   ${BICyan}grep -i 'x-forwarded-for\\|accepted\\|vless' /var/log/xray/access.log | tail -50${NC}"
    echo ""
    echo -e " ${BIYellow}Live monitoring of Xray log for VLESS proxy hops:${NC}"
    echo -e "   ${BICyan}tail -f /var/log/xray/access.log | grep -i 'vless\\|x-forwarded-for'${NC}"
}

# ─────────────────────────────────────────────────────────────
# 8. Show Nginx log format for proxy host capture
# ─────────────────────────────────────────────────────────────
show_nginx_config() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[44;1;39m      ⇱ NGINX LOG FORMAT FOR PROXY HOST IDENTIFICATION ⇲     \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo -e " ${BIYellow}Add this log_format block to /etc/nginx/nginx.conf (inside http {}):${NC}"
    echo ""
    cat << 'NGINX_CONFIG'
# Log format that captures CDN forwarding headers to identify proxy hosts.
# X-Forwarded-For reveals the client's path: ClientIP, ProxyHostIP (→ CDN → Origin).
# The last IP in the XFF chain is the proxy host IP used by the client.
log_format proxy_capture
    '$remote_addr [$time_local] "$request" $status '
    'XFF:"$http_x_forwarded_for" '
    'RealIP:"$http_x_real_ip" '
    'Host:"$http_host" '
    'SNI:"$ssl_server_name" '
    'UA:"$http_user_agent" '
    'BunnyCDN:"$http_cdn_requestcountrycode" '
    'VercelFWD:"$http_x_vercel_forwarded_for" '
    'CFConnecting:"$http_cf_connecting_ip"';

# Apply this log format to your server block:
# access_log /var/log/nginx/proxy-capture.log proxy_capture;
NGINX_CONFIG
    echo ""
    echo -e " ${BIYellow}Then restart nginx and parse the new log:${NC}"
    echo -e "   ${BICyan}systemctl restart nginx${NC}"
    echo ""
    echo -e " ${BIYellow}Parse the proxy capture log to find proxy host IPs:${NC}"
    echo -e '   '"${BICyan}grep -oP 'XFF:\"\\K[^\"]+' /var/log/nginx/proxy-capture.log | awk -F, '{print \$NF}' | tr -d ' ' | sort -u${NC}"
    echo ""
    echo -e " ${BIYellow}Apply the nginx log format now (adds to existing nginx.conf):${NC}"
    echo -e "   ${BICyan}/usr/bin/vless-proxy-identifier --apply-nginx${NC}"
}

# ─────────────────────────────────────────────────────────────
# 9. Apply nginx proxy_capture log format automatically
# ─────────────────────────────────────────────────────────────
apply_nginx_config() {
    local NGINX_CONF="/etc/nginx/nginx.conf"
    [ ! -f "$NGINX_CONF" ] && echo -e "${EROR} nginx.conf not found at $NGINX_CONF" && return 1

    if grep -q "proxy_capture" "$NGINX_CONF" 2>/dev/null; then
        echo -e "${INFO} proxy_capture log format already present in nginx.conf."
        return 0
    fi

    # Insert proxy_capture log_format before the closing brace of the http block
    local log_format_block='
    # Proxy host capture log format - reveals client proxy entry point via XFF chain
    log_format proxy_capture
        '"'"'$remote_addr [$time_local] "$request" $status '"'"'
        '"'"'XFF:"$http_x_forwarded_for" '"'"'
        '"'"'RealIP:"$http_x_real_ip" '"'"'
        '"'"'Host:"$http_host" '"'"'
        '"'"'SNI:"$ssl_server_name" '"'"'
        '"'"'BunnyCDN:"$http_cdn_requestcountrycode" '"'"'
        '"'"'VercelFWD:"$http_x_vercel_forwarded_for" '"'"'
        '"'"'CFConnecting:"$http_cf_connecting_ip"'"'"';'

    # Use awk to insert before the last closing brace of http block
    cp "$NGINX_CONF" /tmp/nginx_proxy.conf.bak
    awk -v insert="$log_format_block" '
        /include \/etc\/nginx\/conf\.d\/\*\.conf;/ {
            print insert
        }
        { print }
    ' "$NGINX_CONF" > /tmp/nginx_proxy.conf && mv /tmp/nginx_proxy.conf "$NGINX_CONF"

    if nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null
        echo -e "${OKEY} proxy_capture log format applied and nginx reloaded."
    else
        echo -e "${EROR} Nginx config test failed. Reverting..."
        cp /tmp/nginx_proxy.conf.bak "$NGINX_CONF"
    fi
}

# ─────────────────────────────────────────────────────────────
# 10. Show tcpdump commands for raw packet inspection
# ─────────────────────────────────────────────────────────────
show_tcpdump_commands() {
    clear
    local IFACE
    IFACE=$(ip route show to default 2>/dev/null | awk '{print $5}' | head -1)
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[44;1;39m    ⇱ TCPDUMP COMMANDS FOR PROXY HOST PACKET INSPECTION ⇲    \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo -e " ${BIYellow}Network interface: ${BIWhite}${IFACE:-eth0}${NC}"
    echo ""
    echo -e " ${BIYellow}1. Capture all HTTPS/WebSocket traffic and extract X-Forwarded-For:${NC}"
    echo -e "   ${BICyan}tcpdump -i ${IFACE:-eth0} -A -s 0 'tcp port 443' 2>/dev/null | grep -a 'X-Forwarded-For'${NC}"
    echo ""
    echo -e " ${BIYellow}2. Capture WebSocket upgrade headers (proxy host entry point):${NC}"
    echo -e "   ${BICyan}tcpdump -i ${IFACE:-eth0} -A -s 0 'tcp port 443 or tcp port 80' 2>/dev/null | grep -a -A5 'GET /vless\|GET /vless-xhttp'${NC}"
    echo ""
    echo -e " ${BIYellow}3. Inspect incoming TLS SNI to see which domain clients use:${NC}"
    echo -e "   ${BICyan}tcpdump -i ${IFACE:-eth0} -A -s 256 'tcp port 443' 2>/dev/null | strings | grep -E '\\.com|\\.net|\\.io|\\.org'${NC}"
    echo ""
    echo -e " ${BIYellow}4. Capture gRPC metadata stream for proxy host headers:${NC}"
    echo -e "   ${BICyan}tcpdump -i ${IFACE:-eth0} -A -s 0 'tcp port 443' 2>/dev/null | grep -a -E 'x-forwarded|grpc-status|content-type: application/grpc'${NC}"
    echo ""
    echo -e " ${BIYellow}5. Save capture to file for analysis with Wireshark:${NC}"
    echo -e "   ${BICyan}tcpdump -i ${IFACE:-eth0} -w /tmp/vless-capture.pcap 'tcp port 443' &${NC}"
    echo -e "   ${BICyan}# Press Ctrl+C after capturing, then analyze /tmp/vless-capture.pcap${NC}"
    echo ""
    echo -e " ${BIYellow}Note: With TLS/XTLS the payload is encrypted. Use X-Forwarded-For from${NC}"
    echo -e " ${BIYellow}      nginx logs or Xray access logs for proxy host identification.${NC}"
}

# ─────────────────────────────────────────────────────────────
# 11. Clear identified proxy hosts
# ─────────────────────────────────────────────────────────────
clear_proxy_hosts() {
    read -p " Clear all identified proxy hosts? (y/n): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        > "$PROXY_HOSTS_FILE"
        echo -e "${OKEY} Proxy hosts list cleared."
    else
        echo -e "${INFO} Cancelled."
    fi
}

# ─────────────────────────────────────────────────────────────
# Handle CLI argument: --apply-nginx
# ─────────────────────────────────────────────────────────────
if [ "$1" = "--apply-nginx" ]; then
    apply_nginx_config
    exit $?
fi

# ─────────────────────────────────────────────────────────────
# Main menu
# ─────────────────────────────────────────────────────────────
clear
echo -e "${BICyan} ┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "         ${BIWhite}${UWhite}VLESS PROXY HOST IDENTIFIER${NC}"
echo -e ""
echo -e "   ${BICyan}Chain: Client → ${BIYellow}[Proxy Host/Address]${BICyan} → CDN → Origin${NC}"
echo -e ""
echo -e "   ${BICyan}[${BIWhite}1${BICyan}] Scan Logs for Proxy Hosts"
echo -e "   ${BICyan}[${BIWhite}2${BICyan}] View Identified Proxy Hosts"
echo -e "   ${BICyan}[${BIWhite}3${BICyan}] Show Xray Log Policy Config"
echo -e "   ${BICyan}[${BIWhite}4${BICyan}] Show Nginx Log Format Config"
echo -e "   ${BICyan}[${BIWhite}5${BICyan}] Apply Nginx proxy_capture Log Format"
echo -e "   ${BICyan}[${BIWhite}6${BICyan}] Show tcpdump Commands"
echo -e "   ${BICyan}[${BIWhite}7${BICyan}] Clear Proxy Hosts List"
echo -e " ${BICyan}└────────────────────────────────────────────────────────────┘${NC}"
echo -e "   ${BIYellow}Press x to Exit${NC}"
echo ""
read -p " Select menu: " opt
echo ""

case $opt in
    1) run_scan ;;
    2) display_proxy_hosts ;;
    3) show_xray_config ;;
    4) show_nginx_config ;;
    5) apply_nginx_config ;;
    6) show_tcpdump_commands ;;
    7) clear_proxy_hosts ;;
    x) exit 0 ;;
    *) echo -e "${INFO} Invalid option." ;;
esac

echo ""
read -n 1 -s -r -p "Press any key to continue..."
exec "$0"
