#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              Falco Runtime Security                       ║"
echo "║         (Kernel Module Driver pour WSL2)                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster non trouvé"
    echo "Lancez d'abord : ./01-cluster-kind.sh"
    exit 1
fi

echo "📋 Ce script va déployer :"
echo "  - Falco (runtime security)"
echo "  - Falcosidekick (event forwarder)"
echo "  - Falcosidekick UI (dashboard)"
echo ""
echo "⚠️  Note : Utilise le driver 'kernel module' (compatible WSL2)"
echo "   Le driver eBPF ne fonctionne pas avec Kind/WSL2"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# Créer le namespace
echo ""
echo "📁 Création du namespace security-detection..."
kubectl create namespace security-detection --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm
echo ""
echo "📦 Ajout du repo Helm Falco..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Déployer Falco
echo ""
echo "🛡️  Déploiement de Falco (5-10 minutes)..."
helm upgrade --install falco falcosecurity/falco \
  --namespace security-detection \
  --version 4.0.0 \
  --set driver.kind=module \
  --set driver.loader.initContainer.enabled=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  --set falcosidekick.webui.redis.storageEnabled=false \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=512Mi \
  --set resources.limits.cpu=1000m \
  --set resources.limits.memory=1Gi \
  --set tty=true \
  --timeout 15m \
  --wait=false

echo ""
echo "⏳ Attente du démarrage des pods..."
echo "   (Le chargement du kernel module peut prendre 5-10 minutes)"
echo ""

for i in {1..40}; do
    echo "─────── Check $i/40 (${i}0s) ───────"
    kubectl get pods -n security-detection -l app.kubernetes.io/name=falco 2>/dev/null || echo "  Pas encore de pods"

    # Compter les pods Running
    RUNNING=$(kubectl get pods -n security-detection -l app.kubernetes.io/name=falco -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l || echo "0")
    TOTAL=$(kubectl get pods -n security-detection -l app.kubernetes.io/name=falco --no-headers 2>/dev/null | wc -l || echo "0")

    echo "  Running: $RUNNING/$TOTAL"

    # Vérifier les erreurs d'init
    INIT_ERRORS=$(kubectl get pods -n security-detection -l app.kubernetes.io/name=falco -o jsonpath='{.items[*].status.initContainerStatuses[*].state.waiting.reason}' 2>/dev/null | grep -i "error\|crash" || echo "")
    if [ -n "$INIT_ERRORS" ]; then
        echo "  ⚠️  Init container issues detected"
        kubectl get pods -n security-detection -l app.kubernetes.io/name=falco
        echo ""
        echo "  Vérifier les logs :"
        POD=$(kubectl get pods -n security-detection -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$POD" ]; then
            echo "    kubectl logs $POD -n security-detection -c falco-driver-loader"
        fi
    fi
    echo ""

    if [ "$TOTAL" -gt 0 ] && [ "$RUNNING" -eq "$TOTAL" ]; then
        echo "✅ Tous les pods Falco sont Running !"
        break
    fi

    if [ $i -lt 40 ]; then
        sleep 15
    fi
done

echo ""
echo "📊 État final des pods :"
kubectl get pods -n security-detection

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║             ✅ FALCO DÉPLOYÉ                              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ✅ Falco (runtime security)"
echo "  ✅ Falcosidekick (event forwarder)"
echo "  ✅ Falcosidekick UI (dashboard)"
echo ""
echo "Accès à l'interface Falco :"
echo "  kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802"
echo "  http://localhost:2802"
echo ""
echo "Tester Falco :"
echo "  # Déclencher une alerte (shell interactif dans un pod)"
echo "  kubectl run test-pod --image=busybox --rm -it -- sh"
echo ""
echo "  # Voir les événements Falco"
echo "  kubectl logs -n security-detection -l app.kubernetes.io/name=falco -f"
echo ""
echo "Prochaine étape :"
echo "  ./31-wazuh.sh (optionnel, 8GB RAM requis)"
echo "  ./40-gatekeeper.sh"
echo ""
