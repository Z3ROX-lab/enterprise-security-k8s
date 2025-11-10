#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          NETTOYAGE COMPLET - Enterprise Security         ║"
echo "║          Suppression de TOUT (cluster + resources)       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

read -p "⚠️  ATTENTION : Cela va TOUT supprimer. Continuer ? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Annulation."
    exit 0
fi

echo ""
echo "🗑️  Nettoyage en cours..."
echo ""

# 1. Supprimer toutes les releases Helm
echo "📦 Suppression des releases Helm..."
helm uninstall kibana -n security-siem 2>/dev/null && echo "  ✅ kibana" || echo "  ⏭️  kibana (déjà supprimé)"
helm uninstall elasticsearch -n security-siem 2>/dev/null && echo "  ✅ elasticsearch" || echo "  ⏭️  elasticsearch"
helm uninstall filebeat -n security-siem 2>/dev/null && echo "  ✅ filebeat" || echo "  ⏭️  filebeat"
helm uninstall prometheus -n security-siem 2>/dev/null && echo "  ✅ prometheus" || echo "  ⏭️  prometheus"
helm uninstall keycloak -n security-iam 2>/dev/null && echo "  ✅ keycloak" || echo "  ⏭️  keycloak"
helm uninstall vault -n security-iam 2>/dev/null && echo "  ✅ vault" || echo "  ⏭️  vault"
helm uninstall cert-manager -n cert-manager 2>/dev/null && echo "  ✅ cert-manager" || echo "  ⏭️  cert-manager"
helm uninstall falco -n security-detection 2>/dev/null && echo "  ✅ falco" || echo "  ⏭️  falco"
helm uninstall gatekeeper -n gatekeeper-system 2>/dev/null && echo "  ✅ gatekeeper" || echo "  ⏭️  gatekeeper"
helm uninstall trivy-operator -n trivy-system 2>/dev/null && echo "  ✅ trivy" || echo "  ⏭️  trivy"

echo ""
echo "🗂️  Suppression des namespaces..."
kubectl delete namespace security-siem --ignore-not-found=true && echo "  ✅ security-siem" || echo "  ⏭️  security-siem"
kubectl delete namespace security-iam --ignore-not-found=true && echo "  ✅ security-iam" || echo "  ⏭️  security-iam"
kubectl delete namespace security-detection --ignore-not-found=true && echo "  ✅ security-detection" || echo "  ⏭️  security-detection"
kubectl delete namespace cert-manager --ignore-not-found=true && echo "  ✅ cert-manager" || echo "  ⏭️  cert-manager"
kubectl delete namespace gatekeeper-system --ignore-not-found=true && echo "  ✅ gatekeeper-system" || echo "  ⏭️  gatekeeper-system"
kubectl delete namespace trivy-system --ignore-not-found=true && echo "  ✅ trivy-system" || echo "  ⏭️  trivy-system"

echo ""
echo "🔥 Suppression du cluster Kind..."
kind delete cluster --name enterprise-security 2>/dev/null && echo "  ✅ Cluster supprimé" || echo "  ⏭️  Cluster déjà supprimé"

echo ""
echo "🧹 Nettoyage de l'état Terraform..."
cd ~/work/enterprise-security-k8s/terraform
rm -rf .terraform 2>/dev/null && echo "  ✅ .terraform supprimé" || true
rm -f .terraform.lock.hcl 2>/dev/null && echo "  ✅ .terraform.lock.hcl supprimé" || true
rm -f terraform.tfstate* 2>/dev/null && echo "  ✅ terraform.tfstate supprimé" || true
rm -f terraform.tfvars 2>/dev/null && echo "  ✅ terraform.tfvars supprimé" || true

echo ""
echo "🧹 Nettoyage des images temporaires..."
rm -rf /tmp/wazuh-kubernetes 2>/dev/null && echo "  ✅ Wazuh repo temporaire supprimé" || true
rm -f /tmp/load-images-kind.sh 2>/dev/null && echo "  ✅ Scripts temporaires supprimés" || true
rm -f /tmp/docker_pull.log 2>/dev/null && echo "  ✅ Logs temporaires supprimés" || true

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                   ✅ NETTOYAGE TERMINÉ                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Système nettoyé. Vous pouvez maintenant redéployer :"
echo "  cd ~/work/enterprise-security-k8s/deploy"
echo "  ./01-cluster.sh"
echo "  ./02-monitoring.sh"
echo "  ./03-iam.sh"
echo "  etc."
echo ""
