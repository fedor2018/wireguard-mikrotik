# wireguard-mikrotik
Генератор конфигураций wireguard для mikrotik и openwrt

За основу взят проект https://github.com/angristan/wireguard-install.git

Дополнительно создаются конфигурации в каталоге mikrotik:
- базовая для сервера (server.rsc)
- peer для сервера (\*-peer.rsc)
- настройки для клиентов (clients/\*.rsc)
- удаление всех настроек (remove.rsc)

Добавлено создание конфигов для openwrt:
- базовая для сервера (server.uci, network)
- peer для сервера (server.uci, network)
- настройки для клиентов (clients/\*.uci, clients/\*.cfg)

```
Запуск:
./wireguard-mikrotik.sh <config dir>
Первый запуск создает серверные настройки, повторные добавляются пиры
```

Проверены варианты:
- windows -> mikrotik
- android -> mikrotik
- mikrotik -> mikrotik
- openwrt -> mikrotik

----------------------------------------------------

wireguard configuration generator for mikrotik and openwrt

Based on the project https://github.com/angristan/wireguard-install.git

Additionally, configurations are created in the mikrotik directory:
- base for the server (server.rsc)
- peer for server (\*-peer.rsc)
- settings for clients (clients/\*.rsc)
- remove all settings (remove.rsc)

Added creation of configs for openwrt:
- base for the server (server.uci, network)
- peer for server (server.uci, network)
- settings for clients (clients/\*.uci, clients/\*.cfg)

```
Usage:
./wireguard-mikrotik.sh <config dir>
The first launch creates server settings, repeated peers are added
```

Configs tested:
- windows -> mikrotik
- android -> mikrotik
- mikrotik -> mikrotik
- openwrt -> mikrotik
