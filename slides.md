---
marp: true
theme: default
paginate: true
---

# Ansible: от shell-скриптов к идемпотентной автоматизации

### Разворачиваем кластер ClickHouse на 3 нодах — без единой ручной команды



---

## Agenda

- Часть 1: Теория — ~75 мин
- Часть 2: Демо — ~60 мин
  - Разворачиваем ClickHouse (3 ноды) + clickhouse-keeper
  - Разбор аудит плейбука

- Q&A — 30 мин


---

## Проблема: shell-скрипты в prod

```bash
# setup.sh — запускаем второй раз и получаем сюрприз
apt install -y clickhouse-server   # уже установлен — OK
useradd clickhouse                 # пользователь уже есть — ERROR
systemctl start clickhouse-server  # уже запущен — ERROR
```

- Не идемпотентны: повторный запуск ломает систему
- Нет состояния: скрипт не знает, что уже сделано
- Параллелизм вручную: SSH-цикл по 20 нодам в bash
- Нет отката: ошибка на шаге 7 из 10 — ручная починка

**Ключевая идея:** shell-скрипт описывает *действия*, а не *желаемое состояние* — это корень всех проблем.

---

## Что такое Ansible

- **Ansible** — инструмент автоматизации: описываешь *желаемое состояние*, он его достигает
- Agentless: работает через SSH, ничего не надо устанавливать на ноды
- Язык конфигурации — YAML, читается как документация
- Декларативность: `state: present` вместо `apt install`

**Ansible НЕ является:**
- Оркестратором контейнеров (это Kubernetes)
- CI/CD системой (это GitLab CI / GitHub Actions)
- Инструментом provisioning инфраструктуры (это Terraform)

**Ключевая идея:** Ansible управляет конфигурацией существующих машин, а не создаёт их.

---

## Ansible в стеке: push-модель, пакеты, версии

**Push-модель:** control node сам инициирует подключение к нодам по SSH и
«проталкивает» изменения. Нет демона-агента и нет polling, как в pull-модели
(Puppet/Chef) — нечего держать запущенным на нодах.

**Два пакета — не путать:**

| Пакет | Что внутри | Когда |
|---|---|---|
| `ansible-core` | движок + модули `ansible.builtin` | предсказуемые версии, ставим коллекции явно |
| `ansible` | `ansible-core` + ~сотни предустановленных коллекций | быстрый старт, без ручной доустановки |

**Версии нумеруются по-разному:** `ansible-core` — `2.x` (2.18, 2.19);
community-пакет `ansible` — своя нумерация (например, `ansible 12.x` поставляет
`ansible-core 2.19`).

**Что меняет 2.19:** переписанный шаблонизатор (**Data Tagging**) — строже к
типам и необъявленным переменным, недоверенные данные не исполняются как шаблон
(защита от инъекций). Часть ранее «прощавшихся» шаблонов теперь падает с ошибкой.

**Ключевая идея:** `ansible-core` + явно выбранные коллекции — контроль версий; пакет `ansible` с предустановленными коллекциями — для быстрого старта.

---

## Архитектура Ansible

```
Control Node (твой ноутбук / CI-runner)
│
├── Inventory  (список хостов и групп)
│   ├── node1: 10.0.0.1
│   ├── node2: 10.0.0.2
│   └── node3: 10.0.0.3
│
└── Playbook  (что делать)
    └── Play  (на каких хостах и с какими правами)
        └── Task  (конкретное действие)
            └── Module  (ansible.builtin.apt, ansible.builtin.template, ...)
```

- **Inventory** — где; **Playbook** — что; **Module** — как
- Control node подключается по SSH к каждому хосту
- На управляемых нодах нужен только Python и SSH-доступ

**Ключевая идея:** весь интеллект находится на control node — ноды остаются чистыми.

---

## Подготовка окружения

**1. venv — фиксируем версию ansible, не трогая системный Python:**

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install "ansible-core==2.19.*"
ansible --version          # проверяем версию и путь к python
```

**2. `ansible.cfg` — умолчания проекта** (порядок поиска: `$ANSIBLE_CONFIG` → `./ansible.cfg` → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg`):

```ini
[defaults]
inventory          = inventories/clickhouse/yc.py
roles_path         = roles
stdout_callback    = yaml          # читаемый вывод вместо сплошного JSON
host_key_checking  = False
```

**3. Первый ad-hoc запуск — одна задача без playbook:**

```bash
ansible all -i inventory -m ansible.builtin.ping     # связность
ansible all -i inventory -m ansible.builtin.setup    # собрать факты о ноде
```

