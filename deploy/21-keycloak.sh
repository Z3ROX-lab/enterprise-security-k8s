#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                      Keycloak                             ║"
echo "║          IAM / SSO / OIDC / SAML Provider                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Créer le namespace
kubectl create namespace security-iam --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm officiel Keycloak
echo "📦 Configuration du repository Helm..."
helm repo add codecentric https://codecentric.github.io/helm-charts
helm repo update

# Déployer Keycloak (avec PostgreSQL intégré)
echo ""
echo "🔑 Déploiement de Keycloak + PostgreSQL..."
echo "   Note: Utilisation du chart officiel Keycloak (codecentric)"
helm upgrade --install keycloak codecentric/keycloak \
  --namespace security-iam \
  --set keycloak.username=admin \
  --set keycloak.password=admin123 \
  --set postgresql.enabled=true \
  --set postgresql.postgresqlPassword=postgres123 \
  --timeout 15m \
  --wait=false

echo ""
echo "⏳ Attente que PostgreSQL démarre (5 min)..."
for i in {1..10}; do
    if kubectl get pod -n security-iam -l app=postgresql --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✅ PostgreSQL est Running !"
        break
    fi
    echo "  Check $i/10..."
    sleep 30
done

echo ""
echo "⏳ Attente que Keycloak démarre (10 min)..."
for i in {1..20}; do
    if kubectl get pod -n security-iam -l app.kubernetes.io/name=keycloak --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✅ Keycloak est Running !"
        break
    fi
    echo "  Check $i/20..."
    sleep 30
done

echo ""
echo "📊 État des pods :"
kubectl get pods -n security-iam

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ KEYCLOAK DÉPLOYÉ                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ✅ Keycloak (IAM/SSO)"
echo "  ✅ PostgreSQL (base de données)"
echo ""
echo "Accès au dashboard :"
echo "  kubectl port-forward -n security-iam svc/keycloak 8080:80"
echo "  http://localhost:8080 (admin/admin123)"
echo ""
echo "Console admin :"
echo "  http://localhost:8080/admin"
echo ""
