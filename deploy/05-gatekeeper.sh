#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          ÉTAPE 5 : OPA Gatekeeper (Policies)             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster Kubernetes non accessible"
    exit 1
fi

# Ajouter le repo Helm
echo "📦 Configuration du repository Helm..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

# Déployer OPA Gatekeeper
echo ""
echo "📜 Déploiement de OPA Gatekeeper..."
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --version 3.15.0 \
  --timeout 5m \
  --wait

echo ""
echo "⏳ Attente que Gatekeeper soit Ready..."
kubectl wait --for=condition=Ready pod --all -n gatekeeper-system --timeout=300s

echo ""
echo "📊 État des pods :"
kubectl get pods -n gatekeeper-system

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          ✅ GATEKEEPER DÉPLOYÉ AVEC SUCCÈS                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Service déployé :"
echo "  ✅ OPA Gatekeeper (policy enforcement)"
echo ""
echo "Prochaines étapes :"
echo "  - Créer des ConstraintTemplates"
echo "  - Appliquer des Constraints"
echo ""
echo "Exemple de policy :"
echo '  kubectl apply -f - <<EOF'
echo '  apiVersion: templates.gatekeeper.sh/v1'
echo '  kind: ConstraintTemplate'
echo '  metadata:'
echo '    name: k8srequiredlabels'
echo '  # ...'
echo '  EOF'
echo ""
echo "Script suivant (optionnel) :"
echo "  ./06-trivy.sh"
echo ""
