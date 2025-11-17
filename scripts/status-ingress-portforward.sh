#!/bin/bash

SESSION_NAME="ingress-pf"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Statut du Port-Forward Ingress (Screen)            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier si screen est installé
if ! command -v screen &> /dev/null; then
    echo "❌ 'screen' n'est pas installé"
    exit 1
fi

# Vérifier si la session existe
if screen -list 2>/dev/null | grep -q "$SESSION_NAME"; then
    echo "✅ Session screen '$SESSION_NAME' ACTIVE"
    echo ""

    echo "📊 Informations de la session:"
    screen -list | grep "$SESSION_NAME"
    echo ""

    # Test de connectivité
    echo "🧪 Test de connectivité sur localhost:8443..."
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 --connect-timeout 3 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" =~ ^(200|301|302|404)$ ]]; then
        echo "✅ Port-forward FONCTIONNEL (HTTP $HTTP_CODE)"
    else
        echo "❌ Port-forward NON FONCTIONNEL (HTTP $HTTP_CODE)"
        echo "   La session screen existe mais le port ne répond pas"
    fi

    echo ""
    echo "🌐 URLs accessibles:"
    echo "   https://keycloak.local.lab:8443/admin/"
    echo "   https://vault.local.lab:8443/ui/"
    echo "   https://kibana.local.lab:8443/"
    echo "   https://dashboard.local.lab:8443/"
    echo ""

    echo "🔧 Commandes:"
    echo "   Voir la session:  screen -r $SESSION_NAME"
    echo "   Arrêter:          ./scripts/stop-ingress-portforward.sh"

else
    echo "❌ Session screen '$SESSION_NAME' INACTIVE"
    echo ""
    echo "   Le port-forward n'est pas actif"
    echo ""
    echo "🚀 Pour démarrer:"
    echo "   ./scripts/start-ingress-portforward.sh"
    echo ""

    # Afficher toutes les sessions screen
    echo "📋 Sessions screen existantes:"
    if screen -list 2>/dev/null; then
        # screen -list affiche déjà la sortie
        true
    else
        echo "   (aucune session active)"
    fi
fi

echo ""
