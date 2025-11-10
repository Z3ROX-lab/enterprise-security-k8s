# Scripts de Déploiement Modulaires

Ce dossier contient des scripts de déploiement **indépendants** pour chaque composant de la stack de sécurité.

## 🎯 Avantages de Cette Approche

- ✅ **Modulaire** : Déployer service par service
- ✅ **Debuggable** : Identifier précisément les problèmes
- ✅ **Flexible** : Sauter les composants non désirés
- ✅ **Reproductible** : Chaque script peut être relancé
- ✅ **Compréhensible** : Code simple et lisible

## 📋 Scripts Disponibles

### Scripts Principaux (dans l'ordre)

| Script | Description | Durée | Requis |
|--------|-------------|-------|--------|
| `cleanup.sh` | Nettoie TOUT (cluster + resources) | 1 min | - |
| `01-cluster.sh` | Crée le cluster Kind (4 nœuds) | 3 min | ✅ |
| `02-monitoring.sh` | Elasticsearch + Prometheus + Grafana | 10 min | ✅ |
| `03-iam.sh` | Keycloak + Vault + cert-manager | 15 min | ✅ |
| `04-falco.sh` | Falco Runtime Security | 10 min | ✅ |
| `05-gatekeeper.sh` | OPA Gatekeeper (policies) | 5 min | ✅ |
| `06-trivy.sh` | Trivy Operator (vulnerability scan) | 5 min | ⭕ |
| `deploy-all.sh` | Déploie tout dans l'ordre | 45 min | - |

### Scripts Optionnels

| Script | Description | Note |
|--------|-------------|------|
| `optional-kibana.sh` | Kibana dashboard | ⚠️ Problèmes connus |
| `optional-wazuh.sh` | Wazuh HIDS | Nécessite 8GB RAM |

## 🚀 Utilisation

### Déploiement Complet (Automatique)

```bash
cd ~/work/enterprise-security-k8s/deploy
./deploy-all.sh
```

### Déploiement Manuel (Service par Service)

```bash
# 1. Nettoyer (optionnel)
./cleanup.sh

# 2. Créer le cluster
./01-cluster.sh

# 3. Déployer le monitoring
./02-monitoring.sh

# 4. Déployer l'IAM
./03-iam.sh

# 5. Déployer Falco
./04-falco.sh

# 6. Déployer OPA Gatekeeper
./05-gatekeeper.sh

# 7. Trivy (optionnel)
./06-trivy.sh
```

### Déploiement Partiel

```bash
# Uniquement cluster + monitoring
./01-cluster.sh
./02-monitoring.sh

# Puis tester avant de continuer
kubectl get pods --all-namespaces
```

## 🔧 Dépannage

### Un script échoue ?

Chaque script est **idempotent** et peut être relancé :

```bash
# Le script a échoué ? Relancez-le !
./03-iam.sh

# Ou nettoyez et recommencez
helm uninstall keycloak -n security-iam
./03-iam.sh
```

### Vérifier l'état

```bash
# État du cluster
kubectl get nodes

# État des pods
kubectl get pods --all-namespaces

# Pods en erreur
kubectl get pods --all-namespaces | grep -v Running

# Logs d'un pod
kubectl logs <pod-name> -n <namespace>
```

### Nettoyer et recommencer

```bash
# Nettoie TOUT
./cleanup.sh

# Puis recommencez
./01-cluster.sh
```

## 📊 Ressources Requises

### Minimum (sans Wazuh)

- **RAM** : 12 GB disponible
- **CPU** : 6 cores
- **Disk** : 30 GB

### Complet (avec Wazuh)

- **RAM** : 20 GB disponible
- **CPU** : 8 cores
- **Disk** : 40 GB

## 🌐 Accès aux Services

Après déploiement :

```bash
# Grafana (Monitoring)
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
# http://localhost:3000 (admin/admin123)

# Keycloak (IAM)
kubectl port-forward -n security-iam svc/keycloak 8080:80
# http://localhost:8080 (admin/admin123)

# Vault (Secrets)
kubectl port-forward -n security-iam svc/vault 8200:8200
# http://localhost:8200

# Falco UI
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
# http://localhost:2802
```

## 🎓 Structure des Scripts

Chaque script suit la même structure :

```bash
# 1. Vérifications préalables
# 2. Configuration des repos Helm
# 3. Déploiement avec helm upgrade --install
# 4. Attente que les pods soient Ready
# 5. Affichage de l'état
# 6. Instructions pour la suite
```

## 💡 Conseils

### Surveiller le Déploiement

```bash
# Terminal 1 : Exécuter le script
./03-iam.sh

# Terminal 2 : Surveiller les pods
watch -n 3 'kubectl get pods --all-namespaces'
```

### Problèmes Fréquents

**ImagePullBackOff** :
- Rate limit Docker Hub
- Solution : Attendre 6h ou authentifier Docker Hub

**CrashLoopBackOff** :
- Vérifier les logs : `kubectl logs <pod> -n <namespace>`
- Vérifier les ressources : `kubectl top nodes`

**Pods Pending** :
- Ressources insuffisantes
- Solution : Augmenter RAM/CPU WSL2

## 📚 Documentation Complète

Voir les guides dans `/docs` :
- `WINDOWS11-SETUP.md` - Setup complet Windows 11
- `TROUBLESHOOTING.md` - Guide de dépannage
- `architecture.md` - Architecture technique

## 🆘 Support

Si un problème persiste :

1. Vérifier les logs : `kubectl logs <pod> -n <namespace>`
2. Vérifier les events : `kubectl get events -n <namespace>`
3. Consulter `TROUBLESHOOTING.md`
4. Nettoyer et recommencer : `./cleanup.sh`

---

**Auteur** : Z3ROX
**Date** : 2025-11-10
**Version** : 2.0 (Modulaire)
