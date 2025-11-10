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
echo "⏳ Attente que les pods démarrent..."
sleep 30
kubectl get pods -n security-iam -l app.kubernetes.io/name=vault

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ VAULT DÉPLOYÉ (initialisation requise)         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  ÉTAPES OBLIGATOIRES POST-INSTALLATION :"
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
echo "5️⃣  Vérifier le statut :"
echo "    kubectl exec -n security-iam vault-0 -- vault status"
echo ""
echo "Accès au dashboard (après unseal) :"
echo "  kubectl port-forward -n security-iam svc/vault 8200:8200"
echo "  http://localhost:8200"
echo "  Token: <root_token_from_init>"
echo ""
