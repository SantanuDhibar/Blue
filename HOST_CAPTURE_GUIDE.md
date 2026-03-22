# Enhanced Host Capture System Guide

## Overview
The enhanced host capture system monitors and logs all incoming connections to extract custom domains, SNI (Server Name Indication), and various host headers used by clients. This helps administrators understand what domains users are accessing through the VPN.

## Key Features

### 1. Comprehensive Host Capture
Captures hosts from multiple sources:
- **HTTP Host Headers**: Standard Host header from HTTP requests
- **SNI (Server Name Indication)**: TLS/SSL handshake server name
- **Proxy Host Headers**: X-Forwarded-Host, proxy-host
- **WebSocket Host**: ws-host, wsHost headers
- **gRPC Service Names**: serviceName from gRPC connections
- **Server Addresses**: address, serverAddress from custom configs
- **Query Parameters**: ?host= from URL query strings
- **Destination Domains**: Actual connection destinations

### 2. Protocol Support
Monitors all protocols:
- SSH (OpenSSH and Dropbear)
- VMESS (all transports: WebSocket, gRPC, TCP, etc.)
- VLESS (all transports)
- TROJAN (all transports)
- Shadowsocks

### 3. Source IP Tracking
- Captures source IP address for each connection
- Helps identify which users are using which domains
- Useful for security auditing

### 4. Real-time Monitoring
- Updates every 2 seconds (configurable 1-5 seconds)
- Systemd service for continuous capture
- Real-time display with 100ms refresh rate

## How It Works

### Capture Process

1. **Log Analysis**:
   - Monitors `/var/log/xray/access.log` for Xray protocols
   - Monitors `/var/log/auth.log` for SSH connections
   - Monitors `/var/log/nginx/access.log` for nginx proxied connections
   - Monitors `/var/log/nginx/error.log` for SNI information

2. **Pattern Extraction**:
   - Uses regex patterns to extract domains from logs
   - Validates domains (must contain letters, not just IPs)
   - Normalizes domains (lowercase, remove ports, remove trailing dots)

3. **Deduplication**:
   - Checks if host already exists before adding
   - Case-insensitive comparison
   - Prevents duplicate entries

4. **Storage**:
   - Stores in `/etc/myvpn/hosts.log`
   - Format: `host|service|source_ip|timestamp`
   - Example: `example.com|VLESS|192.168.1.100|2024-12-07 10:30:45`

### Captured Patterns

#### Host Header Patterns
```
- host=example.com
- Host: example.com
- "host": "example.com"
- host: example.com
```

#### SNI Patterns
```
- sni=example.com
- serverName=example.com
- server_name=example.com
- "sni": "example.com"
```

#### Proxy Headers
```
- proxy-host=example.com
- proxyHost=example.com
- X-Forwarded-Host: example.com
- "proxyHost": "example.com"
```

#### WebSocket Host
```
- ws-host=example.com
- wsHost=example.com
- "wsHost": "example.com"
```

#### gRPC Service
```
- serviceName=example.com
- "serviceName": "example.com"
```

#### Server Address
```
- address=example.com
- serverAddress=example.com
- "address": "example.com"
```

#### Query Parameters
```
- ?host=example.com
- &host=example.com
```

## Menu Options

### Captured Hosts Menu
```
[1] View Captured Hosts - Display all captured hosts with details
[2] Scan for New Hosts - Manually trigger host capture
[3] Add Host Manually - Add a custom host to the list
[4] Remove Host - Remove a specific host from the list
[5] Clear All Hosts - Clear the entire captured hosts list
[6] Turn ON Auto Capture - Enable automatic continuous capture
[7] Turn OFF Auto Capture - Disable automatic capture
[8] Real-time Host Monitor - Live view of captured hosts (100ms refresh)
```

## Usage Examples

### Viewing Captured Hosts
```bash
# Via menu
/usr/bin/menu-captured-hosts

# Direct command
cat /etc/myvpn/hosts.log
```

### Manual Host Capture
```bash
# Trigger manual scan
/usr/bin/capture-host

# View results
cat /etc/myvpn/hosts.log
```

### Real-time Monitoring
```bash
# Launch real-time monitor
/usr/bin/realtime-hosts

# Or use menu option 8
/usr/bin/menu-captured-hosts
# Select option 8
```

### Filtering Captured Hosts
```bash
# View only VLESS connections
grep "VLESS" /etc/myvpn/hosts.log

# View connections from specific IP
grep "192.168.1.100" /etc/myvpn/hosts.log

# View recent captures (last 10)
tail -n 10 /etc/myvpn/hosts.log

# Count unique hosts
cut -d'|' -f1 /etc/myvpn/hosts.log | sort -u | wc -l
```

## Configuration

### Auto-Capture Service
Location: `/etc/systemd/system/host-capture.service`

```ini
[Unit]
Description=Real-time Host Capture Service (2s interval)
After=network.target xray.service nginx.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/bin/capture-host >/dev/null 2>&1; sleep 2; done'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

### Service Management
```bash
# Check status
systemctl status host-capture

