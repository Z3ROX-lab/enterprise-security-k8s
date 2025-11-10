#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║     DÉPLOIEMENT COMPLET - Enterprise Security Stack      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Ce script va déployer la stack complète dans l'ordre :"
echo "  1. Cluster Kind"
echo "  2. Elasticsearch"
echo "  3. Filebeat"
echo "  4. Prometheus + Grafana"
echo "  5. cert-manager"
echo "  6. Keycloak"
echo "  7. Vault (dev mode)"
echo "  8. Vault PKI"
echo "  9. Falco"
echo " 10. OPA Gatekeeper"
echo ""
echo "Optionnel (avec confirmation) :"
echo "  - Kibana"
echo "  - Vault Raft (production)"
echo "  - Wazuh"
echo "  - Trivy"
echo ""
echo "Durée estimée : 30-45 minutes"
echo ""

read -p "Voulez-vous continuer ? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Annulation."
    exit 0
fi

# Fonction pour exécuter un script
run_step() {
    local SCRIPT=$1
    local STEP_NAME=$2
    local OPTIONAL=$3

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ $STEP_NAME"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    if [ -f "$SCRIPT" ]; then
        # Pour les scripts optionnels, on demande confirmation
        if [ "$OPTIONAL" = "yes" ]; then
            read -p "Installer ce composant optionnel ? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "⏭️  Étape ignorée."
                return 0
            fi
        fi

        # Exécuter le script avec 'yes' automatique pour les confirmations
        yes | bash "$SCRIPT" || {
            RET=$?
            echo ""
            echo "❌ Échec de l'étape : $STEP_NAME"
            echo ""
            read -p "Voulez-vous continuer quand même ? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Déploiement arrêté."
                exit 1
            fi
        }
    else
        echo "⚠️  Script introuvable : $SCRIPT"
    fi
}

# Déploiement étape par étape
run_step "$SCRIPT_DIR/01-cluster-kind.sh" "ÉTAPE 1/10 : Cluster Kind" "no"
run_step "$SCRIPT_DIR/10-elasticsearch.sh" "ÉTAPE 2/10 : Elasticsearch" "no"
run_step "$SCRIPT_DIR/11-kibana.sh" "ÉTAPE 3/10 : Kibana (optionnel)" "yes"
run_step "$SCRIPT_DIR/12-filebeat.sh" "ÉTAPE 4/10 : Filebeat" "no"
run_step "$SCRIPT_DIR/13-prometheus.sh" "ÉTAPE 5/10 : Prometheus + Grafana" "no"
run_step "$SCRIPT_DIR/20-cert-manager.sh" "ÉTAPE 6/10 : cert-manager" "no"
run_step "$SCRIPT_DIR/21-keycloak.sh" "ÉTAPE 7/10 : Keycloak" "no"

# Choix entre Vault dev et Raft
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║ ÉTAPE 8/10 : Vault (choix du mode)"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Deux modes disponibles :"
echo "  1. Dev mode (rapide, test, données en mémoire)"
echo "  2. Raft HA (production, persistant, 3 replicas)"
echo ""
read -p "Mode ? (1=dev / 2=raft) " -n 1 -r
echo
if [[ $REPLY == "2" ]]; then
    run_step "$SCRIPT_DIR/23-vault-raft.sh" "ÉTAPE 8/10 : Vault Raft HA" "no"
else
    run_step "$SCRIPT_DIR/22-vault-dev.sh" "ÉTAPE 8/10 : Vault Dev" "no"
fi

run_step "$SCRIPT_DIR/24-vault-pki.sh" "ÉTAPE 9/10 : Vault PKI" "no"
run_step "$SCRIPT_DIR/30-falco.sh" "ÉTAPE 10/10 : Falco" "no"
run_step "$SCRIPT_DIR/40-gatekeeper.sh" "ÉTAPE 11/10 : OPA Gatekeeper" "no"

# Composants optionnels
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║ COMPOSANTS OPTIONNELS"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

run_step "$SCRIPT_DIR/31-wazuh.sh" "OPTIONNEL : Wazuh HIDS (8GB RAM)" "yes"
run_step "$SCRIPT_DIR/41-trivy.sh" "OPTIONNEL : Trivy Operator" "yes"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║        ✅ DÉPLOIEMENT COMPLET TERMINÉ AVEC SUCCÈS        ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Résumé de la stack déployée :"
echo ""
kubectl get nodes
echo ""
echo "Namespaces :"
kubectl get namespaces | grep -E "security-|cert-manager|gatekeeper|trivy"
echo ""

echo "📈 État des pods par namespace :"
echo ""
for ns in security-siem security-iam security-detection cert-manager gatekeeper-system trivy-system; do
    if kubectl get namespace $ns &>/dev/null; then
        COUNT=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l || echo "0")
        RUNNING=$(kubectl get pods -n $ns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        echo "  ▶ $ns: $RUNNING/$COUNT pods Running"
    fi
done
echo ""

echo "🌐 Accès aux dashboards :"
echo ""
echo "  Grafana (Monitoring):"
echo "    kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "    http://localhost:3000 (admin/admin123)"
echo ""
echo "  Keycloak (IAM):"
echo "    kubectl port-forward -n security-iam svc/keycloak 8080:80"
echo "    http://localhost:8080 (admin/admin123)"
echo ""
echo "  Vault (Secrets):"
echo "    kubectl port-forward -n security-iam svc/vault 8200:8200"
echo "    http://localhost:8200"
echo ""
echo "  Falco UI:"
echo "    kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802"
echo "    http://localhost:2802"
echo ""

if kubectl get namespace trivy-system &>/dev/null; then
    echo "  Trivy Reports:"
    echo "    kubectl get vulnerabilityreports --all-namespaces"
    echo ""
fi

echo "🎉 Stack de sécurité déployée avec succès !"
echo ""
echo "📚 Documentation complète dans : deploy/README.md"
echo ""
