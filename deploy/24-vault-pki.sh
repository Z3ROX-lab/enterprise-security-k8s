#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Vault PKI Engine                       ║"
echo "║         Configure Vault comme Certificate Authority      ║"
echo "║          Intégration avec cert-manager                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que jq est installé
if ! command -v jq &> /dev/null; then
    echo "⚠️  jq n'est pas installé (requis pour parser JSON)"
    echo ""
    read -p "Installer jq automatiquement ? (yes/no) " -r
    echo
    if [[ $REPLY =~ ^yes$ ]]; then
        echo "📦 Installation de jq..."
        sudo apt update && sudo apt install -y jq
        if command -v jq &> /dev/null; then
            echo "✅ jq installé avec succès"
        else
            echo "❌ Échec de l'installation de jq"
            exit 1
        fi
    else
        echo "❌ Installation annulée"
        echo "   Installez jq manuellement : sudo apt install -y jq"
        exit 1
    fi
fi

# Vérifier que Vault existe
if ! kubectl get pod -n security-iam vault-0 &>/dev/null; then
    echo "❌ Vault non trouvé"
    echo "Lancez d'abord : ./22-vault-dev.sh ou ./23-vault-raft.sh"
    exit 1
fi

# Vérifier que cert-manager existe
if ! kubectl get pod -n cert-manager -l app=cert-manager &>/dev/null; then
    echo "❌ cert-manager non trouvé"
    echo "Lancez d'abord : ./20-cert-manager.sh"
    exit 1
fi

echo "📋 Ce script va :"
echo "  1. Activer le PKI engine dans Vault"
echo "  2. Créer un Root CA"
echo "  3. Créer un Intermediate CA"
echo "  4. Configurer cert-manager pour utiliser Vault"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

# Récupérer le root token selon le mode (DEV ou PROD)
echo "🔍 Détection du mode Vault..."
if kubectl exec -n security-iam vault-0 -- env | grep -q "VAULT_DEV_ROOT_TOKEN_ID"; then
    echo "  Mode: DEV"
    ROOT_TOKEN="root"
else
    echo "  Mode: PRODUCTION (Raft)"
    # Récupérer le root token depuis le secret Kubernetes
    if kubectl get secret -n security-iam vault-unseal-keys &>/dev/null; then
        ROOT_TOKEN=$(kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)
        echo "  ✅ Root token récupéré"
    elif kubectl get secret -n security-iam vault-init &>/dev/null; then
        ROOT_TOKEN=$(kubectl get secret -n security-iam vault-init -o jsonpath='{.data.root-token}' | base64 -d)
        echo "  ✅ Root token récupéré"
    else
        echo "❌ Impossible de trouver le root token"
        echo ""
        echo "Pour Vault Raft (production), le root token devrait être dans un secret."
        echo "Vérifiez avec : kubectl get secrets -n security-iam | grep vault"
        echo ""
        echo "Si Vault vient d'être déployé, initialisez-le :"
        echo "  kubectl exec -n security-iam vault-0 -- vault operator init"
        exit 1
    fi
fi

# Vérifier que Vault n'est pas sealed
if kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault status 2>/dev/null | grep -q "Sealed.*true"; then
    echo "❌ Vault est sealed. Unseal-le d'abord."
    echo "   kubectl exec -n security-iam vault-0 -- vault operator unseal"
    exit 1
fi

echo "  ✅ Vault accessible et unsealed"

echo ""
echo "🔧 Configuration du PKI Engine..."

# Activer le PKI engine
echo ""
echo "1️⃣  Activation du PKI engine (root)..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=pki pki || echo "  Déjà activé"
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault secrets tune -max-lease-ttl=87600h pki

# Générer le Root CA
echo ""
echo "2️⃣  Génération du Root CA..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write -field=certificate pki/root/generate/internal \
    common_name="Enterprise Security Root CA" \
    ttl=87600h > /tmp/root_ca.crt 2>/dev/null || echo "  Root CA déjà existant"

# Configurer les URLs du CA
echo ""
echo "3️⃣  Configuration des URLs du CA..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write pki/config/urls \
    issuing_certificates="http://vault.security-iam:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.security-iam:8200/v1/pki/crl"

# Activer le PKI Intermediate
echo ""
echo "4️⃣  Activation du PKI Intermediate..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=pki_int pki || echo "  Déjà activé"
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault secrets tune -max-lease-ttl=43800h pki_int

# Générer le CSR Intermediate
echo ""
echo "5️⃣  Génération du Intermediate CA CSR..."

# Vérifier si l'intermediate est déjà configuré
if kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault read pki_int/cert/ca &>/dev/null; then
    echo "  ✅ Intermediate CA déjà configuré"
