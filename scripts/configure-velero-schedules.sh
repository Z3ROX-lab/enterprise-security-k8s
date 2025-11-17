#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Configuration des Backups Automatiques Velero       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Velero est installé
if ! command -v velero &> /dev/null; then
    echo "❌ Velero CLI n'est pas installé"
    echo "   Lancez d'abord: ./scripts/deploy-velero.sh"
    exit 1
fi

if ! kubectl get namespace velero &>/dev/null; then
    echo "❌ Velero n'est pas déployé dans le cluster"
    echo "   Lancez d'abord: ./scripts/deploy-velero.sh"
    exit 1
fi

echo "✅ Velero est installé"
echo ""

echo "📋 Configuration des schedules de backup:"
echo ""
echo "   1. Backup quotidien complet (tous les namespaces)"
echo "      - Fréquence: Tous les jours à 2h00"
echo "      - Rétention: 7 jours"
echo ""
echo "   2. Backup horaire des données critiques"
echo "      - Namespaces: security-iam, security-siem"
echo "      - Fréquence: Toutes les heures"
echo "      - Rétention: 24 heures"
echo ""
echo "   3. Backup hebdomadaire archivage"
echo "      - Fréquence: Tous les dimanches à 3h00"
echo "      - Rétention: 30 jours"
echo ""

read -p "Créer ces schedules de backup ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "🗓️  Création du backup quotidien complet..."
velero schedule create daily-full-backup \
    --schedule="0 2 * * *" \
    --ttl 168h0m0s \
    --include-namespaces "*" \
    --exclude-namespaces "kube-system,kube-public,kube-node-lease" \
    --snapshot-volumes=false

echo "   ✅ Schedule 'daily-full-backup' créé"

echo ""
echo "⏰ Création du backup horaire des données critiques..."
velero schedule create hourly-critical-backup \
    --schedule="0 * * * *" \
    --ttl 24h0m0s \
    --include-namespaces security-iam,security-siem,security-detection \
    --snapshot-volumes=false

echo "   ✅ Schedule 'hourly-critical-backup' créé"

echo ""
echo "📅 Création du backup hebdomadaire archivage..."
velero schedule create weekly-archive-backup \
    --schedule="0 3 * * 0" \
    --ttl 720h0m0s \
    --include-namespaces "*" \
    --exclude-namespaces "kube-system,kube-public,kube-node-lease" \
    --snapshot-volumes=false

echo "   ✅ Schedule 'weekly-archive-backup' créé"

echo ""
echo "📊 Schedules configurés:"
velero schedule get

echo ""
echo "✅ Configuration terminée !"
echo ""
echo "📝 Informations schedules:"
echo ""
echo "   📌 daily-full-backup"
echo "      Prochaine exécution: Demain à 02:00"
echo "      Rétention: 7 jours"
echo ""
echo "   📌 hourly-critical-backup"
echo "      Prochaine exécution: Dans 1 heure"
echo "      Rétention: 24 heures"
echo ""
echo "   📌 weekly-archive-backup"
echo "      Prochaine exécution: Dimanche prochain à 03:00"
echo "      Rétention: 30 jours"
echo ""
echo "🧪 Commandes utiles:"
echo ""
echo "   # Lister tous les schedules"
echo "   velero schedule get"
echo ""
echo "   # Déclencher manuellement un schedule"
echo "   velero backup create --from-schedule daily-full-backup"
echo ""
echo "   # Voir les backups créés par un schedule"
echo "   velero backup get -l velero.io/schedule-name=daily-full-backup"
echo ""
echo "   # Suspendre un schedule"
echo "   velero schedule pause daily-full-backup"
echo ""
echo "   # Reprendre un schedule"
echo "   velero schedule unpause daily-full-backup"
echo ""
echo "   # Supprimer un schedule"
echo "   velero schedule delete daily-full-backup"
echo ""
echo "🔍 Vérifier les backups:"
echo "   velero backup get"
echo ""
