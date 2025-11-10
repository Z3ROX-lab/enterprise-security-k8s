#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       ÉTAPE 2 : Monitoring (Elasticsearch + Prometheus)  ║"
echo "║       SANS KIBANA (utiliser Grafana à la place)          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster Kubernetes non accessible"
    echo "Exécutez d'abord : ./01-cluster.sh"
    exit 1
fi

# Créer le namespace
echo "📁 Création du namespace security-siem..."
kubectl create namespace security-siem --dry-run=client -o yaml | kubectl apply -f -

# Ajouter les repos Helm
echo ""
echo "📦 Configuration des repositories Helm..."
helm repo add elastic https://helm.elastic.co
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Déployer Elasticsearch
echo ""
echo "🔍 Déploiement d'Elasticsearch..."
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
  --wait

echo ""
echo "⏳ Attente qu'Elasticsearch soit Ready..."
kubectl wait --for=condition=Ready pod -l app=elasticsearch-master -n security-siem --timeout=600s

# Déployer Filebeat
echo ""
echo "📊 Déploiement de Filebeat (DaemonSet)..."
helm upgrade --install filebeat elastic/filebeat \
  --namespace security-siem \
  --version 8.5.1 \
  --set daemonset.enabled=true \
  --timeout 5m \
  --wait

# Déployer Prometheus Stack (avec Grafana)
echo ""
echo "📈 Déploiement de Prometheus + Grafana..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace security-siem \
  --version 55.0.0 \
  --set prometheus.prometheusSpec.resources.requests.memory=1Gi \
  --set prometheus.prometheusSpec.retention=7d \
  --set grafana.adminPassword=admin123 \
  --set grafana.persistence.enabled=false \
  --set grafana.defaultDashboardsEnabled=true \
  --set alertmanager.enabled=true \
  --timeout 10m \
  --wait

echo ""
echo "⏳ Attente que tous les pods soient Ready..."
kubectl wait --for=condition=Ready pod --all -n security-siem --timeout=600s

echo ""
echo "📊 État des pods :"
kubectl get pods -n security-siem

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ MONITORING DÉPLOYÉ AVEC SUCCÈS                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ✅ Elasticsearch (indexation des logs)"
echo "  ✅ Filebeat (collecte des logs)"
echo "  ✅ Prometheus (métriques)"
echo "  ✅ Grafana (visualisation)"
echo "  ✅ Alertmanager (alertes)"
echo ""
echo "Accès aux dashboards :"
echo "  Grafana: kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "           http://localhost:3000 (admin/admin123)"
echo ""
echo "  Prometheus: kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "              http://localhost:9090"
echo ""
echo "Prochaine étape :"
echo "  ./03-iam.sh"
echo ""
