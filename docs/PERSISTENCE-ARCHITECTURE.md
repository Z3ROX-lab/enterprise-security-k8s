# Architecture de Persistence - Keycloak & PostgreSQL

## 🎯 Comprendre où sont stockées vos données

### Schéma du Flux de Données

```
┌─────────────────┐
│   Utilisateur   │
│   crée "admin"  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│       Keycloak (Pod)            │
│  ┌───────────────────────────┐  │
│  │ Application Java          │  │
│  │ (traite les requêtes)     │  │
│  └───────────┬───────────────┘  │
│              │                   │
│              │ SQL INSERT        │
└──────────────┼───────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│    PostgreSQL (Pod)             │
│  ┌───────────────────────────┐  │
│  │ Base de données           │  │
│  │ (tables: users, realms)   │  │
│  └───────────┬───────────────┘  │
│              │                   │
│              │ WRITE             │
│              ▼                   │
│  ┌───────────────────────────┐  │
│  │ /bitnami/postgresql       │  │
│  │  ← PVC 10Gi (DISQUE)      │◄─┼─── 💾 DONNÉES PERSISTANTES
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

---

## ❌ Configuration AVANT (Problématique)

### Situation Initiale
```yaml
# PostgreSQL sans persistence
primary.persistence.enabled: false

# Keycloak avec PVC inutile
keycloak-data-persistent (2Gi) → /opt/jboss/keycloak/standalone/data
```

### Problèmes
1. **PostgreSQL n'a PAS de PVC** → Données en RAM uniquement
2. **User admin stocké en RAM** → Perdu au redémarrage de PostgreSQL
3. **PVC Keycloak inutile** → Monte un dossier qui n'est pas utilisé (prévu pour H2 embarqué)

### Résultat
```bash
# Vous créez un user
kubectl exec keycloak-0 -- kcadm.sh create users -r master ...

# PostgreSQL redémarre
kubectl delete pod keycloak-postgresql-0

# ❌ User perdu !
```

---

## ✅ Configuration APRÈS (Production-Ready)

### Nouvelle Configuration
```yaml
# PostgreSQL avec persistence
primary.persistence.enabled: true
primary.persistence.size: 10Gi
primary.persistence.storageClass: standard

# PVC créé automatiquement
data-keycloak-postgresql-0 → /bitnami/postgresql
```

### Avantages
1. **✅ Données sur disque persistant** → Survive aux redémarrages
2. **✅ User admin sauvegardé** → Stocké dans PostgreSQL sur PVC
3. **✅ Realms et configurations persistants** → Tout est dans la base

### Résultat
```bash
# Vous créez un user
kubectl exec keycloak-0 -- kcadm.sh create users -r master ...

# PostgreSQL redémarre
kubectl delete pod keycloak-postgresql-0

# ✅ User toujours là !
```

---

## 🔍 Où sont VRAIMENT stockées vos données ?

### Table de Vérité

| Donnée | Stockée où ? | PVC nécessaire ? |
|--------|--------------|------------------|
| **Users Keycloak** | PostgreSQL → `/bitnami/postgresql` | ✅ PVC PostgreSQL |
| **Realms** | PostgreSQL → `/bitnami/postgresql` | ✅ PVC PostgreSQL |
| **Sessions actives** | PostgreSQL → `/bitnami/postgresql` | ✅ PVC PostgreSQL |
| **Configuration Keycloak** | PostgreSQL → `/bitnami/postgresql` | ✅ PVC PostgreSQL |
| **Cache Keycloak** | RAM (volatile) | ❌ Pas besoin |
| **Logs Keycloak** | stdout (captured par K8s) | ❌ Pas besoin |

### Points Clés
- 🔑 **Toutes les données métier sont dans PostgreSQL**
- 💾 **PostgreSQL stocke dans `/bitnami/postgresql`**
- 📦 **Le PVC doit être sur PostgreSQL, PAS sur Keycloak**

---

## 🛠️ Migration : Étape par Étape

### 1. État Initial (Avant)
```bash
$ kubectl get pvc -n security-iam

# Aucun PVC PostgreSQL !
NAME                        STATUS   VOLUME   CAPACITY
keycloak-data-persistent    Bound    pv-001   2Gi        # ← INUTILE
```

### 2. Activation de la Persistence
```bash
./scripts/enable-postgresql-persistence.sh
```

### 3. État Final (Après)
```bash
$ kubectl get pvc -n security-iam

