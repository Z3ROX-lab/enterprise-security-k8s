#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Fix Vault PKI role: disable CN requirement           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Problème détecté :"
echo "  Le rôle Vault PKI 'ingress-tls' exige un Common Name (CN)"
echo "  dans le CSR, mais cert-manager utilise uniquement dnsNames"
echo "  (standard moderne avec SANs)."
echo ""
echo "💡 Solution :"
echo "  Modifier le rôle Vault PKI pour accepter les certificats"
echo "  sans CN en ajoutant 'require_cn=false'."
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

echo ""
echo "1️⃣  Lecture du root token..."

# Lire le root token depuis vault-keys.txt (local) ou secret Kubernetes
if [ -f "vault-keys.txt" ]; then
    echo "  📄 Lecture depuis vault-keys.txt (local)"
    ROOT_TOKEN=$(grep "Initial Root Token:" vault-keys.txt | awk '{print $NF}')
elif kubectl get secret -n security-iam vault-unseal-keys &> /dev/null; then
    echo "  🔑 Lecture depuis le secret Kubernetes vault-unseal-keys"
    ROOT_TOKEN=$(kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data.root-token}' | base64 -d)
else
    echo "  ❌ Impossible de trouver le root token !"
    echo "     Ni vault-keys.txt ni le secret vault-unseal-keys n'existent."
    exit 1
fi

if [ -z "$ROOT_TOKEN" ]; then
    echo "  ❌ Le root token est vide !"
    exit 1
fi

echo "  ✅ Root token récupéré"

echo ""
echo "2️⃣  Vérification de l'état de Vault..."

# Vérifier que vault-0 est accessible
if ! kubectl exec -n security-iam vault-0 -- vault status > /dev/null 2>&1; then
    echo "  ❌ Vault n'est pas accessible !"
    echo "     Vérifier que les pods sont unsealed :"
    echo "     ./scripts/vault-unseal.sh vault-keys.txt"
    exit 1
fi

echo "  ✅ Vault accessible"

echo ""
echo "3️⃣  Lecture de la configuration actuelle du rôle..."

kubectl exec -n security-iam vault-0 -- sh -c "
VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='$ROOT_TOKEN' vault read pki/roles/ingress-tls
"

echo ""
echo "4️⃣  Modification du rôle Vault PKI pour désactiver CN requirement..."

kubectl exec -n security-iam vault-0 -- sh -c "
VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='$ROOT_TOKEN' vault write pki/roles/ingress-tls \
    allowed_domains='local.lab' \
    allow_subdomains=true \
    max_ttl='720h' \
    require_cn=false \
    use_csr_common_name=false
"

echo ""
echo "  ✅ Rôle PKI modifié avec succès"

echo ""
echo "5️⃣  Vérification de la nouvelle configuration..."

kubectl exec -n security-iam vault-0 -- sh -c "
VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='$ROOT_TOKEN' vault read pki/roles/ingress-tls
" | grep -E "require_cn|use_csr_common_name"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ RÔLE VAULT PKI MODIFIÉ                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Changements appliqués :"
echo "  - require_cn: false (n'exige plus de Common Name)"
echo "  - use_csr_common_name: false (ignore le CN du CSR s'il existe)"
echo ""
echo "🔄 Prochaine étape :"
echo "  Les certificaterequests vont automatiquement réessayer."
echo "  Attendre 1-2 minutes ou forcer une nouvelle tentative avec :"
echo ""
echo "  ./deploy/56-certificates-force-retry.sh"
echo ""
echo "📊 Vérifier l'état des certificats :"
echo "  kubectl get certificates -A"
echo ""
