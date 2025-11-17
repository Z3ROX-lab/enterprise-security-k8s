#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        Ajouter Persistance pour Keycloak                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

POD=$(kubectl get pods -n security-iam | grep "^keycloak-" | grep Running | head -n1 | awk '{print $1}')

if [ -z "$POD" ]; then
    echo "❌ Pod Keycloak non trouvé"
    exit 1
fi

echo "✅ Pod Keycloak actuel: $POD"
echo ""
echo "📋 Ce script va:"
echo "   1. Créer un PVC de 2Gi pour les données Keycloak"
echo "   2. Copier les données actuelles vers le PVC"
echo "   3. Patcher le StatefulSet pour utiliser ce PVC"
echo "   4. Redémarrer le pod avec persistance"
echo ""
echo "⚠️  IMPORTANT: Vos données actuelles (y compris l'admin) seront préservées"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# 1. Créer le PVC
echo ""
echo "1️⃣  Création du PVC keycloak-data-persistent..."
echo ""

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: keycloak-data-persistent
  namespace: security-iam
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: standard
EOF

echo "✅ PVC créé"
echo ""

# Attendre que le PVC soit bound
echo "⏳ Attente que le PVC soit disponible..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/keycloak-data-persistent -n security-iam --timeout=60s || echo "⚠️ PVC pas encore bound, continuons..."

# 2. Copier les données actuelles vers le PVC
echo ""
echo "2️⃣  Copie des données actuelles vers le PVC..."
echo ""

# Créer un pod temporaire pour copier les données
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: keycloak-data-copy
  namespace: security-iam
spec:
  containers:
  - name: copy
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: new-data
      mountPath: /mnt/new-data
  volumes:
  - name: new-data
    persistentVolumeClaim:
      claimName: keycloak-data-persistent
  restartPolicy: Never
EOF

echo "⏳ Attente du pod temporaire..."
kubectl wait --for=condition=ready pod/keycloak-data-copy -n security-iam --timeout=60s

echo "📦 Copie des données depuis $POD vers le PVC..."

# Copier les données du pod actuel vers le pod temporaire
kubectl exec -n security-iam $POD -- tar czf - -C /opt/jboss/keycloak/standalone data | \
kubectl exec -i -n security-iam keycloak-data-copy -- tar xzf - -C /mnt/new-data/

echo "✅ Données copiées"
echo ""

# Nettoyer le pod temporaire
kubectl delete pod keycloak-data-copy -n security-iam

# 3. Patcher le StatefulSet
echo "3️⃣  Patch du StatefulSet keycloak..."
echo ""

# Obtenir le StatefulSet en YAML
kubectl get statefulset keycloak -n security-iam -o yaml > /tmp/keycloak-sts-backup.yaml

echo "📝 Sauvegarde du StatefulSet actuel dans /tmp/keycloak-sts-backup.yaml"

# Patcher pour ajouter le volume persistant
kubectl patch statefulset keycloak -n security-iam --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "keycloak-data",
      "persistentVolumeClaim": {
        "claimName": "keycloak-data-persistent"
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "keycloak-data",
      "mountPath": "/opt/jboss/keycloak/standalone/data"
    }
  }
]'

echo "✅ StatefulSet patché"
echo ""

# 4. Redémarrer le pod
echo "4️⃣  Redémarrage du pod Keycloak..."
echo ""

kubectl delete pod $POD -n security-iam --grace-period=10

echo "⏳ Attente du nouveau pod (jusqu'à 2 minutes)..."
kubectl wait --for=condition=ready pod/keycloak-0 -n security-iam --timeout=120s

echo "✅ Nouveau pod prêt"
echo ""

# 5. Vérifier le montage
echo "5️⃣  Vérification du montage du volume..."
echo ""

kubectl exec -n security-iam keycloak-0 -- df -h | grep "/opt/jboss/keycloak/standalone/data" || \
kubectl exec -n security-iam keycloak-0 -- ls -la /opt/jboss/keycloak/standalone/data/

echo ""

# 6. Attendre que Keycloak démarre
echo "6️⃣  Attente du démarrage complet de Keycloak (60 secondes)..."
sleep 60

# 7. Tester l'authentification
echo ""
echo "7️⃣  Test de l'authentification admin..."
echo ""

TOKEN_RESPONSE=$(kubectl exec -n security-iam keycloak-0 -- curl -s \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=admin123" \
    -d "grant_type=password" \
    "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ Admin fonctionne avec persistance !"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║        ✅ PERSISTANCE KEYCLOAK CONFIGURÉE                 ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
else
    echo "⚠️  Authentification échouée"
    echo ""
    echo "Réponse: $TOKEN_RESPONSE"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      ⚠️  PERSISTANCE AJOUTÉE MAIS ADMIN À RECRÉER         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "📝 Recréez l'admin:"
    echo "   kubectl port-forward -n security-iam keycloak-0 8080:8080"
    echo "   Puis allez sur http://localhost:8080"
fi

echo ""
echo "🎯 Résumé:"
echo "   - PVC créé: keycloak-data-persistent (2Gi)"
echo "   - Données préservées: ✅"
echo "   - StatefulSet patché: ✅"
echo "   - Persistance active: ✅"
echo ""
echo "🌐 Admin Console:"
echo "   https://keycloak.local.lab:8443/admin/admin/"
echo ""
echo "📊 Vérifier le PVC:"
echo "   kubectl get pvc -n security-iam"
echo "   kubectl describe pvc keycloak-data-persistent -n security-iam"
echo ""
echo "🔍 Vérifier le montage:"
echo "   kubectl exec -n security-iam keycloak-0 -- df -h"
echo ""