else
    echo "  Génération du CSR..."
    CSR_OUTPUT=$(kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write -format=json pki_int/intermediate/generate/internal \
        common_name="Enterprise Security Intermediate CA" \
        ttl=43800h)

    echo "$CSR_OUTPUT" | jq -r '.data.csr' > /tmp/pki_intermediate.csr

    if [ ! -s /tmp/pki_intermediate.csr ]; then
        echo "  ❌ Échec de la génération du CSR"
        echo "$CSR_OUTPUT"
        exit 1
    fi

    echo "  ✅ CSR généré"

    # Signer le CSR avec le Root CA
    echo ""
    echo "6️⃣  Signature du Intermediate CA..."
    CERT_OUTPUT=$(kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write -format=json pki/root/sign-intermediate \
        csr="$(cat /tmp/pki_intermediate.csr)" \
        format=pem_bundle \
        ttl="43800h")

    echo "$CERT_OUTPUT" | jq -r '.data.certificate' > /tmp/intermediate.cert.pem

    if [ ! -s /tmp/intermediate.cert.pem ]; then
        echo "  ❌ Échec de la signature"
        echo "$CERT_OUTPUT"
        exit 1
    fi

    echo "  ✅ Certificat signé"

    # Importer le certificat signé
    echo "  Import du certificat..."
    cat /tmp/intermediate.cert.pem | kubectl exec -i -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write pki_int/intermediate/set-signed certificate=-
    echo "  ✅ Intermediate CA configuré"
fi

# Créer un rôle pour cert-manager
echo ""
echo "6️⃣  Création d'un rôle pour cert-manager..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write pki_int/roles/cert-manager \
    allowed_domains="example.com,security-iam.svc.cluster.local" \
    allow_subdomains=true \
    max_ttl="720h"

# Créer une policy pour cert-manager
echo ""
echo "7️⃣  Création de la policy..."
POLICY_CONTENT='path "pki_int/sign/cert-manager" {
  capabilities = ["create", "update"]
}

path "pki_int/issue/cert-manager" {
  capabilities = ["create"]
}'

echo "$POLICY_CONTENT" | kubectl exec -i -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault policy write cert-manager -

# Créer un token pour cert-manager avec la policy
echo ""
echo "8️⃣  Création d'un token pour cert-manager..."
CERT_MANAGER_TOKEN=$(kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=cert-manager -format=json | jq -r '.auth.client_token')

if [ -z "$CERT_MANAGER_TOKEN" ] || [ "$CERT_MANAGER_TOKEN" = "null" ]; then
    echo "  ❌ Échec de la création du token"
    exit 1
fi

echo "  ✅ Token créé"

# Créer le secret Kubernetes avec le token
echo ""
echo "9️⃣  Création du secret Kubernetes pour cert-manager..."
kubectl create secret generic vault-token -n cert-manager \
    --from-literal=token="$CERT_MANAGER_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "  ✅ Secret 'vault-token' créé dans cert-manager namespace"

# Créer le ClusterIssuer
echo ""
echo "🔟 Création du ClusterIssuer Vault..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: http://vault.security-iam:8200
    path: pki_int/sign/cert-manager
    auth:
      tokenSecretRef:
        name: vault-token
        key: token
EOF

echo "  ✅ ClusterIssuer 'vault-issuer' créé"

# Créer un certificat de test
echo ""
echo "1️⃣1️⃣  Création d'un certificat de test..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-vault-certificate
  namespace: default
spec:
  secretName: test-vault-cert-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: test.example.com
  dnsNames:
    - test.example.com
    - "*.test.example.com"
EOF

echo "  ✅ Certificat de test créé"
echo ""
echo "  ⏳ Attente de l'émission du certificat (10 sec)..."
sleep 10

# Vérifier le certificat
echo ""
echo "📊 Vérification du certificat..."
kubectl get certificate -n default test-vault-certificate
echo ""
kubectl describe certificate -n default test-vault-certificate | grep -A 5 "Status:"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       ✅ VAULT PKI + CERT-MANAGER CONFIGURÉS              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ Root CA créé"
echo "  ✅ Intermediate CA créé et signé"
echo "  ✅ Rôle cert-manager configuré"
echo "  ✅ Policy créée"
echo "  ✅ Token cert-manager créé"
echo "  ✅ Secret Kubernetes créé"
echo "  ✅ ClusterIssuer 'vault-issuer' déployé"
echo "  ✅ Certificat de test créé"
echo ""
echo "🎯 Utilisation :"
echo "  Pour créer un certificat dans n'importe quel namespace :"
echo ""
echo '  kubectl apply -f - <<EOF'
echo '  apiVersion: cert-manager.io/v1'
echo '  kind: Certificate'
echo '  metadata:'
echo '    name: mon-certificat'
echo '    namespace: mon-namespace'
echo '  spec:'
echo '    secretName: mon-cert-tls'
echo '    issuerRef:'
echo '      name: vault-issuer'
echo '      kind: ClusterIssuer'
echo '    commonName: mon-service.example.com'
echo '    dnsNames:'
echo '      - mon-service.example.com'
echo '  EOF'
echo ""
echo "📋 Commandes utiles :"
echo "  # Lister les certificats"
echo "  kubectl get certificates --all-namespaces"
echo ""
echo "  # Voir les détails d'un certificat"
echo "  kubectl describe certificate <name> -n <namespace>"
echo ""
echo "  # Voir le certificat de test"
echo "  kubectl get secret test-vault-cert-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout"
echo ""
