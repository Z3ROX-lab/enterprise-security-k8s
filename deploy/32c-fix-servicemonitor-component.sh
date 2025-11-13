#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Fix ServiceMonitor - Cibler uniquement le service core ║"
echo "║   Utiliser le label app.kubernetes.io/component=core     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🔍 Analyse du problème :"
echo "  Les deux services partagent le label app.kubernetes.io/name=falcosidekick"
echo "  Mais ils se différencient par app.kubernetes.io/component :"
echo "    - falco-falcosidekick     → component: core  (port 2801) ✅"
echo "    - falco-falcosidekick-ui  → component: ui    (port 2802) ❌"
echo ""
echo "💡 Solution :"
echo "  Ajouter le label component=core au sélecteur du ServiceMonitor"
echo ""

read -p "Continuer avec la correction ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Correction annulée."
    exit 0
fi

# Supprimer l'ancien ServiceMonitor
echo ""
echo "1️⃣  Suppression de l'ancien ServiceMonitor..."
kubectl delete servicemonitor falcosidekick -n security-detection --ignore-not-found=true
echo "  ✅ ServiceMonitor supprimé"

# Créer le nouveau ServiceMonitor avec les deux labels
echo ""
echo "2️⃣  Création du nouveau ServiceMonitor (avec component=core)..."
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
      app.kubernetes.io/component: core  # Cibler uniquement le service principal
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF

echo "  ✅ Nouveau ServiceMonitor créé"

# Attendre que Prometheus redécouvre les targets
echo ""
echo "3️⃣  Attente de la redécouverte par Prometheus (30 secondes)..."
sleep 30

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       ✅ SERVICEMONITOR CORRIGÉ (component=core)          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔍 Vérifier les targets Prometheus :"
echo "   kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "   http://localhost:9090/targets"
echo ""
echo "✅ Résultat attendu :"
echo "   serviceMonitor/security-detection/falcosidekick/0 (2/2 up)"
echo "   - http://10.x.x.x:2801/metrics → UP ✅"
echo "   - http://10.x.x.x:2801/metrics → UP ✅"
echo "   (Plus de endpoints sur port 2802)"
echo ""
echo "📊 Vérifier le ServiceMonitor :"
echo "   kubectl get servicemonitor falcosidekick -n security-detection -o yaml"
echo ""
echo "🎯 Le sélecteur doit maintenant inclure :"
echo "   matchLabels:"
echo "     app.kubernetes.io/name: falcosidekick"
echo "     app.kubernetes.io/component: core"
echo ""
