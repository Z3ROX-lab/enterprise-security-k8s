#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Activer la Persistence PostgreSQL (CRITIQUE!)         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Problème actuel:"
echo "   ❌ PostgreSQL n'a PAS de PVC"
echo "   ❌ Toutes vos données (users, realms) sont en RAM"
echo "   ❌ Si PostgreSQL redémarre = TOUT PERDU"
echo ""
echo "✅ Solution: Ajouter un PVC à PostgreSQL"
echo ""

read -p "Voulez-vous activer la persistence PostgreSQL maintenant ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

echo ""
echo "1️⃣  Vérification de l'état actuel..."
echo ""

# Vérifier si PostgreSQL existe
if ! kubectl get statefulset keycloak-postgresql -n security-iam &>/dev/null; then
    echo "❌ PostgreSQL n'est pas déployé !"
    echo "   Lancez d'abord: ./deploy/21-keycloak.sh"
    exit 1
fi

echo "✅ PostgreSQL trouvé"

# Vérifier si des PVC existent déjà
EXISTING_PVC=$(kubectl get pvc -n security-iam -l app.kubernetes.io/name=postgresql --no-headers 2>/dev/null | wc -l)

if [ "$EXISTING_PVC" -gt 0 ]; then
    echo "✅ Des PVC PostgreSQL existent déjà:"
    kubectl get pvc -n security-iam -l app.kubernetes.io/name=postgresql
    echo ""
    read -p "⚠️  Voulez-vous reconfigurer quand même ? Les données existantes seront préservées (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Opération annulée."
        exit 0
    fi
fi

echo ""
echo "2️⃣  Mise à jour de PostgreSQL avec persistence..."
echo ""

# Redéployer PostgreSQL avec persistence activée
helm upgrade keycloak-postgresql bitnami/postgresql \
  --namespace security-iam \
  --reuse-values \
  --set primary.persistence.enabled=true \
  --set primary.persistence.size=10Gi \
  --set primary.persistence.storageClass=standard \
  --wait

echo ""
echo "✅ PostgreSQL mis à jour avec persistence"
echo ""

# Attendre que PostgreSQL redémarre
echo "3️⃣  Attente du redémarrage de PostgreSQL..."
kubectl rollout status statefulset/keycloak-postgresql -n security-iam --timeout=5m

echo ""
echo "✅ PostgreSQL redémarré"
echo ""

# Vérifier les PVC
echo "4️⃣  Vérification des PVC créés..."
echo ""
kubectl get pvc -n security-iam -l app.kubernetes.io/name=postgresql

echo ""

# Vérifier le montage dans le pod
PG_POD=$(kubectl get pod -n security-iam -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')

if [ -n "$PG_POD" ]; then
    echo "5️⃣  Vérification du montage dans le pod PostgreSQL..."
    echo ""
    echo "Volume monté sur /bitnami/postgresql:"
    kubectl exec -n security-iam "$PG_POD" -- df -h /bitnami/postgresql | tail -1
    echo ""
fi

# Redémarrer Keycloak pour re-synchroniser
echo "6️⃣  Redémarrage de Keycloak pour reconnexion..."
kubectl rollout restart statefulset/keycloak -n security-iam || \
kubectl delete pod -n security-iam -l app.kubernetes.io/name=keycloak

echo "⏳ Attente du redémarrage de Keycloak..."
sleep 30

kubectl wait --for=condition=ready pod -n security-iam -l app.kubernetes.io/name=keycloak --timeout=180s || true

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ PERSISTENCE POSTGRESQL ACTIVÉE !                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 Maintenant vos données sont PERSISTANTES !"
echo ""
echo "📊 Architecture finale:"
echo "   Keycloak → PostgreSQL → PVC 10Gi"
echo "   └─ Les users/realms survivent aux redémarrages"
echo ""
echo "🧪 Test recommandé:"
echo "   1. Créez un user dans Keycloak"
echo "   2. kubectl delete pod -n security-iam \$PG_POD"
echo "   3. Vérifiez que le user existe toujours"
echo ""
echo "📋 Vérifications:"
echo "   kubectl get pvc -n security-iam"
echo "   kubectl describe pvc -n security-iam data-keycloak-postgresql-0"
echo ""
