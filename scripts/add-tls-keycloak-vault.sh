#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Ajout TLS pour Keycloak et Vault Ingress            ║"
echo "║          Certificats via cert-manager + Vault             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que cert-manager et Vault sont prêts
if ! kubectl get clusterissuer vault-issuer &>/dev/null; then
    echo "❌ ClusterIssuer 'vault-issuer' non trouvé"
    echo "Lancez d'abord: ./deploy/53-ingress-tls.sh"
    exit 1
fi

echo "✅ ClusterIssuer 'vault-issuer' détecté"
echo ""
echo "📋 Ce script va :"
echo "  1. Créer des certificats TLS pour Keycloak et Vault"
echo "  2. Mettre à jour les Ingress pour activer HTTPS"
echo "  3. Rediriger automatiquement HTTP → HTTPS"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# ========================================================================
# 1. Créer le certificat pour Keycloak
# ========================================================================
echo ""
echo "1️⃣  Création du certificat TLS pour Keycloak..."

cat <<EOF | kubectl apply -f -
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
EOF

echo "  ✅ Certificat Keycloak créé"

# ========================================================================
# 2. Créer le certificat pour Vault
# ========================================================================
echo ""
echo "2️⃣  Création du certificat TLS pour Vault..."

cat <<EOF | kubectl apply -f -
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

echo "  ✅ Certificat Vault créé"

# ========================================================================
# 3. Attendre la génération des certificats
# ========================================================================
echo ""
echo "3️⃣  Attente de la génération des certificats..."
echo "  ⏳ Cela peut prendre 10-20 secondes..."

sleep 15

# Vérifier le statut des certificats
echo ""
echo "  📜 Statut des certificats:"
kubectl get certificate -n security-iam keycloak-tls vault-tls 2>/dev/null || echo "  ⚠️  Certificats en cours de création..."

# ========================================================================
# 4. Identifier le bon service Keycloak
# ========================================================================
echo ""
echo "4️⃣  Identification du service Keycloak..."

KEYCLOAK_SVC=$(kubectl get svc -n security-iam -o json | jq -r '.items[] | select(.metadata.name | contains("keycloak")) | select(.spec.clusterIP != "None") | .metadata.name' | head -n1)

if [ -z "$KEYCLOAK_SVC" ]; then
    echo "  ⚠️  Service principal non trouvé, utilisation de 'keycloak'"
    KEYCLOAK_SVC="keycloak"
fi

KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
if [ -z "$KEYCLOAK_PORT" ]; then
    KEYCLOAK_PORT=$(kubectl get svc $KEYCLOAK_SVC -n security-iam -o jsonpath='{.spec.ports[0].port}')
fi

echo "  ✅ Service: $KEYCLOAK_SVC:$KEYCLOAK_PORT"

# ========================================================================
# 5. Mettre à jour l'Ingress Keycloak avec TLS
# ========================================================================
echo ""
echo "5️⃣  Mise à jour de l'Ingress Keycloak avec TLS..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: security-iam
  annotations:
    # Redirection HTTP → HTTPS
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Configuration backend
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    # Headers pour Keycloak
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Port \$server_port;
    # Certificat cert-manager
    cert-manager.io/cluster-issuer: vault-issuer
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

echo "  ✅ Ingress Keycloak mis à jour avec TLS"

# ========================================================================
# 6. Mettre à jour l'Ingress Vault avec TLS
# ========================================================================
echo ""
echo "6️⃣  Mise à jour de l'Ingress Vault avec TLS..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: security-iam
  annotations:
    # Redirection HTTP → HTTPS
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Configuration backend
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    # Certificat cert-manager
    cert-manager.io/cluster-issuer: vault-issuer
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

echo "  ✅ Ingress Vault mis à jour avec TLS"

# ========================================================================
# 7. Vérification finale
# ========================================================================
echo ""
echo "7️⃣  Vérification finale..."
sleep 10

echo ""
echo "  📜 Certificats dans security-iam:"
kubectl get certificate -n security-iam

echo ""
echo "  📊 Ingress dans security-iam:"
kubectl get ingress -n security-iam

# ========================================================================
# 8. Test de connectivité HTTPS
# ========================================================================
echo ""
echo "8️⃣  Test de connectivité HTTPS..."

INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "  📡 IP Ingress: $INGRESS_IP"
echo ""

echo "  🧪 Test Keycloak HTTPS..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: keycloak.local.lab" https://$INGRESS_IP --connect-timeout 10 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "    ✅ Keycloak HTTPS accessible (HTTP $HTTP_CODE)"
else
    echo "    ⚠️  Keycloak HTTPS: HTTP $HTTP_CODE"
fi

echo "  🧪 Test Vault HTTPS..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: vault.local.lab" https://$INGRESS_IP/v1/sys/health --connect-timeout 10 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "429" ] || [ "$HTTP_CODE" = "473" ] || [ "$HTTP_CODE" = "501" ] || [ "$HTTP_CODE" = "503" ]; then
    echo "    ✅ Vault HTTPS accessible (HTTP $HTTP_CODE)"
else
    echo "    ⚠️  Vault HTTPS: HTTP $HTTP_CODE"
fi

# ========================================================================
# Résumé final
# ========================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ TLS CONFIGURÉ POUR KEYCLOAK & VAULT            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔐 Certificats TLS générés par Vault PKI via cert-manager"
echo ""
echo "🌐 URLs HTTPS :"
echo "  Keycloak:        https://keycloak.local.lab"
echo "  Keycloak Admin:  https://keycloak.local.lab/admin"
echo "  Vault:           https://vault.local.lab"
echo "  Vault UI:        https://vault.local.lab/ui"
echo ""
echo "⚠️  Certificat auto-signé (CA Vault local)"
echo "  Votre navigateur affichera un avertissement de sécurité"
echo "  C'est NORMAL pour un environnement de lab/démo"
echo ""
echo "🔧 Pour accepter le certificat :"
echo "  1. Dans le navigateur, cliquez sur 'Avancé' ou 'Advanced'"
echo "  2. Cliquez sur 'Continuer vers le site (non sécurisé)'"
echo "  3. Ou importez le CA Vault dans votre navigateur"
echo ""
echo "📊 Exporter le CA Vault (optionnel) :"
echo "  kubectl exec -n security-iam vault-0 -- sh -c \\"
echo "    export VAULT_TOKEN=\$(kubectl get secret vault-unseal-keys -n security-iam -o jsonpath='{.data.root-token}' | base64 -d) && \\"
echo "    vault read -field=certificate pki/cert/ca\\" > vault-ca.crt"
echo ""
echo "  Importez vault-ca.crt dans votre navigateur (Paramètres → Certificats)"
echo ""
echo "🔄 Redirection automatique HTTP → HTTPS activée"
echo "  http://keycloak.local.lab redirige vers https://keycloak.local.lab"
echo ""
echo "🔍 Vérifier les certificats :"
echo "  kubectl get certificates -n security-iam"
echo "  kubectl describe certificate keycloak-tls -n security-iam"
echo "  kubectl describe certificate vault-tls -n security-iam"
echo ""
echo "🔐 Credentials (inchangés) :"
echo "  Keycloak: kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d"
echo "  Vault:    kubectl get secret vault-unseal-keys -n security-iam -o jsonpath='{.data.root-token}' | base64 -d 2>/dev/null || echo 'root'"
echo ""
