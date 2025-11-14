#!/bin/bash

set -e

echo "======================================"
echo "Déploiement SANS Docker Hub"
echo "======================================"
echo ""

echo "Ce script va :"
echo "  1. Vérifier les images Docker locales"
echo "  2. Les charger dans Kind"
echo "  3. Nettoyer les pods en erreur"
echo "  4. Redéployer avec Terraform"
echo ""

read -p "Continuer? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo "======================================"
echo "Étape 1 : Vérification des Images"
echo "======================================"
echo ""

./scripts/check-available-images.sh

echo ""
read -p "Voulez-vous charger les images dans Kind? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulation."
    exit 0
fi

echo ""
echo "======================================"
echo "Étape 2 : Chargement dans Kind"
echo "======================================"
echo ""

./scripts/preload-images.sh

echo ""
echo "======================================"
echo "Étape 3 : Nettoyage des Pods en Erreur"
echo "======================================"
echo ""

echo "Suppression des releases Helm échouées..."
helm uninstall keycloak -n security-iam 2>/dev/null || echo "  Keycloak déjà supprimé"
helm uninstall vault -n security-iam 2>/dev/null || echo "  Vault déjà supprimé"
helm uninstall falco -n security-detection 2>/dev/null || echo "  Falco déjà supprimé"
helm uninstall trivy-operator -n trivy-system 2>/dev/null || echo "  Trivy déjà supprimé"

echo ""
echo "Suppression des pods en erreur..."
kubectl delete pods --all -n security-iam --ignore-not-found=true
kubectl delete pods --all -n security-detection --ignore-not-found=true
kubectl delete pods --all -n trivy-system --ignore-not-found=true

echo ""
echo "✅ Nettoyage terminé"
sleep 3

echo ""
echo "======================================"
echo "Étape 4 : Redéploiement Terraform"
echo "======================================"
echo ""

cd ~/work/enterprise-security-k8s/terraform

echo "Pull des dernières modifications..."
git pull origin claude/review-repository-011CUxDmyN615VtysZeHB5x8

echo ""
echo "Terraform apply..."
terraform apply -auto-approve

echo ""
echo "✅ Terraform terminé"

echo ""
echo "======================================"
echo "Étape 5 : Surveillance des Pods"
echo "======================================"
echo ""

echo "Surveillance pendant 5 minutes..."
echo "(Ctrl+C pour arrêter)"
echo ""

for i in {1..10}; do
    echo "─────────────────────────────────────────"
    echo "Check $i/10 - $(date +%H:%M:%S)"
    echo "─────────────────────────────────────────"
    echo ""

    echo "▶ security-iam :"
    kubectl get pods -n security-iam
    echo ""

    echo "▶ security-detection :"
    kubectl get pods -n security-detection
    echo ""

    # Vérifier les erreurs
    ERRORS=$(kubectl get pods --all-namespaces | grep -E "ImagePull|CrashLoop|Error" | wc -l)

    if [ $ERRORS -eq 0 ]; then
        echo "✅ TOUS LES PODS SONT OK !"
        break
    fi

    echo "⚠️  Pods en erreur restants : $ERRORS"

    if [ $i -lt 10 ]; then
        echo "Attente 30 secondes..."
        sleep 30
    fi
done

echo ""
echo "======================================"
echo "Résumé Final"
echo "======================================"
echo ""

kubectl get pods --all-namespaces | grep -E "security-|cert-manager|gatekeeper|trivy"

echo ""
FAILED=$(kubectl get pods --all-namespaces | grep -E "ImagePull|CrashLoop|Error" | wc -l)

if [ $FAILED -eq 0 ]; then
    echo "🎉 SUCCÈS ! Stack déployée sans Docker Hub !"
    echo ""
    echo "Accès aux services :"
    echo "  Grafana:  kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
    echo "  Keycloak: kubectl port-forward -n security-iam svc/keycloak 8080:80"
    echo "  Vault:    kubectl port-forward -n security-iam svc/vault 8200:8200"
    echo "  Falco UI: kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802"
else
    echo "⚠️  Il reste $FAILED pods en erreur"
    echo ""
    echo "Diagnostiquer :"
    echo "  kubectl get pods --all-namespaces | grep -v Running"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
    echo "  kubectl logs <pod-name> -n <namespace>"
fi

echo ""
echo "======================================"
echo "Déploiement terminé"
echo "======================================"
