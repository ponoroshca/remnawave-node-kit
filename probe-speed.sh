#!/usr/bin/env bash
# probe-speed.sh — замер полосы ноды: 8 параллельных потоков, отдельно Европа и РФ.
# Считает по счётчикам интерфейса и ВЫЧИТАЕТ текущую нагрузку клиентов — иначе на живой
# ноде замер завышен на величину рабочего трафика. Однопоточный замер занижает (упирается
# в RTT), поэтому 8 потоков. curl -4: IPv6-ловушка давала «0 Мбит» на ровном месте.
#
#   ./probe-speed.sh                 # 6 секунд на источник
#   DUR=10 ./probe-speed.sh          # дольше
#   SRC_EU=https://… SRC_RU=http://… ./probe-speed.sh   # свои источники (файл ≥ 1 ГБ, отдаётся по GET)
set -u
command -v curl >/dev/null || { echo "нужен curl (apt-get install curl)"; exit 1; }
DUR=${DUR:-6}
SRC_EU=${SRC_EU:-https://fsn1-speed.hetzner.com/1GB.bin}
SRC_RU=${SRC_RU:-http://speedtest.selectel.ru/1GB}
IF=$(ip -o -4 route show default | awk '{print $5}' | head -1)
[ -n "$IF" ] || { echo "не нашёл интерфейс с маршрутом по умолчанию"; exit 1; }
echo "$(hostname): ядер $(nproc), интерфейс $IF"
probe() {
  local url="$1" label="$2" r1 r2 base total net
  r1=$(cat /sys/class/net/$IF/statistics/rx_bytes); sleep 2; r2=$(cat /sys/class/net/$IF/statistics/rx_bytes)
  base=$(( (r2 - r1) / 2 ))
  r1=$(cat /sys/class/net/$IF/statistics/rx_bytes)
  for i in 1 2 3 4 5 6 7 8; do curl -4 -s --max-time "$DUR" -o /dev/null "$url" & done; wait
  r2=$(cat /sys/class/net/$IF/statistics/rx_bytes)
  total=$(( (r2 - r1) / DUR )); net=$(( total - base )); [ "$net" -lt 0 ] && net=0
  printf "  %-8s %5d Мбит/с   (фон клиентов %d Мбит/с)\n" "$label" $(( net * 8 / 1000000 )) $(( base * 8 / 1000000 ))
}
probe "$SRC_EU" "Европа"
probe "$SRC_RU" "РФ"
echo "  замер занижен, если источник далеко или сам ограничен; 0 = источник недоступен с этого сервера"
