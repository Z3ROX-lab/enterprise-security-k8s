#!/bin/bash

echo "======================================"
echo "Vérification des Images Disponibles"
echo "======================================"
echo ""

echo "📦 Images Docker locales :"
echo ""

# Liste des images nécessaires
declare -A REQUIRED_IMAGES=(
    ["Keycloak"]="bitnami/keycloak:23.0.3"
    ["PostgreSQL"]="bitnami/postgresql:15"
    ["Vault"]="hashicorp/vault:1.15.2"
    ["Vault K8s"]="hashicorp/vault-k8s:1.3.1"
    ["Falco"]="falcosecurity/falco:0.37.0"
    ["Falco Driver Loader"]="falcosecurity/falco-driver-loader:0.37.0"
    ["Falcosidekick"]="falcosecurity/falcosidekick:2.28.0"
    ["Falcosidekick UI"]="falcosecurity/falcosidekick-ui:2.2.0"
    ["Redis"]="redis:7.2-alpine"
    ["cert-manager controller"]="quay.io/jetstack/cert-manager-controller:v1.13.0"
    ["cert-manager webhook"]="quay.io/jetstack/cert-manager-webhook:v1.13.0"
    ["cert-manager cainjector"]="quay.io/jetstack/cert-manager-cainjector:v1.13.0"
    ["OPA Gatekeeper"]="openpolicyagent/gatekeeper:v3.15.0"
    ["Trivy Operator"]="aquasec/trivy-operator:0.18.0"
)

AVAILABLE=0
MISSING=0

for NAME in "${!REQUIRED_IMAGES[@]}"; do
    IMAGE="${REQUIRED_IMAGES[$NAME]}"
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE}$"; then
        echo "  ✅ $NAME ($IMAGE)"
        ((AVAILABLE++))
    else
        echo "  ❌ $NAME ($IMAGE)"
        ((MISSING++))
    fi
done

echo ""
echo "────────────────────────────────────"
echo "Résumé :"
echo "  ✅ Disponibles : $AVAILABLE"
echo "  ❌ Manquantes  : $MISSING"
echo ""

if [ $MISSING -gt 0 ]; then
    echo "💡 Solutions pour les images manquantes :"
    echo ""
    echo "  1. Charger les images avec ./scripts/preload-images.sh"
    echo "     (télécharge et charge dans Kind)"
    echo ""
    echo "  2. Attendre 6 heures (rate limit Docker Hub)"
    echo ""
    echo "  3. Redémarrer Docker Desktop"
    echo "     (réinitialise parfois le rate limit local)"
    echo ""
    echo "  4. Déployer uniquement ce qui est disponible"
    echo "     (désactiver les composants sans images)"
else
    echo "✅ Toutes les images sont disponibles !"
    echo ""
    echo "Prochaine étape :"
    echo "  ./scripts/preload-images.sh"
    echo "  (charge les images dans Kind)"
fi

echo ""
echo "======================================"
