#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    cert-manager                           ║"
echo "║           PKI Automatique pour Kubernetes                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Créer le namespace
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm
echo "📦 Configuration du repository Helm..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Déployer cert-manager
echo ""
echo "🔐 Déploiement de cert-manager 1.13.0..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version 1.13.0 \
  --set installCRDs=true \
  --timeout 5m \
  --wait

echo ""
echo "⏳ Attente que cert-manager soit Ready..."
kubectl wait --for=condition=Ready pod --all -n cert-manager --timeout=300s

echo ""
echo "📊 État des pods :"
kubectl get pods -n cert-manager

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ CERT-MANAGER DÉPLOYÉ                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Service déployé :"
echo "  ✅ cert-manager (controller + webhook + cainjector)"
echo ""
echo "Créer un ClusterIssuer self-signed :"
echo '  kubectl apply -f - <<EOF'
echo '  apiVersion: cert-manager.io/v1'
echo '  kind: ClusterIssuer'
echo '  metadata:'
echo '    name: selfsigned-issuer'
echo '  spec:'
echo '    selfSigned: {}'
echo '  EOF'
echo ""
echo "Script dépendant :"
echo "  ./24-vault-pki.sh  - Configure Vault comme CA avec cert-manager"
echo ""
