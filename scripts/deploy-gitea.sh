#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Déploiement Gitea (Git Server Local)             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
NAMESPACE="gitea"
GITEA_VERSION="10.4.1"  # Dernière version stable Helm chart
ADMIN_USER="gitea-admin"
ADMIN_PASSWORD="gitea123!"
ADMIN_EMAIL="admin@gitea.local.lab"

echo "📦 Configuration:"
echo "   Namespace: $NAMESPACE"
echo "   Helm Chart Version: $GITEA_VERSION"
echo "   Admin User: $ADMIN_USER"
echo "   Admin Password: $ADMIN_PASSWORD"
echo ""

# Vérifier que kubectl fonctionne
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Impossible de se connecter au cluster Kubernetes"
    echo "   Vérifiez que le cluster est démarré"
    exit 1
fi

# Créer le namespace
echo "📁 Création du namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace créé/vérifié"
echo ""

# Ajouter le repo Helm Gitea
echo "📦 Ajout du repository Helm Gitea..."
helm repo add gitea-charts https://dl.gitea.com/charts/ 2>/dev/null || true
helm repo update gitea-charts
echo "✅ Repository ajouté"
echo ""

# Créer le fichier values.yaml pour Gitea
echo "⚙️  Création de la configuration Gitea..."
cat > /tmp/gitea-values.yaml <<EOF
# Configuration Gitea pour enterprise-security-k8s
replicaCount: 1

image:
  repository: gitea/gitea
  tag: "1.22.3"
  pullPolicy: IfNotPresent
  rootless: true  # Gitea rootless pour sécurité

# Service
service:
  http:
    type: ClusterIP
    port: 3000
  ssh:
    type: ClusterIP
    port: 22

# Ingress (sera créé séparément)
ingress:
  enabled: false

# Persistence pour les données Git
persistence:
  enabled: true
  size: 10Gi

# Désactiver PostgreSQL (on utilise SQLite pour simplicité)
postgresql:
  enabled: false

# Désactiver PostgreSQL HA
postgresql-ha:
  enabled: false

# Désactiver Redis cluster (pas nécessaire pour la démo)
redis-cluster:
  enabled: false

# Configuration Gitea
gitea:
  admin:
    username: $ADMIN_USER
    password: $ADMIN_PASSWORD
    email: $ADMIN_EMAIL

  config:
    APP_NAME: "Gitea Enterprise Security K8s"
    RUN_MODE: prod

    server:
      DOMAIN: gitea.local.lab
      ROOT_URL: https://gitea.local.lab:8443/
      PROTOCOL: http
      HTTP_PORT: 3000
      DISABLE_SSH: false
      SSH_PORT: 22
      SSH_DOMAIN: gitea.local.lab
      START_SSH_SERVER: true
      LFS_START_SERVER: true

    database:
      DB_TYPE: sqlite3
      PATH: /data/gitea/gitea.db

    security:
      INSTALL_LOCK: true
      SECRET_KEY: "changeme-secret-key-for-gitea-security"
      INTERNAL_TOKEN: "changeme-internal-token-for-gitea"

    service:
      DISABLE_REGISTRATION: false
      REQUIRE_SIGNIN_VIEW: false
      DEFAULT_KEEP_EMAIL_PRIVATE: true
      DEFAULT_ALLOW_CREATE_ORGANIZATION: true
      ENABLE_NOTIFY_MAIL: false

    webhook:
      ALLOWED_HOST_LIST: "*"

    repository:
      DEFAULT_BRANCH: main
      DEFAULT_PRIVATE: public
      ENABLE_PUSH_CREATE_USER: true
      ENABLE_PUSH_CREATE_ORG: true

    ui:
      DEFAULT_THEME: arc-green

    metrics:
      ENABLED: true
      TOKEN: "gitea-metrics-token"

    indexer:
      ISSUE_INDEXER_TYPE: db
      REPO_INDEXER_ENABLED: true

# Ressources (adapté pour la démo)
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

# Métriques Prometheus
metrics:
  enabled: true
  serviceMonitor:
    enabled: true

# Sécurité
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Gitea a besoin d'écrire dans /tmp
  runAsNonRoot: true
EOF

echo "✅ Configuration créée"
echo ""

# Installer Gitea via Helm
echo "🚀 Installation de Gitea via Helm..."
echo "   (Cela peut prendre 3-4 minutes)"
echo ""

helm upgrade --install gitea gitea-charts/gitea \
    --namespace "$NAMESPACE" \
    --version "$GITEA_VERSION" \
    --values /tmp/gitea-values.yaml \
    --wait=false \
    --timeout 15m

echo ""
echo "✅ Gitea installé avec succès"
echo ""

# Attendre que les pods soient prêts
echo "⏳ Attente que tous les pods Gitea soient prêts..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=gitea \
    -n "$NAMESPACE" \
    --timeout=300s 2>/dev/null || true

echo "✅ Pods Gitea prêts"
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                 ✅ GITEA DÉPLOYÉ                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Informations de connexion:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo "   Email:    $ADMIN_EMAIL"
echo ""
echo "⚠️  IMPORTANT: Changez ce mot de passe en production !"
echo ""
echo "🌐 Accès (après configuration Ingress):"
echo "   UI Web:     https://gitea.local.lab:8443"
echo "   Git HTTP:   https://gitea.local.lab:8443/<user>/<repo>.git"
echo "   Git SSH:    ssh://git@gitea.local.lab:2222/<user>/<repo>.git"
echo ""
echo "📝 Prochaines étapes:"
echo "   1. Déployez l'Ingress: kubectl apply -f deploy/argocd-gitea-ingress.yaml"
echo "   2. Démarrez le port-forward: ./scripts/start-ingress-portforward.sh"
echo "   3. Ajoutez à /etc/hosts: 127.0.0.1 gitea.local.lab"
echo "   4. Configurez l'intégration avec ArgoCD:"
echo "      ./scripts/configure-argocd-gitea.sh"
echo ""
echo "🔧 Commandes utiles:"
echo "   # Port-forward direct (si besoin)"
echo "   kubectl port-forward -n gitea svc/gitea-http 3000:3000"
echo ""
echo "   # Voir les logs"
echo "   kubectl logs -n gitea -l app.kubernetes.io/name=gitea -f"
echo ""
echo "   # Configuration Git locale"
echo "   git config --global user.name \"$ADMIN_USER\""
echo "   git config --global user.email \"$ADMIN_EMAIL\""
echo ""
echo "   # Cloner un repo (exemple)"
echo "   git clone https://gitea.local.lab:8443/demo/my-app.git"
echo ""
echo "📊 Status du déploiement:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""
echo "📊 Services exposés:"
kubectl get svc -n "$NAMESPACE"
echo ""
