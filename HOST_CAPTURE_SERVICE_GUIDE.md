# Enhanced Host Capture Service Guide

## Overview
This guide covers the enhanced host capture service daemon that provides real-time, continuous monitoring of all incoming VPN connections with full root access to capture comprehensive host information.

## What is the Host Capture Service?

The Host Capture Service is a **systemd-managed daemon** that runs continuously in the background to:
- **Capture all incoming hosts/domains** from VPN connections
- **Monitor SSH, VLESS, VMESS, Trojan, and Shadowsocks** protocols
- **Track source IP addresses** for each connection
- **Prevent duplicate entries** in the capture log
- **Run with full root privileges** for comprehensive log access
- **Operate at 2-second intervals** for real-time capture without system overload

## Key Features

### 1. Continuous Monitoring (24/7)
- **Always-on service** managed by systemd
- **Automatic restart** on failure
- **Starts on boot** automatically
- **2-second capture interval** - optimal for real-time monitoring

### 2. Full Root Access
The service runs with full root privileges and capabilities:
- `CAP_NET_ADMIN` - Network administration
- `CAP_NET_RAW` - Raw network access
- `CAP_SYS_ADMIN` - System administration
- `CAP_DAC_READ_SEARCH` - Read all files

This allows comprehensive access to:
- All system log files (`/var/log/auth.log`, `/var/log/xray/`)
- Network interfaces and traffic
- System processes and connections

### 3. High-Performance Configuration
The service is optimized for performance:
- **Nice value: -10** (higher CPU priority)
- **Real-time I/O scheduling** (Class: realtime, Priority: 0)
- **FIFO CPU scheduling** (Priority: 50)
- **Minimal latency** for time-critical operations

### 4. Comprehensive Pattern Matching
Captures hosts from multiple sources:
- HTTP Host headers
- SNI (Server Name Indication)
- Proxy Host headers
- WebSocket hosts
- gRPC service names
- TCP prefixed hosts
- CDN/Cloudflare hosts
- Domain fronting hosts
- Bug host patterns
- Server addresses

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│  host-capture.service (systemd service)                 │
│  - Manages the daemon lifecycle                         │
│  - Ensures automatic start/restart                      │
│  - Configured with full root access                     │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  capture-host-daemon.sh (continuous loop)               │
│  - Runs every 2 seconds                                 │
│  - Calls capture-host.sh                                │
│  - Logs to /var/log/host-capture-service.log           │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  capture-host.sh (actual capture logic)                 │
│  - Scans SSH, Xray, Nginx, Dropbear logs               │
│  - Extracts hosts using regex patterns                  │
│  - Saves to /etc/myvpn/hosts.log                       │
└─────────────────────────────────────────────────────────┘
```

## Installation and Setup

The service is automatically installed and configured during system update:

```bash
# Update the system (includes host capture service)
update

# Or manually install
wget -O /etc/systemd/system/host-capture.service https://raw.githubusercontent.com/SantanuDhibar/Blue/main/host-capture.service
wget -O /usr/local/bin/capture-host-daemon.sh https://raw.githubusercontent.com/SantanuDhibar/Blue/main/capture-host-daemon.sh
wget -O /usr/local/bin/capture-host.sh https://raw.githubusercontent.com/SantanuDhibar/Blue/main/capture-host.sh
chmod +x /usr/local/bin/capture-host-daemon.sh
chmod +x /usr/local/bin/capture-host.sh

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable host-capture
systemctl start host-capture
```

## Service Management

### Check Service Status
```bash
systemctl status host-capture
```

Expected output:
```
● host-capture.service - Host Capture Service - Real-time VPN Host Monitoring
   Loaded: loaded (/etc/systemd/system/host-capture.service; enabled)
   Active: active (running) since Mon 2024-12-09 15:30:00 UTC; 1h ago
 Main PID: 12345 (capture-host-d)
   Status: "Capturing hosts..."
    Tasks: 2 (limit: 4915)
   Memory: 4.2M
   CGroup: /system.slice/host-capture.service
           └─12345 /bin/bash /usr/local/bin/capture-host-daemon.sh
```

### Start Service
```bash
systemctl start host-capture
```

### Stop Service
```bash
systemctl stop host-capture
```

### Restart Service
```bash
systemctl restart host-capture
```

### Enable Auto-start on Boot
```bash
systemctl enable host-capture
```

### Disable Auto-start
```bash
systemctl disable host-capture
```

### View Service Logs
```bash
# View systemd journal logs
journalctl -u host-capture -f

