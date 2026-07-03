# Сеть и подсеть для кластера ClickHouse — все три ноды живут в одной подсети

resource "yandex_vpc_network" "main" {
  name = "${var.env}-network"

  labels = local.common_labels
}

# Подсеть в зоне ru-central1-a — CIDR 10.10.0.0/24 достаточно для стенда
resource "yandex_vpc_subnet" "main" {
  name           = "${var.env}-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.0.0/24"]

  labels = local.common_labels
}

# Security Group — правила для SSH снаружи и внутрикластерного трафика ClickHouse/Keeper
resource "yandex_vpc_security_group" "clickhouse" {
  name        = "${var.env}-sg-clickhouse"
  description = "SSH + внутрикластерные порты ClickHouse и Keeper"
  network_id  = yandex_vpc_network.main.id

  labels = local.common_labels

  # SSH — доступ к нодам для Ansible и отладки
  ingress {
    protocol       = "TCP"
    description    = "SSH"
    port           = 22
    v4_cidr_blocks = var.allowed_ssh_cidr
  }

  # Внутрикластерные порты ClickHouse и Keeper — разрешаем только из подсети стенда
  # Список портов: 9000 (native), 8123 (HTTP), 9009 (inter-server), 9181 (Keeper), 9234 (Keeper raft)
  dynamic "ingress" {
    for_each = [9000, 8123, 9009, 9181, 9234]
    content {
      protocol       = "TCP"
      description    = "ClickHouse/Keeper internal port ${ingress.value}"
      port           = ingress.value
      v4_cidr_blocks = yandex_vpc_subnet.main.v4_cidr_blocks
    }
  }

  # Весь исходящий трафик разрешён — ноды качают пакеты, обновления и т.д.
  egress {
    protocol       = "ANY"
    description    = "Весь исходящий трафик"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
