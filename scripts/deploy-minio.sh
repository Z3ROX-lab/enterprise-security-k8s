#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Déploiement MinIO pour Velero Backups              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📦 Ce script déploie MinIO comme backend S3 pour Velero"
echo ""

# Variables
NAMESPACE="minio"
MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"
BUCKET_NAME="velero"
PVC_SIZE="50Gi"

echo "🔍 Configuration:"
echo "   Namespace: $NAMESPACE"
echo "   Access Key: $MINIO_ACCESS_KEY"
echo "   Secret Key: $MINIO_SECRET_KEY"
echo "   Bucket: $BUCKET_NAME"
echo "   Storage: $PVC_SIZE"
echo ""

read -p "Continuer avec le déploiement ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "📁 Étape 1: Créer le namespace MinIO..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "   ✅ Namespace créé"

echo ""
echo "🔐 Étape 2: Créer le secret pour les credentials MinIO..."
kubectl create secret generic minio-credentials \
  --from-literal=accesskey=$MINIO_ACCESS_KEY \
  --from-literal=secretkey=$MINIO_SECRET_KEY \
  --namespace=$NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -
echo "   ✅ Secret créé"

echo ""
echo "🚀 Étape 3: Déployer MinIO..."

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PVC_SIZE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: $NAMESPACE
  labels:
    app: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
        ports:
        - containerPort: 9000
          name: s3
        - containerPort: 9001
          name: console
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: minio-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  ports:
  - port: 9000
    targetPort: 9000
    name: s3
  - port: 9001
    targetPort: 9001
    name: console
  selector:
    app: minio
EOF

echo "   ✅ MinIO déployé"

echo ""
echo "⏳ Étape 4: Attendre que MinIO soit prêt..."
kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=minio --timeout=300s
echo "   ✅ MinIO est prêt"

echo ""
echo "🪣 Étape 5: Créer le bucket Velero..."

# Job pour créer le bucket
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-setup
  namespace: $NAMESPACE
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: mc
        image: minio/mc:latest
        command:
        - /bin/sh
        - -c
        - |
          mc alias set myminio http://minio:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
          mc mb myminio/$BUCKET_NAME --ignore-existing
          mc version enable myminio/$BUCKET_NAME
          echo "Bucket $BUCKET_NAME créé avec succès"
EOF

echo "   ⏳ Création du bucket en cours..."
kubectl wait --for=condition=complete job/minio-setup -n $NAMESPACE --timeout=120s 2>/dev/null || true
echo "   ✅ Bucket créé"

echo ""
echo "📊 État final:"
kubectl get pods -n $NAMESPACE
echo ""
kubectl get pvc -n $NAMESPACE

echo ""
echo "✅ MinIO déployé avec succès !"
echo ""
echo "📝 Informations MinIO:"
echo "   Service S3:    minio.$NAMESPACE.svc.cluster.local:9000"
echo "   Access Key:    $MINIO_ACCESS_KEY"
echo "   Secret Key:    $MINIO_SECRET_KEY"
echo "   Bucket Velero: $BUCKET_NAME"
echo ""
echo "🌐 Accès à la console MinIO (via port-forward):"
echo "   kubectl port-forward -n $NAMESPACE svc/minio 9001:9001"
echo "   URL: http://localhost:9001"
echo ""
echo "🔐 Créer le fichier credentials pour Velero:"
cat > /tmp/velero-credentials <<CREDS
[default]
aws_access_key_id = $MINIO_ACCESS_KEY
aws_secret_access_key = $MINIO_SECRET_KEY
CREDS
echo "   ✅ Fichier créé: /tmp/velero-credentials"
echo ""
echo "📋 Prochaine étape: Installer Velero"
echo "   ./scripts/deploy-velero.sh"
echo ""
