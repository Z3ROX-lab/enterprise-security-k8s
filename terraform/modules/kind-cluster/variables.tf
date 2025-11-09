variable "cluster_name" {
  description = "Nom du cluster Kind"
  type        = string
}

variable "kubernetes_version" {
  description = "Version de Kubernetes (format: v1.28.0)"
  type        = string
}

variable "worker_nodes" {
  description = "Nombre de worker nodes"
  type        = number
  default     = 2
}

variable "enable_ingress" {
  description = "Installer Ingress NGINX Controller"
  type        = bool
  default     = true
}

variable "install_calico" {
  description = "Installer Calico CNI pour NetworkPolicies"
  type        = bool
  default     = true
}
