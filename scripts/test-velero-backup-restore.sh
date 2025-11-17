#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Test Velero Backup & Restore                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "🧪 Ce script teste le backup et la restauration avec Velero"
echo ""
echo "   Le test va:"
echo "   1. Créer un namespace de test avec une application"
echo "   2. Faire un backup avec Velero"
echo "   3. Supprimer le namespace"
echo "   4. Restaurer depuis le backup"
echo "   5. Vérifier que tout est restauré"
echo ""

read -p "Lancer le test ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

TEST_NAMESPACE="velero-test"
BACKUP_NAME="test-backup-$(date +%Y%m%d-%H%M%S)"

echo ""
echo "📦 Étape 1: Créer un namespace de test..."
kubectl create namespace $TEST_NAMESPACE 2>/dev/null || true

echo ""
echo "🚀 Étape 2: Déployer une application de test..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-config
  namespace: $TEST_NAMESPACE
data:
  message: "Hello from Velero test!"
  timestamp: "$(date)"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: $TEST_NAMESPACE
spec:
  replicas: 2
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
        volumeMounts:
        - name: config
          mountPath: /etc/config
      volumes:
      - name: config
        configMap:
          name: test-config
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test-svc
  namespace: $TEST_NAMESPACE
spec:
  selector:
    app: nginx-test
  ports:
  - port: 80
    targetPort: 80
EOF

echo "   ⏳ Attendre que les pods soient prêts..."
kubectl wait --for=condition=ready pod -n $TEST_NAMESPACE -l app=nginx-test --timeout=60s

echo ""
echo "📊 État avant backup:"
kubectl get all -n $TEST_NAMESPACE
kubectl get cm -n $TEST_NAMESPACE

echo ""
echo "💾 Étape 3: Créer le backup Velero..."
velero backup create $BACKUP_NAME --include-namespaces $TEST_NAMESPACE --wait

echo ""
echo "🔍 Vérifier le backup:"
velero backup describe $BACKUP_NAME

echo ""
echo "🗑️  Étape 4: Supprimer le namespace de test..."
kubectl delete namespace $TEST_NAMESPACE --wait=true

echo "   ⏳ Attendre la suppression complète..."
sleep 10

echo ""
echo "✅ Namespace supprimé. Vérification:"
kubectl get namespace $TEST_NAMESPACE 2>&1 || echo "   ✅ Namespace bien supprimé"

echo ""
echo "🔄 Étape 5: Restaurer depuis le backup..."
velero restore create --from-backup $BACKUP_NAME --wait

echo ""
echo "⏳ Attendre que les pods soient restaurés..."
kubectl wait --for=condition=ready pod -n $TEST_NAMESPACE -l app=nginx-test --timeout=120s 2>/dev/null || true

echo ""
echo "📊 État après restore:"
kubectl get all -n $TEST_NAMESPACE
kubectl get cm -n $TEST_NAMESPACE

echo ""
echo "✅ Test terminé !"
echo ""
echo "🔍 Vérification des ressources restaurées:"
echo ""

# Vérifier le ConfigMap
if kubectl get cm test-config -n $TEST_NAMESPACE &>/dev/null; then
    echo "   ✅ ConfigMap restauré"
    kubectl get cm test-config -n $TEST_NAMESPACE -o jsonpath='{.data.message}'
    echo ""
else
    echo "   ❌ ConfigMap NON restauré"
fi

# Vérifier le Deployment
if kubectl get deployment nginx-test -n $TEST_NAMESPACE &>/dev/null; then
    echo "   ✅ Deployment restauré"
    REPLICAS=$(kubectl get deployment nginx-test -n $TEST_NAMESPACE -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment nginx-test -n $TEST_NAMESPACE -o jsonpath='{.status.readyReplicas}')
    echo "   Replicas: $READY/$REPLICAS ready"
else
    echo "   ❌ Deployment NON restauré"
fi

# Vérifier le Service
if kubectl get svc nginx-test-svc -n $TEST_NAMESPACE &>/dev/null; then
    echo "   ✅ Service restauré"
else
    echo "   ❌ Service NON restauré"
fi

echo ""
echo "📝 Commandes pour cleanup:"
echo "   # Supprimer le namespace de test"
echo "   kubectl delete namespace $TEST_NAMESPACE"
echo ""
echo "   # Supprimer le backup"
echo "   velero backup delete $BACKUP_NAME --confirm"
echo ""
echo "   # Voir tous les backups"
echo "   velero backup get"
echo ""
echo "   # Voir toutes les restaurations"
echo "   velero restore get"
echo ""
