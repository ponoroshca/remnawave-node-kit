#!/usr/bin/env bash
# tune-resilience.sh — «чтобы такого больше не было»: настройки, после которых нода не
# зависает молча и не роняет соединения под нагрузкой. Запускать на ноде или мосту (root).
#
# Что ставит и почему (подробно — docs/tuning.md):
#   • conntrack по памяти + короткие таймауты — иначе при 3–7 тыс. соединений таблица
#     переполняется и ядро МОЛЧА выбрасывает новые соединения;
#   • очередь приёма (somaxconn / syn_backlog 32768) — переполнение = клиент заходит
#     со второй попытки; xray читает её при старте, поэтому потом нужен рестарт remnanode;
#   • softdog + systemd-watchdog + авторебут при панике — завис ядра лечится за минуту сам;
#   • earlyoom с приоритетом «сначала убить xray, но не sshd/docker» — вместо зависания
#     по памяти; на серверах ≤ 1,5 ГБ порог мягче и добавляется своп 2 ГБ.
#
#   sudo ./tune-resilience.sh             # применить
#   sudo ./tune-resilience.sh --dry-run   # показать значения, ничего не менять
#   sudo ./tune-resilience.sh --undo      # убрать файлы node-kit (earlyoom и своп остаются)
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root (sudo)"; exit 1; }
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
if [ "${1:-}" = "--undo" ]; then
  rm -f /etc/sysctl.d/98-node-kit-conntrack.conf /etc/sysctl.d/97-node-kit-resilience.conf /etc/sysctl.d/99-node-kit-smallram.conf /etc/sysctl.d/99-node-kit-queue.conf /etc/modprobe.d/node-kit-conntrack.conf /etc/systemd/system.conf.d/node-kit-watchdog.conf
  sysctl -q --system >/dev/null 2>&1 || true; systemctl daemon-reexec 2>/dev/null || true
  echo "$(hostname): файлы node-kit убраны (earlyoom и своп не трогал)"; exit 0
fi
export DEBIAN_FRONTEND=noninteractive
memkb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
if   [ "$memkb" -gt 3000000 ]; then CT=524288
elif [ "$memkb" -gt 1500000 ]; then CT=262144
else CT=131072; fi
EOM=8; [ "$memkb" -le 1500000 ] && EOM=4
if [ "$DRY" = 1 ]; then
  echo "$(hostname): память $((memkb/1024)) МБ → conntrack_max=$CT hashsize=$((CT/4)), earlyoom порог ${EOM}%, somaxconn=32768, watchdog softdog 60с, panic-ребут 10с$( [ "$memkb" -le 1500000 ] && echo ', своп 2 ГБ, буферы 8 МБ' )"
  exit 0
fi
cat > /etc/sysctl.d/98-node-kit-conntrack.conf <<X
net.netfilter.nf_conntrack_max=$CT
net.netfilter.nf_conntrack_tcp_timeout_established=7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=30
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=120
X
echo "options nf_conntrack hashsize=$((CT/4))" > /etc/modprobe.d/node-kit-conntrack.conf
modprobe nf_conntrack 2>/dev/null || true
echo $((CT/4)) > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
sysctl -q -p /etc/sysctl.d/98-node-kit-conntrack.conf 2>/dev/null || true
cat > /etc/sysctl.d/97-node-kit-resilience.conf <<X
kernel.panic=10
kernel.panic_on_oops=1
vm.min_free_kbytes=49152
X
sysctl -q -p /etc/sysctl.d/97-node-kit-resilience.conf 2>/dev/null || true
cat > /etc/sysctl.d/99-node-kit-queue.conf <<X
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 32768
X
sysctl -q -p /etc/sysctl.d/99-node-kit-queue.conf 2>/dev/null || true
modprobe softdog 2>/dev/null || true
echo softdog > /etc/modules-load.d/softdog.conf
mkdir -p /etc/systemd/system.conf.d
printf "[Manager]\nRuntimeWatchdogSec=60\nShutdownWatchdogSec=5min\n" > /etc/systemd/system.conf.d/node-kit-watchdog.conf
systemctl daemon-reexec 2>/dev/null || true
if ! command -v earlyoom >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq earlyoom >/dev/null 2>&1 || true
fi
if command -v earlyoom >/dev/null 2>&1; then
  printf 'EARLYOOM_ARGS="-m %s -s 100 -r 3600 --avoid (^|/)(sshd|systemd|dockerd|containerd|node_exporter)$ --prefer (^|/)xray$"\n' "$EOM" > /etc/default/earlyoom
  systemctl enable earlyoom >/dev/null 2>&1; systemctl restart earlyoom 2>/dev/null; EO=on
else EO=absent; fi
if [ "$memkb" -le 1500000 ]; then
  swapmb=$(free -m | awk '/Swap:/{print $2}')
  if [ "$swapmb" -lt 1500 ]; then
    if [ -f /swapfile ]; then swapoff /swapfile 2>/dev/null || true; rm -f /swapfile; fi
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  fi
  cat > /etc/sysctl.d/99-node-kit-smallram.conf <<X
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.ipv4.tcp_rmem=4096 87380 8388608
net.ipv4.tcp_wmem=4096 65536 8388608
X
  sysctl -q -p /etc/sysctl.d/99-node-kit-smallram.conf 2>/dev/null || true
fi
WD=$([ -e /dev/watchdog ] && echo on || echo off)
echo "DONE $(hostname): conntrack=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo ?) est_timeout=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established 2>/dev/null || echo ?) watchdog=$WD earlyoom=$EO somaxconn=$(cat /proc/sys/net/core/somaxconn) swap=$(free -m | awk '/Swap:/{print $2}')M"
echo "Очередь приёма применится к xray после рестарта: docker restart remnanode (лучше ночью)"
