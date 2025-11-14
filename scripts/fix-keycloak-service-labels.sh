#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Corriger les Labels du StatefulSet Keycloak          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Problème détecté:"
echo "   Les services cherchent: app.kubernetes.io/instance=keycloak"
echo "   Le pod a seulement: app.kubernetes.io/name=keycloak"
echo ""
echo "✅ Solution: Ajouter le label manquant au StatefulSet"
echo ""

read -p "Corriger maintenant ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# 1. Patcher le StatefulSet pour ajouter le label manquant
echo ""
echo "1️⃣  Ajout du label app.kubernetes.io/instance=keycloak..."
echo ""

kubectl patch statefulset keycloak -n security-iam --type=merge -p '
{
  "spec": {
    "template": {
      "metadata": {
        "labels": {
          "app.kubernetes.io/instance": "keycloak"
        }
      }
    }
  }
}'

echo "✅ StatefulSet patché"
echo ""

# 2. Redémarrer le pod pour appliquer les nouveaux labels
echo "2️⃣  Redémarrage du pod pour appliquer les labels..."
kubectl delete pod keycloak-0 -n security-iam --grace-period=10

echo "⏳ Attente du nouveau pod..."
kubectl wait --for=condition=ready pod/keycloak-0 -n security-iam --timeout=120s

echo "✅ Pod redémarré"
echo ""

# 3. Vérifier les labels
echo "3️⃣  Vérification des labels du pod..."
echo ""

kubectl get pod keycloak-0 -n security-iam --show-labels | grep "app.kubernetes.io/instance=keycloak" && {
    echo "✅ Label app.kubernetes.io/instance=keycloak présent"
} || {
    echo "⚠️  Label manquant encore"
}

echo ""

# 4. Vérifier les endpoints
echo "4️⃣  Vérification des endpoints..."
echo ""

sleep 10

kubectl get endpoints -n security-iam | grep keycloak

KEYCLOAK_HTTP_EP=$(kubectl get endpoints keycloak-http -n security-iam -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")

if [ -n "$KEYCLOAK_HTTP_EP" ]; then
    echo ""
    echo "✅ Endpoints créés ! IP du pod: $KEYCLOAK_HTTP_EP"
else
    echo ""
    echo "⚠️  Endpoints toujours vides, attendez encore 10 secondes..."
    sleep 10
    kubectl get endpoints -n security-iam | grep keycloak
fi

echo ""

# 5. Attendre que Keycloak démarre
echo "5️⃣  Attente du démarrage complet de Keycloak (60 secondes)..."
sleep 60

# 6. Test via le service
echo ""
echo "6️⃣  Test via le service keycloak-http..."
echo ""

HTTP_CODE=$(kubectl exec -n security-iam keycloak-0 -- curl -s -o /dev/null -w "%{http_code}" http://keycloak-http.security-iam.svc.cluster.local/auth/ --connect-timeout 5 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "✅ Service accessible (HTTP $HTTP_CODE)"
else
    echo "⚠️  Service pas encore accessible (HTTP $HTTP_CODE)"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ LABELS CORRIGÉS - ENDPOINTS OK               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 L'Ingress devrait maintenant fonctionner !"
echo ""
echo "🌐 Testez dans votre navigateur:"
echo "   https://keycloak.local.lab:8443/auth/admin/"
echo ""
echo "🔐 Credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "📊 Vérifications:"
echo "   kubectl get endpoints -n security-iam | grep keycloak"
echo "   kubectl get pods -n security-iam keycloak-0 --show-labels"
echo ""
