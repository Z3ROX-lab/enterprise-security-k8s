# GitOps Applications

Ce répertoire contient les applications de démonstration pour le pipeline GitOps (ArgoCD + Gitea).

## Structure

```
gitops-apps/
├── demo-nginx/              # Application Nginx simple
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── ingress.yaml
│   └── README.md
│
├── demo-security/           # Application avec monitoring Falco
│   ├── deployment.yaml
│   ├── service.yaml
│   └── README.md
│
├── argocd-apps/            # Définitions ArgoCD Application
│   ├── demo-nginx-app.yaml
│   └── demo-security-app.yaml
│
└── README.md               # Ce fichier
```

## Applications Disponibles

### 1. demo-nginx

**Description**: Application Nginx avec configuration sécurisée

**Composants**:
- Deployment avec 2 replicas
- Service ClusterIP
- ConfigMap pour la configuration Nginx
- Ingress (optionnel)

**Security Features**:
- Non-root user
- Read-only root filesystem (sauf cache)
- Resource limits
- Health checks
- Security headers

**Utilisation**:
```bash
cd demo-nginx
git init
git add .
git commit -m "Initial commit"
git remote add origin https://gitea.local.lab:8443/demo/demo-nginx.git
git push -u origin main

kubectl apply -f ../argocd-apps/demo-nginx-app.yaml
```

**Test du Pipeline**:
```bash
# Changer replicas
sed -i 's/replicas: 2/replicas: 5/' deployment.yaml
git add deployment.yaml
git commit -m "Scale to 5 replicas"
git push

# Observer dans ArgoCD UI
```

### 2. demo-security

**Description**: Application pour démontrer la détection Falco

**Composants**:
- Deployment Alpine avec 1 replica
- Service headless
- Labels Falco monitoring

**Security Features**:
- Monitored par Falco
- Non-root user
- Read-only root filesystem
- Minimal resources

**Utilisation**:
```bash
cd demo-security
git init
git add .
git commit -m "Initial commit"
git remote add origin https://gitea.local.lab:8443/demo/demo-security.git
git push -u origin main

kubectl apply -f ../argocd-apps/demo-security-app.yaml
```

**Test des Alertes Falco**:
```bash
# Shell interactif (déclenche alerte)
kubectl exec -it deployment/demo-security -- sh

# Lecture fichier sensible (déclenche alerte)
kubectl exec deployment/demo-security -- cat /etc/shadow

# Voir les alertes
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=50

# Dans Kibana
# Index: falco-*
# Filtre: kubernetes.pod_name:demo-security*
```

## ArgoCD Applications

Le répertoire `argocd-apps/` contient les définitions des applications ArgoCD.

### Structure d'une Application ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-nginx
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/demo/demo-nginx.git
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Déployer une Application

```bash
kubectl apply -f argocd-apps/demo-nginx-app.yaml
```

### Vérifier le Status

```bash
kubectl get application -n argocd
kubectl describe application demo-nginx -n argocd
```

## Workflow GitOps

```
┌──────────────────────────────────────────────────────────┐
│                    GITOPS WORKFLOW                        │
└──────────────────────────────────────────────────────────┘

1. DÉVELOPPER
   cd gitops-apps/demo-nginx
   # Modifier deployment.yaml

2. COMMIT & PUSH
   git add .
   git commit -m "Update deployment"
   git push

3. ARGOCD DÉTECTE
   # ArgoCD poll le repo toutes les 3 minutes
   # Ou forcer: argocd app refresh demo-nginx

4. SYNC AUTOMATIQUE
   # Si syncPolicy.automated: true
   # ArgoCD applique les changements

5. DEPLOY KUBERNETES
   # Rolling update
   # Health checks
   # Self-healing si drift

6. MONITORING
   # Falco monitore le runtime
   # Prometheus collecte les métriques
   # ELK collecte les logs
```

## Créer Votre Propre Application

### Étape 1: Créer le Répertoire

