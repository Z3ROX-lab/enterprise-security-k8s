#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Ingress TLS avec cert-manager + Vault           ║"
echo "║         Certificats automatiques pour HTTPS               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que NGINX Ingress est installé
if ! kubectl get namespace ingress-nginx &>/dev/null; then
    echo "❌ NGINX Ingress Controller n'est pas installé"
    echo "Lancez d'abord : ./deploy/51-nginx-ingress.sh"
    exit 1
fi

# Vérifier que cert-manager est installé
if ! kubectl get namespace cert-manager &>/dev/null; then
    echo "❌ cert-manager n'est pas installé"
    echo "Lancez d'abord : ./deploy/40-cert-manager.sh"
    exit 1
fi

# Vérifier que Vault est installé
if ! kubectl get namespace security-iam &>/dev/null || ! kubectl get pods -n security-iam -l app.kubernetes.io/name=vault &>/dev/null 2>&1; then
    echo "❌ Vault n'est pas installé"
    echo "Lancez d'abord : ./deploy/20-vault.sh"
    exit 1
fi

echo "✅ Prérequis détectés (NGINX Ingress, cert-manager, Vault)"
echo ""
echo "📋 Ce script va :"
echo "  1. Configurer Vault PKI pour les certificats TLS"
echo "  2. Créer un ClusterIssuer cert-manager → Vault"
echo "  3. Mettre à jour les Ingress avec TLS"
echo "  4. Générer les certificats automatiquement"
echo ""
echo "🔐 Certificats créés pour :"
echo "  - grafana.local.lab"
echo "  - kibana.local.lab"
echo "  - prometheus.local.lab"
echo "  - falco-ui.local.lab"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

# ========================================================================
# 1. Vérifier/Configurer Vault PKI
# ========================================================================
echo ""
echo "1️⃣  Configuration de Vault PKI..."

