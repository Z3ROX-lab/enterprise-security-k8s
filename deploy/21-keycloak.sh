#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                      Keycloak                             ║"
echo "║          IAM / SSO / OIDC / SAML Provider                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Créer le namespace
kubectl create namespace security-iam --dry-run=client -o yaml | kubectl apply -f -

# Ajouter les repos Helm
echo "📦 Configuration des repositories Helm..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add codecentric https://codecentric.github.io/helm-charts
helm repo update

# Déployer PostgreSQL séparément (avec une version récente du chart)
echo ""
echo "🗄️  Déploiement de PostgreSQL..."
helm upgrade --install keycloak-postgresql bitnami/postgresql \
  --namespace security-iam \
  --set auth.username=keycloak \
  --set auth.password=keycloak123 \
  --set auth.database=keycloak \
  --set primary.persistence.enabled=false \
  --timeout 10m \
  --wait=false

echo "⏳ Attente que PostgreSQL soit prêt (2-3 min)..."
sleep 60

# Déployer Keycloak (sans PostgreSQL intégré, utilise celui qu'on vient de déployer)
echo ""
echo "🔑 Déploiement de Keycloak..."
echo "   Note: PostgreSQL déployé séparément pour éviter les conflits d'images"
helm upgrade --install keycloak codecentric/keycloak \
  --namespace security-iam \
  --set keycloak.username=admin \
  --set keycloak.password=admin123 \
  --set postgresql.enabled=false \
  --set keycloak.extraEnv="
    - name: DB_VENDOR
      value: postgres
    - name: DB_ADDR
      value: keycloak-postgresql
    - name: DB_DATABASE
      value: keycloak
    - name: DB_USER
      value: keycloak
    - name: DB_PASSWORD
      value: keycloak123
  " \
  --timeout 15m \
  --wait=false

echo ""
echo "⏳ Vérification que PostgreSQL est bien démarré..."
for i in {1..10}; do
    if kubectl get pod -n security-iam -l app.kubernetes.io/name=postgresql --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✅ PostgreSQL est Running !"
        break
    fi
    echo "  Check $i/10..."
    sleep 15
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
