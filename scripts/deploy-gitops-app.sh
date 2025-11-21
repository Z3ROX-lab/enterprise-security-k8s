#!/bin/bash

# =============================================================================
# SCRIPT: deploy-gitops-app.sh
# DESCRIPTION: Automatise le déploiement d'une application via le pipeline GitOps
#              (Gitea + ArgoCD)
#
# WORKFLOW:
#   1. Initialise un repo Git local dans le dossier de l'application
#   2. Pousse le code vers Gitea (serveur Git)
#   3. Crée une application ArgoCD qui sync automatiquement depuis Gitea
#   4. ArgoCD déploie l'application dans Kubernetes
#
# USAGE:
#   ./scripts/deploy-gitops-app.sh <app-name> [namespace]
#
# EXEMPLES:
#   ./scripts/deploy-gitops-app.sh demo-nginx
#   ./scripts/deploy-gitops-app.sh demo-nginx my-namespace
#   ./scripts/deploy-gitops-app.sh demo-security default
#
# PRÉREQUIS:
#   - Gitea déployé et accessible (https://gitea.local.lab:8443)
#   - ArgoCD déployé et accessible
#   - Organisation "demo" créée dans Gitea
#   - Repository créé dans Gitea (même nom que l'app)
#
# =============================================================================

set -e  # Arrêter le script en cas d'erreur

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration par défaut
GITEA_URL="https://gitea.local.lab:8443"
GITEA_INTERNAL_URL="http://gitea-http.gitea.svc.cluster.local:3000"
GITEA_ORG="demo"
GITEA_USER="gitea-admin"
GITEA_EMAIL="admin@gitea.local.lab"
DEFAULT_NAMESPACE="default"

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -----------------------------------------------------------------------------
# FONCTIONS
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     $1"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}▶ ÉTAPE $1:${NC} $2"
    echo ""
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_explanation() {
    echo -e "${BLUE}   📖 $1${NC}"
}

# -----------------------------------------------------------------------------
# VÉRIFICATION DES ARGUMENTS
# -----------------------------------------------------------------------------

if [ -z "$1" ]; then
    print_error "Usage: $0 <app-name> [namespace]"
    echo ""
    echo "  app-name:  Nom de l'application (ex: demo-nginx)"
    echo "  namespace: Namespace Kubernetes (défaut: default)"
    echo ""
    echo "Exemples:"
    echo "  $0 demo-nginx"
    echo "  $0 demo-security default"
    exit 1
fi

APP_NAME="$1"
NAMESPACE="${2:-$DEFAULT_NAMESPACE}"
APP_DIR="$PROJECT_ROOT/gitops-apps/$APP_NAME"
ARGOCD_APP_FILE="$PROJECT_ROOT/gitops-apps/argocd-apps/${APP_NAME}-app.yaml"

# -----------------------------------------------------------------------------
# VÉRIFICATIONS PRÉLIMINAIRES
# -----------------------------------------------------------------------------

print_header "Déploiement GitOps: $APP_NAME"

echo "📋 Configuration:"
echo "   Application:     $APP_NAME"
echo "   Namespace K8s:   $NAMESPACE"
echo "   Dossier source:  $APP_DIR"
echo "   Gitea URL:       $GITEA_URL"
echo "   Gitea Org:       $GITEA_ORG"
echo ""

# Vérifier que le dossier de l'application existe
if [ ! -d "$APP_DIR" ]; then
    print_error "Le dossier $APP_DIR n'existe pas"
    echo "   Créez d'abord l'application dans gitops-apps/$APP_NAME/"
    exit 1
fi

# Vérifier que le fichier ArgoCD Application existe
if [ ! -f "$ARGOCD_APP_FILE" ]; then
    print_error "Le fichier ArgoCD $ARGOCD_APP_FILE n'existe pas"
    echo "   Créez d'abord le fichier dans gitops-apps/argocd-apps/${APP_NAME}-app.yaml"
    exit 1
fi

# Vérifier kubectl
if ! kubectl cluster-info &>/dev/null; then
    print_error "Impossible de se connecter au cluster Kubernetes"
    exit 1
fi

print_success "Vérifications préliminaires OK"
echo ""

# =============================================================================
# ÉTAPE 1: INITIALISER LE REPO GIT LOCAL
# =============================================================================

print_step "1" "Initialisation du repo Git local"

print_explanation "Git est un système de contrôle de version qui track les modifications"
print_explanation "du code. On initialise un repo local pour pouvoir pousser vers Gitea."
echo ""

cd "$APP_DIR"

# Supprimer l'ancien .git s'il existe
if [ -d ".git" ]; then
    print_info "Suppression de l'ancien repo Git..."
    rm -rf .git
fi

# Initialiser le repo
print_info "Initialisation du nouveau repo Git..."
git init

# Configurer l'identité Git (locale au repo)
# Cela définit qui est l'auteur des commits
print_info "Configuration de l'identité Git..."
git config user.name "$GITEA_USER"
git config user.email "$GITEA_EMAIL"

# Ajouter tous les fichiers au staging area
# Le staging area est une zone intermédiaire avant le commit
print_info "Ajout des fichiers au staging..."
git add .

