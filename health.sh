#!/usr/bin/env bash
# health.sh — одна строка здоровья узла (5 секунд замера). Гонять по ssh или через fleet.sh.
#   cores, cpu%, steal%, ретрансмиты%, память, своп, RSS xray, убийств earlyoom за 24 ч, аптайм дней,
#   возраст xray ч, соединений на портах xray, conntrack%, ошибок xray за 30 мин, переполнений
#   очереди приёма, контейнер, tx/rx Мбит.
# Что тревожит: st ≥ 15 (перепродан), retr ≥ 2 (потери), ct ≥ 80 (таблица соединений), ovf растёт
# (очередь приёма — см. tune-resilience.sh), oom > 0 (не хватает памяти), rn=0 (контейнер лежит).
read_stat(){ awk '/^cpu[0-9]/{print $1,$2+$3+$4+$7+$8,$5,$7,$9}' /proc/stat; }
IF=$(ip -o -4 route show default | awk '{print $5}' | head -1)
R1=$(cat /sys/class/net/$IF/statistics/rx_bytes); T1=$(cat /sys/class/net/$IF/statistics/tx_bytes)
A=$(read_stat); SA=$(awk '/^Tcp:/{a=$0} END{print a}' /proc/net/snmp | awk '{print $12,$13}')
sleep 5
B=$(read_stat); SB=$(awk '/^Tcp:/{a=$0} END{print a}' /proc/net/snmp | awk '{print $12,$13}')
R2=$(cat /sys/class/net/$IF/statistics/rx_bytes); T2=$(cat /sys/class/net/$IF/statistics/tx_bytes)
CPU=$(paste <(echo "$A") <(echo "$B") | awk '{tot=($7+$8)-($2+$3); if(tot>0){busy+=100*($7-$2)/tot; st+=100*($10-$5)/tot}; n++} END{printf "cpu=%d st=%d", busy/n, st/n}')
RET=$(echo "$SA $SB" | awk '{o=$3-$1; r=$4-$2; if (o<200) printf "retr=n/a"; else printf "retr=%.1f", 100*r/o}')   # мало трафика — процент не имеет смысла
MEM=$(free -m | awk '/Mem:/{printf "mem=%d/%d", $2-$7, $2}')
SWAP=$(free -m | awk '/Swap:/{print $3+0}')
XR=$(ps -o rss= -C rw-core -C xray 2>/dev/null | awk '{s+=$1} END{printf "%d", s/1024}')
OOM=$(journalctl -u earlyoom --since -24h --no-pager 2>/dev/null | grep -cE 'sending sig(term|kill) to' | head -1)
UP=$(awk '{printf "%d", $1/86400}' /proc/uptime)
XUP=$(ps -o etimes= -C rw-core -C xray 2>/dev/null | head -1 | awk '{printf "%d", $1/3600}')
PORTS=$(ss -ltnp 2>/dev/null | awk '/rw-core|xray/{print $4}' | grep -oE '[0-9]+$' | sort -u | grep -vE '^(3000|61000)$' | head -8 | tr '\n' ' ')
EST=0; for p in $PORTS; do EST=$((EST + $(ss -Htn state established "( sport = :$p )" | wc -l))); done
CT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
CTM=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 1)
ERR=$(docker logs --since 30m remnanode 2>&1 | grep -cE 'failed to dial|rejected|invalid request' | head -1)
OVF=$(nstat -az TcpExtListenOverflows 2>/dev/null | awk '/Overflows/{print $2}')
DOK=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^remnanode$' | head -1)
printf "%s cores=%s %s %s %s swap=%sM xray=%sM oom=%s upd=%s xrayh=%s ports=[%s] est=%s ct=%s%% err=%s ovf=%s rn=%s tx=%s rx=%s\n" \
  "$(hostname)" "$(nproc)" "$CPU" "$RET" "$MEM" "$SWAP" "${XR:-0}" "${OOM:-0}" "$UP" "${XUP:-0}" "${PORTS% }" "$EST" "$((100*CT/CTM))" "${ERR:-0}" "${OVF:-0}" "${DOK:-0}" \
  "$(( (T2-T1)*8/5/1000000 ))" "$(( (R2-R1)*8/5/1000000 ))"
