# Velero Backup & Restore - Guide Complet

## 🎯 Objectif

Ce guide explique comment utiliser **Velero** pour sauvegarder et restaurer le cluster Kubernetes, incluant :
- Toutes les ressources Kubernetes (Deployments, Services, ConfigMaps, Secrets, etc.)
- Persistent Volumes (PVCs) avec Restic/Node-Agent
- Disaster Recovery complet
- Migration de workloads entre clusters

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────┐
│                 Cluster Kubernetes                       │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Velero (Namespace: velero)                        │  │
│  │  - velero-deployment (controller)                  │  │
│  │  - node-agent DaemonSet (backup PVCs)             │  │
│  └─────────────────┬──────────────────────────────────┘  │
│                    │ Backup/Restore                      │
│                    ↓                                      │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Namespaces à Sauvegarder                          │  │
│  │  - security-iam      (Keycloak + PostgreSQL)      │  │
│  │  - security-siem     (ELK + Prometheus)           │  │
│  │  - security-detection (Falco, Wazuh, Trivy)       │  │
│  │  - ingress-nginx                                   │  │
│  │  - cert-manager                                    │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
                           │
                           │ S3 API
                           ↓
┌──────────────────────────────────────────────────────────┐
│                 MinIO (Backend Storage)                  │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Bucket: velero                                    │  │
│  │  - Backups (manifests YAML)                        │  │
│  │  - Restic data (PVC backups)                       │  │
│  │  PVC: 50Gi (extensible)                           │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## 🚀 Installation

### Étape 1 : Déployer MinIO (Backend S3)

```bash
cd ~/work/enterprise-security-k8s
./scripts/deploy-minio.sh
```

**Ce qui est créé :**
- Namespace `minio`
- Deployment MinIO
- PVC 50Gi pour le stockage des backups
- Bucket `velero` automatiquement créé
- Credentials : `minio` / `minio123`

### Étape 2 : Installer Velero

```bash
./scripts/deploy-velero.sh
```

**Ce qui est installé :**
- Velero CLI (dans `/usr/local/bin/velero`)
- Namespace `velero`
- Velero server (deployment)
- Node-agent DaemonSet (pour backups PVCs)
- Plugin AWS S3 pour MinIO

### Étape 3 : Configurer les Schedules Automatiques

```bash
./scripts/configure-velero-schedules.sh
```

**Schedules créés :**

| Schedule | Fréquence | Namespaces | Rétention | Description |
|----------|-----------|------------|-----------|-------------|
| `daily-full-backup` | Tous les jours à 2h00 | Tous (sauf kube-*) | 7 jours | Backup quotidien complet |
| `hourly-critical-backup` | Toutes les heures | security-iam, security-siem | 24 heures | Backup données critiques |
| `weekly-archive-backup` | Dimanches à 3h00 | Tous (sauf kube-*) | 30 jours | Archive hebdomadaire |

---

## 🧪 Test de Backup/Restore

### Test Automatique

Lancez le script de test complet :

```bash
./scripts/test-velero-backup-restore.sh
```

**Le script va :**
1. ✅ Créer un namespace de test avec une application
2. ✅ Faire un backup Velero
3. ✅ Supprimer le namespace
4. ✅ Restaurer depuis le backup
5. ✅ Vérifier que tout est restauré

### Test Manuel

#### 1. Créer un Backup Manuel

```bash
# Backup de tout le cluster (sauf kube-*)
velero backup create full-backup --exclude-namespaces kube-system,kube-public,kube-node-lease

# Backup d'un namespace spécifique
velero backup create keycloak-backup --include-namespaces security-iam

# Backup avec sélecteur de labels
velero backup create prod-backup --selector environment=production

# Backup avec exclusions
velero backup create backup-no-logs --exclude-resources pods,events
```

#### 2. Vérifier le Backup

```bash
# Lister tous les backups
velero backup get

# Voir les détails d'un backup
velero backup describe keycloak-backup

# Voir les logs d'un backup
velero backup logs keycloak-backup

# Télécharger un backup en YAML
velero backup download keycloak-backup -o /tmp/keycloak-backup.tar.gz
```

#### 3. Restaurer un Backup

```bash
# Restauration complète
velero restore create --from-backup full-backup

# Restauration dans un nouveau namespace
velero restore create --from-backup keycloak-backup \
  --namespace-mappings security-iam:security-iam-restored

# Restauration sélective (seulement certaines ressources)
velero restore create --from-backup full-backup \
  --include-resources deployments,services,configmaps

# Restauration avec exclusion
velero restore create --from-backup full-backup \
  --exclude-namespaces velero,minio
```

