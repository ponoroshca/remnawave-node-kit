# node-kit — install, tune and keep alive Remnawave nodes and bridges

*Русская версия — [README.md](README.md).*

Seven dependency-free bash scripts from running a few dozen nodes and bridges:

- `install-node.sh` — a node or a bridge on clean Ubuntu/Debian in one command (docker, BBR,
  `.env`, compose, geodata with size checks for bridges; never touches an existing install
  without `--force`; optional ufw with the panel IP);
- `tune-net.sh` — BBR + large TCP buffers: bridge → node hop went **87 → 600 Mbit/s**;
- `tune-resilience.sh` — conntrack sized by RAM, accept queue, watchdog, panic auto-reboot,
  earlyoom that kills xray first and never sshd/docker, swap for small boxes;
- `geodata-update.sh` — weekly routing-list refresh with a health check and rollback;
- `probe-speed.sh` (8 streams, minus client background), `probe-steal.sh`, `health.sh`;
- `fleet.sh` — run any of them over ssh across a list of servers.

```bash
git clone https://github.com/ponoroshca/remnawave-node-kit.git && cd remnawave-node-kit
sudo ./install-node.sh --secret <SECRET_KEY> --bridge --panel-ip <panel ip> --open 2053
sudo ./tune-resilience.sh && ./health.sh
```

Docs and messages are in Russian. MIT. Bridge watchdog with real-client probing lives in
[remnawave-bridge-guard](https://github.com/ponoroshca/remnawave-bridge-guard).
