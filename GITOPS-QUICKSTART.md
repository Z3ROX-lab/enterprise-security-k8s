# Guide Rapide - Pipeline GitOps (ArgoCD + Gitea)

Guide de démarrage rapide pour déployer et tester le pipeline GitOps en 15 minutes.

## Prérequis

- Cluster Kubernetes démarré (Kind ou autre)
- Ingress Controller déployé
- Accès kubectl fonctionnel

## Installation Rapide (5 minutes)

### 1. Déployer ArgoCD

```bash
./scripts/deploy-argocd.sh
```

**Output important**: Notez le mot de passe admin affiché à la fin.

### 2. Déployer Gitea

```bash
./scripts/deploy-gitea.sh
```

### 3. Déployer les Ingress

```bash
kubectl apply -f deploy/argocd-gitea-ingress.yaml
```

### 4. Configurer le Port-Forward

```bash
./scripts/start-ingress-portforward.sh
```

### 5. Configurer /etc/hosts sur Windows

**Fichier**: `C:\Windows\System32\drivers\etc\hosts`

Ajouter:
```
127.0.0.1 argocd.local.lab
127.0.0.1 gitea.local.lab
```

### 6. Configurer l'intégration

```bash
./scripts/configure-argocd-gitea.sh
```

## Test Rapide (10 minutes)

### Étape 1: Accéder à Gitea

1. Ouvrez https://gitea.local.lab:8443
2. Connectez-vous: `gitea-admin` / `gitea123!`
3. Créez une organisation: **demo**
4. Dans l'organisation, créez un repo: **demo-nginx**

### Étape 2: Pousser l'application

```bash
cd gitops-apps/demo-nginx

# Init Git
git init
git add .
git commit -m "Initial commit"

# Configure pour ignorer SSL (dev only)
git config --global http.sslVerify false

# Push vers Gitea
git remote add origin https://gitea.local.lab:8443/demo/demo-nginx.git
git push -u origin main
```

**Credentials** (si demandés): gitea-admin / gitea123!

### Étape 3: Déployer avec ArgoCD

```bash
# Créer l'application ArgoCD
kubectl apply -f gitops-apps/argocd-apps/demo-nginx-app.yaml

# Vérifier
kubectl get application -n argocd
```

### Étape 4: Visualiser

1. **ArgoCD UI**: https://argocd.local.lab:8443
   - User: `admin`
   - Password: [celui du deploy-argocd.sh]
   - Vous verrez l'application `demo-nginx` en cours de sync

2. **Vérifier les pods**:
   ```bash
   kubectl get pods -l app=demo-nginx
   ```

### Étape 5: Tester le Pipeline GitOps

Modifiez le nombre de replicas:

```bash
cd gitops-apps/demo-nginx

# Changer replicas de 2 à 5
sed -i 's/replicas: 2/replicas: 5/' deployment.yaml

# Commit et push
git add deployment.yaml
git commit -m "Scale to 5 replicas"
git push

# Observer dans ArgoCD UI (rafraîchir)
# Après ~1-2 minutes, vous verrez 5 pods
kubectl get pods -l app=demo-nginx -w
```

## Scénario de Démo Complet

### Démontrer le Pipeline

```
1. MODIFIER LE CODE
   └─▶ Changez deployment.yaml dans Gitea UI ou localement

2. COMMIT & PUSH
   └─▶ Git push vers Gitea

3. ARGOCD DÉTECTE
   └─▶ Dans ArgoCD UI, voir "OutOfSync" puis "Syncing"

4. DEPLOY AUTOMATIQUE
   └─▶ Nouvelles pods apparaissent dans Kubernetes

5. MONITORING
   ├─▶ Grafana: https://grafana.local.lab:8443
   │   └─▶ Dashboard "Kubernetes / Compute Resources"
   ├─▶ Kibana: https://kibana.local.lab:8443
   │   └─▶ Index filebeat-*, filtrer par app=demo-nginx
   └─▶ Falco détecte les événements de création de pods
```

### Scénarios Intéressants

#### 1. Scaler l'Application
```bash
# Via Gitea UI:
# - Éditer deployment.yaml
# - Changer replicas
# - Commit

# Observer:
# - ArgoCD sync automatiquement
# - Pods créés dans k8s
# - Métriques dans Grafana
```

