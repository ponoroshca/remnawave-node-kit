#!/usr/bin/env bash
# install-node.sh — нода или мост Remnawave на чистом Ubuntu/Debian одной командой.
#
#   sudo ./install-node.sh --secret <SECRET_KEY>                     # выходная нода
#   sudo ./install-node.sh --secret <SECRET_KEY> --bridge            # мост: + geodata для умной маршрутизации
#   sudo ./install-node.sh --secret-file node.env --bridge --panel-ip 203.0.113.5 --open 2053,2054
#   curl -fsSL <raw-url>/install-node.sh | sudo bash -s -- --secret <SECRET_KEY> --bridge
#
# Что делает: ставит docker (если нет), включает BBR и большие TCP-буферы, пишет
# /opt/remnanode/.env и docker-compose.yml, для моста скачивает geodata (Loyalsoldier +
# runetfreedom) с проверкой размера, поднимает контейнер и печатает строку RESULT.
# Если /opt/remnanode уже есть — останавливается; --force перепишет, сохранив старые файлы рядом.
#
# Флаги: --secret KEY | --secret-file FILE (файл с ключом или .env со строкой SECRET_KEY=)
#        --bridge            geodata + монтирование в контейнер (для мостов с правилами маршрутизации)
#        --image IMG         образ ноды (по умолчанию ghcr.io/remnawave/node:latest; нода не должна быть
#                            новее панели — при ошибках рукопожатия пиньте версию панели, см. docs/faq.md)
#        --port N            порт API ноды (3000)
#        --panel-ip IP       закрыть порт ноды для всех, кроме панели (ufw; ssh-порт определяется сам)
#        --open PORTS        клиентские порты, открыть для всех (например 2053,2054); только с --panel-ip
#        --no-tune           не трогать sysctl (BBR, буферы)
#        --force             переписать существующую установку (бэкап старых файлов)
#        --dry-run           только показать, что будет сделано
set -euo pipefail

SECRET=""; SECRET_FILE=""; BRIDGE=0; IMAGE="ghcr.io/remnawave/node:latest"; PORT=3000
PANEL_IP=""; OPEN=""; TUNE=1; FORCE=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --secret) SECRET="$2"; shift 2 ;;
    --secret-file) SECRET_FILE="$2"; shift 2 ;;
    --bridge) BRIDGE=1; shift ;;
    --image) IMAGE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --panel-ip) PANEL_IP="$2"; shift 2 ;;
    --open) OPEN="$2"; shift 2 ;;
    --no-tune) TUNE=0; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "неизвестный флаг: $1 (см. --help)"; exit 2 ;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "нужен root (sudo)"; exit 1; }
if [ -n "$SECRET_FILE" ]; then
  [ -f "$SECRET_FILE" ] || { echo "нет файла $SECRET_FILE"; exit 2; }
  SECRET=$(grep -m1 -oE '^SECRET_KEY=.*' "$SECRET_FILE" | cut -d= -f2- || true)
  [ -n "$SECRET" ] || SECRET=$(head -1 "$SECRET_FILE" | tr -d ' \r\n')
