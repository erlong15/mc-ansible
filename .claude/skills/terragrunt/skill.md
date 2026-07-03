---
name: terragrunt-masterclass
description: Terragrunt DRY patterns, multi-environment configs, and generate blocks for masterclass demos. Covers the progression from raw Terraform to Terragrunt.
metadata:
  type: skill
  topic: terragrunt
---

# Terragrunt skill — masterclass context

## When to introduce Terragrunt

Teach Terragrunt after students understand Terraform modules. The key motivation: DRY across environments (dev/prod) without copy-pasting provider/backend blocks.

## Standard directory layout (from mc-terraform-terragrunt)

```
envs/
├── env.hcl.example     # cloud_id, folder_id — студенты копируют и заполняют
├── dev/
│   ├── env.hcl         # переменные окружения (gitignored)
│   └── vm/
│       └── terragrunt.hcl
└── prod/
    └── vm/
        └── terragrunt.hcl
root.hcl                # общий backend, provider generate
```

## root.hcl template

```hcl
# Корневой конфиг Terragrunt — DRY-бэкенд и провайдер для всех окружений
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        yandex = { source = "yandex-cloud/yandex", version = "~> 0.127" }
      }
    }
    provider "yandex" {
      cloud_id  = "${local.env.locals.cloud_id}"
      folder_id = "${local.env.locals.folder_id}"
    }
  EOF
}

remote_state {
  backend = "s3"
  config = {
    endpoint                    = "https://storage.yandexcloud.net"
    bucket                      = "mc-tfstate"
    key                         = "${path_relative_to_include()}/terraform.tfstate"
    region                      = "ru-central1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_lockfile                = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

## Module terragrunt.hcl template

```hcl
# Конфигурация для среды dev — наследует бэкенд и провайдер из root.hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/vm-stand"
}

inputs = {
  vm_count = 1
  vm_name  = "demo-dev"
}
```

## Key commands for demo

```bash
# Один модуль
terragrunt plan
terragrunt apply

# Все окружения сразу
cd envs/
terragrunt run-all plan
terragrunt run-all apply

# Форматирование
terragrunt hclfmt --terragrunt-check
```

## Teaching progression

1. Show the problem: copy-paste in raw Terraform across dev/prod
2. Introduce `include` + `generate "provider"` → remove duplication
3. Add `remote_state` → centralized S3 state
4. Show `run-all` → deploy all envs in one command
