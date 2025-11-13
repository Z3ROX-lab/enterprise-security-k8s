#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Création des Ingress Resources                  ║"
echo "║      Exposer Grafana, Kibana, Prometheus, Falco UI       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que NGINX Ingress est installé
if ! kubectl get namespace ingress-nginx &>/dev/null; then
    echo "❌ NGINX Ingress Controller n'est pas installé"
    echo "Lancez d'abord : ./deploy/51-nginx-ingress.sh"
    exit 1
fi

INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
    echo "❌ Aucune IP externe pour le LoadBalancer"
    echo "Vérifiez: kubectl get svc ingress-nginx-controller -n ingress-nginx"
    exit 1
fi

echo "✅ NGINX Ingress Controller détecté"
echo "📡 IP externe: $INGRESS_IP"
echo ""
echo "📋 Ce script va créer des Ingress resources pour :"
echo "  - Grafana (grafana.local.lab)"
echo "  - Kibana (kibana.local.lab)"
echo "  - Prometheus (prometheus.local.lab)"
echo "  - Falcosidekick UI (falco-ui.local.lab)"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Création annulée."
    exit 0
fi

# ========================================================================
# 1. Ingress pour Grafana
# ========================================================================
echo ""
echo "1️⃣  Création de l'Ingress pour Grafana..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: security-siem
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
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

echo "  ✅ Ingress Grafana créé: http://grafana.local.lab"

# ========================================================================
# 2. Ingress pour Kibana
# ========================================================================
echo ""
echo "2️⃣  Création de l'Ingress pour Kibana..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: security-siem
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
spec:
  ingressClassName: nginx
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

echo "  ✅ Ingress Kibana créé: http://kibana.local.lab"

# ========================================================================
# 3. Ingress pour Prometheus
# ========================================================================
echo ""
echo "3️⃣  Création de l'Ingress pour Prometheus..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: security-siem
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
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

echo "  ✅ Ingress Prometheus créé: http://prometheus.local.lab"

# ========================================================================
# 4. Ingress pour Falcosidekick UI
# ========================================================================
echo ""
echo "4️⃣  Création de l'Ingress pour Falcosidekick UI..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: falcosidekick-ui-ingress
  namespace: security-detection
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/websocket-services: "falco-falcosidekick-ui"
spec:
  ingressClassName: nginx
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

echo "  ✅ Ingress Falcosidekick UI créé: http://falco-ui.local.lab"

# ========================================================================
# 5. Vérification des Ingress
# ========================================================================
echo ""
echo "5️⃣  Vérification des Ingress créés..."

sleep 5

echo ""
echo "📊 Ingress dans security-siem:"
kubectl get ingress -n security-siem

echo ""
echo "📊 Ingress dans security-detection:"
kubectl get ingress -n security-detection

# ========================================================================
# 6. Test de connectivité
# ========================================================================
echo ""
echo "6️⃣  Test de connectivité des services..."

echo ""
echo "  🧪 Test Grafana..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: grafana.local.lab" http://$INGRESS_IP --connect-timeout 5 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "  ✅ Grafana accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Grafana: HTTP $HTTP_CODE (peut prendre quelques secondes)"
fi

echo "  🧪 Test Kibana..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: kibana.local.lab" http://$INGRESS_IP --connect-timeout 5 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "  ✅ Kibana accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Kibana: HTTP $HTTP_CODE (peut prendre quelques secondes)"
fi

echo "  🧪 Test Prometheus..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: prometheus.local.lab" http://$INGRESS_IP --connect-timeout 5 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "  ✅ Prometheus accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Prometheus: HTTP $HTTP_CODE (peut prendre quelques secondes)"
fi

echo "  🧪 Test Falcosidekick UI..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: falco-ui.local.lab" http://$INGRESS_IP --connect-timeout 5 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "  ✅ Falcosidekick UI accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Falcosidekick UI: HTTP $HTTP_CODE (peut prendre quelques secondes)"
fi

# ========================================================================
# Résumé final
# ========================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ INGRESS RESOURCES CRÉÉS                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📡 Tous les services sont maintenant accessibles via l'Ingress"
echo ""
echo "🌐 URLs des services :"
echo "  Grafana:         http://grafana.local.lab"
echo "  Kibana:          http://kibana.local.lab"
echo "  Prometheus:      http://prometheus.local.lab"
echo "  Falcosidekick UI: http://falco-ui.local.lab"
echo ""
echo "⚠️  IMPORTANT: Configurez votre fichier hosts !"
echo ""
echo "Sur WSL2/Linux (/etc/hosts) :"
echo "  sudo tee -a /etc/hosts <<EOF"
echo "  $INGRESS_IP grafana.local.lab"
echo "  $INGRESS_IP kibana.local.lab"
echo "  $INGRESS_IP prometheus.local.lab"
echo "  $INGRESS_IP falco-ui.local.lab"
echo "  EOF"
echo ""
echo "Sur Windows (C:\\Windows\\System32\\drivers\\etc\\hosts) en tant qu'Administrateur :"
echo "  $INGRESS_IP grafana.local.lab"
echo "  $INGRESS_IP kibana.local.lab"
echo "  $INGRESS_IP prometheus.local.lab"
echo "  $INGRESS_IP falco-ui.local.lab"
echo ""
echo "🔐 Credentials restent inchangés :"
echo "  - Grafana: admin / (voir CREDENTIALS.md)"
echo "  - Kibana: elastic / (voir CREDENTIALS.md)"
echo "  - Prometheus: pas d'auth"
echo "  - Falcosidekick UI: admin / admin"
echo ""
echo "🔍 Vérifier les Ingress :"
echo "  kubectl get ingress -A"
echo "  kubectl describe ingress grafana-ingress -n security-siem"
echo ""
echo "🎯 Prochaine étape (optionnel) :"
echo "  ./deploy/53-ingress-tls.sh"
echo "  (Activer HTTPS avec cert-manager + Vault)"
echo ""