fi
[ -n "$SECRET" ] || { echo "нужен ключ ноды: --secret <SECRET_KEY> (панель → Nodes → карточка ноды) или --secret-file"; exit 2; }
[ ${#SECRET} -ge 20 ] || { echo "SECRET_KEY подозрительно короткий (${#SECRET} символов) — скопируйте целиком"; exit 2; }
[ -z "$OPEN" ] || [ -n "$PANEL_IP" ] || { echo "--open работает только вместе с --panel-ip"; exit 2; }

say() { echo "$@"; }

say "══ install-node: $(hostname) ($( [ "$BRIDGE" = 1 ] && echo мост || echo нода )) ══"
if [ -d /opt/remnanode ] && [ "$FORCE" != 1 ]; then
  say "СТОП: /opt/remnanode уже существует — здесь уже стоит нода. Чтобы переписать (старые файлы сохранятся рядом): --force"
  exit 1
fi
if [ "$DRY" = 1 ]; then
  say "  план: docker → $( [ "$TUNE" = 1 ] && echo 'BBR+буферы → ' )/opt/remnanode (.env, compose, образ $IMAGE, порт $PORT)$( [ "$BRIDGE" = 1 ] && echo ' → geodata в /var/lib/remnanode' )$( [ -n "$PANEL_IP" ] && echo " → ufw: $PORT только с $PANEL_IP${OPEN:+, открыть $OPEN}" ) → docker compose up -d"
  exit 0
fi

# ── docker ─────────────────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
if ! command -v docker >/dev/null 2>&1; then
  say "  docker: ставлю…"
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq docker.io docker-compose-v2 >/dev/null 2>&1 \
    || apt-get install -y -qq docker.io docker-compose-plugin >/dev/null 2>&1 \
    || { echo "не удалось поставить docker через apt — поставьте вручную (https://docs.docker.com/engine/install/) и запустите снова"; exit 1; }
  systemctl enable --now docker >/dev/null 2>&1
fi
docker compose version >/dev/null 2>&1 || { echo "нет docker compose (v2) — apt-get install docker-compose-v2 или docker-compose-plugin"; exit 1; }
say "  docker: $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1), compose: $(docker compose version --short 2>/dev/null)"

# ── сеть ───────────────────────────────────────────────────────────────────────
if [ "$TUNE" = 1 ]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)"
  if [ -f "$HERE/tune-net.sh" ]; then bash "$HERE/tune-net.sh" | sed 's/^/  /'
  else
    modprobe tcp_bbr 2>/dev/null || true
    memkb=$(awk '/MemTotal/{print $2}' /proc/meminfo); buf=67108864; [ "$memkb" -le 1500000 ] && buf=8388608
    cat > /etc/sysctl.d/99-node-kit-net.conf <<NET
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=$buf
net.core.wmem_max=$buf
net.ipv4.tcp_rmem=4096 87380 $buf
net.ipv4.tcp_wmem=4096 65536 $buf
net.ipv4.tcp_mtu_probing=1
NET
    sysctl -q -p /etc/sysctl.d/99-node-kit-net.conf 2>/dev/null || true
    say "  сеть: cc=$(sysctl -n net.ipv4.tcp_congestion_control), буферы $((buf/1048576)) МБ"
  fi
fi

# ── geodata (мост) ─────────────────────────────────────────────────────────────
VOLUMES=""
if [ "$BRIDGE" = 1 ]; then
  mkdir -p /var/lib/remnanode && cd /var/lib/remnanode
  get() {  # <файл> <url> <мин.байт> — качаем, только если ещё нет годного; неудача не валит скрипт
    if [ -s "$1" ] && [ "$(stat -c %s "$1")" -ge "$3" ]; then say "  geodata: $1 уже есть"; return 0; fi
    if curl -sL --fail --max-time 300 --retry 3 --retry-delay 3 -o "$1.part" "$2" && [ "$(stat -c %s "$1.part" 2>/dev/null || echo 0)" -ge "$3" ]; then
      mv "$1.part" "$1"; say "  geodata: $1 скачан ($(( $(stat -c %s "$1") / 1048576 )) МБ)"
    else rm -f "$1.part"; say "  geodata: $1 НЕ СКАЧАЛСЯ"; fi
  }
  B1=https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download
  B2=https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download
  get geoip.dat                "$B1/geoip.dat"   5000000
  get geosite.dat              "$B1/geosite.dat" 5000000
  get runetfreedom-geoip.dat   "$B2/geoip.dat"   5000000
  get runetfreedom-geosite.dat "$B2/geosite.dat" 20000000
  for f in geoip.dat geosite.dat runetfreedom-geoip.dat runetfreedom-geosite.dat; do
    [ -s "/var/lib/remnanode/$f" ] || { echo "ОШИБКА: нет /var/lib/remnanode/$f. С этого сервера GitHub не тянется? Скачайте файл на другой машине и положите сюда (scp), затем запустите снова."; exit 1; }
  done
  VOLUMES=$'    volumes:\n      - /var/lib/remnanode/geoip.dat:/usr/local/share/xray/geoip.dat\n      - /var/lib/remnanode/geosite.dat:/usr/local/share/xray/geosite.dat\n      - /var/lib/remnanode/runetfreedom-geoip.dat:/usr/local/share/xray/runetfreedom-geoip.dat\n      - /var/lib/remnanode/runetfreedom-geosite.dat:/usr/local/share/xray/runetfreedom-geosite.dat'
fi

# ── конфиг и запуск ────────────────────────────────────────────────────────────
mkdir -p /opt/remnanode
ts=$(date +%Y%m%d-%H%M%S)
for f in .env docker-compose.yml; do
  [ -f "/opt/remnanode/$f" ] && cp -a "/opt/remnanode/$f" "/opt/remnanode/$f.bak-$ts" && say "  бэкап: /opt/remnanode/$f.bak-$ts"
done
umask 077
cat > /opt/remnanode/.env <<ENV
### NODE ###
NODE_PORT=$PORT

### XRAY ###
SECRET_KEY=$SECRET

XTLS_API_PORT=61000
ENV
umask 022
cat > /opt/remnanode/docker-compose.yml <<COMPOSE
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: $IMAGE
    env_file:
      - .env
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
${VOLUMES}
COMPOSE
cd /opt/remnanode && { docker compose up -d 2>&1 | tail -2 | sed 's/^/  /'; } || { echo "ОШИБКА: контейнер не поднялся — смотрите вывод выше (образ не скачался? docker compose logs remnanode)"; exit 1; }

# ── файрвол ────────────────────────────────────────────────────────────────────
if [ -n "$PANEL_IP" ]; then
  if command -v ufw >/dev/null 2>&1; then
    # ssh открываем ПЕРВЫМ: и стандартный 22, и тот порт, на котором sshd реально слушает
    sshp=$(ss -ltnp 2>/dev/null | awk '/sshd/{print $4}' | grep -oE '[0-9]+$' | sort -u | head -1); sshp=${sshp:-22}
    ufw allow 22/tcp >/dev/null; [ "$sshp" != 22 ] && ufw allow "$sshp/tcp" >/dev/null
    ufw allow from "$PANEL_IP" to any port "$PORT" proto tcp >/dev/null
    for p in $(echo "$OPEN" | tr ',' ' '); do ufw allow "$p/tcp" >/dev/null; done
    ufw --force enable >/dev/null 2>&1
    say "  ufw: ssh $sshp открыт, порт $PORT только с $PANEL_IP${OPEN:+, открыты $OPEN}"
  else
    say "  ufw не установлен — файрвол не настроен (apt-get install ufw и запустите снова с --panel-ip)"
  fi
fi

sleep 8
st=$(docker ps --format '{{.Status}}' --filter name=remnanode)
xv=$(docker exec remnanode xray version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
lst=$(ss -ltn 2>/dev/null | grep -c ":$PORT " || true)
say "RESULT $(hostname): контейнер=[${st:-нет}] xray=${xv:-?} порт $PORT слушает=$([ "$lst" -gt 0 ] && echo да || echo НЕТ)"
if [ -z "$st" ] || [ "$lst" -eq 0 ]; then
  say "Порт не слушает — последние строки лога контейнера:"
  docker logs --tail 8 remnanode 2>&1 | sed 's/^/  │ /'
  say "Если там «Please fix your .env file» — SECRET_KEY неверный или обрезан: возьмите его в панели заново и запустите с --force."
  exit 1
fi
say "Дальше: в панели нода должна стать «на связи»; привяжите ей профиль и инбаунды. Здоровье: ./health.sh"
