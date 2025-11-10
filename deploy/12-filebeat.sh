#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                       Filebeat                            ║"
echo "║              Collecteur de Logs (DaemonSet)              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier qu'Elasticsearch existe
if ! kubectl get deployment elasticsearch-master -n security-siem &>/dev/null; then
    echo "❌ Elasticsearch non trouvé"
    echo "Lancez d'abord : ./10-elasticsearch.sh"
    exit 1
fi

# Ajouter le repo Helm
echo "📦 Configuration du repository Helm..."
helm repo add elastic https://helm.elastic.co
helm repo update

# Déployer Filebeat
echo ""
echo "📊 Déploiement de Filebeat 8.5.1 (DaemonSet)..."
helm upgrade --install filebeat elastic/filebeat \
  --namespace security-siem \
  --version 8.5.1 \
  --set daemonset.enabled=true \
  --timeout 5m \
  --wait=false

echo ""
echo "⏳ Attente que Filebeat démarre..."
sleep 20
kubectl get pods -n security-siem -l app=filebeat

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║               ✅ FILEBEAT DÉPLOYÉ                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Service déployé :"
echo "  ✅ Filebeat DaemonSet (1 pod par nœud)"
echo ""
echo "Vérifier les logs collectés :"
echo "  kubectl logs -n security-siem -l app=filebeat --tail=50"
echo ""
