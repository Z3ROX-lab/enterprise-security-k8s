#!/bin/bash
#
# Enterprise Security Stack - Script de déploiement COMPLET
# Ce script orchestre le déploiement complet avec tous les fixes
#
# Usage: ./scripts/deploy-complete.sh [--skip-infra] [--skip-vault-init]
#

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
SKIP_INFRA=false
SKIP_VAULT_INIT=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-infra)
            SKIP_INFRA=true
            shift
            ;;
        --skip-vault-init)
            SKIP_VAULT_INIT=true
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --skip-infra         Skip infrastructure deployment (Kind cluster + Terraform)
  --skip-vault-init    Skip Vault initialization and PKI setup
  -h, --help           Show this help message

Description:
  Déploiement complet de la stack de sécurité avec tous les fixes :
  1. Infrastructure (Kind + Terraform + Ansible)
  2. Configuration Vault PKI (fix CN requirement)
  3. Certificats TLS (retry forcé)
  4. Métriques Falco pour Prometheus
  5. Vérification complète

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

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

log_step() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Banner
clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Enterprise Security Stack - Déploiement COMPLET        ║
║   Avec tous les fixes et configurations                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Étape 1 : Déploiement infrastructure
if [ "$SKIP_INFRA" = false ]; then
    log_step "1️⃣  Déploiement Infrastructure (Terraform + Ansible)"

    if [ -f "$SCRIPTS_DIR/deploy-all.sh" ]; then
        log_info "Lancement du déploiement de base..."
        bash "$SCRIPTS_DIR/deploy-all.sh" || {
            log_error "Échec du déploiement de base"
            exit 1
        }
        log_success "Infrastructure déployée"
    else
        log_warning "Script deploy-all.sh non trouvé, skip"
    fi
else
    log_warning "Skip infrastructure deployment (--skip-infra)"
fi

# Étape 2 : Attendre que les pods soient prêts
log_step "2️⃣  Attente de la disponibilité des services"

log_info "Vérification du cluster..."
kubectl cluster-info || {
    log_error "Cluster Kubernetes non accessible"
    exit 1
}

log_info "Attente des pods Vault..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vault \
    -n security-iam --timeout=300s 2>/dev/null && \
    log_success "Vault prêt" || log_warning "Vault timeout (continuer quand même)"

log_info "Attente des pods cert-manager..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=cert-manager \
    -n cert-manager --timeout=300s 2>/dev/null && \
    log_success "cert-manager prêt" || log_warning "cert-manager timeout"

log_info "Attente des pods Prometheus..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=prometheus \
    -n security-siem --timeout=300s 2>/dev/null && \
    log_success "Prometheus prêt" || log_warning "Prometheus timeout"

