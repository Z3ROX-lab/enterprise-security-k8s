# Module Security Stack
# Déploie IAM (Keycloak), Secrets (Vault), Runtime Security (Falco, Wazuh), Network Security

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

# ========================================
# NAMESPACES
# ========================================

resource "kubernetes_namespace" "security_iam" {
  metadata {
    name = "security-iam"
    labels = {
      "security-tier" = "identity"
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "kubernetes_namespace" "security_detection" {
  metadata {
    name = "security-detection"
    labels = {
      "security-tier" = "edr"
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_namespace" "security_network" {
  metadata {
    name = "security-network"
    labels = {
      "security-tier" = "network"
    }
  }
}

# ========================================
# IAM - KEYCLOAK
# ========================================

resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  namespace  = kubernetes_namespace.security_iam.metadata[0].name
  version    = "18.0.0"

  set {
    name  = "auth.adminUser"
    value = "admin"
  }

  set {
    name  = "auth.adminPassword"
    value = var.keycloak_admin_password
  }

  set {
    name  = "postgresql.enabled"
    value = "true"
  }

  set {
    name  = "postgresql.auth.password"
    value = var.postgres_password
  }

  set {
    name  = "production"
    value = "false"
  }

  set {
    name  = "proxy"
    value = "edge"
  }

  timeout = 600
}

# ========================================
# SECRETS MANAGEMENT - VAULT
# ========================================

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = kubernetes_namespace.security_iam.metadata[0].name
  version    = "0.27.0"

  # Mode dev pour démo (production = Raft HA)
  set {
    name  = "server.dev.enabled"
    value = var.vault_dev_mode ? "true" : "false"
  }

  # Mode production (Raft)
  set {
    name  = "server.ha.enabled"
    value = var.vault_dev_mode ? "false" : "true"
  }

  set {
    name  = "server.ha.replicas"
    value = "3"
  }

  set {
    name  = "ui.enabled"
    value = "true"
  }

  # Vault injector pour injection de secrets
  set {
    name  = "injector.enabled"
    value = "true"
  }

  timeout = 600
}

# ========================================
# PKI - CERT-MANAGER
# ========================================

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.13.3"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  timeout = 600
}

# ClusterIssuer pour certificats auto-signés
resource "null_resource" "selfsigned_issuer" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOF | kubectl apply -f -
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: selfsigned-issuer
      spec:
        selfSigned: {}
      EOF
    EOT
  }

  depends_on = [helm_release.cert_manager]
}

# ========================================
# RUNTIME SECURITY - FALCO
# ========================================

resource "helm_release" "falco" {
  name       = "falco"
  repository = "https://falcosecurity.github.io/charts"
  chart      = "falco"
  namespace  = kubernetes_namespace.security_detection.metadata[0].name
  version    = "4.0.0"

  # eBPF driver (mieux que kernel module)
  set {
    name  = "driver.kind"
    value = "ebpf"
  }

  # Falcosidekick pour export logs
  set {
    name  = "falcosidekick.enabled"
    value = "true"
  }

  set {
    name  = "falcosidekick.webui.enabled"
    value = "true"
  }

  # Export vers Elasticsearch
  set {
    name  = "falcosidekick.config.elasticsearch.hostport"
    value = var.elasticsearch_url
  }

  # Note: Custom rules can be added via ConfigMap after deployment
  # See falco-rules/custom-rules.yaml for example rules

  timeout = 600
}

# ========================================
# HOST INTRUSION DETECTION - WAZUH
# ========================================
#
# Note: Wazuh n'a plus de chart Helm officiel public.
# Utiliser le déploiement manuel avec leurs manifests Kubernetes :
# https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/index.html
#
# Quick deploy command:
# kubectl apply -k https://github.com/wazuh/wazuh-kubernetes/deployments/kubernetes/
#
# Pour activer via Terraform (expérimental), set enable_wazuh = true

resource "null_resource" "wazuh_deployment" {
  count = var.enable_wazuh ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Deploying Wazuh via Kustomize..."
      kubectl create namespace ${kubernetes_namespace.security_detection.metadata[0].name} --dry-run=client -o yaml | kubectl apply -f -

      # Note: This requires the Wazuh repository to be cloned or use kustomize remote
      # kubectl apply -k https://github.com/wazuh/wazuh-kubernetes//deployments/kubernetes/

      echo "Wazuh deployment requires manual configuration. Please follow:"
      echo "https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/index.html"
    EOT
  }

  depends_on = [kubernetes_namespace.security_detection]
}

# ========================================
# POLICY ENFORCEMENT - OPA GATEKEEPER
# ========================================

resource "helm_release" "gatekeeper" {
  name       = "gatekeeper"
  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  namespace  = "gatekeeper-system"
  version    = "3.15.0"

  create_namespace = true

  set {
    name  = "replicas"
    value = "3"
  }

  set {
    name  = "auditInterval"
    value = "60"
  }

  timeout = 600
}

# Constraint Templates OPA
resource "null_resource" "require_labels_template" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<'YAML' | kubectl apply -f -
      apiVersion: templates.gatekeeper.sh/v1
      kind: ConstraintTemplate
      metadata:
        name: k8srequiredlabels
      spec:
        crd:
          spec:
            names:
              kind: K8sRequiredLabels
            validation:
              openAPIV3Schema:
                type: object
                properties:
                  labels:
                    type: array
                    items:
                      type: string
        targets:
          - target: admission.k8s.gatekeeper.sh
            rego: |
              package k8srequiredlabels
              violation[{"msg": msg, "details": {"missing_labels": missing}}] {
                provided := {label | input.review.object.metadata.labels[label]}
                required := {label | label := input.parameters.labels[_]}
                missing := required - provided
                count(missing) > 0
                msg := sprintf("You must provide labels: %v", [missing])
              }
      YAML
    EOT
  }

  depends_on = [helm_release.gatekeeper]
}

# ========================================
# SUPPLY CHAIN - TRIVY OPERATOR
# ========================================

resource "helm_release" "trivy_operator" {
  name       = "trivy-operator"
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  namespace  = "trivy-system"
  version    = "0.20.0"

  create_namespace = true

  set {
    name  = "trivy.ignoreUnfixed"
    value = "false"
  }

  set {
    name  = "operator.scanJobTimeout"
    value = "5m"
  }

  timeout = 600
}

# ========================================
# NETWORK POLICIES - DEFAULT DENY
# ========================================

resource "kubernetes_network_policy" "default_deny_all_iam" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.security_iam.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "allow_dns_iam" {
  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace.security_iam.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }
}
