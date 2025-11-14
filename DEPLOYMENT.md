# Guide de Déploiement - Enterprise Security Stack

Ce document décrit comment déployer la stack de sécurité complète avec tous les fixes et configurations.

## 🚀 Déploiement Rapide

### Option 1 : Déploiement complet automatisé (RECOMMANDÉ)

```bash
# Déploiement complet avec tous les fixes
./scripts/deploy-complete.sh
```

Ce script orchestre :
1. ✅ Déploiement infrastructure (Terraform + Ansible)
2. ✅ Configuration Vault PKI (avec fix `require_cn=false`)
3. ✅ Génération et retry des certificats TLS
4. ✅ Configuration métriques Falco pour Prometheus
5. ✅ Vérification complète

### Option 2 : Déploiement étape par étape

Si vous avez déjà l'infrastructure déployée :

```bash
# Skip le déploiement infrastructure
./scripts/deploy-complete.sh --skip-infra

# Skip l'initialisation Vault (si déjà fait)
./scripts/deploy-complete.sh --skip-vault-init

# Combiner les deux
./scripts/deploy-complete.sh --skip-infra --skip-vault-init
```

## 📋 Prérequis

### Outils requis

- Docker
- kubectl
- Helm 3+
- Terraform
- Kind (ou autre cluster Kubernetes)
- jq (pour le parsing JSON)

### Vérification des prérequis

```bash
./scripts/check-environment.sh
```

## 🔧 Scripts Disponibles

### 1. `deploy-all.sh` - Déploiement de base

Déploie l'infrastructure de base (Terraform + Ansible) sans les fixes.

```bash
./scripts/deploy-all.sh [--skip-infra] [--skip-security]
```

### 2. `deploy-complete.sh` - Déploiement complet (RECOMMANDÉ)

Déploiement complet avec tous les fixes et configurations.

```bash
./scripts/deploy-complete.sh [--skip-infra] [--skip-vault-init]
```

### 3. `check-environment.sh` - Vérification environnement

Vérifie que tous les prérequis sont installés.

```bash
./scripts/check-environment.sh
```

## 🐛 Problèmes Connus et Solutions

### Problème 1 : Certificats TLS en échec (RBAC)

**Symptôme** :
```
Error: serviceaccounts "cert-manager" is forbidden:
User "system:serviceaccount:cert-manager:cert-manager" cannot create resource "serviceaccounts/token"
```

**Solution** : Le script `deploy-complete.sh` fixe automatiquement ce problème en configurant les bonnes permissions RBAC.

**Fix manuel** :
```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-manager-vault-token-creator
rules:
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-vault-token-creator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-manager-vault-token-creator
subjects:
- kind: ServiceAccount
  name: cert-manager
  namespace: cert-manager
EOF
```

### Problème 2 : Vault PKI exige Common Name

**Symptôme** :
```
Error: the common_name field is required, or must be provided in a CSR
with "use_csr_common_name" set to true, unless "require_cn" is set to false
```

**Solution** : Le script `deploy-complete.sh` configure automatiquement Vault PKI avec `require_cn=false`.

**Fix manuel** :
```bash
# Récupérer le pod Vault
VAULT_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

# Configurer le rôle PKI
kubectl exec -n security-iam "$VAULT_POD" -- sh -c "
export VAULT_TOKEN='<your-root-token>'
vault write pki/roles/ingress-tls \
    allowed_domains='local.lab' \
    allow_subdomains=true \
    max_ttl='720h' \
    require_cn=false \
    use_csr_common_name=false
"
```

### Problème 3 : Certificats en backoff exponentiel

**Symptôme** :
```
Backing off from issuance due to previously failed issuance(s).
Issuance will next be attempted at ...
```

**Solution** : Le script `deploy-complete.sh` force le retry des certificats automatiquement.

**Fix manuel** :
```bash
# Pour chaque certificat
kubectl get certificate <name> -n <namespace> -o yaml > cert-backup.yaml
kubectl delete certificate <name> -n <namespace>
kubectl apply -f cert-backup.yaml
```

### Problème 4 : Grafana affiche "No Data"

**Symptôme** : Les dashboards Grafana ne montrent aucune donnée.

**Causes possibles** :

1. **Prometheus ne scrape pas les targets**
   - Vérifier : `kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090`
   - Aller sur http://localhost:9090/targets
   - Vérifier que les targets sont "UP"

2. **Falco ne publie pas ses métriques**
   - Le script `deploy-complete.sh` crée automatiquement un ServiceMonitor pour Falco
   - Vérifier : `kubectl get servicemonitor -n security-detection`

