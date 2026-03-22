#!/bin/bash
# =========================================
# Universal Host Capture
# Captures hosts used by clients when they connect to the VPN.
#
# Runtime sources (live connection data):
#   1. /var/log/nginx/proxy-capture.log  - Host header & SNI per connection
#   2. /var/log/xray/access.log          - Accepted connection destinations
#
# Config sources (what is configured):
#   3. /etc/xray/config.json             - serverName, address, Host header fields
#   4. /home/vps/public_html/*.txt       - vless://, vmess://, trojan:// client links
#
# Hosts are accumulated in /etc/myvpn/hosts.log (new unique entries appended).
# Run periodically (e.g., via host-capture.service) to capture connections in real-time.
#
# Author: LamonLind
# =========================================

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

# Paths
NGINX_CAPTURE_LOG="/var/log/nginx/proxy-capture.log"
XRAY_ACCESS_LOG="/var/log/xray/access.log"
XRAY_CONFIG="/etc/xray/config.json"
CLIENT_DIR="/home/vps/public_html"
DOMAIN_FILE="/etc/xray/domain"
HOSTS_FILE="/etc/myvpn/hosts.log"
STATE_FILE="/etc/myvpn/.capture-state"   # tracks last-read positions

mkdir -p /etc/myvpn 2>/dev/null
touch "$HOSTS_FILE" 2>/dev/null

# ================================================================
# Normalize and validate
# ================================================================
normalize_host() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/:[0-9]*$//; s/\.$//'
}

is_valid_host() {
    local h="$1"
    [ -z "$h" ] && return 1
    # Must start and end with alphanumeric; dots/hyphens only in the middle
    echo "$h" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$' || return 1
    # Not a bare integer
    echo "$h" | grep -qE '^[0-9]+$' && return 1
    # Not loopback/special
    case "$h" in
        127.0.0.1|localhost|0.0.0.0|"::1") return 1 ;;
    esac
    return 0
}

# ================================================================
# Add unique host entry; append to HOSTS_FILE only if new
# Format: host|type|source_ip|timestamp
# ================================================================
add_host() {
    local host="$1"
    local type="$2"
    local source_ip="$3"
    host=$(normalize_host "$host")
    is_valid_host "$host" || return

    # Check if this host|type combination already exists
    if ! grep -qF "${host}|${type}|" "$HOSTS_FILE" 2>/dev/null; then
        local ts
        ts=$(date "+%Y-%m-%d %H:%M:%S")
        echo "${host}|${type}|${source_ip}|${ts}" >> "$HOSTS_FILE"
    fi
}

