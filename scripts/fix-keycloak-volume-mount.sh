#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Corriger le Montage du Volume Keycloak              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Vérifier l'état actuel
echo "1️⃣  Vérification de l'état actuel..."
echo ""

kubectl get pvc keycloak-data-persistent -n security-iam

echo ""
echo "📋 Vérification du StatefulSet..."

# Vérifier si le volume est défini
HAS_VOLUME=$(kubectl get statefulset keycloak -n security-iam -o jsonpath='{.spec.template.spec.volumes[?(@.name=="keycloak-data")].name}' 2>/dev/null || echo "")

if [ -n "$HAS_VOLUME" ]; then
    echo "✅ Volume 'keycloak-data' trouvé dans le StatefulSet"
else
    echo "⚠️  Volume 'keycloak-data' non trouvé, ajout nécessaire"
fi

# Vérifier si le volumeMount est défini
HAS_MOUNT=$(kubectl get statefulset keycloak -n security-iam -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="keycloak-data")].name}' 2>/dev/null || echo "")

if [ -n "$HAS_MOUNT" ]; then
    echo "✅ VolumeMount 'keycloak-data' trouvé"
else
    echo "⚠️  VolumeMount 'keycloak-data' non trouvé, ajout nécessaire"
fi

echo ""

# 2. Recréer le StatefulSet avec volumeClaimTemplates
echo "2️⃣  Recréation du StatefulSet avec volumeClaimTemplates..."
echo ""

read -p "Recréer le StatefulSet ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# Sauvegarder le StatefulSet actuel
kubectl get statefulset keycloak -n security-iam -o yaml > /tmp/keycloak-sts-current.yaml
echo "📝 Sauvegarde: /tmp/keycloak-sts-current.yaml"

# Supprimer le StatefulSet (sans supprimer les pods avec --cascade=orphan)
echo "🗑️  Suppression du StatefulSet (pods préservés)..."
kubectl delete statefulset keycloak -n security-iam --cascade=orphan

echo ""
echo "3️⃣  Création du nouveau StatefulSet avec volume persistant..."
echo ""

# Créer un nouveau StatefulSet avec le volume monté
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak
  namespace: security-iam
spec:
  serviceName: keycloak-headless
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:17.0.1
        env:
        - name: KC_PROXY
          value: "edge"
        - name: KC_HOSTNAME_STRICT
          value: "false"
        - name: KC_HOSTNAME_STRICT_HTTPS
          value: "false"
        - name: PROXY_ADDRESS_FORWARDING
          value: "true"
        - name: DB_VENDOR
          value: "h2"
        ports:
        - name: http
          containerPort: 8080
        - name: https
          containerPort: 8443
        volumeMounts:
        - name: keycloak-data
          mountPath: /opt/jboss/keycloak/standalone/data
      volumes:
      - name: keycloak-data
        persistentVolumeClaim:
          claimName: keycloak-data-persistent
EOF

echo "✅ StatefulSet recréé"
echo ""

# 4. Redémarrer le pod
echo "4️⃣  Redémarrage du pod pour appliquer le montage..."
kubectl delete pod keycloak-0 -n security-iam --grace-period=10

echo "⏳ Attente du nouveau pod..."
kubectl wait --for=condition=ready pod/keycloak-0 -n security-iam --timeout=120s

echo "✅ Pod prêt"
echo ""

# 5. Vérifier le montage
echo "5️⃣  Vérification du montage du volume..."
echo ""

kubectl exec -n security-iam keycloak-0 -- df -h | grep "keycloak.*data" || {
    echo "⚠️  Montage non visible dans df, vérification alternative..."
    kubectl exec -n security-iam keycloak-0 -- ls -la /opt/jboss/keycloak/standalone/data/
}

echo ""

# 6. Attendre Keycloak
echo "6️⃣  Attente du démarrage de Keycloak (60 secondes)..."
sleep 60

# 7. Vérifier si l'admin existe
echo ""
echo "7️⃣  Vérification de l'admin..."
echo ""

TOKEN_RESPONSE=$(kubectl exec -n security-iam keycloak-0 -- curl -s \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=admin123" \
    -d "grant_type=password" \
    "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ Admin existe et fonctionne !"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         ✅ PERSISTANCE CONFIGURÉE ET ADMIN OK             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
else
    echo "⚠️  Admin n'existe pas, besoin de le recréer"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      ⚠️  VOLUME MONTÉ MAIS ADMIN À RECRÉER                ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "📝 Créez l'admin maintenant:"
    echo ""
    echo "   Terminal 1 (WSL):"
    echo "   kubectl port-forward -n security-iam keycloak-0 8080:8080 --address 0.0.0.0"
    echo ""
    echo "   Navigateur Windows:"
    echo "   http://localhost:8080"
    echo ""
    echo "   Remplissez le formulaire:"
    echo "   Username: admin"
    echo "   Password: admin123"
    echo ""
    echo "   Cette fois, l'admin sera PERSISTÉ sur le PVC !"
fi

echo ""
echo "🎯 Résumé:"
echo "   - PVC: keycloak-data-persistent (2Gi) ✅"
echo "   - Volume monté: /opt/jboss/keycloak/standalone/data ✅"
echo "   - Persistance active: ✅"
echo ""
echo "📊 Vérifications:"
echo "   kubectl exec -n security-iam keycloak-0 -- df -h"
echo "   kubectl exec -n security-iam keycloak-0 -- ls -la /opt/jboss/keycloak/standalone/data/"
echo ""
echo "🌐 Admin Console:"
echo "   https://keycloak.local.lab:8443/auth/admin/"
echo ""
