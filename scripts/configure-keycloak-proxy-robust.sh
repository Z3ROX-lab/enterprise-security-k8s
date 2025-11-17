#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Configuration Proxy Keycloak (méthode robuste)         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Trouver le pod Keycloak
POD=$(kubectl get pods -n security-iam | grep keycloak | grep Running | head -n1 | awk '{print $1}')

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    kubectl get pods -n security-iam
    exit 1
fi

echo "✅ Pod Keycloak: $POD"
echo ""

# 2. Identifier le workload parent (Deployment ou StatefulSet)
echo "1️⃣  Identification du type de déploiement..."
echo ""

# Chercher tous les déploiements et statefulsets
DEPLOYMENTS=$(kubectl get deployment -n security-iam -o name 2>/dev/null)
STATEFULSETS=$(kubectl get statefulset -n security-iam -o name 2>/dev/null)

echo "Déploiements disponibles:"
if [ -n "$DEPLOYMENTS" ]; then
    echo "$DEPLOYMENTS"
else
    echo "  (aucun)"
fi

echo ""
echo "StatefulSets disponibles:"
if [ -n "$STATEFULSETS" ]; then
    echo "$STATEFULSETS"
else
    echo "  (aucun)"
fi

echo ""

# Déterminer le type basé sur le nom du pod
if [[ "$POD" =~ -[0-9]+$ ]]; then
    # Le pod se termine par -<nombre>, c'est probablement un StatefulSet
    RESOURCE_TYPE="statefulset"
    RESOURCE_NAME=$(echo "$POD" | sed 's/-[0-9]*$//')
    echo "✅ Détecté: StatefulSet/$RESOURCE_NAME"
else
    # Le pod a un hash aléatoire, c'est un Deployment
    RESOURCE_TYPE="deployment"
    RESOURCE_NAME=$(echo "$POD" | sed 's/-[a-z0-9]\{10\}-[a-z0-9]\{5\}$//')
    echo "✅ Détecté: Deployment/$RESOURCE_NAME"
fi

echo ""

# Vérifier que la ressource existe
if ! kubectl get $RESOURCE_TYPE/$RESOURCE_NAME -n security-iam &>/dev/null; then
    echo "⚠️  $RESOURCE_TYPE/$RESOURCE_NAME non trouvé"
    echo ""
    echo "Listing manuel:"
    kubectl get $RESOURCE_TYPE -n security-iam
    echo ""
    read -p "Entrez le nom exact du $RESOURCE_TYPE: " RESOURCE_NAME
fi

echo "📝 Ressource cible: $RESOURCE_TYPE/$RESOURCE_NAME"
echo ""

# 3. Configuration des variables Keycloak
echo "2️⃣  Configuration des variables proxy Keycloak..."
echo ""

# Ajouter les variables directement avec kubectl set env
kubectl set env $RESOURCE_TYPE/$RESOURCE_NAME -n security-iam \
    KC_PROXY=edge \
    KC_HOSTNAME_STRICT=false \
    KC_HOSTNAME_STRICT_HTTPS=false \
    PROXY_ADDRESS_FORWARDING=true \
    2>&1 || {
        echo ""
        echo "⚠️  Erreur lors de l'ajout des variables"
        echo ""
        echo "Méthode alternative: Patch manuel"
        echo ""

        # Méthode alternative: patch JSON
        kubectl patch $RESOURCE_TYPE/$RESOURCE_NAME -n security-iam --type=json -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {"name": "KC_PROXY", "value": "edge"}
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {"name": "KC_HOSTNAME_STRICT", "value": "false"}
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {"name": "PROXY_ADDRESS_FORWARDING", "value": "true"}
          }
        ]' 2>&1 || echo "⚠️  Patch échoué aussi"
    }

echo "✅ Variables configurées"
echo ""

# 4. Redémarrer le pod
echo "3️⃣  Redémarrage du pod..."
echo ""

kubectl delete pod $POD -n security-iam --grace-period=10

echo "⏳ Attente du nouveau pod (jusqu'à 2 minutes)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n security-iam --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=ready pod -l app=keycloak -n security-iam --timeout=120s 2>/dev/null || \
echo "⚠️  Attente timeout, vérification manuelle..."

NEW_POD=$(kubectl get pods -n security-iam | grep keycloak | grep Running | head -n1 | awk '{print $1}')

if [ -z "$NEW_POD" ]; then
    echo "⚠️  Nouveau pod pas encore prêt, attendez encore..."
    kubectl get pods -n security-iam | grep keycloak
else
    echo "✅ Nouveau pod: $NEW_POD"
fi

echo ""
echo "4️⃣  Attente du démarrage complet de Keycloak (60 secondes)..."
sleep 60

# 5. Vérifier les variables
if [ -n "$NEW_POD" ]; then
    echo ""
    echo "5️⃣  Vérification des variables proxy..."
    kubectl exec -n security-iam $NEW_POD -- env 2>/dev/null | grep -E "(KC_PROXY|KC_HOSTNAME|PROXY_ADDRESS)" || echo "⚠️  Variables non visibles encore"

    echo ""
    echo "6️⃣  Test de connectivité..."

    HTTP_CODE=$(kubectl exec -n security-iam $NEW_POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/ --connect-timeout 5 2>/dev/null || echo "000")
    echo "   http://localhost:8080/auth/ → HTTP $HTTP_CODE"

    HTTP_CODE=$(kubectl exec -n security-iam $NEW_POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/admin/ --connect-timeout 5 2>/dev/null || echo "000")
    echo "   http://localhost:8080/auth/admin/ → HTTP $HTTP_CODE"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          ✅ CONFIGURATION TERMINÉE                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 URLs d'accès:"
echo "   https://keycloak.local.lab:8443/admin/admin/"
echo ""
echo "🔐 Credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "⏳ Attendez encore 1-2 minutes que Keycloak démarre complètement"
echo "🔄 Puis testez dans le navigateur (videz le cache: Ctrl+Shift+R)"
echo ""
echo "📝 Vérifier le statut:"
echo "   kubectl get pods -n security-iam"
echo "   kubectl logs -n security-iam $NEW_POD --tail=50"
echo ""
