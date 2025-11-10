#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Vault PKI Engine                       ║"
echo "║         Configure Vault comme Certificate Authority      ║"
echo "║          Intégration avec cert-manager                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

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
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write -format=json pki_int/intermediate/generate/internal \
    common_name="Enterprise Security Intermediate CA" \
    | jq -r '.data.csr' > /tmp/pki_intermediate.csr 2>/dev/null || echo "  CSR déjà existant"

# Signer le CSR avec le Root CA
echo ""
echo "6️⃣  Signature du Intermediate CA..."
if [ -f /tmp/pki_intermediate.csr ]; then
    kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write -format=json pki/root/sign-intermediate \
        csr=@/tmp/pki_intermediate.csr \
        format=pem_bundle ttl="43800h" \
        | jq -r '.data.certificate' > /tmp/intermediate.cert.pem

    # Importer le certificat signé
    cat /tmp/intermediate.cert.pem | kubectl exec -i -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write pki_int/intermediate/set-signed certificate=-
fi

# Créer un rôle pour cert-manager
echo ""
echo "7️⃣  Création d'un rôle pour cert-manager..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault write pki_int/roles/cert-manager \
    allowed_domains="example.com,security-iam.svc.cluster.local" \
    allow_subdomains=true \
    max_ttl="720h"

# Créer une policy pour cert-manager
echo ""
echo "8️⃣  Création de la policy..."
kubectl exec -n security-iam vault-0 -- env VAULT_TOKEN=$ROOT_TOKEN vault policy write cert-manager - <<EOF
path "pki_int/sign/cert-manager" {
  capabilities = ["create", "update"]
}

path "pki_int/issue/cert-manager" {
  capabilities = ["create"]
}
EOF

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ VAULT PKI CONFIGURÉ                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ Root CA créé"
echo "  ✅ Intermediate CA créé et signé"
echo "  ✅ Rôle cert-manager configuré"
echo "  ✅ Policy créée"
echo ""
echo "Prochaines étapes :"
echo "  - Créer un Issuer cert-manager qui utilise Vault"
echo "  - Créer des Certificates avec cert-manager"
echo ""
echo "Exemple d'Issuer :"
echo '  kubectl apply -f - <<EOF'
echo '  apiVersion: cert-manager.io/v1'
echo '  kind: Issuer'
echo '  metadata:'
echo '    name: vault-issuer'
echo '    namespace: default'
echo '  spec:'
echo '    vault:'
echo '      server: http://vault.security-iam:8200'
echo '      path: pki_int/sign/cert-manager'
echo '      auth:'
echo '        tokenSecretRef:'
echo '          name: vault-token'
echo '          key: token'
echo '  EOF'
echo ""
