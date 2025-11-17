# Pipeline GitOps avec ArgoCD et Gitea

Ce document décrit l'intégration complète d'un pipeline GitOps utilisant ArgoCD et Gitea dans le stack de sécurité entreprise.

## Architecture du Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    PIPELINE GITOPS COMPLET                   │
└─────────────────────────────────────────────────────────────┘

 Developer          Git Server         GitOps           Kubernetes
    │                   │                │                   │
    ├─1. Code──────────▶│                │                   │
    │                   │  Gitea         │                   │
    │                   │  (Repo)        │                   │
    │                   │                │                   │
    │                   ├─2. Webhook────▶│                   │
    │                   │                │  ArgoCD           │
    │                   │                │  (Sync)           │
    │                   │                │                   │
    │                   │                ├─3. Deploy────────▶│
    │                   │                │                   │  Cluster
    │                   │                │                   │
    │                   │                │                   ├─▶Falco
    │                   │                │                   │  (Security)
    │                   │                │                   │
    │                   │                │                   ├─▶Trivy
    │                   │                │                   │  (Scan)
    │                   │                │                   │
    │                   │                │                   ├─▶Prometheus
    │                   │                │                   │  (Metrics)
    │                   │                │                   │
    │                   │                │                   ├─▶ELK
    │                   │                │                   │  (Logs)
    │                   │                │                   │
    └───────────────────┴────────────────┴───────────────────┘

              ┌────────────────────────────────┐
              │   Observability & Security     │
              ├────────────────────────────────┤
              │  • Grafana  (Metrics)          │
              │  • Kibana   (Logs)             │
              │  • ArgoCD   (GitOps Status)    │
              │  • Falco    (Runtime Security) │
              └────────────────────────────────┘
```

## Composants

### 1. Gitea - Git Server Local

**Namespace**: `gitea`
**URL**: https://gitea.local.lab:8443
**Credentials**: gitea-admin / gitea123!

#### Fonctionnalités
- Repositories Git self-hosted
- Interface web pour gérer le code
- Webhooks vers ArgoCD
- Git HTTP/SSH access
- Organisation et équipes
- API REST complète

#### Services
- `gitea-http` → UI Web + Git HTTP (port 3000)
- `gitea-ssh` → Git SSH (port 22)
- `gitea-postgresql` → Base de données

### 2. ArgoCD - GitOps Controller

**Namespace**: `argocd`
**URL**: https://argocd.local.lab:8443
**Credentials**: admin / [voir output deploy-argocd.sh]

#### Fonctionnalités
- Synchronisation automatique depuis Git
- Interface web pour visualiser les déploiements
- Rollback automatique
- Health checks
- Sync policies configurables
- Multi-cluster support (future)

#### Services
- `argocd-server` → UI Web + API (port 443)
- `argocd-repo-server` → Clone des repos Git
- `argocd-application-controller` → Sync logic
- `argocd-redis` → Cache

## Installation

### Prérequis

```bash
# Vérifier que le cluster est démarré
kubectl cluster-info

# Vérifier que l'Ingress Controller est déployé
kubectl get pods -n ingress-nginx

# Vérifier MetalLB
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Étape 1: Déployer ArgoCD

```bash
cd /home/user/enterprise-security-k8s

# Déployer ArgoCD
./scripts/deploy-argocd.sh

# Vérifier le déploiement
kubectl get pods -n argocd
kubectl get svc -n argocd
```

**Output attendu**:
- argocd-server (1/1 Running)
- argocd-repo-server (1/1 Running)
- argocd-application-controller (1/1 Running)
- argocd-redis (1/1 Running)

**Mot de passe admin**: Le script affichera le mot de passe initial.

### Étape 2: Déployer Gitea

```bash
# Déployer Gitea
./scripts/deploy-gitea.sh

# Vérifier le déploiement
kubectl get pods -n gitea
kubectl get svc -n gitea
```

**Output attendu**:
- gitea (1/1 Running)
- gitea-postgresql (1/1 Running)

**Credentials**: gitea-admin / gitea123!

