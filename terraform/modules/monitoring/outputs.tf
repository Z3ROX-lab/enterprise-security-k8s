output "namespace" {
  description = "Namespace monitoring"
  value       = kubernetes_namespace.security_siem.metadata[0].name
}

output "elasticsearch_service" {
  description = "Service Elasticsearch"
  value       = "elasticsearch-master.${kubernetes_namespace.security_siem.metadata[0].name}.svc.cluster.local:9200"
}

output "kibana_service" {
  description = "Service Kibana"
  value       = "kibana-kibana.${kubernetes_namespace.security_siem.metadata[0].name}.svc.cluster.local:5601"
}

output "grafana_service" {
  description = "Service Grafana"
  value       = "prometheus-grafana.${kubernetes_namespace.security_siem.metadata[0].name}.svc.cluster.local:80"
}

output "prometheus_service" {
  description = "Service Prometheus"
  value       = "prometheus-kube-prometheus-prometheus.${kubernetes_namespace.security_siem.metadata[0].name}.svc.cluster.local:9090"
}
