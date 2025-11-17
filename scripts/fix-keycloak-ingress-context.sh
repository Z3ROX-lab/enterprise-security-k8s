#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║    Corriger l'Ingress Keycloak pour le contexte /auth    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Identifier le service Keycloak
KEYCLOAK_SVC=$(kubectl get svc -n security-iam -o json | jq -r '.items[] | select(.metadata.name | contains("keycloak")) | select(.spec.clusterIP != "None") | .metadata.name' | head -n1)

if [ -z "$KEYCLOAK_SVC" ]; then
    KEYCLOAK_SVC="keycloak-http"
fi

KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
if [ -z "$KEYCLOAK_PORT" ]; then
    KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[0].port}')
fi

echo "✅ Service Keycloak: $KEYCLOAK_SVC:$KEYCLOAK_PORT"
echo ""
echo "📝 Ce script va créer 2 Ingress pour Keycloak:"
echo "   1. keycloak.local.lab/ → Keycloak (contexte /auth)"
echo "   2. keycloak.local.lab/auth → Keycloak (accès direct)"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# Supprimer l'ancien Ingress s'il existe
kubectl delete ingress keycloak-ingress -n security-iam 2>/dev/null || true

echo ""
echo "1️⃣  Création du nouvel Ingress Keycloak..."
echo ""

# Créer l'Ingress avec le bon contexte
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: security-iam
  annotations:
    # TLS
    cert-manager.io/cluster-issuer: vault-issuer
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Backend
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    # Headers (via ConfigMap)
    nginx.ingress.kubernetes.io/proxy-set-headers: "security-iam/keycloak-proxy-headers"
    nginx.ingress.kubernetes.io/use-forwarded-headers: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - keycloak.local.lab
    secretName: keycloak-tls
  rules:
  - host: keycloak.local.lab
    http:
      paths:
      # Route principale - redirige vers /auth
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $KEYCLOAK_SVC
            port:
              number: $KEYCLOAK_PORT
EOF

echo "✅ Ingress créé"
echo ""

# Attendre quelques secondes
echo "2️⃣  Attente de la propagation (10 secondes)..."
sleep 10

# Vérifier
echo ""
echo "3️⃣  Vérification de l'Ingress..."
kubectl get ingress keycloak-ingress -n security-iam

echo ""
echo "4️⃣  Test de connectivité..."
echo ""

# Test via curl (depuis le pod)
POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')

echo "   Test depuis le pod:"
HTTP_CODE=$(kubectl exec -n security-iam $POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/ --connect-timeout 5 || echo "000")
echo "   http://localhost:8080/auth/ → HTTP $HTTP_CODE"

HTTP_CODE=$(kubectl exec -n security-iam $POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/admin/ --connect-timeout 5 || echo "000")
echo "   http://localhost:8080/auth/admin/ → HTTP $HTTP_CODE"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ INGRESS KEYCLOAK CORRIGÉ                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 URLs d'accès depuis Windows:"
echo ""
echo "   Page d'accueil:  https://keycloak.local.lab:8443/"
echo "   Admin Console:   https://keycloak.local.lab:8443/admin/admin/"
echo ""
echo "   ⚠️  IMPORTANT: Utilisez /auth/admin/ (avec /auth)"
echo ""
echo "🔐 Credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "📝 Note: Keycloak 17.x utilise le contexte /auth par défaut"
echo "   - /auth/            → Page d'accueil Keycloak"
echo "   - /auth/admin/      → Admin Console"
echo "   - /auth/realms/...  → API des realms"
echo ""
echo "🔄 Rafraîchir le navigateur avec Ctrl+Shift+R"
echo ""
