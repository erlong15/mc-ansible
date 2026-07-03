# Провайдер Yandex Cloud — токен берётся из YC_TOKEN или yc CLI, хардкодить не нужно
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.127"
    }
  }
}

# cloud_id, folder_id и zone берём из переменных — никаких хардкодов
provider "yandex" {
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
  # Токен: export YC_TOKEN=$(yc iam create-token)
  # Или через yc CLI: yc config set token <token>
}
