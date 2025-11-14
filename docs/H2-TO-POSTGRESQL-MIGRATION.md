# Migration Keycloak : H2 → PostgreSQL

## 🎯 Pourquoi cette Migration ?

### Situation Initiale (Problématique)

```
Keycloak → H2 embarquée → keycloak-data-persistent (2Gi)
              ↓
        ❌ Non production-ready
        ❌ Pas de réplication
        ❌ Performance limitée

PostgreSQL → Existe mais PAS utilisé !
```

### Situation Cible (Production-Ready)

```
Keycloak → PostgreSQL → data-keycloak-postgresql-0 (10Gi)
              ↓
        ✅ Production-ready
        ✅ Réplication possible
        ✅ Performance élevée
        ✅ Backups natifs (pg_dump)
```

---

## 🔍 Comment Détecter Si Vous Êtes Concerné ?

### Vérification Rapide

```bash
# 1. Vérifier la config Keycloak
kubectl describe pod -n security-iam -l app.kubernetes.io/name=keycloak | grep DB_VENDOR

# Si vous voyez:
# DB_VENDOR: h2
# ➡️ Vous utilisez H2, migration nécessaire !

# Si vous voyez:
# DB_VENDOR: postgres
# ➡️ Vous utilisez déjà PostgreSQL, migration non nécessaire
```

### Vérification des Logs

```bash
kubectl logs -n security-iam -l app.kubernetes.io/name=keycloak --tail=50 | grep -i database

# Si vous voyez:
# databaseUrl=jdbc:h2:/opt/jboss/keycloak/standalone/data/keycloak
# ➡️ H2 confirmé, migration nécessaire !

# Si vous voyez:
# databaseUrl=jdbc:postgresql://keycloak-postgresql:5432/keycloak
# ➡️ PostgreSQL confirmé, migration non nécessaire
```

---

## 🛠️ Processus de Migration (Automatisé)

### Script de Migration

Le script `migrate-keycloak-h2-to-postgresql.sh` effectue automatiquement :

### Étape 1 : Export H2
1. ✅ Export via Keycloak Admin API (tous les realms + users)
2. ✅ Backup du répertoire H2 complet (`/opt/jboss/keycloak/standalone/data`)
3. ✅ Sauvegarde dans `/tmp/keycloak-migration-YYYYMMDD-HHMMSS/`

### Étape 2 : Activation PostgreSQL
1. ✅ Active la persistence PostgreSQL (10Gi PVC)
2. ✅ Redémarre PostgreSQL avec le PVC
3. ✅ Vérifie que le PVC est correctement monté

### Étape 3 : Reconfiguration Keycloak
1. ✅ Patch le StatefulSet Keycloak pour utiliser PostgreSQL
2. ✅ Change `DB_VENDOR: h2` → `DB_VENDOR: postgres`
3. ✅ Ajoute les variables de connexion PostgreSQL
4. ✅ Redémarre Keycloak (init auto de la DB PostgreSQL)

### Étape 4 : Vérification
1. ✅ Vérifie que Keycloak se connecte à PostgreSQL
2. ✅ Vérifie que l'admin user fonctionne
3. ✅ Conserve tous les backups H2

---

## 🚀 Lancer la Migration

### Commande Simple

```bash
./scripts/migrate-keycloak-h2-to-postgresql.sh
```

### Ce Qui Va Se Passer

```
╔═══════════════════════════════════════════════════════════╗
║     Migration Keycloak : H2 → PostgreSQL (SÉCURISÉ)      ║
╚═══════════════════════════════════════════════════════════╝

1️⃣  Export des données H2 via API                [~2 min]
2️⃣  Backup du répertoire H2                      [~1 min]
3️⃣  Activation persistence PostgreSQL            [~3 min]
4️⃣  Reconfiguration Keycloak                     [~1 min]
5️⃣  Redémarrage Keycloak sur PostgreSQL          [~5 min]
6️⃣  Vérification de la connexion                 [~1 min]

Total: ~13 minutes
```

---

## ⚠️ Important : Données Utilisateur

### Que Devient Votre User Admin ?

**Lors de la migration :**

1. **Export H2** → Vos données sont sauvegardées dans `/tmp/keycloak-migration-*/`
2. **Keycloak démarre sur PostgreSQL** → Init automatique d'une nouvelle DB
3. **Admin recréé** → L'admin initial (`admin/admin123`) est recréé par Keycloak

### Credentials Préservés

```bash
Username: admin
Password: admin123
```

Ces credentials sont configurés lors du déploiement Helm et seront **automatiquement recréés** lors de l'init PostgreSQL.

### Si Vous Aviez D'autres Users

Les users créés dans H2 ne seront **PAS automatiquement migrés** par ce script. Vous avez deux options :

**Option 1 : Recréer Manuellement** (Recommandé si peu de users)
```bash
# Connectez-vous à Keycloak admin console
# Recréez vos users manuellement
```

**Option 2 : Import Avancé** (Pour beaucoup de users)
```bash
# Utilisez les fichiers JSON sauvegardés
# /tmp/keycloak-migration-*/users-*.json
# Et importez-les via l'API Keycloak
```

---

## 📊 Avant / Après Migration

### État Avant

```bash
$ kubectl get pvc -n security-iam
NAME                       STATUS   CAPACITY
keycloak-data-persistent   Bound    2Gi       # ← H2 data
# Pas de PVC PostgreSQL

$ kubectl describe pod keycloak-0 -n security-iam | grep DB_VENDOR
DB_VENDOR: h2

$ kubectl logs keycloak-0 -n security-iam | grep database
databaseUrl=jdbc:h2:/opt/jboss/keycloak/standalone/data/keycloak
```

### État Après

