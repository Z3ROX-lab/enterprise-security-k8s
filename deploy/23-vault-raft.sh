#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                 Vault (Mode RAFT HA)                      ║"
echo "║         Gestion des Secrets (Production-Ready)           ║"
echo "║            Haute Disponibilité + Persistence             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Mode Raft HA - Caractéristiques :"
echo "  - 3 replicas pour haute disponibilité"
echo "  - Stockage persistent (survit aux redémarrages)"
echo "  - Nécessite initialisation + unseal manuel"
echo "  - Production-ready"
echo ""

read -p "Continuer avec le mode Raft HA ? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# Créer le namespace
kubectl create namespace security-iam --dry-run=client -o yaml | kubectl apply -f -

# Ajouter le repo Helm
echo ""
echo "📦 Configuration du repository Helm..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Déployer Vault en mode Raft
echo ""
echo "🔒 Déploiement de Vault 0.27.0 (mode Raft HA)..."
helm upgrade --install vault hashicorp/vault \
  --namespace security-iam \
  --version 0.27.0 \
  --set server.dev.enabled=false \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set server.ha.raft.enabled=true \
  --set server.dataStorage.enabled=true \
  --set server.dataStorage.size=10Gi \
  --set ui.enabled=true \
  --set injector.enabled=true \
  --timeout 10m \
  --wait=false

echo ""
echo "⏳ Attente que vault-0 soit prêt..."
for i in {1..20}; do
    if kubectl get pod -n security-iam vault-0 --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✅ vault-0 est Running !"
        break
    fi
    echo "  Check $i/20..."
    sleep 10
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ VAULT DÉPLOYÉ                                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🤖 Voulez-vous automatiser l'initialisation ? (recommandé pour dev/test)"
echo "   ⚠️  En production, faites-le manuellement pour plus de sécurité"
echo ""
read -p "Initialiser et unseal automatiquement ? (yes/no) " -r
echo

if [[ $REPLY =~ ^yes$ ]]; then
    echo ""
    echo "🔧 Initialisation automatique de Vault..."

    # Vérifier si déjà initialisé
    if kubectl exec -n security-iam vault-0 -- vault status 2>/dev/null | grep -q "Initialized.*true"; then
        echo "  ℹ️  Vault déjà initialisé, récupération du status..."

        # Vérifier si sealed
        if kubectl exec -n security-iam vault-0 -- vault status 2>/dev/null | grep -q "Sealed.*true"; then
            echo "  ⚠️  Vault est sealed mais déjà initialisé."
            echo "     Vous devez unseal manuellement avec les clés sauvegardées."
            echo "     Vérifiez le secret : kubectl get secret -n security-iam vault-unseal-keys"
        else
            echo "  ✅ Vault déjà initialisé et unsealed"
        fi
    else
        echo "  1️⃣  Initialisation de vault-0..."
        INIT_OUTPUT=$(kubectl exec -n security-iam vault-0 -- vault operator init -format=json)

        # Extraire les clés et le token
        UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
        UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
        UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
        UNSEAL_KEY_4=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[3]')
        UNSEAL_KEY_5=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[4]')
        ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

        echo "  ✅ Vault initialisé"
        echo ""
        echo "  📝 Sauvegarde des clés dans un secret Kubernetes..."
        kubectl create secret generic vault-unseal-keys -n security-iam \
            --from-literal=vault-root="$ROOT_TOKEN" \
            --from-literal=unseal-key-1="$UNSEAL_KEY_1" \
            --from-literal=unseal-key-2="$UNSEAL_KEY_2" \
            --from-literal=unseal-key-3="$UNSEAL_KEY_3" \
            --from-literal=unseal-key-4="$UNSEAL_KEY_4" \
            --from-literal=unseal-key-5="$UNSEAL_KEY_5" \
            --dry-run=client -o yaml | kubectl apply -f -

        echo "  ✅ Clés sauvegardées dans le secret 'vault-unseal-keys'"
        echo ""

        # Sauvegarder dans vault-keys.txt (LOCAL, pas dans git)
        echo "  💾 Sauvegarde des clés dans vault-keys.txt (local, gitignored)..."
        cat > vault-keys.txt <<EOF
Unseal Key 1: $UNSEAL_KEY_1
Unseal Key 2: $UNSEAL_KEY_2
Unseal Key 3: $UNSEAL_KEY_3
Unseal Key 4: $UNSEAL_KEY_4
Unseal Key 5: $UNSEAL_KEY_5

Initial Root Token: $ROOT_TOKEN

Vault initialized with 5 key shares and a key threshold of 3. Please securely
distribute the key shares printed above. When the Vault is re-sealed,
restarted, or stopped, you must supply at least 3 of these keys to unseal it
before it can start servicing requests.

Vault does not store the generated root key. Without at least 3 keys to
reconstruct the root key, Vault will remain permanently sealed!

