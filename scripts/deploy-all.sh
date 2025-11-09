#!/bin/bash
#
# Enterprise Security Stack - Script de déploiement complet
# Usage: ./scripts/deploy-all.sh [--skip-infra] [--skip-security]
#
# Ce script déploie la stack complète de sécurité entreprise :
# - Infrastructure Kubernetes (Kind)
# - Stack Monitoring (Prometheus, Grafana, ELK)
# - Stack Security (IAM, EDR, Network Security, CSPM)
#

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variables
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
SKIP_INFRA=false
SKIP_SECURITY=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-infra)
            SKIP_INFRA=true
            shift
            ;;
        --skip-security)
            SKIP_SECURITY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-infra] [--skip-security]"
            echo ""
            echo "Options:"
            echo "  --skip-infra      Skip infrastructure deployment (Kind cluster)"
            echo "  --skip-security   Skip security stack deployment"
            echo "  -h, --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Banner
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Enterprise Security Stack - Déploiement Complet        ║
║   Cloud-Native Security Architecture on Kubernetes       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Fonction de log
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

log_step() {
    echo ""
    echo -e "${MAGENTA}━━━ $1 ━━━${NC}"
}

# Vérification des prérequis
check_prerequisites() {
    log_step "Vérification des prérequis"

    local missing_tools=()

    for tool in docker kubectl helm terraform kind; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=("$tool")
            log_error "$tool n'est pas installé"
        else
            local version=$($tool version --short 2>/dev/null || $tool --version 2>/dev/null | head -n1)
            log_success "$tool installé: $version"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Outils manquants: ${missing_tools[*]}"
        log_info "Installez les outils manquants avant de continuer"
        exit 1
    fi

    # Vérifier Docker
    if ! docker info &> /dev/null; then
        log_error "Docker n'est pas démarré"
        exit 1
    fi
    log_success "Docker fonctionne"
}

# Déploiement infrastructure avec Terraform
deploy_infrastructure() {
    if [ "$SKIP_INFRA" = true ]; then
        log_warning "Skip infrastructure deployment (--skip-infra)"
        return 0
    fi

    log_step "Déploiement Infrastructure avec Terraform"

    cd "$TERRAFORM_DIR"

    log_info "Terraform init..."
    terraform init -upgrade

    log_info "Terraform plan..."
    terraform plan -out=tfplan

    log_info "Terraform apply..."
    terraform apply tfplan

    log_success "Infrastructure déployée"

    # Exporter le kubeconfig
    local kubeconfig_path=$(terraform output -raw kubeconfig_path)
    export KUBECONFIG=$kubeconfig_path
    log_info "KUBECONFIG défini: $kubeconfig_path"

    # Attendre que le cluster soit prêt
    log_info "Attente de la disponibilité du cluster..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s

    log_success "Cluster Kubernetes prêt"
    kubectl get nodes
}

# Configuration avec Ansible
configure_cluster() {
    log_step "Configuration du cluster avec Ansible"

    cd "$ANSIBLE_DIR"

    log_info "Vérification de la connexion au cluster..."
    ansible-playbook playbooks/site.yml --check

    log_info "Application de la configuration..."
    ansible-playbook playbooks/site.yml

    log_success "Cluster configuré"
}

# Déploiement stack de sécurité
deploy_security_stack() {
    if [ "$SKIP_SECURITY" = true ]; then
        log_warning "Skip security stack deployment (--skip-security)"
        return 0
    fi

    log_step "Déploiement de la Stack de Sécurité"

    log_info "Attente du déploiement des composants de sécurité..."

    # Attendre Keycloak
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=keycloak \
        -n security-iam --timeout=600s 2>/dev/null && \
        log_success "Keycloak prêt" || log_warning "Keycloak timeout"

    # Attendre Vault
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vault \
        -n security-iam --timeout=300s 2>/dev/null && \
        log_success "Vault prêt" || log_warning "Vault timeout"

    # Attendre Elasticsearch
    kubectl wait --for=condition=Ready pods -l app=elasticsearch-master \
        -n security-siem --timeout=600s 2>/dev/null && \
        log_success "Elasticsearch prêt" || log_warning "Elasticsearch timeout"

    # Attendre Kibana
    kubectl wait --for=condition=Ready pods -l app=kibana \
        -n security-siem --timeout=600s 2>/dev/null && \
        log_success "Kibana prêt" || log_warning "Kibana timeout"

    # Attendre Prometheus
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=prometheus \
        -n security-siem --timeout=600s 2>/dev/null && \
        log_success "Prometheus prêt" || log_warning "Prometheus timeout"

    # Attendre Grafana
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=grafana \
        -n security-siem --timeout=600s 2>/dev/null && \
        log_success "Grafana prêt" || log_warning "Grafana timeout"

    # Attendre Falco
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=falco \
        -n security-detection --timeout=600s 2>/dev/null && \
        log_success "Falco prêt" || log_warning "Falco timeout"

    log_success "Stack de sécurité déployée"
}

# Afficher le résumé
show_summary() {
    log_step "Résumé du Déploiement"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Déploiement terminé avec succès ! ✓             ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "📊 Composants déployés:"
    echo ""

    local namespaces=("security-iam" "security-siem" "security-detection" "security-network")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
            local ready_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            echo -e "  ${GREEN}✓${NC} Namespace: $ns ($ready_count/$pod_count pods ready)"
        fi
    done

    echo ""
    log_info "🌐 Accès aux interfaces:"
    echo ""

    cat << 'ACCESS'
# Kibana (SIEM)
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601
→ http://localhost:5601

# Grafana (Monitoring)
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
→ http://localhost:3000 (admin/admin123)

# Keycloak (IAM)
kubectl port-forward -n security-iam svc/keycloak 8080:80
→ http://localhost:8080 (admin/admin123)

# Vault (Secrets)
kubectl port-forward -n security-iam svc/vault 8200:8200
→ http://localhost:8200 (token: root)

# Falco UI
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
→ http://localhost:2802

# Wazuh Dashboard
kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:5601
→ https://localhost:5443
ACCESS

    echo ""
    log_info "🔍 Commandes utiles:"
    echo ""

    cat << 'COMMANDS'
# Voir tous les pods
kubectl get pods --all-namespaces

# Vérifier les NetworkPolicies
kubectl get networkpolicies --all-namespaces

# Voir les événements Falco
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=50

# Tester les NetworkPolicies
kubectl run test-pod --rm -it --image=busybox -n demo-app -- sh

# Voir les vulnérabilités détectées par Trivy
kubectl get vulnerabilityreports --all-namespaces
COMMANDS

    echo ""
    log_info "📚 Documentation:"
    echo "  - README.md - Vue d'ensemble"
    echo "  - docs/architecture.md - Architecture détaillée"
    echo "  - docs/WINDOWS11-SETUP.md - Guide Windows 11"
    echo "  - docs/equivalences.md - Mapping OSS ↔ Commercial"

    echo ""
    log_info "🧹 Pour nettoyer:"
    echo "  cd $TERRAFORM_DIR && terraform destroy -auto-approve"

    echo ""
}

# Fonction de nettoyage en cas d'erreur
cleanup_on_error() {
    log_error "Une erreur s'est produite durant le déploiement"
    log_info "Logs disponibles ci-dessus"
    exit 1
}

trap cleanup_on_error ERR

# Exécution principale
main() {
    local start_time=$(date +%s)

    check_prerequisites
    deploy_infrastructure
    configure_cluster
    deploy_security_stack
    show_summary

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    log_success "Déploiement terminé en ${duration}s"
    echo ""
}

main "$@"
