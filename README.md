# ClickHouse-кластер через Ansible: управление состоянием, а не сбор данных

Учебный пример для администраторов и DevOps-инженеров: развёртывание кластера
ClickHouse (3 ноды) с `clickhouse-keeper` через Ansible. Ноды поднимает OpenTofu
в Yandex Cloud.

Это **парный пример к плейбуку-аудиту** ([erlong15/ansible](https://github.com/erlong15/ansible)).
Там — read-only сбор данных, где `shell` оправдан. Здесь — управление состоянием,
где правило обратное: модули, handlers, идемпотентность, оркестрация и health-gates.
Контраст «shell vs модули» — центральный урок (см. [раздел про shell vs модули](#shell-vs-модули--центральный-урок)).

---

## Архитектура стенда

```
Yandex Cloud · 3× standard-v3, preemptible, Ubuntu 24.04
│
├── ch-01  keeper(server_id=1) + clickhouse-server
├── ch-02  keeper(server_id=2) + clickhouse-server
└── ch-03  keeper(server_id=3) + clickhouse-server

Keeper-ансамбль: 3 ноды, кворум 2/3 (raft, ZooKeeper-совместимый протокол).
Данные: 1 шард × 3 реплики (HA), движок ReplicatedMergeTree.
Порты: server 9000/8123/9009 · keeper 9181 (клиент) / 9234 (raft).
```

Keeper запускается **из общего бинаря** `/usr/bin/clickhouse-keeper` (поставляется
пакетом `clickhouse-server`) как отдельный systemd-сервис. Отдельный пакет
`clickhouse-keeper` НЕ ставится — он конфликтует с `clickhouse-server` через
`Provides: clickhouse-server-common`.

## Целевые версии

| Компонент | Версия |
|---|---|
| ansible-core | 2.18+ (FQCN везде, `deb822_repository`) |
| ClickHouse | 25.8 LTS (пин `25.8.*` через apt-preferences) |
| OpenTofu | 1.6+ (провайдер `yandex` ~> 0.127) |
| ОС нод | Ubuntu 24.04 LTS |

## Структура репозитория

```
terraform/                  OpenTofu: 3 VM + сеть + security group
inventories/clickhouse/
  yc.py                     динамический инвентори (фильтр по labels masterclass=true)
  hosts.yaml                статический фолбэк
  host_vars/ch-0N.yml       идентичность ноды: keeper_id, ch_shard, ch_replica
  group_vars/clickhouse/    vars.yml + vault.yml (секреты, зашифрованы)
roles/clickhouse/           единая роль; компонент выбирается clickhouse_component
  tasks/{main,install,keeper,server}.yml
  templates/                keeper_config.xml, systemd-unit, config.d/, users.d/
  handlers/main.yml         restart keeper (throttle:1) / server
  meta/argument_specs.yml   валидация входных переменных роли
playbooks/clickhouse/
  site.yml                  плей 1: keeper (все ноды) → плей 2: server (serial:1)
  validate.yml              капстоун: репликация через Keeper (ON CLUSTER)
slides.md                   лекция (Marp)
demo-plan.md                пошаговый сценарий демо для лектора
```

## Предварительные требования

- `tofu`, `ansible-core` 2.18+, `yc` CLI установлены
- SSH-ключ (путь к `.pub` указан в `terraform/terraform.tfvars`)
- `yc config list` показывает корректные `cloud_id` / `folder_id`
- файл `.vault_pass` в корне репо с паролем Vault (для демо — `masterclass`; в `.gitignore`)

## Запуск

`tofu apply`/`destroy` выполняет преподаватель/студент самостоятельно; Ansible —
против уже поднятых нод.

```bash
# 1. Инфраструктура (3 ноды в Yandex Cloud)
cd terraform
cp terraform.tfvars.example terraform.tfvars   # заполнить cloud_id/folder_id/zone/ssh-ключ
tofu init && tofu apply
cd ..

# 2. Окружение: токен для динамического инвентори + пароль Vault
export YC_PROFILE=<ваш-профиль>
export YC_TOKEN=$(yc --profile "$YC_PROFILE" iam create-token)
export ANSIBLE_VAULT_PASSWORD_FILE=$PWD/.vault_pass

# 3. Развернуть кластер (инвентори берётся из ansible.cfg → yc.py)
ansible-playbook playbooks/clickhouse/site.yml

# 4. Идемпотентность: повторный прогон не делает изменений
ansible-playbook playbooks/clickhouse/site.yml        # ожидаем changed=0

# 5. Капстоун: доказать репликацию через Keeper
ansible-playbook playbooks/clickhouse/validate.yml    # INSERT на ch-01 → SELECT на ch-02/03

# 6. Очистка
cd terraform && tofu destroy
```

## shell vs модули — центральный урок

| | Аудит (`collect_info`) | Кластер (роль `clickhouse`) |
|---|---|---|
| Задача | снять состояние (read-only) | **управлять** состоянием |
| Инструмент | `shell`/`command` — и это правильно | `apt`/`template`/`systemd` |
| `changed_when` | `false` на каждой задаче | модуль решает сам |
| Идемпотентность | не нужна (снимок) | критична: 2-й прогон `changed=0` |
| Handlers / `become` | нет / false | есть / true |

Урок не «shell — это плохо», а «инструмент выбирают по задаче». Снимок состояния →
`shell` с `changed_when: false`. Изменение системы → модули + handlers +
идемпотентность. Запустить аудит против этих же нод для контраста:

```bash
git clone https://github.com/erlong15/ansible /tmp/express-audit
ansible-playbook -i "$PWD/inventories/clickhouse/yc.py" \
  /tmp/express-audit/playbooks/express-audit/run.yml   # ожидаем changed=0 — аудит ничего не меняет
```

## Ключевые решения

- **Keeper-плей без `serial`.** Свежий raft-ансамбль нельзя бутстрапить по одному:
  порт 9181 открывается только после кворума 2/3, а одна нода кворум не соберёт —
  health-gate повиснет. Поэтому все 3 ноды поднимаются разом. Rolling для
  последующих изменений конфига даёт `throttle: 1` в хендлере restart keeper.
- **`serial: 1` на плее server** — обновление реплик по одной без простоя записи.
- **Динамический инвентори.** `yc.py` опрашивает YC и отбирает ноды по лейблу
  `masterclass=true` (ставит OpenTofu). Galaxy-плагин не нужен — источник истины само облако.
- **Секреты через Vault.** `vault.yml` зашифрован; пароль из `.vault_pass`
  (в `.gitignore`); на задачах с паролями — `no_log: true`.
- **`deb822_repository` + ключ `.asc`.** Современный формат apt-репозитория;
  armored-ключ обязан иметь расширение `.asc`, иначе apt выдаёт `NO_PUBKEY`.

## Статус проверки

Все плейбуки прогнаны на живом кластере из 3 нод и проходят: `site.yml`,
повторный прогон (идемпотентность, `changed=0`), `validate.yml` (репликация
через Keeper) и парный плейбук-аудит (read-only, `changed=0`).
