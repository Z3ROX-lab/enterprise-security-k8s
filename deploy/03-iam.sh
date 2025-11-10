#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ÉTAPE 3 : IAM (Keycloak + Vault + cert-manager)      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster Kubernetes non accessible"
    echo "Exécutez d'abord : ./01-cluster.sh"
    exit 1
fi

# Créer les namespaces
echo "📁 Création des namespaces..."
kubectl create namespace security-iam --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Ajouter les repos Helm
echo ""
echo "📦 Configuration des repositories Helm..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Déployer cert-manager (PKI)
echo ""
echo "🔐 Déploiement de cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version 1.13.0 \
  --set installCRDs=true \
  --timeout 5m \
  --wait

echo ""
echo "⏳ Attente que cert-manager soit Ready..."
kubectl wait --for=condition=Ready pod --all -n cert-manager --timeout=300s

# Déployer Keycloak (IAM/SSO)
echo ""
echo "🔑 Déploiement de Keycloak + PostgreSQL..."
helm upgrade --install keycloak bitnami/keycloak \
  --namespace security-iam \
  --version 18.0.0 \
  --set auth.adminUser=admin \
  --set auth.adminPassword=admin123 \
  --set postgresql.enabled=true \
  --set postgresql.auth.password=postgres123 \
  --set production=false \
  --set proxy=edge \
  --timeout 15m \
  --wait=false

echo ""
echo "⏳ Attente que PostgreSQL démarre (peut prendre 5 min)..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=postgresql -n security-iam --timeout=600s || true

echo ""
echo "⏳ Attente que Keycloak démarre (peut prendre 10 min)..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=keycloak -n security-iam --timeout=600s || true

# Déployer Vault (Secrets Management)
echo ""
echo "🔒 Déploiement de HashiCorp Vault..."
helm upgrade --install vault hashicorp/vault \
  --namespace security-iam \
  --version 0.27.0 \
  --set server.dev.enabled=true \
  --set server.ha.enabled=false \
  --set ui.enabled=true \
  --set injector.enabled=true \
  --timeout 10m \
  --wait=false

echo ""
echo "⏳ Attente que Vault démarre..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault -n security-iam --timeout=600s || true

echo ""
echo "📊 État des pods :"
kubectl get pods -n security-iam
kubectl get pods -n cert-manager

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ IAM DÉPLOYÉ AVEC SUCCÈS                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ✅ cert-manager (PKI automatique)"
echo "  ✅ PostgreSQL (base de données Keycloak)"
echo "  ✅ Keycloak (IAM/SSO/OIDC)"
echo "  ✅ Vault (gestion des secrets)"
echo ""
echo "Accès aux services :"
echo "  Keycloak: kubectl port-forward -n security-iam svc/keycloak 8080:80"
echo "            http://localhost:8080 (admin/admin123)"
echo ""
echo "  Vault: kubectl port-forward -n security-iam svc/vault 8200:8200"
echo "         http://localhost:8200"
echo ""
echo "Prochaine étape :"
echo "  ./04-falco.sh"
echo ""
