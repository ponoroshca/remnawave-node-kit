#!/usr/bin/env bash
# uninstall-node.sh — снять ноду и настройки набора с сервера. Каждую часть спрашивает отдельно.
#   sudo ./uninstall-node.sh
set -u
[ "$(id -u)" = 0 ] || { echo "нужен root (sudo)"; exit 1; }
yes_no() { local a; read -r -p "$1 [y/N] " a; [ "${a,,}" = y ]; }
if [ -d /opt/remnanode ]; then
  if yes_no "остановить и удалить контейнер remnanode и /opt/remnanode (ключ ноды)?"; then
    (cd /opt/remnanode && docker compose down 2>/dev/null); rm -rf /opt/remnanode; echo "  удалено"
  fi
fi
[ -d /var/lib/remnanode ] && yes_no "удалить geodata (/var/lib/remnanode)?" && rm -rf /var/lib/remnanode && echo "  удалено"
if ls /etc/sysctl.d/*node-kit* >/dev/null 2>&1; then
  if yes_no "убрать настройки ядра node-kit (BBR, conntrack, очередь, watchdog)?"; then
    rm -f /etc/sysctl.d/*node-kit* /etc/modprobe.d/node-kit-conntrack.conf /etc/systemd/system.conf.d/node-kit-watchdog.conf
    sysctl -q --system >/dev/null 2>&1; systemctl daemon-reexec 2>/dev/null; echo "  убрано (значения ядра вернутся к умолчанию после перезагрузки)"
  fi
fi
systemctl list-unit-files geodata-update.timer >/dev/null 2>&1 && yes_no "убрать таймер обновления geodata?" && { systemctl disable --now geodata-update.timer 2>/dev/null; rm -f /etc/systemd/system/geodata-update.{service,timer} /usr/local/sbin/geodata-update.sh; systemctl daemon-reload; echo "  убран"; }
command -v earlyoom >/dev/null 2>&1 && yes_no "выключить earlyoom?" && { systemctl disable --now earlyoom 2>/dev/null; echo "  выключен (пакет остался)"; }
echo "Файрвол (ufw) и своп не трогал — их правила видны в «ufw status numbered» и /etc/fstab."
echo "Ноду в панели удалите руками: Nodes → карточка → Delete."