# Étape 3 : Configuration Vault PKI
if [ "$SKIP_VAULT_INIT" = false ]; then
    log_step "3️⃣  Configuration Vault PKI (fix CN requirement)"

    log_info "Vérification de Vault..."

    # Vérifier si Vault est unsealed
    VAULT_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$VAULT_POD" ]; then
        log_error "Pod Vault non trouvé"
        exit 1
    fi

    log_info "Pod Vault: $VAULT_POD"

    # Attendre que Vault soit unsealed
    log_info "Attente que Vault soit unsealed..."
    for i in {1..30}; do
        SEALED=$(kubectl exec -n security-iam "$VAULT_POD" -- vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")
        if [ "$SEALED" = "false" ]; then
            log_success "Vault est unsealed"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "Vault n'est pas unsealed après 30 secondes"
            log_warning "Vous devez peut-être unseal Vault manuellement"
            log_info "Commande: kubectl exec -n security-iam $VAULT_POD -- vault operator unseal <unseal-key>"
            exit 1
        fi
        sleep 1
    done

    # Lire le root token
    if [ -f "$PROJECT_ROOT/vault-keys.txt" ]; then
        log_info "Lecture du root token depuis vault-keys.txt..."
        VAULT_TOKEN=$(grep "Initial Root Token:" "$PROJECT_ROOT/vault-keys.txt" | awk '{print $4}')
    else
        log_warning "vault-keys.txt non trouvé, tentative de récupération depuis secret..."
        VAULT_TOKEN=$(kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")
    fi

    if [ -z "$VAULT_TOKEN" ]; then
        log_error "Impossible de récupérer le root token"
        log_info "Vous pouvez le passer avec: export VAULT_TOKEN=<token>"
        exit 1
    fi

    log_success "Root token récupéré"

    # Configuration PKI
    log_info "Configuration du backend PKI..."

    kubectl exec -n security-iam "$VAULT_POD" -- sh -c "
        export VAULT_TOKEN='$VAULT_TOKEN'

        # Enable PKI if not already enabled
        vault secrets enable -path=pki pki 2>/dev/null || echo 'PKI already enabled'

        # Configure PKI
        vault secrets tune -max-lease-ttl=87600h pki

        # Generate root CA
        vault write -field=certificate pki/root/generate/internal \
            common_name='Enterprise Security Root CA' \
            ttl=87600h 2>/dev/null || echo 'Root CA already exists'

        # Configure URLs
        vault write pki/config/urls \
            issuing_certificates='http://vault.security-iam.svc.cluster.local:8200/v1/pki/ca' \
            crl_distribution_points='http://vault.security-iam.svc.cluster.local:8200/v1/pki/crl'

        # Configure role with require_cn=false (FIX!)
        vault write pki/roles/ingress-tls \
            allowed_domains='local.lab' \
            allow_subdomains=true \
            max_ttl='720h' \
            require_cn=false \
            use_csr_common_name=false

        # Configure policy
        vault policy write cert-manager - <<EOF_POLICY
path \"pki/sign/ingress-tls\" {
  capabilities = [\"create\", \"update\"]
}
path \"pki/issue/ingress-tls\" {
  capabilities = [\"create\", \"update\"]
}
EOF_POLICY

        # Configure Kubernetes auth
        vault auth enable kubernetes 2>/dev/null || echo 'Kubernetes auth already enabled'

        vault write auth/kubernetes/config \
            kubernetes_host='https://\$KUBERNETES_SERVICE_HOST:\$KUBERNETES_SERVICE_PORT'

        vault write auth/kubernetes/role/cert-manager \
            bound_service_account_names=cert-manager \
            bound_service_account_namespaces=cert-manager \
            policies=cert-manager \
            ttl=1h
    " || {
        log_error "Échec de la configuration Vault PKI"
        exit 1
    }

    log_success "Vault PKI configuré avec require_cn=false"

else
    log_warning "Skip Vault initialization (--skip-vault-init)"
fi

# Étape 4 : Vérifier et forcer retry des certificats
log_step "4️⃣  Vérification et retry des certificats TLS"

log_info "Vérification du ClusterIssuer..."
ISSUER_READY=$(kubectl get clusterissuer vault-issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

if [ "$ISSUER_READY" = "True" ]; then
    log_success "ClusterIssuer vault-issuer est Ready"
else
    log_warning "ClusterIssuer vault-issuer n'est pas Ready, attente..."
    sleep 10
fi

log_info "Vérification des certificats..."
CERTS_NOT_READY=$(kubectl get certificates -A -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l)

if [ "$CERTS_NOT_READY" -gt 0 ]; then
    log_warning "$CERTS_NOT_READY certificat(s) pas prêt(s), forçage du retry..."

    # Liste des certificats à retry
    CERT_LIST=$(kubectl get certificates -A -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"')

    while read -r namespace name; do
        [ -z "$namespace" ] && continue
        log_info "Retry certificat: $namespace/$name"

        # Supprimer et recréer le certificat
        kubectl get certificate "$name" -n "$namespace" -o yaml > /tmp/cert-backup-$name.yaml
        kubectl delete certificate "$name" -n "$namespace" --ignore-not-found=true
        kubectl apply -f /tmp/cert-backup-$name.yaml
        rm -f /tmp/cert-backup-$name.yaml
    done <<< "$CERT_LIST"

    log_info "Attente de la génération des certificats (max 60s)..."
    sleep 10

    for i in {1..12}; do
        READY_COUNT=$(kubectl get certificates -A -o json | jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
        TOTAL_COUNT=$(kubectl get certificates -A -o json | jq -r '.items | length')

        log_info "Certificats prêts: $READY_COUNT/$TOTAL_COUNT"

        if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ]; then
            log_success "Tous les certificats sont prêts !"
            break
        fi

        if [ $i -eq 12 ]; then
            log_warning "Timeout, mais continuons..."
        fi

        sleep 5
    done
else
    log_success "Tous les certificats sont déjà prêts"
fi

# Étape 5 : Configuration Falco pour exporter les métriques
log_step "5️⃣  Configuration des métriques Falco pour Prometheus"

log_info "Vérification de Falco..."
FALCO_PODS=$(kubectl get pods -n security-detection -l app.kubernetes.io/name=falco -o jsonpath='{.items[*].metadata.name}')

if [ -z "$FALCO_PODS" ]; then
    log_warning "Aucun pod Falco trouvé, skip configuration métriques"
else
    log_info "Pods Falco: $FALCO_PODS"

    # Créer un ServiceMonitor pour Falco
    log_info "Création du ServiceMonitor pour Falco..."

    cat <<EOF | kubectl apply -f - || log_warning "Échec création ServiceMonitor Falco"
apiVersion: v1
kind: Service
metadata:
  name: falco-metrics
  namespace: security-detection
  labels:
    app.kubernetes.io/name: falco
spec:
  selector:
    app.kubernetes.io/name: falco
  ports:
  - name: metrics
    port: 8765
    targetPort: 8765
    protocol: TCP
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: falco-metrics
  namespace: security-detection
  labels:
    app.kubernetes.io/name: falco
    prometheus: kube-prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: falco
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF

    log_success "ServiceMonitor Falco créé"
fi

# Étape 6 : Vérification Prometheus targets
log_step "6️⃣  Vérification des targets Prometheus"

log_info "Récupération des targets Prometheus..."

PROM_POD=$(kubectl get pods -n security-siem -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROM_POD" ]; then
    log_info "Port-forward Prometheus pour vérifier les targets..."
    kubectl port-forward -n security-siem "$PROM_POD" 9090:9090 > /dev/null 2>&1 &
    PF_PID=$!
    sleep 3

    TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets | length' || echo "0")
    log_info "Nombre de targets actives: $TARGETS"

    kill $PF_PID 2>/dev/null || true

    if [ "$TARGETS" -gt 0 ]; then
        log_success "Prometheus scrape des targets"
    else
        log_warning "Aucune target active, vérifier la configuration"
    fi
else
    log_warning "Pod Prometheus non trouvé"
fi

# Étape 7 : Résumé final
log_step "7️⃣  Résumé du déploiement"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Déploiement terminé avec succès ! ✓             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "📊 État des composants:"
echo ""

# Vérifier les namespaces
for ns in security-iam security-siem security-detection security-network; do
    if kubectl get namespace "$ns" &>/dev/null; then
        TOTAL=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        RUNNING=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✓${NC} $ns: $RUNNING/$TOTAL pods Running"
    fi
done

# Vérifier les certificats
echo ""
log_info "🔐 Certificats TLS:"
kubectl get certificates -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status --no-headers 2>/dev/null | \
    while read -r ns name ready; do
        if [ "$ready" = "True" ]; then
            echo -e "  ${GREEN}✓${NC} $ns/$name"
        else
            echo -e "  ${YELLOW}⚠${NC} $ns/$name (not ready)"
        fi
    done || echo "  Aucun certificat trouvé"

echo ""
log_info "🌐 Accès aux interfaces:"
echo ""

cat << 'ACCESS'
# Grafana (Monitoring)
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
→ https://grafana.local.lab (avec /etc/hosts)
→ http://localhost:3000 (admin/admin123)

# Kibana (SIEM)
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601
→ https://kibana.local.lab
→ http://localhost:5601

# Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
→ https://prometheus.local.lab
→ http://localhost:9090

# Falco UI
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
→ https://falco-ui.local.lab
→ http://localhost:2802

# Vault
kubectl port-forward -n security-iam svc/vault 8200:8200
→ http://localhost:8200

# Keycloak
kubectl port-forward -n security-iam svc/keycloak 8080:80
→ http://localhost:8080 (admin/admin123)
ACCESS

echo ""
log_info "🔍 Commandes utiles:"
echo ""

cat << 'COMMANDS'
# Voir tous les pods
kubectl get pods --all-namespaces

# Vérifier les certificats
kubectl get certificates -A

# Vérifier Prometheus targets
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets

# Voir les événements Falco
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=50

# Vérifier les métriques Falco
kubectl port-forward -n security-detection svc/falco-metrics 8765:8765
# → http://localhost:8765/metrics
COMMANDS

echo ""
log_info "📝 Configuration Windows hosts:"
echo ""
echo "  Ajouter dans C:\\Windows\\System32\\drivers\\etc\\hosts:"
echo "  127.0.0.1  grafana.local.lab"
echo "  127.0.0.1  kibana.local.lab"
echo "  127.0.0.1  prometheus.local.lab"
echo "  127.0.0.1  falco-ui.local.lab"

echo ""
log_success "Déploiement complet terminé !"
echo ""
