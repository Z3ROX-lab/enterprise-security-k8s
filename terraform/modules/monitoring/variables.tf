variable "grafana_admin_password" {
  description = "Mot de passe admin Grafana"
  type        = string
  default     = "admin123"
  sensitive   = true
}

variable "elasticsearch_storage_size" {
  description = "Taille du stockage Elasticsearch"
  type        = string
  default     = "10Gi"
}

variable "prometheus_retention" {
  description = "Durée de rétention des métriques Prometheus"
  type        = string
  default     = "7d"
}