It is possible to generate new unseal keys, provided you have a quorum of
existing unseal keys shares. See "vault operator rekey" for more information.
EOF
        echo "  ✅ Clés sauvegardées dans vault-keys.txt"
        echo "     ⚠️  Ce fichier contient des secrets ! Il est gitignored (ne sera pas committé)"
        echo "     ⚠️  Sauvegardez-le dans un endroit sûr (gestionnaire de mots de passe, Vault externe, etc.)"
        echo ""

        echo "  2️⃣  Unseal vault-0 (3 clés)..."
        kubectl exec -n security-iam vault-0 -- vault operator unseal "$UNSEAL_KEY_1" > /dev/null
        kubectl exec -n security-iam vault-0 -- vault operator unseal "$UNSEAL_KEY_2" > /dev/null
        kubectl exec -n security-iam vault-0 -- vault operator unseal "$UNSEAL_KEY_3" > /dev/null
        echo "  ✅ vault-0 unsealed"

        echo ""
        echo "  3️⃣  Attente que vault-1 démarre..."
        sleep 15
        if kubectl get pod -n security-iam vault-1 --no-headers 2>/dev/null | grep -q "Running"; then
            echo "  ✅ vault-1 est Running"
            echo "     Joining cluster..."
            kubectl exec -n security-iam vault-1 -- vault operator raft join http://vault-0.vault-internal:8200 > /dev/null || echo "     Déjà dans le cluster"
            echo "     Unseal vault-1..."
            kubectl exec -n security-iam vault-1 -- vault operator unseal "$UNSEAL_KEY_1" > /dev/null
            kubectl exec -n security-iam vault-1 -- vault operator unseal "$UNSEAL_KEY_2" > /dev/null
            kubectl exec -n security-iam vault-1 -- vault operator unseal "$UNSEAL_KEY_3" > /dev/null
            echo "  ✅ vault-1 unsealed"
        else
            echo "  ⏭️  vault-1 pas encore prêt, skip"
        fi

        echo ""
        echo "  4️⃣  Attente que vault-2 démarre..."
        sleep 15
        if kubectl get pod -n security-iam vault-2 --no-headers 2>/dev/null | grep -q "Running"; then
            echo "  ✅ vault-2 est Running"
            echo "     Joining cluster..."
            kubectl exec -n security-iam vault-2 -- vault operator raft join http://vault-0.vault-internal:8200 > /dev/null || echo "     Déjà dans le cluster"
            echo "     Unseal vault-2..."
            kubectl exec -n security-iam vault-2 -- vault operator unseal "$UNSEAL_KEY_1" > /dev/null
            kubectl exec -n security-iam vault-2 -- vault operator unseal "$UNSEAL_KEY_2" > /dev/null
            kubectl exec -n security-iam vault-2 -- vault operator unseal "$UNSEAL_KEY_3" > /dev/null
            echo "  ✅ vault-2 unsealed"
        else
            echo "  ⏭️  vault-2 pas encore prêt, skip"
        fi

        echo ""
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║     ✅ VAULT INITIALISÉ ET UNSEALED AUTOMATIQUEMENT       ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo ""
        echo "🔑 Credentials sauvegardés :"
        echo "   Secret Kubernetes: vault-unseal-keys (namespace: security-iam)"
        echo "   Root Token: $ROOT_TOKEN"
        echo ""
        echo "📊 Vérifier le statut :"
        kubectl exec -n security-iam vault-0 -- vault status
    fi
else
    echo ""
    echo "⚠️  ÉTAPES MANUELLES REQUISES :"
    echo ""
    echo "1️⃣  Initialiser Vault (génère les unseal keys) :"
    echo "    kubectl exec -n security-iam vault-0 -- vault operator init"
    echo "    ⚠️  SAUVEGARDER les unseal keys et root token !"
    echo ""
    echo "2️⃣  Unseal vault-0 (3 fois avec 3 clés différentes) :"
    echo "    kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY1>"
    echo "    kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY2>"
    echo "    kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY3>"
    echo ""
    echo "3️⃣  Joindre vault-1 au cluster :"
    echo "    kubectl exec -n security-iam vault-1 -- vault operator raft join http://vault-0.vault-internal:8200"
    echo "    kubectl exec -n security-iam vault-1 -- vault operator unseal <KEY1>"
    echo "    kubectl exec -n security-iam vault-1 -- vault operator unseal <KEY2>"
    echo "    kubectl exec -n security-iam vault-1 -- vault operator unseal <KEY3>"
    echo ""
    echo "4️⃣  Joindre vault-2 au cluster :"
    echo "    kubectl exec -n security-iam vault-2 -- vault operator raft join http://vault-0.vault-internal:8200"
    echo "    kubectl exec -n security-iam vault-2 -- vault operator unseal <KEY1>"
    echo "    kubectl exec -n security-iam vault-2 -- vault operator unseal <KEY2>"
    echo "    kubectl exec -n security-iam vault-2 -- vault operator unseal <KEY3>"
    echo ""
    echo "5️⃣  Créer le secret Kubernetes avec le root token :"
    echo "    kubectl create secret generic vault-unseal-keys -n security-iam \\"
    echo "      --from-literal=vault-root=<YOUR_ROOT_TOKEN>"
    echo ""
fi

echo ""
echo "Accès au dashboard :"
echo "  kubectl port-forward -n security-iam svc/vault 8200:8200"
echo "  http://localhost:8200"
echo ""
echo "Prochaine étape :"
echo "  ./24-vault-pki.sh (configurer le PKI engine)"
echo ""
