#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Configuration ArgoCD + Gitea (Pipeline GitOps)      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
GITEA_NAMESPACE="gitea"
ARGOCD_NAMESPACE="argocd"
GITEA_URL="http://gitea-http.gitea.svc.cluster.local:3000"
GITEA_EXTERNAL_URL="https://gitea.local.lab:8443"
GITEA_ADMIN="gitea-admin"
GITEA_PASSWORD="gitea123!"

echo "📦 Configuration:"
echo "   Gitea URL (interne):  $GITEA_URL"
echo "   Gitea URL (externe):  $GITEA_EXTERNAL_URL"
echo "   Gitea Admin:          $GITEA_ADMIN"
echo ""

# Vérifier que kubectl fonctionne
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Impossible de se connecter au cluster Kubernetes"
    exit 1
fi

# Vérifier que Gitea est déployé
echo "🔍 Vérification du déploiement Gitea..."
if ! kubectl get namespace "$GITEA_NAMESPACE" &>/dev/null; then
    echo "❌ Namespace $GITEA_NAMESPACE n'existe pas"
    echo "   Déployez d'abord Gitea: ./scripts/deploy-gitea.sh"
    exit 1
fi

if ! kubectl get deployment gitea -n "$GITEA_NAMESPACE" &>/dev/null; then
    echo "❌ Gitea n'est pas déployé"
    echo "   Déployez d'abord Gitea: ./scripts/deploy-gitea.sh"
    exit 1
fi

echo "✅ Gitea est déployé"
echo ""

# Vérifier que ArgoCD est déployé
echo "🔍 Vérification du déploiement ArgoCD..."
if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    echo "❌ Namespace $ARGOCD_NAMESPACE n'existe pas"
    echo "   Déployez d'abord ArgoCD: ./scripts/deploy-argocd.sh"
    exit 1
fi

if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &>/dev/null; then
    echo "❌ ArgoCD n'est pas déployé"
    echo "   Déployez d'abord ArgoCD: ./scripts/deploy-argocd.sh"
    exit 1
fi

echo "✅ ArgoCD est déployé"
echo ""

# Récupérer le mot de passe ArgoCD
echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "❌ Impossible de récupérer le mot de passe ArgoCD"
    exit 1
fi

echo "✅ Mot de passe ArgoCD récupéré"
echo ""

# Créer une organisation dans Gitea pour les démos
echo "📁 Création de l'organisation 'demo' dans Gitea..."
echo "   (peut échouer si elle existe déjà - c'est normal)"
echo ""

# On utilise kubectl exec pour créer l'organisation via l'API Gitea
kubectl exec -n "$GITEA_NAMESPACE" deployment/gitea -- \
    gitea admin user create \
    --username demo-user \
    --password demo123! \
    --email demo@gitea.local.lab \
    --must-change-password=false \
    --admin 2>/dev/null || echo "   ℹ️  User demo-user existe peut-être déjà"

echo ""

# Créer un token d'accès Gitea pour ArgoCD
echo "🔑 Création d'un token d'accès Gitea pour ArgoCD..."

