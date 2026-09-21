#!/usr/bin/env bash
# fleet.sh — прогнать любой скрипт набора на списке серверов по ssh, по одному, с итогом.
#
#   ./fleet.sh nodes.txt health.sh                       # здоровье всех
#   ./fleet.sh nodes.txt probe-steal.sh                  # steal на всех
#   ./fleet.sh -k ~/.ssh/id_ed25519 nodes.txt tune-resilience.sh -- --dry-run
#   ./fleet.sh -j root@203.0.113.5 nodes.txt health.sh   # через jump-хост (например, ноды за границей — через сервер в РФ)
#
# nodes.txt: по строке на сервер — «имя ip» или просто «ip»; # — комментарий. Пример: examples/nodes.txt
# Скрипт передаётся через stdin (bash -s), на серверы ничего не копируется.
set -uo pipefail
command -v ssh >/dev/null || { echo "нужен ssh-клиент"; exit 2; }
KEY=""; JUMP=""; PORT=22
while [ $# -gt 0 ]; do case "$1" in -k) KEY="$2"; shift 2 ;; -j) JUMP="$2"; shift 2 ;; -p) PORT="$2"; shift 2 ;; *) break ;; esac; done
LIST="${1:?файл со списком серверов}"; SCRIPT="${2:?скрипт}"; shift 2; [ "${1:-}" = "--" ] && shift
[ -f "$LIST" ] || { echo "нет файла $LIST"; exit 2; }
[ -f "$SCRIPT" ] || SCRIPT="$(dirname "$0")/$SCRIPT"; [ -f "$SCRIPT" ] || { echo "нет скрипта $2"; exit 2; }
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -p "$PORT")
[ -n "$KEY" ] && SSH+=(-i "$KEY")
[ -n "$JUMP" ] && SSH+=(-J "$JUMP")
ok=0; bad=0
while read -r name ip _; do
  [ -z "$name" ] || [ "${name:0:1}" = "#" ] && continue
  [ -z "$ip" ] && { ip="$name"; name="$ip"; }
  printf "── %s %s ──\n" "$name" "$ip"
  if "${SSH[@]}" "root@$ip" 'bash -s' -- "$@" < "$SCRIPT" 2>&1 | sed 's/^/  /'; then ok=$((ok+1)); else bad=$((bad+1)); echo "  ❌ $name: ошибка"; fi
done < "$LIST"
echo "итого: успешно $ok, с ошибкой $bad"
[ "$bad" -eq 0 ]
