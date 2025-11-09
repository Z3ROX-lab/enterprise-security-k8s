# Module Monitoring Stack
# Déploie Prometheus, Grafana, ELK Stack

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# Namespace pour monitoring
resource "kubernetes_namespace" "security_siem" {
  metadata {
    name = "security-siem"
    labels = {
      "security-tier" = "logging"
      "monitoring"    = "enabled"
    }
  }
}

# ELK Stack - Elasticsearch
resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  namespace  = kubernetes_namespace.security_siem.metadata[0].name
  version    = "8.5.1"

  set {
    name  = "replicas"
    value = "1"
  }

  set {
    name  = "minimumMasterNodes"
    value = "1"
  }

  set {
    name  = "resources.requests.memory"
    value = "2Gi"
  }

  set {
    name  = "resources.limits.memory"
    value = "4Gi"
  }

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  # Security settings
  set {
    name  = "esJavaOpts"
    value = "-Xmx2g -Xms2g"
  }

  timeout = 600
}

# ELK Stack - Kibana
resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = kubernetes_namespace.security_siem.metadata[0].name
  version    = "8.5.1"

  set {
    name  = "resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name  = "elasticsearchHosts"
    value = "http://elasticsearch-master:9200"
  }

  depends_on = [helm_release.elasticsearch]
  timeout    = 600
}

# ELK Stack - Filebeat
resource "helm_release" "filebeat" {
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  namespace  = kubernetes_namespace.security_siem.metadata[0].name
  version    = "8.5.1"

  set {
    name  = "filebeatConfig.filebeat\\.yml"
    value = yamlencode({
      "filebeat.inputs" = [{
        type = "container"
        paths = [
          "/var/log/containers/*.log"
        ]
      }]
      "output.elasticsearch" = {
        hosts = ["http://elasticsearch-master:9200"]
      }
    })
  }

  depends_on = [helm_release.elasticsearch]
}

# Prometheus Stack (avec Grafana)
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.security_siem.metadata[0].name
  version    = "55.0.0"

  # Prometheus settings
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }

  # Grafana settings
  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.persistence.enabled"
    value = "false"
  }

  # Enable dashboards
  set {
    name  = "grafana.defaultDashboardsEnabled"
    value = "true"
  }

  # Alertmanager
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  timeout = 600
}

# ConfigMap pour dashboards Grafana personnalisés
resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "custom-security-dashboards"
    namespace = kubernetes_namespace.security_siem.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "security-overview.json" = file("${path.module}/dashboards/security-overview.json")
  }

  depends_on = [helm_release.prometheus]
}
