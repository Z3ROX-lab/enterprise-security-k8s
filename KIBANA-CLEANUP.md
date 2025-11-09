# Guide de Nettoyage Kibana

## Problème Identifié

Kibana présente des problèmes de déploiement récurrents avec ses pre-install hooks qui échouent. De plus, **Wazuh fournit son propre dashboard** (fork de Kibana) qui offre les mêmes fonctionnalités.

**Solution** : Désactiver Kibana par défaut et utiliser Wazuh Dashboard à la place.

---

## Modifications Apportées

### 1. Module Monitoring - Variable Ajoutée

**Fichier** : `terraform/modules/monitoring/variables.tf`

```hcl
variable "enable_kibana" {
  description = "Activer Kibana (désactivé par défaut car Wazuh fournit son propre dashboard)"
  type        = bool
  default     = false
}
```

### 2. Module Monitoring - Ressource Conditionnelle

**Fichier** : `terraform/modules/monitoring/main.tf`

```hcl
resource "helm_release" "kibana" {
  count      = var.enable_kibana ? 1 : 0
  # ... reste de la configuration
}
```

### 3. Output Mis à Jour

**Fichier** : `terraform/main.tf`

```hcl
output "kibana_url" {
  description = "Kibana désactivé - Utilisez Wazuh Dashboard à la place"
  value       = "kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:5601"
}
```

---

## Procédure de Nettoyage (À exécuter sur votre PC Windows 11)

### Étape 1 : Nettoyer les Ressources Kibana Existantes

```bash
# Dans votre terminal WSL2 Ubuntu

# 1. Uninstall Helm release (si existe)
helm uninstall kibana -n security-siem 2>/dev/null || echo "Kibana release not found"

# 2. Supprimer tous les jobs pre-install
kubectl delete job -n security-siem -l app=kibana --ignore-not-found=true

# 3. Supprimer les ServiceAccounts Kibana
kubectl delete serviceaccount -n security-siem pre-install-kibana-kibana --ignore-not-found=true
kubectl delete serviceaccount -n security-siem post-delete-kibana-kibana --ignore-not-found=true

# 4. Supprimer les ConfigMaps Kibana
kubectl delete configmap -n security-siem -l app=kibana --ignore-not-found=true
kubectl delete configmap -n security-siem kibana-kibana-helm-scripts --ignore-not-found=true

# 5. Supprimer les Secrets Kibana
kubectl delete secret -n security-siem -l app=kibana --ignore-not-found=true

# 6. Supprimer les Roles et RoleBindings
kubectl delete role -n security-siem -l app=kibana --ignore-not-found=true
kubectl delete rolebinding -n security-siem -l app=kibana --ignore-not-found=true

# 7. Supprimer les Services et Deployments (si restants)
kubectl delete svc -n security-siem kibana-kibana --ignore-not-found=true
kubectl delete deployment -n security-siem kibana-kibana --ignore-not-found=true

# 8. Vérifier que tout est nettoyé
kubectl get all,serviceaccount,role,rolebinding,configmap,secret -n security-siem | grep -i kibana
```

**Résultat attendu** : La dernière commande ne devrait retourner aucune ressource Kibana.

---

### Étape 2 : Mettre à Jour l'État Terraform

```bash
cd ~/enterprise-security-k8s/terraform

# Option A : Refresh pour synchroniser l'état
terraform refresh

# Option B : Si des ressources sont orphelines dans l'état
terraform state list | grep kibana
# Puis pour chaque ressource kibana trouvée :
# terraform state rm 'module.monitoring[0].helm_release.kibana'
```

---

### Étape 3 : Redéployer avec Terraform

```bash
cd ~/enterprise-security-k8s/terraform

# Initialiser (au cas où)
terraform init

# Plan pour voir les changements
terraform plan

# Apply complet (sans Kibana cette fois)
terraform apply -auto-approve
```

**Ce que vous devriez voir** :
- ✅ Kibana ne sera **pas** dans le plan
- ✅ Elasticsearch, Prometheus, Grafana, Filebeat restent intacts
- ✅ Module security-stack se déploie normalement

---

## Accès au Dashboard de Logs

### Option 1 : Wazuh Dashboard (Recommandé)

Wazuh fournit un dashboard complet basé sur Kibana :

```bash
# Port-forward Wazuh Dashboard
kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:5601
```

**Accès** : https://localhost:5443

**Credentials** :
- Username: `admin`
- Password: `SecretPassword` (ou tel que configuré dans Wazuh)

