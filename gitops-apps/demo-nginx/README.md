# Demo Nginx - GitOps Application

Cette application démontre le pipeline GitOps complet avec ArgoCD et Gitea.

## Description

Application Nginx simple qui peut être déployée et mise à jour via GitOps.

## Architecture

```
┌────────────┐    ┌──────────┐    ┌─────────────┐
│   Gitea    │───▶│  ArgoCD  │───▶│ Kubernetes  │
│ (Git Repo) │    │ (Sync)   │    │  (Deploy)   │
└────────────┘    └──────────┘    └─────────────┘
```

## Utilisation

### 1. Initialiser le repo Git

```bash
cd gitops-apps/demo-nginx
git init
git add .
git commit -m "Initial commit: Demo nginx app"
```

### 2. Pousser vers Gitea

```bash
# Créer le repo dans Gitea d'abord (via l'UI web)
# Organisation: demo
# Repository: demo-nginx

git remote add origin https://gitea.local.lab:8443/demo/demo-nginx.git
git push -u origin main
```

### 3. Déployer avec ArgoCD

```bash
kubectl apply -f ../argocd-apps/demo-nginx-app.yaml
```

### 4. Visualiser dans ArgoCD

Allez sur https://argocd.local.lab:8443 et connectez-vous.

## Scénario de Démo

### Scaler l'application

1. Modifiez `replicas: 2` à `replicas: 5` dans `deployment.yaml`
2. Commit et push:
   ```bash
   git add deployment.yaml
   git commit -m "Scale to 5 replicas"
   git push
   ```
3. ArgoCD détecte le changement automatiquement
4. Observez dans Grafana les nouvelles pods qui apparaissent
5. Falco enregistre les événements de création de pods

### Changer l'image

1. Modifiez `image:` dans `deployment.yaml`
2. Commit et push
3. ArgoCD sync automatiquement
4. Trivy scanne la nouvelle image
5. Les logs sont envoyés vers Elasticsearch/Kibana

### Rollback en cas de problème

```bash
# Via ArgoCD UI: cliquez sur "History & Rollback"
# Ou via CLI:
argocd app rollback demo-nginx
```

## Composants

- `deployment.yaml` - Déploiement Nginx
- `service.yaml` - Service ClusterIP
- `ingress.yaml` - Exposition via Ingress (optionnel)
- `README.md` - Cette documentation

## Monitoring

### Grafana
Visualisez les métriques de l'application dans Grafana:
- https://grafana.local.lab:8443

### Kibana
Consultez les logs dans Kibana:
- https://kibana.local.lab:8443

### ArgoCD
Status de synchronisation:
- https://argocd.local.lab:8443
