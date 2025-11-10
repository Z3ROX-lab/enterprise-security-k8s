# Guide de Dépannage - Déploiement Security Stack

## Problèmes Rencontrés

### 1. Context Deadline Exceeded (Timeouts)

**Symptômes** :
```
Error: context deadline exceeded
  with module.security_stack[0].helm_release.keycloak
  with module.security_stack[0].helm_release.vault
  with module.security_stack[0].helm_release.falco
```

**Causes** :
- Ressources insuffisantes (RAM/CPU)
- Pods en CrashLoopBackOff
- Images Docker lentes à télécharger
- PostgreSQL (Keycloak) ou autres dépendances lentes à démarrer

**Solutions Appliquées** :
- ✅ Augmentation des timeouts de 600s (10min) → 1200s (20min)
- ✅ Ajout de `wait = true` pour attendre que les pods soient Ready
- ✅ Ajout de `wait_for_jobs = true` pour Keycloak (attend les jobs de migration)

---

### 2. Erreur Wazuh Kustomize

**Symptôme** :
```
error: evalsymlink failure on '/tmp/kustomize-2026077951/deployments/kubernetes'
lstat /tmp/kustomize-2026077951/deployments: no such file or directory
```

**Cause** :
- Syntaxe `//` dans URL GitHub ne fonctionne pas avec toutes les versions de kubectl
- Kustomize ne peut pas résoudre le remote path

**Solution Appliquée** :
- ✅ Clone le repository Wazuh localement dans `/tmp/wazuh-kubernetes`
- ✅ Applique Kustomize depuis le repo cloné
- ✅ Réutilise le clone existant si déjà présent

---

## Diagnostic Post-Erreur

### Vérifier l'État des Pods

```bash
# Voir tous les pods et leur statut
kubectl get pods --all-namespaces

# Filtrer les pods en erreur
kubectl get pods --all-namespaces | grep -E "Error|CrashLoop|Pending"

# Détails sur un pod spécifique
kubectl describe pod <pod-name> -n <namespace>

# Logs d'un pod en échec
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Logs du container précédent
```

### Vérifier les Ressources du Cluster

```bash
# État des nœuds
kubectl top nodes

# Utilisation CPU/Mémoire des pods
kubectl top pods --all-namespaces

# Vérifier les ressources disponibles
kubectl describe nodes
```

### Vérifier les Helm Releases

```bash
# Lister toutes les releases
helm list --all-namespaces

# Status d'une release spécifique
helm status keycloak -n security-iam
helm status vault -n security-iam
helm status falco -n security-detection

# Historique des déploiements
helm history keycloak -n security-iam
```

---

## Solutions aux Problèmes Courants

### Problème 1 : Keycloak en Échec

**Diagnostic** :
```bash
kubectl get pods -n security-iam
kubectl logs -n security-iam <keycloak-pod> -f
kubectl logs -n security-iam <postgresql-pod> -f
```

**Causes fréquentes** :
- PostgreSQL ne démarre pas (manque de ressources)
- Migration database timeout
- Credentials incorrects

**Solutions** :

#### A. Augmenter les ressources PostgreSQL
```bash
# Éditer les valeurs Helm
helm upgrade keycloak bitnami/keycloak \
  -n security-iam \
  --set postgresql.primary.resources.requests.memory=512Mi \
  --set postgresql.primary.resources.limits.memory=1Gi
```

#### B. Redémarrer PostgreSQL
```bash
kubectl rollout restart statefulset/keycloak-postgresql -n security-iam
```

#### C. Nettoyer et redéployer
```bash
helm uninstall keycloak -n security-iam
kubectl delete pvc -n security-iam data-keycloak-postgresql-0
terraform apply -target=module.security_stack[0].helm_release.keycloak
```

---

### Problème 2 : Vault en Échec

**Diagnostic** :
```bash
kubectl get pods -n security-iam | grep vault
kubectl logs -n security-iam <vault-pod> -f
```

**Causes fréquentes** :
- Vault non-initialisé (mode dev)
- Problème de storage
- Injector échoue

**Solutions** :

#### A. Vérifier le mode dev
```bash
kubectl exec -it -n security-iam vault-0 -- vault status
```

#### B. Initialiser Vault (si mode production)
```bash
kubectl exec -it -n security-iam vault-0 -- vault operator init
kubectl exec -it -n security-iam vault-0 -- vault operator unseal <unseal-key>
```

#### C. Redéployer en mode dev
```bash
helm upgrade vault hashicorp/vault \
  -n security-iam \
  --set server.dev.enabled=true \
  --set server.ha.enabled=false
```

---

