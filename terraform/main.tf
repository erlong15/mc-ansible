# Три ноды ClickHouse — одинаковые ВМ, создаются через for_each по карте узлов

locals {
  # Метки применяются ко всем ресурсам — помогают фильтровать по стенду в консоли YC
  common_labels = {
    env         = var.env
    managed-by  = "opentofu"
    masterclass = "true"
  }

  # Карта узлов: имя → любые метаданные (сейчас пусто, можно расширить)
  # for_each по map даёт предсказуемые имена и стабильные адреса в state
  ch_nodes = {
    "ch-01" = {}
    "ch-02" = {}
    "ch-03" = {}
  }
}

# Образ Ubuntu 24.04 LTS — последний актуальный в family, без хардкода ID
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

# Три ноды кластера — прерываемые ВМ (дешевле на стенде, Ansible переустановит всё сам)
resource "yandex_compute_instance" "ch" {
  for_each = local.ch_nodes

  name        = each.key
  hostname    = each.key
  platform_id = "standard-v3"
  zone        = var.yc_zone

  # Прерываемая ВМ: ~3× дешевле, но может быть остановлена YC — ок для учебного стенда
  scheduling_policy {
    preemptible = true
  }

  resources {
    cores         = var.cores
    core_fraction = var.core_fraction
    memory        = var.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.disk_size
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true # внешний IP нужен для Ansible-подключения
    security_group_ids = [yandex_vpc_security_group.clickhouse.id]
  }

  # SSH-ключ пробрасывается через metadata — Ansible подключается от имени ubuntu
  metadata = {
    "user-data" = "#cloud-config\nusers:\n  - name: ubuntu\n    sudo: ALL=(ALL) NOPASSWD:ALL\n    ssh_authorized_keys:\n      - ${file(pathexpand(var.ssh_public_key_path))}"
  }

  labels = local.common_labels
}
