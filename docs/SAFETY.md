# Что меняет каждый скрипт и как это отменить

Все скрипты запускаются на самом сервере (или через `fleet.sh` по ssh) и не знают ни
адреса панели, ни API-токена. Ниже — полный список того, что они пишут.

## install-node.sh

| что | где | отмена |
|---|---|---|
| docker и compose из apt (только если нет) | системные пакеты | `apt-get remove docker.io` — обычно не нужно |
| BBR и буферы | `/etc/sysctl.d/99-node-kit-net.conf` | `tune-net.sh --undo` |
| ключ и порт ноды | `/opt/remnanode/.env` (права 600) | удалить папку |
| описание контейнера | `/opt/remnanode/docker-compose.yml` | `cd /opt/remnanode && docker compose down` |
| списки маршрутизации (`--bridge`) | `/var/lib/remnanode/*.dat` | удалить папку |
| файрвол (`--panel-ip`) | правила ufw: ssh-порт, порт ноды с IP панели, `--open` порты | `ufw status numbered` → `ufw delete N`; `ufw disable` |

Существующую установку не трогает без `--force`; с `--force` старые `.env` и `compose`
остаются рядом как `*.bak-<дата>`.

## tune-net.sh

`/etc/sysctl.d/99-node-kit-net.conf` — BBR, `fq`, буферы 64 МБ (8 МБ при памяти ≤ 1,5 ГБ),
`tcp_mtu_probing`. Действует сразу, рестарт не нужен. Отмена: `tune-net.sh --undo`.

## tune-resilience.sh

| что | где | отмена |
|---|---|---|
| conntrack: лимит по памяти (128k / 256k / 512k), таймауты | `/etc/sysctl.d/98-node-kit-conntrack.conf`, `/etc/modprobe.d/node-kit-conntrack.conf` | `--undo` |
| очередь приёма 32768 | `/etc/sysctl.d/99-node-kit-queue.conf` | `--undo` |
| авторебут при панике через 10 с | `/etc/sysctl.d/97-node-kit-resilience.conf` | `--undo` |
| watchdog: модуль softdog + systemd 60 с | `/etc/modules-load.d/softdog.conf`, `/etc/systemd/system.conf.d/node-kit-watchdog.conf` | `--undo` |
| earlyoom (пакет) с приоритетом «сначала xray, никогда sshd/docker» | `/etc/default/earlyoom` | `systemctl disable --now earlyoom` |
| своп 2 ГБ и буферы 8 МБ — только при памяти ≤ 1,5 ГБ | `/swapfile`, `/etc/fstab`, `/etc/sysctl.d/99-node-kit-smallram.conf` | `swapoff /swapfile; rm /swapfile` + строка в fstab |

Очередь приёма xray читает при старте — применится после `docker restart remnanode`.
Watchdog перезагрузит сервер, только если само ядро/systemd перестанут отвечать 60 секунд —
на живом сервере он не срабатывает.

## geodata-update.sh

Пишет в `/var/lib/remnanode/`: новые списки, предыдущие — рядом как `*.bak`. Перезапускает
`remnanode` и ждёт `is up and running` + слушающий порт xray; иначе возвращает `.bak` и
перезапускает снова. С `--install-timer` — копия в `/usr/local/sbin/`, юниты
`geodata-update.service/.timer` (воскресенье 05:10 ± 10 мин). Отмена таймера:
`systemctl disable --now geodata-update.timer`.

## probe-speed.sh, probe-steal.sh, health.sh

Только читают (`/proc`, `ss`, `docker logs`). `probe-speed.sh` на 6 секунд занимает канал
скачиванием — на нагруженной ноде клиенты это заметят; результат вычитает их трафик.

## fleet.sh

На серверы ничего не копирует: скрипт передаётся через stdin `ssh … 'bash -s'`.
