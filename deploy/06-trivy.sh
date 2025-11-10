#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       ÉTAPE 6 : Trivy Operator (Vulnerability Scan)      ║"
echo "║                     (OPTIONNEL)                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  Note : Trivy peut être gourmand en ressources"
read -p "Voulez-vous installer Trivy Operator ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation ignorée."
    exit 0
fi

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster Kubernetes non accessible"
    exit 1
fi

# Ajouter le repo Helm
echo ""
echo "📦 Configuration du repository Helm..."
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

# Déployer Trivy Operator
echo ""
echo "🔍 Déploiement de Trivy Operator..."
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --version 0.18.0 \
  --timeout 5m \
  --wait

echo ""
echo "⏳ Attente que Trivy soit Ready..."
kubectl wait --for=condition=Ready pod --all -n trivy-system --timeout=300s || true

echo ""
echo "📊 État des pods :"
kubectl get pods -n trivy-system

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ TRIVY DÉPLOYÉ AVEC SUCCÈS                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Service déployé :"
echo "  ✅ Trivy Operator (scan des vulnérabilités)"
echo ""
echo "Vérifier les scans :"
echo "  kubectl get vulnerabilityreports --all-namespaces"
echo "  kubectl get configauditreports --all-namespaces"
echo ""