**Ключевая идея:** venv фиксирует версию ansible на проект; ad-hoc — быстрый способ проверить связность и опробовать модуль, не написав ни одного playbook.

---

## Inventory: статический vs динамический

**Статический** — файл `hosts.yaml`, подходит для стабильных стендов:

```yaml
all:
  children:
    clickhouse:
      hosts:
        node1: { ansible_host: 10.0.0.1 }
        node2: { ansible_host: 10.0.0.2 }
        node3: { ansible_host: 10.0.0.3 }
```

**Динамический** — скрипт `yc.py` опрашивает Yandex Cloud API:

```bash
ansible-inventory -i inventory/yc.py --list   # JSON с актуальными IP
```

- Статический: быстро, прозрачно, для стендов с фиксированными IP
- Динамический: необходим когда IP меняются (preemptible VM, auto-scaling)

**Ключевая идея:** если ВМ preemptible — IP меняется при каждом перезапуске, статический inventory сразу устаревает.

---

## Группы, group_vars и host_vars

**Группы** объединяют хосты по роли. Есть спец-группы `all` (все) и `ungrouped`.

```yaml
clickhouse:                 # группа
  hosts:
    ch-01:
    ch-02:
    ch-03:
```

**Переменные подхватываются по имени автоматически:**

```
inventories/clickhouse/
├── group_vars/clickhouse/vars.yml   # переменные ВСЕЙ группы
└── host_vars/ch-01.yml              # переменные ОДНОЙ ноды
```

В нашем проекте:
- `group_vars/clickhouse/` — общее: имя кластера, пароль (через Vault)
- `host_vars/ch-0N.yml` — идентичность ноды: `keeper_id`, `ch_shard`, `ch_replica`

При конфликте **`host_vars` сильнее `group_vars`** — точечное переопределение для
одной ноды. Это лишь два из источников переменных; полный их приоритет — на слайде
«Переменные: источники и приоритет».

**Ключевая идея:** общее для группы — в `group_vars`, уникальное для ноды — в `host_vars`; Ansible сам объединяет их по имени хоста.

---

## Modules vs Shell: в чём разница

| Подход | Команда | Идемпотентность |
|--------|---------|-----------------|
| `ansible.builtin.shell` | `apt install clickhouse-server` | Нет — запускает команду всегда |
| `ansible.builtin.apt` | `name: clickhouse-server state: present` | Да — проверяет, установлен ли пакет |

```yaml
# Плохо — не идемпотентно
- name: Установить ClickHouse
  ansible.builtin.shell: apt install -y clickhouse-server

# Хорошо — идемпотентно
- name: Установить ClickHouse
  ansible.builtin.apt:
    name: clickhouse-server
    state: present
```

**Ключевая идея:** используй **FQCN** (Fully Qualified Collection Name) — `ansible.builtin.apt`, а не `apt`. FQCN исключает конфликты имён между коллекциями.

---

## Коллекции и документация

**Коллекция** — пакет модулей, ролей и плагинов со своим namespace:

| Коллекция | Примеры модулей |
|---|---|
| `ansible.builtin` | `apt`, `template`, `systemd` (идёт в ядре) |
| `ansible.posix` | `firewalld`, `mount`, `sysctl` |
| `community.general` | `ufw`, `timezone`, `make` |

**FQCN** = `namespace.collection.module` → `ansible.posix.firewalld`.

```bash
# Установить коллекцию (всё, кроме ansible.builtin — ставится явно)
ansible-galaxy collection install community.general

# Читать документацию прямо в терминале
ansible-doc ansible.builtin.apt          # опции модуля + примеры
ansible-doc -l | grep firewall           # найти нужный модуль
```

**Ключевая идея:** `ansible.builtin` встроена в ядро; всё остальное — коллекции, ставятся через `ansible-galaxy` и фиксируются в `requirements.yml`. `ansible-doc` — справка без выхода из терминала.

---

## Идемпотентность: почему это важно

**Идемпотентность** — повторный запуск даёт тот же результат, что и первый.

```
Первый запуск:    TASK [Установить ClickHouse] ... changed: [node1]
Второй запуск:    TASK [Установить ClickHouse] ... ok: [node1]
```

- `changed` — модуль сделал изменение
- `ok` — состояние уже соответствует желаемому, ничего не трогаем
- `changed=0` на втором прогоне — гарантия стабильности

Когда это критично:
- CI/CD: playbook запускается при каждом merge — не должен ломать prod
- Ночной cron: drift-detection без побочных эффектов
- Отладка: безопасно перезапустить после падения на шаге 7

