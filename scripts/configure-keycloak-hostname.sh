#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Configuration Hostname et Proxy pour Keycloak          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    exit 1
fi

echo "✅ Pod Keycloak: $POD"
echo ""

# Identifier le service
KEYCLOAK_SVC=$(kubectl get svc -n security-iam -o json | jq -r '.items[] | select(.metadata.name | contains("keycloak")) | select(.spec.clusterIP != "None") | .metadata.name' | head -n1)
KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[0].port}')

echo "✅ Service: $KEYCLOAK_SVC:$KEYCLOAK_PORT"
echo ""

# 1. Supprimer l'annotation proxy-set-headers qui pose problème
echo "1️⃣  Simplification de l'Ingress (sans ConfigMap)..."
echo ""

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
    nginx.ingress.kubernetes.io/proxy-buffer-size: "128k"
    nginx.ingress.kubernetes.io/proxy-buffers-number: "4"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    # Proxy settings - simplifié sans snippet
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
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
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $KEYCLOAK_SVC
            port:
              number: $KEYCLOAK_PORT
EOF

echo "✅ Ingress simplifié créé"
echo ""

# 2. Configurer les variables d'environnement Keycloak pour accepter le proxy
echo "2️⃣  Configuration des variables Keycloak pour le proxy..."
echo ""

# Récupérer le type de déploiement
if kubectl get deployment -n security-iam -l app.kubernetes.io/name=keycloak &>/dev/null; then
    RESOURCE_TYPE="deployment"
    RESOURCE_NAME=$(kubectl get deployment -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
else
    RESOURCE_TYPE="statefulset"
    RESOURCE_NAME=$(kubectl get statefulset -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
fi

echo "   Type: $RESOURCE_TYPE/$RESOURCE_NAME"
echo ""

# Créer un secret avec les variables Keycloak
kubectl create secret generic keycloak-config -n security-iam \
    --from-literal=KC_PROXY=edge \
    --from-literal=KC_HOSTNAME_STRICT=false \
    --from-literal=KC_HOSTNAME_STRICT_HTTPS=false \
    --from-literal=PROXY_ADDRESS_FORWARDING=true \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret keycloak-config créé"
echo ""

# Patcher le déploiement pour ajouter ces variables
echo "3️⃣  Application des variables au pod..."
echo ""

kubectl set env $RESOURCE_TYPE/$RESOURCE_NAME -n security-iam \
    --from=secret/keycloak-config

echo "✅ Variables appliquées"
echo ""

# Attendre le rollout
echo "4️⃣  Redémarrage des pods..."
kubectl rollout status $RESOURCE_TYPE/$RESOURCE_NAME -n security-iam --timeout=120s

NEW_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
echo "✅ Nouveau pod: $NEW_POD"
echo ""

# Attendre que Keycloak démarre
echo "5️⃣  Attente du démarrage de Keycloak (60 secondes)..."
sleep 60

# Vérifier les variables
echo ""
echo "6️⃣  Vérification des variables proxy..."
kubectl exec -n security-iam $NEW_POD -- env | grep -E "(PROXY|KC_)" | head -10

echo ""
echo "7️⃣  Test de connectivité..."
echo ""

# Test depuis le pod
HTTP_CODE=$(kubectl exec -n security-iam $NEW_POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/ --connect-timeout 5 || echo "000")
echo "   http://localhost:8080/auth/ → HTTP $HTTP_CODE"

HTTP_CODE=$(kubectl exec -n security-iam $NEW_POD -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/admin/ --connect-timeout 5 || echo "000")
echo "   http://localhost:8080/auth/admin/ → HTTP $HTTP_CODE"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ KEYCLOAK CONFIGURÉ POUR LE PROXY               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 URLs d'accès depuis Windows:"
echo ""
echo "   Admin Console:  https://keycloak.local.lab:8443/admin/admin/"
echo "   Welcome Page:   https://keycloak.local.lab:8443/admin/"
echo ""
echo "🔐 Credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "⏳ Attendez 1-2 minutes que Keycloak initialise complètement"
echo ""
echo "🔄 Puis testez dans le navigateur:"
echo "   1. Videz le cache: Ctrl+Shift+R"
echo "   2. Ou navigation privée"
echo "   3. Allez sur: https://keycloak.local.lab:8443/admin/admin/"
echo ""
echo "📝 Si 400 Bad Request persiste:"
echo "   kubectl logs -n security-iam $NEW_POD --tail=100 | grep -i error"
echo ""
