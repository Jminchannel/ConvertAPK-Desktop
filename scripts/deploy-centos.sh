#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/convertapk"
DATA_DIR="/data/convertapk"
REPO_URL="${REPO_URL:-}"

echo "=== ConvertAPK deploy (CentOS 7.9) ==="

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root." >&2
  exit 1
fi

echo "[1/6] Installing dependencies..."
yum update -y
yum install -y yum-utils git nginx

if ! command -v docker >/dev/null 2>&1; then
  echo "[2/6] Installing Docker..."
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum install -y docker-ce docker-ce-cli containerd.io
  systemctl enable --now docker
else
  systemctl enable --now docker
fi

if ! command -v docker-compose >/dev/null 2>&1; then
  echo "[3/6] Installing docker-compose..."
  curl -L https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

echo "[4/6] Preparing directories..."
mkdir -p "$DATA_DIR/gradle-cache"

if [[ ! -d "$APP_DIR/.git" ]]; then
  if [[ -z "$REPO_URL" ]]; then
    echo "REPO_URL is empty. Export REPO_URL and re-run." >&2
    exit 1
  fi
  echo "[5/6] Cloning repo..."
  rm -rf "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
else
  echo "[5/6] Updating repo..."
  cd "$APP_DIR"
  git pull --rebase
fi

echo "[6/6] Configuring Nginx and starting services..."
cp -f "$APP_DIR/scripts/nginx/convertapk.conf" /etc/nginx/conf.d/convertapk.conf
nginx -t
systemctl enable --now nginx
systemctl restart nginx

cd "$APP_DIR"
docker-compose up -d --build

echo "=== Done ==="
echo "Frontend: http://<server-ip>/"
echo "API: http://<server-ip>/api/"