**Ключевая идея:** идемпотентный playbook можно запускать хоть 100 раз — лишних изменений не будет.

---

## Результат задачи: register, changed_when, failed_when

**Директивы задачи** — применяются к любой задаче рядом с вызовом модуля.
По умолчанию Ansible сам решает, изменила ли задача систему и упала ли она;
эти директивы дают контроль:

- **`register`** — сохранить результат задачи (`stdout`, `rc`, …) в переменную
- **`changed_when`** — вручную задать, когда задача считается изменившей систему
- **`failed_when`** — вручную задать, когда задача считается упавшей

`set_fact` — это **отдельный модуль** (`ansible.builtin.set_fact`), а не директива:
вызывается как задача и создаёт новую переменную во время выполнения (живёт до конца плея).

```yaml
- name: Health-gate — SELECT 1 (реальный пример из server.yml)
  ansible.builtin.command: clickhouse-client --query "SELECT 1"
  register: ch_ping
  changed_when: false              # проверка ничего не меняет → не "changed"
  failed_when: ch_ping.rc != 0     # упасть только при ошибке клиента

- name: Сохранить число реплик как факт
  ansible.builtin.set_fact:
    replica_count: "{{ ch_ping.stdout | int }}"
```

**`register` vs `set_fact` — обе создают переменную, но по-разному:**

| | `register` | `set_fact` |
|---|---|---|
| Что кладёт | весь результат задачи (`stdout`, `rc`, `changed`, …) | ровно то, что вычислил ты |
| Кто задаёт значение | модуль — автоматически | ты — любым выражением |
| Роль | поймать сырой вывод | извлечь/преобразовать нужное |

Частая связка: `register` ловит сырьё → `set_fact` достаёт из него чистое
значение (в примере: `ch_ping` → `replica_count`).

В **плейбуке-аудите** — `register` + `changed_when: false` + `failed_when: false`
на *каждой* задаче: снимок ничего не меняет и не должен падать, а `set_fact`
превращает сырой вывод в переменную для отчёта.

**Ключевая идея:** `register` ловит результат, `changed_when`/`failed_when` переопределяют статус задачи, `set_fact` создаёт переменную на лету — вместе это основа и health-gate, и read-only аудита.

---

## Когда shell — правильный выбор: плейбук-аудит