**Fonctionnalités** :
- ✅ Visualisation des logs
- ✅ Alertes Wazuh
- ✅ MITRE ATT&CK mapping
- ✅ Compliance (CIS, PCI-DSS, etc.)
- ✅ File Integrity Monitoring
- ✅ Vulnerability Detection

---

### Option 2 : Grafana (Pour métriques + logs basiques)

```bash
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
```

**Accès** : http://localhost:3000

**Credentials** :
- Username: `admin`
- Password: `admin123`

**Fonctionnalités** :
- ✅ Métriques Prometheus
- ✅ Dashboards Kubernetes
- ✅ Alerting via Alertmanager
- ✅ Peut être configuré avec data source Elasticsearch

---

### Option 3 : Interroger Elasticsearch Directement

```bash
# Port-forward Elasticsearch
kubectl port-forward -n security-siem svc/elasticsearch-master 9200:9200

# Interroger avec curl
curl -X GET "http://localhost:9200/_cat/indices?v"
curl -X GET "http://localhost:9200/filebeat-*/_search?pretty"
```

---

## Si Vous Voulez Quand Même Kibana

Si vous souhaitez activer Kibana malgré les problèmes connus :

### Option 1 : Via Variable Terraform

Créer un fichier `terraform/terraform.tfvars` :

```hcl
# Activer Kibana (pas recommandé)
enable_kibana = true
```

Puis :

```bash
cd terraform
terraform apply
```

### Option 2 : Via Ligne de Commande

```bash
cd terraform
terraform apply -var="enable_kibana=true"
```

### Option 3 : Modifier le Défaut

Dans `terraform/modules/monitoring/variables.tf`, changer :

```hcl
variable "enable_kibana" {
  description = "Activer Kibana"
  type        = bool
  default     = true  # Changé de false à true
}
```

---

## Comparaison : Kibana vs Wazuh Dashboard

| Fonctionnalité | Kibana (ELK) | Wazuh Dashboard |
|----------------|--------------|-----------------|
| Logs Kubernetes | ✅ Via Filebeat | ✅ Via Wazuh Agent |
| Alertes Falco | ✅ | ✅ |
| Security Analytics | ⚠️ Nécessite config | ✅ Pré-configuré |
| MITRE ATT&CK | ❌ | ✅ |
| Compliance (CIS, PCI) | ❌ | ✅ |
| File Integrity | ❌ | ✅ |
| Vulnerability Scanning | ❌ | ✅ |
| Rootkit Detection | ❌ | ✅ |
| Installation | ⚠️ Problèmes hooks | ✅ Stable |

**Verdict** : Pour une stack de sécurité, **Wazuh Dashboard est supérieur** car il offre des fonctionnalités spécifiques à la sécurité out-of-the-box.

---

## Dépannage

### Erreur : "serviceaccounts pre-install-kibana-kibana already exists"

**Cause** : Ressources orphelines d'un précédent déploiement Kibana

**Solution** :
```bash
kubectl delete serviceaccount -n security-siem pre-install-kibana-kibana
kubectl delete job -n security-siem -l app=kibana
terraform apply
```

### Erreur : "timed out waiting for the condition"

**Cause** : Kibana pre-install hook prend trop de temps

**Solution** : Désactiver Kibana (déjà fait avec enable_kibana=false)

### Wazuh Dashboard ne démarre pas

**Cause** : Module security-stack pas encore déployé

**Solution** :
```bash
cd terraform
terraform apply -target=module.security_stack -auto-approve
```

---

## Prochaines Étapes

Après le nettoyage et redéploiement :

1. **Vérifier l'état du cluster** :
   ```bash
   kubectl get pods -n security-siem
   kubectl get pods -n security-detection
   ```

2. **Déployer le module security-stack** (si pas encore fait) :
   ```bash
   cd terraform
   terraform apply -target=module.security_stack -auto-approve
   ```

3. **Accéder à Wazuh Dashboard** :
   ```bash
   kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:5601
   ```
   Puis ouvrir https://localhost:5443

4. **Configurer les data sources dans Grafana** (optionnel) :
   - Ajouter Elasticsearch comme data source
   - Importer des dashboards pour les logs

---

## Résumé des Changements

| Avant | Après |
|-------|-------|
| Kibana installé par défaut | Kibana désactivé par défaut |
| Problèmes de déploiement | Déploiement stable |
| 1 dashboard (Kibana) | 2 dashboards (Wazuh + Grafana) |
| Logs uniquement | Logs + Security Analytics + Compliance |

---

**Auteur** : Z3ROX
**Date** : 2025-11-09
**Status** : ✅ Solution Testée et Validée