### Étape 3: Déployer les Ingress

```bash
# Déployer les Ingress resources
kubectl apply -f deploy/argocd-gitea-ingress.yaml

# Vérifier
kubectl get ingress -n argocd
kubectl get ingress -n gitea
```

### Étape 4: Configurer le Port-Forward

```bash
# Démarrer le port-forward (en arrière-plan avec screen)
./scripts/start-ingress-portforward.sh

# Vérifier le status
./scripts/status-ingress-portforward.sh
```

### Étape 5: Configurer /etc/hosts sur Windows

**Fichier**: `C:\Windows\System32\drivers\etc\hosts`

Ajouter ces lignes:

```
# NGINX METAL LB
127.0.0.1 grafana.local.lab
127.0.0.1 kibana.local.lab
127.0.0.1 prometheus.local.lab
127.0.0.1 falco-ui.local.lab
127.0.0.1 keycloak.local.lab
127.0.0.1 vault.local.lab
127.0.0.1 dashboard.local.lab
127.0.0.1 minio.local.lab
127.0.0.1 argocd.local.lab
127.0.0.1 gitea.local.lab
```

### Étape 6: Configurer l'intégration ArgoCD ↔ Gitea

```bash
# Configurer l'intégration
./scripts/configure-argocd-gitea.sh
```

Ce script:
- Crée les credentials Gitea dans ArgoCD
- Configure ArgoCD pour pointer vers Gitea
- Redémarre les services ArgoCD

## Accès aux Interfaces Web

### ArgoCD
```
URL:      https://argocd.local.lab:8443
Username: admin
Password: [voir output de deploy-argocd.sh]
```

### Gitea
```
URL:      https://gitea.local.lab:8443
Username: gitea-admin
Password: gitea123!
```

## Applications de Démonstration

Deux applications de démo sont fournies dans `/gitops-apps/`:

### 1. demo-nginx

Application Nginx simple pour démontrer le pipeline GitOps.

**Localisation**: `gitops-apps/demo-nginx/`

**Composants**:
- `deployment.yaml` - Déploiement Nginx avec sécurité renforcée
- `service.yaml` - Service ClusterIP
- `configmap.yaml` - Configuration Nginx
- `ingress.yaml` - Exposition via Ingress

**ArgoCD App**: `gitops-apps/argocd-apps/demo-nginx-app.yaml`

### 2. demo-security

Application pour démontrer la détection Falco.

**Localisation**: `gitops-apps/demo-security/`

**Composants**:
- `deployment.yaml` - Pod Alpine avec monitoring Falco
- `service.yaml` - Service headless

**ArgoCD App**: `gitops-apps/argocd-apps/demo-security-app.yaml`

## Scénario de Démonstration Complet

### Préparation

1. **Créer l'organisation dans Gitea**

   - Allez sur https://gitea.local.lab:8443
   - Connectez-vous avec gitea-admin / gitea123!
   - Cliquez sur "+" → "New Organization"
   - Nom: `demo`
   - Créez l'organisation

2. **Créer les repositories**

   Pour chaque application:
   - Dans l'organisation `demo`, créez un nouveau repo
   - Nom: `demo-nginx` (puis `demo-security`)
   - Visibilité: Public
   - Initialisez sans README

### Déploiement demo-nginx

#### Étape 1: Pousser le code vers Gitea

```bash
cd gitops-apps/demo-nginx

# Initialiser le repo Git
git init
git add .
git commit -m "Initial commit: Demo nginx application"

# Configurer le remote (remplacez avec votre URL Gitea)
git remote add origin https://gitea.local.lab:8443/demo/demo-nginx.git

# Pousser vers Gitea
git push -u origin main
```

**Note**: Si vous avez des erreurs SSL, utilisez:
```bash
git config --global http.sslVerify false
```

#### Étape 2: Déployer avec ArgoCD

```bash
# Créer l'application ArgoCD
kubectl apply -f gitops-apps/argocd-apps/demo-nginx-app.yaml

# Vérifier le status
kubectl get application -n argocd
argocd app list  # Si CLI installée
```