### Problème 3 : Falco en Échec

**Diagnostic** :
```bash
kubectl get pods -n security-detection | grep falco
kubectl logs -n security-detection <falco-pod> -f
```

**Causes fréquentes** :
- Driver eBPF ne se charge pas
- Kernel trop ancien
- Permissions insuffisantes

**Solutions** :

#### A. Vérifier le driver
```bash
kubectl exec -it -n security-detection <falco-pod> -- falco-driver-loader
```

#### B. Passer au kernel module (si eBPF échoue)
```bash
helm upgrade falco falcosecurity/falco \
  -n security-detection \
  --set driver.kind=module
```

#### C. Vérifier les logs du driver
```bash
kubectl logs -n security-detection <falco-pod> -c falco-driver-loader
```

---

### Problème 4 : Wazuh en Échec

**Diagnostic** :
```bash
kubectl get pods -n security-detection | grep wazuh
kubectl logs -n security-detection wazuh-manager-master-0 -f
kubectl logs -n security-detection wazuh-indexer-0 -f
```

**Causes fréquentes** :
- Indexer ne démarre pas (discovery nodes)
- Ressources insuffisantes (8GB requis minimum)
- PVC non-créés

**Solutions** :

#### A. Vérifier les StatefulSets
```bash
kubectl get statefulsets -n security-detection
kubectl describe statefulset wazuh-manager-master -n security-detection
kubectl describe statefulset wazuh-indexer -n security-detection
```

#### B. Augmenter les ressources
```bash
kubectl edit statefulset wazuh-indexer -n security-detection
# Modifier resources.requests.memory à 2Gi minimum
```

#### C. Redéployer Wazuh
```bash
kubectl delete -k /tmp/wazuh-kubernetes/deployments/kubernetes/ -n security-detection
kubectl apply -k /tmp/wazuh-kubernetes/deployments/kubernetes/ -n security-detection
```

---

## Stratégie de Déploiement Progressive

Si le déploiement complet échoue, déployer **composant par composant** :

### Étape 1 : IAM Uniquement

```bash
cd ~/enterprise-security-k8s/terraform

# Désactiver tout sauf IAM
cat > terraform.tfvars <<EOF
enable_falco = false
enable_wazuh = false
enable_gatekeeper = false
enable_trivy = false
EOF

terraform apply -target=module.security_stack[0].helm_release.keycloak
terraform apply -target=module.security_stack[0].helm_release.vault
terraform apply -target=module.security_stack[0].helm_release.cert_manager
```

**Vérifier** :
```bash
kubectl get pods -n security-iam
# Attendre que tout soit Running
```

### Étape 2 : Ajouter Falco

```bash
cat > terraform.tfvars <<EOF
enable_falco = true
enable_wazuh = false
enable_gatekeeper = false
enable_trivy = false
EOF

terraform apply -target=module.security_stack[0].helm_release.falco
```

**Vérifier** :
```bash
kubectl get pods -n security-detection
```

### Étape 3 : Ajouter Wazuh

```bash
cat > terraform.tfvars <<EOF
enable_falco = true
enable_wazuh = true
enable_gatekeeper = false
enable_trivy = false
EOF

terraform apply -target=module.security_stack[0].null_resource.wazuh_deployment[0]
```

**Vérifier** :
```bash
kubectl get pods -n security-detection
# Attendre 10 minutes pour Wazuh
```

### Étape 4 : Ajouter OPA + Trivy

```bash
cat > terraform.tfvars <<EOF
enable_falco = true
enable_wazuh = true
enable_gatekeeper = true
enable_trivy = true
EOF

terraform apply
```

---

## Vérification des Ressources WSL2

### Vérifier la Configuration .wslconfig

```powershell
# Dans PowerShell Windows
notepad $env:USERPROFILE\.wslconfig
```

**Configuration recommandée** :
```ini
[wsl2]
memory=16GB
processors=8
swap=4GB
localhostForwarding=true
```

### Vérifier les Ressources Disponibles

```bash
# Dans WSL2 Ubuntu
free -h
nproc
df -h
```

**Minimum requis pour la stack complète** :
- RAM : 16 GB (12 GB disponible pour Kubernetes)
- CPU : 8 cores
- Disk : 40 GB libre

### Redimensionner Docker Desktop

1. Ouvrir Docker Desktop
2. Settings → Resources → Advanced
3. Allouer :
   - Memory : 12 GB minimum
   - CPUs : 6 minimum
   - Swap : 2 GB
   - Disk : 60 GB

---

## Nettoyage et Redéploiement

### Nettoyage Complet

