#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Fix Keycloak Health Probes (HTTP 404 → TCP)            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🔍 Diagnostic du problème..."
echo ""

# Vérifier l'état actuel
echo "📊 État actuel du pod Keycloak:"
kubectl get pods -n security-iam keycloak-0 2>/dev/null || echo "Pod non trouvé"

echo ""
echo "📋 Endpoints Keycloak (devrait être vide si problème):"
kubectl get endpoints -n security-iam keycloak-http

echo ""
echo "⚠️  Problème identifié:"
echo "   Les probes HTTP (/health/ready et /health/live) retournent 404"
echo "   → Keycloak redémarre en boucle"
echo "   → Endpoints vides → 503 sur l'Ingress"
echo ""
echo "✅ Solution:"
echo "   Remplacer les probes HTTP par des probes TCP (port 8080)"
echo "   → Plus robuste pour Keycloak en mode start-dev"
echo ""

read -p "Continuer avec la correction ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "🔄 Étape 1: Sauvegarder le StatefulSet actuel..."
kubectl get statefulset -n security-iam keycloak -o yaml > /tmp/keycloak-sts-backup-probes.yaml
echo "   ✅ Sauvegardé dans /tmp/keycloak-sts-backup-probes.yaml"

echo ""
echo "🗑️  Étape 2: Supprimer le StatefulSet (en gardant les pods)..."
kubectl delete statefulset -n security-iam keycloak --cascade=orphan
echo "   ✅ StatefulSet supprimé"

echo ""
echo "⏳ Attendre 3 secondes..."
sleep 3

echo ""
echo "🚀 Étape 3: Recréer le StatefulSet avec probes TCP..."

cat <<EOF | kubectl apply -f -
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
EOF

echo "   ✅ StatefulSet recréé avec probes TCP"

echo ""
echo "🔄 Étape 4: Redémarrer le pod Keycloak..."
kubectl delete pod -n security-iam keycloak-0 2>/dev/null || true
echo "   ✅ Pod supprimé, il va redémarrer automatiquement"

echo ""
echo "⏳ Étape 5: Attente du démarrage de Keycloak (jusqu'à 5 minutes)..."
kubectl wait --for=condition=ready pod -n security-iam -l app.kubernetes.io/name=keycloak --timeout=300s || echo "⚠️  Timeout, mais le pod peut encore démarrer..."

echo ""
echo "📊 État final:"
kubectl get pods -n security-iam keycloak-0

echo ""
echo "🔌 Endpoints (ne devrait plus être vide):"
kubectl get endpoints -n security-iam keycloak-http

echo ""
echo "✅ Correction terminée !"
echo ""
echo "🧪 Testez l'accès:"
echo "   https://keycloak.local.lab:8443/admin/"
echo "   Credentials: admin / admin123"
echo ""
echo "💡 Les probes TCP vérifient maintenant que le port 8080 est ouvert"
echo "   Plus de problèmes HTTP 404 !"
echo ""
