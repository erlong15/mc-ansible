---
name: ansible-masterclass
description: Ansible playbooks, roles, and inventory patterns for masterclass demos. Covers node configuration, idempotency, and Yandex Cloud dynamic inventory.
metadata:
  type: skill
  topic: ansible
---

# Ansible skill — masterclass context

## Standard project layout

```
ansible/
├── inventory/
│   ├── hosts.ini           # статический инвентарь для демо
│   └── group_vars/
│       └── all.yml         # общие переменные
├── roles/
│   └── <role-name>/
│       ├── tasks/main.yml
│       ├── defaults/main.yml
│       └── templates/
├── playbook.yml            # основной плейбук
└── requirements.yml        # galaxy dependencies
```

## Minimal playbook template

```yaml
---
# Плейбук для настройки узлов стенда мастеркласса
- name: Configure demo nodes
  hosts: all
  become: true
  gather_facts: true

  vars:
    app_name: demo
    app_version: "1.0.0"

  pre_tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

  roles:
    - role: common
    - role: docker

  tasks:
    - name: Deploy application config
      ansible.builtin.template:
        src: app.conf.j2
        dest: /etc/app/app.conf
        mode: "0644"
      notify: restart app

  handlers:
    - name: restart app
      ansible.builtin.systemd:
        name: app
        state: restarted
```

## Yandex Cloud dynamic inventory

```bash
# Установить плагин
pip install yandex.cloud

# inventory/yc.yml
plugin: yandex.cloud.yc
folder_id: "{{ lookup('env', 'YC_FOLDER_ID') }}"
```

## Idempotency rules for demos

1. Always use modules (`apt`, `copy`, `template`, `systemd`) — never `shell:`/`command:` when a module exists.
2. Use `creates:` with `command:` if you must use it (idempotency guard).
3. Check mode: `ansible-playbook playbook.yml --check --diff` before running live.
4. Tags for partial runs: `--tags install`, `--tags configure`, `--tags deploy`.

## Key commands for demo

```bash
# Проверить подключение
ansible all -i inventory/hosts.ini -m ping

# Dry run с diff
ansible-playbook -i inventory/hosts.ini playbook.yml --check --diff

# Запустить
ansible-playbook -i inventory/hosts.ini playbook.yml -v

# Только определённые роли
ansible-playbook -i inventory/hosts.ini playbook.yml --tags docker
```

## Common patterns for K8s masterclasses

```yaml
# Установка kubectl на узел
- name: Install kubectl
  ansible.builtin.get_url:
    url: "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
    dest: /usr/local/bin/kubectl
    mode: "0755"
    checksum: "sha256:<hash>"

# Добавить helm repo
- name: Add helm repo
  kubernetes.core.helm_repository:
    name: argo
    repo_url: https://argoproj.github.io/argo-helm
```