# Créer le token via l'API Gitea
GITEA_POD=$(kubectl get pod -n "$GITEA_NAMESPACE" -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')

# Note: Dans une vraie démo, on créerait le token via l'API REST
# Pour l'instant, on va créer un secret Kubernetes pour ArgoCD
echo "   Creating Kubernetes secret for Gitea credentials..."

kubectl create secret generic gitea-repo-creds \
    -n "$ARGOCD_NAMESPACE" \
    --from-literal=url="$GITEA_URL" \
    --from-literal=username="$GITEA_ADMIN" \
    --from-literal=password="$GITEA_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le label pour ArgoCD
kubectl label secret gitea-repo-creds \
    -n "$ARGOCD_NAMESPACE" \
    argocd.argoproj.io/secret-type=repository \
    --overwrite

echo "✅ Secret créé pour les credentials Gitea"
echo ""

# Configurer ArgoCD pour utiliser Gitea
echo "⚙️  Configuration d'ArgoCD pour utiliser Gitea..."

# Créer un ConfigMap pour la configuration du repo
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # Configuration des repositories
  repositories: |
    - url: $GITEA_URL
      name: gitea-local
      type: git
      insecure: true
  # Configuration de l'URL
  url: https://argocd.local.lab:8443
  # Activer les repo credentials
  repository.credentials: |
    - url: $GITEA_URL
      usernameSecret:
        name: gitea-repo-creds
        key: username
      passwordSecret:
        name: gitea-repo-creds
        key: password
EOF

echo "✅ Configuration ArgoCD mise à jour"
echo ""

# Redémarrer ArgoCD pour appliquer la configuration
echo "🔄 Redémarrage d'ArgoCD pour appliquer la configuration..."
kubectl rollout restart deployment argocd-server -n "$ARGOCD_NAMESPACE"
kubectl rollout restart deployment argocd-repo-server -n "$ARGOCD_NAMESPACE"

echo "   Attente du redémarrage..."
kubectl rollout status deployment argocd-server -n "$ARGOCD_NAMESPACE" --timeout=120s
kubectl rollout status deployment argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=120s

echo "✅ ArgoCD redémarré"
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ CONFIGURATION TERMINÉE                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Informations de connexion:"
echo ""
echo "   🔷 Gitea:"
echo "      URL:      $GITEA_EXTERNAL_URL"
echo "      User:     $GITEA_ADMIN"
echo "      Password: $GITEA_PASSWORD"
echo ""
echo "   🔶 ArgoCD:"
echo "      URL:      https://argocd.local.lab:8443"
echo "      User:     admin"
echo "      Password: $ARGOCD_PASSWORD"
echo ""
echo "📝 Prochaines étapes:"
echo ""
echo "   1. Créez un repository dans Gitea:"
echo "      - Allez sur $GITEA_EXTERNAL_URL"
echo "      - Connectez-vous avec $GITEA_ADMIN / $GITEA_PASSWORD"
echo "      - Créez une nouvelle organisation 'demo'"
echo "      - Créez un nouveau repo 'demo-app'"
echo ""
echo "   2. Poussez une application de démonstration:"
echo "      cd $PROJECT_ROOT/gitops-apps/demo-nginx"
echo "      git init"
echo "      git remote add origin $GITEA_EXTERNAL_URL/demo/demo-app.git"
echo "      git add ."
echo "      git commit -m 'Initial commit'"
echo "      git push -u origin main"
echo ""
echo "   3. Créez une application ArgoCD:"
echo "      kubectl apply -f $PROJECT_ROOT/gitops-apps/argocd-apps/demo-nginx-app.yaml"
echo ""
echo "   4. Visualisez dans ArgoCD:"
echo "      - Allez sur https://argocd.local.lab:8443"
echo "      - Connectez-vous avec admin / $ARGOCD_PASSWORD"
echo "      - Vous verrez l'application 'demo-nginx'"
echo ""
echo "🎬 Scénario de démo:"
echo "   1. Modifiez replicas dans demo-nginx/deployment.yaml"
echo "   2. Commit & push vers Gitea"
echo "   3. ArgoCD détecte le changement et sync automatiquement"
echo "   4. Observez dans Grafana les nouvelles pods qui apparaissent"
echo "   5. Falco/Prometheus enregistrent tous les événements"
echo ""
echo "🔧 Commandes utiles:"
echo "   # Login ArgoCD CLI"
echo "   argocd login argocd.local.lab:8443 --username admin --password '$ARGOCD_PASSWORD' --insecure"
echo ""
echo "   # Créer une app via CLI"
echo "   argocd app create demo-nginx \\"
echo "     --repo $GITEA_EXTERNAL_URL/demo/demo-app.git \\"
echo "     --path . \\"
echo "     --dest-server https://kubernetes.default.svc \\"
echo "     --dest-namespace default"
echo ""
