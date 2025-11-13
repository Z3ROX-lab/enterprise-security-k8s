#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              MetalLB - LoadBalancer pour Kind             ║"
echo "║         Simuler un LoadBalancer en environnement local    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 MetalLB permet d'avoir de vraies IPs LoadBalancer dans Kind"
echo "   Au lieu de NodePort ou port-forward, vos services auront des IPs externes"
echo ""

read -p "Continuer avec l'installation de MetalLB ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# 1. Créer le namespace
echo ""
echo "1️⃣  Création du namespace metallb-system..."
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
echo "  ✅ Namespace créé"

# 2. Installer MetalLB via manifests
echo ""
echo "2️⃣  Installation de MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

echo "  ⏳ Attente du déploiement de MetalLB (30 secondes)..."
sleep 30

# 3. Vérifier le déploiement
echo ""
echo "3️⃣  Vérification du déploiement..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

echo "  ✅ MetalLB déployé"

# 4. Déterminer la plage d'IPs pour Kind
echo ""
echo "4️⃣  Configuration de la plage d'IPs..."

# Obtenir le réseau Docker utilisé par Kind
KIND_NET=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "172.18.0.0/16")
KIND_GATEWAY=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.18.0.1")

echo "  📡 Réseau Kind détecté: $KIND_NET"
echo "  📡 Gateway Kind: $KIND_GATEWAY"

# Extraire la base du réseau (ex: 172.18 de 172.18.0.0/16)
NETWORK_BASE=$(echo $KIND_NET | cut -d'.' -f1-2)

# Définir une plage d'IPs pour MetalLB (on utilise .255.200-.255.250)
IP_RANGE_START="${NETWORK_BASE}.255.200"
IP_RANGE_END="${NETWORK_BASE}.255.250"

echo "  📡 Plage d'IPs MetalLB: $IP_RANGE_START - $IP_RANGE_END"

# 5. Créer la configuration MetalLB
echo ""
echo "5️⃣  Création de la configuration MetalLB..."

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IP_RANGE_START}-${IP_RANGE_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

echo "  ✅ Configuration MetalLB créée"

# 6. Tester MetalLB avec un service de test
echo ""
echo "6️⃣  Test de MetalLB avec un service temporaire..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: metallb-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test-lb
  namespace: metallb-test
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nginx-test
EOF

echo "  ⏳ Attente de l'allocation d'IP externe (30 secondes)..."
sleep 30

# Vérifier l'IP externe
EXTERNAL_IP=$(kubectl get svc nginx-test-lb -n metallb-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$EXTERNAL_IP" ]; then
    echo "  ✅ IP externe allouée: $EXTERNAL_IP"
    echo ""
    echo "  🧪 Test de connectivité..."
    if curl -s -o /dev/null -w "%{http_code}" http://$EXTERNAL_IP --connect-timeout 5 | grep -q "200"; then
        echo "  ✅ MetalLB fonctionne ! Service accessible sur http://$EXTERNAL_IP"
    else
        echo "  ⚠️  IP allouée mais service pas encore accessible (normal, peut prendre quelques secondes)"
    fi
else
    echo "  ⚠️  Aucune IP externe allouée pour le moment"
    echo "  Vérifiez avec: kubectl get svc nginx-test-lb -n metallb-test -w"
fi

# Cleanup du test
echo ""
echo "  🧹 Nettoyage du service de test..."
kubectl delete namespace metallb-test --wait=false

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ METALLB INSTALLÉ ET CONFIGURÉ             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📡 Configuration MetalLB :"
echo "  - Plage d'IPs: $IP_RANGE_START - $IP_RANGE_END"
echo "  - Pool: default-pool"
echo "  - Mode: Layer 2 (L2Advertisement)"
echo ""
echo "✅ Les services de type LoadBalancer recevront automatiquement une IP de cette plage"
echo ""
echo "🔍 Vérifier MetalLB :"
echo "  kubectl get pods -n metallb-system"
echo "  kubectl get ipaddresspools -n metallb-system"
echo "  kubectl get l2advertisements -n metallb-system"
echo ""
echo "🎯 Prochaine étape :"
echo "  ./deploy/51-nginx-ingress.sh"
echo "  (Déployer NGINX Ingress Controller avec LoadBalancer)"
echo ""