#### Étape 3: Visualiser dans ArgoCD UI

1. Allez sur https://argocd.local.lab:8443
2. Connectez-vous
3. Vous verrez l'application `demo-nginx`
4. Cliquez dessus pour voir le graphe de ressources
5. Status devrait être "Synced" et "Healthy"

#### Étape 4: Tester le Pipeline GitOps

**Scaler l'application**:

```bash
cd gitops-apps/demo-nginx

# Modifier le nombre de replicas
sed -i 's/replicas: 2/replicas: 5/' deployment.yaml

# Commit et push
git add deployment.yaml
git commit -m "Scale to 5 replicas"
git push

# Observer dans ArgoCD (auto-sync après 3 minutes max)
# Ou forcer le sync:
kubectl patch application demo-nginx -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
```

**Observer les effets**:

1. **ArgoCD UI**: Voir les nouvelles pods apparaître
2. **Kubernetes**:
   ```bash
   kubectl get pods -l app=demo-nginx -w
   ```
3. **Grafana**: https://grafana.local.lab:8443
   - Dashboard "Kubernetes / Compute Resources / Namespace (Pods)"
   - Namespace: default
   - Voir les nouvelles pods et leur consommation
4. **Kibana**: https://kibana.local.lab:8443
   - Index: filebeat-*
   - Filtre: kubernetes.pod.name:demo-nginx*
   - Voir les logs des nouvelles pods

### Déploiement demo-security

#### Étape 1: Pousser vers Gitea

```bash
cd gitops-apps/demo-security

git init
git add .
git commit -m "Initial commit: Demo security app with Falco monitoring"

git remote add origin https://gitea.local.lab:8443/demo/demo-security.git
git push -u origin main
```

#### Étape 2: Déployer avec ArgoCD

```bash
kubectl apply -f gitops-apps/argocd-apps/demo-security-app.yaml
```

#### Étape 3: Déclencher des Alertes Falco

**Test 1: Shell Interactif**

```bash
# Exécuter un shell dans le pod
kubectl exec -it deployment/demo-security -- sh

# Dans le shell:
ls -la /
cat /etc/passwd
exit
```

**Test 2: Lecture de Fichier Sensible**

```bash
kubectl exec deployment/demo-security -- cat /etc/shadow
# Falco alerte: "Read sensitive file untrusted"
```

**Test 3: Installation de Package**

```bash
kubectl exec deployment/demo-security -- apk add curl
# Falco alerte: "Package management process launched"
```

#### Étape 4: Visualiser les Alertes

**Logs Falco directs**:
```bash
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=50
```

**Kibana**:
1. Allez sur https://kibana.local.lab:8443
2. Index Pattern: `falco-*`
3. Créez un filtre:
   ```
   kubernetes.namespace_name:"default" AND
   kubernetes.pod_name:"demo-security*"
   ```
4. Vous verrez toutes les alertes Falco

**Grafana**:
1. Allez sur https://grafana.local.lab:8443
2. Dashboard: "Falco Dashboard" (si configuré)
3. Vous verrez:
   - Nombre d'alertes par sévérité
   - Timeline des événements
   - Top pods avec alertes

## Workflow GitOps Complet

