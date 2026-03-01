variable "admin_username" {
    description = "Nombre del usuario administrador de la VM"
    type        = string
    default     = "dante" 
}

variable "ssh_public_key_path" {
  description = "Ruta local a tu llave pública de SSH"
  type        = string
  default     = "/home/dante/.ssh/id_rsa.pub"
}