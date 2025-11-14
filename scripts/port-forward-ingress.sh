#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Port-forward Ingress HTTPS vers Windows (localhost)   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script expose le nginx-ingress-controller sur localhost:8443"
echo "   pour permettre l'accès depuis Windows via:"
echo ""
echo "   https://localhost:8443/  (avec Host header routing)"
echo ""
echo "⚠️  Configurer le fichier hosts Windows avec:"
echo "   127.0.0.1 grafana.local.lab"
echo "   127.0.0.1 kibana.local.lab"
echo "   127.0.0.1 prometheus.local.lab"
echo "   127.0.0.1 falco-ui.local.lab"
echo ""
echo "🌐 URLs d'accès depuis Windows:"
echo "   https://grafana.local.lab:8443"
echo "   https://kibana.local.lab:8443"
echo "   https://prometheus.local.lab:8443"
echo "   https://falco-ui.local.lab:8443"
echo ""
echo "⚠️  Ce terminal restera occupé par le port-forward."
echo "   Pour arrêter : Ctrl+C"
echo ""

read -p "Démarrer le port-forward ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Port-forward annulé."
    exit 0
fi

echo ""
echo "🚀 Démarrage du port-forward..."
echo "   Local:  localhost:8443"
echo "   Remote: ingress-nginx-controller:443"
echo ""
echo "✅ Port-forward actif ! Accédez aux services depuis Windows."
echo ""

kubectl port-forward -n ingress-nginx \
    svc/ingress-nginx-controller 8443:443 \
    --address 0.0.0.0
