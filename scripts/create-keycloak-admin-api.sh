#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Créer Admin Keycloak via CLI (kcadm.sh)              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

POD=$(kubectl get pods -n security-iam | grep keycloak | grep Running | head -n1 | awk '{print $1}')

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    exit 1
fi

ADMIN_USER="admin"
ADMIN_PASSWORD="admin123"

echo "✅ Pod Keycloak: $POD"
echo ""
echo "🔐 Configuration admin:"
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
echo "1️⃣  Vérification que Keycloak est prêt..."
echo ""

# Attendre que Keycloak soit prêt
for i in {1..10}; do
    HTTP_CODE=$(kubectl exec -n security-iam $POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/ --connect-timeout 3 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "✅ Keycloak est prêt (HTTP $HTTP_CODE)"
        break
    fi

    if [ $i -eq 10 ]; then
        echo "❌ Keycloak ne répond pas (HTTP $HTTP_CODE)"
        exit 1
    fi

    echo "   Tentative $i/10: HTTP $HTTP_CODE - Attente 3s..."
    sleep 3
done

echo ""
echo "2️⃣  Création de l'admin via kcadm.sh..."
echo ""

# Utiliser kcadm.sh pour créer l'admin
# Cette commande crée l'admin s'il n'existe pas
kubectl exec -n security-iam $POD -- bash -c "
    set -e

    # Créer l'utilisateur admin dans le realm master
    /opt/jboss/keycloak/bin/kcadm.sh create users \
        -r master \
        -s username=$ADMIN_USER \
        -s enabled=true \
        --server http://localhost:8080/auth \
        --realm master \
        --no-config 2>&1 || {
            echo 'Utilisateur existe peut-être déjà, tentative de mise à jour...'
        }

    # Récupérer l'ID de l'utilisateur
    USER_ID=\$(/opt/jboss/keycloak/bin/kcadm.sh get users \
        -r master \
        -q username=$ADMIN_USER \
        --fields id \
        --format csv \
        --noquotes \
        --server http://localhost:8080/auth \
        --realm master \
        --no-config | tail -n1)

    if [ -z \"\$USER_ID\" ]; then
        echo 'Erreur: Impossible de trouver l utilisateur'
        exit 1
    fi

    echo \"ID utilisateur: \$USER_ID\"

    # Définir le mot de passe
    /opt/jboss/keycloak/bin/kcadm.sh set-password \
        -r master \
        --userid \$USER_ID \
        --new-password $ADMIN_PASSWORD \
        --server http://localhost:8080/auth \
        --realm master \
        --no-config

    # Ajouter les rôles admin
    /opt/jboss/keycloak/bin/kcadm.sh add-roles \
        -r master \
        --uid \$USER_ID \
        --rolename admin \
        --server http://localhost:8080/auth \
        --realm master \
        --no-config 2>&1 || echo 'Rôle déjà assigné'

    echo 'Utilisateur admin créé avec succès'
" 2>&1 | tee /tmp/keycloak-admin-creation.log

RESULT=$?

echo ""
if [ $RESULT -eq 0 ]; then
    echo "✅ Admin créé avec succès"
else
    echo "⚠️  Erreur lors de la création (voir logs ci-dessus)"
    echo ""
    echo "Tentative alternative avec add-user-keycloak.sh..."

    # Méthode de fallback
    kubectl exec -n security-iam $POD -- /opt/jboss/keycloak/bin/add-user-keycloak.sh \
        -r master \
        -u $ADMIN_USER \
        -p $ADMIN_PASSWORD

    echo ""
    echo "⚠️  add-user-keycloak.sh exécuté"
    echo "    Keycloak doit être redémarré pour lire ce fichier"
    echo ""
    read -p "Redémarrer le pod maintenant ? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete pod $POD -n security-iam
        echo "Pod en cours de redémarrage..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n security-iam --timeout=120s 2>/dev/null || \
        kubectl wait --for=condition=ready pod -l app=keycloak -n security-iam --timeout=120s 2>/dev/null || true
    fi
fi

echo ""
echo "3️⃣  Vérification de l'authentification..."
echo ""

sleep 5

# Tester l'authentification
TOKEN_RESPONSE=$(kubectl exec -n security-iam $POD -- curl -s \
    -d "client_id=admin-cli" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASSWORD" \
    -d "grant_type=password" \
    "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ Authentification réussie !"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         ✅ ADMIN KEYCLOAK CRÉÉ ET FONCTIONNEL             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
else
    echo "⚠️  Authentification échouée"
    echo ""
    echo "Réponse:"
    echo "$TOKEN_RESPONSE"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      ⚠️  ADMIN CRÉÉ MAIS AUTHENTIFICATION ÉCHOUE          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
fi

echo ""
echo "🔐 Credentials:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "🌐 URLs:"
echo "   Admin Console: https://keycloak.local.lab:8443/auth/admin/"
echo ""
echo "🔄 Testez maintenant dans le navigateur:"
echo "   1. Videz le cache: Ctrl+Shift+R"
echo "   2. Allez sur: https://keycloak.local.lab:8443/auth/admin/"
echo "   3. Connectez-vous avec admin / admin123"
echo ""
