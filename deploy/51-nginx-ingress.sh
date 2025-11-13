#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            NGINX Ingress Controller avec LoadBalancer    ║"
echo "║        Exposer tous les services via Ingress + TLS       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que MetalLB est installé
if ! kubectl get namespace metallb-system &>/dev/null; then
    echo "❌ MetalLB n'est pas installé"
    echo "Lancez d'abord : ./deploy/50-metallb.sh"
    exit 1
fi

echo "✅ MetalLB détecté"
echo ""
echo "📋 Ce script va :"
echo "  1. Déployer NGINX Ingress Controller via Helm"
echo "  2. Créer un LoadBalancer (IP externe via MetalLB)"
echo "  3. Configurer pour supporter les WebSockets (Falcosidekick UI)"
echo "  4. Préparer pour les certificats TLS (cert-manager + Vault)"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# 1. Ajouter le repo Helm NGINX Ingress
echo ""
echo "1️⃣  Ajout du repository Helm NGINX Ingress..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
echo "  ✅ Repository ajouté"

# 2. Créer le namespace
echo ""
echo "2️⃣  Création du namespace ingress-nginx..."
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
echo "  ✅ Namespace créé"

# 3. Installer NGINX Ingress Controller
echo ""
echo "3️⃣  Installation de NGINX Ingress Controller..."

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."metallb\.universe\.tf/allow-shared-ip"="ingress" \
  --set controller.replicaCount=2 \
  --set controller.admissionWebhooks.enabled=true \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.additionalLabels.release="prometheus" \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.compute-full-forwarded-for="true" \
  --set controller.config.proxy-buffer-size="16k" \
  --set controller.config.proxy-body-size="100m" \
  --set controller.config.ssl-protocols="TLSv1.2 TLSv1.3" \
  --set controller.config.ssl-ciphers="ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384" \
  --set controller.config.enable-brotli="true" \
  --wait

echo "  ✅ NGINX Ingress Controller installé"

# 4. Attendre l'allocation de l'IP externe
echo ""
echo "4️⃣  Attente de l'allocation de l'IP externe par MetalLB..."
echo "  ⏳ Cela peut prendre 30-60 secondes..."

# Attendre jusqu'à 2 minutes
for i in {1..24}; do
    INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$INGRESS_IP" ]; then
        echo "  ✅ IP externe allouée: $INGRESS_IP"
        break
    fi

    if [ $i -eq 24 ]; then
        echo "  ⚠️  Timeout: IP externe non allouée après 2 minutes"
        echo "  Vérifiez MetalLB: kubectl get pods -n metallb-system"
        echo "  Vérifiez le service: kubectl get svc ingress-nginx-controller -n ingress-nginx"
        exit 1
    fi

    sleep 5
    echo "  ⏳ Tentative $i/24..."
done

# 5. Tester le Ingress Controller
echo ""
echo "5️⃣  Test du NGINX Ingress Controller..."

# Test de connectivité
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$INGRESS_IP --connect-timeout 5 || echo "000")

if [ "$HTTP_CODE" = "404" ]; then
    echo "  ✅ NGINX Ingress répond (404 = normal, aucun Ingress configuré encore)"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "  ⚠️  Pas de réponse HTTP (peut prendre quelques secondes supplémentaires)"
else
    echo "  ✅ NGINX Ingress répond (HTTP $HTTP_CODE)"
fi

# 6. Afficher les informations
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ NGINX INGRESS CONTROLLER DÉPLOYÉ               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📡 IP externe du LoadBalancer: $INGRESS_IP"
echo ""
echo "⚙️  Configuration appliquée :"
echo "  - Réplicas: 2 (haute disponibilité)"
echo "  - LoadBalancer: MetalLB"
echo "  - Métriques Prometheus: activées"
echo "  - WebSockets: supportés"
echo "  - TLS 1.2/1.3: activés"
echo "  - Upload max: 100MB"
echo ""
echo "🌐 Configuration DNS locale (à ajouter dans /etc/hosts sur Windows/WSL) :"
echo ""
echo "# Copier ces lignes dans C:\\Windows\\System32\\drivers\\etc\\hosts (Windows)"
echo "# OU dans /etc/hosts (WSL2)"
echo ""
echo "$INGRESS_IP grafana.local.lab"
echo "$INGRESS_IP kibana.local.lab"
echo "$INGRESS_IP prometheus.local.lab"
echo "$INGRESS_IP falco-ui.local.lab"
echo "$INGRESS_IP vault.local.lab"
echo "$INGRESS_IP keycloak.local.lab"
echo ""
echo "📋 Pour ajouter ces entrées automatiquement (dans WSL2) :"
echo ""
echo "sudo tee -a /etc/hosts <<EOF"
echo "# Enterprise Security Stack"
echo "$INGRESS_IP grafana.local.lab"
echo "$INGRESS_IP kibana.local.lab"
echo "$INGRESS_IP prometheus.local.lab"
echo "$INGRESS_IP falco-ui.local.lab"
echo "$INGRESS_IP vault.local.lab"
echo "$INGRESS_IP keycloak.local.lab"
echo "EOF"
echo ""
echo "🔍 Vérifier NGINX Ingress :"
echo "  kubectl get pods -n ingress-nginx"
echo "  kubectl get svc ingress-nginx-controller -n ingress-nginx"
echo "  kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx"
echo ""
echo "🎯 Prochaine étape :"
echo "  ./deploy/52-ingress-resources.sh"
echo "  (Créer les Ingress resources pour tous les services)"
echo ""
