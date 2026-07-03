# Выходные значения — интерфейс между Terraform и Ansible-инвентарём

# Карта нод: имя → {external_ip, internal_ip}
# Используется для передачи адресов в шаблон инвентаря
output "clickhouse_nodes" {
  description = "Адреса всех нод кластера: external_ip (SSH) и internal_ip (репликация)"
  value = {
    for name, instance in yandex_compute_instance.ch : name => {
      external_ip = instance.network_interface[0].nat_ip_address
      internal_ip = instance.network_interface[0].ip_address
    }
  }
}

# Готовый hosts.yaml для Ansible — рендерится через шаблон inventory.tftpl
# Команда: tofu output -raw inventory > ../inventories/clickhouse/hosts.yaml
output "inventory" {
  description = "Ansible-инвентарь в формате YAML. Сохрани командой: tofu output -raw inventory > ../inventories/clickhouse/hosts.yaml"
  value = templatefile("${path.module}/inventory.tftpl", {
    nodes = {
      for name, instance in yandex_compute_instance.ch : name => {
        external_ip = instance.network_interface[0].nat_ip_address
        internal_ip = instance.network_interface[0].ip_address
      }
    }
    ansible_user = "ubuntu"
  })
}
