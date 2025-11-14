#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              Prometheus + Grafana Stack                  ║"
echo "║           Métriques + Visualisation + Alerting           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Créer le namespace si nécessaire
kubectl create namespace security-siem --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm
echo "📦 Configuration du repository Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Déployer Prometheus Stack (inclut Grafana)
echo ""
echo "📈 Déploiement de Prometheus + Grafana + Alertmanager..."
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
  --wait=false

echo ""
echo "⏳ Attente que les pods démarrent (5-10 min)..."
sleep 30
kubectl get pods -n security-siem -l release=prometheus

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ PROMETHEUS STACK DÉPLOYÉ (en cours)             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ⏳ Prometheus (métriques)"
echo "  ⏳ Grafana (visualisation)"
echo "  ⏳ Alertmanager (alertes)"
echo "  ⏳ Node Exporter (métriques nodes)"
echo "  ⏳ Kube State Metrics"
echo ""
echo "Accès aux dashboards :"
echo "  Grafana:"
echo "    kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "    http://localhost:3000 (admin/admin123)"
echo ""
echo "  Prometheus:"
echo "    kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "    http://localhost:9090"
echo ""
echo "  Alertmanager:"
echo "    kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-alertmanager 9093:9093"
echo "    http://localhost:9093"
echo ""
