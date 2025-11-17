#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Port-forward Ingress HTTPS (avec auto-restart)         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script expose le nginx-ingress-controller sur localhost:8443"
echo "   avec redémarrage automatique en cas de déconnexion"
echo ""
echo "⚠️  Configurer le fichier hosts Windows/Linux avec:"
echo "   127.0.0.1 grafana.local.lab"
echo "   127.0.0.1 kibana.local.lab"
echo "   127.0.0.1 prometheus.local.lab"
echo "   127.0.0.1 falco-ui.local.lab"
echo "   127.0.0.1 keycloak.local.lab"
echo "   127.0.0.1 vault.local.lab"
echo "   127.0.0.1 dashboard.local.lab"
echo "   127.0.0.1 minio.local.lab"
echo "   127.0.0.1 argocd.local.lab"
echo "   127.0.0.1 gitea.local.lab"
echo ""
echo "🌐 URLs d'accès:"
echo "   https://grafana.local.lab:8443"
echo "   https://kibana.local.lab:8443"
echo "   https://prometheus.local.lab:8443"
echo "   https://falco-ui.local.lab:8443"
echo "   https://keycloak.local.lab:8443"
echo "   https://vault.local.lab:8443"
echo "   https://dashboard.local.lab:8443"
echo "   https://minio.local.lab:8443         (Console MinIO - Backups Velero)"
echo "   https://argocd.local.lab:8443        (ArgoCD - GitOps)"
echo "   https://gitea.local.lab:8443         (Gitea - Git Server)"
echo ""
echo "✨ Nouveau: Redémarrage automatique en cas de déconnexion"
echo "⚠️  Ce terminal restera occupé. Pour arrêter : Ctrl+C"
echo ""

read -p "Démarrer le port-forward avec auto-restart ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Port-forward annulé."
    exit 0
fi

# Fonction pour cleanup
cleanup() {
    echo ""
    echo "🛑 Arrêt du port-forward..."
    exit 0
}

trap cleanup SIGINT SIGTERM

echo ""
echo "🚀 Démarrage du port-forward avec auto-restart..."
echo "   Local:  localhost:8443"
echo "   Remote: ingress-nginx-controller:443"
echo ""

# Compteur de tentatives
attempt=1

while true; do
    echo "📡 Tentative #$attempt - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "✅ Port-forward actif ! Accédez aux services depuis Windows."
    echo ""

    # Lancer le port-forward
    kubectl port-forward -n ingress-nginx \
        svc/ingress-nginx-controller 8443:443 \
        --address 0.0.0.0 2>&1

    # Si on arrive ici, le port-forward s'est arrêté
    exit_code=$?

    echo ""
    echo "⚠️  Port-forward interrompu (exit code: $exit_code)"
    echo "🔄 Redémarrage dans 3 secondes..."
    echo ""

    sleep 3
    attempt=$((attempt + 1))
done