#### 2. Changer l'Image
```bash
# deployment.yaml
image: nginx:1.27-alpine → nginx:1.26-alpine

# Observer:
# - Rolling update dans k8s
# - Trivy scan la nouvelle image
# - Logs dans Kibana
```

#### 3. Rollback
```bash
# Via ArgoCD UI:
# - Cliquer sur l'app
# - "History and Rollback"
# - Sélectionner version précédente
# - Rollback

# Ou via Git:
git revert HEAD
git push
```

## Applications de Démo Disponibles

### 1. demo-nginx
Application Nginx simple pour démontrer le pipeline de base.

**Features**:
- Deployment sécurisé (non-root, read-only filesystem)
- Service ClusterIP
- Ingress
- Health checks

**Dossier**: `gitops-apps/demo-nginx/`

### 2. demo-security
Application pour démontrer la détection Falco.

**Features**:
- Pod Alpine minimal
- Monitored par Falco
- Déclenche des alertes de sécurité

**Dossier**: `gitops-apps/demo-security/`

**Tests**:
```bash
# Après déploiement, déclencher des alertes:
kubectl exec -it deployment/demo-security -- sh
kubectl exec deployment/demo-security -- cat /etc/shadow

# Voir les alertes dans Kibana
```

## URLs d'Accès

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | https://argocd.local.lab:8443 | admin / [output deploy] |
| Gitea | https://gitea.local.lab:8443 | gitea-admin / gitea123! |
| Grafana | https://grafana.local.lab:8443 | admin / prom-operator |
| Kibana | https://kibana.local.lab:8443 | - |
| Keycloak | https://keycloak.local.lab:8443 | admin / admin123 |
| Vault | https://vault.local.lab:8443 | - |

## Troubleshooting Rapide

### ArgoCD ne sync pas

```bash
# Forcer un refresh
kubectl patch application demo-nginx -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

### Erreur Git push

```bash
# Désactiver SSL verify (dev only)
git config --global http.sslVerify false

# Ou configurer les credentials
git config --global credential.helper store
```

### Port-forward ne fonctionne pas

```bash
# Redémarrer
./scripts/stop-ingress-portforward.sh
./scripts/start-ingress-portforward.sh

# Vérifier
curl -k https://localhost:8443
```

### Pods ne démarrent pas

```bash
# Vérifier les events
kubectl get events --sort-by='.lastTimestamp' -n default

# Décrire le pod
kubectl describe pod <pod-name>

# Logs ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## Commandes Utiles

```bash
# Status général
kubectl get all -n argocd
kubectl get all -n gitea
kubectl get applications -n argocd

# Logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
kubectl logs -n gitea -l app.kubernetes.io/name=gitea -f

# Port-forward direct (backup)
kubectl port-forward -n argocd svc/argocd-server 8080:443
kubectl port-forward -n gitea svc/gitea-http 3000:3000

# Cleanup
kubectl delete application demo-nginx -n argocd
kubectl delete namespace argocd gitea
```

## Prochaines Étapes

### Documentation Complète
Consultez `docs/ARGOCD-GITEA-PIPELINE.md` pour:
- Architecture détaillée
- Configuration avancée
- Sécurité et bonnes pratiques
- Intégration avec le stack de sécurité
- Métriques et monitoring

### Personnalisation
- Créez vos propres applications GitOps
- Configurez des webhooks Gitea → ArgoCD
- Intégrez avec Vault pour les secrets
- Ajoutez des tests automatisés (CI/CD)

### Démo Complète
Suivez le workflow complet dans `docs/ARGOCD-GITEA-PIPELINE.md` section "Scénario de Démonstration Complet"

## Support

En cas de problème:
1. Vérifiez les logs des composants
2. Consultez `TROUBLESHOOTING.md`
3. Lisez `docs/ARGOCD-GITEA-PIPELINE.md`
4. Créez une issue sur GitHub

---

**Temps total**: ~15 minutes
**Niveau**: Débutant
**Prérequis**: Cluster K8s + Ingress Controller

Profitez de votre pipeline GitOps ! 🚀