```bash
$ kubectl get pvc -n security-iam
NAME                              STATUS   CAPACITY
keycloak-data-persistent          Bound    2Gi       # ← Peut être supprimé
data-keycloak-postgresql-0        Bound    10Gi      # ← NOUVELLE DB !

$ kubectl describe pod keycloak-0 -n security-iam | grep DB_VENDOR
DB_VENDOR: postgres

$ kubectl logs keycloak-0 -n security-iam | grep database
databaseUrl=jdbc:postgresql://keycloak-postgresql:5432/keycloak
```

---

## 🧪 Vérification Post-Migration

### Test 1 : Connexion Admin

```bash
# Port-forward Keycloak
kubectl port-forward -n security-iam svc/keycloak 8080:80

# Ouvrez dans votre navigateur
http://localhost:8080/admin

# Login
Username: admin
Password: admin123

# ✅ Devrait fonctionner !
```

### Test 2 : Vérifier la Base PostgreSQL

```bash
# Connexion à PostgreSQL
kubectl exec -it keycloak-postgresql-0 -n security-iam -- psql -U keycloak -d keycloak

# Lister les tables Keycloak
\dt

# Vous devriez voir ~100 tables Keycloak
# user_entity, realm, client, etc.

# Compter les users
SELECT username FROM user_entity;

# Devrait afficher au minimum:
# admin

# Quitter
\q
```

### Test 3 : Persistence

```bash
# Créer un user de test dans Keycloak
# (via l'interface admin)

# Redémarrer PostgreSQL
kubectl delete pod keycloak-postgresql-0 -n security-iam

# Attendre le redémarrage (2-3 min)
kubectl wait --for=condition=ready pod/keycloak-postgresql-0 -n security-iam --timeout=180s

# Vérifier que le user existe toujours
# ✅ Il devrait être là (PVC fonctionne !)
```

---

## 🗑️ Nettoyage Post-Migration

### Supprimer l'Ancien PVC H2 (Optionnel)

**⚠️ Attendez quelques jours pour être sûr que tout fonctionne !**

```bash
# Backup final du PVC H2
kubectl get pvc keycloak-data-persistent -n security-iam -o yaml > keycloak-h2-pvc-backup.yaml

# Supprimer le volume mount H2 du StatefulSet
kubectl patch statefulset keycloak -n security-iam --type=json -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/volumeMounts/0"}
]'

# Supprimer le PVC H2
kubectl delete pvc keycloak-data-persistent -n security-iam
```

### Backups à Conserver

Les backups H2 sont dans `/tmp/keycloak-migration-*/` :
- `realm-*.json` → Export des realms
- `users-*.json` → Export des users
- `h2-data-backup/` → Copie complète du répertoire H2

**Copiez-les dans un endroit sûr !**

```bash
# Exemple : copier dans un dossier de backups permanent
mkdir -p ~/keycloak-backups
cp -r /tmp/keycloak-migration-* ~/keycloak-backups/
```

---

## 🔧 Troubleshooting

### Problème 1 : Keycloak ne démarre pas après migration

```bash
# Vérifier les logs
kubectl logs -n security-iam keycloak-0

# Erreur courante : connexion PostgreSQL refusée
# Solution : Vérifier que PostgreSQL est bien running
kubectl get pods -n security-iam | grep postgresql

# Redémarrer PostgreSQL si nécessaire
kubectl delete pod keycloak-postgresql-0 -n security-iam
```

### Problème 2 : Admin user ne fonctionne pas

```bash
# Recréer l'admin manuellement
kubectl exec -it keycloak-0 -n security-iam -- /opt/jboss/keycloak/bin/add-user-keycloak.sh \
  -u admin -p admin123 -r master

# Redémarrer Keycloak
kubectl delete pod keycloak-0 -n security-iam
```

### Problème 3 : PostgreSQL plein / Pas d'espace

```bash
# Vérifier l'espace disponible
kubectl exec -it keycloak-postgresql-0 -n security-iam -- df -h /bitnami/postgresql

# Augmenter la taille du PVC (si supporté par votre StorageClass)
kubectl patch pvc data-keycloak-postgresql-0 -n security-iam -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

---

## 📈 Avantages de PostgreSQL vs H2

| Aspect | H2 Embarqué | PostgreSQL |
|--------|-------------|------------|
| **Production** | ❌ Non recommandé | ✅ Production-ready |
| **Performance** | 🐌 Moyenne | 🚀 Élevée |
| **Scalabilité** | ❌ 1 pod seulement | ✅ Réplication possible |
| **Backup** | 🤷 Copie de fichiers | ✅ pg_dump natif |
| **Haute Dispo** | ❌ Non | ✅ Oui (avec réplication) |
| **Transactions** | ⚠️ Basique | ✅ ACID complet |
| **Monitoring** | ⚠️ Limité | ✅ Excellent (pg_stat_*) |

---

## 🎯 Recommandations

### Pour la Production

```yaml
# PostgreSQL avec réplication
postgresql:
  enabled: true
  primary:
    persistence:
      enabled: true
      size: 50Gi
      storageClass: fast-ssd
  readReplicas:
    replicaCount: 2
    persistence:
      enabled: true
      size: 50Gi
```

### Pour le Développement

```yaml
# PostgreSQL simple avec persistence
postgresql:
  enabled: true
  primary:
    persistence:
      enabled: true
      size: 10Gi
      storageClass: standard
```

---

## 📚 Ressources

- **Keycloak Database Setup**: https://www.keycloak.org/server/db
- **Bitnami PostgreSQL Chart**: https://github.com/bitnami/charts/tree/main/bitnami/postgresql
- **PostgreSQL Backup Best Practices**: https://www.postgresql.org/docs/current/backup.html

---

**✅ Après cette migration, votre Keycloak sera production-ready avec PostgreSQL !**
