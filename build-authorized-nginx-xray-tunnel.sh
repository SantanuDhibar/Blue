#!/bin/bash

set -euo pipefail

XRAY_PORT=10000
XRAY_PATH="/vless"
OUTPUT_DIR="./generated-tunnel"
INPUT_FILE=""
TIMEOUT=12
INSECURE_TLS=0
HTTP_PORTS="80"
HTTPS_PORTS="443"

usage() {
    cat <<'EOF'
Usage:
  build-authorized-nginx-xray-tunnel.sh --input URL_FILE [options]
  build-authorized-nginx-xray-tunnel.sh [options] URL [URL...]

Options:
  --input FILE       File containing URLs (one per line, '#' comments allowed)
  --output-dir DIR   Output directory (default: ./generated-tunnel)
  --xray-port PORT   Xray VLESS WS port (default: 10000)
  --xray-path PATH   WebSocket path (default: /vless)
  --http-ports CSV   HTTP listen ports (default: 80)
  --https-ports CSV  HTTPS listen ports (default: 443)
  --timeout SEC      Curl timeout in seconds (default: 12)
  --insecure         Allow insecure TLS checks for header fetches
  --help             Show this help
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

ensure_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        printf "%s\n" "$url"
    else
        printf "https://%s\n" "$url"
    fi
}

extract_domain() {
    local url="$1"
    local host
    host=$(printf "%s" "$url" | sed -E 's#^https?://##; s#/.*$##; s#:[0-9]+$##')
    printf "%s\n" "$host"
}

valid_domain() {
    local domain="$1"
    [[ -n "$domain" ]] || return 1
    [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || return 1
}

safe_origin_from_url() {
    local url="$1"
    local domain="$2"
    local scheme
    scheme=$(printf "%s" "$url" | sed -nE 's#^(https?)://.*#\1#p')
    [[ -n "$scheme" ]] || scheme="https"
    printf "%s://%s\n" "$scheme" "$domain"
}

normalize_csv_ports() {
    local raw="$1"
    printf "%s" "$raw" | tr -d '[:space:]'
}

validate_csv_ports() {
    local csv="$1"
    [[ -n "$csv" ]] || return 0
    local IFS=','
    read -r -a ports <<< "$csv"
    for port in "${ports[@]}"; do
        [[ "$port" =~ ^[0-9]+$ ]] || return 1
        (( port > 0 && port <= 65535 )) || return 1
    done
}

is_nginx_like() {
    local server_header="${1:-}"
    local lc
    lc=$(printf "%s" "$server_header" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == *nginx* || "$lc" == *openresty* ]]
}