# Créer le premier commit
# Un commit est un snapshot de l'état du code à un moment donné
print_info "Création du commit initial..."
git commit -m "Initial commit: $APP_NAME application"

# Renommer la branche en 'main' (convention moderne au lieu de 'master')
git branch -m main

print_success "Repo Git local initialisé"
echo ""

# =============================================================================
# ÉTAPE 2: CONFIGURER ET POUSSER VERS GITEA
# =============================================================================

print_step "2" "Push vers Gitea"

print_explanation "Gitea est un serveur Git self-hosted (comme GitHub mais local)."
print_explanation "On pousse le code vers Gitea pour qu'ArgoCD puisse le récupérer."
echo ""

# Désactiver la vérification SSL (car on utilise des certificats auto-signés)
print_info "Configuration SSL (désactivé pour dev)..."
git config http.sslVerify false

# Ajouter le remote (l'URL du repo distant sur Gitea)
# Le remote est la référence vers le repo sur le serveur
REMOTE_URL="$GITEA_URL/$GITEA_ORG/$APP_NAME.git"
print_info "Ajout du remote Gitea: $REMOTE_URL"

# Supprimer l'ancien remote s'il existe
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"

# Pousser vers Gitea
# -u (--set-upstream) : lie la branche locale à la branche distante
print_info "Push vers Gitea..."
echo ""
echo "   ⚠️  Si demandé, utilisez:"
echo "      Username: $GITEA_USER"
echo "      Password: gitea123!"
echo ""

if git push -u origin main; then
    print_success "Code poussé vers Gitea"
else
    print_error "Échec du push vers Gitea"
    echo ""
    echo "   Vérifiez que:"
    echo "   1. Le repo '$APP_NAME' existe dans l'organisation '$GITEA_ORG' sur Gitea"
    echo "   2. Les credentials sont corrects"
    echo "   3. Gitea est accessible: $GITEA_URL"
    exit 1
fi

echo ""

# =============================================================================
# ÉTAPE 3: DÉPLOYER L'APPLICATION ARGOCD
# =============================================================================

print_step "3" "Déploiement de l'application ArgoCD"

print_explanation "ArgoCD est un contrôleur GitOps qui synchronise automatiquement"
print_explanation "l'état du cluster Kubernetes avec le code dans Git."
print_explanation "Quand vous modifiez le code dans Gitea, ArgoCD détecte le changement"
print_explanation "et met à jour automatiquement l'application dans Kubernetes."
echo ""

# Appliquer le manifest ArgoCD Application
print_info "Création de l'application ArgoCD..."
kubectl apply -f "$ARGOCD_APP_FILE"

print_success "Application ArgoCD créée"
echo ""

# =============================================================================
# ÉTAPE 4: VÉRIFIER LE DÉPLOIEMENT
# =============================================================================

print_step "4" "Vérification du déploiement"

print_explanation "ArgoCD va maintenant synchroniser le code depuis Gitea vers Kubernetes."
print_explanation "Cela peut prendre 1-2 minutes (polling toutes les 3 minutes par défaut)."
echo ""

# Attendre que l'application soit créée
print_info "Attente de la synchronisation ArgoCD..."
sleep 5

# Afficher le status de l'application ArgoCD
echo "📊 Status de l'application ArgoCD:"
kubectl get application "$APP_NAME" -n argocd 2>/dev/null || echo "   (en cours de création...)"
echo ""

# Afficher les pods de l'application
echo "📊 Pods de l'application (namespace: $NAMESPACE):"
kubectl get pods -n "$NAMESPACE" -l "app=$APP_NAME" 2>/dev/null || echo "   (pas encore créés - ArgoCD sync en cours)"
echo ""

# =============================================================================
# RÉSUMÉ ET PROCHAINES ÉTAPES
# =============================================================================

print_header "DÉPLOIEMENT TERMINÉ !"

echo "📋 Résumé:"
echo "   ✅ Code poussé vers Gitea"
echo "   ✅ Application ArgoCD créée"
echo "   ⏳ Synchronisation en cours..."
echo ""

echo "🌐 Accès:"
echo "   Gitea:  $GITEA_URL/$GITEA_ORG/$APP_NAME"
echo "   ArgoCD: https://argocd.local.lab:8443"
echo ""

echo "🔄 Pour tester le pipeline GitOps:"
echo ""
echo "   1. Modifiez le code:"
echo "      cd $APP_DIR"
echo "      # Exemple: changer replicas de 2 à 5"
echo "      sed -i 's/replicas: 2/replicas: 5/' deployment.yaml"
echo ""
echo "   2. Commit et push:"
echo "      git add ."
echo "      git commit -m 'Scale to 5 replicas'"
echo "      git push"
echo ""
echo "   3. Observez:"
echo "      - ArgoCD UI: https://argocd.local.lab:8443"
echo "      - Pods: kubectl get pods -l app=$APP_NAME -w"
echo ""

echo "🔧 Commandes utiles:"
echo "   # Forcer sync ArgoCD"
echo "   kubectl patch application $APP_NAME -n argocd --type merge -p '{\"operation\":{\"sync\":{}}}'"
echo ""
echo "   # Voir les logs ArgoCD"
echo "   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50"
echo ""
echo "   # Supprimer l'application"
echo "   kubectl delete application $APP_NAME -n argocd"
echo ""
