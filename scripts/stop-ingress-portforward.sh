#!/bin/bash

set -e

SESSION_NAME="ingress-pf"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Arrêt du Port-Forward Ingress (Screen)             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier si screen est installé
if ! command -v screen &> /dev/null; then
    echo "❌ 'screen' n'est pas installé"
    exit 1
fi

# Vérifier si la session existe
if screen -list 2>/dev/null | grep -q "$SESSION_NAME"; then
    echo "📊 Session screen trouvée:"
    screen -list | grep "$SESSION_NAME"
    echo ""

    read -p "Voulez-vous arrêter la session '$SESSION_NAME' ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Opération annulée."
        exit 0
    fi

    echo ""
    echo "🛑 Arrêt de la session screen..."

    # Arrêter la session
    screen -X -S "$SESSION_NAME" quit

    sleep 2

    # Vérifier que la session est bien arrêtée
    if screen -list 2>/dev/null | grep -q "$SESSION_NAME"; then
        echo "⚠️  La session n'a pas pu être arrêtée"
        echo "   Essayez manuellement: screen -X -S $SESSION_NAME quit"
    else
        echo "✅ Session arrêtée avec succès"
        echo ""
        echo "   Le port-forward a été arrêté"
        echo "   Les URLs ne sont plus accessibles:"
        echo "   - https://keycloak.local.lab:8443/"
        echo "   - https://vault.local.lab:8443/"
        echo "   - https://kibana.local.lab:8443/"
        echo "   - https://dashboard.local.lab:8443/"
        echo "   - https://minio.local.lab:8443/"
        echo "   - https://argocd.local.lab:8443/"
        echo "   - https://gitea.local.lab:8443/"
    fi
else
    echo "ℹ️  Aucune session screen '$SESSION_NAME' active"
    echo ""
    echo "   Sessions screen actuelles:"
    screen -list || echo "   (aucune session)"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                       ✅ TERMINÉ                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