NAME                              STATUS   VOLUME   CAPACITY
data-keycloak-postgresql-0        Bound    pv-002   10Gi       # ← CRITIQUE
keycloak-data-persistent          Bound    pv-001   2Gi        # ← Optionnel
```

---

## 🧪 Test de Persistence

### Scénario de Test
```bash
# 1. Créer un user admin dans Keycloak
kubectl port-forward -n security-iam svc/keycloak 8080:80
# Ouvrez http://localhost:8080/admin et créez un user "testuser"

# 2. Redémarrer PostgreSQL (simulation crash)
kubectl delete pod keycloak-postgresql-0 -n security-iam

# 3. Attendre le redémarrage
kubectl wait --for=condition=ready pod/keycloak-postgresql-0 -n security-iam --timeout=180s

# 4. Vérifier que le user existe toujours
# Retournez dans l'interface Keycloak
# ✅ Le user "testuser" doit toujours être là !
```

---

## 📊 Comparaison : H2 vs PostgreSQL

| Aspect | H2 Embarqué | PostgreSQL Externe |
|--------|-------------|-------------------|
| **Stockage** | `/opt/jboss/keycloak/standalone/data` | `/bitnami/postgresql` |
| **PVC nécessaire** | Sur pod Keycloak | Sur pod PostgreSQL |
| **Production-ready** | ❌ Non recommandé | ✅ Oui |
| **Performance** | 🐌 Moyenne | 🚀 Élevée |
| **Scalabilité** | ❌ 1 seul pod | ✅ Réplication possible |
| **Backup** | Difficile | ✅ pg_dump natif |

---

## 🎯 Recommandations Finales

### Pour la Production
```yaml
# PostgreSQL
primary.persistence.enabled: true
primary.persistence.size: 20Gi  # Au moins 20Gi pour production
primary.persistence.storageClass: fast-ssd  # SSD recommandé

# Réplication PostgreSQL (haute disponibilité)
readReplicas.replicaCount: 2
readReplicas.persistence.enabled: true
```

### Pour le Développement
```yaml
# PostgreSQL
primary.persistence.enabled: true
primary.persistence.size: 5Gi  # 5Gi suffisant pour dev

# Pas de réplication nécessaire
```

### Keycloak (Production & Dev)
```yaml
# PAS de PVC sur Keycloak si PostgreSQL est utilisé
# Le PVC keycloak-data-persistent est INUTILE et peut être supprimé
```

---

## 🔐 Sécurité & Backup

### Stratégie de Backup PostgreSQL
```bash
# 1. Backup manuel
kubectl exec -n security-iam keycloak-postgresql-0 -- \
  pg_dump -U keycloak keycloak > keycloak-backup-$(date +%Y%m%d).sql

# 2. Backup automatique (CronJob recommandé)
# Voir: docs/BACKUP-STRATEGY.md

# 3. Snapshot PVC (si supporté par votre storage class)
kubectl create volumesnapshot keycloak-pg-snapshot \
  --volume-claim data-keycloak-postgresql-0 \
  -n security-iam
```

---

## 📚 Ressources

- **Bitnami PostgreSQL Chart**: https://github.com/bitnami/charts/tree/main/bitnami/postgresql
- **Keycloak Database Setup**: https://www.keycloak.org/server/db
- **Kubernetes PVC Guide**: https://kubernetes.io/docs/concepts/storage/persistent-volumes/

---

## 🆘 Troubleshooting

### Problème : PVC non créé
```bash
# Vérifier les événements
kubectl get events -n security-iam --sort-by='.lastTimestamp'

# Vérifier les StorageClasses disponibles
kubectl get storageclass

# Vérifier les logs du pod PostgreSQL
kubectl logs -n security-iam keycloak-postgresql-0
```

### Problème : Données perdues après redémarrage
```bash
# Vérifier si le PVC est bien monté
kubectl describe pod keycloak-postgresql-0 -n security-iam | grep -A5 "Volumes:"

# Vérifier le contenu du PVC
kubectl exec -n security-iam keycloak-postgresql-0 -- ls -lah /bitnami/postgresql/data
```

---

**✅ Avec cette architecture, vos données Keycloak sont maintenant persistantes et production-ready !**
