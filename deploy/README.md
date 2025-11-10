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
| `01-cluster-kind.sh` | Crée le cluster Kind (4 nœuds) | 3 min | ✅ |
| **Monitoring & SIEM** ||||
| `10-elasticsearch.sh` | Elasticsearch (logs storage) | 5 min | ✅ |
| `11-kibana.sh` | Kibana dashboard | 5 min | ⭕ Problématique |
| `12-filebeat.sh` | Filebeat (log shipper) | 2 min | ✅ |
| `13-prometheus.sh` | Prometheus + Grafana + Alertmanager | 8 min | ✅ |
| **IAM & Secrets** ||||
| `20-cert-manager.sh` | cert-manager (PKI) | 3 min | ✅ |
| `21-keycloak.sh` | Keycloak (SSO/OIDC) | 8 min | ✅ |
| `22-vault-dev.sh` | Vault Dev mode (test) | 3 min | ⭕ |
| `23-vault-raft.sh` | Vault Raft HA (production) | 5 min | ⭕ |
| `24-vault-pki.sh` | Vault PKI (Certificate Authority) | 2 min | ⭕ |
| **Security Detection** ||||
| `30-falco.sh` | Falco Runtime Security | 10 min | ✅ |
| `31-wazuh.sh` | Wazuh HIDS | 15 min | ⭕ Gourmand |
| **Policy & Compliance** ||||
| `40-gatekeeper.sh` | OPA Gatekeeper (admission control) | 5 min | ✅ |
| `41-trivy.sh` | Trivy Operator (vulnerability scan) | 5 min | ⭕ |
| **Orchestration** ||||
| `deploy-all.sh` | Déploie tout dans l'ordre | 45 min | - |

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
./01-cluster-kind.sh

# 3. Monitoring & SIEM
./10-elasticsearch.sh    # Requis pour les logs
./11-kibana.sh          # Optionnel (problèmes connus)
./12-filebeat.sh        # Optionnel (envoi logs vers Elasticsearch)
./13-prometheus.sh      # Requis (Prometheus + Grafana)

# 4. IAM & Secrets
./20-cert-manager.sh    # Requis pour les certificats
./21-keycloak.sh        # Authentification & SSO

# Vault : Choisir UN des deux modes
./22-vault-dev.sh       # Dev mode (test rapide)
# OU
./23-vault-raft.sh      # Production HA (persistent)

./24-vault-pki.sh       # Configuration PKI (après Vault)

# 5. Security Detection
./30-falco.sh           # Runtime security
./31-wazuh.sh           # HIDS (optionnel, 8GB RAM)

# 6. Policy & Compliance
./40-gatekeeper.sh      # Admission control
./41-trivy.sh           # Vulnerability scanning (optionnel)
```

### Déploiement Partiel

```bash
# Exemple 1 : Uniquement cluster + monitoring basique
./01-cluster-kind.sh
./10-elasticsearch.sh
./13-prometheus.sh

# Exemple 2 : Cluster + IAM uniquement
./01-cluster-kind.sh
./20-cert-manager.sh
./21-keycloak.sh
./22-vault-dev.sh

# Exemple 3 : Cluster + Security Detection
./01-cluster-kind.sh
./30-falco.sh

# Puis tester avant de continuer
kubectl get pods --all-namespaces
```

### Choix des Scripts selon Votre Besoin

**Pour un environnement de test rapide** :
```bash
./01-cluster-kind.sh
./13-prometheus.sh       # Monitoring
./22-vault-dev.sh        # Secrets (dev mode)
./30-falco.sh            # Security
```

**Pour un environnement de production** :
```bash
./01-cluster-kind.sh
./10-elasticsearch.sh
./12-filebeat.sh
./13-prometheus.sh
./20-cert-manager.sh
./21-keycloak.sh
./23-vault-raft.sh      # Production HA
./24-vault-pki.sh
./30-falco.sh
./31-wazuh.sh           # Si vous avez 8GB RAM
./40-gatekeeper.sh
./41-trivy.sh
```

## 🔧 Dépannage

### Un script échoue ?

Chaque script est **idempotent** et peut être relancé :

```bash
# Le script a échoué ? Relancez-le !
./21-keycloak.sh

# Ou nettoyez le composant et recommencez
helm uninstall keycloak -n security-iam
./21-keycloak.sh

# Pour Falco avec problèmes de driver
kubectl delete namespace security-detection
./30-falco.sh
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
# Nettoie TOUT (cluster + tous les composants)
./cleanup.sh

# Puis recommencez from scratch
./01-cluster-kind.sh

