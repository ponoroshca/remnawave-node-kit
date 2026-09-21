#!/usr/bin/env bash
# geodata-update.sh — обновление списков маршрутизации на мосту с проверкой и откатом.
#
# Зачем: списки runetfreedom (что в России заблокировано → пускать за границу) обновляются
# каждую неделю, а свежезаблокированные сайты в режиме «Авто» уходят «напрямую» и не
# открываются. Безопасность важнее свежести: качаем во временный файл, проверяем размер,
# сравниваем хэш (не изменилось — выходим тихо), бэкапим текущие, подменяем, перезапускаем
# remnanode и ЖДЁМ, что xray реально поднялся. Не поднялся за 90 с — ОТКАТ на бэкап.
#
#   sudo ./geodata-update.sh                  # обновить runetfreedom-geoip/geosite
#   sudo ./geodata-update.sh --all            # и Loyalsoldier geoip/geosite тоже
#   sudo ./geodata-update.sh --dry-run        # скачать и сравнить, ничего не менять
#   sudo ./geodata-update.sh --install-timer  # раз в неделю (вс 05:10 ± 10 мин) через systemd
set -u
DIR=/var/lib/remnanode
ALL=0; DRY=0
for a in "$@"; do case "$a" in --all) ALL=1 ;; --dry-run) DRY=1 ;; --install-timer) INSTALL=1 ;; -h|--help) sed -n '2,14p' "$0"; exit 0 ;; esac; done
[ "$(id -u)" = 0 ] || { echo "нужен root (sudo)"; exit 1; }
if [ "${INSTALL:-0}" = 1 ]; then
  install -m 755 "$0" /usr/local/sbin/geodata-update.sh
  cat > /etc/systemd/system/geodata-update.service <<'U'
[Unit]
Description=geodata-update: обновление списков маршрутизации с откатом
After=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/geodata-update.sh
U
  cat > /etc/systemd/system/geodata-update.timer <<'U'
[Unit]
Description=geodata-update — раз в неделю
[Timer]
OnCalendar=Sun 05:10
RandomizedDelaySec=600
Persistent=true
[Install]
WantedBy=timers.target
U
  systemctl daemon-reload && systemctl enable --now geodata-update.timer && echo "таймер включён: $(systemctl list-timers geodata-update.timer --no-pager | sed -n 2p | awk '{print $1, $2, $3}')"
  exit 0
fi
[ -d "$DIR" ] || { echo "нет $DIR — это не мост с geodata (install-node.sh --bridge)"; exit 1; }
log() { logger -t geodata-update "$1" 2>/dev/null; echo "$(date '+%F %T') $1"; }
fail() { log "❌ $1"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
B1=https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download
B2=https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download
# файл : url : минимальный размер (мусор/страница ошибки вместо файла — меньше)
SET=("runetfreedom-geoip.dat:$B2/geoip.dat:5000000" "runetfreedom-geosite.dat:$B2/geosite.dat:20000000")
[ "$ALL" = 1 ] && SET+=("geoip.dat:$B1/geoip.dat:5000000" "geosite.dat:$B1/geosite.dat:5000000")
changed=()
for item in "${SET[@]}"; do
  f=${item%%:*}; rest=${item#*:}; url=${rest%:*}; min=${rest##*:}
  curl -fsSL --max-time 900 --retry 3 -o "$TMP/$f" "$url" || fail "не скачался $f"
  sz=$(stat -c%s "$TMP/$f"); [ "$sz" -ge "$min" ] || fail "$f подозрительно мал: $sz байт"
  new=$(sha256sum "$TMP/$f" | cut -d' ' -f1); old=$(sha256sum "$DIR/$f" 2>/dev/null | cut -d' ' -f1 || echo none)
  [ "$new" = "$old" ] || changed+=("$f")
done
if [ ${#changed[@]} -eq 0 ]; then log "списки не изменились — обновление не требуется"; exit 0; fi
log "изменились: ${changed[*]}"
[ "$DRY" = 1 ] && { echo "[dry-run] ничего не меняю"; exit 0; }
for f in "${changed[@]}"; do cp -a "$DIR/$f" "$DIR/$f.bak" 2>/dev/null; install -m 644 "$TMP/$f" "$DIR/$f"; done
log "списки обновлены, перезапускаю remnanode"
docker restart remnanode >/dev/null 2>&1
healthy() {
  docker logs --since 3m remnanode 2>&1 | grep -q "is up and running" || return 1
  ss -ltnp 2>/dev/null | grep -qE "rw-core|xray" || return 1
}
ok=0; for i in $(seq 1 18); do sleep 5; healthy && { ok=1; break; }; done
if [ "$ok" = 1 ]; then log "✅ xray поднялся на новых списках"; exit 0; fi
log "⚠️ xray НЕ поднялся за 90 с — откатываю"
for f in "${changed[@]}"; do [ -f "$DIR/$f.bak" ] && cp -a "$DIR/$f.bak" "$DIR/$f"; done
docker restart remnanode >/dev/null 2>&1; sleep 30
if healthy; then fail "откат успешен, мост жив на СТАРЫХ списках. Новые файлы битые — разобраться вручную."; else fail "🔴 мост не поднялся даже после отката — нужно вмешательство!"; fi
