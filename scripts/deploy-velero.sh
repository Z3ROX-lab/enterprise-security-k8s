#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Déploiement Velero pour Backups K8s             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Variables
VELERO_VERSION="v1.12.0"
NAMESPACE="velero"
BUCKET="velero"
MINIO_ENDPOINT="http://minio.minio.svc.cluster.local:9000"
CREDENTIALS_FILE="/tmp/velero-credentials"

echo "📦 Configuration Velero:"
echo "   Version: $VELERO_VERSION"
echo "   Namespace: $NAMESPACE"
echo "   Backend: MinIO"
echo "   Bucket: $BUCKET"
echo "   Endpoint: $MINIO_ENDPOINT"
echo ""

# Vérifier que MinIO est déployé
echo "🔍 Vérification des prérequis..."
if ! kubectl get namespace minio &>/dev/null; then
    echo "❌ MinIO n'est pas déployé"
    echo "   Lancez d'abord: ./scripts/deploy-minio.sh"
    exit 1
fi

if ! kubectl get deployment minio -n minio &>/dev/null; then
    echo "❌ MinIO deployment non trouvé"
    echo "   Lancez d'abord: ./scripts/deploy-minio.sh"
    exit 1
fi

echo "   ✅ MinIO est déployé"

# Vérifier le fichier de credentials
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    echo "❌ Fichier credentials non trouvé: $CREDENTIALS_FILE"
    echo ""
    echo "Créez le fichier avec:"
    echo "cat > $CREDENTIALS_FILE <<EOF"
    echo "[default]"
    echo "aws_access_key_id = minio"
    echo "aws_secret_access_key = minio123"
    echo "EOF"
    exit 1
fi

echo "   ✅ Fichier credentials trouvé"
echo ""

# Vérifier si Velero CLI est installé
if ! command -v velero &> /dev/null; then
    echo "⚠️  Velero CLI n'est pas installé"
    echo ""
    echo "Installation automatique du CLI Velero..."

    # Détecter l'architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            echo "❌ Architecture non supportée: $ARCH"
            exit 1
            ;;
    esac

    VELERO_TAR="velero-${VELERO_VERSION}-linux-${ARCH}.tar.gz"
    VELERO_URL="https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/${VELERO_TAR}"

    echo "   📥 Téléchargement de Velero CLI..."
    curl -sL "$VELERO_URL" -o "/tmp/$VELERO_TAR"

    echo "   📦 Extraction..."
    tar -xzf "/tmp/$VELERO_TAR" -C /tmp

    echo "   📁 Installation dans /usr/local/bin..."
    sudo mv "/tmp/velero-${VELERO_VERSION}-linux-${ARCH}/velero" /usr/local/bin/
    sudo chmod +x /usr/local/bin/velero

    echo "   🧹 Nettoyage..."
    rm -rf "/tmp/$VELERO_TAR" "/tmp/velero-${VELERO_VERSION}-linux-${ARCH}"

    echo "   ✅ Velero CLI installé"
    velero version --client-only
    echo ""
fi

read -p "Continuer avec le déploiement Velero ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "🚀 Déploiement de Velero dans le cluster..."

velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.0 \
    --bucket $BUCKET \
    --secret-file $CREDENTIALS_FILE \
    --use-volume-snapshots=false \
    --use-node-agent \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=$MINIO_ENDPOINT \
    --namespace $NAMESPACE

echo ""
echo "⏳ Attendre que Velero soit prêt..."
kubectl wait --for=condition=ready pod -n $NAMESPACE -l deploy=velero --timeout=300s

echo ""
echo "📊 État de Velero:"
kubectl get pods -n $NAMESPACE

echo ""
echo "✅ Velero déployé avec succès !"
echo ""
echo "📋 Informations Velero:"
echo "   Namespace: $NAMESPACE"
echo "   Backend: MinIO ($MINIO_ENDPOINT)"
echo "   Bucket: $BUCKET"
echo ""
echo "🧪 Commandes utiles:"
echo "   # Vérifier le backup location"
echo "   velero backup-location get"
echo ""
echo "   # Créer un backup manuel"
echo "   velero backup create mon-backup"
echo ""
echo "   # Lister les backups"
echo "   velero backup get"
echo ""
echo "   # Créer un backup d'un namespace spécifique"
echo "   velero backup create keycloak-backup --include-namespaces security-iam"
echo ""
echo "   # Restaurer un backup"
echo "   velero restore create --from-backup mon-backup"
echo ""
echo "📝 Prochaine étape: Configurer les backups automatiques"
echo "   ./scripts/configure-velero-schedules.sh"
echo ""
