output "cluster_name" {
  description = "Nom du cluster Kind"
  value       = kind_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint de l'API Kubernetes"
  value       = kind_cluster.main.endpoint
}

output "kubeconfig_path" {
  description = "Chemin vers le fichier kubeconfig"
  value       = kind_cluster.main.kubeconfig_path
}

output "cluster_ca_certificate" {
  description = "Certificat CA du cluster"
  value       = kind_cluster.main.cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Certificat client"
  value       = kind_cluster.main.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Clé privée client"
  value       = kind_cluster.main.client_key
  sensitive   = true
}
