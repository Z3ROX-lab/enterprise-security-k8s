#!/bin/bash

set -e

SESSION_NAME="ingress-pf"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Gestionnaire Port-Forward Ingress (Screen)            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier si screen est installé
if ! command -v screen &> /dev/null; then
    echo "❌ 'screen' n'est pas installé !"
    echo ""
    echo "Installation:"
    echo "   sudo apt install screen -y"
    echo ""
    exit 1
fi

# Vérifier si la session existe déjà
if screen -list 2>/dev/null | grep -q "$SESSION_NAME"; then
    echo "✅ Session screen '$SESSION_NAME' déjà active !"
    echo ""

    # Afficher les infos de la session
    echo "📊 Informations de la session:"
    screen -list | grep "$SESSION_NAME"
    echo ""

    echo "🔧 Commandes disponibles:"
    echo "   Voir la session active:  screen -r $SESSION_NAME"
    echo "   Détacher la session:     Ctrl+A puis D (depuis la session)"
    echo "   Arrêter la session:      screen -X -S $SESSION_NAME quit"
    echo ""

    # Vérifier que le port-forward fonctionne
    echo "🧪 Test de connectivité..."
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 --connect-timeout 2 | grep -q "404\|200\|301\|302"; then
        echo "✅ Port-forward fonctionne correctement !"
    else
        echo "⚠️  Port-forward ne répond pas"
        echo "   La session screen existe mais le port-forward semble inactif"
        echo ""
        read -p "   Voulez-vous redémarrer la session ? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🔄 Redémarrage de la session..."
            screen -X -S "$SESSION_NAME" quit 2>/dev/null || true
            sleep 2
        else
            exit 0
        fi
    fi
else
    echo "🚀 Création d'une nouvelle session screen '$SESSION_NAME'..."
    echo ""

    # Créer la session screen en mode détaché
    # On utilise -L pour logger la session
    # On passe "yes y" pour auto-confirmer le prompt du script
    screen -dmS "$SESSION_NAME" -L bash -c 'yes y | ./scripts/port-forward-ingress-stable.sh'

    sleep 3

    # Vérifier que la session est créée
    if screen -list 2>/dev/null | grep -q "$SESSION_NAME"; then
        echo "✅ Session screen créée et lancée en arrière-plan !"
        echo ""

        # Attendre que le port-forward démarre
        echo "⏳ Attente du démarrage du port-forward..."
        sleep 5

        # Tester la connectivité
        echo "🧪 Test de connectivité..."
        if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443 --connect-timeout 2 | grep -q "404\|200\|301\|302"; then
            echo "✅ Port-forward actif et fonctionnel !"
        else
            echo "⚠️  Port-forward en cours de démarrage..."
            echo "   Attendez quelques secondes et testez à nouveau"
        fi

        echo ""
        echo "📋 Session screen créée:"
        screen -list | grep "$SESSION_NAME"
        echo ""

        echo "🔧 Commandes utiles:"
        echo "   Voir la session:     screen -r $SESSION_NAME"
        echo "   Détacher:            Ctrl+A puis D (depuis la session)"
        echo "   Arrêter:             screen -X -S $SESSION_NAME quit"
        echo "   Ou utiliser:         ./scripts/stop-ingress-portforward.sh"
        echo ""

        echo "🌐 URLs d'accès maintenant disponibles:"
        echo "   https://keycloak.local.lab:8443/auth/admin/"
        echo "   https://vault.local.lab:8443/ui/"
        echo "   https://kibana.local.lab:8443/"
        echo "   https://dashboard.local.lab:8443/"
        echo ""

        echo "📝 Note: La session screen reste active même si vous fermez le terminal"
        echo "   Le port-forward continuera en arrière-plan"
        echo ""
    else
        echo "❌ Erreur lors de la création de la session screen"
        exit 1
    fi
fi

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  ✅ PRÊT À UTILISER                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
