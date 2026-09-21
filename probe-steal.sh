#!/usr/bin/env bash
# probe-steal.sh — steal time: сколько процессорного времени у вашей виртуалки забирает
# гипервизор. Высокий steal = хостер перепродал сервер; для видео это рывки и «зависания»,
# даже когда полоса и load выглядят приемлемо. Меряем по дельте /proc/stat за 8 секунд.
#   ./probe-steal.sh          → «ядер 2 | steal 3% | softirq 4% | idle 80% | load 0.41»
# Ориентир: steal до 5% — норма, 10–15% — заметно, ≥ 20% — менять хостера/тариф.
read -r _ u1 n1 s1 i1 w1 h1 sq1 st1 _ < /proc/stat
sleep 8
read -r _ u2 n2 s2 i2 w2 h2 sq2 st2 _ < /proc/stat
du=$((u2-u1)); dn=$((n2-n1)); ds=$((s2-s1)); di=$((i2-i1)); dw=$((w2-w1)); dh=$((h2-h1)); dsq=$((sq2-sq1)); dst=$((st2-st1))
tot=$((du+dn+ds+di+dw+dh+dsq+dst)); [ "$tot" -eq 0 ] && { echo "нет данных"; exit 0; }
printf "%s: ядер %s | steal %d%% | softirq %d%% | idle %d%% | load %s\n" "$(hostname)" "$(nproc)" $((dst*100/tot)) $((dsq*100/tot)) $((di*100/tot)) "$(cut -d' ' -f1 /proc/loadavg)"