# Start service
systemctl start host-capture

# Stop service
systemctl stop host-capture

# Enable auto-start
systemctl enable host-capture

# Disable auto-start
systemctl disable host-capture

# View logs
journalctl -u host-capture -n 50 -f
```

### Capture Interval
Default: 2 seconds (safe frequency)

To change:
1. Edit `/etc/systemd/system/host-capture.service`
2. Change `sleep 2` to desired interval (1-5 seconds recommended)
3. Reload: `systemctl daemon-reload`
4. Restart: `systemctl restart host-capture`

## Storage and Logs

### Primary Storage
- **Location**: `/etc/myvpn/hosts.log`
- **Format**: `host|service|source_ip|timestamp`
- **Permissions**: 644 (readable by all)

### Legacy Storage (Backward Compatibility)
- **Location**: `/etc/xray/captured-hosts.txt`
- **Format**: `host|service|timestamp`

### Log Rotation
Create `/etc/logrotate.d/captured-hosts`:
```
/etc/myvpn/hosts.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 644 root root
}
```

## Advanced Features

### Real-time Display
The real-time monitor shows:
- All captured hosts in a table format
- Host/domain name
- Service type (SSH, VLESS, VMESS, etc.)
- Source IP address
- Capture timestamp
- Highlights new entries in green
- Updates every 100ms for smooth viewing

### Custom VPN Config Detection
The system detects hosts from various VPN client configurations:
- v2rayNG configs (Android)
- v2rayN configs (Windows)
- Clash configs
- Surge configs
- Quantumult configs
- Custom JSON configs

### Security Filtering
Automatically excludes:
- VPS main domain (prevents self-capture)
- VPS IP address
- localhost and 127.0.0.1
- ::1 (IPv6 localhost)
- Common internal addresses

## Troubleshooting

### No Hosts Being Captured

1. **Check Service Status**:
   ```bash
   systemctl status host-capture
   ```

2. **Verify Log Files Exist**:
   ```bash
   ls -la /var/log/xray/access.log
   ls -la /var/log/auth.log
   ```

3. **Check Permissions**:
   ```bash
   ls -la /etc/myvpn/hosts.log
   ```

4. **Manual Test**:
   ```bash
   /usr/bin/capture-host
   cat /etc/myvpn/hosts.log
   ```

### Duplicate Hosts

The system should prevent duplicates, but if they occur:
```bash
# Remove duplicates
sort -u /etc/myvpn/hosts.log > /tmp/hosts_unique.log
mv /tmp/hosts_unique.log /etc/myvpn/hosts.log
```

### Missing Source IPs

Some log formats may not include source IPs:
- Shows as "N/A" in the display
- Still captures the host/domain
- Update log format to include source IPs if needed

### Performance Issues

If capturing causes high CPU:
1. Increase capture interval (from 2s to 5s)
2. Reduce tail lines in script (from 1000 to 500)
3. Enable log rotation to prevent huge log files

## Integration Examples

### Webhook Notification
Modify `/usr/bin/capture-host` to send webhooks:
```bash
# Add after capturing new host
curl -X POST https://your-webhook.com/notify \
  -H "Content-Type: application/json" \
  -d "{\"host\":\"$host\",\"service\":\"$service\",\"ip\":\"$source_ip\"}"
```

### Database Storage
Export to database periodically:
```bash
# Cron job to export to MySQL
0 */6 * * * /usr/local/bin/export-hosts-to-db.sh
```

### Statistics Dashboard
Generate daily statistics:
```bash
#!/bin/bash
echo "Total unique hosts: $(cut -d'|' -f1 /etc/myvpn/hosts.log | sort -u | wc -l)"
echo "Total captures today: $(grep "$(date +%Y-%m-%d)" /etc/myvpn/hosts.log | wc -l)"
echo "Top 10 domains:"
cut -d'|' -f1 /etc/myvpn/hosts.log | sort | uniq -c | sort -rn | head -10
```

## Privacy Considerations

### Data Retention
- Consider implementing automatic cleanup of old captures
- Comply with local privacy laws
- Inform users about logging practices

### Example Cleanup Script
```bash
#!/bin/bash
# Keep only last 30 days of captures
find /etc/myvpn/hosts.log -mtime +30 -type f -delete

