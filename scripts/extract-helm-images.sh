#!/bin/bash

set -e

echo "======================================"
echo "Extraction des Versions d'Images depuis Helm"
echo "======================================"
echo ""

# Ajouter les repos Helm si nécessaire
echo "📦 Configuration des repositories Helm..."

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || echo "  bitnami déjà ajouté"
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || echo "  hashicorp déjà ajouté"
helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || echo "  falcosecurity déjà ajouté"
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || echo "  jetstack déjà ajouté"
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>/dev/null || echo "  gatekeeper déjà ajouté"
helm repo add aqua https://aquasecurity.github.io/helm-charts/ 2>/dev/null || echo "  aqua déjà ajouté"

echo "Mise à jour des repos..."
helm repo update

echo ""
echo "======================================"
echo "Extraction des Images"
echo "======================================"
echo ""

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

declare -A IMAGES

# Keycloak
echo "📦 Keycloak (chart: bitnami/keycloak:18.0.0)..."
helm template keycloak bitnami/keycloak --version 18.0.0 > $TEMP_DIR/keycloak.yaml
KEYCLOAK_IMAGE=$(grep "image:" $TEMP_DIR/keycloak.yaml | grep keycloak | head -1 | awk '{print $2}' | tr -d '"')
POSTGRES_IMAGE=$(grep "image:" $TEMP_DIR/keycloak.yaml | grep postgresql | head -1 | awk '{print $2}' | tr -d '"')
IMAGES["keycloak"]=$KEYCLOAK_IMAGE
IMAGES["postgresql"]=$POSTGRES_IMAGE
echo "  ✅ Keycloak: $KEYCLOAK_IMAGE"
echo "  ✅ PostgreSQL: $POSTGRES_IMAGE"

# Vault
echo "📦 Vault (chart: hashicorp/vault:0.27.0)..."
helm template vault hashicorp/vault --version 0.27.0 > $TEMP_DIR/vault.yaml
VAULT_IMAGE=$(grep "image:" $TEMP_DIR/vault.yaml | grep hashicorp/vault | head -1 | awk '{print $2}' | tr -d '"')
VAULT_K8S_IMAGE=$(grep "image:" $TEMP_DIR/vault.yaml | grep vault-k8s | head -1 | awk '{print $2}' | tr -d '"')
IMAGES["vault"]=$VAULT_IMAGE
IMAGES["vault-k8s"]=$VAULT_K8S_IMAGE
echo "  ✅ Vault: $VAULT_IMAGE"
echo "  ✅ Vault K8s: $VAULT_K8S_IMAGE"

# Falco
echo "📦 Falco (chart: falcosecurity/falco:4.0.0)..."
helm template falco falcosecurity/falco --version 4.0.0 \
  --set driver.kind=module \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true > $TEMP_DIR/falco.yaml
FALCO_IMAGE=$(grep "image:" $TEMP_DIR/falco.yaml | grep "falcosecurity/falco:" | head -1 | awk '{print $2}' | tr -d '"' | sed 's/"//g')
FALCO_DRIVER_IMAGE=$(grep "image:" $TEMP_DIR/falco.yaml | grep "falco-driver-loader" | head -1 | awk '{print $2}' | tr -d '"')
FALCOSIDEKICK_IMAGE=$(grep "image:" $TEMP_DIR/falco.yaml | grep "falcosidekick:" | grep -v "falcosidekick-ui" | head -1 | awk '{print $2}' | tr -d '"')
FALCOSIDEKICK_UI_IMAGE=$(grep "image:" $TEMP_DIR/falco.yaml | grep "falcosidekick-ui" | head -1 | awk '{print $2}' | tr -d '"')
REDIS_IMAGE=$(grep "image:" $TEMP_DIR/falco.yaml | grep "redis" | head -1 | awk '{print $2}' | tr -d '"')

IMAGES["falco"]=$FALCO_IMAGE
IMAGES["falco-driver-loader"]=$FALCO_DRIVER_IMAGE
IMAGES["falcosidekick"]=$FALCOSIDEKICK_IMAGE
IMAGES["falcosidekick-ui"]=$FALCOSIDEKICK_UI_IMAGE
IMAGES["redis"]=$REDIS_IMAGE

echo "  ✅ Falco: $FALCO_IMAGE"
echo "  ✅ Falco Driver: $FALCO_DRIVER_IMAGE"
echo "  ✅ Falcosidekick: $FALCOSIDEKICK_IMAGE"
echo "  ✅ Falcosidekick UI: $FALCOSIDEKICK_UI_IMAGE"
echo "  ✅ Redis: $REDIS_IMAGE"

# cert-manager
echo "📦 cert-manager (chart: jetstack/cert-manager:1.13.0)..."
helm template cert-manager jetstack/cert-manager --version 1.13.0 --set installCRDs=true > $TEMP_DIR/cert-manager.yaml
CERT_MANAGER_CONTROLLER=$(grep "image:" $TEMP_DIR/cert-manager.yaml | grep "cert-manager-controller" | head -1 | awk '{print $2}' | tr -d '"')
CERT_MANAGER_WEBHOOK=$(grep "image:" $TEMP_DIR/cert-manager.yaml | grep "cert-manager-webhook" | head -1 | awk '{print $2}' | tr -d '"')
CERT_MANAGER_CAINJECTOR=$(grep "image:" $TEMP_DIR/cert-manager.yaml | grep "cert-manager-cainjector" | head -1 | awk '{print $2}' | tr -d '"')

