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
echo "  2. Monitoring (Elasticsearch + Prometheus)"
echo "  3. IAM (Keycloak + Vault)"
echo "  4. Falco (Runtime Security)"
echo "  5. OPA Gatekeeper (Policies)"
echo "  6. Trivy (optionnel)"
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

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║ $STEP_NAME"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    if [ -f "$SCRIPT" ]; then
        bash "$SCRIPT"
        if [ $? -ne 0 ]; then
            echo ""
            echo "❌ Échec de l'étape : $STEP_NAME"
            echo ""
            read -p "Voulez-vous continuer quand même ? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Déploiement arrêté."
                exit 1
            fi
        fi
    else
        echo "⚠️  Script introuvable : $SCRIPT"
    fi
}

# Déploiement étape par étape
run_step "$SCRIPT_DIR/01-cluster.sh" "ÉTAPE 1/5 : Cluster Kind"
run_step "$SCRIPT_DIR/02-monitoring.sh" "ÉTAPE 2/5 : Monitoring Stack"
run_step "$SCRIPT_DIR/03-iam.sh" "ÉTAPE 3/5 : IAM (Keycloak + Vault)"
run_step "$SCRIPT_DIR/04-falco.sh" "ÉTAPE 4/5 : Falco Runtime Security"
run_step "$SCRIPT_DIR/05-gatekeeper.sh" "ÉTAPE 5/5 : OPA Gatekeeper"

# Trivy optionnel
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║ ÉTAPE OPTIONNELLE : Trivy Operator"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
read -p "Installer Trivy Operator ? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/06-trivy.sh"
fi

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
kubectl get namespaces | grep -E "security-|cert-manager|gatekeeper"
echo ""

echo "📈 État des pods :"
echo ""
echo "▶ Monitoring :"
kubectl get pods -n security-siem --no-headers | wc -l | xargs echo "  Pods:"
echo ""
echo "▶ IAM :"
kubectl get pods -n security-iam --no-headers | wc -l | xargs echo "  Pods:"
echo ""
echo "▶ Security Detection :"
kubectl get pods -n security-detection --no-headers | wc -l | xargs echo "  Pods:"
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

echo "📚 Scripts optionnels disponibles :"
echo "  ./optional-kibana.sh   - Installer Kibana (problématique)"
echo "  ./optional-wazuh.sh    - Installer Wazuh HIDS (8GB RAM requis)"
echo ""

echo "🎉 Stack de sécurité déployée avec succès !"
echo ""
