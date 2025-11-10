#!/bin/bash

set -e

echo "======================================"
echo "Kind Image Preloader"
echo "Charge les images dans Kind sans Docker Hub"
echo "======================================"
echo ""

# Nom du cluster Kind
CLUSTER_NAME="enterprise-security"

# Vérifier que Kind cluster existe
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ Cluster Kind '${CLUSTER_NAME}' introuvable"
    echo "Clusters disponibles :"
    kind get clusters
    exit 1
fi

echo "✅ Cluster Kind trouvé : ${CLUSTER_NAME}"
echo ""

# Liste des images nécessaires pour notre stack
IMAGES=(
    # Keycloak
    "bitnami/keycloak:23.0.3"
    "bitnami/postgresql:15"

    # Vault
    "hashicorp/vault:1.15.2"
    "hashicorp/vault-k8s:1.3.1"

    # Falco
    "falcosecurity/falco:0.37.0"
    "falcosecurity/falco-driver-loader:0.37.0"
    "falcosecurity/falcosidekick:2.28.0"
    "falcosecurity/falcosidekick-ui:2.2.0"

    # cert-manager
    "quay.io/jetstack/cert-manager-controller:v1.13.0"
    "quay.io/jetstack/cert-manager-webhook:v1.13.0"
    "quay.io/jetstack/cert-manager-cainjector:v1.13.0"

    # OPA Gatekeeper
    "openpolicyagent/gatekeeper:v3.15.0"

    # Trivy
    "aquasec/trivy-operator:0.18.0"

    # Redis (pour Falco UI)
    "redis:7.2-alpine"
)

echo "📦 Images à charger : ${#IMAGES[@]}"
echo ""

# Compteurs
LOADED=0
FAILED=0
SKIPPED=0

for IMAGE in "${IMAGES[@]}"; do
    echo "────────────────────────────────────"
    echo "📥 Image : $IMAGE"

    # Vérifier si l'image existe déjà localement
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE}$"; then
        echo "   ✅ Déjà présente localement"
    else
        echo "   ⬇️  Téléchargement..."
        if docker pull "$IMAGE" 2>&1 | tee /tmp/docker_pull.log; then
            echo "   ✅ Téléchargée"
        else
            if grep -q "toomanyrequests\|rate limit" /tmp/docker_pull.log; then
                echo "   ⚠️  Rate limit Docker Hub atteint"
                echo "   💡 Attendez 6 heures ou utilisez une image en cache"
                ((SKIPPED++))
                continue
            else
                echo "   ❌ Échec du téléchargement"
                cat /tmp/docker_pull.log
                ((FAILED++))
                continue
            fi
        fi
    fi

    # Charger dans Kind
    echo "   📤 Chargement dans Kind..."
    if kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"; then
        echo "   ✅ Chargée dans Kind"
        ((LOADED++))
    else
        echo "   ❌ Échec du chargement dans Kind"
        ((FAILED++))
    fi

    echo ""
done

echo "======================================"
echo "Résumé"
echo "======================================"
echo "✅ Chargées avec succès : $LOADED"
echo "❌ Échecs              : $FAILED"
echo "⏭️  Ignorées (rate limit): $SKIPPED"
echo ""

if [ $SKIPPED -gt 0 ]; then
    echo "⚠️  Certaines images n'ont pas pu être téléchargées (rate limit)"
    echo ""
    echo "Options :"
    echo "  1. Attendre 6 heures et relancer ce script"
    echo "  2. Redémarrer Docker Desktop (réinitialise parfois le compteur)"
    echo "  3. Continuer avec les images disponibles"
    echo ""
    read -p "Voulez-vous continuer quand même? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Annulation."
        exit 0
    fi
fi

if [ $LOADED -gt 0 ]; then
    echo "✅ Images chargées dans Kind avec succès !"
    echo ""
    echo "Prochaines étapes :"
    echo "  1. Nettoyer les pods en erreur :"
    echo "     kubectl delete pods --all -n security-iam"
    echo "     kubectl delete pods --all -n security-detection"
    echo ""
    echo "  2. Redéployer avec Terraform :"
    echo "     cd ~/work/enterprise-security-k8s/terraform"
    echo "     terraform apply -auto-approve"
    echo ""
    echo "  3. Surveiller les pods :"
    echo "     watch -n 3 'kubectl get pods --all-namespaces'"
else
    echo "❌ Aucune image n'a pu être chargée"
    echo ""
    echo "Le rate limit Docker Hub est probablement actif."
    echo "Attendez 6 heures ou redémarrez Docker Desktop."
fi

echo ""
echo "======================================"
echo "Script terminé"
echo "======================================"
