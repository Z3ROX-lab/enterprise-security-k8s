#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Fix ServiceMonitor Falco → Prometheus               ║"
echo "║   Corriger la cible pour le bon service                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script va :"
echo "  1. Analyser les services Falcosidekick existants"
echo "  2. Supprimer l'ancien ServiceMonitor"
echo "  3. Créer un nouveau ServiceMonitor ciblant uniquement le service principal"
echo ""

# 1. Analyser les services
echo ""
echo "1️⃣  Analyse des services dans security-detection..."
echo ""
echo "Services Falco :"
kubectl get svc -n security-detection | grep falco || echo "Aucun service trouvé"
echo ""

# Déterminer le service principal (celui qui a les métriques)
echo "Détection du service avec /metrics..."
MAIN_SERVICE=""
UI_SERVICE=""

# Liste des services falco
SERVICES=$(kubectl get svc -n security-detection -o name | grep falco || true)

for svc in $SERVICES; do
    SVC_NAME=$(echo $svc | cut -d'/' -f2)
    if [[ "$SVC_NAME" == *"-ui"* ]]; then
        UI_SERVICE="$SVC_NAME"
        echo "  Service UI trouvé: $UI_SERVICE"
    else
        if [[ "$SVC_NAME" == *"falcosidekick"* ]]; then
            MAIN_SERVICE="$SVC_NAME"
            echo "  Service principal trouvé: $MAIN_SERVICE"
        fi
    fi
done

if [ -z "$MAIN_SERVICE" ]; then
    echo "❌ Service Falcosidekick principal non trouvé"
    echo "Services disponibles :"
    kubectl get svc -n security-detection
    exit 1
fi

echo ""
echo "✅ Service cible identifié : $MAIN_SERVICE"
echo ""

read -p "Continuer avec la correction ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Correction annulée."
    exit 0
fi

# 2. Récupérer les labels du service principal
echo ""
echo "2️⃣  Récupération des labels du service $MAIN_SERVICE..."

# Obtenir le label app.kubernetes.io/name du service
SERVICE_LABEL=$(kubectl get svc -n security-detection $MAIN_SERVICE -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}' 2>/dev/null || echo "")
APP_LABEL=$(kubectl get svc -n security-detection $MAIN_SERVICE -o jsonpath='{.metadata.labels.app}' 2>/dev/null || echo "")

echo "  Labels trouvés :"
echo "    app.kubernetes.io/name: $SERVICE_LABEL"
echo "    app: $APP_LABEL"

# 3. Supprimer les anciens ServiceMonitors
echo ""
echo "3️⃣  Suppression des anciens ServiceMonitors..."
kubectl delete servicemonitor falcosidekick -n security-detection --ignore-not-found=true
kubectl delete servicemonitor falcosidekick-metrics -n security-detection --ignore-not-found=true
echo "  ✅ Anciens ServiceMonitors supprimés"

# 4. Créer le nouveau ServiceMonitor avec les bons labels
echo ""
echo "4️⃣  Création du nouveau ServiceMonitor..."

# Déterminer quels labels utiliser
if [ -n "$SERVICE_LABEL" ]; then
    echo "  Utilisation du label app.kubernetes.io/name=$SERVICE_LABEL"
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
      app.kubernetes.io/name: $SERVICE_LABEL
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF
elif [ -n "$APP_LABEL" ]; then
    echo "  Utilisation du label app=$APP_LABEL"
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: falcosidekick
  namespace: security-detection
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: $APP_LABEL
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF
else
    echo "  ⚠️  Aucun label standard trouvé, utilisation du nom de service direct"
    # Fallback : utiliser une expression qui matche uniquement le service principal
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: falcosidekick
  namespace: security-detection
  labels:
    release: prometheus
spec:
  selector:
    matchExpressions:
    - key: app.kubernetes.io/name
      operator: NotIn
      values: ["falcosidekick-ui", "ui"]  # Exclure explicitement le UI
  namespaceSelector:
    matchNames:
    - security-detection
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF
fi

echo "  ✅ Nouveau ServiceMonitor créé"

# 5. Attendre que Prometheus redécouvre les targets
echo ""
echo "5️⃣  Attente de la redécouverte par Prometheus (30 secondes)..."
sleep 30

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       ✅ SERVICEMONITORS CORRIGÉS                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔍 Vérifier les targets Prometheus :"
echo "   kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "   http://localhost:9090/targets"
echo "   Chercher 'security-detection/falcosidekick'"
echo ""
echo "📊 Debug des services et labels :"
echo "   kubectl get svc -n security-detection -o yaml | grep -A 10 'kind: Service'"
echo "   kubectl get servicemonitor -n security-detection -o yaml"
echo ""
echo "🧪 Tester l'endpoint /metrics manuellement :"
echo "   kubectl port-forward -n security-detection svc/falco-falcosidekick 2801:2801"
echo "   curl http://localhost:2801/metrics | grep falcosidekick_"
echo ""