# Ou déploiement automatique complet
./deploy-all.sh
```

### Problèmes Spécifiques

**Kibana (problèmes connus)** :
- Pre-install hooks qui timeout
- Solution : Ne pas installer Kibana, utiliser Grafana
- Ou : Nettoyer manuellement avant réessai
```bash
kubectl delete job,pod,configmap,secret -n security-siem -l app=kibana
./11-kibana.sh
```

**Falco CrashLoopBackOff** :
- Vérifier que le driver kernel module se charge
```bash
kubectl logs -n security-detection -l app.kubernetes.io/name=falco -c falco-driver-loader
# Si erreurs : le kernel module peut prendre 5-10 min à compiler
```

**Wazuh ne démarre pas** :
- Vérifier les ressources disponibles (8GB RAM minimum)
```bash
free -h
kubectl top nodes
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

Chaque script suit la même structure pour une expérience cohérente :

```bash
#!/bin/bash
set -e

# 1. Bannière descriptive
echo "╔═══════════════════════════════════════════╗"
echo "║        Nom du Service                     ║"
echo "╚═══════════════════════════════════════════╝"

# 2. Vérifications préalables
# - Cluster existe ?
# - Dépendances installées ?
# - Ressources suffisantes ?

# 3. Demander confirmation utilisateur
read -p "Continuer ? (y/n) "

# 4. Configuration des repos Helm
helm repo add <repo> <url>
helm repo update

# 5. Déploiement avec helm upgrade --install
# - namespace créé automatiquement
# - wait=false (pas de blocage)
# - timeout raisonnable

# 6. Boucle de surveillance (non-bloquante)
# - Vérifier status des pods
# - Afficher progression
# - Détecter erreurs

# 7. Affichage état final
kubectl get pods -n <namespace>

# 8. Instructions d'accès
# - Port-forward commands
# - Credentials par défaut
# - Prochaines étapes

# 9. Suggestions pour la suite
echo "Prochaine étape : ./XX-next-script.sh"
```

### Avantages de cette Structure

✅ **Non-bloquant** : `wait=false` permet aux pods de démarrer en arrière-plan
✅ **Informatif** : Affichage en temps réel de la progression
✅ **Idempotent** : Peut être relancé sans problème (`helm upgrade --install`)
✅ **Sûr** : Demande confirmation avant actions importantes
✅ **Debuggable** : Instructions claires pour vérifier/dépanner

## 💡 Conseils

### Surveiller le Déploiement

```bash
# Terminal 1 : Exécuter le script
./21-keycloak.sh

# Terminal 2 : Surveiller les pods en temps réel
watch -n 3 'kubectl get pods --all-namespaces'

# Terminal 3 : Surveiller les events (pour debugging)
kubectl get events --all-namespaces --watch
```

### Ordre de Déploiement Recommandé

Les scripts sont numérotés pour suggérer un ordre logique :

1. **01-** : Infrastructure (cluster)
2. **10-19** : Monitoring & SIEM (observabilité d'abord)
3. **20-29** : IAM & Secrets (identité et certificats)
4. **30-39** : Security Detection (runtime security)
5. **40-49** : Policy & Compliance (gouvernance)

💡 Mais vous pouvez les exécuter dans n'importe quel ordre selon vos besoins !

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

## 🔄 Différences avec l'Approche Précédente

### Avant (Terraform monolithique)
- ❌ Déploiement groupé de plusieurs services
- ❌ Timeouts bloquants (`wait=true`)
- ❌ Difficile de débugger quel service pose problème
- ❌ Tout ou rien : échec d'un service bloque tout
- ❌ État Terraform complexe à gérer

### Maintenant (Scripts Helm individuels)
- ✅ Un script = un service
- ✅ Déploiements non-bloquants (`wait=false`)
- ✅ Facile d'identifier et corriger les problèmes
- ✅ Déploiement à la carte selon vos besoins
- ✅ Pas de state Terraform à gérer
- ✅ Relancer un script spécifique en cas d'échec
- ✅ Monitoring en temps réel dans les scripts

### Migration

Si vous aviez déployé avec Terraform :

```bash
# 1. Nettoyer complètement
./cleanup.sh

# 2. Redéployer avec les nouveaux scripts
./deploy-all.sh
# Ou service par service
```

## 📝 Notes Importantes

### Kibana
- Problèmes connus avec les pre-install hooks
- Recommandation : Utiliser Grafana à la place
- Script `11-kibana.sh` fourni mais optionnel

### Vault Dev vs Raft
- **Dev mode** (`22-vault-dev.sh`) : Test rapide, données en mémoire, auto-unseal
- **Raft mode** (`23-vault-raft.sh`) : Production, persistent, HA, nécessite init/unseal manuel

### Falco Driver
- Utilise kernel module (pas eBPF)
- Compatible WSL2/Kind
- Le chargement peut prendre 5-10 min (compilation)

### Wazuh
- Nécessite 8GB RAM minimum
- Déploiement avec Kustomize depuis GitHub
- Optionnel mais recommandé pour HIDS

---

**Auteur** : Z3ROX
**Date** : 2025-11-10
**Version** : 2.0 (Modulaire - From Scratch)
**Architecture** : Scripts Helm individuels pour contrôle total