# ================================================================
# 1. Parse nginx proxy-capture log (runtime - actual client connections)
#    Format set in nginx.conf proxy_capture log_format:
#    REMOTE_IP [TIME] "REQUEST" STATUS XFF:"..." RealIP:"..." Host:"HOST" SNI:"SNI" ...
# ================================================================
parse_nginx_proxy_capture() {
    [ -f "$NGINX_CAPTURE_LOG" ] || return

    # Read only new lines since last run (using line count state)
    local state_key="nginx_proxy_capture"
    local last_line=0
    [ -f "$STATE_FILE" ] && last_line=$(grep "^${state_key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    last_line=${last_line:-0}

    local total_lines
    total_lines=$(wc -l < "$NGINX_CAPTURE_LOG")

    if [ "$total_lines" -le "$last_line" ]; then
        # Log was rotated; start from beginning of new file
        # add_host deduplicates so re-processing is safe
        last_line=0
    fi

    local new_lines=$(( total_lines - last_line ))
    if [ "$new_lines" -le 0 ]; then
        return
    fi

    # Process only new lines
    tail -n "$new_lines" "$NGINX_CAPTURE_LOG" 2>/dev/null | while IFS= read -r line; do
        local source_ip host sni
        source_ip=$(echo "$line" | awk '{print $1}')

        # Extract Host:"..." field
        host=$(echo "$line" | grep -oE 'Host:"[^"]*"' | head -1 | cut -d'"' -f2)
        # Extract SNI:"..." field
        sni=$(echo "$line" | grep -oE 'SNI:"[^"]*"' | head -1 | cut -d'"' -f2)

        [ -n "$host" ] && [ "$host" != "-" ] && add_host "$host" "Host-Header" "$source_ip"
        [ -n "$sni" ]  && [ "$sni"  != "-" ] && add_host "$sni"  "SNI"         "$source_ip"
    done

    # Update state
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${state_key}=/d" "$STATE_FILE"
    fi
    echo "${state_key}=${total_lines}" >> "$STATE_FILE"
}

# ================================================================
# 2. Parse xray access log (runtime - what hosts are accessed via VPN tunnel)
#    Format: DATE TIME from SRC_IP:PORT accepted tcp:DEST_HOST:PORT [tags]
# ================================================================
parse_xray_access_log() {
    [ -f "$XRAY_ACCESS_LOG" ] || return

    local state_key="xray_access"
    local last_line=0
    [ -f "$STATE_FILE" ] && last_line=$(grep "^${state_key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    last_line=${last_line:-0}

    local total_lines
    total_lines=$(wc -l < "$XRAY_ACCESS_LOG")

    if [ "$total_lines" -le "$last_line" ]; then
        last_line=0
    fi

    local new_lines=$(( total_lines - last_line ))
    if [ "$new_lines" -le 0 ]; then
        return
    fi

    tail -n "$new_lines" "$XRAY_ACCESS_LOG" 2>/dev/null | while IFS= read -r line; do
        # Only process accepted connection lines
        echo "$line" | grep -q "accepted" || continue

        local source_ip dest_host
        # Extract source IP from "from IP:PORT" (IPv4 only)
        source_ip=$(echo "$line" | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+' | head -1 | sed 's/from //;s/:[0-9]*$//')
        # Extract destination host from "accepted tcp:HOST:PORT" or "accepted udp:HOST:PORT"
        dest_host=$(echo "$line" | grep -oE 'accepted [a-z]+:[^: ]+:[0-9]+' | head -1 | sed 's/accepted [a-z]*://;s/:[0-9]*$//')

        [ -n "$dest_host" ] && add_host "$dest_host" "Xray-Dest" "$source_ip"
    done

    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${state_key}=/d" "$STATE_FILE"
    fi
    echo "${state_key}=${total_lines}" >> "$STATE_FILE"
}

# ================================================================
# 3. Parse /etc/xray/config.json (config-based - what is configured)
# ================================================================
parse_xray_config() {
    [ -f "$XRAY_CONFIG" ] || return

    # serverName -> SNI
    grep -oE '"serverName"[[:space:]]*:[[:space:]]*"[^"]+"' "$XRAY_CONFIG" | \
        grep -oE '"[^"]+"\s*$' | tr -d '"' | while read -r val; do
        add_host "$val" "Config-SNI" "config.json"
    done

    # "host" in headers -> Host Header
    grep -oE '"[Hh]ost"[[:space:]]*:[[:space:]]*"[^"]+"' "$XRAY_CONFIG" | \
        grep -oE '"[^"]+"\s*$' | tr -d '"' | while read -r val; do
        add_host "$val" "Config-Host" "config.json"
    done

    # "address" fields -> Target Host
    grep -oE '"address"[[:space:]]*:[[:space:]]*"[^"]+"' "$XRAY_CONFIG" | \
        grep -oE '"[^"]+"\s*$' | tr -d '"' | while read -r val; do
        add_host "$val" "Config-Addr" "config.json"
    done
}

# ================================================================
# 4. Parse client link files (vless://, vmess://, trojan://)
# ================================================================
parse_url_link() {
    local link="$1"
    local src="$2"

    local addr
    addr=$(echo "$link" | sed -n 's|.*://[^@]*@\([^:/?#]*\).*|\1|p')
    add_host "$addr" "Config-Addr" "$src"

    local query
    query=$(echo "$link" | grep -oE '\?[^#]*' | tr -d '?')

    local host_param sni_param
    host_param=$(echo "$query" | tr '&' '\n' | grep -i '^host=' | cut -d= -f2- | head -1)
    sni_param=$(echo "$query" | tr '&' '\n' | grep -i '^sni=' | cut -d= -f2- | head -1)

    if [ -n "$host_param" ]; then
        local decoded_host
        # Decode percent-encoded hostname chars; only keep valid hostname characters
        decoded_host=$(echo "$host_param" | sed 's/%2E/./g; s/%2e/./g; s/%2D/-/g; s/%2d/-/g' | \
            sed 's/[^a-zA-Z0-9._-]//g')
        [ -z "$decoded_host" ] && decoded_host="$host_param"
        add_host "$decoded_host" "Config-Host" "$src"
    fi
    [ -n "$sni_param" ] && add_host "$sni_param" "Config-SNI" "$src"
}

parse_vmess_link() {
    local link="$1"
    local src="$2"

    local b64
    b64=$(echo "$link" | sed 's|vmess://||')
    local json
    json=$(echo "$b64" | base64 -d 2>/dev/null) || { echo "vmess decode failed in ${src}" >&2; return; }

    local add_val host_val sni_val
    add_val=$(echo "$json" | grep -oE '"add"[[:space:]]*:[[:space:]]*"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')
    host_val=$(echo "$json" | grep -oE '"host"[[:space:]]*:[[:space:]]*"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')
    sni_val=$(echo "$json" | grep -oE '"sni"[[:space:]]*:[[:space:]]*"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')

    add_host "$add_val" "Config-Addr" "$src"
    add_host "$host_val" "Config-Host" "$src"
    [ -n "$sni_val" ] && add_host "$sni_val" "Config-SNI" "$src"
}

parse_client_files() {
    [ -d "$CLIENT_DIR" ] || return

    find "$CLIENT_DIR" -name "*.txt" -type f 2>/dev/null | while read -r file; do
        local src
        src=$(basename "$file")

        while read -r line; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "$line" in
                vless://*)   parse_url_link "$line" "$src" ;;
                trojan://*)  parse_url_link "$line" "$src" ;;
                vmess://*)   parse_vmess_link "$line" "$src" ;;
            esac
        done < <(grep -oE '(vless|vmess|trojan)://[^[:space:]"'"'"']+' "$file")
    done
}

# ================================================================
# Run all capture sources
# ================================================================
parse_nginx_proxy_capture     # Runtime: actual client connections
parse_xray_access_log         # Runtime: VPN tunnel destinations
parse_xray_config             # Config: what is configured
parse_client_files            # Config: client link files

total=$(wc -l < "$HOSTS_FILE")
echo -e "${OKEY} Host capture complete. Total unique hosts: ${total}"