# Vérifier si Vault est unsealed
VAULT_STATUS=$(kubectl exec -n security-iam vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")

if [ "$VAULT_STATUS" = "true" ]; then
    echo "  ⚠️  Vault est sealed. Unseal Vault d'abord:"
    echo "  kubectl exec -n security-iam vault-0 -- vault operator unseal"
    exit 1
fi

echo "  ✅ Vault est unsealed"

# Obtenir le root token
ROOT_TOKEN=$(kubectl get secret -n security-iam vault-init -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")

if [ -z "$ROOT_TOKEN" ]; then
    echo "  ⚠️  Root token Vault introuvable"
    echo "  Vault doit être initialisé avec : ./deploy/20-vault.sh"
    exit 1
fi

# Configurer PKI dans Vault
echo "  📝 Configuration du backend PKI dans Vault..."

kubectl exec -n security-iam vault-0 -- sh -c "
export VAULT_TOKEN=$ROOT_TOKEN

# Activer PKI si pas déjà fait
vault secrets enable -path=pki pki 2>/dev/null || true

# Configurer les TTLs
vault secrets tune -max-lease-ttl=87600h pki

# Générer le CA root
vault write -field=certificate pki/root/generate/internal \
    common_name='local.lab' \
    issuer_name='root-2024' \
    ttl=87600h > /dev/null 2>&1 || true

# Configurer les URLs
vault write pki/config/urls \
    issuing_certificates='http://vault.security-iam.svc.cluster.local:8200/v1/pki/ca' \
    crl_distribution_points='http://vault.security-iam.svc.cluster.local:8200/v1/pki/crl'

# Créer un rôle pour les certificats Ingress
vault write pki/roles/ingress-tls \
    allowed_domains='local.lab' \
    allow_subdomains=true \
    allow_glob_domains=true \
    max_ttl='720h' \
    ttl='720h'

# Créer une policy pour cert-manager
vault policy write cert-manager - <<EOF
path \"pki/sign/ingress-tls\" {
  capabilities = [\"create\", \"update\"]
}
path \"pki/issue/ingress-tls\" {
  capabilities = [\"create\"]
}
EOF

# Activer l'authentification Kubernetes si pas déjà fait
vault auth enable kubernetes 2>/dev/null || true

# Configurer l'authentification Kubernetes
vault write auth/kubernetes/config \
    kubernetes_host='https://kubernetes.default.svc:443'

# Créer un rôle pour cert-manager
vault write auth/kubernetes/role/cert-manager \
    bound_service_account_names=cert-manager \
    bound_service_account_namespaces=cert-manager \
    policies=cert-manager \
    ttl=24h
"

echo "  ✅ Vault PKI configuré"

# ========================================================================
# 2. Créer le ClusterIssuer pour Vault
# ========================================================================
echo ""
echo "2️⃣  Création du ClusterIssuer cert-manager → Vault..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    path: pki/sign/ingress-tls
    server: http://vault.security-iam.svc.cluster.local:8200
    auth:
      kubernetes:
        role: cert-manager
        mountPath: /v1/auth/kubernetes
        serviceAccountRef:
          name: cert-manager
EOF

echo "  ✅ ClusterIssuer 'vault-issuer' créé"

# Attendre que le ClusterIssuer soit prêt
echo "  ⏳ Attente de la synchronisation (10 secondes)..."
sleep 10

# ========================================================================
# 3. Mettre à jour les Ingress avec TLS
# ========================================================================
echo ""
echo "3️⃣  Mise à jour des Ingress avec TLS..."

# Grafana
echo "  📝 Grafana (grafana.local.lab)..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: security-siem
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "vault-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.local.lab
    secretName: grafana-tls
  rules:
  - host: grafana.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-grafana
            port:
              number: 80
EOF
echo "    ✅ Grafana Ingress mis à jour"

# Kibana
echo "  📝 Kibana (kibana.local.lab)..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: security-siem
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    cert-manager.io/cluster-issuer: "vault-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - kibana.local.lab
    secretName: kibana-tls
  rules:
  - host: kibana.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana-kibana
            port:
              number: 5601
EOF
echo "    ✅ Kibana Ingress mis à jour"

# Prometheus
echo "  📝 Prometheus (prometheus.local.lab)..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: security-siem
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "vault-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.local.lab
    secretName: prometheus-tls
  rules:
  - host: prometheus.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-kube-prometheus-prometheus
            port:
              number: 9090
EOF
echo "    ✅ Prometheus Ingress mis à jour"

# Falcosidekick UI
echo "  📝 Falcosidekick UI (falco-ui.local.lab)..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: falcosidekick-ui-ingress
  namespace: security-detection
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/websocket-services: "falco-falcosidekick-ui"
    cert-manager.io/cluster-issuer: "vault-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - falco-ui.local.lab
    secretName: falco-ui-tls
  rules:
  - host: falco-ui.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: falco-falcosidekick-ui
            port:
              number: 2802
EOF
echo "    ✅ Falcosidekick UI Ingress mis à jour"

# ========================================================================
# 4. Vérifier la génération des certificats
# ========================================================================
echo ""
echo "4️⃣  Vérification de la génération des certificats..."
echo "  ⏳ Attente de cert-manager (30 secondes)..."
sleep 30

echo ""
echo "  📜 Certificats dans security-siem:"
kubectl get certificates -n security-siem

echo ""
echo "  📜 Certificats dans security-detection:"
kubectl get certificates -n security-detection

# ========================================================================
# Résumé final
# ========================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           ✅ TLS CONFIGURÉ POUR LES INGRESS               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔐 Certificats TLS générés par Vault PKI via cert-manager"
echo ""
echo "🌐 URLs HTTPS (remplacer http:// par https://) :"
echo "  Grafana:         https://grafana.local.lab"
echo "  Kibana:          https://kibana.local.lab"
echo "  Prometheus:      https://prometheus.local.lab"
echo "  Falcosidekick UI: https://falco-ui.local.lab"
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
echo "  kubectl exec -n security-iam vault-0 -- sh -c \""
echo "    export VAULT_TOKEN=$ROOT_TOKEN && \\"
echo "    vault read -field=certificate pki/cert/ca\" > vault-ca.crt"
echo ""
echo "  Importez vault-ca.crt dans votre navigateur (Paramètres → Certificats)"
echo ""
echo "🔍 Vérifier les certificats :"
echo "  kubectl get certificates -A"
echo "  kubectl describe certificate grafana-tls -n security-siem"
echo "  kubectl get secrets -n security-siem | grep tls"
echo ""
echo "🔄 Renouvellement automatique :"
echo "  Les certificats seront renouvelés automatiquement par cert-manager"
echo "  avant leur expiration (720h = 30 jours)"
echo ""
