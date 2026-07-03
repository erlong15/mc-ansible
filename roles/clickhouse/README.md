# Роль `clickhouse`

Единая Ansible-роль для установки и настройки **ClickHouse Keeper** и **ClickHouse Server** на Ubuntu.

## Концепция

Роль объединяет два компонента в один переиспользуемый артефакт. Выбор компонента управляется переменной `clickhouse_component`:

- `keeper` — запускает отдельный процесс ClickHouse Keeper (ZooKeeper-совместимый координатор репликации)
- `server` — настраивает ClickHouse Server с конфигами для кластерной репликации

**Почему один пакет для обоих компонентов?** Пакет `clickhouse-keeper` конфликтует с `clickhouse-server` (оба предоставляют `clickhouse-server-common`). Бинарь `/usr/bin/clickhouse-keeper` — это симлинк на `/usr/bin/clickhouse`, который поставляется пакетом `clickhouse-server`. Поэтому Keeper запускается как отдельный systemd-сервис из общего бинаря.

## Переменные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `clickhouse_component` | — | **Обязательна.** `keeper` или `server` |
| `clickhouse_secret` | — | **Обязательна.** Секрет межсерверной аутентификации (из Vault) |
| `clickhouse_default_password` | — | **Обязательна.** Пароль пользователя `default` (из Vault) |
| `clickhouse_cluster_group` | `clickhouse` | Имя группы инвентори с нодами кластера |
| `clickhouse_version` | `25.8.*` | Маска версии для apt-preferences |
| `clickhouse_cluster_name` | `ch_cluster` | Имя кластера в `remote_servers.xml` |
| `clickhouse_tcp_port` | `9000` | TCP-порт Server |
| `clickhouse_http_port` | `8123` | HTTP-порт Server |
| `clickhouse_keeper_tcp_port` | `9181` | ZooKeeper-совместимый порт Keeper |
| `clickhouse_keeper_raft_port` | `9234` | Внутренний порт Raft-консенсуса |
| `clickhouse_repo_url` | `https://packages.clickhouse.com/deb` | URL deb-репозитория |

## Пример вызова

```yaml
# Плей 1: Keeper на всех нодах (bootstrap без serial)
- name: "Keeper-ансамбль"
  hosts: clickhouse
  become: true
  vars:
    clickhouse_component: keeper
  roles:
    - role: clickhouse

# Плей 2: Server rolling по одной ноде
- name: "ClickHouse Server"
  hosts: clickhouse
  become: true
  serial: 1
  vars:
    clickhouse_component: server
  roles:
    - role: clickhouse
```

## Требования

- Ubuntu 22.04 (jammy) или 24.04 (noble)
- `ansible-core >= 2.15` (модуль `deb822_repository`)
- Доступ к `packages.clickhouse.com` или зеркалу
- Переменные `clickhouse_secret` и `clickhouse_default_password` из Ansible Vault
- host_vars каждой ноды: `keeper_id`, `ch_shard`, `ch_replica`, `internal_ip`

## Структура директорий

```
roles/clickhouse/
├── defaults/main.yml          # все операционные дефолты
├── meta/main.yml              # galaxy_info
├── meta/argument_specs.yml    # валидация входных переменных
├── tasks/
│   ├── main.yml               # диспетчер
│   ├── install.yml            # repo + key + pref + пакет (общее)
│   ├── keeper.yml             # keeper: конфиг + unit + сервис + health-gate
│   └── server.yml             # server: config.d + users.d + сервис + health-gate
├── templates/
│   ├── clickhouse.pref.j2
│   ├── clickhouse-keeper.service.j2
│   ├── keeper_config.xml.j2
│   ├── config.d/
│   │   ├── listen.xml.j2
│   │   ├── zookeeper.xml.j2
│   │   ├── macros.xml.j2
│   │   └── remote_servers.xml.j2
│   └── users.d/
│       └── default-password.xml.j2
├── handlers/main.yml
└── README.md
```
