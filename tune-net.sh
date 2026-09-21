#!/usr/bin/env bash
# tune-net.sh — BBR + большие TCP-буферы. Запускать на ноде или мосту (root).
#
# Зачем: одиночный поток через межконтинентальный линк упирается в окно TCP. На хопе
# мост → нода с cubic и буфером 208 КБ было 87 Мбит/с, с BBR и 64 МБ — 600 Мбит/с.
# На серверах с памятью ≤ 1,5 ГБ буферы 8 МБ — иначе память уйдёт в сокеты.
#
#   sudo ./tune-net.sh            # применить (файл /etc/sysctl.d/99-node-kit-net.conf)
#   sudo ./tune-net.sh --undo     # убрать файл и вернуть значения ядра по умолчанию
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root (sudo)"; exit 1; }
F=/etc/sysctl.d/99-node-kit-net.conf
if [ "${1:-}" = "--undo" ]; then
  rm -f "$F"; sysctl -q -w net.ipv4.tcp_congestion_control=cubic net.core.default_qdisc=fq_codel 2>/dev/null || true
  sysctl -q --system >/dev/null 2>&1 || true; echo "$(hostname): tune-net убран, cc=$(sysctl -n net.ipv4.tcp_congestion_control)"; exit 0
fi
modprobe tcp_bbr 2>/dev/null || true
memkb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
buf=67108864; [ "$memkb" -le 1500000 ] && buf=8388608
cat > "$F" <<NET
# node-kit: BBR + буферы (${buf} байт). Убрать: tune-net.sh --undo
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=$buf
net.core.wmem_max=$buf
net.ipv4.tcp_rmem=4096 87380 $buf
net.ipv4.tcp_wmem=4096 65536 $buf
net.ipv4.tcp_mtu_probing=1
NET
sysctl -q -p "$F" 2>/dev/null || echo "  sysctl не применился (контейнер или нет прав?) — файл $F записан, применится после перезагрузки"
echo "$(hostname): cc=$(sysctl -n net.ipv4.tcp_congestion_control) qdisc=$(sysctl -n net.core.default_qdisc) буферы=$((buf/1048576))МБ (память $((memkb/1024))МБ)"
