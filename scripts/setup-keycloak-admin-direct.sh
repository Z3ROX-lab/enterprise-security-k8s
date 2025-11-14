#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        Configuration Admin Keycloak (méthode directe)    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    exit 1
fi

ADMIN_USER="admin"
ADMIN_PASSWORD="admin123"

echo "✅ Pod Keycloak: $POD"
echo ""
echo "🔐 Credentials admin:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo ""

# 1. Créer l'admin avec add-user-keycloak.sh
echo "1️⃣  Création de l'admin avec add-user-keycloak.sh..."
echo ""

kubectl exec -n security-iam $POD -- /opt/jboss/keycloak/bin/add-user-keycloak.sh \
    -r master \
    -u $ADMIN_USER \
    -p $ADMIN_PASSWORD

echo ""
echo "✅ Configuration admin écrite dans le fichier"
echo ""

# 2. Copier le fichier dans un emplacement persistant (si possible)
echo "2️⃣  Sauvegarde du fichier de configuration..."

kubectl exec -n security-iam $POD -- bash -c '
    if [ -f /opt/jboss/keycloak/standalone/configuration/keycloak-add-user.json ]; then
        cp /opt/jboss/keycloak/standalone/configuration/keycloak-add-user.json \
           /opt/jboss/keycloak/standalone/data/keycloak-add-user.json.backup 2>/dev/null || true
        cat /opt/jboss/keycloak/standalone/configuration/keycloak-add-user.json
    fi
'

echo ""

# 3. Redémarrer le pod pour que Keycloak lise la config
echo "3️⃣  Redémarrage du pod Keycloak..."
echo "   ⚠️  Le pod va redémarrer maintenant"
echo ""

read -p "Continuer avec le redémarrage ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "⚠️  Redémarrage annulé"
    echo "   Pour appliquer les changements, redémarrez manuellement:"
    echo "   kubectl delete pod $POD -n security-iam"
    exit 0
fi

echo ""
echo "🔄 Suppression du pod actuel..."
kubectl delete pod $POD -n security-iam --grace-period=10

echo ""
echo "⏳ Attente du nouveau pod (jusqu'à 2 minutes)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n security-iam --timeout=120s

NEW_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
echo "✅ Nouveau pod: $NEW_POD"

echo ""
echo "4️⃣  Attente du démarrage complet de Keycloak..."
echo "   ⏳ Cela peut prendre 60-90 secondes..."
echo ""

# Attendre que Keycloak soit vraiment prêt
for i in {1..18}; do
    HTTP_CODE=$(kubectl exec -n security-iam $NEW_POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ --connect-timeout 2 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "✅ Keycloak est prêt (HTTP $HTTP_CODE)"
        break
    fi

    echo "   Tentative $i/18: HTTP $HTTP_CODE - Attente 5s..."
    sleep 5
done

echo ""
echo "5️⃣  Vérification de l'authentification admin..."
echo ""

# Attendre 10 secondes supplémentaires pour que Keycloak charge tout
sleep 10

# Tester l'authentification
TOKEN_RESPONSE=$(kubectl exec -n security-iam $NEW_POD -- curl -s \
    -d "client_id=admin-cli" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASSWORD" \
    -d "grant_type=password" \
    "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ Authentification admin réussie !"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║            ✅ ADMIN KEYCLOAK CRÉÉ AVEC SUCCÈS             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
else
    echo "⚠️  L'authentification a échoué"
    echo ""
    echo "Réponse de l'API:"
    echo "$TOKEN_RESPONSE"
    echo ""
    echo "📝 Vérifications à faire:"
    echo "   1. Attendre encore 1-2 minutes (Keycloak initialise la DB)"
    echo "   2. Vérifier les logs:"
    echo "      kubectl logs -n security-iam $NEW_POD --tail=100"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         ⚠️  ADMIN CRÉÉ MAIS PAS ENCORE ACTIF              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
fi

echo ""
echo "🔐 Credentials pour la connexion:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "🌐 URLs d'accès:"
echo "   Admin Console:  https://keycloak.local.lab:8443/admin"
echo "   Welcome Page:   https://keycloak.local.lab:8443"
echo ""
echo "📝 Instructions:"
echo "   1. Attendez 1-2 minutes supplémentaires"
echo "   2. Allez sur: https://keycloak.local.lab:8443/admin"
echo "   3. Videz le cache du navigateur (Ctrl+Shift+R)"
echo "   4. Connectez-vous avec admin / admin123"
echo ""
echo "🔍 Si le message 'local access required' persiste:"
echo "   kubectl logs -n security-iam $NEW_POD --tail=50"
echo ""
