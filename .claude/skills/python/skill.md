---
name: python-masterclass
description: Python patterns for demo scripts, K8s automation, Ansible modules, and data processing in masterclass contexts.
metadata:
  type: skill
  topic: python
---

# Python skill — masterclass context

## Typical Python use cases in masterclasses

1. **K8s automation scripts** — using kubernetes Python client
2. **Demo helper scripts** — setup/teardown, health checks
3. **Ansible custom modules** — when existing modules aren't enough
4. **Data generation** — test data, load generation

## Kubernetes client example

```python
#!/usr/bin/env python3
"""Демонстрация работы с K8s API из Python."""
from kubernetes import client, config

def list_pods(namespace: str = "default") -> None:
    config.load_kube_config()          # из ~/.kube/config
    # config.load_incluster_config()   # внутри pod

    v1 = client.CoreV1Api()
    pods = v1.list_namespaced_pod(namespace)

    for pod in pods.items:
        print(f"{pod.metadata.name}: {pod.status.phase}")

if __name__ == "__main__":
    list_pods("demo-dev")
```

## Minimal FastAPI service for K8s demos

```python
from fastapi import FastAPI
import os
import socket

app = FastAPI()

@app.get("/")
def root():
    return {"hostname": socket.gethostname(), "version": os.getenv("APP_VERSION", "dev")}

@app.get("/health")
def health():
    return {"status": "ok"}
```

## Demo helper script pattern

```python
#!/usr/bin/env python3
"""Скрипт подготовки стенда — запускать перед началом мастеркласса."""
import subprocess
import sys

def run(cmd: str, check: bool = True) -> subprocess.CompletedProcess:
    print(f"$ {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.returncode != 0 and check:
        print(f"ERROR: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result

def main():
    run("kubectl cluster-info")
    run("helm repo update")
    run("kubectl get nodes")
    print("Стенд готов к работе!")

if __name__ == "__main__":
    main()
```

## requirements.txt for masterclass scripts

```
kubernetes>=29.0.0
pyyaml>=6.0
requests>=2.31.0
rich>=13.0.0   # красивый вывод в терминале для демо
```

## Packaging with uv (modern, fast)

```bash
# Создать окружение
uv venv && source .venv/bin/activate

# Установить зависимости
uv pip install -r requirements.txt

# Запустить скрипт
uv run script.py
```

## Common commands for demo

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 script.py

# Форматирование
ruff format .
ruff check .
```
