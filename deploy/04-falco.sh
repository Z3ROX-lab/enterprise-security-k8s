#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ÉTAPE 4 : Falco Runtime Security                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster Kubernetes non accessible"
    exit 1
fi

# Créer le namespace
echo "📁 Création du namespace security-detection..."
kubectl create namespace security-detection --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm
echo ""
echo "📦 Configuration du repository Helm..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Déployer Falco
echo ""
echo "🦅 Déploiement de Falco (Runtime Security)..."
helm upgrade --install falco falcosecurity/falco \
  --namespace security-detection \
  --version 4.0.0 \
  --set driver.kind=module \
  --set driver.loader.initContainer.enabled=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  --set falcosidekick.config.elasticsearch.hostport=http://elasticsearch-master.security-siem:9200 \
  --timeout 15m \
  --wait=false

echo ""
echo "⏳ Attente que Falco démarre (peut prendre 5-10 min)..."
sleep 30
kubectl get pods -n security-detection

echo ""
echo "📊 État des pods (en cours de démarrage) :"
kubectl get pods -n security-detection

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ FALCO DÉPLOYÉ (démarrage en cours)           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ⏳ Falco DaemonSet (1 pod par nœud)"
echo "  ⏳ Falcosidekick (export des événements)"
echo "  ⏳ Falcosidekick WebUI (dashboard)"
echo ""
echo "Note : Falco peut prendre 5-10 minutes à démarrer complètement"
echo "       (chargement du driver kernel sur chaque nœud)"
echo ""
echo "Surveillance :"
echo "  watch -n 3 'kubectl get pods -n security-detection'"
echo ""
echo "Accès au dashboard :"
echo "  kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802"
echo "  http://localhost:2802"
echo ""
echo "Prochaine étape :"
echo "  ./05-gatekeeper.sh"
echo ""