# Or use date-based filtering
awk -v date=$(date -d '30 days ago' '+%Y-%m-%d') -F'|' '$4 >= date' /etc/myvpn/hosts.log > /tmp/recent_hosts.log
mv /tmp/recent_hosts.log /etc/myvpn/hosts.log
```

## Best Practices

1. **Regular Review**: Check captured hosts weekly for unusual patterns
2. **Clean Old Data**: Implement log rotation or periodic cleanup
3. **Monitor Service**: Ensure host-capture service is running
4. **Security Audit**: Review captured domains for malicious activity
5. **Performance**: Monitor system resources if capture interval is too frequent

## Summary

The enhanced host capture system provides:
- ✅ Comprehensive domain/host extraction
- ✅ Multiple pattern recognition (10+ types)
- ✅ Source IP tracking
- ✅ Real-time monitoring (2s capture, 100ms display)
- ✅ Duplicate prevention
- ✅ All protocols supported
- ✅ Easy management via menu
- ✅ Customizable and extensible
- ✅ VLESS proxy host identification for CDN setups (Bunny/Vercel)

This helps administrators:
- Understand user traffic patterns
- Detect unusual activity
- Troubleshoot connection issues
- Monitor custom domain usage
- Security auditing and compliance
- **Identify the proxy host IP clients use in CDN-routed VLESS setups**

---

## VLESS Proxy Host Identification (CDN Setup)

### Problem

When running Xray-core VLESS behind a CDN (Bunny or Vercel), the connection chain is:

```
Client → [Proxy Host / Address field] → CDN (Vercel/Bunny) → Origin Server
```

- The **client** sets its `Address` field to a third-party proxy host IP/domain.
- The `Host` header and `SNI` are set to the CDN domain.
- At the **origin server**, you only see CDN node IPs and your own domain in the Host header.
- The intermediate **proxy host** (the client's `Address` field) is not directly visible.

### Solution

The proxy host IP is embedded in the **X-Forwarded-For** header chain that CDN nodes add:
- CDN appends the connecting IP (the proxy host) to `X-Forwarded-For` before forwarding to origin.
- The **last IP** in the XFF chain is the proxy host the client connected to.

### Step 1: Enable Nginx Proxy Capture Log Format

The `proxy_capture` log format is already included in `nginx.conf`. To activate it, add the following line to your VLESS server block (in `/etc/nginx/conf.d/*.conf`):

```nginx
access_log /var/log/nginx/proxy-capture.log proxy_capture;
```

Then reload nginx:

```bash
systemctl reload nginx
```

### Step 2: Use the VLESS Proxy Host Identifier Tool

```bash
# Launch the interactive menu
/usr/bin/vless-proxy-identifier

# Or via the captured hosts menu (option 9)
/usr/bin/menu-captured-hosts
```

The tool provides:
1. **Scan** – Parses nginx logs and Xray access logs for proxy host IPs
2. **View** – Displays all identified proxy hosts with detection method and CDN node IP
3. **Xray Config** – Shows Xray `log` and `policy` config for verbose access logging
4. **Nginx Config** – Shows and explains the `proxy_capture` log format
5. **Apply Nginx** – Automatically applies the log format to `nginx.conf`
6. **tcpdump Commands** – Provides packet capture commands for raw inspection
7. **Clear** – Clears the proxy hosts list

### Step 3: Manual Log Analysis

Parse the proxy capture log directly:

```bash
# Extract all proxy host IPs from XFF chain (last IP = proxy host entry point)
grep -oP 'XFF:"[^"]*"' /var/log/nginx/proxy-capture.log \
  | grep -oP '"[^"]*"' | tr -d '"' \
  | awk -F',' '{print $NF}' | tr -d ' ' \
  | sort | uniq -c | sort -rn

# Monitor proxy hosts in real time
tail -f /var/log/nginx/proxy-capture.log \
  | grep -oP 'XFF:"[^"]*"'

# Find Vercel CDN proxy entries
grep 'VercelFWD' /var/log/nginx/proxy-capture.log \
  | grep -oP 'VercelFWD:"[^"]*"'

# Find Bunny CDN proxy entries (non-empty BunnyCDN field)
grep -v 'BunnyCDN:"-"' /var/log/nginx/proxy-capture.log \
  | grep -oP 'XFF:"[^"]*"'
```

### Step 4: Xray Access Log Configuration

Enable verbose Xray logging to capture VLESS connection metadata:

```json
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  }
}
```

Then parse VLESS entries:

```bash
# Live VLESS connection monitoring
tail -f /var/log/xray/access.log | grep -i vless

# Extract X-Forwarded-For from Xray logs
grep -i 'x-forwarded-for' /var/log/xray/access.log | tail -50
```

### Step 5: tcpdump Packet Inspection

For raw packet-level inspection (unencrypted or XHTTP):

```bash
# Get your network interface
IFACE=$(ip route show to default | awk '{print $5}')

# Capture WebSocket upgrade headers to see proxy host metadata
tcpdump -i $IFACE -A -s 0 'tcp port 443' 2>/dev/null | grep -a 'X-Forwarded-For'

# Capture and save for Wireshark analysis
tcpdump -i $IFACE -w /tmp/vless-capture.pcap 'tcp port 443'
```

### Storage

Identified proxy hosts are saved to:
- **Location**: `/etc/myvpn/proxy-hosts.log`
- **Format**: `proxy_host|detection_method|cdn_node_ip|timestamp`
- **Example**: `1.2.3.4|XFF-Proxy|104.21.1.1|2024-12-07 10:30:45`

For support or questions, refer to the main documentation or contact the system administrator.
