#!/bin/bash
#
# Fix Ingress Access - Configure port-forward for Kind + MetalLB
#
# Ce script configure l'accès aux Ingress depuis Windows dans un environnement Kind
#

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

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
║   Fix Ingress Access - Kind + MetalLB + Windows         ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_step "1️⃣  Diagnostic de la configuration actuelle"

# Vérifier l'Ingress Controller
log_info "Vérification de l'Ingress Controller..."

INGRESS_SVC=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o json 2>/dev/null)

if [ -z "$INGRESS_SVC" ]; then
    log_error "Ingress Controller non trouvé"
    exit 1
fi

EXTERNAL_IP=$(echo "$INGRESS_SVC" | jq -r '.status.loadBalancer.ingress[0].ip // "none"')
NODEPORT_HTTP=$(echo "$INGRESS_SVC" | jq -r '.spec.ports[] | select(.port==80) | .nodePort')
NODEPORT_HTTPS=$(echo "$INGRESS_SVC" | jq -r '.spec.ports[] | select(.port==443) | .nodePort')

log_info "External IP (MetalLB): $EXTERNAL_IP"
log_info "NodePort HTTP: $NODEPORT_HTTP"
log_info "NodePort HTTPS: $NODEPORT_HTTPS"

# Vérifier les ingress
log_info "Vérification des Ingress configurés..."
kubectl get ingress -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.rules[0].host,ADDRESS:.status.loadBalancer.ingress[0].ip --no-headers | \
    while read -r ns name host ip; do
        echo -e "  ${GREEN}✓${NC} $ns/$name → $host ($ip)"
    done

# Vérifier les certificats
log_info "Vérification des certificats TLS..."
CERTS_READY=$(kubectl get certificates -A -o json | jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
CERTS_TOTAL=$(kubectl get certificates -A -o json | jq -r '.items | length')

if [ "$CERTS_READY" -eq "$CERTS_TOTAL" ]; then
    log_success "Tous les certificats sont prêts ($CERTS_READY/$CERTS_TOTAL)"
else
    log_warning "Certificats: $CERTS_READY/$CERTS_TOTAL prêts"
fi

log_step "2️⃣  Problème identifié"

echo -e "${YELLOW}⚠ PROBLÈME :${NC}"
echo ""
echo "  L'IP MetalLB ${EXTERNAL_IP} est dans le réseau Docker interne (172.19.x.x)."
echo "  Cette IP n'est PAS accessible depuis Windows car elle est isolée dans"
echo "  le réseau bridge Docker du cluster Kind."
echo ""
echo -e "${BLUE}ℹ EXPLICATION :${NC}"
echo ""
echo "  Kind (Kubernetes in Docker) crée un réseau Docker privé pour les nodes."
echo "  MetalLB assigne des IPs de ce réseau, mais elles ne sont pas routables"
echo "  depuis l'hôte Windows/WSL."
echo ""

log_step "3️⃣  Solutions disponibles"

echo -e "${GREEN}Solution 1 : Port-forward l'Ingress Controller (RECOMMANDÉ)${NC}"
echo ""
echo "  Avantages:"
echo "    ✓ Simple et rapide"
echo "    ✓ Fonctionne immédiatement"
echo "    ✓ Pas besoin de recréer le cluster"
echo ""
echo "  Inconvénients:"
echo "    ✗ Nécessite de garder le port-forward actif"
echo "    ✗ Doit être relancé après chaque redémarrage"
echo ""
echo "  Commande:"
echo -e "    ${CYAN}kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443${NC}"
echo ""
echo "  Fichier Windows hosts (C:\\Windows\\System32\\drivers\\etc\\hosts):"
echo -e "    ${CYAN}127.0.0.1  grafana.local.lab kibana.local.lab prometheus.local.lab falco-ui.local.lab${NC}"
echo ""
echo "  Puis accéder à: https://grafana.local.lab/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Solution 2 : Utiliser les NodePorts${NC}"
echo ""
echo "  Avantages:"
echo "    ✓ Pas de port-forward nécessaire"
echo "    ✓ Fonctionne immédiatement"
echo ""
echo "  Inconvénients:"
echo "    ✗ Ports non-standard (doit spécifier :$NODEPORT_HTTPS)"
echo "    ✗ Moins élégant"
echo ""
echo "  Fichier Windows hosts (C:\\Windows\\System32\\drivers\\etc\\hosts):"
echo -e "    ${CYAN}127.0.0.1  grafana.local.lab kibana.local.lab prometheus.local.lab falco-ui.local.lab${NC}"
echo ""
echo "  Puis accéder à: https://grafana.local.lab:$NODEPORT_HTTPS/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Solution 3 : Recréer le cluster Kind avec extraPortMappings${NC}"
echo ""
echo "  Avantages:"
echo "    ✓ Mapping natif des ports 80/443"
echo "    ✓ Pas de port-forward nécessaire"
echo "    ✓ Ports standard (80/443)"
echo "    ✓ Persiste après redémarrage"
echo ""
echo "  Inconvénients:"
echo "    ✗ Nécessite de DÉTRUIRE et recréer le cluster"
echo "    ✗ Perd toutes les données actuelles"
echo "    ✗ Nécessite de redéployer la stack complète"
echo ""
echo "  Voir: scripts/recreate-kind-with-port-mapping.sh"
echo ""

log_step "4️⃣  Démarrage automatique du port-forward (Solution 1)"

echo ""
read -p "Voulez-vous démarrer le port-forward maintenant ? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Démarrage du port-forward..."
    log_warning "IMPORTANT: Gardez cette fenêtre ouverte !"
    echo ""
    log_info "Une fois le port-forward actif, configurez votre fichier Windows hosts:"
    echo ""
    echo "  1. Ouvrir PowerShell en tant qu'Administrateur"
    echo "  2. Exécuter:"
    echo -e "     ${CYAN}notepad C:\\Windows\\System32\\drivers\\etc\\hosts${NC}"
    echo ""
    echo "  3. Ajouter la ligne:"
    echo -e "     ${CYAN}127.0.0.1  grafana.local.lab kibana.local.lab prometheus.local.lab falco-ui.local.lab${NC}"
    echo ""
    echo "  4. Sauvegarder et fermer"
    echo ""
    echo "  5. Accéder à: https://grafana.local.lab/"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_success "Port-forward démarré sur localhost:80 et localhost:443"
    echo ""
    log_warning "Appuyez sur Ctrl+C pour arrêter le port-forward"
    echo ""

    # Démarrer le port-forward
    kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443
else
    log_info "Port-forward non démarré"
    echo ""
    log_info "Pour démarrer manuellement:"
    echo -e "  ${CYAN}kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443${NC}"
    echo ""
fi

log_step "✅ Terminé"
