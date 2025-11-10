#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                   Vault (Mode DEV)                        ║"
echo "║            Gestion des Secrets (Non-Production)          ║"
echo "║         ⚠️  PAS pour Production (données volatile)       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  Mode DEV : Données perdues au redémarrage !"
echo "   Pour production, utilisez : ./23-vault-raft.sh"
echo ""

read -p "Continuer avec le mode DEV ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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

# Déployer Vault en mode DEV
echo ""
echo "🔒 Déploiement de Vault 0.27.0 (mode DEV)..."
helm upgrade --install vault hashicorp/vault \
  --namespace security-iam \
  --version 0.27.0 \
  --set server.dev.enabled=true \
  --set server.ha.enabled=false \
  --set ui.enabled=true \
  --set injector.enabled=true \
  --timeout 10m \
  --wait=false

echo ""
echo "⏳ Attente que Vault démarre..."
for i in {1..10}; do
    if kubectl get pod -n security-iam -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | grep -q "Running"; then
        echo "✅ Vault est Running !"
        break
    fi
    echo "  Check $i/10..."
    sleep 30
done

echo ""
echo "📊 État des pods :"
kubectl get pods -n security-iam -l app.kubernetes.io/name=vault

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            ✅ VAULT DÉPLOYÉ (Mode DEV)                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  MODE DEV - Caractéristiques :"
echo "  - Root token : 'root'"
echo "  - Auto-unseal"
echo "  - Données en mémoire (perdues au redémarrage)"
echo "  - HTTP non-TLS"
echo ""
echo "Accès au dashboard :"
echo "  kubectl port-forward -n security-iam svc/vault 8200:8200"
echo "  http://localhost:8200"
echo "  Token: root"
echo ""
echo "Test CLI :"
echo "  kubectl exec -n security-iam vault-0 -- vault status"
echo ""
echo "Pour production :"
echo "  ./23-vault-raft.sh"
echo ""
