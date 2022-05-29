# wireguard-mikrotik
Генератор конфигураций wireguard для mikrotik

За основу взят проект https://github.com/angristan/wireguard-install.git

Дополнительно создаются конфигурации в каталоге mikrotik:
- базовая для сервера (server.rsc)
- peer для сервера (*-peer.rsc)
- настройки для клиентов (clients/*.rsc)
- удаление всех настроек (remove.rsc)

Добавлено создание конфигов для openwrt:
- базовая для сервера (server.uci, network)
- peer для сервера (server.uci, network)
- настройки для клиентов (clients/*.uci, clients/*.cfg)
```
Запуск:
./wireguard-mikrotik.sh <config dir>
Первый запуск создает серверные настройки, повторные добавляются пиры
```
Проверены варианты:
- mikrotik -> mikrotik
- openwrt -> mikrotik

