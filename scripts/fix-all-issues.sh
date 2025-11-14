#!/bin/bash

set -e

echo "======================================"
echo "Fix All Deployment Issues"
echo "======================================"
echo ""

echo "Ce script va corriger :"
echo "  1. ImagePullBackOff (Keycloak, PostgreSQL)"
echo "  2. Falco eBPF → Kernel Module"
echo "  3. Trivy node-collector Pending"
echo ""

read -p "Continuer? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo "======================================"
echo "Étape 1 : Nettoyage des Releases Échouées"
echo "======================================"
echo ""

echo "Suppression de Keycloak..."
helm uninstall keycloak -n security-iam 2>/dev/null || echo "Déjà supprimé"

echo "Suppression de Falco..."
helm uninstall falco -n security-detection 2>/dev/null || echo "Déjà supprimé"

echo "Suppression de Trivy..."
helm uninstall trivy-operator -n trivy-system 2>/dev/null || echo "Déjà supprimé"

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
echo "Étape 2 : Configuration Docker Hub (Optionnel)"
echo "======================================"
echo ""

read -p "Avez-vous un compte Docker Hub? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Docker Hub Username: " DOCKER_USER
    read -sp "Docker Hub Password: " DOCKER_PASS
    echo ""
    read -p "Docker Hub Email: " DOCKER_EMAIL

    echo ""
    echo "Création des secrets Docker..."
    kubectl create secret docker-registry dockerhub \
      --docker-username=$DOCKER_USER \
      --docker-password=$DOCKER_PASS \
      --docker-email=$DOCKER_EMAIL \
      -n security-iam --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret docker-registry dockerhub \
      --docker-username=$DOCKER_USER \
      --docker-password=$DOCKER_PASS \
      --docker-email=$DOCKER_EMAIL \
      -n security-detection --dry-run=client -o yaml | kubectl apply -f -

    echo "✅ Secrets créés"

    echo ""
    echo "Liaison aux ServiceAccounts..."
    kubectl patch serviceaccount default -n security-iam \
      -p '{"imagePullSecrets": [{"name": "dockerhub"}]}'
    kubectl patch serviceaccount default -n security-detection \
      -p '{"imagePullSecrets": [{"name": "dockerhub"}]}'

    echo "✅ ServiceAccounts patchés"
else
    echo "⚠️  Sans authentification Docker Hub, vous risquez d'avoir des rate limits."
    echo "   Vous pouvez continuer, mais si les pulls échouent encore,"
    echo "   vous devrez créer un compte Docker Hub."
fi

echo ""
echo "======================================"
echo "Étape 3 : Redéploiement avec Terraform"
echo "======================================"
echo ""

cd ~/work/enterprise-security-k8s/terraform

echo "Pull des dernières corrections..."
git pull origin claude/review-repository-011CUxDmyN615VtysZeHB5x8

echo ""
echo "Lancement de terraform apply..."
echo "(Cela va prendre 2-5 minutes)"
echo ""

terraform apply -auto-approve

echo ""
echo "✅ Terraform terminé"

echo ""
echo "======================================"
echo "Étape 4 : Surveillance du Déploiement"
echo "======================================"
echo ""

echo "Les pods vont démarrer en arrière-plan."
echo "Surveillance pendant 5 minutes..."
echo ""

for i in {1..10}; do
    echo "--- Check $i/10 ($(date +%H:%M:%S)) ---"
    kubectl get pods -n security-iam
    echo ""
    kubectl get pods -n security-detection
    echo ""

    # Vérifier si tout est Running
    FAILED=$(kubectl get pods --all-namespaces | grep -E "ImagePull|CrashLoop|Error" | wc -l)
    if [ $FAILED -eq 0 ]; then
        echo "✅ TOUS LES PODS SONT EN ÉTAT NORMAL !"
        break
    fi

    echo "Pods en erreur restants : $FAILED"
    echo "Attente 30 secondes..."
    sleep 30
done

echo ""
echo "======================================"
echo "Résumé Final"
echo "======================================"
echo ""

echo "📊 État des Namespaces :"
echo ""
echo "▶ security-iam :"
kubectl get pods -n security-iam
echo ""

echo "▶ security-detection :"
kubectl get pods -n security-detection
echo ""

echo "▶ cert-manager :"
kubectl get pods -n cert-manager
echo ""

echo "▶ gatekeeper-system :"
kubectl get pods -n gatekeeper-system 2>/dev/null || echo "  Pas de pods"
echo ""

FAILED=$(kubectl get pods --all-namespaces | grep -E "ImagePull|CrashLoop|Error" | wc -l)

if [ $FAILED -eq 0 ]; then
    echo "🎉 SUCCÈS ! Tous les pods sont opérationnels."
    echo ""
    echo "Accès aux dashboards :"
    echo "  Grafana:  kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
    echo "  Keycloak: kubectl port-forward -n security-iam svc/keycloak 8080:80"
    echo "  Vault:    kubectl port-forward -n security-iam svc/vault 8200:8200"
    echo "  Falco UI: kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802"
else
    echo "⚠️  Il reste $FAILED pods en erreur."
    echo ""
    echo "Pour diagnostiquer :"
    echo "  kubectl get pods --all-namespaces | grep -v Running"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
    echo "  kubectl logs <pod-name> -n <namespace>"
    echo ""
    echo "Pour obtenir de l'aide :"
    echo "  ./scripts/diagnose-pods.sh"
fi

echo ""
echo "======================================"
echo "Script terminé"
echo "======================================"