IMAGES["cert-manager-controller"]=$CERT_MANAGER_CONTROLLER
IMAGES["cert-manager-webhook"]=$CERT_MANAGER_WEBHOOK
IMAGES["cert-manager-cainjector"]=$CERT_MANAGER_CAINJECTOR

echo "  ✅ Controller: $CERT_MANAGER_CONTROLLER"
echo "  ✅ Webhook: $CERT_MANAGER_WEBHOOK"
echo "  ✅ CA Injector: $CERT_MANAGER_CAINJECTOR"

# OPA Gatekeeper
echo "📦 OPA Gatekeeper (chart: gatekeeper/gatekeeper:3.15.0)..."
helm template gatekeeper gatekeeper/gatekeeper --version 3.15.0 > $TEMP_DIR/gatekeeper.yaml
GATEKEEPER_IMAGE=$(grep "image:" $TEMP_DIR/gatekeeper.yaml | grep "gatekeeper" | head -1 | awk '{print $2}' | tr -d '"')
IMAGES["gatekeeper"]=$GATEKEEPER_IMAGE
echo "  ✅ Gatekeeper: $GATEKEEPER_IMAGE"

# Trivy (optionnel, peut être désactivé)
echo "📦 Trivy Operator (chart: aqua/trivy-operator:0.18.0)..."
helm template trivy-operator aqua/trivy-operator --version 0.18.0 > $TEMP_DIR/trivy.yaml 2>/dev/null || true
TRIVY_IMAGE=$(grep "image:" $TEMP_DIR/trivy.yaml | grep "trivy-operator" | head -1 | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "")
if [ -n "$TRIVY_IMAGE" ]; then
    IMAGES["trivy-operator"]=$TRIVY_IMAGE
    echo "  ✅ Trivy: $TRIVY_IMAGE"
else
    echo "  ⚠️  Trivy: impossible d'extraire (peut être ignoré)"
fi

echo ""
echo "======================================"
echo "Génération du Script de Chargement"
echo "======================================"
echo ""

# Créer un script avec les bonnes versions
cat > /tmp/load-images-kind.sh <<'SCRIPT_START'
#!/bin/bash

set -e

CLUSTER_NAME="enterprise-security"

echo "======================================"
echo "Chargement des Images dans Kind"
echo "======================================"
echo ""

# Vérifier le cluster
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ Cluster Kind '${CLUSTER_NAME}' introuvable"
    exit 1
fi

echo "✅ Cluster Kind trouvé: ${CLUSTER_NAME}"
echo ""

IMAGES=(
SCRIPT_START

# Ajouter les images au script
for key in "${!IMAGES[@]}"; do
    echo "    \"${IMAGES[$key]}\"" >> /tmp/load-images-kind.sh
done

cat >> /tmp/load-images-kind.sh <<'SCRIPT_END'
)

LOADED=0
FAILED=0
SKIPPED=0

for IMAGE in "${IMAGES[@]}"; do
    [ -z "$IMAGE" ] && continue

    echo "────────────────────────────────────"
    echo "📥 Image : $IMAGE"

    # Vérifier si l'image existe localement
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE}$"; then
        echo "   ✅ Déjà présente localement"
    else
        echo "   ⬇️  Téléchargement..."
        if docker pull "$IMAGE" 2>&1 | tee /tmp/docker_pull.log; then
            echo "   ✅ Téléchargée"
        else
            if grep -q "toomanyrequests\|rate limit" /tmp/docker_pull.log; then
                echo "   ⚠️  Rate limit Docker Hub"
                ((SKIPPED++))
                continue
            elif grep -q "not found" /tmp/docker_pull.log; then
                echo "   ❌ Image introuvable (peut-être une ancienne version)"
                ((FAILED++))
                continue
            else
                echo "   ❌ Échec du téléchargement"
                ((FAILED++))
                continue
            fi
        fi
    fi

    # Charger dans Kind
    echo "   📤 Chargement dans Kind..."
    if kind load docker-image "$IMAGE" --name "$CLUSTER_NAME" 2>&1; then
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
echo "✅ Chargées : $LOADED"
echo "❌ Échecs   : $FAILED"
echo "⏭️  Ignorées : $SKIPPED"
echo ""

if [ $LOADED -gt 0 ]; then
    echo "✅ Images chargées dans Kind avec succès !"
else
    echo "❌ Aucune image chargée"
fi
SCRIPT_END

chmod +x /tmp/load-images-kind.sh

echo "✅ Script généré : /tmp/load-images-kind.sh"
echo ""
echo "======================================"
echo "Images à Charger (${#IMAGES[@]})"
echo "======================================"
echo ""

for key in "${!IMAGES[@]}"; do
    echo "  $key: ${IMAGES[$key]}"
done

echo ""
echo "======================================"
echo "Prochaines Étapes"
echo "======================================"
echo ""
echo "1. Exécuter le script généré :"
echo "   /tmp/load-images-kind.sh"
echo ""
echo "2. Nettoyer les pods en erreur :"
echo "   kubectl delete pods --all -n security-iam"
echo "   kubectl delete pods --all -n security-detection"
echo ""
echo "3. Redéployer :"
echo "   cd ~/work/enterprise-security-k8s/terraform"
echo "   terraform apply -auto-approve"
echo ""
