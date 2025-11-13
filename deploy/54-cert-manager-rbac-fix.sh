#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Fix cert-manager RBAC for Vault authentication     ║"
echo "║         Permissions manquantes pour créer des tokens     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script va :"
echo "  1. Créer un ClusterRole avec permissions serviceaccounts/token"
echo "  2. Créer un ClusterRoleBinding pour cert-manager"
echo "  3. Permettre à cert-manager de s'authentifier auprès de Vault"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

echo ""
echo "1️⃣  Création du ClusterRole cert-manager-vault-auth..."

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-manager-vault-auth
rules:
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
EOF

echo "  ✅ ClusterRole créé"

echo ""
echo "2️⃣  Création du ClusterRoleBinding..."

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-vault-auth
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-manager-vault-auth
subjects:
- kind: ServiceAccount
  name: cert-manager
  namespace: cert-manager
EOF

echo "  ✅ ClusterRoleBinding créé"

echo ""
echo "3️⃣  Attente que cert-manager détecte les nouvelles permissions (30s)..."
sleep 30

echo ""
echo "4️⃣  Vérification des certificats..."
echo ""

# Attendre que les certificats soient générés
echo "⏳ Vérification de la génération des certificats (max 60s)..."
for i in {1..12}; do
    READY_COUNT=$(kubectl get certificates -A -o json | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
    TOTAL_COUNT=$(kubectl get certificates -A -o json | jq '.items | length')

    echo "  Tentative $i/12: $READY_COUNT/$TOTAL_COUNT certificats prêts"

    if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ]; then
        echo "  ✅ Tous les certificats sont prêts !"
        break
    fi

    if [ $i -lt 12 ]; then
        sleep 5
    fi
done

echo ""
echo "📊 État final des certificats :"
kubectl get certificates -A

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ RBAC FIX APPLIQUÉ                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier si tous les certificats sont prêts
READY_COUNT=$(kubectl get certificates -A -o json | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
TOTAL_COUNT=$(kubectl get certificates -A -o json | jq '.items | length')

if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ]; then
    echo "✅ Tous les certificats TLS sont générés et prêts"
    echo ""
    echo "🌐 Vous pouvez maintenant accéder aux services en HTTPS :"
    echo "  - https://grafana.local.lab"
    echo "  - https://kibana.local.lab"
    echo "  - https://prometheus.local.lab"
    echo "  - https://falco-ui.local.lab"
    echo ""
    echo "⚠️  N'oubliez pas de configurer /etc/hosts avec l'IP du LoadBalancer :"
    echo "  kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
else
    echo "⚠️  Certains certificats ne sont pas encore prêts"
    echo "  Patientez quelques minutes et vérifiez avec:"
    echo "  kubectl get certificates -A"
    echo ""
    echo "  Pour voir les détails d'un certificat :"
    echo "  kubectl describe certificate grafana-tls -n security-siem"
fi

echo ""