3. **Datasource Grafana mal configuré**
   - Vérifier dans Grafana → Configuration → Data Sources
   - Le datasource Prometheus doit pointer vers `http://prometheus-kube-prometheus-prometheus:9090`

**Solution** : Le script `deploy-complete.sh` configure automatiquement les ServiceMonitors pour Falco.

**Vérification manuelle** :
```bash
# Vérifier les ServiceMonitors
kubectl get servicemonitor -A

# Vérifier les targets Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets

# Vérifier les métriques Falco
kubectl get svc -n security-detection falco-metrics
kubectl port-forward -n security-detection svc/falco-metrics 8765:8765
# → http://localhost:8765/metrics
```

## 📊 Vérification du Déploiement

### 1. Vérifier les pods

```bash
# Tous les namespaces
kubectl get pods -A

# Par namespace
kubectl get pods -n security-iam
kubectl get pods -n security-siem
kubectl get pods -n security-detection
kubectl get pods -n security-network
```

### 2. Vérifier les certificats TLS

```bash
# Liste des certificats
kubectl get certificates -A

# Détails d'un certificat
kubectl describe certificate <name> -n <namespace>

# Vérifier que tous sont READY=True
kubectl get certificates -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status
```

### 3. Vérifier Vault

```bash
# Status Vault
kubectl exec -n security-iam <vault-pod> -- vault status

# ClusterIssuer
kubectl get clusterissuer vault-issuer

# Doit montrer Ready=True
kubectl describe clusterissuer vault-issuer
```

### 4. Vérifier Prometheus

```bash
# Port-forward Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090

# Ouvrir http://localhost:9090
# Aller sur Status → Targets pour voir les targets scrapées
```

### 5. Vérifier Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80

# Ouvrir http://localhost:3000
# Login: admin / admin123
# Vérifier les dashboards
```

## 🌐 Accès aux Interfaces

### Avec port-forward (sans TLS)

```bash
# Grafana
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
# → http://localhost:3000 (admin/admin123)

# Kibana
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601
# → http://localhost:5601

# Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090

# Falco UI
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
# → http://localhost:2802

# Vault
kubectl port-forward -n security-iam svc/vault 8200:8200
# → http://localhost:8200

# Keycloak
kubectl port-forward -n security-iam svc/keycloak 8080:80
# → http://localhost:8080 (admin/admin123)
```

### Avec Ingress + TLS (après certificats prêts)

1. **Configurer le fichier hosts** (Windows: `C:\Windows\System32\drivers\etc\hosts`)

```
127.0.0.1  grafana.local.lab
127.0.0.1  kibana.local.lab
127.0.0.1  prometheus.local.lab
127.0.0.1  falco-ui.local.lab
```

2. **Port-forward l'Ingress Controller**

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 443:443 80:80
```

3. **Accéder aux services**

- https://grafana.local.lab
- https://kibana.local.lab
- https://prometheus.local.lab
- https://falco-ui.local.lab

## 🔍 Debugging

### Logs cert-manager

```bash
# Trouver le pod cert-manager
CERT_MGR_POD=$(kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[0].metadata.name}')

# Voir les logs
kubectl logs -n cert-manager $CERT_MGR_POD --tail=100 -f
```

### Logs Vault

```bash
# Trouver le pod Vault
VAULT_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

# Voir les logs
kubectl logs -n security-iam $VAULT_POD --tail=100 -f
```

### Logs Prometheus

```bash
# Trouver le pod Prometheus
PROM_POD=$(kubectl get pods -n security-siem -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

# Voir les logs
kubectl logs -n security-siem $PROM_POD -c prometheus --tail=100 -f
```

### Logs Falco

```bash
# Voir les logs de tous les pods Falco
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=100 -f
```

## 🧹 Nettoyage

```bash
# Détruire tout
cd terraform
terraform destroy -auto-approve

# Ou juste le cluster Kind
kind delete cluster --name security-lab
```

## 📚 Documentation

- [README.md](README.md) - Vue d'ensemble du projet
- [docs/architecture.md](docs/architecture.md) - Architecture détaillée
- [docs/WINDOWS11-SETUP.md](docs/WINDOWS11-SETUP.md) - Guide spécifique Windows 11
- [docs/equivalences.md](docs/equivalences.md) - Mapping OSS ↔ Commercial

## ❓ Support

Pour toute question ou problème :

1. Vérifier les logs des composants concernés
2. Consulter la section "Problèmes Connus" ci-dessus
3. Ouvrir une issue avec :
   - Description du problème
   - Logs pertinents
   - Sortie de `kubectl get pods -A`
   - Sortie de `kubectl get certificates -A`
