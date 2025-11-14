#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Diagnostic et Correction Ingress Keycloak            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Lister tous les services Keycloak
echo "1️⃣  Services Keycloak disponibles dans security-iam:"
echo ""
kubectl get svc -n security-iam | grep -i keycloak || echo "Aucun service Keycloak trouvé"
echo ""

# 2. Détails de chaque service
echo "2️⃣  Détails des services:"
echo ""
for svc in $(kubectl get svc -n security-iam -o name | grep -i keycloak); do
    svc_name=$(echo $svc | cut -d'/' -f2)
    echo "📋 Service: $svc_name"
    kubectl get svc $svc_name -n security-iam -o jsonpath='{.metadata.name}{"\t"}{.spec.type}{"\t"}{.spec.clusterIP}{"\t"}{.spec.ports[0].port}{"\n"}'
    echo ""
done

# 3. Déterminer le bon service
echo "3️⃣  Identification du service principal..."
echo ""

# Chercher le service non-headless
KEYCLOAK_SVC=$(kubectl get svc -n security-iam -o json | jq -r '.items[] | select(.metadata.name | contains("keycloak")) | select(.spec.clusterIP != "None") | .metadata.name' | head -n1)

if [ -z "$KEYCLOAK_SVC" ]; then
    echo "❌ Aucun service Keycloak non-headless trouvé"
    echo ""
    echo "Services disponibles:"
    kubectl get svc -n security-iam
    exit 1
fi

echo "✅ Service Keycloak principal détecté: $KEYCLOAK_SVC"
echo ""

# 4. Vérifier le port
KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
if [ -z "$KEYCLOAK_PORT" ]; then
    KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[0].port}')
fi

echo "📡 Port HTTP du service: $KEYCLOAK_PORT"
echo ""

# 5. Vérifier l'Ingress actuel
echo "4️⃣  Ingress actuel:"
echo ""
kubectl get ingress keycloak-ingress -n security-iam -o yaml | grep -A5 "backend:" || echo "Ingress non trouvé"
echo ""

# 6. Proposer la correction
echo "5️⃣  Correction de l'Ingress..."
echo ""
read -p "Voulez-vous corriger l'Ingress pour pointer vers '$KEYCLOAK_SVC:$KEYCLOAK_PORT' ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Correction annulée."
    exit 0
fi

# 7. Appliquer la correction
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: security-iam
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Port \$server_port;
spec:
  ingressClassName: nginx
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

echo ""
echo "✅ Ingress mis à jour avec le service: $KEYCLOAK_SVC:$KEYCLOAK_PORT"
echo ""

# 8. Attendre quelques secondes
echo "⏳ Attente de la propagation (10 secondes)..."
sleep 10

# 9. Test de connectivité
echo ""
echo "6️⃣  Test de connectivité..."
echo ""

INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "📡 IP Ingress: $INGRESS_IP"
echo ""

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: keycloak.local.lab" http://$INGRESS_IP --connect-timeout 10 || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "✅ Keycloak est accessible ! (HTTP $HTTP_CODE)"
    echo ""
    echo "🌐 Accédez à Keycloak via :"
    echo "   http://keycloak.local.lab"
    echo "   http://keycloak.local.lab/admin"
else
    echo "⚠️  HTTP $HTTP_CODE"
    echo ""
    echo "Vérifications supplémentaires :"
    echo ""
    echo "1. Pods Keycloak :"
    kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak
    echo ""
    echo "2. Logs Keycloak (dernières 10 lignes) :"
    kubectl logs -n security-iam -l app.kubernetes.io/name=keycloak --tail=10
    echo ""
    echo "3. Test direct du service :"
    echo "   kubectl port-forward -n security-iam svc/$KEYCLOAK_SVC 8080:$KEYCLOAK_PORT"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    ✅ DIAGNOSTIC TERMINÉ                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
