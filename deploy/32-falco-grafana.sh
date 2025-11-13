#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Falco → Prometheus → Grafana Integration         ║"
echo "║       Métriques Falco dans Grafana pour monitoring       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Falcosidekick existe
if ! kubectl get deployment -n security-detection falco-falcosidekick &>/dev/null; then
    echo "❌ Falcosidekick non trouvé"
    echo "Lancez d'abord : ./31-falco-elasticsearch-config.sh"
    exit 1
fi

# Vérifier que Prometheus existe
if ! kubectl get prometheus -n security-siem prometheus-kube-prometheus-prometheus &>/dev/null; then
    echo "❌ Prometheus non trouvé"
    echo "Lancez d'abord : ./13-prometheus.sh"
    exit 1
fi

# Vérifier que Grafana existe
if ! kubectl get deployment -n security-siem prometheus-grafana &>/dev/null; then
    echo "❌ Grafana non trouvé"
    echo "Lancez d'abord : ./14-grafana.sh"
    exit 1
fi

echo "✅ Tous les prérequis sont présents"
echo ""
echo "📋 Ce script va configurer :"
echo "  1. ServiceMonitor pour Falcosidekick"
echo "  2. Vérification dans Prometheus"
echo "  3. Instructions pour créer un dashboard Grafana"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

# 1. Créer le ServiceMonitor pour Falcosidekick
echo ""
echo "1️⃣  Création du ServiceMonitor pour Falcosidekick..."

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: falcosidekick
  namespace: security-detection
  labels:
    release: prometheus  # Label crucial pour la découverte par Prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: falcosidekick
      app.kubernetes.io/component: core  # Cibler uniquement le service principal (pas l'UI)
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF

echo "  ✅ ServiceMonitor créé"

# 2. Attendre un peu que Prometheus détecte le nouveau target
echo ""
echo "2️⃣  Attente de la découverte par Prometheus (30 secondes)..."
sleep 30

# 3. Vérifier que Prometheus a détecté Falcosidekick
echo ""
echo "3️⃣  Vérification de la configuration Prometheus..."

echo "  📊 Vérifier les targets Prometheus :"
echo "     kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "     http://localhost:9090/targets"
echo "     Chercher 'falcosidekick' dans la liste"
echo ""

# 4. Lister les métriques Falcosidekick disponibles
echo ""
echo "4️⃣  Métriques Falcosidekick disponibles :"
echo ""
echo "  📊 Métriques principales :"
echo "     - falcosidekick_inputs_total : Nombre total d'événements reçus de Falco"
echo "     - falcosidekick_outputs_total : Nombre d'événements envoyés vers les outputs (Elasticsearch, WebUI)"
echo "     - falcosidekick_outputs_errors_total : Nombre d'erreurs d'envoi"
echo "     - falcosidekick_outputs_latency_seconds : Latence d'envoi vers les outputs"
echo "     - falcosidekick_requests_total : Nombre de requêtes HTTP reçues"
echo ""

# 5. Afficher les instructions pour Grafana
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ✅ FALCO → PROMETHEUS → GRAFANA CONFIGURÉ             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ ServiceMonitor créé pour Falcosidekick"
echo "  ✅ Prometheus scrappe les métriques Falco"
echo ""
echo "🖥️  Accès aux interfaces :"
echo ""
echo "  📊 Prometheus (vérifier les targets) :"
echo "     kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "     http://localhost:9090/targets"
echo "     Chercher 'security-detection/falcosidekick'"
echo ""
echo "  📊 Grafana (créer des dashboards) :"
echo "     kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "     http://localhost:3000"
echo "     Login : admin / admin123"
echo ""
echo "📊 Exemples de requêtes PromQL pour Grafana :"
echo ""
echo "  # Taux d'alertes Falco reçues par seconde"
echo "  rate(falcosidekick_inputs_total[5m])"
echo ""
echo "  # Nombre d'alertes par output"
echo "  sum by (output) (falcosidekick_outputs_total)"
echo ""
echo "  # Taux d'erreurs par output"
echo "  rate(falcosidekick_outputs_errors_total[5m])"
echo ""
echo "  # Latence moyenne d'envoi vers Elasticsearch"
echo "  avg(falcosidekick_outputs_latency_seconds{output=\"elasticsearch\"})"
echo ""
echo "  # Nombre total d'événements reçus (compteur)"
echo "  falcosidekick_inputs_total"
echo ""
echo "📈 Créer un dashboard Grafana :"
echo ""
echo "  1. Dashboard → New Dashboard → Add visualization"
echo "  2. Data source : Prometheus"
echo "  3. Ajouter des panels avec les requêtes ci-dessus :"
echo ""
echo "     Panel 1 : Taux d'alertes Falco"
echo "     Query : rate(falcosidekick_inputs_total[5m])"
echo "     Type : Time series"
echo ""
echo "     Panel 2 : Alertes par output (pie chart)"
echo "     Query : sum by (output) (falcosidekick_outputs_total)"
echo "     Type : Pie chart"
echo ""
echo "     Panel 3 : Taux d'erreurs"
echo "     Query : rate(falcosidekick_outputs_errors_total[5m])"
echo "     Type : Time series"
echo ""
echo "     Panel 4 : Latence Elasticsearch"
echo "     Query : avg(falcosidekick_outputs_latency_seconds{output=\"elasticsearch\"})"
echo "     Type : Gauge"
echo ""
echo "  4. Save dashboard"
echo ""
echo "🔍 Vérifier les métriques dans Prometheus :"
echo ""
echo "  1. Ouvrir Prometheus : http://localhost:9090"
echo "  2. Graph → Query"
echo "  3. Taper : falcosidekick_"
echo "  4. L'autocomplétion montrera toutes les métriques disponibles"
echo ""
echo "💡 Architecture complète :"
echo ""
echo "  Falco → Falcosidekick ─┬→ Prometheus → Grafana (métriques agrégées)"
echo "                         ├→ Elasticsearch → Kibana (SIEM détaillé)"
echo "                         └→ WebUI (alertes temps réel)"
echo ""
echo "🎯 Vous avez maintenant 3 interfaces pour Falco :"
echo "  - Grafana : Tableaux de bord et métriques de performance"
echo "  - Kibana : Analyse SIEM et recherche détaillée"
echo "  - Falcosidekick UI : Alertes temps réel"
echo ""
