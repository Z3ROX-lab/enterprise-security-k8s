#!/bin/bash

set -e

CLUSTER_NAME="enterprise-security"

echo "======================================"
echo "Chargement Robuste des Images dans Kind"
echo "======================================"
echo ""

# Vérifier le cluster
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ Cluster Kind '${CLUSTER_NAME}' introuvable"
    exit 1
fi

echo "✅ Cluster Kind trouvé: ${CLUSTER_NAME}"
echo ""

# Fonction pour charger une image avec méthode alternative
load_image_alternative() {
    local IMAGE=$1
    echo "   🔄 Tentative alternative (docker save + ctr import)..."

    # Sauvegarder l'image en tar
    local IMAGE_TAR="/tmp/$(echo $IMAGE | tr '/:' '_').tar"

    if docker save "$IMAGE" -o "$IMAGE_TAR" 2>/dev/null; then
        echo "   ✅ Image sauvegardée en tar"

        # Charger dans chaque nœud Kind
        for node in $(kind get nodes --name "$CLUSTER_NAME"); do
            echo "      📤 Chargement dans $node..."
            if docker cp "$IMAGE_TAR" "$node:/tmp/image.tar" && \
               docker exec "$node" ctr -n k8s.io images import /tmp/image.tar && \
               docker exec "$node" rm /tmp/image.tar; then
                echo "      ✅ OK"
            else
                echo "      ⚠️  Échec (non-bloquant)"
            fi
        done

        rm -f "$IMAGE_TAR"
        return 0
    else
        return 1
    fi
}

# Liste des images critiques (les autres peuvent être téléchargées par Kubernetes)
CRITICAL_IMAGES=(
    "docker.io/bitnami/keycloak:24.0.4-debian-12-r0"
    "docker.io/bitnami/postgresql:16.2.0-debian-12-r18"
    "hashicorp/vault:1.15.2"
    "docker.io/falcosecurity/falco:0.37.0"
)

# Liste des images non-critiques (skip si erreur)
OPTIONAL_IMAGES=(
    "docker.io/falcosecurity/falco-driver-loader:0.37.0"
    "docker.io/falcosecurity/falcosidekick:2.28.0"
    "docker.io/falcosecurity/falcosidekick-ui:2.2.0"
    "redis:7.2-alpine"
    "hashicorp/vault-k8s:1.3.1"
)

LOADED=0
FAILED=0

echo "📦 Chargement des images CRITIQUES..."
echo ""

for IMAGE in "${CRITICAL_IMAGES[@]}"; do
    echo "────────────────────────────────────"
    echo "📥 Image : $IMAGE"

    # Vérifier si l'image existe localement
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE#docker.io/}$" && \
       ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE}$"; then
        echo "   ⬇️  Téléchargement..."
        if docker pull "$IMAGE" 2>&1 | tee /tmp/docker_pull.log; then
            echo "   ✅ Téléchargée"
        else
            echo "   ❌ ÉCHEC CRITIQUE - Cette image est nécessaire"
            ((FAILED++))
            continue
        fi
    else
        echo "   ✅ Déjà présente localement"
    fi

    # Charger dans Kind (méthode standard)
    echo "   📤 Chargement dans Kind..."
    if kind load docker-image "$IMAGE" --name "$CLUSTER_NAME" 2>&1 | tee /tmp/kind_load.log; then
        echo "   ✅ Chargée dans Kind"
        ((LOADED++))
    else
        if grep -q "not yet present on node\|not found" /tmp/kind_load.log; then
            echo "   ⚠️  Erreur multi-plateforme détectée"
            if load_image_alternative "$IMAGE"; then
                echo "   ✅ Chargée avec méthode alternative"
                ((LOADED++))
            else
                echo "   ❌ ÉCHEC CRITIQUE"
                ((FAILED++))
            fi
        else
            echo "   ❌ ÉCHEC CRITIQUE"
            ((FAILED++))
        fi
    fi

    echo ""
done

echo ""
echo "📦 Chargement des images OPTIONNELLES..."
echo ""

for IMAGE in "${OPTIONAL_IMAGES[@]}"; do
    echo "────────────────────────────────────"
    echo "📥 Image : $IMAGE (optionnelle)"

    # Vérifier si l'image existe localement
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE#docker.io/}$" && \
       ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE}$"; then
        echo "   ⬇️  Téléchargement..."
        if ! docker pull "$IMAGE" 2>&1; then
            echo "   ⚠️  Skip (pas critique)"
            continue
        fi
    else
        echo "   ✅ Déjà présente localement"
    fi

    # Charger dans Kind (erreurs ignorées)
    echo "   📤 Chargement dans Kind..."
    if kind load docker-image "$IMAGE" --name "$CLUSTER_NAME" 2>&1; then
        echo "   ✅ Chargée dans Kind"
        ((LOADED++))
    else
        echo "   ⚠️  Échec (ignoré, Kubernetes peut la pull)"
    fi

    echo ""
done

echo "======================================"
echo "Résumé"
echo "======================================"
echo "✅ Chargées avec succès : $LOADED"
echo "❌ Échecs critiques     : $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "⚠️  Des images critiques n'ont pas pu être chargées."
    echo ""
    echo "Options :"
    echo "  1. Vérifier Docker Desktop (redémarrer si nécessaire)"
    echo "  2. Vérifier la connexion internet"
    echo "  3. Attendre et réessayer (rate limit Docker Hub)"
    echo ""
    exit 1
fi

echo "✅ Toutes les images critiques sont chargées !"
echo ""
echo "Note : Certaines images optionnelles peuvent avoir échoué."
echo "Ce n'est pas grave, Kubernetes les téléchargera au besoin."
echo ""
echo "Prochaines étapes :"
echo "  1. Nettoyer les pods en erreur"
echo "  2. Redéployer avec Terraform"
echo "  3. Les images manquantes seront pull par Kubernetes"
echo ""
