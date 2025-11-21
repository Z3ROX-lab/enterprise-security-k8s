# Guide de Déploiement GitOps - Commandes et Workflow

Ce document explique toutes les commandes nécessaires pour déployer une application via le pipeline GitOps (Gitea + ArgoCD).

## Table des Matières

1. [Vue d'ensemble du Workflow](#vue-densemble-du-workflow)
2. [Prérequis](#prérequis)
3. [Méthode Manuelle (Commandes détaillées)](#méthode-manuelle-commandes-détaillées)
4. [Méthode Automatisée (Script)](#méthode-automatisée-script)
5. [Test du Pipeline GitOps](#test-du-pipeline-gitops)
6. [Référence des Commandes](#référence-des-commandes)

---

## Vue d'ensemble du Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    PIPELINE GITOPS                           │
└─────────────────────────────────────────────────────────────┘

   DÉVELOPPEUR              GIT SERVER           GITOPS            KUBERNETES
       │                        │                  │                    │
       │   1. git push          │                  │                    │
       ├───────────────────────▶│  Gitea           │                    │
       │                        │  (Repository)    │                    │
       │                        │                  │                    │
       │                        │   2. Poll/Sync   │                    │
       │                        ├─────────────────▶│  ArgoCD            │
       │                        │                  │  (Controller)      │
       │                        │                  │                    │
       │                        │                  │   3. Apply         │
       │                        │                  ├───────────────────▶│
       │                        │                  │                    │  Pods
       │                        │                  │                    │  Services
       │                        │                  │                    │  etc.
       │                        │                  │                    │
```

**Concept clé** : "Ce qui est dans Git est ce qui tourne dans Kubernetes"

---

## Prérequis

### Services déployés
- ✅ ArgoCD déployé dans le namespace `argocd`
- ✅ Gitea déployé dans le namespace `gitea`
- ✅ Ingress configurés pour ArgoCD et Gitea

### Accès configuré
- ✅ `/etc/hosts` configuré avec `argocd.local.lab` et `gitea.local.lab`
- ✅ Port-forward actif (`./scripts/start-ingress-portforward.sh`)

### Dans Gitea
- ✅ Organisation "demo" créée
- ✅ Repository créé (même nom que l'application, ex: `demo-nginx`)

---

## Méthode Manuelle (Commandes détaillées)

### Étape 1 : Préparation du repo Git local

```bash
# Se déplacer dans le dossier de l'application
cd ~/work/enterprise-security-k8s/gitops-apps/demo-nginx
```

**Explication** : Chaque application GitOps a son propre dossier avec les manifests Kubernetes (deployment.yaml, service.yaml, etc.)

### Étape 2 : Initialiser le repo Git

```bash
# Initialiser un nouveau repo Git local
git init
```

**Explication** :
- `git init` crée un dossier `.git` qui contient l'historique des modifications
- C'est le point de départ pour tracker le code avec Git
- Un repo Git est comme un "journal" de toutes les versions du code

### Étape 3 : Ajouter les fichiers au staging

```bash
# Ajouter tous les fichiers au staging area
git add .
```

**Explication** :
- Le "staging area" est une zone intermédiaire entre les fichiers modifiés et le commit
- `git add .` ajoute TOUS les fichiers du dossier
- Vous pouvez aussi ajouter des fichiers spécifiques : `git add deployment.yaml`

### Étape 4 : Configurer l'identité Git

```bash
# Définir le nom d'utilisateur
git config user.name "gitea-admin"

# Définir l'email
git config user.email "admin@gitea.local.lab"
```

**Explication** :
- Git a besoin de savoir qui fait les commits (pour l'historique)
- Ces infos apparaissent dans chaque commit
- Sans `--global`, la config est locale au repo uniquement

### Étape 5 : Créer le commit

```bash
# Créer un commit avec un message descriptif
git commit -m "Initial commit: Demo nginx app"
```

**Explication** :
- Un commit est un "snapshot" du code à un instant T
- Le message (`-m`) décrit ce qui a été fait
- Chaque commit a un identifiant unique (hash SHA)

**Output attendu** :
```
[master (root-commit) e6e2424] Initial commit: Demo nginx app
 5 files changed, 294 insertions(+)
 create mode 100644 README.md
 create mode 100644 configmap.yaml
 create mode 100644 deployment.yaml
 create mode 100644 ingress.yaml
 create mode 100644 service.yaml
```

### Étape 6 : Renommer la branche en "main"

```bash
# Renommer la branche de "master" à "main"
git branch -m main
```

**Explication** :
- Par défaut, Git crée une branche "master"
- La convention moderne est d'utiliser "main"
- ArgoCD est configuré pour sync depuis la branche "main"

### Étape 7 : Désactiver la vérification SSL

```bash
# Désactiver SSL verify (pour certificats auto-signés)
git config http.sslVerify false
```

**Explication** :
- On utilise des certificats auto-signés pour Gitea (dev)
- Git refuserait de se connecter sans cette option
- ⚠️ En production, utilisez des certificats valides !

### Étape 8 : Ajouter le remote Gitea

```bash
# Ajouter l'URL du repo distant sur Gitea
git remote add origin https://gitea.local.lab:8443/demo/demo-nginx.git
```

**Explication** :
- Un "remote" est une référence vers un repo sur un serveur
- "origin" est le nom conventionnel du remote principal
- L'URL suit le format : `https://gitea/organisation/repo.git`

### Étape 9 : Pousser vers Gitea

```bash
# Pousser la branche main vers Gitea
git push -u origin main
```

**Explication** :
- `git push` envoie les commits locaux vers le serveur
- `-u` (ou `--set-upstream`) lie la branche locale à la distante
- Après `-u`, vous pouvez juste faire `git push`

**Credentials** (si demandés) :
- Username: `gitea-admin`
- Password: `gitea123!`

**Output attendu** :
```
Enumerating objects: 7, done.
Counting objects: 100% (7/7), done.
Delta compression using up to 8 threads
Compressing objects: 100% (7/7), done.
Writing objects: 100% (7/7), 3.25 KiB | 3.25 MiB/s, done.
Total 7 (delta 0), reused 0 (delta 0), pack-reused 0
To https://gitea.local.lab:8443/demo/demo-nginx.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

### Étape 10 : Déployer l'application ArgoCD

```bash
# Créer l'application ArgoCD
kubectl apply -f ~/work/enterprise-security-k8s/gitops-apps/argocd-apps/demo-nginx-app.yaml
```

**Explication** :
- Le fichier `demo-nginx-app.yaml` définit une "Application" ArgoCD
- ArgoCD va surveiller le repo Gitea et sync automatiquement
- La configuration inclut : repo URL, branche, namespace cible, sync policy

### Étape 11 : Vérifier le déploiement

```bash
# Vérifier l'application ArgoCD
kubectl get application -n argocd

# Vérifier les pods créés
kubectl get pods -l app=demo-nginx -w
```

**Explication** :
- L'application ArgoCD doit être "Synced" et "Healthy"
- Les pods doivent être "Running" avec "1/1 Ready"
- Le `-w` (watch) permet de voir les changements en temps réel

---

## Méthode Automatisée (Script)

### Script disponible

```bash
./scripts/deploy-gitops-app.sh <app-name> [namespace]
```

### Exemples d'utilisation

```bash
# Déployer demo-nginx dans le namespace default
./scripts/deploy-gitops-app.sh demo-nginx

# Déployer demo-security dans le namespace default
./scripts/deploy-gitops-app.sh demo-security

# Déployer une app dans un namespace spécifique
./scripts/deploy-gitops-app.sh my-app production
```

### Ce que fait le script

1. ✅ Vérifie que le dossier de l'app existe
2. ✅ Vérifie que le fichier ArgoCD Application existe
3. ✅ Initialise le repo Git local
4. ✅ Configure l'identité Git
5. ✅ Crée le commit initial
6. ✅ Pousse vers Gitea
7. ✅ Crée l'application ArgoCD
8. ✅ Affiche le status et les prochaines étapes

### Prérequis pour le script

1. **Créer l'organisation dans Gitea** (une seule fois) :
   - Aller sur https://gitea.local.lab:8443
   - Se connecter avec gitea-admin / gitea123!
   - Créer l'organisation "demo"

2. **Créer le repository dans Gitea** :
   - Dans l'organisation "demo"
   - Nom du repo = nom de l'application
   - Ne PAS initialiser avec README

---

## Test du Pipeline GitOps

Une fois l'application déployée, testez le pipeline GitOps :

### 1. Modifier le code

```bash
cd ~/work/enterprise-security-k8s/gitops-apps/demo-nginx

# Exemple : changer le nombre de replicas de 2 à 5
sed -i 's/replicas: 2/replicas: 5/' deployment.yaml

# Vérifier la modification
grep "replicas:" deployment.yaml
```

### 2. Commit et push

```bash
# Ajouter les modifications
git add deployment.yaml

# Créer un commit
git commit -m "Scale to 5 replicas"

# Pousser vers Gitea
git push
```

### 3. Observer la synchronisation

```bash
# Dans ArgoCD UI
# https://argocd.local.lab:8443
# Voir le status passer de "OutOfSync" à "Syncing" à "Synced"

# Ou via kubectl
kubectl get pods -l app=demo-nginx -w
# Vous verrez 3 nouveaux pods se créer (de 2 à 5)
```

### 4. Forcer une synchronisation (optionnel)

```bash
# Si vous ne voulez pas attendre le polling automatique (~3 min)
kubectl patch application demo-nginx -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
```

---

## Référence des Commandes

### Commandes Git

| Commande | Description |
|----------|-------------|
| `git init` | Initialise un nouveau repo Git |
| `git add .` | Ajoute tous les fichiers au staging |
| `git add <file>` | Ajoute un fichier spécifique |
| `git commit -m "msg"` | Crée un commit avec un message |
| `git branch -m <name>` | Renomme la branche actuelle |
| `git remote add origin <url>` | Ajoute un remote |
| `git push -u origin main` | Pousse et lie la branche |
| `git push` | Pousse les commits (après -u) |
| `git status` | Affiche l'état du repo |
| `git log` | Affiche l'historique des commits |
| `git diff` | Affiche les modifications |

### Commandes Git Config

| Commande | Description |
|----------|-------------|
| `git config user.name "xxx"` | Configure le nom (local) |
| `git config user.email "xxx"` | Configure l'email (local) |
| `git config --global user.name "xxx"` | Configure le nom (global) |
| `git config http.sslVerify false` | Désactive SSL verify |

### Commandes Kubernetes/ArgoCD

| Commande | Description |
|----------|-------------|
| `kubectl apply -f <file>` | Applique un manifest |
| `kubectl get application -n argocd` | Liste les apps ArgoCD |
| `kubectl get pods -l app=<name>` | Liste les pods d'une app |
| `kubectl get pods -w` | Watch les pods |
| `kubectl describe pod <name>` | Détails d'un pod |
| `kubectl logs <pod>` | Logs d'un pod |

### URLs importantes

| Service | URL | Credentials |
|---------|-----|-------------|
| Gitea | https://gitea.local.lab:8443 | gitea-admin / gitea123! |
| ArgoCD | https://argocd.local.lab:8443 | admin / [voir deploy-argocd.sh] |
| Grafana | https://grafana.local.lab:8443 | admin / prom-operator |
| Kibana | https://kibana.local.lab:8443 | - |

---

## Dépannage

### Erreur "Repository not found"

**Cause** : Le repo n'existe pas dans Gitea

**Solution** :
1. Allez sur Gitea (https://gitea.local.lab:8443)
2. Créez le repo dans l'organisation "demo"
3. Nom du repo = nom de l'application

### Erreur "SSL certificate problem"

**Cause** : Certificat auto-signé non accepté

**Solution** :
```bash
git config http.sslVerify false
```

### Erreur "Authentication failed"

**Cause** : Mauvais credentials

**Solution** :
- Username: `gitea-admin`
- Password: `gitea123!`

### Application ArgoCD "OutOfSync"

**Cause** : ArgoCD n'a pas encore sync (polling toutes les 3 min)

**Solution** : Forcer le sync
```bash
kubectl patch application demo-nginx -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
```

### Pods pas créés

**Cause** : ArgoCD n'a pas encore sync

**Solution** :
1. Vérifier le status dans ArgoCD UI
2. Attendre le sync ou le forcer
3. Vérifier les logs ArgoCD :
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
   ```

---

## Résumé

### Commandes à retenir (workflow manuel)

```bash
# 1. Se placer dans le dossier
cd gitops-apps/<app-name>

# 2. Initialiser et configurer Git
git init
git add .
git config user.name "gitea-admin"
git config user.email "admin@gitea.local.lab"
git commit -m "Initial commit"
git branch -m main

# 3. Pousser vers Gitea
git config http.sslVerify false
git remote add origin https://gitea.local.lab:8443/demo/<app-name>.git
git push -u origin main

# 4. Déployer avec ArgoCD
kubectl apply -f gitops-apps/argocd-apps/<app-name>-app.yaml
```

### Script automatisé

```bash
./scripts/deploy-gitops-app.sh <app-name>
```

---

**Documentation créée le** : 2025-11-21
**Auteur** : Enterprise Security K8s Team