`shell` — не зло. Для **read-only снимка** состояния это идиоматично.
Парный пример — плейбук-аудит [erlong15/ansible](https://github.com/erlong15/ansible):

```yaml
# collect_info: ~40 задач, и все такие
- name: GET LISTENING PORTS
  ansible.builtin.shell: "sudo -n ss -tulnp"
  register: output_ports
  changed_when: false     # снимок ничего НЕ меняет
  failed_when: false      # ни одна проверка не валит прогон
```

| | Аудит (`collect_info`) | Кластер (роль `clickhouse`) |
|---|---|---|
| Задача | снять состояние | **управлять** состоянием |
| Инструмент | `shell`/`command` — ок | `apt`/`template`/`systemd` |
| `changed_when` | `false` везде | модуль решает сам |
| Идемпотентность | не нужна (снимок) | критична (`changed=0`) |
| Handlers / `become` | нет / false | есть / true |

**Ключевая идея:** выбирай инструмент по задаче. Снимок — `shell`; изменение состояния — модули. Антипаттерн — это `shell` *вместо* модулей для изменения, а не сам аудит.

---

## Playbook и Plays

**Playbook** — YAML-файл с одним или несколькими **plays**. **Play** — привязка хостов к задачам.

```yaml
---
- name: Настройка ClickHouse Keeper    # <-- это Play
  hosts: clickhouse
  become: true
  roles:
    - role: clickhouse
      vars:
        clickhouse_component: keeper

- name: Настройка ClickHouse Server    # <-- второй Play
  hosts: clickhouse
  become: true
  roles:
    - role: clickhouse
      vars:
        clickhouse_component: server
```

- Plays выполняются последовательно сверху вниз
- Каждая задача выполняется на хостах параллельно — пачками по `forks` (по умолчанию 5)

**Ключевая идея:** разделяй Keeper и Server на разные plays — это даёт контроль над порядком запуска.

---

## Запуск: become, --check, --diff

**`become` — эскалация привилегий** (sudo), без захода под root по SSH:

```yaml
- hosts: clickhouse
  become: true          # все задачи плея — под sudo (по умолчанию → root)
```

**`--check` — dry-run:** прогон без изменений, показывает, что *было бы* сделано
(модуль должен поддерживать check mode). **`--diff`** — построчный diff файлов и шаблонов:

```bash
ansible-playbook site.yml --check --diff
```

```diff
TASK [Шаблон config.d/listen.xml] *******
--- before
+++ after
+    <listen_host>0.0.0.0</listen_host>
changed: [ch-01]
```

- Ограничение: `--check` неточен, если задача зависит от результата предыдущей
  изменяющей задачи (её в dry-run «не было»).

**Ключевая идея:** `become` даёт права точечно, не открывая root-вход по SSH; `--check --diff` — безопасный предпросмотр изменений перед prod.

---

## Handlers: уведомление об изменении

**Handler** — задача, которая выполняется **только при изменении** (`changed`)

- Срабатывает **один раз в конце play**, не сразу
- Задача уведомляет handler через `notify:`
- Типичный случай: перезапустить сервис после изменения конфига

```yaml
- name: Записать конфиг clickhouse-server
  ansible.builtin.template:
    src: config.d/listen.xml.j2
    dest: /etc/clickhouse-server/config.d/listen.xml
  notify: Restart clickhouse-server

handlers:
  - name: Restart clickhouse-server
    ansible.builtin.systemd:
      name: clickhouse-server
      state: restarted
```

**Ключевая идея:** handler не перезапускает сервис при каждом запуске playbook — только когда конфиг реально изменился.

---

## Handler throttle:1 — rolling restart Keeper

**Проблема:** при обычном handler все 3 ноды Keeper перезапускаются одновременно — кворум Raft теряется.

```
Raft-кворум: нужно 2 из 3 нод живых
Без throttle:  node1 + node2 + node3 DOWN → кворум потерян → ClickHouse недоступен
С throttle:1:  node1 DOWN (node2, node3 живы) → UP → node2 DOWN → UP → ...
```

```yaml
handlers:
  - name: Restart clickhouse-keeper
    ansible.builtin.systemd:
      name: clickhouse-keeper
      state: restarted
    throttle: 1          # не более 1 хоста одновременно
```

- `throttle: 1` доступен на уровне task или handler
- Применять при любом rolling-рестарте кластерных сервисов
- Альтернатива — `serial` в плее, но он режет на батчи **весь плей**, а `throttle` — только одну задачу

**Ключевая идея:** `throttle: 1` в handler безопасно перезапускает кластерный сервис без потери кворума — точечно, не ограничивая остальной плей.

---

## Jinja2: шаблоны и фильтры

Шаблон `.j2` рендерится **на control node**, готовый файл копируется на ноду.
`{{ }}` — подстановка, `{% %}` — логика (циклы, условия).

**Фильтры** преобразуют значение через `|`:

```jinja
{{ password | hash('sha256') }}      {# хэш вместо открытого пароля #}
{{ port | default(9000) }}           {# значение по умолчанию #}
{{ nodes | join(',') }}              {# список → строка #}
```

Пример из проекта — `keeper_config.xml.j2` генерирует raft-конфиг из инвентори:

```jinja
{% for h in groups['clickhouse'] %}
<server>
    <id>{{ hostvars[h].keeper_id }}</id>
    <hostname>{{ hostvars[h].internal_ip }}</hostname>
</server>
{% endfor %}
```

**Ключевая идея:** шаблон превращает инвентори в конфиг — один `.j2` на 3 ноды, у каждой свой `server_id` через `{{ keeper_id }}`.

---

## Условное выполнение: when и факты

**`when`** — условие выполнения задачи. Это Jinja-выражение **без** `{{ }}`:

```yaml
# Реальный пример из tasks/main.yml — диспетчер компонентов роли
- name: Настроить компонент keeper
  ansible.builtin.include_tasks: keeper.yml
  when: clickhouse_component == 'keeper'
```

**Факты** — данные о ноде, которые Ansible собирает в начале плея
(`gather_facts` → модуль `setup`): ОС, IP-адреса, память, CPU.

```yaml
- name: Установить пакет только на Debian/Ubuntu
  ansible.builtin.apt: {name: clickhouse-server, state: present}
  when: ansible_facts['os_family'] == 'Debian'
```

- `when` + `register` — реагировать на результат предыдущей задачи
- `when` + `loop` — условие проверяется для каждого `item` отдельно
- Факты не нужны — отключай: `gather_facts: false` (как в нашем `validate.yml`), плей стартует быстрее

**Ключевая идея:** `when` — Jinja-выражение без фигурных скобок; в связке с фактами и `register` даёт условную логику «выполни, только если…».

---

## Контроль выполнения: block/rescue, теги, строгий рендер 2.19

**`block` / `rescue` / `always`** — try/catch для группы задач:

```yaml
- block:
    - ansible.builtin.command: рискованная_операция
  rescue:
    - ansible.builtin.debug: {msg: "упало — откатываемся"}
  always:
    - ansible.builtin.debug: {msg: "выполнится в любом случае"}
```

**Теги** — запуск части плейбука:

```bash
ansible-playbook site.yml --tags config      # только задачи с tags: config
ansible-playbook site.yml --skip-tags install
```

**Строгая шаблонизация 2.19:** новый движок (Data Tagging) строже к необъявленным
переменным и типам, не исполняет недоверенные данные как шаблон. Роли, написанные
под старые версии, стоит **протестировать на 2.19** — часть шаблонов теперь падает.

**Ключевая идея:** `block/rescue` даёт устойчивость к сбоям, теги — выборочный запуск; на 2.19 проверь шаблоны — рендер стал строже.

---

## Циклы: loop

**`loop`** повторяет одну задачу для каждого элемента списка — вместо копипасты задач.

```yaml
# вместо трёх почти одинаковых задач — один цикл
- name: Создать каталоги Keeper
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
  loop:
    - /var/lib/clickhouse-keeper
    - /var/lib/clickhouse-keeper/logs
    - /var/lib/clickhouse-keeper/snapshots
```

**Реальный пример из `server.yml`** — четыре конфига `config.d` отличаются только
именем файла, поэтому `item` подставляется и в `src`, и в `dest`:

```yaml
- name: Шаблонировать конфиги config.d сервера
  ansible.builtin.template:
    src: "config.d/{{ item }}.xml.j2"
    dest: "{{ clickhouse_server_config_d }}/{{ item }}.xml"
    mode: "0640"
  loop:
    - listen          # слушать все интерфейсы
    - zookeeper       # подключение к Keeper-ансамблю
    - macros          # метки реплики для ReplicatedMergeTree
    - remote_servers  # топология кластера
  notify: "Restart clickhouse-server"
```

Если у элементов несколько разных полей — итерируют **список словарей**
(`item.src`, `item.dest`), а `loop_control.label` оставляет в выводе только
короткую метку вместо всего словаря.

**Ключевая идея:** `loop` убирает копипасту; `item` — текущий элемент. Пароль-шаблон в нашей роли намеренно вне цикла — у него `no_log: true`, иначе вывод скрылся бы для всех итераций. Старый синтаксис `with_items` официально не запрещён, но в новом коде используй `loop`.

---

## Цикл-ретрай: until / retries

Иногда нужно не перебрать список, а **повторять задачу, пока не выполнится
условие** — типичный health-gate: дождаться, пока сервис ответит.

```yaml
- name: Дождаться репликации строки на реплике
  ansible.builtin.command: >-
    clickhouse-client --query "SELECT count() FROM capstone_db.events"
  register: result
  retries: 10                        # до 10 попыток
  delay: 2                           # пауза 2 с между попытками
  until: result.stdout | int >= 1    # условие успеха
  changed_when: false
```

- `until` — условие, при котором цикл прекращается (успех)
- `retries` × `delay` — сколько раз и с каким интервалом пробовать
- Реальный пример из `validate.yml`: проверяем, что INSERT на ch-01 доехал до ch-02/ch-03

**Ключевая идея:** `until/retries/delay` — цикл «пробуй, пока не получится»; основа health-gate и защиты от гонок (репликация, старт сервиса).

---

## Роли: структура и переиспользование

**Role** — переиспользуемый набор задач с собственными переменными, шаблонами и handlers.

```
roles/clickhouse/
├── tasks/
│   ├── main.yml          # диспетчер: install + компонент по clickhouse_component
│   ├── install.yml       # репозиторий, GPG-ключ, установка пакета
│   ├── keeper.yml        # настройка Keeper
│   └── server.yml        # настройка Server
├── handlers/
│   └── main.yml          # restart keeper (throttle:1) / server
├── templates/
│   ├── keeper_config.xml.j2          # конфиг Keeper (raft)
│   ├── clickhouse-keeper.service.j2  # systemd-юнит Keeper
│   ├── config.d/                     # шаблоны конфигов сервера
│   └── users.d/                      # шаблон пароля пользователя
├── defaults/
│   └── main.yml          # значения переменных по умолчанию
└── meta/
    └── argument_specs.yml  # валидация входных переменных
```

- Одна роль — один компонент; повторно используй, передавая переменные
- `defaults/main.yml` содержит все переменные с безопасными значениями по умолчанию

**Ключевая идея:** роль — это "пакет" для задач; как Helm chart для K8s, только для конфигурации ОС.

---

## Готовые роли из Galaxy

Не всё писать самому — Ansible Galaxy даёт готовые роли (`geerlingguy.postgresql`
и др.). Зависимости фиксируются в **`requirements.yml`**:

```yaml
# requirements.yml
roles:
  - name: geerlingguy.nginx
    version: "3.1.4"        # фиксация версии — воспроизводимость
collections:
  - name: community.general
```

```bash
ansible-galaxy install -r requirements.yml
```

**Подключение роли:**
- `roles:` в плее — статически, выполняется до `tasks:`
- `include_role` / `import_role` в задачах — условно/динамически (`when:`, в цикле)
- переопределение переменных — передай `vars:` при подключении (значения по умолчанию у роли — самые слабые)
- зависимости роли — в `meta/main.yml` → `dependencies:` (роль подключает другие роли)

**Наш выбор:** написали свою роль — контроль, обучение и независимость от внешних
зависимостей (Galaxy под вопросом из РФ).

**Ключевая идея:** `requirements.yml` фиксирует внешние роли и коллекции — воспроизводимость; `roles:` для статики, `include_role` — для условного подключения.

---

## argument_specs.yml — самодокументирующийся интерфейс роли

**Проблема:** без валидации роль принимает любой мусор на входе и падает в непредсказуемом месте.

```yaml
# roles/clickhouse/meta/argument_specs.yml
argument_specs:
  main:
    short_description: Устанавливает и настраивает ClickHouse
    options:
      clickhouse_component:
        type: str
        required: true
        choices: [keeper, server]
        description: Какой компонент установить
      clickhouse_version:
        type: str
        required: false
        default: "25.8.*"
        description: Маска версии ClickHouse для apt-preferences
```

- Ansible проверяет переменные **до выполнения** любой задачи
- При неверном значении — немедленная ошибка с понятным сообщением
- `ansible-doc -t role clickhouse` — читаемая документация прямо в терминале

**Ключевая идея:** `argument_specs.yml` превращает роль в типизированный API с встроенной документацией.

---

## Линтинг и организация проекта

Два линтера дополняют друг друга:

| Инструмент | Что проверяет |
|---|---|
| `yamllint` | форму: отступы, длину строк, дубли ключей |
| `ansible-lint` | смысл: FQCN, имена задач, `changed_when`, риск-правила |

```bash
yamllint .
ansible-lint --profile production    # профили: min → basic → ... → production
```

**Стандартная раскладка проекта** — читаемость и предсказуемый `roles_path`:

```
ansible.cfg · inventories/ · group_vars/ · host_vars/
roles/ · playbooks/ · requirements.yml
```

В CI линт запускается на каждый pull request — ловит ошибки до живого прогона.

**Ключевая идея:** `yamllint` = форма, `ansible-lint` = смысл; зелёный линт в CI — первая линия защиты до контакта с реальными нодами.

---

## Переменные: источники и приоритет

Одну переменную можно задать в десятке мест. При конфликте побеждает источник
с более высоким приоритетом (от слабого к сильному):

```
role defaults  (defaults/main.yml)      ← слабейший, легко переопределить
   ↓
inventory group_vars
   ↓
inventory host_vars
   ↓
play vars  (vars: в плее)
   ↓
task vars  (vars: у задачи)
   ↓
set_fact  /  register
   ↓
extra-vars  (-e на CLI)                  ← сильнейший, побеждает всё
```

- `defaults/main.yml` — безопасные значения по умолчанию роли, на то и слабейшие
- `host_vars` сильнее `group_vars` — точечно переопределяем для одной ноды
- `-e key=value` — разовое переопределение, перебивает любой файл

**Ключевая идея:** `defaults` — слабейшие, `-e` — сильнейшие; знание приоритета экономит часы отладки «почему переменная не та».

---

## Переменные через параметры команды: -e / extra-vars

**extra-vars** (`-e` / `--extra-vars`) — переданные в командной строке, имеют
**высший приоритет**: перебивают любой файл и любую переменную.

```bash
# простое значение
ansible-playbook site.yml -e "clickhouse_version=25.8.*"

# несколько значений или сложная структура — JSON
ansible-playbook site.yml -e '{"cluster": "ch_cluster", "replicas": 3}'

# из файла — удобно для окружений
ansible-playbook site.yml -e @environments/prod.yml
```

- Когда применять: переключение окружения (dev/prod), разовое переопределение,
  параметры из CI-пайплайна
- Осторожно: раз `-e` перебивает всё, легко незаметно «прибить» значение из
  `group_vars`/`host_vars`

**Ключевая идея:** `-e` — самый сильный источник; для разовых и CI-параметров, но не для постоянной конфигурации (её место — в `group_vars`/`host_vars`).

---

## Переменные окружения

**1. Конфигурация самого Ansible** — переменные `ANSIBLE_*` переопределяют `ansible.cfg`:

```bash
export ANSIBLE_VAULT_PASSWORD_FILE=$PWD/.vault_pass
export ANSIBLE_HOST_KEY_CHECKING=False
# приоритет: флаг CLI  >  ANSIBLE_*  >  ansible.cfg  >  умолчание
```

В нашем демо так задаются `ANSIBLE_VAULT_PASSWORD_FILE` (пароль Vault) и
`YC_TOKEN` / `YC_PROFILE` (их читает скрипт динамического инвентори `yc.py`).

**2. Окружение для команды на ноде** — ключевое слово `environment:`:

```yaml
- name: Собрать проект
  ansible.builtin.command: make
  environment:
    http_proxy: "http://proxy:3128"
    PATH: "/opt/bin:{{ ansible_env.PATH }}"
```

**3. Прочитать переменную окружения control node** — `lookup`:

```jinja
{{ lookup('env', 'HOME') }}
```

**Ключевая идея:** `ANSIBLE_*` настраивают сам Ansible (удобно в CI без правки `ansible.cfg`); `environment:` задаёт окружение команды на ноде; `lookup('env')` читает окружение control node.

---

## Ansible Vault: секреты в git

**Правило:** секреты никогда не хранятся в открытом виде в git — только зашифрованные через **Vault**.

```bash
# Зашифровать файл с секретами
ansible-vault encrypt vars/secrets.yml

# Запустить playbook с паролем из файла
ansible-playbook -i inventory/hosts.yaml site.yml \
  --vault-password-file .vault_pass
```

```yaml
# tasks/main.yml — задача, работающая с паролем
- name: Создать пользователя admin
  ansible.builtin.template:
    src: users.xml.j2
    dest: /etc/clickhouse-server/users.d/admin.xml
  no_log: true    # не выводить значения в лог
```

- `.vault_pass` в `.gitignore` — пароль никогда не попадает в репозиторий
- `no_log: true` — скрыть вывод задачи, работающей с секретами
- В CI: пароль Vault хранится в переменной окружения `ANSIBLE_VAULT_PASSWORD_FILE`

**Ключевая идея:** `no_log: true` + Vault = секреты не утекают ни в git, ни в CI-логи.

---

## deb822_repository — современные apt-репозитории

**Проблема:** `ansible.builtin.apt_repository` пишет однострочную запись в `/etc/apt/sources.list` — легаси-формат, который вытесняется deb822.

Современный путь: `/etc/apt/sources.list.d/*.sources` — формат **deb822**.

```yaml
- name: Добавить GPG-ключ ClickHouse
  ansible.builtin.get_url:
    url: https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key
    dest: /usr/share/keyrings/clickhouse-keyring.asc   # расширение .asc обязательно!
    mode: "0644"

- name: Добавить репозиторий ClickHouse (deb822)
  ansible.builtin.deb822_repository:
    name: clickhouse
    types: deb
    uris: https://packages.clickhouse.com/deb
    suites: stable
    components: main
    signed_by: /usr/share/keyrings/clickhouse-keyring.asc
    state: present
```

- GPG-ключ должен иметь расширение `.asc` (armored) — иначе apt выдаёт `NO_PUBKEY`
- `deb822_repository` требует ansible-core 2.15+

**Ключевая идея:** используй `ansible.builtin.deb822_repository` для новых репозиториев — структурированный формат `*.sources`, читаемый и легко управляемый Ansible.

---

## Демо: что будем разворачивать

```
Yandex Cloud (folder: mc-ansible)
│
├── ch-01 (10.10.0.x)  Ubuntu 24.04, preemptible
│   ├── clickhouse-keeper  :9181 (Raft)
│   └── clickhouse-server  :8123 (HTTP) :9000 (native)
│
├── ch-02 (10.10.0.x)  Ubuntu 24.04, preemptible
│   ├── clickhouse-keeper  :9181 (Raft)
│   └── clickhouse-server  :8123 (HTTP) :9000 (native)
│
└── ch-03 (10.10.0.x)  Ubuntu 24.04, preemptible
    ├── clickhouse-keeper  :9181 (Raft)
    └── clickhouse-server  :8123 (HTTP) :9000 (native)

Репликация: ReplicatedMergeTree → Keeper (замена ZooKeeper)
DDL: CREATE TABLE ... ON CLUSTER ch_cluster
```

- Один playbook — 3 ноды настроены идентично
- Конфигурация генерируется из Jinja2-шаблонов с учётом `inventory_hostname`

---

## ClickHouse: Keeper и репликация

**clickhouse-keeper** заменяет ZooKeeper — встроенная координация реплик на Raft.

```
Raft-кворум (3 ноды):
  Leader ── Follower ── Follower
    │
    └── координирует DDL, хранит метаданные реплик

ReplicatedMergeTree:
  INSERT → node1 → Keeper регистрирует блок данных
                 → node2, node3 скачивают блок у node1
```

- Кворум: `(N/2) + 1` — при 3 нодах нужно минимум 2 живых
- `ON CLUSTER ch_cluster` — DDL выполняется на всех нодах через Keeper
- Keeper слушает порт `9181`, Server подключается к нему при старте

**Вопрос к аудитории:** что произойдёт, если одна из 3 нод Keeper упадёт навсегда?

**Ключевая идея:** Keeper — мозг кластера; без кворума Keeper весь кластер останавливает запись.

---

## Ключевое решение: Keeper без serial:1

**Проблема:** если стартовать Keeper по одному (`serial: 1`), первая нода не поднимется — нет кворума.

```
serial: 1 (НЕПРАВИЛЬНО для bootstrap):
  node1: keeper стартует → ждёт кворума → порт 9181 не открылся → таймаут
  node2: никогда не запускается — Ansible ждёт node1

Все ноды одновременно (ПРАВИЛЬНО для bootstrap):
  node1 + node2 + node3 стартуют вместе → кворум 3/3 → все OK
```

```yaml
- name: Настройка ClickHouse Keeper
  hosts: clickhouse
  # serial: НЕ указываем — все ноды параллельно
  become: true
  roles:
    - role: clickhouse
      vars:
        clickhouse_component: keeper
```

- `serial` нужен только для rolling update уже работающего кластера
- Rolling update — через `handler` с `throttle: 1`, не через `serial` в play

**Ключевая идея:** bootstrap Keeper = все ноды одновременно; rolling restart = `throttle: 1` в handler.

---

## Best practices

1. **FQCN везде** — `ansible.builtin.apt`, `ansible.builtin.template`, не просто `apt`

2. **Без жёстко зашитых значений** — все значения через переменные и `defaults/main.yml`; конфигурация — это данные, не код

3. **`changed_when: false`** для read-only команд:
   ```yaml
   - ansible.builtin.command: clickhouse-client --query "SELECT 1"
     changed_when: false   # команда не меняет состояние
   ```

4. **`no_log: true`** для задач с секретами — пароли не попадают в CI-логи

5. **`--check --diff`** перед применением в prod:
   ```bash
   ansible-playbook site.yml --check --diff
   ```

**Ключевая идея:** playbook должен быть безопасно запускаемым в `--check` режиме в любой момент.

---

## Итоги

**Что узнали:**
- Ansible решает проблему идемпотентности там, где shell-скрипты не справляются
- Роли + `argument_specs.yml` = переиспользуемые, типизированные компоненты
- `throttle: 1` в handler — безопасный rolling restart кластерных сервисов
- Keeper bootstrap требует параллельного старта всех нод

**Когда Ansible — правильный выбор:**
- Конфигурация ОС и пакетов на группе серверов
- Однотипная настройка новых нод (onboarding)
- Drift-detection: `--check` в cron для обнаружения ручных изменений

**Когда НЕ Ansible:**
- Stateful оркестрация контейнеров — используй Kubernetes
- K8s-объекты (Deployment, Service) — используй Helm / kubectl
- Создание инфраструктуры (VPC, VM) — используй Terraform / OpenTofu

---

## Ресурсы

- Документация Ansible: https://docs.ansible.com/ansible/latest/
- Встроенные модули (FQCN): https://docs.ansible.com/ansible/latest/collections/ansible/builtin/
- ClickHouse Keeper: https://clickhouse.com/docs/en/guides/sre/keeper/clickhouse-keeper
- Репозиторий мастеркласса: https://github.com/your-org/mc-ansible

**Вопросы?**

Цыкунов Алексей
@erlong15
luckyerlong@gmail.com
