#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Ajout Ingress pour MinIO Console Web               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🌐 Ce script expose la console MinIO via Ingress NGINX"
echo "   URL: https://minio.local.lab:8443/"
echo ""

# Variables
NAMESPACE="minio"
INGRESS_NAME="minio-console-ingress"
HOSTNAME="minio.local.lab"

echo "🔍 Vérification des prérequis..."

# Vérifier que MinIO est déployé
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo "❌ Namespace $NAMESPACE n'existe pas"
    echo "   Déployez MinIO d'abord: ./scripts/deploy-minio.sh"
    exit 1
fi

if ! kubectl get service minio -n $NAMESPACE &>/dev/null; then
    echo "❌ Service MinIO non trouvé"
    echo "   Déployez MinIO d'abord: ./scripts/deploy-minio.sh"
    exit 1
fi

echo "   ✅ MinIO trouvé dans le namespace $NAMESPACE"

# Vérifier que l'Ingress Controller est actif
if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx &>/dev/null; then
    echo "⚠️  Ingress Controller NGINX non trouvé"
    echo "   Le déploiement va continuer, mais l'Ingress ne sera pas fonctionnel"
fi

echo ""
echo "📝 Configuration Ingress:"
echo "   Namespace: $NAMESPACE"
echo "   Hostname: $HOSTNAME"
echo "   Backend: minio:9001 (console)"
echo ""

read -p "Continuer avec le déploiement ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "🚀 Étape 1: Créer l'Ingress pour MinIO Console..."

cat <<EOF | kubectl apply -f -
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $INGRESS_NAME
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    # MinIO console nécessite ces headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Port \$server_port;
spec:
  ingressClassName: nginx
  rules:
  - host: $HOSTNAME
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: minio
            port:
              number: 9001
EOF

echo "   ✅ Ingress créé"

echo ""
echo "🌐 Étape 2: Configurer /etc/hosts..."

# Vérifier si l'entrée existe déjà
if grep -q "^127.0.0.1.*$HOSTNAME" /etc/hosts 2>/dev/null; then
    echo "   ✅ Entrée $HOSTNAME déjà présente dans /etc/hosts"
else
    echo "   Ajout de $HOSTNAME à /etc/hosts..."
    if [ "$EUID" -ne 0 ]; then
        echo "   ⚠️  Droits sudo requis pour modifier /etc/hosts"
        echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
    else
        echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
    fi
    echo "   ✅ Entrée ajoutée"
fi

echo ""
echo "📊 État final:"
kubectl get ingress -n $NAMESPACE
echo ""
kubectl get service -n $NAMESPACE

echo ""
echo "✅ Ingress MinIO configuré avec succès !"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "   🌐 ACCÈS À LA CONSOLE MINIO"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "1️⃣  Assurez-vous que le port-forward Ingress est actif:"
echo "   ./scripts/port-forward-ingress.sh"
echo "   ou:"
echo "   ./scripts/start-ingress-portforward.sh"
echo ""
echo "2️⃣  Accédez à MinIO Console:"
echo "   🔗 URL: http://minio.local.lab:8080/"
echo "   ou avec HTTPS (si configuré):"
echo "   🔗 URL: https://minio.local.lab:8443/"
echo ""
echo "3️⃣  Credentials de connexion:"
echo "   👤 Username: minio"
echo "   🔑 Password: minio123"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📦 Dans la console MinIO vous pourrez:"
echo "   ✅ Voir le bucket 'velero' avec tous vos backups"
echo "   ✅ Explorer le contenu des backups"
echo "   ✅ Vérifier l'espace disque utilisé"
echo "   ✅ Gérer les fichiers de backup manuellement si besoin"
echo ""
echo "🔍 Commandes utiles:"
echo "   # Vérifier l'Ingress"
echo "   kubectl get ingress -n $NAMESPACE"
echo ""
echo "   # Voir les logs MinIO"
echo "   kubectl logs -n $NAMESPACE -l app=minio -f"
echo ""
echo "   # Test de connectivité"
echo "   curl -I http://minio.local.lab:8080/"
echo ""
