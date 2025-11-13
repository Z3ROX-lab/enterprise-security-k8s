#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Restart cert-manager to reload RBAC permissions    ║"
echo "║         Force certificate generation retry               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script va :"
echo "  1. Redémarrer tous les pods cert-manager"
echo "  2. Attendre que les pods soient prêts"
echo "  3. Vérifier que les certificats sont générés"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Redémarrage annulé."
    exit 0
fi

echo ""
echo "1️⃣  Redémarrage de cert-manager..."
kubectl rollout restart deployment cert-manager -n cert-manager
kubectl rollout restart deployment cert-manager-webhook -n cert-manager
kubectl rollout restart deployment cert-manager-cainjector -n cert-manager

echo "  ✅ Rollout restart déclenché"

echo ""
echo "2️⃣  Attente que les pods soient prêts (max 60s)..."
kubectl rollout status deployment cert-manager -n cert-manager --timeout=60s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=60s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=60s

echo "  ✅ Tous les pods cert-manager sont prêts"

echo ""
echo "3️⃣  Attente de la génération des certificats (max 90s)..."
echo "    (cert-manager va détecter les nouvelles permissions et réessayer)"
echo ""

for i in {1..18}; do
    READY_COUNT=$(kubectl get certificates -A -o json | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
    TOTAL_COUNT=$(kubectl get certificates -A -o json | jq '.items | length')

    echo "  Tentative $i/18: $READY_COUNT/$TOTAL_COUNT certificats prêts"

    if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
        echo "  ✅ Tous les certificats sont prêts !"
        break
    fi

    if [ $i -lt 18 ]; then
        sleep 5
    fi
done

echo ""
echo "4️⃣  État final des certificats :"
kubectl get certificates -A

echo ""
echo "5️⃣  Vérification des logs cert-manager (dernières 20 lignes)..."
CERT_MANAGER_POD=$(kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[0].metadata.name}')
echo "    Pod: $CERT_MANAGER_POD"
echo ""
kubectl logs -n cert-manager $CERT_MANAGER_POD --tail=20 | grep -i "error\|forbidden\|ready" || echo "    Pas d'erreurs récentes"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"

# Vérifier si tous les certificats sont prêts
READY_COUNT=$(kubectl get certificates -A -o json | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
TOTAL_COUNT=$(kubectl get certificates -A -o json | jq '.items | length')

if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
    echo "║              ✅ CERTIFICATS TLS PRÊTS                     ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 Vous pouvez maintenant accéder aux services en HTTPS :"
    echo "  - https://grafana.local.lab"
    echo "  - https://kibana.local.lab"
    echo "  - https://prometheus.local.lab"
    echo "  - https://falco-ui.local.lab"
    echo ""
    echo "⚠️  N'oubliez pas de configurer votre fichier hosts Windows :"
    echo "    C:\\Windows\\System32\\drivers\\etc\\hosts"
    echo ""
    echo "  Ajoutez ces lignes (en tant qu'administrateur) :"
    LOADBALANCER_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "  $LOADBALANCER_IP grafana.local.lab"
    echo "  $LOADBALANCER_IP kibana.local.lab"
    echo "  $LOADBALANCER_IP prometheus.local.lab"
    echo "  $LOADBALANCER_IP falco-ui.local.lab"
else
    echo "║         ⚠️  CERTIFICATS TOUJOURS PAS PRÊTS                ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "❌ Problème persistant avec les certificats"
    echo ""
    echo "📊 Diagnostic supplémentaire :"
    echo ""
    echo "1. Vérifier les permissions RBAC :"
    echo "   kubectl get clusterrole cert-manager-vault-auth -o yaml"
    echo ""
    echo "2. Vérifier le ClusterIssuer :"
    echo "   kubectl describe clusterissuer vault-issuer"
    echo ""
    echo "3. Vérifier les logs détaillés :"
    echo "   kubectl logs -n cert-manager $CERT_MANAGER_POD --tail=100"
    echo ""
    echo "4. Tester manuellement la création d'un service account token :"
    echo "   kubectl create token cert-manager -n cert-manager"
fi

echo ""
