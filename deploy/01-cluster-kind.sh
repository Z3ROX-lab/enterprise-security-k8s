#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ÉTAPE 1 : Cluster Kubernetes Kind            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

CLUSTER_NAME="enterprise-security"

# Vérifier si le cluster existe déjà
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Le cluster '${CLUSTER_NAME}' existe déjà."
    read -p "Voulez-vous le supprimer et le recréer ? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Suppression du cluster existant..."
        kind delete cluster --name ${CLUSTER_NAME}
    else
        echo "✅ Utilisation du cluster existant"
        exit 0
    fi
fi

echo "🚀 Création du cluster Kind..."
echo ""

# Créer la configuration Kind
cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 80
    protocol: TCP
  - containerPort: 30443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
- role: worker
EOF

# Créer le cluster
kind create cluster --config /tmp/kind-config.yaml

echo ""
echo "📦 Installation de Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

echo ""
echo "⏳ Attente que tous les nœuds soient Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo ""
echo "📊 État du cluster :"
kubectl get nodes

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            ✅ CLUSTER CRÉÉ AVEC SUCCÈS                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Cluster : ${CLUSTER_NAME}"
echo "Nœuds   : 4 (1 control-plane + 3 workers)"
echo "CNI     : Calico"
echo ""
echo "Prochaine étape :"
echo "  ./10-elasticsearch.sh (monitoring)"
echo "  ./20-cert-manager.sh (PKI)"
echo "  ./30-falco.sh (security)"
echo "  ou ./deploy-all.sh (tout déployer)"
echo ""
