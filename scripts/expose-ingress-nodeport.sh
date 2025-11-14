#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Exposer Ingress via NodePort (plus stable)           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Cette méthode expose l'Ingress via NodePort au lieu de port-forward"
echo "   Avantages:"
echo "   - ✅ Plus stable (pas de broken pipe)"
echo "   - ✅ Pas besoin de garder un terminal ouvert"
echo "   - ✅ Survit aux redémarrages de pods"
echo ""
echo "   Inconvénient:"
echo "   - ⚠️  Utilise un port aléatoire (30000-32767)"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# Vérifier si le service existe déjà
CURRENT_TYPE=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}' 2>/dev/null || echo "")

if [ "$CURRENT_TYPE" = "NodePort" ]; then
    echo ""
    echo "ℹ️  Le service est déjà en mode NodePort"
    HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
    HTTPS_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')

    echo "   HTTP NodePort:  $HTTP_PORT"
    echo "   HTTPS NodePort: $HTTPS_PORT"
    echo ""

    read -p "Voulez-vous recréer le service ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Conservation du service existant."

        # Afficher les instructions
        echo ""
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║              ✅ SERVICE DÉJÀ CONFIGURÉ                    ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo ""
        echo "🌐 Accès depuis Windows (fichier hosts):"
        echo ""
        echo "C:\\Windows\\System32\\drivers\\etc\\hosts:"
        echo "  127.0.0.1 grafana.local.lab"
        echo "  127.0.0.1 kibana.local.lab"
        echo "  127.0.0.1 prometheus.local.lab"
        echo "  127.0.0.1 falco-ui.local.lab"
        echo "  127.0.0.1 keycloak.local.lab"
        echo "  127.0.0.1 vault.local.lab"
        echo ""
        echo "🔗 URLs d'accès:"
        echo "  https://keycloak.local.lab:$HTTPS_PORT/admin"
        echo "  https://vault.local.lab:$HTTPS_PORT/ui"
        echo "  https://grafana.local.lab:$HTTPS_PORT"
        echo "  https://kibana.local.lab:$HTTPS_PORT"
        echo "  https://prometheus.local.lab:$HTTPS_PORT"
        echo "  https://falco-ui.local.lab:$HTTPS_PORT"
        echo ""
        exit 0
    fi
fi

# Patcher le service pour utiliser NodePort
echo ""
echo "1️⃣  Modification du service Ingress en NodePort..."

kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "name": "http",
        "port": 80,
        "protocol": "TCP",
        "targetPort": "http",
        "nodePort": 30080
      },
      {
        "name": "https",
        "port": 443,
        "protocol": "TCP",
        "targetPort": "https",
        "nodePort": 30443
      }
    ]
  }
}'

echo "  ✅ Service modifié en NodePort"
echo ""

# Attendre la propagation
echo "2️⃣  Attente de la propagation (5 secondes)..."
sleep 5

# Récupérer les ports
HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
HTTPS_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')

echo "  ✅ Ports NodePort configurés:"
echo "     HTTP:  $HTTP_PORT"
echo "     HTTPS: $HTTPS_PORT"
echo ""

# Récupérer l'IP d'un node Kind
DOCKER_CONTAINER=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
KIND_NODE_IP="127.0.0.1"  # Kind expose les NodePorts sur localhost

echo "3️⃣  Test de connectivité..."
echo ""

# Test HTTPS
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: keycloak.local.lab" https://$KIND_NODE_IP:$HTTPS_PORT --connect-timeout 10 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "  ✅ Keycloak accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Test Keycloak: HTTP $HTTP_CODE"
fi

HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: vault.local.lab" https://$KIND_NODE_IP:$HTTPS_PORT/ui --connect-timeout 10 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "307" ]; then
    echo "  ✅ Vault accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Test Vault: HTTP $HTTP_CODE"
fi

# Résumé final
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ INGRESS EXPOSÉ VIA NODEPORT                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 Avantages de cette configuration:"
echo "   - Pas de port-forward nécessaire"
echo "   - Connexion stable (pas de broken pipe)"
echo "   - Survit aux redémarrages de pods"
echo ""
echo "🌐 Configuration fichier hosts Windows:"
echo ""
echo "C:\\Windows\\System32\\drivers\\etc\\hosts (en tant qu'Administrateur):"
echo "  127.0.0.1 grafana.local.lab"
echo "  127.0.0.1 kibana.local.lab"
echo "  127.0.0.1 prometheus.local.lab"
echo "  127.0.0.1 falco-ui.local.lab"
echo "  127.0.0.1 keycloak.local.lab"
echo "  127.0.0.1 vault.local.lab"
echo ""
echo "🔗 URLs d'accès depuis Windows:"
echo "  https://keycloak.local.lab:$HTTPS_PORT/admin"
echo "  https://vault.local.lab:$HTTPS_PORT/ui"
echo "  https://grafana.local.lab:$HTTPS_PORT"
echo "  https://kibana.local.lab:$HTTPS_PORT"
echo "  https://prometheus.local.lab:$HTTPS_PORT"
echo "  https://falco-ui.local.lab:$HTTPS_PORT"
echo ""
echo "⚠️  Port HTTPS: $HTTPS_PORT (NodePort, fixe jusqu'au prochain redéploiement)"
echo ""
echo "🔄 Pour revenir à LoadBalancer (MetalLB):"
echo "   kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"
echo ""