```bash
# Supprimer toutes les releases Helm
helm uninstall keycloak -n security-iam
helm uninstall vault -n security-iam
helm uninstall cert-manager -n cert-manager
helm uninstall falco -n security-detection
helm uninstall gatekeeper -n gatekeeper-system
helm uninstall trivy-operator -n trivy-system

# Supprimer les namespaces
kubectl delete namespace security-iam
kubectl delete namespace security-detection
kubectl delete namespace gatekeeper-system
kubectl delete namespace trivy-system

# Supprimer Wazuh
kubectl delete -k /tmp/wazuh-kubernetes/deployments/kubernetes/ -n security-detection

# Nettoyer l'état Terraform
cd ~/enterprise-security-k8s/terraform
terraform destroy -target=module.security_stack
```

### Redéploiement Propre

```bash
# 1. Vérifier les ressources
free -h
kubectl top nodes

# 2. Nettoyer terraform.tfvars si présent
rm terraform.tfvars

# 3. Redéployer
terraform init
terraform plan
terraform apply -auto-approve
```

---

## Surveillance Continue

### Monitoring en Temps Réel

```bash
# Terminal 1 : Pods
watch -n 3 'kubectl get pods --all-namespaces'

# Terminal 2 : Ressources
watch -n 5 'kubectl top nodes && echo "" && kubectl top pods --all-namespaces'

# Terminal 3 : Events
kubectl get events --all-namespaces --watch
```

### Alertes Importantes

Surveiller ces événements :
- `OOMKilled` → Manque de RAM
- `Evicted` → Manque d'espace disque
- `CrashLoopBackOff` → Application échoue au démarrage
- `ImagePullBackOff` → Problème de téléchargement d'image
- `Pending` → Ressources insuffisantes pour scheduler

---

## Logs de Débogage

### Activer le Mode Debug pour Helm

```bash
export HELM_DEBUG=1
helm install <release> <chart> --debug --dry-run
```

### Logs Terraform Détaillés

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform-debug.log
terraform apply
```

### Logs kubectl Verbeux

```bash
kubectl apply -f manifest.yaml -v=9
```

---

## Checklist Pré-Déploiement

Avant de lancer `terraform apply`, vérifier :

- [ ] WSL2 configuré avec 16GB RAM minimum
- [ ] Docker Desktop avec 12GB RAM alloués
- [ ] Cluster Kind existant et healthy (`kubectl get nodes`)
- [ ] Monitoring stack déployé (`kubectl get pods -n security-siem`)
- [ ] 40GB d'espace disque libre (`df -h`)
- [ ] Connexion internet stable (téléchargement images)
- [ ] Pas d'autres applications lourdes en cours

---

## Ressources par Composant

| Composant | CPU Request | RAM Request | RAM Limit | Pods | Temps Démarrage |
|-----------|-------------|-------------|-----------|------|-----------------|
| **Keycloak** | 1 core | 1 GB | 2 GB | 1 | 5-8 min |
| **PostgreSQL** | 0.5 core | 512 MB | 1 GB | 1 | 2-3 min |
| **Vault** | 0.5 core | 256 MB | 512 MB | 1-3 | 2-5 min |
| **Falco** | 0.2 core | 512 MB | 1 GB | 1 per node | 3-5 min |
| **Wazuh Manager** | 2 cores | 4 GB | 8 GB | 1 | 5-10 min |
| **Wazuh Indexer** | 1 core | 2 GB | 4 GB | 1 | 3-5 min |
| **Wazuh Dashboard** | 0.5 core | 1 GB | 2 GB | 1 | 2-3 min |
| **OPA Gatekeeper** | 0.1 core | 128 MB | 512 MB | 3 | 1-2 min |
| **Trivy Operator** | 0.2 core | 256 MB | 512 MB | 2 | 2-3 min |
| **TOTAL** | ~7-9 cores | ~12-14 GB | ~24 GB | ~12-15 | **20-30 min** |

---

## Contacts & Support

**Documentation** :
- Terraform : https://registry.terraform.io/providers/hashicorp/helm/latest/docs
- Keycloak : https://www.keycloak.org/docs/
- Vault : https://developer.hashicorp.com/vault/docs
- Falco : https://falco.org/docs/
- Wazuh : https://documentation.wazuh.com/

**Issues Connues** :
- Voir `KIBANA-CLEANUP.md` pour les problèmes Kibana
- Voir `WAZUH-DEPLOYMENT.md` pour les problèmes Wazuh
- Voir `IMPLEMENTATION-REVIEW.md` pour l'état global

---

**Auteur** : Z3ROX
**Date** : 2025-11-09
**Version** : 1.0
**Status** : ✅ Testé et Validé
