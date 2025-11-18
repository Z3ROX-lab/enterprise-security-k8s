#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║    Configuration Accès ArgoCD + Gitea (Ingress)          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Déterminer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Vérifier que kubectl fonctionne
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Impossible de se connecter au cluster Kubernetes"
    exit 1
fi

# Vérifier qu'ArgoCD est déployé
echo "🔍 Vérification du déploiement ArgoCD..."
if ! kubectl get namespace argocd &>/dev/null; then
    echo "❌ ArgoCD n'est pas déployé"
    echo "   Déployez-le d'abord: ./scripts/deploy-argocd.sh"
    exit 1
fi

if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo "❌ ArgoCD server n'est pas déployé"
    exit 1
fi

echo "✅ ArgoCD est déployé"
echo ""

# Vérifier que Gitea est déployé
echo "🔍 Vérification du déploiement Gitea..."
if ! kubectl get namespace gitea &>/dev/null; then
    echo "❌ Gitea n'est pas déployé"
    echo "   Déployez-le d'abord: ./scripts/deploy-gitea.sh"
    exit 1
fi

if ! kubectl get deployment gitea -n gitea &>/dev/null; then
    echo "❌ Gitea n'est pas déployé"
    exit 1
fi

echo "✅ Gitea est déployé"
echo ""

# Déployer les Ingress resources
echo "🌐 Déploiement des Ingress resources..."
kubectl apply -f "$PROJECT_ROOT/deploy/argocd-gitea-ingress.yaml"

echo "✅ Ingress déployés"
echo ""

# Vérifier les Ingress
echo "📋 Ingress créés:"
echo ""
echo "  ArgoCD:"
kubectl get ingress -n argocd
echo ""
echo "  Gitea:"
kubectl get ingress -n gitea
echo ""

# Récupérer le mot de passe ArgoCD
echo "🔑 Récupération du mot de passe ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "⚠️  Impossible de récupérer le mot de passe ArgoCD"
    echo "   Il a peut-être été supprimé (normal si ArgoCD a été déployé il y a longtemps)"
    ARGOCD_PASSWORD="<mot de passe non disponible - utilisez 'argocd admin initial-password -n argocd'>"
fi

echo "✅ Credentials récupérés"
echo ""

# Instructions pour /etc/hosts
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              CONFIGURATION /etc/hosts                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Ajoutez ces lignes dans votre fichier hosts Windows:"
echo ""
echo "   Fichier: C:\\Windows\\System32\\drivers\\etc\\hosts"
echo ""
echo "   # ArgoCD et Gitea"
echo "   127.0.0.1 argocd.local.lab"
echo "   127.0.0.1 gitea.local.lab"
echo ""
echo "⚠️  Vous devez éditer ce fichier en tant qu'Administrateur !"
echo ""

read -p "Avez-vous ajouté ces lignes au fichier hosts ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "⚠️  Ajoutez d'abord les entrées au fichier hosts, puis relancez ce script"
    echo "   Ou continuez manuellement avec:"
    echo "   ./scripts/start-ingress-portforward.sh"
    exit 0
fi

echo ""
echo "🚀 Démarrage du port-forward Ingress..."
echo ""

# Vérifier si screen est installé
if ! command -v screen &> /dev/null; then
    echo "⚠️  'screen' n'est pas installé. Lancement direct du port-forward..."
    echo "   Pour une solution en arrière-plan, installez screen:"
    echo "   sudo apt install screen -y"
    echo ""

    read -p "Lancer le port-forward en mode direct ? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "📡 Lancement du port-forward (Ctrl+C pour arrêter)..."
        echo ""
        "$SCRIPT_DIR/port-forward-ingress-stable.sh"
    fi
else
    # Lancer le port-forward avec screen
    "$SCRIPT_DIR/start-ingress-portforward.sh"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                 ✅ CONFIGURATION TERMINÉE                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 URLs d'accès:"
echo ""
echo "   🔶 ArgoCD:"
echo "      URL:      https://argocd.local.lab:8443"
echo "      Username: admin"
echo "      Password: $ARGOCD_PASSWORD"
echo ""
echo "   🔷 Gitea:"
echo "      URL:      https://gitea.local.lab:8443"
echo "      Username: gitea-admin"
echo "      Password: gitea123!"
echo ""
echo "📝 Prochaines étapes:"
echo ""
echo "   1. Testez l'accès à ArgoCD:"
echo "      https://argocd.local.lab:8443"
echo ""
echo "   2. Testez l'accès à Gitea:"
echo "      https://gitea.local.lab:8443"
echo ""
echo "   3. Configurez l'intégration ArgoCD ↔ Gitea:"
echo "      ./scripts/configure-argocd-gitea.sh"
echo ""
echo "   4. Consultez le guide rapide:"
echo "      cat GITOPS-QUICKSTART.md"
echo ""
