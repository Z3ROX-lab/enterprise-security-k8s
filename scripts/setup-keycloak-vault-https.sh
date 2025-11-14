#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Configuration Keycloak & Vault Ingress avec TLS        ║"
echo "║          (Sans snippets, HTTPS direct)                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que cert-manager et vault-issuer sont prêts
if ! kubectl get clusterissuer vault-issuer &>/dev/null; then
    echo "❌ ClusterIssuer 'vault-issuer' non trouvé"
    echo "Le script 53-ingress-tls.sh a-t-il été exécuté ?"
    exit 1
fi

echo "✅ ClusterIssuer 'vault-issuer' détecté"
echo ""

# Identifier le bon service Keycloak
echo "1️⃣  Identification du service Keycloak..."
KEYCLOAK_SVC=$(kubectl get svc -n security-iam -o json | jq -r '.items[] | select(.metadata.name | contains("keycloak")) | select(.spec.clusterIP != "None") | .metadata.name' | head -n1)

if [ -z "$KEYCLOAK_SVC" ]; then
    echo "  ⚠️  Service principal non trouvé, vérification manuelle..."
    kubectl get svc -n security-iam | grep keycloak
    exit 1
fi

KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
if [ -z "$KEYCLOAK_PORT" ]; then
    KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[0].port}')
fi

echo "  ✅ Service détecté: $KEYCLOAK_SVC:$KEYCLOAK_PORT"
echo ""

# Créer ConfigMap pour les headers proxy
echo "2️⃣  Création du ConfigMap pour les headers Keycloak..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-proxy-headers
  namespace: security-iam
data:
  X-Forwarded-For: "\$proxy_add_x_forwarded_for"
  X-Forwarded-Proto: "\$scheme"
  X-Forwarded-Host: "\$host"
  X-Forwarded-Port: "\$server_port"
EOF

echo "  ✅ ConfigMap créé"
echo ""

# Créer les certificats TLS
echo "3️⃣  Création des certificats TLS..."

cat <<EOF | kubectl apply -f -
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: keycloak-tls
  namespace: security-iam
spec:
  secretName: keycloak-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: keycloak.local.lab
  dnsNames:
  - keycloak.local.lab
  duration: 720h  # 30 jours
  renewBefore: 168h  # Renouveler 7 jours avant expiration
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-tls
  namespace: security-iam
spec:
  secretName: vault-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: vault.local.lab
  dnsNames:
  - vault.local.lab
  duration: 720h  # 30 jours
  renewBefore: 168h  # Renouveler 7 jours avant expiration
EOF

echo "  ✅ Certificats TLS créés"
echo "  ⏳ Attente de la génération (15 secondes)..."
sleep 15

# Vérifier les certificats
kubectl get certificate -n security-iam keycloak-tls vault-tls 2>/dev/null || echo "  ⏳ Certificats en cours de création..."
echo ""

# Créer l'Ingress Keycloak avec TLS (SANS snippets)
echo "4️⃣  Création de l'Ingress Keycloak avec TLS..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: security-iam
  annotations:
    # TLS et redirection
    cert-manager.io/cluster-issuer: vault-issuer
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Backend configuration
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    # Headers pour Keycloak (via ConfigMap au lieu de snippet)
    nginx.ingress.kubernetes.io/proxy-set-headers: "security-iam/keycloak-proxy-headers"
    # Autres configurations
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
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $KEYCLOAK_SVC
            port:
              number: $KEYCLOAK_PORT
EOF

echo "  ✅ Ingress Keycloak créé avec TLS"
echo ""

# Créer l'Ingress Vault avec TLS
echo "5️⃣  Création de l'Ingress Vault avec TLS..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: security-iam
  annotations:
    # TLS et redirection
    cert-manager.io/cluster-issuer: vault-issuer
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Backend configuration
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - vault.local.lab
    secretName: vault-tls
  rules:
  - host: vault.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vault
            port:
              number: 8200
EOF

echo "  ✅ Ingress Vault créé avec TLS"
echo ""

# Attendre la propagation
echo "6️⃣  Attente de la propagation (10 secondes)..."
sleep 10

# Vérifications
echo ""
echo "7️⃣  Vérifications..."
echo ""
echo "  📜 Certificats dans security-iam:"
kubectl get certificate -n security-iam

echo ""
echo "  📊 Ingress dans security-iam:"
kubectl get ingress -n security-iam

# Test de connectivité
echo ""
echo "8️⃣  Test de connectivité HTTPS..."
echo ""

INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "  📡 IP Ingress: $INGRESS_IP"
echo ""

echo "  🧪 Test Keycloak HTTPS..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: keycloak.local.lab" https://$INGRESS_IP --connect-timeout 10 --max-time 15 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "    ✅ Keycloak HTTPS accessible (HTTP $HTTP_CODE)"
else
    echo "    ⚠️  Keycloak HTTPS: HTTP $HTTP_CODE"
    echo "    Tentative de diagnostic..."
    kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak
fi

echo ""
echo "  🧪 Test Vault HTTPS..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: vault.local.lab" https://$INGRESS_IP/v1/sys/health --connect-timeout 10 --max-time 15 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "429" ] || [ "$HTTP_CODE" = "473" ] || [ "$HTTP_CODE" = "501" ] || [ "$HTTP_CODE" = "503" ]; then
    echo "    ✅ Vault HTTPS accessible (HTTP $HTTP_CODE)"
else
    echo "    ⚠️  Vault HTTPS: HTTP $HTTP_CODE"
fi

# Résumé final
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ HTTPS CONFIGURÉ POUR KEYCLOAK & VAULT           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔐 Configuration appliquée :"
echo "  - Certificats TLS via Vault PKI + cert-manager"
echo "  - Redirection automatique HTTP → HTTPS"
echo "  - Headers proxy via ConfigMap (pas de snippets)"
echo "  - Service Keycloak: $KEYCLOAK_SVC:$KEYCLOAK_PORT"
echo ""
echo "🌐 URLs HTTPS :"
echo "  Keycloak:        https://keycloak.local.lab"
echo "  Keycloak Admin:  https://keycloak.local.lab/admin"
echo "  Vault:           https://vault.local.lab"
echo "  Vault UI:        https://vault.local.lab/ui"
echo ""
echo "⚠️  Configuration du fichier hosts (si pas déjà fait) :"
echo ""
echo "Sur Windows (C:\\Windows\\System32\\drivers\\etc\\hosts) :"
echo "  $INGRESS_IP keycloak.local.lab"
echo "  $INGRESS_IP vault.local.lab"
echo ""
echo "Sur WSL2/Linux (/etc/hosts) :"
echo "  sudo tee -a /etc/hosts <<EOF"
echo "  $INGRESS_IP keycloak.local.lab"
echo "  $INGRESS_IP vault.local.lab"
echo "  EOF"
echo ""
echo "⚠️  Certificat auto-signé (CA Vault local)"
echo "  Le navigateur affichera un avertissement - c'est NORMAL"
echo "  Cliquez sur 'Avancé' → 'Continuer vers le site'"
echo ""
echo "🔐 Récupérer les credentials :"
echo "  # Keycloak admin password"
echo "  kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d"
echo ""
echo "  # Vault root token"
echo "  kubectl get secret vault-unseal-keys -n security-iam -o jsonpath='{.data.root-token}' | base64 -d 2>/dev/null || echo 'root'"
echo ""
echo "📊 Vérifier la configuration :"
echo "  kubectl get ingress -n security-iam"
echo "  kubectl describe ingress keycloak-ingress -n security-iam"
echo "  kubectl get certificate -n security-iam"
echo ""
