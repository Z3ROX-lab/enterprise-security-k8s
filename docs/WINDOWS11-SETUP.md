# Guide de Déploiement - Windows 11

Ce guide détaille comment déployer la stack de sécurité complète sur Windows 11 avec Docker Desktop et WSL2.

## 📋 Prérequis

### 1. Docker Desktop pour Windows

**Installation :**
1. Télécharger depuis [docker.com](https://www.docker.com/products/docker-desktop/)
2. Installer Docker Desktop
3. Activer WSL2 backend dans Settings → General → "Use the WSL 2 based engine"
4. Allocation ressources minimales :
   - **CPU** : 4 cores
   - **Memory** : 8 GB
   - **Disk** : 20 GB

**Vérification :**
```powershell
docker --version
docker run hello-world
```

### 2. WSL2 Ubuntu

**Installation depuis PowerShell (Admin) :**
```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default Ubuntu-22.04
wsl --set-version Ubuntu-22.04 2
```

**Vérification :**
```powershell
wsl --list --verbose
```

Devrait afficher :
```
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
```

### 3. Outils dans WSL2 Ubuntu

Ouvrir Ubuntu WSL2 et installer les outils nécessaires :

```bash
# Mise à jour système
sudo apt update && sudo apt upgrade -y

# Installation des dépendances
sudo apt install -y \
    curl \
    wget \
    git \
    make \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release

# Installer kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Installer Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# Installer Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform -y
terraform --version

# Installer Kind (Kubernetes in Docker)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind --version

# Installer Ansible
sudo apt install -y python3-pip
pip3 install ansible kubernetes
ansible --version
```

### 4. Configuration Docker dans WSL2

Vérifier que Docker est accessible depuis WSL2 :

```bash
docker info
```

Si erreur, installer Docker CLI dans WSL2 :

```bash
# Ajouter le repo Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce-cli docker-compose-plugin

# Docker est géré par Docker Desktop Windows, pas besoin de daemon dans WSL
```

---

## 🚀 Déploiement de la Stack

### Étape 1 : Cloner le dépôt

```bash
cd ~
git clone https://github.com/Z3ROX-lab/enterprise-security-k8s.git
cd enterprise-security-k8s
```

### Étape 2 : Vérifier l'environnement

```bash
# Vérifier tous les prérequis
./scripts/check-environment.sh
```

### Étape 3 : Déploiement automatique complet

```bash
# Déployer toute la stack (30-40 minutes)
./scripts/deploy-all.sh
```

**Ce script va :**
1. ✓ Créer un cluster Kind 4 nodes (1 control-plane + 3 workers)
2. ✓ Installer Calico CNI (NetworkPolicies)
3. ✓ Déployer ELK Stack (Elasticsearch, Kibana, Filebeat)
4. ✓ Déployer Prometheus + Grafana + Alertmanager
5. ✓ Déployer Keycloak (IAM + SSO)
6. ✓ Déployer HashiCorp Vault (Secrets Management)
7. ✓ Déployer Falco (Runtime Security)
8. ✓ Déployer Wazuh (HIDS)
9. ✓ Déployer OPA Gatekeeper (Policy Enforcement)
10. ✓ Déployer Trivy Operator (Vulnerability Scanning)
11. ✓ Appliquer NetworkPolicies (Zero Trust)
12. ✓ Configurer Pod Security Standards

### Étape 4 : Déploiement manuel (étape par étape)

Si vous préférez contrôler chaque étape :

```bash
# 1. Infrastructure uniquement (Kind cluster)
cd terraform
terraform init
terraform plan
terraform apply

# Exporter le kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# 2. Configuration Ansible
cd ../ansible
ansible-playbook playbooks/site.yml

# 3. Vérifier le déploiement
kubectl get pods --all-namespaces
```

---

## 🌐 Accès aux Interfaces

Une fois le déploiement terminé, ouvrir **plusieurs terminaux WSL2** pour les port-forwards :

### Terminal 1 - Grafana
```bash
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
```
→ Ouvrir dans Windows : http://localhost:3000
→ Credentials : `admin` / `admin123`

### Terminal 2 - Kibana
```bash
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601
```
→ Ouvrir dans Windows : http://localhost:5601

### Terminal 3 - Keycloak
```bash
kubectl port-forward -n security-iam svc/keycloak 8080:80
```
→ Ouvrir dans Windows : http://localhost:8080
→ Credentials : `admin` / `admin123`

### Terminal 4 - Vault
```bash
kubectl port-forward -n security-iam svc/vault 8200:8200
```
→ Ouvrir dans Windows : http://localhost:8200
→ Token : `root` (dev mode)

### Terminal 5 - Falco UI
```bash
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
```
→ Ouvrir dans Windows : http://localhost:2802

### Terminal 6 - Wazuh Dashboard
```bash
kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:5601
```
→ Ouvrir dans Windows : https://localhost:5443

---

## 🧪 Tests et Validation

### Test 1 : Vérifier les NetworkPolicies

```bash
# Créer un pod de test
kubectl run test-pod --rm -it --image=busybox -n demo-app -- sh

# Dans le pod, essayer de contacter différents services
# (Doit être bloqué par NetworkPolicy default-deny)
wget -O- http://keycloak.security-iam
```

### Test 2 : Déclencher une alerte Falco

```bash
# Exécuter une commande suspecte
kubectl exec -it -n demo-app deployment/frontend -- bash -c "cat /etc/shadow"

# Voir l'alerte dans Falco
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=20
```

### Test 3 : Scanner les vulnérabilités avec Trivy

```bash
# Voir les rapports de vulnérabilités
kubectl get vulnerabilityreports --all-namespaces

# Détails d'un rapport
kubectl get vulnerabilityreport <report-name> -n <namespace> -o yaml
```

### Test 4 : Vérifier les métriques Prometheus

```bash
# Port-forward Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090

# Ouvrir http://localhost:9090
# Requête exemple : kube_pod_status_phase{phase="Running"}
```

---

## 🔧 Troubleshooting

### Problème : Pods en CrashLoopBackOff

```bash
# Vérifier les logs
kubectl logs <pod-name> -n <namespace>

# Décrire le pod
kubectl describe pod <pod-name> -n <namespace>

# Vérifier les ressources
kubectl top nodes
kubectl top pods --all-namespaces
```

### Problème : Docker Desktop lent

**Augmenter les ressources :**
1. Docker Desktop → Settings → Resources
2. CPUs : 6+
3. Memory : 12 GB+
4. Swap : 2 GB

### Problème : Kind cluster ne démarre pas

```bash
# Supprimer et recréer
kind delete cluster --name enterprise-security
cd terraform
terraform destroy -auto-approve
terraform apply -auto-approve
```

### Problème : Port déjà utilisé

```bash
# Trouver le processus utilisant le port
netstat -ano | findstr :8080  # Dans PowerShell Windows

# Tuer le processus
taskkill /PID <PID> /F
```

---

## 📊 Monitoring Ressources

### Vérifier l'utilisation dans WSL2

```bash
# Ressources cluster
kubectl top nodes
kubectl top pods --all-namespaces

# Ressources Docker
docker stats
```

### Grafana Dashboards pré-configurés

Accéder à Grafana (http://localhost:3000) et explorer :

1. **Kubernetes / Compute Resources / Cluster** - Vue d'ensemble CPU/Memory
2. **Kubernetes / Networking / Pod** - Trafic réseau par pod
3. **Security Overview** - Dashboard custom (déjà chargé)
4. **Falco Alerts** - Alertes de sécurité runtime

---

## 🧹 Nettoyage

### Supprimer uniquement les workloads

```bash
cd terraform
terraform destroy -target=module.security_stack -auto-approve
terraform destroy -target=module.monitoring -auto-approve
```

### Supprimer tout le cluster

```bash
cd terraform
terraform destroy -auto-approve
```

### Supprimer Kind cluster manuellement

```bash
kind delete cluster --name enterprise-security
```

---

## 💡 Tips & Tricks

### Alias utiles pour WSL2

Ajouter dans `~/.bashrc` :

```bash
# Alias Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias kx='kubectl exec -it'

# Alias projet
alias cdp='cd ~/enterprise-security-k8s'
alias deploy='~/enterprise-security-k8s/scripts/deploy-all.sh'

# Port-forwards rapides
alias pf-grafana='kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80'
alias pf-kibana='kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601'
alias pf-keycloak='kubectl port-forward -n security-iam svc/keycloak 8080:80'
```

Puis : `source ~/.bashrc`

### Accéder aux fichiers WSL depuis Windows

Dans l'explorateur Windows : `\\wsl$\Ubuntu-22.04\home\<username>\enterprise-security-k8s`

### Éditer des fichiers avec VSCode

```bash
# Installer VSCode dans Windows puis
code .  # Depuis WSL2, ouvre VSCode Windows avec Remote-WSL
```

---

## 📚 Ressources Additionnelles

- **Docker Desktop WSL2** : https://docs.docker.com/desktop/wsl/
- **Kind Documentation** : https://kind.sigs.k8s.io/
- **Terraform Provider Kind** : https://registry.terraform.io/providers/tehcyx/kind/latest
- **Falco Rules** : https://falco.org/docs/rules/
- **OPA Gatekeeper** : https://open-policy-agent.github.io/gatekeeper/

---

## ✅ Checklist Post-Installation

- [ ] Cluster Kind créé avec 4 nodes
- [ ] Tous les namespaces créés (security-iam, security-siem, security-detection)
- [ ] ELK Stack déployé et accessible
- [ ] Prometheus + Grafana fonctionnels
- [ ] Keycloak accessible et configuré
- [ ] Vault initialisé
- [ ] Falco collecte des événements
- [ ] NetworkPolicies appliquées
- [ ] Trivy Operator scanne les images
- [ ] Dashboards Grafana affichent des données

**Félicitations ! Votre stack de cybersécurité entreprise est opérationnelle !** 🎉
