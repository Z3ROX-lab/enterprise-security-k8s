#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Kubernetes Dashboard avec Ingress                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

NAMESPACE="kubernetes-dashboard"

echo "1️⃣  Création du namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Namespace créé"
echo ""

echo "2️⃣  Déploiement du Kubernetes Dashboard..."
echo ""

# Déployer le dashboard officiel
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

echo "⏳ Attente du déploiement (30 sec)..."
sleep 30

kubectl wait --for=condition=available deployment/kubernetes-dashboard -n "$NAMESPACE" --timeout=180s || true

echo "✅ Dashboard déployé"
echo ""

echo "3️⃣  Création du ServiceAccount admin..."
echo ""

# Créer un ServiceAccount avec permissions admin
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: $NAMESPACE
EOF

echo "✅ ServiceAccount créé"
echo ""

echo "4️⃣  Création du token d'authentification..."
echo ""

# Créer un Secret pour le token (Kubernetes 1.24+)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF

sleep 5

# Récupérer le token
TOKEN=$(kubectl get secret admin-user-token -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
    echo "⚠️  Token non généré automatiquement, création manuelle..."
    # Méthode alternative pour Kubernetes récent
    TOKEN=$(kubectl create token admin-user -n "$NAMESPACE" --duration=87600h)
fi

echo "✅ Token créé"
echo ""

echo "5️⃣  Configuration de l'Ingress..."
echo ""

# Récupérer l'IP MetalLB
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
    echo "⚠️  IP MetalLB non trouvée, utilisez l'IP manuellement"
    INGRESS_IP="<METALLB_IP>"
fi

# Créer l'Ingress pour le dashboard
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard-ingress
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: dashboard.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF

echo "✅ Ingress créé"
echo ""

echo "6️⃣  Vérification du déploiement..."
echo ""

kubectl get pods -n "$NAMESPACE"
echo ""

kubectl get svc -n "$NAMESPACE"
echo ""

kubectl get ingress -n "$NAMESPACE"
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ KUBERNETES DASHBOARD DÉPLOYÉ !                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Accès au Dashboard:"
echo "   URL: https://dashboard.local.lab:8443/"
echo ""
echo "⚠️  Configuration /etc/hosts requise:"
echo "   $INGRESS_IP dashboard.local.lab"
echo ""
echo "   Ajoutez cette ligne avec:"
echo "   echo \"$INGRESS_IP dashboard.local.lab\" | sudo tee -a /etc/hosts"
echo ""
echo "🔐 Token d'authentification (à copier):"
echo ""
echo "$TOKEN"
echo ""
echo "   Ce token a aussi été sauvegardé dans:"
echo "   /tmp/k8s-dashboard-token.txt"
echo ""

# Sauvegarder le token
echo "$TOKEN" > /tmp/k8s-dashboard-token.txt
chmod 600 /tmp/k8s-dashboard-token.txt

echo "📋 Instructions d'accès:"
echo "   1. Ajoutez 'dashboard.local.lab' à /etc/hosts"
echo "   2. Ouvrez https://dashboard.local.lab:8443/ dans votre navigateur"
echo "   3. Acceptez le certificat auto-signé (erreur SSL normale)"
echo "   4. Choisissez 'Token' comme méthode d'authentification"
echo "   5. Collez le token ci-dessus"
echo "   6. Cliquez 'Sign In'"
echo ""
echo "🔄 Pour récupérer le token plus tard:"
echo "   kubectl get secret admin-user-token -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d"
echo ""
echo "   OU"
echo "   cat /tmp/k8s-dashboard-token.txt"
echo ""
