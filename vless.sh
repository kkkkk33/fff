#!/bin/bash

# ==========================================
# 1. 自定义配置区
# ==========================================
TG_TOKEN="8526087156:AAHR5forb44MA061r0zgcPMiGtkkxHD5K6o"
TG_CHAT_ID="6303873752"
PORT=52254
UUID=$(cat /proc/sys/kernel/random/uuid)
DEST_DOMAIN="://apple.com"
SNI_DOMAIN="://apple.com"

# ==========================================
# 2. 基础环境安装与内核转发
# ==========================================
sudo apt-get update && sudo apt-get install -y ca-certificates curl jq docker.io docker-compose
sudo systemctl enable --now docker
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# ==========================================
# 3. 准备 Reality 密钥对并生成配置
# ==========================================
WORKDIR="$HOME/vless_isolated"
mkdir -p "$WORKDIR" && cd "$WORKDIR" || exit 1

KEY_PAIR=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair)
PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "PrivateKey" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "PublicKey" | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

cat <<EOT > config.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [{ "tag": "dns-remote", "address": "https://223.5.5", "detour": "direct" }],
    "strategy": "ipv4_only"
  },
  "inbounds": [{
    "type": "vless",
    "tag": "vless-in",
    "listen": "::",
    "listen_port": $PORT,
    "users": [{ "uuid": "$UUID" }],
    "tls": {
      "enabled": true,
      "server_name": "$SNI_DOMAIN",
      "reality": {
        "enabled": true,
        "handshake": { "server": "$DEST_DOMAIN" },
        "private_key": "$PRIVATE_KEY",
        "short_id": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOT

cat <<EOT > docker-compose.yml
version: '3'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: vless-isolated
    restart: always
    ports: ["$PORT:$PORT/tcp", "$PORT:$PORT/udp"]
    volumes: [./config.json:/etc/sing-box/config.json]
    command: run -c /etc/sing-box/config.json
EOT

# ==========================================
# 4. 启动服务与 Telegram 推送
# ==========================================
docker compose up -d 2>/dev/null || docker-compose up -d
IP=$(curl -s https://ipify.org)
RAW_LINK="vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI_DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID#SingBox_VLESS_$IP"

curl -s -X POST "https://telegram.org" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$RAW_LINK" >/dev/null
