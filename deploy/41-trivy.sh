#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Trivy Operator (Vulnerability Scanner)           ║"
echo "║      Scan automatique des images et workloads            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que le cluster existe
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster non trouvé"
    echo "Lancez d'abord : ./01-cluster-kind.sh"
    exit 1
fi

echo "📋 Ce script va déployer :"
echo "  - Trivy Operator (vulnerability scanner)"
echo "  - Scan automatique des images"
echo "  - Reports de vulnérabilités"
echo ""
echo "⚠️  Note : Trivy télécharge les bases de vulnérabilités (~500 MB)"
echo "   Le premier scan peut prendre 5-10 minutes"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# Ajouter le repo Helm
echo ""
echo "📦 Ajout du repo Helm Trivy..."
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

# Déployer Trivy Operator
echo ""
echo "🔍 Déploiement de Trivy Operator..."
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --version 0.20.0 \
  --set trivy.ignoreUnfixed=true \
  --set operator.scanJobTimeout=10m \
  --set operator.vulnerabilityScannerEnabled=true \
  --set operator.configAuditScannerEnabled=true \
  --set operator.rbacAssessmentScannerEnabled=true \
  --set trivy.resources.requests.cpu=100m \
  --set trivy.resources.requests.memory=512Mi \
  --set trivy.resources.limits.cpu=1000m \
  --set trivy.resources.limits.memory=2Gi \
  --timeout 10m \
  --wait=false

echo ""
echo "⏳ Attente du démarrage des pods..."
echo ""

for i in {1..20}; do
    echo "─────── Check $i/20 ───────"
    kubectl get pods -n trivy-system 2>/dev/null || echo "  Pas encore de pods"

    # Compter les pods Running
    RUNNING=$(kubectl get pods -n trivy-system -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l || echo "0")
    TOTAL=$(kubectl get pods -n trivy-system --no-headers 2>/dev/null | wc -l || echo "0")

    echo "  Running: $RUNNING/$TOTAL"
    echo ""

    if [ "$TOTAL" -gt 0 ] && [ "$RUNNING" -eq "$TOTAL" ]; then
        echo "✅ Tous les pods Trivy sont Running !"
        break
    fi

    if [ $i -lt 20 ]; then
        sleep 15
    fi
done

echo ""
echo "📊 État final des pods :"
kubectl get pods -n trivy-system

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ TRIVY OPERATOR DÉPLOYÉ                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Services déployés :"
echo "  ✅ trivy-operator (scanner controller)"
echo ""
echo "Attendre quelques minutes pour les premiers scans..."
echo ""
echo "Vérifier les rapports de vulnérabilités :"
echo "  # Voir tous les rapports"
echo "  kubectl get vulnerabilityreports --all-namespaces"
echo ""
echo "  # Voir les vulnérabilités critiques"
echo "  kubectl get vulnerabilityreports --all-namespaces -o json | \\"
echo "    jq '.items[] | select(.report.summary.criticalCount > 0) | {name: .metadata.name, namespace: .metadata.namespace, critical: .report.summary.criticalCount}'"
echo ""
echo "  # Détails d'un rapport spécifique"
echo "  kubectl describe vulnerabilityreport <report-name> -n <namespace>"
echo ""
echo "Vérifier les audits de configuration :"
echo "  kubectl get configauditreports --all-namespaces"
echo ""
echo "Vérifier les évaluations RBAC :"
echo "  kubectl get rbacassessmentreports --all-namespaces"
echo ""
echo "🎉 Stack de sécurité complète déployée !"
echo ""