validate_args() {
    [[ "$XRAY_PATH" = /* ]] || die "--xray-path must start with '/'"
    [[ "$XRAY_PORT" =~ ^[0-9]+$ ]] || die "--xray-port must be numeric"
    (( XRAY_PORT > 0 && XRAY_PORT <= 65535 )) || die "--xray-port must be in 1..65535"
    [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout must be numeric"
    HTTP_PORTS=$(normalize_csv_ports "$HTTP_PORTS")
    HTTPS_PORTS=$(normalize_csv_ports "$HTTPS_PORTS")
    validate_csv_ports "$HTTP_PORTS" || die "--http-ports must be comma-separated 1..65535 values"
    validate_csv_ports "$HTTPS_PORTS" || die "--https-ports must be comma-separated 1..65535 values"
    [[ -n "$HTTP_PORTS" || -n "$HTTPS_PORTS" ]] || die "At least one of --http-ports or --https-ports must be set"
}

declare -a URLS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            [[ $# -ge 2 ]] || die "--input requires a value"
            INPUT_FILE="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --xray-port)
            [[ $# -ge 2 ]] || die "--xray-port requires a value"
            XRAY_PORT="$2"
            shift 2
            ;;
        --xray-path)
            [[ $# -ge 2 ]] || die "--xray-path requires a value"
            XRAY_PATH="$2"
            shift 2
            ;;
        --http-ports)
            [[ $# -ge 2 ]] || die "--http-ports requires a value"
            HTTP_PORTS="$2"
            shift 2
            ;;
        --https-ports)
            [[ $# -ge 2 ]] || die "--https-ports requires a value"
            HTTPS_PORTS="$2"
            shift 2
            ;;
        --timeout)
            [[ $# -ge 2 ]] || die "--timeout requires a value"
            TIMEOUT="$2"
            shift 2
            ;;
        --insecure)
            INSECURE_TLS=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            URLS+=("$1")
            shift
            ;;
    esac
done

validate_args

if [[ -n "$INPUT_FILE" ]]; then
    [[ -f "$INPUT_FILE" ]] || die "Input file not found: $INPUT_FILE"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        URLS+=("$line")
    done < "$INPUT_FILE"
fi

(( ${#URLS[@]} > 0 )) || die "No URLs provided"

mkdir -p "$OUTPUT_DIR"

ANALYSIS_FILE="$OUTPUT_DIR/header-analysis.tsv"
AUTHORIZED_FILE="$OUTPUT_DIR/authorized-domains.txt"
XRAY_CONFIG_FILE="$OUTPUT_DIR/xray-vless-ws.json"
NGINX_CONFIG_FILE="$OUTPUT_DIR/nginx-authorized-vless.conf"
DEPLOYMENT_FILE="$OUTPUT_DIR/deployment-steps.txt"

printf "url\tdomain\tstatus\tserver\tcontent_type\tnginx_or_openresty\n" > "$ANALYSIS_FILE"
: > "$AUTHORIZED_FILE"

declare -A DOMAIN_ORIGIN=()
declare -A DOMAIN_SEEN=()

declare -a CURL_TLS_FLAGS=()
if (( INSECURE_TLS == 1 )); then
    CURL_TLS_FLAGS+=("-k")
fi

for raw_url in "${URLS[@]}"; do
    url=$(ensure_url "$raw_url")
    domain=$(extract_domain "$url")
    valid_domain "$domain" || continue

    headers=$(curl "${CURL_TLS_FLAGS[@]}" -sSIL --connect-timeout 5 --max-time "$TIMEOUT" "$url" 2>/dev/null || true)
    status=$(printf "%s\n" "$headers" | awk '/^HTTP\// { line=$0 } END { print line }' | tr -d '\r')
    server=$(printf "%s\n" "$headers" | awk -F': *' 'tolower($1)=="server" { v=$2 } END { print v }' | tr -d '\r')
    content_type=$(printf "%s\n" "$headers" | awk -F': *' 'tolower($1)=="content-type" { v=$2 } END { print v }' | tr -d '\r')

    marker="no"
    if is_nginx_like "$server"; then
        marker="yes"
        if [[ -z "${DOMAIN_SEEN[$domain]+x}" ]]; then
            DOMAIN_SEEN["$domain"]=1
            DOMAIN_ORIGIN["$domain"]="$(safe_origin_from_url "$url" "$domain")"
            printf "%s\n" "$domain" >> "$AUTHORIZED_FILE"
        fi
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$url" "$domain" "${status:-N/A}" "${server:-N/A}" "${content_type:-N/A}" "$marker" >> "$ANALYSIS_FILE"
done

cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "port": $XRAY_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "REPLACE_WITH_UUID",
            "level": 0,
            "email": "proxy-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "$XRAY_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

{
    cat <<'EOF'
# Generated authorized reverse proxy tunnel config
# Includes only domains detected as nginx/openresty from header analysis.

EOF
    for domain in $(sort -u "$AUTHORIZED_FILE" 2>/dev/null); do
        origin="${DOMAIN_ORIGIN[$domain]:-https://$domain}"
        http_listen_lines=""
        https_listen_lines=""
        ssl_block=""

        if [[ -n "$HTTP_PORTS" ]]; then
            IFS=',' read -r -a h_ports <<< "$HTTP_PORTS"
            for p in "${h_ports[@]}"; do
                http_listen_lines+="    listen $p;"$'\n'
                http_listen_lines+="    listen [::]:$p;"$'\n'
            done
        fi

        if [[ -n "$HTTPS_PORTS" ]]; then
            IFS=',' read -r -a s_ports <<< "$HTTPS_PORTS"
            for p in "${s_ports[@]}"; do
                https_listen_lines+="    listen $p ssl http2;"$'\n'
                https_listen_lines+="    listen [::]:$p ssl http2;"$'\n'
            done
            ssl_block=$'    ssl_certificate /etc/xray/xray.crt;\n    ssl_certificate_key /etc/xray/xray.key;\n'
        fi

        cat <<EOF
server {
${http_listen_lines}${https_listen_lines}    server_name $domain;

${ssl_block}

    location / {
        proxy_pass $origin;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = $XRAY_PATH {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$XRAY_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

EOF
    done
} > "$NGINX_CONFIG_FILE"

cat > "$DEPLOYMENT_FILE" <<EOF
Authorized Reverse Proxy Tunnel Deployment
=========================================

1) Review analysis output:
   - $ANALYSIS_FILE
   - $AUTHORIZED_FILE

2) Configure Xray (VLESS + WS):
   - Copy $XRAY_CONFIG_FILE to /etc/xray/config.json
   - Replace REPLACE_WITH_UUID with a real UUID
   - Restart Xray:
     systemctl restart xray

3) Configure Nginx/OpenResty:
   - Copy $NGINX_CONFIG_FILE to /etc/nginx/conf.d/authorized-vless.conf
   - HTTP listen ports configured: ${HTTP_PORTS:-none}
   - HTTPS listen ports configured: ${HTTPS_PORTS:-none}
   - If HTTPS ports are enabled, ensure certificate/key exist:
     /etc/xray/xray.crt and /etc/xray/xray.key
   - Validate config:
     nginx -t
   - Reload Nginx:
     systemctl reload nginx

4) Verify tunnel path:
   - Ensure WebSocket upgrade works on path: $XRAY_PATH
   - Ensure normal content still works on: /

Notes:
- Only URLs with Server header containing nginx/openresty are authorized.
- TLS must remain disabled in Xray; TLS termination is handled by reverse proxy.
- If no domains are authorized, nginx config will contain only comments.
EOF

echo "Generated:"
echo "  Header analysis : $ANALYSIS_FILE"
echo "  Authorized list : $AUTHORIZED_FILE"
echo "  Xray config     : $XRAY_CONFIG_FILE"
echo "  Nginx config    : $NGINX_CONFIG_FILE"
echo "  Deploy steps    : $DEPLOYMENT_FILE"
echo
echo "Authorized domains count: $(wc -l < "$AUTHORIZED_FILE" | tr -d ' ')"
