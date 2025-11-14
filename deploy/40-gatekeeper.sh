#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              OPA Gatekeeper (Policy Engine)               ║"
echo "║         Admission Controller + Policy Enforcement        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster non trouvé"
    echo "Lancez d'abord : ./01-cluster-kind.sh"
    exit 1
fi

echo "📋 Ce script va déployer :"
echo "  - OPA Gatekeeper (admission controller)"
echo "  - Constraint templates de base"
echo "  - Policies de sécurité exemples"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# Ajouter le repo Helm
echo ""
echo "📦 Ajout du repo Helm Gatekeeper..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

# Déployer Gatekeeper
echo ""
echo "🔒 Déploiement d'OPA Gatekeeper..."
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --version 3.14.0 \
  --set replicas=1 \
  --set audit.replicas=1 \
  --set enableDeleteOperations=true \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.cpu=1000m \
  --set resources.limits.memory=512Mi \
  --timeout 10m \
  --wait=false

echo ""
echo "⏳ Attente du démarrage des pods..."
echo ""

for i in {1..20}; do
    echo "─────── Check $i/20 ───────"
    kubectl get pods -n gatekeeper-system 2>/dev/null || echo "  Pas encore de pods"

    # Compter les pods Running
    RUNNING=$(kubectl get pods -n gatekeeper-system -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l || echo "0")
    TOTAL=$(kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | wc -l || echo "0")

    echo "  Running: $RUNNING/$TOTAL"
    echo ""

    if [ "$TOTAL" -gt 0 ] && [ "$RUNNING" -eq "$TOTAL" ]; then
        echo "✅ Tous les pods Gatekeeper sont Running !"
        break
    fi

    if [ $i -lt 20 ]; then
        sleep 15
    fi
done

echo ""
echo "📊 État final des pods :"
kubectl get pods -n gatekeeper-system

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          ✅ OPA GATEKEEPER DÉPLOYÉ                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ✅ gatekeeper-controller-manager (admission controller)"
echo "  ✅ gatekeeper-audit (policy audit)"
echo ""
echo "Exemples de policies à appliquer :"
echo ""
echo "1. Bloquer les images non vérifiées :"
echo '  kubectl apply -f - <<EOF'
echo '  apiVersion: templates.gatekeeper.sh/v1'
echo '  kind: ConstraintTemplate'
echo '  metadata:'
echo '    name: k8srequiredlabels'
echo '  spec:'
echo '    crd:'
echo '      spec:'
echo '        names:'
echo '          kind: K8sRequiredLabels'
echo '    targets:'
echo '      - target: admission.k8s.gatekeeper.sh'
echo '        rego: |'
echo '          package k8srequiredlabels'
echo '          violation[{"msg": msg}] {'
echo '            input.review.object.metadata.labels["app"]'
echo '            not input.review.object.metadata.labels["environment"]'
echo '            msg := "Label environment is required"'
echo '          }'
echo '  EOF'
echo ""
echo "2. Forcer les resource limits :"
echo '  kubectl apply -f - <<EOF'
echo '  apiVersion: constraints.gatekeeper.sh/v1beta1'
echo '  kind: K8sRequiredLabels'
echo '  metadata:'
echo '    name: require-environment-label'
echo '  spec:'
echo '    match:'
echo '      kinds:'
echo '        - apiGroups: [""]'
echo '          kinds: ["Pod"]'
echo '  EOF'
echo ""
echo "Vérifier les constraints :"
echo "  kubectl get constrainttemplates"
echo "  kubectl get constraints"
echo ""
echo "Voir les violations :"
echo "  kubectl get k8srequiredlabels -o yaml"
echo ""
echo "Prochaine étape :"
echo "  ./41-trivy.sh (optionnel)"
echo ""
