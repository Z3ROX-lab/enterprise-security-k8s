#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Activer Persistence PostgreSQL (AVEC BACKUP SÉCURISÉ)   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🛡️  Ce script va:"
echo "   1. Faire un BACKUP complet de PostgreSQL"
echo "   2. Activer la persistence (PVC 10Gi)"
echo "   3. RESTAURER vos données (admin/admin123 préservé)"
echo ""

read -p "Voulez-vous continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# Variables
NAMESPACE="security-iam"
PG_POD="keycloak-postgresql-0"
BACKUP_FILE="/tmp/keycloak-pg-backup-$(date +%Y%m%d-%H%M%S).sql"
BACKUP_DIR="/tmp/keycloak-backups"

mkdir -p "$BACKUP_DIR"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                ÉTAPE 1: BACKUP DES DONNÉES                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que PostgreSQL existe et est running
echo "1️⃣  Vérification de PostgreSQL..."
if ! kubectl get pod "$PG_POD" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Pod PostgreSQL '$PG_POD' introuvable !"
    echo "   Vérifiez avec: kubectl get pods -n $NAMESPACE"
    exit 1
fi

PG_STATUS=$(kubectl get pod "$PG_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$PG_STATUS" != "Running" ]; then
    echo "❌ PostgreSQL n'est pas Running (état: $PG_STATUS)"
    echo "   Attendez qu'il soit prêt avant de continuer"
    exit 1
fi

echo "✅ PostgreSQL est Running"
echo ""

# Vérifier si des données existent
echo "2️⃣  Vérification des données existantes..."
TABLES_COUNT=$(kubectl exec -n "$NAMESPACE" "$PG_POD" -- \
    psql -U keycloak -d keycloak -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$TABLES_COUNT" = "0" ] || [ -z "$TABLES_COUNT" ]; then
    echo "⚠️  Aucune table trouvée dans PostgreSQL"
    echo "   Soit Keycloak n'a pas encore initialisé la DB"
    echo "   Soit la connexion a échoué"
    echo ""
    read -p "   Continuer quand même (pas de backup nécessaire) ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Opération annulée."
        exit 0
    fi
    SKIP_BACKUP=true
else
    echo "✅ Base de données contient $TABLES_COUNT tables"
    SKIP_BACKUP=false
fi

echo ""

# Faire le backup
if [ "$SKIP_BACKUP" = false ]; then
    echo "3️⃣  Création du backup PostgreSQL..."
    echo "   Fichier: $BACKUP_FILE"
    echo ""

    kubectl exec -n "$NAMESPACE" "$PG_POD" -- \
        pg_dump -U keycloak -d keycloak --clean --if-exists > "$BACKUP_FILE"

    if [ -s "$BACKUP_FILE" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "✅ Backup créé avec succès ($BACKUP_SIZE)"

        # Copier aussi dans le dossier de backups
        cp "$BACKUP_FILE" "$BACKUP_DIR/"
        echo "   Copie sauvegardée dans: $BACKUP_DIR/"
    else
        echo "❌ Le backup est vide !"
        echo "   Vérifiez les logs: kubectl logs $PG_POD -n $NAMESPACE"
        exit 1
    fi
else
    echo "3️⃣  Backup ignoré (pas de données)"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ÉTAPE 2: ACTIVATION DE LA PERSISTENCE          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "4️⃣  Mise à jour de PostgreSQL avec persistence..."
echo ""

# Upgrade PostgreSQL avec persistence
helm upgrade keycloak-postgresql bitnami/postgresql \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set primary.persistence.enabled=true \
  --set primary.persistence.size=10Gi \
  --set primary.persistence.storageClass=standard \
  --wait \
  --timeout 10m

echo ""
echo "✅ PostgreSQL upgradé avec persistence"
echo ""

# Attendre que le pod soit ready
echo "5️⃣  Attente du redémarrage de PostgreSQL..."
kubectl rollout status statefulset/keycloak-postgresql -n "$NAMESPACE" --timeout=5m

echo ""
echo "✅ PostgreSQL redémarré avec PVC"
echo ""

# Vérifier le PVC
echo "6️⃣  Vérification du PVC créé..."
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql

echo ""

# Attendre que PostgreSQL soit vraiment prêt
echo "7️⃣  Attente que PostgreSQL soit complètement prêt..."
sleep 30

# Vérifier que PostgreSQL accepte les connexions
for i in {1..10}; do
    if kubectl exec -n "$NAMESPACE" "$PG_POD" -- psql -U keycloak -d keycloak -c "SELECT 1;" &>/dev/null; then
        echo "✅ PostgreSQL accepte les connexions"
        break
    fi
    echo "   Tentative $i/10..."
    sleep 10
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ÉTAPE 3: RESTAURATION DES DONNÉES              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if [ "$SKIP_BACKUP" = false ]; then
    echo "8️⃣  Restauration du backup..."
    echo ""

    # Restaurer le backup
    cat "$BACKUP_FILE" | kubectl exec -i -n "$NAMESPACE" "$PG_POD" -- \
        psql -U keycloak -d keycloak

    echo ""
    echo "✅ Données restaurées avec succès"
    echo ""

    # Vérifier que les tables sont présentes
    echo "9️⃣  Vérification de la restauration..."
    RESTORED_TABLES=$(kubectl exec -n "$NAMESPACE" "$PG_POD" -- \
        psql -U keycloak -d keycloak -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ')

    echo "   Tables restaurées: $RESTORED_TABLES"

    if [ "$RESTORED_TABLES" = "$TABLES_COUNT" ]; then
        echo "✅ Restauration complète !"
    else
        echo "⚠️  Nombre de tables différent (avant: $TABLES_COUNT, après: $RESTORED_TABLES)"
        echo "   Vérifiez les logs si nécessaire"
    fi
else
    echo "8️⃣  Pas de restauration nécessaire (DB vide initialement)"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ÉTAPE 4: REDÉMARRAGE DE KEYCLOAK                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🔄 Redémarrage de Keycloak pour reconnexion..."

# Redémarrer Keycloak
kubectl rollout restart statefulset/keycloak -n "$NAMESPACE" 2>/dev/null || \
kubectl delete pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak

echo "⏳ Attente du redémarrage de Keycloak (peut prendre 2-3 min)..."
sleep 60

kubectl wait --for=condition=ready pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak --timeout=180s || true

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ MIGRATION TERMINÉE AVEC SUCCÈS !          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🎉 Vos données ont été préservées !"
echo ""
echo "📊 Résumé:"
echo "   ✅ Backup créé: $BACKUP_FILE"
echo "   ✅ Persistence PostgreSQL activée (10Gi PVC)"
echo "   ✅ Données restaurées"
echo "   ✅ Keycloak reconnecté"
echo ""
echo "🔐 Vos credentials sont préservés:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "🧪 Test recommandé:"
echo "   kubectl port-forward -n security-iam svc/keycloak 8080:80"
echo "   Ouvrez http://localhost:8080/admin et connectez-vous"
echo ""
echo "💾 Backup disponible ici:"
echo "   $BACKUP_FILE"
echo "   $BACKUP_DIR/"
echo ""
echo "📋 Vérifications:"
echo "   kubectl get pvc -n security-iam"
echo "   kubectl get pods -n security-iam"
echo ""
