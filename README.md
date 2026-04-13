 <p align="center">


<h2 align="center">
Auto Script Install XRAY/SSH Websocket Service
Mod By LamonLind
<img src="https://img.shields.io/badge/Release-v3.0-red.svg"></h2>

</p> 
<h2 align="center"> Supported Linux Distribution</h2>
<p align="center"><img src="https://d33wubrfki0l68.cloudfront.net/5911c43be3b1da526ed609e9c55783d9d0f6b066/9858b/assets/img/debian-ubuntu-hover.png"width="400"></p> 
<p align="center">
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%209&message=Stretch&color=purple"> 
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2010&message=Buster&color=purple">  
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2011&message=bullseye&color=purple"> 
<p align="center">
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=ubuntu%2018.04 LTS&message=Bionic Beaver&color=red"> 
<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=ubuntu%2020.04 LTS&message=Focal Fossa&color=red"> 
</p>



<h2 align="center">Network VPN</h2>

<h2 align="center">

![Hits](https://img.shields.io/badge/SSH-Websocket-8020f3?style=for-the-badge&logo=Cloudflare&logoColor=white&edge_flat=false)
![Hits](https://img.shields.io/badge/XRAY-Vmess-f34b20?style=for-the-badge&logo=Cloudflare&logoColor=white&edge_flat=false)
![Hits](https://img.shields.io/badge/XRAY-VLess-f34b20?style=for-the-badge&logo=Cloudflare&logoColor=white&edge_flat=false)
![Hits](https://img.shields.io/badge/XRAY-Trojan-f34b20?style=for-the-badge&logo=Cloudflare&logoColor=white&edge_flat=false)
</h2>

PLEASE MAKE SURE YOUR DOMAIN SETTINGS IN YOUR CLOUDFLARE AS BELOW (SSL/TLS SETTINGS)<br>
<br>

1. Your SSL/TLS encryption mode is Full
2. Enable SSL/TLS Recommender ✅
3. Edge Certificates > Disable Always Use HTTPS (off)

<br>
♦️ For Debian 9 / 10 / 11 For First Time Installation (Update Repo) <br>
 
  ```html
 apt update -y && apt upgrade -y && apt dist-upgrade -y && reboot
  ```
  ♦️ For Ubuntu 18.04 / 20.04 For First Time Installation (Update Repo) <br>
  
  ```html
 apt-get update && apt-get upgrade -y && apt dist-upgrade -y && update-grub && reboot
 ```

## ✨ New Features

### 🎯 Bandwidth Quota System (3x-ui Style)
- **Per-user data quotas** for VLESS, VMESS, Trojan, and Shadowsocks
- Automatic quota enforcement when limit exceeded
- Easy quota management via command-line tools
- Supports GB, MB, TB units
- Real-time traffic monitoring
- **NEW: User quota reset** - Reset bandwidth usage and re-enable users
- **NEW: Automatic Xray restart** after quota reset
- See [BANDWIDTH_QUOTA_GUIDE.md](BANDWIDTH_QUOTA_GUIDE.md) for details
- See [USER_QUOTA_RESET_GUIDE.md](USER_QUOTA_RESET_GUIDE.md) for reset feature

### 📡 Host Capture System
- Captures all incoming hosts/domains from VPN connections
- Tracks source IP addresses
- Prevents duplicate entries
- Real-time monitoring with 2-second intervals
- **NEW: Systemd service daemon** for continuous 24/7 monitoring
- **NEW: Full root access** for comprehensive log scanning
- **NEW: Enhanced patterns** - TCP, WebSocket, Bug hosts, CDN hosts
- See [HOST_CAPTURE_GUIDE.md](HOST_CAPTURE_GUIDE.md) for details
- See [HOST_CAPTURE_SERVICE_GUIDE.md](HOST_CAPTURE_SERVICE_GUIDE.md) for service details

♦️ Installation Link <br>

  ```html
apt --fix-missing update && apt update && apt upgrade -y && apt install -y bzip2 gzip coreutils screen dpkg wget vim curl nano zip unzip && wget -q https://raw.githubusercontent.com/SantanuDhibar/Blue/main/setup.sh && chmod +x setup.sh && screen -S setup ./setup.sh
  ```
IPV6 enable
```html
apt --fix-missing update && apt update && apt upgrade -y && apt install -y bzip2 gzip coreutils screen dpkg wget vim curl nano zip unzip && wget -q https://raw.githubusercontent.com/SantanuDhibar/Blue/main/setup2.sh && chmod +x setup2.sh && screen -S setup ./setup2.sh
  ```
<b>

[ SERVICES ] <br>
<br>
✅ SSH WEBSOCKET TLS & NON-TLS 443/80<br>
✅ XRAY VMESS WEBSOCKET TLS & NON-TLS 443/80<br>
✅ XRAY VLESS WEBSOCKET TLS & NON-TLS 443/80<br>
✅ XRAY TROJAN WEBSOCKET TLS & NON-TLS 443/80<br>
✅ XRAY VMESS XHTTP TLS & NON-TLS 443/80<br>
✅ XRAY VLESS XHTTP TLS & NON-TLS 443/80<br>
<br>

[ OTHER SERVICES ] <br>
<br>
✅ NEW UPDATE BBRPLUS 5.15.96 <br>
✅ BANDWITH MONITOR <br>
✅ RAM MONITOR <br>
✅ DNS CHANGER <br>
✅ NETFLIX REGION CHECKER <br>
✅ CHECK LOGIN USER <br>
✅ CHECK CREATED CONFIG <br>
✅ AUTOMATIC CLEAR LOG <br>
✅ AUTOMATIC VPS REBOOT <br>
✅ BACKUP & RESTORE <br>
✅ XRAYCORE CHANGER <br>
✅ VIRTUAL SWAPRAM <br>
✅ UPDATE SCRIPT (Component-based updates) <br>
✅ UNINSTALL SCRIPT (Complete removal) <br></br>


```

## Authorized Nginx/OpenResty Tunnel Generator

Generate an authorized reverse-proxy tunnel setup for Xray (VLESS + WebSocket) by scanning URL response headers and selecting only Nginx/OpenResty domains.

```bash
chmod +x ./build-authorized-nginx-xray-tunnel.sh

# using URL file
./build-authorized-nginx-xray-tunnel.sh \
  --input /path/to/urls.txt \
  --http-ports 80,8080 \
  --https-ports 443,8443 \
  --output-dir /tmp/nginx-xray-generated

# or direct URLs
./build-authorized-nginx-xray-tunnel.sh \
  https://example.com https://openresty.example.net
```

Output files:
- `header-analysis.tsv` (Server/Content-Type analysis per URL)
- `authorized-domains.txt` (only nginx/openresty domains)
- `xray-vless-ws.json` (VLESS+WS backend, default port `10000`, path `/vless`)
- `nginx-authorized-vless.conf` (`/` normal reverse proxy, `/vless` to Xray backend with Upgrade/Connection/Host headers)
- `deployment-steps.txt` (step-by-step deployment instructions)
   [ Service & Port ]
   - OpenSSH                 : 22
   - SSH Websocket           : 80
   - SSH SSL Websocket       : 443
   - Stunnel5                : 447, 777
   - Dropbear                : 109, 143
   - Badvpn                  : 7100-7300
   - Nginx                   : 81
   - XRAY Vmess GRPC         : 443
   - XRAY Vmess TLS          : 443
   - XRAY Vmess None TLS     : 80
   - XRAY Vmess XHTTP TLS    : 443
   - XRAY Vmess XHTTP None   : 80
   - XRAY Vless GRPC         : 443
   - XRAY Vless TLS          : 443
   - XRAY Vless None TLS     : 80
   - XRAY Vless XHTTP TLS    : 443
   - XRAY Vless XHTTP None   : 80
   - XRAY Trojan GRPC        : 443
   - XRAY Trojan GO          : 443
   - XRAY Trojan WS          : 443
   - Sodosok WS/GRPC         : 443

   [ Server Information & Other Features ]
   - Timezone                : Asia/Kuala_Lumpur (GMT +8)
   - Fail2Ban                : [ON]
   - Dflate                  : [ON]
   - IPtables                : [ON]
   - Auto-Reboot             : [ON] - 5.00 AM
   - IPv6                    : [OFF/ON]
   - Autoreboot Off          : [ON]
   - Autobackup Data         : [OFF]
   - AutoKill Multi Login User
   - Auto Delete Expired Account
   - Fully automatic script
   - VPS settings
   - Admin Control
   - Restore Data
   - Full Orders For Various Services
```

## Update & Uninstall Features

### Update Script
Update individual components or all scripts without full reinstallation:
```bash
# From command line
update

# Or from menu, select option 29
```

**Update Options:**
- Update all scripts (recommended)
- Update specific components (SSH, XRAY, Menus, Utilities)
- Check for version updates

### Uninstall Script
Completely remove Blue VPN Script from your system:
```bash
# From command line
uninstall

# Or from menu, select option 30
```

**Features:**
- Complete removal of all components
- Automatic backup before removal
- Safe confirmation required
- Service cleanup and firewall reset

📖 **For detailed documentation, see [UPDATE_UNINSTALL_GUIDE.md](UPDATE_UNINSTALL_GUIDE.md)**

```
