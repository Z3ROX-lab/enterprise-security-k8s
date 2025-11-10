#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              OPTIONNEL : Wazuh HIDS                       ║"
echo "║         (Nécessite 8GB RAM + 4 CPU minimum)              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  Wazuh est gourmand en ressources :"
echo "   - Manager : 2-4 GB RAM"
echo "   - Indexer : 2-4 GB RAM"
echo "   - Dashboard : 1 GB RAM"
echo "   Total : ~8 GB RAM minimum"
echo ""

# Vérifier les ressources disponibles
echo "📊 Ressources disponibles :"
free -h | grep "Mem:"
echo ""

read -p "Voulez-vous installer Wazuh ? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# Créer le namespace
echo "📁 Création du namespace security-detection..."
kubectl create namespace security-detection --dry-run=client -o yaml | kubectl apply -f -

# Cloner le repo Wazuh
echo ""
echo "📥 Téléchargement des manifests Wazuh..."
WAZUH_REPO="/tmp/wazuh-kubernetes"
if [ ! -d "$WAZUH_REPO" ]; then
    git clone --depth 1 https://github.com/wazuh/wazuh-kubernetes.git $WAZUH_REPO
else
    echo "  ✅ Repository déjà cloné"
    cd $WAZUH_REPO && git pull
fi

# Déployer Wazuh
echo ""
echo "🛡️  Déploiement de Wazuh (cela peut prendre 10-15 minutes)..."
kubectl apply -k $WAZUH_REPO/deployments/kubernetes/ -n security-detection

echo ""
echo "⏳ Attente du démarrage des pods (10-15 min)..."
echo "   Surveillance en temps réel..."
echo ""

for i in {1..30}; do
    echo "─────── Check $i/30 ───────"
    kubectl get pods -n security-detection | grep wazuh || echo "  Pas encore de pods Wazuh"
    echo ""

    # Vérifier si tous sont Running
    RUNNING=$(kubectl get pods -n security-detection -l app=wazuh -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l || echo "0")
    TOTAL=$(kubectl get pods -n security-detection -l app=wazuh --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$TOTAL" -gt 0 ] && [ "$RUNNING" -eq "$TOTAL" ]; then
        echo "✅ Tous les pods Wazuh sont Running !"
        break
    fi

    if [ $i -lt 30 ]; then
        sleep 30
    fi
done

echo ""
echo "📊 État final des pods :"
kubectl get pods -n security-detection

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            ✅ WAZUH DÉPLOYÉ (vérifiez l'état)             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  - wazuh-manager (HIDS manager)"
echo "  - wazuh-indexer (base de données)"
echo "  - wazuh-dashboard (WebUI)"
echo ""
echo "Accès au dashboard :"
echo "  kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:443"
echo "  https://localhost:5443 (admin/SecretPassword)"
echo ""
echo "Vérifier les agents :"
echo "  kubectl exec -n security-detection wazuh-manager-master-0 -- /var/ossec/bin/agent_control -l"
echo ""
