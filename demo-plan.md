# Demo Plan — Ansible для DevOps-инженеров

Тема: развёртывание ClickHouse-кластера (3 ноды + clickhouse-keeper) через Ansible.
Главный нарратив — контраст двух подходов: **управление состоянием** (роль
`clickhouse`: модули, handlers, идемпотентность) против **read-only снимка**
(парный плейбук-аудит [erlong15/ansible](https://github.com/erlong15/ansible):
сплошной `shell`, где это уместно). Кластер разворачиваем сами, аудит запускаем
живьём против тех же нод в блоке 9.

Формат документа — конспект-подсказка: для каждого шага указано **что делаем**,
**ключевые аспекты** и **на что обратить внимание**. Длительность демо: ~60 минут.

---

## Pre-flight checklist

Проверить до начала, пока идёт вводная часть слайдов.

- [ ] `yc config list` показывает правильный `cloud_id` и `folder_id`
- [ ] `tofu version` доступен (≥ 1.6)
- [ ] `ansible --version` показывает 2.18+ и корректный `python version`
- [ ] Файл `.vault_pass` существует в корне репозитория и содержит пароль
- [ ] `ssh-add -l` показывает загруженный ключ (не `The agent has no identities`)
- [ ] Интернет-доступ к репозиторию ClickHouse: `curl -I https://packages.clickhouse.com/deb/` → `HTTP/2 200`
- [ ] Терминал: крупный шрифт (16pt+), тёмная тема, ширина 120+ символов
- [ ] Вкладки терминала подписаны: `infra`, `ansible`, `ssh-ch01`, `ssh-ch02`
- [ ] Переменная окружения экспортирована: `export ANSIBLE_VAULT_PASSWORD_FILE=$PWD/.vault_pass`

---

## 1. Обзор репозитория (5 мин)

**Что делаем:** показываем структуру проекта и два ключевых файла — `ansible.cfg`
и `site.yml`. Сначала дерево целиком, затем точечно по слоям (не читать построчно).

```bash
# Структура репозитория — двух уровней достаточно
tree -L 2

# Конфигурация Ansible — здесь заданы все умолчания
cat ansible.cfg

# Главный плейбук — 2 плея
cat playbooks/clickhouse/site.yml
```

**Ключевые аспекты:**
- `ansible.cfg`: `stdout_callback=yaml` — читаемый вывод (не стена JSON);
  `inventory = inventories/clickhouse/yc.py` — по умолчанию динамический инвентори
  (скрипт опрашивает YC при каждом запуске); `roles_path = roles` — где искать роли.
- Пароль к Vault передаётся через переменную окружения `ANSIBLE_VAULT_PASSWORD_FILE`
  (выставлена в pre-flight), а не в `ansible.cfg` — пароль не зашит в конфиг репозитория.
- `site.yml`: два плея с разными стратегиями — Play 1 (Keeper) без `serial`,
  Play 2 (Server) с `serial: 1`.

**На что обратить внимание:** плейбук декларативен — описывает желаемое состояние,
а не последовательность команд.

**Результат на экране:** дерево с `inventories/`, `playbooks/`, `roles/`,
`terraform/`; в `site.yml` — два плея с разными стратегиями выполнения.

---

## 2. Поднятие инфраструктуры (5 мин активно + 5 мин ожидание)

**Что делаем:** вкладка `infra`. Поднимаем три preemptible VM в Yandex Cloud
через OpenTofu. Пока идёт `apply` — разбираем `terraform/main.tf`.

```bash
cd /Users/lucky/projects/masterclasses/mc-ansible/terraform

# Инициализация провайдера (если первый раз)
tofu init

# Поднять три VM — ~4-5 минут
tofu apply -auto-approve

# Outputs: IP-адреса нод
tofu output
```

**Ключевые аспекты:**
- `preemptible = true` — ВМ в ~3× дешевле, YC может остановить в любой момент
  (для учебного стенда приемлемо).
- `platform_id = "standard-v3"`, образ `ubuntu-2404-lts`.
- Лейбл `masterclass = "true"` в `local.common_labels` — по нему dynamic inventory
  найдёт эти машины.

**На что обратить внимание:** IP-адреса нод в `Outputs` — понадобятся для SSH в
блоках 7–8.

**Результат на экране:** `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`
и блок `Outputs:` с тремя IP.

---

## 3. Dynamic Inventory (5 мин)

**Что делаем:** вкладка `ansible`. Показываем, как Ansible узнаёт о нодах без
ручного редактирования файла — скрипт опрашивает облако напрямую.

```bash
# Логика скрипта — вызывает yc CLI
cat inventories/clickhouse/yc.py

# Что видит Ansible — JSON со списком хостов и переменными
python3 inventories/clickhouse/yc.py --list

# Связность — ping через Ansible
ansible -i inventories/clickhouse/yc.py clickhouse -m ansible.builtin.ping

# Переменные конкретной ноды — keeper_id, shard, replica
cat inventories/clickhouse/host_vars/ch-01.yml
cat inventories/clickhouse/host_vars/ch-02.yml
```

**Ключевые аспекты:**
- Скрипт запрашивает `yc compute instance list`, фильтрует по лейблу
  `masterclass=true` (переопределяется через `YC_INVENTORY_LABEL`), возвращает JSON
  в формате инвентори Ansible.
- Источник истины — само облако, файл не устаревает после `tofu apply/destroy`.

**На что обратить внимание:** `keeper_id` различается на каждой ноде (1, 2, 3) —
эти ID идут в конфиг keeper'а. Одинаковый ID на всех нодах → keeper-кластер не
поднимется.

**Результат на экране:** JSON с тремя хостами в группе `clickhouse`; ping —
три строки `"ping": "pong"` со статусом `SUCCESS`.

---

## 4. Первый прогон playbook (15 мин)

**Что делаем:** центральный момент демо. Запускаем `site.yml`, комментируем фазы
по ходу. Первый прогон ~8 минут (установка пакетов, генерация конфигов, запуск служб).

```bash
ansible-playbook -i inventories/clickhouse/yc.py playbooks/clickhouse/site.yml

# Параллельно в соседнем окне — шаблон конфига keeper'а
cat roles/clickhouse/templates/keeper_config.xml.j2
```

**Ключевые аспекты — Play 1, ClickHouse Keeper (все три ноды параллельно):**
- `install.yml` — GPG-ключ (расширение `.asc`, не `.gpg`), `deb822_repository`,
  установка пакета `clickhouse-server` (keeper берётся из общего бинаря
  `/usr/bin/clickhouse-keeper`).
- `keeper.yml` — генерация `keeper_config.xml` из j2-шаблона, регистрация
  systemd-службы `clickhouse-keeper`, health-gate: `wait_for` порт 9181 +
  `echo ruok | nc <ip> 9181` → `imok`.

**Ключевые аспекты — Play 2, ClickHouse Server (`serial: 1`, по одной ноде):**
- 5 шаблонов `config.d/`/`users.d/`: listen, zookeeper (адреса keeper'а),
  macros (shard/replica), remote_servers (топология кластера), пароль пользователя.
- Запуск `clickhouse-server`, health-gate на порты 9000/8123 + `SELECT 1`.

**На что обратить внимание:**
- Корневой тег `keeper_config.xml` — `<clickhouse>`, внутри `<keeper_server>`.
  Без обёртки `<clickhouse>` keeper падает с SIGSEGV.
- `RUNNING HANDLER` срабатывает один раз в конце плея, хотя несколько задач его
  нотифицировали (handler копит уведомления и выполняется однократно).

**Результат на экране:** `PLAY RECAP` с тремя хостами, `failed=0 unreachable=0`.
Play 1 — строки трёх нод идут параллельно. Play 2 — ноды по очереди (строки с паузами).

---

## 5. Keeper без serial — почему (3 мин)

**Что делаем:** разбираем, почему у Keeper нет `serial: 1`, а у Server — есть.

```bash
# Handlers — throttle:1 для rolling-рестарта при обновлении конфига
cat roles/clickhouse/handlers/main.yml
```

**Ключевые аспекты:** для кластера из трёх нод нужен кворум 2/3. Бутстрап с
`serial: 1` зависает:
1. ch-01 стартует один, видит себя (1/3) — кворума нет.
2. Health-gate `wait_for port=9181` ждёт открытия порта — порт не откроется без кворума.
3. Плейбук висит на ch-01, до ch-02/ch-03 не доходит.

Правильно — поднять все три keeper'а одновременно, лидер выбирается через Raft.

**На что обратить внимание:** `serial` и `throttle` — разные уровни.
`serial` управляет порядком плея целиком (бутстрап server по одной ноде);
`throttle: 1` в handler'е — rolling-рестарт keeper по одному при обновлении
конфига, чтобы не потерять кворум.

**Результат на экране:** `handlers/main.yml` с двумя обработчиками —
`Restart clickhouse-keeper` (с `throttle: 1`) и `Restart clickhouse-server`.

---

## 6. Второй прогон — идемпотентность (3 мин)

**Что делаем:** запускаем тот же плейбук повторно, ничего не меняя.

```bash
ansible-playbook -i inventories/clickhouse/yc.py playbooks/clickhouse/site.yml
```

**Ключевые аспекты:** каждый модуль сверяет фактическое состояние с желаемым
(пакет установлен? конфиг совпадает с шаблоном? служба запущена?) и не делает
ничего лишнего. Второй прогон в 3–4× быстрее первого.

**На что обратить внимание:** `changed=0` — главное доказательство идемпотентности.
Плейбук безопасно запускать из CI хоть каждую ночь. Аналогия: `git status`
показывает разницу, но не переписывает файлы без изменений.

**Результат на экране:** `PLAY RECAP` — только `ok`, `changed=0` на всех нодах.

---

## 7. Валидация репликации (5 мин)

**Что делаем:** запускаем `validate.yml` — доказываем, что между нодами работает
не только сервис, но и репликация данных.

```bash
ansible-playbook -i inventories/clickhouse/yc.py playbooks/clickhouse/validate.yml

# Топология кластера с точки зрения ClickHouse
ssh ubuntu@<ch-01-ip> "clickhouse-client --password <пароль> --query 'SELECT * FROM system.clusters FORMAT Pretty'"
```

**Ключевые аспекты — логика плейбука:**
1. `CREATE TABLE capstone_db.events ON CLUSTER ch_cluster` (движок
   `ReplicatedMergeTree`) — создаёт БД и таблицу на всех трёх нодах через DDL кластера.
2. `INSERT INTO capstone_db.events` на ch-01 — пишем тестовую строку.
3. `SELECT count() FROM capstone_db.events` на ch-02/ch-03 (с ретраями) —
   проверяем, что данные реплицировались.

**На что обратить внимание:** `ON CLUSTER` в DDL. Без него таблица создаётся только
на той ноде, к которой подключились. С `ON CLUSTER` одна нода распространяет DDL по
всему кластеру через Keeper.

**Результат на экране:** плейбук без ошибок; в `system.clusters` — три ноды с
корректными `shard_num`/`replica_num`; SELECT на ch-02/ch-03 возвращает то же
число строк, что вставлено на ch-01.

---

## 8. Намеренная поломка и самовосстановление (7 мин)

**Что делаем:** демонстрируем устранение drift. Вручную ломаем одну ноду и
переигрываем плейбук — Ansible чинит только отклонившуюся ноду.

```bash
# Ломаем ch-02 — останавливаем сервер вручную
ssh ubuntu@<ch-02-ip> "sudo systemctl stop clickhouse-server"

# Убеждаемся, что сервис упал
ssh ubuntu@<ch-02-ip> "systemctl status clickhouse-server --no-pager"

# Переигрываем плейбук
ansible-playbook -i inventories/clickhouse/yc.py playbooks/clickhouse/site.yml

# Финальная проверка — ch-02 снова в кластере
ssh ubuntu@<ch-02-ip> "clickhouse-client --password <пароль> --query 'SELECT count() FROM capstone_db.events'"
```

**Ключевые аспекты:** декларативный подход — описываем желаемое состояние,
инструмент сам находит разницу и устраняет её. На ch-01/ch-03 расхождений нет →
изменений не вносится.

**На что обратить внимание:** в `PLAY RECAP` только ch-02 имеет `changed=1`
(задача запуска службы), ch-01 и ch-03 — `changed=0`. После починки число строк на
ch-02 совпадает с остальными — репликация догналась автоматически.

**Результат на экране:** статус ch-02 до починки — `inactive (dead)`; после
прогона — служба поднята, `count()` совпадает с ch-01/ch-03.

---

## 9. Контраст: плейбук-аудит — когда shell уместен (7 мин)

**Что делаем:** смысловая кульминация. После управления состоянием через модули
показываем оборотную сторону — read-only снимок тех же нод, где `shell` идиоматичен.
Берём парный репозиторий [erlong15/ansible](https://github.com/erlong15/ansible)
(плейбук `express-audit`, роль `collect_info`) и запускаем против тех же трёх нод
через наш динамический инвентори.

```bash
# Клонируем парный репозиторий с аудитом (read-only сбор данных)
git clone https://github.com/erlong15/ansible /tmp/express-audit

# Запускаем аудит против наших нод — переиспользуем наш dynamic inventory.
# Ноды доступны под ubuntu с NOPASSWD-sudo, отдельный audit-юзер не нужен.
ansible-playbook \
  -i "$PWD/inventories/clickhouse/yc.py" \
  /tmp/express-audit/playbooks/express-audit/run.yml

# Параллельно — паттерн задач аудита
cat /tmp/express-audit/roles/collect_info/tasks/main.yml

# Отчёты собираются локально — по файлу на ноду
ls -1 /tmp/express-audit/reports/all/
```

**Ключевые аспекты — два паттерна рядом:**

```yaml
# АУДИТ (collect_info): снимок — shell уместен
- name: GET LISTENING PORTS
  ansible.builtin.shell: "sudo -n ss -tulnp"
  register: output_ports
  changed_when: false      # ничего не меняем — всегда "ok", никогда "changed"
  failed_when: false       # ни одна проверка не валит весь аудит

# КЛАСТЕР (роль clickhouse): управление состоянием — модуль
- name: "Установить clickhouse-server и clickhouse-client"
  ansible.builtin.apt:     # модуль сам проверит, установлен ли пакет
    name: [clickhouse-server, clickhouse-client]
    state: present         # идемпотентно: changed только при реальной установке
```

**На что обратить внимание — три отличия аудита:**
1. Нет `become` и handlers — аудит ничего не перезапускает.
2. `changed_when: false` на **каждой** задаче — снимок по определению не меняет
   систему, идемпотентность здесь не нужна.
3. Результат — markdown-отчёт по каждой ноде через `template` + `fetch`, а не
   изменённое состояние сервера.

**Главный вывод занятия:** инструмент выбирают по задаче. Снимок состояния →
`shell` с `changed_when: false`. Управление состоянием → модули + handlers +
идемпотентность. Антипаттерн — `shell` *вместо* модулей при изменении системы,
а не сам аудит.

**Результат на экране:** `PLAY RECAP` с `ok=N`, **`changed=0`** и `failed=0` на
всех трёх нодах (аудит ничего не меняет → нет ни одного `changed` даже на первом
прогоне, в отличие от `site.yml`); в `reports/all/` — файлы вида `ch-01 [ch-01].md`
с разделами Security/Performance/Network.

---

## 10. Очистка (2 мин)

**Что делаем:** вкладка `infra`. Удаляем стенд.

```bash
cd /Users/lucky/projects/masterclasses/mc-ansible/terraform
tofu destroy -auto-approve
```

**Ключевые аспекты:** три preemptible VM за ~60 минут демо стоят ~15–20 ₽ —
аргумент в пользу IaC: инфраструктуру легко поднять и легко удалить.

**На что обратить внимание:** пока идёт destroy — резюме паттернов: dynamic
inventory, идемпотентность, `serial` vs `throttle`, Vault для секретов,
shell-снимок vs модули-состояние.

**Результат на экране:** `Destroy complete! Resources: 3 destroyed.`

---

## Troubleshooting

| Симптом | Вероятная причина | Диагностика | Решение | Профилактика |
|---|---|---|---|---|
| `NO_PUBKEY 3E4AD4719DDE9A38` при `apt update` | URL GPG-ключа вернул 404 или скачан бинарный `.gpg` вместо ASCII-armored `.asc` | `curl -I https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key` — смотреть код ответа; `file /usr/share/keyrings/clickhouse-keyring.asc` — если `data` вместо `PGP public key`, ключ неверного формата | Качать ключ с `https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key` и сохранять с расширением `.asc`; в `deb822_repository` указать `signed_by: /usr/share/keyrings/clickhouse-keyring.asc` (модуль `apt_key` устарел — не использовать) | Проверить URL ключа вручную (`curl -sO`) перед первым деплоем; добавить assert на формат файла |
| `clickhouse-keeper` падает с SIGSEGV сразу после старта | Конфиг XML не обёрнут в тег `<clickhouse>` — keeper ожидает именно такой корневой элемент | `journalctl -u clickhouse-keeper -n 50 --no-pager` — ищем `Signal 11`; `xmllint --noout /etc/clickhouse-keeper/keeper_config.xml` — проверяем валидность XML | В шаблоне `keeper_config.xml.j2` корневой тег должен быть `<clickhouse>`, а `<keeper_server>` — вложенным внутрь | Добавить smoke-тест в роль: `xmllint` над сгенерированным конфигом до запуска службы |
| Health-gate `wait_for port=9181` зависает вечно на первой ноде | `serial: 1` добавлен к Play 1 (Keeper): первая нода стартует одна, кворума 2/3 нет, порт не открывается | `echo ruok \| nc localhost 9181` на ch-01 — нет ответа `imok`; `journalctl -u clickhouse-keeper` — ищем сообщения о невозможности выбрать лидера | Убрать `serial:` из Play 1; keeper'ы должны стартовать все три одновременно для сборки кворума | Хранить в комментарии к Play 1 явное пояснение: `# no serial — Raft requires quorum of 2/3` |
| `Conflict: clickhouse-keeper conflicts with clickhouse-server-common` при установке пакета | Пакет `clickhouse-keeper` объявляет `Provides: clickhouse-server-common`, что конфликтует с `clickhouse-server` | `apt-cache show clickhouse-keeper \| grep Provides` — видим конфликтующую строку; `apt-get install -s clickhouse-keeper` — симуляция показывает конфликт | Не устанавливать пакет `clickhouse-keeper` отдельно; использовать бинарь `/usr/bin/clickhouse-keeper` из пакета `clickhouse-server`, регистрировать кастомный systemd-юнит | В `install.yml` ставить только `clickhouse-server`; в комментарии указать причину |
| `vault.yml: Decryption failed (no vault secrets were found that could decrypt)` | Переменная `ANSIBLE_VAULT_PASSWORD_FILE` не экспортирована, или файл `.vault_pass` не существует | `echo $ANSIBLE_VAULT_PASSWORD_FILE` — пустая строка; `ls -la .vault_pass` — нет файла; `ansible-vault view inventories/clickhouse/group_vars/clickhouse/vault.yml` — тестовая расшифровка | Создать файл: `echo 'vault_password' > .vault_pass && chmod 600 .vault_pass`; экспортировать: `export ANSIBLE_VAULT_PASSWORD_FILE=$PWD/.vault_pass` | Добавить в `ansible.cfg`: `vault_password_file = .vault_pass`; включить проверку в pre-flight checklist |
| `Permission denied (publickey)` при первом SSH-подключении | Ключ не добавлен в `ssh-agent`, или публичный ключ не загружен в метаданные VM при `tofu apply` | `ssh-add -l` — нет ключей (`The agent has no identities`); `ssh -v ubuntu@<ch-01-ip>` — в выводе смотреть `Authentications that can continue: publickey` | `ssh-add ~/.ssh/id_rsa`; убедиться, что `ssh_public_key_path` в `terraform.tfvars` указывает на правильный `.pub` | В pre-flight checklist: `ssh-add -l` обязательно перед запуском; `tofu output` должен выводить IP, по которому реально идёт коннект |
| Dynamic inventory возвращает пустой список: `"clickhouse": {"hosts": []}` | VM не имеют лейбла `masterclass=true`, не в статусе `RUNNING`, `yc` CLI не аутентифицирован, или VM ещё не созданы | `yc compute instance list` — посмотреть список VM; `yc compute instance get ch-01 --format json \| jq .labels` — проверить лейбл; `yc config list` — проверить активный профиль и токен | Убедиться, что `tofu apply` завершился успешно; проверить лейбл в `terraform/main.tf`: `common_labels = { masterclass = "true" }`; обновить токен: `export YC_TOKEN=$(yc iam create-token)` | Добавить в pre-flight checklist: `python3 inventories/clickhouse/yc.py --list \| python3 -m json.tool` — убедиться, что хосты есть |