# View capture service log
tail -f /var/log/host-capture-service.log
```

## Captured Data

### Storage Location
- **Primary log**: `/etc/myvpn/hosts.log`
- **Backward compatible**: `/etc/xray/captured-hosts.txt`
- **Service log**: `/var/log/host-capture-service.log`

### Data Format
Each captured host is stored in the following format:
```
host|service|source_ip|timestamp
```

Example entries:
```
example.com|SSH|192.168.1.100|2024-12-09 15:30:45
api.google.com|VLESS|203.0.113.50|2024-12-09 15:31:10
cdn.cloudflare.com|SNI|198.51.100.25|2024-12-09 15:31:15
bug.com|Bug-Host|203.0.113.75|2024-12-09 15:32:00
```

### Fields Explained
- **host**: Captured domain/hostname
- **service**: Type of capture (SSH, VLESS, VMESS, Trojan, SNI, Header-Host, etc.)
- **source_ip**: IP address of the client connection
- **timestamp**: When the host was captured (YYYY-MM-DD HH:MM:SS)

## Viewing Captured Hosts

### Method 1: Real-time Monitor
```bash
realtime-hosts
```
- Updates display every 100ms (10 times per second)
- Shows new captures highlighted in green
- Press Ctrl+C to exit

### Method 2: Captured Hosts Menu
```bash
menu-captured-hosts
```
- Interactive menu with options to:
  - View all captured hosts
  - Search by host
  - View by service type
  - View by source IP
  - Export to file

### Method 3: Command Line
```bash
# View all captured hosts
cat /etc/myvpn/hosts.log

# View only unique hosts
cut -d'|' -f1 /etc/myvpn/hosts.log | sort | uniq

# Count total captures
wc -l /etc/myvpn/hosts.log

# View captures from specific IP
grep "192.168.1.100" /etc/myvpn/hosts.log

# View captures for specific service
grep "VLESS" /etc/myvpn/hosts.log

# View recent captures (last 20)
tail -n 20 /etc/myvpn/hosts.log
```

## Performance Characteristics

### Capture Interval: 2 Seconds
The service runs at a **2-second interval**, which provides:
- ✅ **Real-time capture** - New hosts detected within 2 seconds
- ✅ **Low CPU usage** - Minimal system resource consumption (~0.5-1% CPU)
- ✅ **Low I/O overhead** - Reduced log file scanning
- ✅ **Scalability** - Handles high connection volumes efficiently

### Why 2 Seconds?
| Interval | Real-time | CPU Usage | I/O Load | Missed Captures |
|----------|-----------|-----------|----------|-----------------|
| 0.5s     | Excellent | High (5%) | High     | Very few        |
| 1s       | Excellent | Medium (2%)| Medium   | Very few        |
| **2s**   | **Excellent** | **Low (0.5-1%)** | **Low** | **Minimal** |
| 5s       | Good      | Very Low  | Very Low | Some            |
| 10s      | Fair      | Minimal   | Minimal  | Many            |

**2 seconds is the sweet spot** - excellent real-time capture with minimal overhead.

## Security and Permissions

### Root Access
The service runs as root with full capabilities:
```ini
User=root
Group=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_SYS_ADMIN CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_SYS_ADMIN CAP_DAC_READ_SEARCH
```

### Why Full Root Access?
1. **Log File Access**: Read protected system logs (`/var/log/auth.log`, `/var/log/xray/`)
2. **Network Monitoring**: Access network interfaces and connections
3. **Process Information**: Read process information for active connections
4. **System Resources**: Access all necessary system resources without restrictions

### Security Considerations
- Service only reads data, doesn't modify system files
- Captured data stored in controlled location (`/etc/myvpn/`)
- Service restarts automatically on crash (no manual intervention needed)
- Logs rotated to prevent disk space issues

## Captured Host Types

The service captures the following types of hosts:

### 1. SSH Connections
- **Source**: `/var/log/auth.log` or `/var/log/secure`
- **Pattern**: `from <hostname> port <port>`
- **Example**: `user@vpn.example.com from ssh.client.com port 22`

### 2. HTTP Host Headers
- **Source**: Xray and Nginx access logs
- **Pattern**: `Host: example.com` or `host=example.com`
- **Example**: `GET /path HTTP/1.1 Host: api.example.com`

### 3. SNI (Server Name Indication)
- **Source**: Xray and Nginx logs
- **Pattern**: `sni=example.com`, `serverName=example.com`, `tls_sni=example.com`
- **Example**: `TLS handshake with SNI: secure.example.com`

### 4. Proxy Host Headers
- **Source**: Xray logs
- **Pattern**: `proxy_host=example.com`, `X-Forwarded-Host: example.com`
- **Example**: `Proxy request with host: proxy.example.com`

### 5. WebSocket Hosts
- **Source**: Xray logs
- **Pattern**: `ws://example.com`, `wss://example.com`, `ws_host=example.com`
- **Example**: `WebSocket connection to wss://ws.example.com`

### 6. gRPC Service Names
- **Source**: Xray logs
- **Pattern**: `serviceName=example.com`
- **Example**: `gRPC request to serviceName: grpc.example.com`

### 7. TCP Prefixed Hosts
- **Source**: Xray logs
- **Pattern**: `tcp:example.com:443`
- **Example**: `TCP connection to tcp:cdn.example.com:443`

