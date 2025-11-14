#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Créer l'Admin Keycloak via add-user script          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Trouver le pod Keycloak
POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    kubectl get pods -n security-iam
    exit 1
fi

echo "✅ Pod Keycloak trouvé: $POD"
echo ""

# 2. Récupérer le mot de passe du secret
ADMIN_PASSWORD=$(kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d || echo "admin123")

echo "🔐 Configuration:"
echo "   Username: admin"
echo "   Password: $ADMIN_PASSWORD"
echo ""

read -p "Créer cet utilisateur admin ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# 3. Exécuter le script add-user-keycloak.sh dans le pod
echo ""
echo "1️⃣  Exécution du script add-user-keycloak.sh..."
echo ""

kubectl exec -n security-iam $POD -- /opt/jboss/keycloak/bin/add-user-keycloak.sh \
    -r master \
    -u admin \
    -p "$ADMIN_PASSWORD"

echo ""
echo "✅ Utilisateur admin ajouté"
echo ""

# 4. Redémarrer Keycloak pour appliquer
echo "2️⃣  Redémarrage de Keycloak pour appliquer les changements..."
echo ""

kubectl delete pod $POD -n security-iam

echo "✅ Pod en cours de redémarrage..."
echo ""

# 5. Attendre que le nouveau pod soit prêt
echo "3️⃣  Attente du nouveau pod (30-60 secondes)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n security-iam --timeout=120s || echo "⚠️  Timeout, vérifier manuellement"

# 6. Obtenir le nouveau pod
NEW_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "✅ Nouveau pod prêt: $NEW_POD"
echo ""

# 7. Attendre quelques secondes supplémentaires
echo "4️⃣  Attente du démarrage complet de Keycloak (30 secondes)..."
sleep 30

# 8. Vérifier les logs
echo ""
echo "5️⃣  Vérification des logs..."
echo ""

kubectl logs -n security-iam $NEW_POD --tail=20 | grep -E "(Added|master realm|WFLYSRV0025)" || echo "Keycloak en cours de démarrage..."

# Résumé final
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ ADMIN KEYCLOAK CRÉÉ                            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔐 Credentials:"
echo "   Username: admin"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "🌐 URLs d'accès:"
echo "   Admin Console: https://keycloak.local.lab:8443/admin"
echo "   Page d'accueil: https://keycloak.local.lab:8443"
echo ""
echo "⏳ Attendre 1-2 minutes pour que Keycloak finalise le démarrage"
echo ""
echo "🔄 Puis rafraîchir la page dans votre navigateur:"
echo "   - Videz le cache (Ctrl+Shift+R)"
echo "   - Ou ouvrez en navigation privée"
echo ""
echo "🔍 Si le problème persiste, vérifier les logs:"
echo "   kubectl logs -n security-iam $NEW_POD --tail=100"
echo ""
