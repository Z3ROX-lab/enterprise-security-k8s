#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Fix Keycloak PVC Issue - Remove H2 Volume              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🔍 Diagnostic..."
echo ""

# Vérifier l'état actuel
echo "📊 État du StatefulSet Keycloak:"
kubectl get statefulset -n security-iam keycloak -o wide

echo ""
echo "📦 PVC actuels:"
kubectl get pvc -n security-iam

echo ""
echo "⚠️  Problème: Le StatefulSet essaie de monter 'keycloak-data-persistent'"
echo "   qui est en cours de suppression (utilisé par l'ancienne base H2)"
echo ""
echo "✅ Solution: Recréer le StatefulSet SANS ce volume"
echo "   (Les données sont maintenant dans PostgreSQL)"
echo ""

read -p "Continuer avec la correction ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "🔄 Étape 1: Sauvegarder le StatefulSet actuel..."
kubectl get statefulset -n security-iam keycloak -o yaml > /tmp/keycloak-sts-backup.yaml
echo "   ✅ Sauvegardé dans /tmp/keycloak-sts-backup.yaml"

echo ""
echo "🗑️  Étape 2: Supprimer le StatefulSet (en gardant les pods)..."
kubectl delete statefulset -n security-iam keycloak --cascade=orphan
echo "   ✅ StatefulSet supprimé"

echo ""
echo "⏳ Attendre 5 secondes..."
sleep 5

echo ""
echo "🧹 Étape 3: Forcer la suppression du PVC bloqué..."
kubectl patch pvc keycloak-data-persistent -n security-iam -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete pvc keycloak-data-persistent -n security-iam --force --grace-period=0 2>/dev/null || true
echo "   ✅ PVC supprimé"

echo ""
echo "🧹 Étape 4: Supprimer le pod Keycloak pour forcer la recréation..."
kubectl delete pod -n security-iam keycloak-0 2>/dev/null || true
echo "   ✅ Pod supprimé"

echo ""
echo "⏳ Attendre 10 secondes..."
sleep 10

echo ""
echo "🚀 Étape 5: Recréer le StatefulSet SANS le volume H2..."

cat <<YAML | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak
  namespace: security-iam
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: keycloak
      app.kubernetes.io/instance: keycloak
  serviceName: keycloak-headless
  template:
    metadata:
      labels:
        app.kubernetes.io/name: keycloak
        app.kubernetes.io/instance: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:18.0.0
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "admin123"
        - name: KC_DB
          value: "postgres"
        - name: KC_DB_URL_HOST
          value: "keycloak-postgresql"
        - name: KC_DB_URL_PORT
          value: "5432"
        - name: KC_DB_URL_DATABASE
          value: "keycloak"
        - name: KC_DB_USERNAME
          value: "keycloak"
        - name: KC_DB_PASSWORD
          value: "keycloak123"
        - name: KC_PROXY
          value: "edge"
        - name: KC_HOSTNAME_STRICT
          value: "false"
        - name: KC_HTTP_ENABLED
          value: "true"
        args:
        - "start-dev"
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        - name: https
          containerPort: 8443
          protocol: TCP
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        readinessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 30
YAML

echo "   ✅ StatefulSet recréé"

echo ""
echo "⏳ Attente du démarrage de Keycloak..."
kubectl wait --for=condition=ready pod -n security-iam -l app.kubernetes.io/name=keycloak --timeout=300s || true

echo ""
echo "📊 État final:"
kubectl get pods -n security-iam
echo ""
kubectl get pvc -n security-iam

echo ""
echo "✅ Correction terminée !"
echo ""
echo "🧪 Tester l'accès:"
echo "   https://keycloak.local.lab:8443/auth/admin/"
echo "   Credentials: admin / admin123"
echo ""
echo "💡 Le user admin est automatiquement créé dans PostgreSQL"
echo ""
