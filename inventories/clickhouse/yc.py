#!/usr/bin/env python3
"""Динамический инвентори Ansible поверх Yandex Cloud CLE (yc).

Идея: вместо статического hosts.yaml спрашиваем у YC список живых инстансов
прямо во время запуска плейбука. Источник истины — само облако, а не файл,
который может протухнуть после tofu apply/destroy.

Почему скрипт, а не galaxy-плагин: доступ к Ansible Galaxy из РФ под вопросом,
а yc CLI уже установлен и аутентифицирован. Так инвентори самодостаточен.

Контракт dynamic inventory: скрипт отвечает на --list (весь инвентори в JSON)
и на --host <name> (vars одного хоста; здесь не нужны — отдаём всё в _meta).

Группировка: в группу `clickhouse` попадают инстансы с меткой masterclass=true
(её ставит OpenTofu). Идентичность нод (keeper_id/ch_shard/ch_replica) лежит
рядом в host_vars/<name>.yml и мёржится Ansible автоматически по имени хоста.

Переменные окружения:
  YC_PROFILE — профиль yc CLI (если задан, передаётся как --profile).
  YC_INVENTORY_LABEL — метка-фильтр кластера (по умолчанию masterclass=true).
"""

import json
import os
import subprocess
import sys


def yc_instances():
    # Спрашиваем у YC список инстансов в каталоге активного профиля.
    cmd = ["yc"]
    profile = os.environ.get("YC_PROFILE")
    if profile:
        cmd += ["--profile", profile]
    cmd += ["compute", "instance", "list", "--format", "json"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def build_inventory():
    # Метка-фильтр вида "ключ=значение" — отбираем только ноды нашего кластера.
    label = os.environ.get("YC_INVENTORY_LABEL", "masterclass=true")
    key, _, value = label.partition("=")

    inventory = {"clickhouse": {"hosts": []}, "_meta": {"hostvars": {}}}
    for inst in yc_instances():
        labels = inst.get("labels") or {}
        if labels.get(key) != value:
            continue
        if inst.get("status") != "RUNNING":
            continue
        name = inst["name"]
        nic = inst["network_interfaces"][0]["primary_v4_address"]
        internal = nic["address"]
        external = (nic.get("one_to_one_nat") or {}).get("address")
        inventory["clickhouse"]["hosts"].append(name)
        inventory["_meta"]["hostvars"][name] = {
            # Подключаемся по внешнему IP; если NAT нет — по внутреннему.
            "ansible_host": external or internal,
            # Внутренний IP нужен для raft/zookeeper/remote_servers внутри кластера.
            "internal_ip": internal,
            "ansible_user": "ubuntu",
        }
    inventory["clickhouse"]["hosts"].sort()
    return inventory


def main():
    if "--host" in sys.argv:
        # Все vars отдаём через _meta в --list, поэтому здесь пусто.
        print(json.dumps({}))
        return
    print(json.dumps(build_inventory(), indent=2))


if __name__ == "__main__":
    main()