#### 4. Vérifier la Restauration

```bash
# Lister les restaurations
velero restore get

# Voir les détails
velero restore describe <restore-name>

# Voir les logs
velero restore logs <restore-name>
```

---

## 📋 Cas d'Usage Courants

### Cas 1 : Backup Avant Mise à Jour

```bash
# Avant une mise à jour de Keycloak
velero backup create pre-keycloak-upgrade --include-namespaces security-iam --wait

# Faire la mise à jour...

# Si problème, restaurer
velero restore create --from-backup pre-keycloak-upgrade
```

### Cas 2 : Disaster Recovery Complet

```bash
# 1. Sur le cluster d'origine (avant la panne)
velero backup create dr-backup --exclude-namespaces kube-system

# 2. Sur le nouveau cluster (après réinstallation)
# Installer Velero avec le même backend MinIO
./scripts/deploy-velero.sh

# Synchroniser les backups
velero backup get
# (Les backups apparaissent automatiquement depuis MinIO)

# 3. Restaurer
velero restore create --from-backup dr-backup
```

### Cas 3 : Migration Entre Clusters

```bash
# Cluster Source
velero backup create migration-backup --include-namespaces security-iam,security-siem

# Cluster Destination
# 1. Installer Velero avec le MÊME backend S3/MinIO
# 2. Les backups apparaissent automatiquement
velero backup get

# 3. Restaurer
velero restore create --from-backup migration-backup
```

### Cas 4 : Backup Sélectif par Label

```bash
# Backup seulement les ressources avec label app=keycloak
velero backup create keycloak-only --selector app.kubernetes.io/name=keycloak

# Backup toutes les ressources "production"
velero backup create prod-only --selector environment=production
```

---

## 🔧 Commandes Utiles

### Gestion des Backups

```bash
# Lister tous les backups
velero backup get

# Supprimer un backup
velero backup delete old-backup --confirm

# Supprimer tous les backups expirés
velero backup delete --all --confirm --selector velero.io/schedule-name=daily-full-backup

# Voir les ressources incluses dans un backup
velero backup describe keycloak-backup --details
```

### Gestion des Schedules

```bash
# Lister les schedules
velero schedule get

# Créer un nouveau schedule
velero schedule create weekly-keycloak \
  --schedule="0 3 * * 0" \
  --include-namespaces security-iam \
  --ttl 168h

# Suspendre un schedule
velero schedule pause daily-full-backup

# Reprendre un schedule
velero schedule unpause daily-full-backup

# Déclencher manuellement un schedule
velero backup create --from-schedule daily-full-backup

# Supprimer un schedule
velero schedule delete weekly-keycloak --confirm
```

### Gestion des Restaurations

```bash
# Lister les restaurations
velero restore get

# Supprimer une restauration (n'affecte pas les ressources restaurées)
velero restore delete old-restore --confirm

# Voir les warnings/errors d'une restauration
velero restore logs restore-20241117 | grep -i error
```

### Diagnostic

```bash
# Vérifier la configuration Velero
velero version

# Vérifier le backup location (MinIO)
velero backup-location get

# Vérifier les logs du serveur Velero
kubectl logs -n velero -l deploy=velero

# Vérifier les logs du node-agent (backup PVCs)
kubectl logs -n velero -l name=node-agent

# Debug d'un backup spécifique
velero backup describe my-backup --details --volume-details
```

---

## 📊 Monitoring des Backups

### Vérification Manuelle

```bash
# Script de vérification quotidien
cat <<'EOF' > /tmp/check-backups.sh
#!/bin/bash
echo "=== État des Backups Velero ==="
echo ""
echo "📅 Backups des dernières 24h:"
velero backup get | grep Completed | head -5
echo ""
echo "⚠️  Backups en erreur:"
velero backup get | grep -v Completed | grep -v NAME
echo ""
echo "🗓️  Prochains backups programmés:"
velero schedule get
EOF
chmod +x /tmp/check-backups.sh
./tmp/check-backups.sh
```

### Métriques Prometheus

Velero expose des métriques Prometheus sur `:8085/metrics` :

```yaml
# ServiceMonitor pour Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: velero
  namespace: velero
spec:
  selector:
    matchLabels:
      deploy: velero
  endpoints:
  - port: monitoring
    interval: 30s
```

**Métriques importantes :**
- `velero_backup_success_total` : Nombre de backups réussis
- `velero_backup_failure_total` : Nombre de backups échoués
- `velero_backup_duration_seconds` : Durée des backups
- `velero_restore_success_total` : Nombre de restaurations réussies

---

## 🌐 Accès à la Console MinIO

Pour visualiser les backups dans MinIO :

