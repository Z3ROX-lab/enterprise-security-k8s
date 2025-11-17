#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           Déploiement ArgoCD (GitOps)                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
NAMESPACE="argocd"
ARGOCD_VERSION="7.7.12"  # Dernière version stable Helm chart

echo "📦 Configuration:"
echo "   Namespace: $NAMESPACE"
echo "   Helm Chart Version: $ARGOCD_VERSION"
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

# Ajouter le repo Helm ArgoCD
echo "📦 Ajout du repository Helm ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
echo "✅ Repository ajouté"
echo ""

# Créer le fichier values.yaml pour ArgoCD
echo "⚙️  Création de la configuration ArgoCD..."
cat > /tmp/argocd-values.yaml <<EOF
# Configuration ArgoCD pour enterprise-security-k8s
global:
  domain: argocd.local.lab

# Désactiver HA pour la démo (économie de ressources)
redis-ha:
  enabled: false

controller:
  replicas: 1

server:
  replicas: 1
  service:
    type: ClusterIP
  # Configuration Ingress (sera créé séparément)
  ingress:
    enabled: false
  # Désactiver le certificat auto-signé (on utilise Ingress TLS)
  certificate:
    enabled: false
  # Exposer les métriques Prometheus
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: argocd
  # Configuration RBAC
  rbacConfig:
    policy.default: role:readonly
    policy.csv: |
      g, argocd-admins, role:admin
  # Configuration pour UI
  config:
    repositories: |
      # Les repos seront ajoutés via le script configure-argocd-gitea.sh
    # Désactiver l'anonymat
    users.anonymous.enabled: "false"

repoServer:
  replicas: 1
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

applicationSet:
  replicas: 1

# Désactiver Dex (on utilisera l'auth local pour la démo)
dex:
  enabled: false

# Notifications (optionnel)
notifications:
  enabled: true
  argocdUrl: https://argocd.local.lab:8443

# Configuration des ressources (adapté pour la démo)
controller:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi

server:
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

repoServer:
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Configuration de la base de données (utiliser Redis simple)
redis:
  enabled: true
  resources:
    limits:
      cpu: 200m
      memory: 128Mi
    requests:
      cpu: 100m
      memory: 64Mi
EOF

echo "✅ Configuration créée"
echo ""

# Installer ArgoCD via Helm
echo "🚀 Installation d'ArgoCD via Helm..."
echo "   (Cela peut prendre 2-3 minutes)"
echo ""

helm upgrade --install argocd argo/argo-cd \
    --namespace "$NAMESPACE" \
    --version "$ARGOCD_VERSION" \
    --values /tmp/argocd-values.yaml \
    --wait \
    --timeout 10m

echo ""
echo "✅ ArgoCD installé avec succès"
echo ""

# Attendre que les pods soient prêts
echo "⏳ Attente que tous les pods ArgoCD soient prêts..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    -n "$NAMESPACE" \
    --timeout=300s 2>/dev/null || true

echo "✅ Pods ArgoCD prêts"
echo ""

# Récupérer le mot de passe admin initial
echo "🔑 Récupération du mot de passe admin ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "⚠️  Le secret initial n'existe pas encore, attente..."
    sleep 10
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                ✅ ARGOCD DÉPLOYÉ                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Informations de connexion:"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Sauvegardez ce mot de passe !"
echo ""
echo "🌐 Accès (après configuration Ingress):"
echo "   UI Web:  https://argocd.local.lab:8443"
echo "   API:     https://argocd.local.lab:8443"
echo ""
echo "📝 Prochaines étapes:"
echo "   1. Déployez l'Ingress: kubectl apply -f deploy/argocd-gitea-ingress.yaml"
echo "   2. Démarrez le port-forward: ./scripts/start-ingress-portforward.sh"
echo "   3. Ajoutez à /etc/hosts: 127.0.0.1 argocd.local.lab"
echo "   4. Installez ArgoCD CLI (optionnel):"
echo "      brew install argocd     # macOS"
echo "      # Ou télécharger depuis https://argo-cd.readthedocs.io/en/stable/cli_installation/"
echo ""
echo "🔧 Commandes utiles:"
echo "   # Port-forward direct (si besoin)"
echo "   kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo ""
echo "   # Login CLI"
echo "   argocd login argocd.local.lab:8443 --username admin --password '$ARGOCD_PASSWORD' --insecure"
echo ""
echo "   # Lister les applications"
echo "   argocd app list"
echo ""
echo "   # Voir les logs"
echo "   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f"
echo ""
echo "📊 Status du déploiement:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""