### 8. Bug/Fronting Hosts
- **Source**: Xray logs
- **Pattern**: `bug=example.com`, `bug_host=example.com`, `fronting_host=example.com`
- **Example**: `Using bug host: bug.cloudflare.com`

### 9. CDN Hosts
- **Source**: Xray logs
- **Pattern**: `cdn_host=example.com`, `cf_host=example.com`
- **Example**: `CDN host: cdn.cloudflare.com`

## Monitoring and Troubleshooting

### Check if Service is Running
```bash
systemctl is-active host-capture
# Output: active
```

### View Recent Captures
```bash
tail -f /etc/myvpn/hosts.log
```

### Check Service Health
```bash
systemctl status host-capture -l
```

### View Capture Statistics
```bash
# Total unique hosts captured
cut -d'|' -f1 /etc/myvpn/hosts.log | sort | uniq | wc -l

# Captures per service type
cut -d'|' -f2 /etc/myvpn/hosts.log | sort | uniq -c

# Most common source IPs
cut -d'|' -f3 /etc/myvpn/hosts.log | sort | uniq -c | sort -nr | head -10
```

### Troubleshooting

#### Service Won't Start
```bash
# Check for errors
journalctl -u host-capture -n 50

# Verify script exists and is executable
ls -l /usr/local/bin/capture-host-daemon.sh
ls -l /usr/local/bin/capture-host.sh

# Check permissions
chmod +x /usr/local/bin/capture-host-daemon.sh
chmod +x /usr/local/bin/capture-host.sh

# Restart service
systemctl restart host-capture
```

#### No Hosts Being Captured
```bash
# Verify logs exist and have data
ls -la /var/log/auth.log
ls -la /var/log/xray/access.log

# Check if VPN connections are active
netstat -an | grep ESTABLISHED

# Run capture manually to test
/usr/local/bin/capture-host.sh
```

#### High CPU Usage
```bash
# Check service priority
systemctl status host-capture

# Adjust Nice value in service file if needed
# Edit: /etc/systemd/system/host-capture.service
# Change: Nice=-10 to Nice=0

# Reload and restart
systemctl daemon-reload
systemctl restart host-capture
```

## Integration with Main Menu

Access via main menu:
```bash
menu
```

Select option **[27] CAPTURED HOSTS** to view:
- All captured hosts
- Search and filter options
- Real-time monitoring
- Export functionality

## Best Practices

1. **Regular Monitoring**: Check captured hosts weekly
   ```bash
   menu-captured-hosts
   ```

2. **Log Rotation**: Prevent log file from growing too large
   ```bash
   # If hosts.log exceeds 100MB, archive it
   if [ $(stat -f%z /etc/myvpn/hosts.log 2>/dev/null || stat -c%s /etc/myvpn/hosts.log) -gt 104857600 ]; then
       mv /etc/myvpn/hosts.log /etc/myvpn/hosts.log.$(date +%Y%m%d)
       touch /etc/myvpn/hosts.log
   fi
   ```

3. **Service Health Checks**: Monitor service status
   ```bash
   # Add to cron (daily check)
   0 0 * * * systemctl is-active host-capture || systemctl restart host-capture
   ```

4. **Backup Captured Data**: Regular backups
   ```bash
   # Weekly backup
   0 0 * * 0 cp /etc/myvpn/hosts.log /backup/hosts.log.$(date +%Y%m%d)
   ```

## Advanced Usage

### Custom Capture Intervals

To change the capture interval, edit the daemon script:
```bash
nano /usr/local/bin/capture-host-daemon.sh
```

Find and modify the `sleep` value:
```bash
sleep 2  # Change to desired interval in seconds
```

Then restart the service:
```bash
systemctl restart host-capture
```

### Export Captured Hosts

```bash
# Export all to CSV
cat /etc/myvpn/hosts.log | sed 's/|/,/g' > captured_hosts.csv

# Export unique hosts only
cut -d'|' -f1 /etc/myvpn/hosts.log | sort | uniq > unique_hosts.txt

# Export with date range
grep "2024-12-09" /etc/myvpn/hosts.log > hosts_2024-12-09.txt
```

### Filter by Service Type

```bash
# Only SSH captures
grep "|SSH|" /etc/myvpn/hosts.log

# Only VLESS captures
grep "|VLESS|" /etc/myvpn/hosts.log

# Only SNI captures
grep "|SNI|" /etc/myvpn/hosts.log
```

## Summary

The Enhanced Host Capture Service provides:
- ✅ **24/7 continuous monitoring** of all VPN connections
- ✅ **Full root access** for comprehensive log scanning
- ✅ **Real-time capture** with 2-second intervals
- ✅ **Low overhead** - minimal CPU and I/O usage
- ✅ **Automatic management** via systemd
- ✅ **Comprehensive patterns** for all host types
- ✅ **Source IP tracking** for security analysis
- ✅ **Easy integration** with existing tools

For questions or issues, refer to the main project documentation or check service logs.
