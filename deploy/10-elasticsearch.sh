#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Elasticsearch                          ║"
echo "║              Stockage et Indexation des Logs             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier le cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster non accessible. Lancez d'abord : ./01-cluster-kind.sh"
    exit 1
fi

# Créer le namespace
echo "📁 Création du namespace security-siem..."
kubectl create namespace security-siem --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm
echo ""
echo "📦 Configuration du repository Helm..."
helm repo add elastic https://helm.elastic.co
helm repo update

# Déployer Elasticsearch
echo ""
echo "🔍 Déploiement d'Elasticsearch 8.5.1..."
helm upgrade --install elasticsearch elastic/elasticsearch \
  --namespace security-siem \
  --version 8.5.1 \
  --set replicas=1 \
  --set minimumMasterNodes=1 \
  --set resources.requests.memory=2Gi \
  --set resources.limits.memory=4Gi \
  --set persistence.enabled=false \
  --set esJavaOpts="-Xmx2g -Xms2g" \
  --timeout 10m \
  --wait=false

echo ""
echo "⏳ Attente qu'Elasticsearch démarre (peut prendre 5-10 min)..."
for i in {1..20}; do
    if kubectl get pod -n security-siem -l app=elasticsearch-master --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✅ Elasticsearch est Running !"
        break
    fi
    echo "  Check $i/20 - En attente..."
    sleep 30
done

echo ""
echo "📊 État des pods :"
kubectl get pods -n security-siem

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ ELASTICSEARCH DÉPLOYÉ                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Service déployé :"
echo "  ✅ Elasticsearch 8.5.1 (single node)"
echo ""
echo "Test de connexion :"
echo "  kubectl port-forward -n security-siem svc/elasticsearch-master 9200:9200"
echo "  curl http://localhost:9200"
echo ""
echo "Scripts dépendants :"
echo "  ./11-kibana.sh       - Dashboard de visualisation"
echo "  ./12-filebeat.sh     - Collecteur de logs"
echo ""