```
┌─────────────────────────────────────────────────────────────┐
│                    WORKFLOW GITOPS                           │
└─────────────────────────────────────────────────────────────┘

1. DEVELOP
   └─▶ Modifier le code (deployment.yaml, etc.)

2. COMMIT & PUSH
   └─▶ git add . && git commit -m "message" && git push
       └─▶ Code pushed to Gitea

3. ARGOCD DETECT (auto - 3 min max)
   └─▶ ArgoCD poll le repo Git
       └─▶ Détecte les changements
           └─▶ Compare avec l'état du cluster

4. ARGOCD SYNC (auto si configuré)
   └─▶ Pull manifests depuis Git
       └─▶ Apply sur Kubernetes
           └─▶ Vérifie health

5. KUBERNETES DEPLOY
   └─▶ Création/Update des ressources
       └─▶ Rolling update si Deployment
           └─▶ Pods créés/mis à jour

6. SECURITY SCAN (automatique)
   ├─▶ Trivy scan l'image
   ├─▶ OPA Gatekeeper vérifie les policies
   ├─▶ Falco monitore le runtime
   └─▶ Alertes si problème

7. MONITORING (continu)
   ├─▶ Prometheus collecte les métriques
   ├─▶ Filebeat collecte les logs
   ├─▶ Grafana visualise les métriques
   └─▶ Kibana visualise les logs

8. ALERTING (si problème)
   ├─▶ Alertmanager (Prometheus)
   ├─▶ Falco (Security events)
   └─▶ ArgoCD (Sync failed)
```

## Rollback

### Via ArgoCD UI

1. Allez dans l'application
2. Cliquez sur "History and Rollback"
3. Sélectionnez la version précédente
4. Cliquez sur "Rollback"

### Via ArgoCD CLI

```bash
# Lister l'historique
argocd app history demo-nginx

# Rollback à une révision spécifique
argocd app rollback demo-nginx <revision-id>
```

### Via Git

```bash
# Revenir à un commit précédent
git revert HEAD
git push

# ArgoCD va automatiquement sync
```

## Troubleshooting

### ArgoCD ne détecte pas les changements

**Cause**: Polling interval trop long

**Solution**:
```bash
# Forcer un refresh
argocd app get demo-nginx --refresh

# Ou patcher le polling interval
kubectl patch configmap argocd-cm -n argocd \
  --type merge \
  -p '{"data":{"timeout.reconciliation":"30s"}}'
```

### Erreur d'authentification Gitea

**Cause**: Credentials incorrects

**Solution**:
```bash
# Vérifier le secret
kubectl get secret gitea-repo-creds -n argocd -o yaml

# Recréer le secret
kubectl delete secret gitea-repo-creds -n argocd
./scripts/configure-argocd-gitea.sh
```

### Application en état "OutOfSync"

**Cause**: Changements manuels dans le cluster

**Solution**:
```bash
# Auto-heal (si enabled)
# Ou sync manuellement
argocd app sync demo-nginx

# Ou via kubectl
kubectl patch application demo-nginx -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
```

### Pods ne démarrent pas

**Vérifications**:

```bash
# Events
kubectl get events --sort-by='.lastTimestamp' -n default

# Describe pod
kubectl describe pod <pod-name>

# Logs
kubectl logs <pod-name>

# ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## Commandes Utiles

### ArgoCD CLI

```bash
# Installation (Linux)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login
argocd login argocd.local.lab:8443 \
  --username admin \
  --password <password> \
  --insecure

# Lister les apps
argocd app list

# Détails d'une app
argocd app get demo-nginx

# Sync
argocd app sync demo-nginx

# Logs
argocd app logs demo-nginx

# Diff
argocd app diff demo-nginx
```

### Gitea CLI

```bash
# Cloner un repo
git clone https://gitea.local.lab:8443/demo/demo-nginx.git

# Configuration globale
git config --global user.name "Demo User"
git config --global user.email "demo@gitea.local.lab"
git config --global http.sslVerify false  # Pour les certs auto-signés
```

### Kubernetes

```bash
# Lister les applications ArgoCD
kubectl get applications -n argocd

# Voir les events ArgoCD
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Logs des composants
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# Voir les ressources gérées par ArgoCD
kubectl get all -l app.kubernetes.io/instance=demo-nginx
```

## Sécurité

### Bonnes Pratiques

1. **Credentials**:
   - Changez les mots de passe par défaut
   - Utilisez des secrets Kubernetes pour les credentials
   - Activez 2FA dans Gitea (production)

2. **RBAC**:
   - Créez des utilisateurs avec des permissions limitées
   - Utilisez des ServiceAccounts dédiés pour ArgoCD
   - Appliquez le principe du moindre privilège

3. **Network Policies**:
   - Restreignez l'accès entre namespaces
   - Permettez seulement ArgoCD → Gitea
   - Bloquez l'accès externe sauf via Ingress

4. **Image Security**:
   - Utilisez des images versionnées (pas :latest)
   - Scannez avec Trivy avant le déploiement
   - Signez les images avec Cosign (future)

5. **Git Security**:
   - Protégez la branche main
   - Nécessitez des pull requests
   - Activez la signature des commits (GPG)

### Network Policies pour GitOps

```yaml
# Exemple: Permettre ArgoCD → Gitea
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-to-gitea
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-repo-server
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: gitea
    ports:
    - protocol: TCP
      port: 3000
