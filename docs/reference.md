# Справочник: все скрипты, флаги, переменные, файлы, коды выхода

Все скрипты запускаются на сервере под root (кроме `fleet.sh` — он запускается там, откуда есть ssh к серверам). Флаги и переменные ниже — из шапок самих скриптов; `./скрипт --help` печатает то же.

## `install-node.sh`

```
sudo ./install-node.sh --secret KEY [--bridge] [--panel-ip IP --open PORTS] [--image IMG] [--port N] [--no-tune] [--force] [--dry-run]
```

| флаг | что делает |
|---|---|
| `--secret KEY` | SECRET_KEY ноды из панели |
| `--secret-file FILE` | файл с ключом или .env со строкой SECRET_KEY= |
| `--bridge` | скачать geodata (Loyalsoldier + runetfreedom) и смонтировать в контейнер |
| `--image IMG` | образ ноды; по умолчанию ghcr.io/remnawave/node:latest |
| `--port N` | порт API ноды, по умолчанию 3000 |
| `--panel-ip IP` | ufw: порт ноды только с IP панели; ssh (22 и реальный порт sshd) открывается первым |
| `--open PORTS` | клиентские порты через запятую, открыть для всех; только с --panel-ip |
| `--no-tune` | не трогать sysctl (BBR, буферы) |
| `--force` | переписать существующую установку; старые .env и compose сохраняются как *.bak-<дата> |
| `--dry-run` | показать план, ничего не делать |

**Коды выхода:** 0 — контейнер запущен и порт слушает; 1 — уже установлено без --force / контейнер не поднялся / порт не слушает (печатает лог); 2 — ошибка аргументов.  
**Пишет:** /opt/remnanode/.env (600), /opt/remnanode/docker-compose.yml, /var/lib/remnanode/*.dat (с --bridge), /etc/sysctl.d/99-node-kit-net.conf, правила ufw (с --panel-ip).

## `tune-net.sh`

```
sudo ./tune-net.sh [--undo]
```

| флаг | что делает |
|---|---|
| `--undo` | убрать файл настроек и вернуть cubic |

**Коды выхода:** 0.  
**Пишет:** /etc/sysctl.d/99-node-kit-net.conf.

## `tune-resilience.sh`

```
sudo ./tune-resilience.sh [--dry-run | --undo]
```

| флаг | что делает |
|---|---|
| `--dry-run` | показать значения по памяти сервера, ничего не менять |
| `--undo` | убрать файлы node-kit; earlyoom и своп остаются |

**Коды выхода:** 0 (без set -e: недоступные настройки пропускает с сообщением).  
**Пишет:** /etc/sysctl.d/98-node-kit-conntrack.conf, 97-node-kit-resilience.conf, 99-node-kit-queue.conf, 99-node-kit-smallram.conf (≤1,5 ГБ), /etc/modprobe.d/node-kit-conntrack.conf, /etc/modules-load.d/softdog.conf, /etc/systemd/system.conf.d/node-kit-watchdog.conf, /etc/default/earlyoom, /swapfile (≤1,5 ГБ).

## `geodata-update.sh`

```
sudo ./geodata-update.sh [--all] [--dry-run] [--install-timer]
```

| флаг | что делает |
|---|---|
| `--all` | обновить и Loyalsoldier geoip/geosite, не только runetfreedom |
| `--dry-run` | скачать и сравнить, ничего не менять |
| `--install-timer` | поставить копию в /usr/local/sbin и таймер: воскресенье 05:10 ± 10 мин |

**Коды выхода:** 0 — обновлено или не требуется; 1 — не скачалось / xray не поднялся (после отката).  
**Пишет:** /var/lib/remnanode/*.dat и *.bak, /usr/local/sbin/geodata-update.sh, юниты geodata-update.service/.timer.

## `probe-speed.sh`

```
./probe-speed.sh
```

**Коды выхода:** 0.  
**Пишет:** ничего.

## `probe-steal.sh`

```
./probe-steal.sh
```

**Коды выхода:** 0.  
**Пишет:** ничего.

## `health.sh`

```
./health.sh
```

**Коды выхода:** 0.  
**Пишет:** ничего.

## `fleet.sh`

```
./fleet.sh [-k ключ] [-j user@jump] [-p порт] СПИСОК СКРИПТ [-- аргументы скрипта]
```

| флаг | что делает |
|---|---|
| `-k ключ` | ssh-ключ |
| `-j user@host` | jump-хост (ProxyJump) |
| `-p порт` | ssh-порт серверов (22) |
| `СПИСОК` | файл «имя ip» по строке, # — комментарий; см. examples/nodes.txt |
| `СКРИПТ` | любой скрипт набора; передаётся через stdin, на серверы не копируется |
| `-- …` | аргументы скрипту, например `-- --dry-run` |

**Коды выхода:** 0 — на всех серверах успешно; 1 — есть ошибки (пишет, где).  
**Пишет:** ничего.

## `uninstall-node.sh`

```
sudo ./uninstall-node.sh
```

**Коды выхода:** 0.  
**Пишет:** удаляет по вашему ответу: /opt/remnanode, /var/lib/remnanode, файлы node-kit в sysctl.d, таймер geodata, выключает earlyoom.

## Переменные окружения

| переменная | где | что |
|---|---|---|
| `DUR` | probe-speed | секунд на источник (6) |
| `SRC_EU`, `SRC_RU` | probe-speed | свои источники замера (файл ≥ 1 ГБ по GET) |
| `DEBIAN_FRONTEND` | install-node, tune-resilience | выставляется в noninteractive сам |

## Что требуется на сервере

bash 4+, `curl` (install-node поставит сам), `iproute2` (`ss`, `ip`, `nstat` — есть везде), `docker` + `compose v2` (install-node поставит: из apt, а если там нет compose v2 — из репозитория Docker), `journalctl` для счётчика earlyoom в health. Root. KVM-виртуализация (на OpenVZ/LXC docker и настройки ядра недоступны).
