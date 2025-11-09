# Enterprise Security Stack - Infrastructure Principal
# Déploiement sur Kind (Kubernetes in Docker) pour Windows 11 + Docker Desktop

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Variables
variable "cluster_name" {
  description = "Nom du cluster Kind"
  type        = string
  default     = "enterprise-security"
}

variable "kubernetes_version" {
  description = "Version Kubernetes"
  type        = string
  default     = "v1.28.0"
}

variable "worker_nodes" {
  description = "Nombre de worker nodes"
  type        = number
  default     = 2
}

variable "enable_ingress" {
  description = "Activer Ingress Controller"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Activer stack monitoring"
  type        = bool
  default     = true
}

variable "enable_security_stack" {
  description = "Activer stack de sécurité complète"
  type        = bool
  default     = true
}

# Module Kind Cluster
module "kind_cluster" {
  source = "./modules/kind-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  worker_nodes       = var.worker_nodes
  enable_ingress     = var.enable_ingress
}

# Provider Kubernetes
provider "kubernetes" {
  host                   = module.kind_cluster.cluster_endpoint
  cluster_ca_certificate = module.kind_cluster.cluster_ca_certificate
  client_certificate     = module.kind_cluster.client_certificate
  client_key             = module.kind_cluster.client_key
}

# Provider Helm
provider "helm" {
  kubernetes {
    host                   = module.kind_cluster.cluster_endpoint
    cluster_ca_certificate = module.kind_cluster.cluster_ca_certificate
    client_certificate     = module.kind_cluster.client_certificate
    client_key             = module.kind_cluster.client_key
  }
}

# Module Monitoring (Prometheus, Grafana, ELK)
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  depends_on = [module.kind_cluster]
}

# Module Security Stack (IAM, EDR, Network Security)
module "security_stack" {
  source = "./modules/security-stack"
  count  = var.enable_security_stack ? 1 : 0

  depends_on = [module.kind_cluster, module.monitoring]
}

# Outputs
output "cluster_name" {
  description = "Nom du cluster créé"
  value       = module.kind_cluster.cluster_name
}

output "kubeconfig_path" {
  description = "Chemin vers kubeconfig"
  value       = module.kind_cluster.kubeconfig_path
}

output "cluster_endpoint" {
  description = "Endpoint API Kubernetes"
  value       = module.kind_cluster.cluster_endpoint
  sensitive   = true
}

output "grafana_url" {
  description = "URL Grafana (via port-forward)"
  value       = var.enable_monitoring ? "kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80" : null
}

output "kibana_url" {
  description = "URL Kibana (via port-forward)"
  value       = var.enable_monitoring ? "kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601" : null
}

output "keycloak_url" {
  description = "URL Keycloak (via port-forward)"
  value       = var.enable_security_stack ? "kubectl port-forward -n security-iam svc/keycloak 8080:80" : null
}