```bash
# Port-forward vers la console MinIO
kubectl port-forward -n minio svc/minio 9001:9001

# Ouvrir dans le navigateur
# URL: http://localhost:9001
# User: minio
# Password: minio123
```

Dans la console MinIO :
1. Cliquer sur **Object Browser**
2. Ouvrir le bucket **velero**
3. Explorer les dossiers :
   - `backups/` : Métadonnées des backups
   - `restic/` : Données des PVCs

---

## 🔐 Sécurité

### Chiffrement des Backups

Pour chiffrer les backups au repos dans MinIO :

```bash
# Activer le chiffrement sur le bucket MinIO
kubectl exec -n minio deploy/minio -- mc encrypt set sse-s3 myminio/velero
```

### Rotation des Credentials

```bash
# 1. Générer de nouveaux credentials MinIO
NEW_ACCESS_KEY="new-minio-key"
NEW_SECRET_KEY="new-minio-secret-$(openssl rand -hex 16)"

# 2. Mettre à jour le secret MinIO
kubectl create secret generic minio-credentials \
  --from-literal=accesskey=$NEW_ACCESS_KEY \
  --from-literal=secretkey=$NEW_SECRET_KEY \
  --namespace=minio \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Redémarrer MinIO
kubectl rollout restart deployment/minio -n minio

# 4. Mettre à jour les credentials Velero
cat > /tmp/velero-credentials-new <<EOF
[default]
aws_access_key_id = $NEW_ACCESS_KEY
aws_secret_access_key = $NEW_SECRET_KEY
EOF

kubectl create secret generic cloud-credentials \
  --from-file=cloud=/tmp/velero-credentials-new \
  --namespace=velero \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Redémarrer Velero
kubectl rollout restart deployment/velero -n velero
```

---

## 🚨 Troubleshooting

### Backup Échoue (PartiallyFailed)

```bash
# Voir les logs du backup
velero backup logs failed-backup

# Vérifier les warnings
velero backup describe failed-backup | grep -A 10 "Warnings:"

# Causes communes:
# - PVC non montés : Ignorer avec --exclude-resources persistentvolumeclaims
# - API deprecated : Mettre à jour les manifests
# - Ressources custom : Vérifier CRDs installés
```

### Restauration Ne Fonctionne Pas

```bash
# Vérifier les logs
velero restore logs failed-restore

# Problèmes courants:
# - Namespace déjà existe : Supprimer ou utiliser --namespace-mappings
# - StorageClass incompatible : Mapper avec --restore-volumes=false
# - PVC déjà bound : Supprimer les PVCs existants
```

### MinIO Inaccessible

```bash
# Vérifier que MinIO est Running
kubectl get pods -n minio

# Vérifier les logs MinIO
kubectl logs -n minio deploy/minio

# Tester la connexion depuis Velero
kubectl exec -n velero deploy/velero -- curl -v http://minio.minio.svc.cluster.local:9000
```

### Node-Agent Ne Sauvegarde Pas les PVCs

```bash
# Vérifier que node-agent tourne sur chaque nœud
kubectl get pods -n velero -l name=node-agent -o wide

# Vérifier les logs
kubectl logs -n velero -l name=node-agent --tail=50

# Annoter les PVCs pour forcer le backup
kubectl annotate pvc data-keycloak-postgresql-0 -n security-iam \
  backup.velero.io/backup-volumes=data
```

---

## 📝 Bonnes Pratiques

### 1. Stratégie de Rétention

- **Backups quotidiens** : 7 jours
- **Backups hebdomadaires** : 30 jours
- **Backups mensuels** : 1 an (pour audit)

### 2. Test Régulier

```bash
# Tester une restauration tous les mois
velero backup create monthly-test
velero restore create test-restore --from-backup monthly-test \
  --namespace-mappings security-iam:security-iam-test

# Vérifier et nettoyer
kubectl delete namespace security-iam-test
velero restore delete test-restore
```

### 3. Monitoring

- ✅ Vérifier quotidiennement que les schedules s'exécutent
- ✅ Alerter si un backup échoue
- ✅ Vérifier l'espace disque MinIO (PVC 50Gi)

### 4. Documentation

- ✅ Documenter les procédures de restore
- ✅ Lister les backups critiques
- ✅ Former l'équipe aux procédures DR

---

## 🔗 Références

- **Documentation Velero** : https://velero.io/docs/
- **Documentation MinIO** : https://min.io/docs/
- **Best Practices** : https://velero.io/docs/main/best-practices/

---

**Dernière mise à jour** : 2025-11-17
**Version Velero** : 1.12.0
**Backend Storage** : MinIO (S3-compatible)
