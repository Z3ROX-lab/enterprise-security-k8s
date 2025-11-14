#!/bin/bash
#
# Recreate Kind Cluster with Port Mapping
#
# ⚠️  ATTENTION: Ce script DÉTRUIT le cluster actuel et le recrée
#
# Usage: ./scripts/recreate-kind-with-port-mapping.sh
#

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Variables
CLUSTER_NAME="security-lab"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Fonctions de log
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Banner
clear
echo -e "${RED}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ⚠️  ATTENTION - Destruction du cluster actuel          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_warning "Ce script va DÉTRUIRE le cluster Kind actuel et le recréer"
log_warning "avec le mapping des ports 80/443 pour un accès direct."
echo ""
log_info "Toutes les données actuelles seront PERDUES."
log_info "Vous devrez redéployer la stack complète après."
echo ""

read -p "Êtes-vous sûr de vouloir continuer ? (yes/no) " -r
echo ""

if [[ ! $REPLY =~ ^(yes|YES)$ ]]; then
    log_info "Opération annulée"
    exit 0
fi

log_warning "Dernière chance ! Tapez 'DESTROY' pour confirmer:"
read -r CONFIRM

if [ "$CONFIRM" != "DESTROY" ]; then
    log_info "Opération annulée"
    exit 0
fi

# Détection du cluster existant
log_info "Recherche du cluster existant..."

EXISTING_CLUSTER=$(kind get clusters 2>/dev/null | grep -E "security-lab|kind" | head -n1 || echo "")

if [ -n "$EXISTING_CLUSTER" ]; then
    log_info "Cluster trouvé: $EXISTING_CLUSTER"
    CLUSTER_NAME="$EXISTING_CLUSTER"
else
    log_warning "Aucun cluster Kind trouvé, création d'un nouveau: $CLUSTER_NAME"
fi

# Sauvegarde de la configuration actuelle (optionnel)
if [ -n "$EXISTING_CLUSTER" ]; then
    log_info "Sauvegarde de kubeconfig..."
    mkdir -p "$PROJECT_ROOT/backups"
    kubectl config view --raw > "$PROJECT_ROOT/backups/kubeconfig-$(date +%Y%m%d-%H%M%S).yaml" || true
    log_success "Kubeconfig sauvegardé dans backups/"
fi

# Destruction du cluster
if [ -n "$EXISTING_CLUSTER" ]; then
    log_warning "Destruction du cluster $CLUSTER_NAME..."
    kind delete cluster --name "$CLUSTER_NAME" || {
        log_error "Échec de la destruction du cluster"
        exit 1
    }
    log_success "Cluster détruit"
    sleep 2
fi

# Création du nouveau cluster avec port mapping
log_info "Création du nouveau cluster Kind avec mapping ports 80/443..."

cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
- role: worker
- role: worker
EOF

if [ $? -ne 0 ]; then
    log_error "Échec de la création du cluster"
    exit 1
fi

log_success "Cluster Kind créé avec succès"

# Vérification
log_info "Vérification du cluster..."
kubectl cluster-info
kubectl get nodes

log_success "Cluster prêt"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Cluster Kind reconfiguré avec succès !          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "📋 Prochaines étapes:"
echo ""
echo "  1. Redéployer la stack complète:"
echo -e "     ${CYAN}./scripts/deploy-complete.sh${NC}"
echo ""
echo "  2. Configurer le fichier Windows hosts (C:\\Windows\\System32\\drivers\\etc\\hosts):"
echo -e "     ${CYAN}127.0.0.1  grafana.local.lab kibana.local.lab prometheus.local.lab falco-ui.local.lab${NC}"
echo ""
echo "  3. Accéder directement aux services (sans port-forward):"
echo "     https://grafana.local.lab/"
echo "     https://kibana.local.lab/"
echo "     https://prometheus.local.lab/"
echo "     https://falco-ui.local.lab/"
echo ""

log_info "🎯 Avec cette configuration, les ports 80/443 de l'hôte sont"
log_info "   directement mappés vers le cluster Kind, donc MetalLB + Ingress"
log_info "   fonctionneront sans port-forward !"
echo ""
