# Переменные стенда — значения задаются в terraform.tfvars (скопируй из .tfvars.example)

variable "yc_cloud_id" {
  description = "Идентификатор облака Yandex Cloud (yc config get cloud-id)"
  type        = string
}

variable "yc_folder_id" {
  description = "Идентификатор каталога, где создаются ресурсы (yc config get folder-id)"
  type        = string
}

variable "yc_zone" {
  description = "Зона доступности для ресурсов"
  type        = string
  default     = "ru-central1-a"
}

variable "env" {
  description = "Окружение — метка для всех ресурсов (например: ch, dev, test)"
  type        = string
  default     = "ch"
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу для доступа на ВМ"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr" {
  description = "Список CIDR, которым разрешён SSH на ноды (ограничьте своим IP в продакшене)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Параметры вычислительных ресурсов — вынесены в переменные для гибкости стенда
variable "cores" {
  description = "Количество vCPU на каждой ноде"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Объём RAM на каждой ноде (ГБ)"
  type        = number
  default     = 4
}

variable "core_fraction" {
  description = "Гарантированная доля vCPU (20% — достаточно для стенда, дешевле)"
  type        = number
  default     = 20
}

variable "disk_size" {
  description = "Размер загрузочного диска каждой ноды (ГБ)"
  type        = number
  default     = 20
}
