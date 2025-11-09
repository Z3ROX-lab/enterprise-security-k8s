output "iam_namespace" {
  description = "Namespace IAM"
  value       = kubernetes_namespace.security_iam.metadata[0].name
}

output "detection_namespace" {
  description = "Namespace Detection"
  value       = kubernetes_namespace.security_detection.metadata[0].name
}

output "keycloak_service" {
  description = "Service Keycloak"
  value       = "keycloak.${kubernetes_namespace.security_iam.metadata[0].name}.svc.cluster.local"
}

output "vault_service" {
  description = "Service Vault"
  value       = "vault.${kubernetes_namespace.security_iam.metadata[0].name}.svc.cluster.local:8200"
}

output "falco_service" {
  description = "Service Falco"
  value       = "falco.${kubernetes_namespace.security_detection.metadata[0].name}.svc.cluster.local"
}

output "wazuh_dashboard" {
  description = "Service Wazuh Dashboard"
  value       = "wazuh-dashboard.${kubernetes_namespace.security_detection.metadata[0].name}.svc.cluster.local"
}
