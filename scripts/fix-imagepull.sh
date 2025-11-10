#!/bin/bash

echo "======================================"
echo "Fix ImagePullBackOff Issues"
echo "======================================"
echo ""

echo "🔍 Diagnostic des problèmes d'images Docker..."
echo ""

# Vérifier les pods en ImagePullBackOff
echo "Pods en ImagePullBackOff :"
kubectl get pods --all-namespaces | grep ImagePullBackOff || echo "Aucun"
echo ""

echo "📋 Détails des erreurs :"
echo ""

# Keycloak
if kubectl get pod keycloak-0 -n security-iam &>/dev/null; then
    echo "▶ Keycloak:"
    kubectl describe pod keycloak-0 -n security-iam | grep -A 5 "Failed to pull image" | head -10
    echo ""
fi

# PostgreSQL
if kubectl get pod keycloak-postgresql-0 -n security-iam &>/dev/null; then
    echo "▶ PostgreSQL:"
    kubectl describe pod keycloak-postgresql-0 -n security-iam | grep -A 5 "Failed to pull image" | head -10
    echo ""
fi

echo "======================================"
echo "Solutions Proposées"
echo "======================================"
echo ""

echo "📊 SOLUTION 1 : Authentification Docker Hub"
echo "-------------------------------------------"
echo "Si l'erreur contient 'rate limit' ou 'toomanyrequests':"
echo ""
echo "1. Créer un compte Docker Hub (gratuit) : https://hub.docker.com/"
echo "2. Se connecter :"
echo "   docker login"
echo ""
echo "3. Créer un secret Kubernetes :"
read -p "Voulez-vous créer un secret Docker maintenant? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Docker Hub Username: " DOCKER_USER
    read -sp "Docker Hub Password: " DOCKER_PASS
    echo ""
    read -p "Docker Hub Email: " DOCKER_EMAIL

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

    echo ""
    echo "✅ Secrets créés dans security-iam et security-detection"
    echo ""
    echo "4. Lier aux ServiceAccounts :"
    kubectl patch serviceaccount default -n security-iam \
      -p '{"imagePullSecrets": [{"name": "dockerhub"}]}'
    kubectl patch serviceaccount default -n security-detection \
      -p '{"imagePullSecrets": [{"name": "dockerhub"}]}'

    echo "✅ Secrets liés aux ServiceAccounts"
fi

echo ""
echo "📊 SOLUTION 2 : Redémarrer les Pods"
echo "------------------------------------"
echo "Après avoir configuré les secrets, redémarrez les pods :"
echo ""
read -p "Voulez-vous redémarrer les pods maintenant? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Suppression des pods en erreur..."
    kubectl delete pod keycloak-0 -n security-iam --ignore-not-found=true
    kubectl delete pod keycloak-postgresql-0 -n security-iam --ignore-not-found=true

    echo ""
    echo "✅ Pods supprimés. Kubernetes va les recréer automatiquement."
    echo ""
    echo "Surveillance des nouveaux pods (Ctrl+C pour arrêter) :"
    sleep 3
    watch -n 3 'kubectl get pods -n security-iam'
fi

echo ""
echo "📊 SOLUTION 3 : Utiliser un Mirror Docker"
echo "------------------------------------------"
echo "Si Docker Hub est bloqué, vous pouvez configurer un mirror."
echo "Voir : https://docs.docker.com/registry/recipes/mirror/"
echo ""

echo "======================================"
echo "Tests Additionnels"
echo "======================================"
echo ""

echo "🔧 Test : Pull manuel d'une image Bitnami"
echo "------------------------------------------"
read -p "Voulez-vous tester le pull manuel? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Pulling bitnami/postgresql:15..."
    docker pull bitnami/postgresql:15
    if [ $? -eq 0 ]; then
        echo "✅ Pull réussi ! Le problème vient probablement de Kubernetes."
    else
        echo "❌ Pull échoué. Vérifiez votre connexion Docker Hub."
    fi
fi

echo ""
echo "======================================"
echo "Script terminé"
echo "======================================"