```bash
mkdir gitops-apps/my-app
cd gitops-apps/my-app
```

### Étape 2: Ajouter les Manifests

```bash
# deployment.yaml
cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: your-image:tag
        ports:
        - containerPort: 8080
EOF

# service.yaml
cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
EOF
```

### Étape 3: Créer le Repo dans Gitea

1. Allez sur https://gitea.local.lab:8443
2. Organisation `demo` → New Repository
3. Nom: `my-app`
4. Créez le repo

### Étape 4: Pousser le Code

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://gitea.local.lab:8443/demo/my-app.git
git push -u origin main
```

### Étape 5: Créer l'Application ArgoCD

```bash
cat > ../argocd-apps/my-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/demo/my-app.git
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

kubectl apply -f ../argocd-apps/my-app.yaml
```

### Étape 6: Vérifier dans ArgoCD UI

https://argocd.local.lab:8443

## Bonnes Pratiques

### Structure des Manifests

```
app-name/
├── base/                  # Manifests de base
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
├── overlays/             # Environnements
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patch-replicas.yaml
│   └── prod/
│       ├── kustomization.yaml
│       └── patch-replicas.yaml
└── README.md
```

### Sécurité

1. **Container Security**:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     allowPrivilegeEscalation: false
     capabilities:
       drop: ["ALL"]
     readOnlyRootFilesystem: true
   ```

2. **Resource Limits**:
   ```yaml
   resources:
     requests:
       cpu: 100m
       memory: 128Mi
     limits:
       cpu: 500m
       memory: 512Mi
   ```

3. **Health Checks**:
   ```yaml
   livenessProbe:
     httpGet:
       path: /healthz
       port: 8080
     initialDelaySeconds: 10
     periodSeconds: 10
   readinessProbe:
     httpGet:
       path: /ready
       port: 8080
     initialDelaySeconds: 5
     periodSeconds: 5
   ```

### GitOps

1. **Commits Atomiques**: Un changement = un commit
2. **Messages Clairs**: Décrivez le "pourquoi", pas le "quoi"
3. **Branches Protégées**: Protégez main/master
4. **Pull Requests**: Review avant merge
5. **Tags/Releases**: Versionnez vos déploiements

## Monitoring et Observabilité

### Grafana

Dashboard pour chaque application:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

### Logs

Labels pour Filebeat:

```yaml
metadata:
  labels:
    app: my-app
    environment: demo
```

Recherche dans Kibana:
- Index: `filebeat-*`
- Filtre: `kubernetes.labels.app:my-app`

### Falco

Labels pour monitoring:

```yaml
metadata:
  labels:
    falco-monitoring: "enabled"
    security-demo: "true"
```

## Troubleshooting

### Application OutOfSync

```bash
# Voir les différences
argocd app diff demo-nginx

# Sync manuellement
argocd app sync demo-nginx

# Ou via kubectl
kubectl patch application demo-nginx -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

### Erreur de Déploiement

```bash
# Events Kubernetes
kubectl get events -n default --sort-by='.lastTimestamp'

# Logs ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Status détaillé
kubectl describe application demo-nginx -n argocd
```

### Repo Git Inaccessible

```bash
# Vérifier les credentials
kubectl get secret gitea-repo-creds -n argocd -o yaml

# Tester l'accès
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
apk add git
git clone http://gitea-http.gitea.svc.cluster.local:3000/demo/demo-nginx.git
```

## Documentation

- **Guide Complet**: `docs/ARGOCD-GITEA-PIPELINE.md`
- **Quickstart**: `GITOPS-QUICKSTART.md`
- **Troubleshooting**: `TROUBLESHOOTING.md`

## Support

Questions ? Consultez:
1. README de chaque application
2. Documentation ArgoCD: https://argo-cd.readthedocs.io/
3. Documentation Gitea: https://docs.gitea.io/

---

**Note**: Ces applications sont des exemples de démonstration. Adaptez-les à vos besoins en production.