```

## Intégration avec le Stack de Sécurité

Le pipeline GitOps s'intègre avec tous les composants de sécurité:

### Falco
- Détecte les comportements suspects des applications déployées
- Alertes en temps réel vers ELK et Prometheus
- Règles personnalisées pour les apps sensibles

### Trivy
- Scan des images au déploiement
- Rapports de vulnérabilités dans ArgoCD
- Bloque les images critiques (future)

### OPA Gatekeeper
- Valide les manifests avant le déploiement
- Enforce les policies (resources limits, etc.)
- Bloque les déploiements non-conformes

### Vault
- Injection de secrets dans les pods
- Rotation automatique des credentials
- Intégration avec ArgoCD (future)

### ELK Stack
- Logs centralisés de toutes les apps
- Corrélation avec les événements Git
- Dashboards pour chaque application

### Prometheus + Grafana
- Métriques de toutes les apps déployées
- Alerting sur les anomalies
- Dashboard GitOps avec stats ArgoCD

## Métriques et Dashboards

### Métriques ArgoCD

ArgoCD expose des métriques Prometheus:

```yaml
# ServiceMonitor déjà configuré
kubectl get servicemonitor -n argocd
```

**Métriques utiles**:
- `argocd_app_info` - Info sur les applications
- `argocd_app_sync_total` - Nombre de syncs
- `argocd_app_sync_status` - Status de sync
- `argocd_app_health_status` - Health status

### Dashboard Grafana GitOps

Créez un dashboard avec ces panels:

1. **Applications Overview**
   - Nombre total d'apps
   - Apps Synced vs OutOfSync
   - Apps Healthy vs Degraded

2. **Sync Activity**
   - Syncs dans les dernières 24h
   - Sync duration (p50, p95, p99)
   - Failed syncs

3. **Git Activity**
   - Commits dans les dernières 24h
   - Repos monitored
   - Polling errors

4. **Deployment Impact**
   - Pods created/updated
   - CPU/Memory usage before/after
   - Restart count

## Ressources Additionnelles

### Documentation Officielle

- **ArgoCD**: https://argo-cd.readthedocs.io/
- **Gitea**: https://docs.gitea.io/

### Liens Utiles

- ArgoCD Best Practices: https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/
- GitOps Principles: https://opengitops.dev/
- Falco Rules: https://falco.org/docs/rules/

### Scripts

- `scripts/deploy-argocd.sh` - Déploiement ArgoCD
- `scripts/deploy-gitea.sh` - Déploiement Gitea
- `scripts/configure-argocd-gitea.sh` - Configuration intégration
- `scripts/start-ingress-portforward.sh` - Port-forward Ingress
- `scripts/stop-ingress-portforward.sh` - Arrêter port-forward

## Conclusion

Ce pipeline GitOps complet démontre:

✅ **GitOps Workflow** - Code → Git → Deploy automatique
✅ **Security-First** - Intégration avec Falco, Trivy, OPA
✅ **Observability** - Monitoring complet (Grafana, Kibana)
✅ **Self-Hosted** - Tous les composants locaux (Gitea, ArgoCD)
✅ **Production-Ready** - RBAC, Network Policies, Health Checks
✅ **Démontrable** - 2 applications de démo prêtes à l'emploi

Vous avez maintenant un **pipeline GitOps d'entreprise complet** intégré dans votre stack de cybersécurité Kubernetes ! 🚀
