# Module Kind Cluster
# Crée un cluster Kubernetes local avec Kind

terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4"
    }
  }
}

# Création du cluster Kind
resource "kind_cluster" "main" {
  name            = var.cluster_name
  node_image      = "kindest/node:${var.kubernetes_version}"
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Control plane node
    node {
      role = "control-plane"

      # Port mappings pour accès services
      dynamic "extra_port_mappings" {
        for_each = var.enable_ingress ? [1] : []
        content {
          container_port = 80
          host_port      = 80
          protocol       = "TCP"
        }
      }

      dynamic "extra_port_mappings" {
        for_each = var.enable_ingress ? [1] : []
        content {
          container_port = 443
          host_port      = 443
          protocol       = "TCP"
        }
      }

      # Labels pour control plane
      kubeadm_config_patches = [
        <<-EOF
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOF
      ]
    }

    # Worker nodes
    dynamic "node" {
      for_each = range(var.worker_nodes)
      content {
        role = "worker"

        # Labels pour worker nodes
        kubeadm_config_patches = [
          <<-EOF
          kind: JoinConfiguration
          nodeRegistration:
            kubeletExtraArgs:
              node-labels: "workload-type=security,node-id=worker-${node.key}"
          EOF
        ]
      }
    }

    # Networking
    networking {
      api_server_address = "127.0.0.1"
      api_server_port    = 6443
    }
  }
}

# Attendre que le cluster soit prêt
resource "null_resource" "wait_for_cluster" {
  depends_on = [kind_cluster.main]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Ready nodes --all --timeout=300s --kubeconfig ${kind_cluster.main.kubeconfig_path}"
  }
}

# Installer Calico CNI si demandé
resource "null_resource" "install_calico" {
  count      = var.install_calico ? 1 : 0
  depends_on = [null_resource.wait_for_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml \
        --kubeconfig ${kind_cluster.main.kubeconfig_path}
    EOT
  }
}

# Installer Ingress NGINX si demandé
resource "null_resource" "install_ingress" {
  count      = var.enable_ingress ? 1 : 0
  depends_on = [null_resource.wait_for_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml \
        --kubeconfig ${kind_cluster.main.kubeconfig_path}
      kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s \
        --kubeconfig ${kind_cluster.main.kubeconfig_path}
    EOT
  }
}

# Data sources pour outputs
data "local_file" "kubeconfig" {
  depends_on = [kind_cluster.main]
  filename   = kind_cluster.main.kubeconfig_path
}
