variable "keycloak_admin_password" {
  description = "Mot de passe admin Keycloak"
  type        = string
  default     = "admin123"
  sensitive   = true
}

variable "postgres_password" {
  description = "Mot de passe PostgreSQL"
  type        = string
  default     = "postgres123"
  sensitive   = true
}

variable "vault_dev_mode" {
  description = "Activer le mode dev pour Vault (désactiver pour production avec Raft)"
  type        = bool
  default     = true
}

variable "elasticsearch_url" {
  description = "URL Elasticsearch pour Falco"
  type        = string
  default     = "http://elasticsearch-master.security-siem:9200"
}

variable "enable_wazuh" {
  description = "Déployer Wazuh HIDS (désactivé par défaut - utiliser déploiement manuel)"
  type        = bool
  default     = false
}

variable "enable_falco" {
  description = "Déployer Falco runtime security"
  type        = bool
  default     = true
}

variable "enable_gatekeeper" {
  description = "Déployer OPA Gatekeeper"
  type        = bool
  default     = true
}

variable "enable_trivy" {
  description = "Déployer Trivy Operator"
  type        = bool
  default     = true
}
