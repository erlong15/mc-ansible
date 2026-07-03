---
name: terraform-masterclass
description: OpenTofu/Terraform patterns for Yandex Cloud masterclass infrastructure. Covers MK8S, VMs, networking, IAM, and teaching-friendly IaC conventions.
metadata:
  type: skill
  topic: terraform
---

# Terraform/OpenTofu skill — masterclass context

## Standard file layout

```
terraform/
├── provider.tf         # yandex provider, required_providers
├── variables.tf        # cloud_id, folder_id, and topic-specific vars
├── main.tf             # K8s cluster or core resources
├── network.tf          # VPC, subnets, security groups
├── outputs.tf          # kubeconfig command, URLs, passwords
├── terraform.tfvars.example  # что заполнять студентам
└── .terraform.lock.hcl
```

## provider.tf template

```hcl
# Провайдер Yandex Cloud — использует yandex_client_config для авторизации
terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.127"
    }
  }
  required_version = ">= 1.5.0"
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  # Токен берётся из окружения: export YC_TOKEN=$(yc iam create-token)
}

# Данные об IAM-токене текущего пользователя — без явного token в provider
data "yandex_client_config" "me" {}
```

## variables.tf template

```hcl
variable "cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "folder_id" {
  description = "Folder ID для ресурсов мастеркласса"
  type        = string
}

variable "domain" {
  description = "Основной домен стенда, например demo.example.com"
  type        = string
  default     = "demo.example.com"
}
```

## MK8S cluster (minimal, for demos)

```hcl
# Managed Kubernetes кластер — минимальная конфигурация для стенда
resource "yandex_kubernetes_cluster" "main" {
  name       = "mc-cluster"
  network_id = yandex_vpc_network.main.id

  master {
    version   = "1.31"
    zonal {
      zone      = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.main.id
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.k8s.id
  node_service_account_id = yandex_iam_service_account.k8s.id

  release_channel = "REGULAR"
}

# Группа узлов — прерываемые ВМ для экономии бюджета
resource "yandex_kubernetes_node_group" "main" {
  cluster_id = yandex_kubernetes_cluster.main.id
  name       = "default"
  version    = "1.31"

  instance_template {
    platform_id = "standard-v3"
    resources {
      cores         = 4
      core_fraction = 50
      memory        = 8
    }
    scheduling_policy { preemptible = true }
    boot_disk { size = 64; type = "network-ssd" }
  }

  scale_policy {
    fixed_scale { size = 2 }
  }

  allocation_policy {
    location { zone = "ru-central1-a" }
  }
}
```

## outputs.tf template

```hcl
output "kubeconfig_command" {
  value       = "yc managed-kubernetes cluster get-credentials ${yandex_kubernetes_cluster.main.name} --external --force"
  description = "Команда для получения kubeconfig"
}

output "cluster_id" {
  value = yandex_kubernetes_cluster.main.id
}
```

## Conventions

- `terraform.tfvars` in `.gitignore` — copy from `.tfvars.example`
- Russian comments on every resource (1-2 lines)
- `labels = { masterclass = "true", env = "demo" }` on all resources that support labels
- Mirror (offline): `provider_installation { network_mirror { url = "https://terraform-mirror.yandexcloud.net/" } }`
