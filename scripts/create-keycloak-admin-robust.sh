#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Créer Admin Keycloak via API REST (méthode robuste)    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Trouver le pod et le service Keycloak
POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
SERVICE=$(kubectl get svc -n security-iam -o json | jq -r '.items[] | select(.metadata.name | contains("keycloak")) | select(.spec.clusterIP != "None") | .metadata.name' | head -n1)

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    exit 1
fi

if [ -z "$SERVICE" ]; then
    SERVICE="keycloak-http"
fi

echo "✅ Pod:     $POD"
echo "✅ Service: $SERVICE"
echo ""

# 2. Configuration admin
ADMIN_USER="admin"
ADMIN_PASSWORD="admin123"

echo "🔐 Configuration:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo ""

read -p "Créer cet utilisateur admin ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

echo ""
echo "1️⃣  Test de connectivité à Keycloak..."

# Test si Keycloak répond
HTTP_CODE=$(kubectl exec -n security-iam $POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ --connect-timeout 5 || echo "000")

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "303" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "❌ Keycloak ne répond pas encore (HTTP $HTTP_CODE)"
    echo "⏳ Attendez quelques minutes que Keycloak démarre complètement"
    echo ""
    echo "Vérifier l'état:"
    echo "  kubectl logs -n security-iam $POD --tail=50"
    exit 1
fi

echo "✅ Keycloak répond (HTTP $HTTP_CODE)"
echo ""

# 3. Vérifier si un admin existe déjà
echo "2️⃣  Vérification si admin existe déjà..."

# Essayer de se connecter
TOKEN_RESPONSE=$(kubectl exec -n security-iam $POD -- curl -s \
    -d "client_id=admin-cli" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASSWORD" \
    -d "grant_type=password" \
    "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ L'admin existe déjà et fonctionne !"
    echo ""
    echo "🌐 Vous pouvez vous connecter avec:"
    echo "   URL:      https://keycloak.local.lab:8443/admin"
    echo "   Username: $ADMIN_USER"
    echo "   Password: $ADMIN_PASSWORD"
    exit 0
fi

echo "⚠️  Admin n'existe pas ou mot de passe incorrect"
echo ""

# 4. Créer l'admin via le endpoint /auth/admin/master/console/
echo "3️⃣  Création de l'utilisateur admin..."
echo ""

# Méthode : utiliser l'endpoint de création initial
# Cet endpoint est disponible uniquement si aucun admin n'existe

CREATE_RESPONSE=$(kubectl exec -n security-iam $POD -- curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\",\"passwordConfirmation\":\"$ADMIN_PASSWORD\"}" \
    "http://localhost:8080/auth/" 2>/dev/null || echo "")

echo "Réponse API: $CREATE_RESPONSE"

if echo "$CREATE_RESPONSE" | grep -q "local access"; then
    echo ""
    echo "⚠️  L'API nécessite un accès local (limitation Keycloak)"
    echo ""
    echo "📝 Solution de contournement: Utiliser kcadm.sh"
    echo ""

    # Utiliser kcadm.sh (Keycloak Admin CLI)
    echo "4️⃣  Tentative avec kcadm.sh..."
    echo ""

    # Configurer kcadm
    kubectl exec -n security-iam $POD -- /opt/jboss/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:8080/auth \
        --realm master \
        --user $ADMIN_USER \
        --password $ADMIN_PASSWORD 2>&1 || true

    # Si ça échoue (normal, admin n'existe pas), créer directement dans la DB
    echo ""
    echo "5️⃣  Création directe via add-user-keycloak.sh (dans le conteneur)..."
    echo ""

    kubectl exec -n security-iam $POD -- /opt/jboss/keycloak/bin/add-user-keycloak.sh \
        -r master \
        -u $ADMIN_USER \
        -p $ADMIN_PASSWORD

    echo ""
    echo "✅ Fichier de configuration créé"
    echo ""
    echo "⚠️  IMPORTANT: Le pod doit être redémarré pour lire cette configuration"
    echo ""

    read -p "Redémarrer le pod maintenant ? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "🔄 Redémarrage du pod..."
        kubectl delete pod $POD -n security-iam

        echo "⏳ Attente du nouveau pod (60 secondes)..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n security-iam --timeout=120s

        NEW_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
        echo "✅ Nouveau pod: $NEW_POD"

        echo ""
        echo "⏳ Attente du démarrage complet (60 secondes)..."
        sleep 60

        # Vérifier que l'admin fonctionne
        echo ""
        echo "6️⃣  Vérification de l'admin..."
        TOKEN_TEST=$(kubectl exec -n security-iam $NEW_POD -- curl -s \
            -d "client_id=admin-cli" \
            -d "username=$ADMIN_USER" \
            -d "password=$ADMIN_PASSWORD" \
            -d "grant_type=password" \
            "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

        if echo "$TOKEN_TEST" | grep -q "access_token"; then
            echo "✅ Admin créé avec succès !"
        else
            echo "⚠️  Admin non créé. Réponse: $TOKEN_TEST"
            echo ""
            echo "Vérifier les logs:"
            echo "  kubectl logs -n security-iam $NEW_POD --tail=100"
        fi
    fi
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ CONFIGURATION TERMINÉE                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔐 Credentials:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "🌐 URLs:"
echo "   Admin Console: https://keycloak.local.lab:8443/admin"
echo "   Welcome Page:  https://keycloak.local.lab:8443"
echo ""
echo "🔄 Rafraîchir votre navigateur:"
echo "   - Videz le cache: Ctrl+Shift+R"
echo "   - Ou navigation privée"
echo ""
