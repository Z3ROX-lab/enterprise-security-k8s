# Kubernetes Dashboard - Interface Web GUI

## 🎯 Objectif

Déployer le **Kubernetes Dashboard** officiel accessible via Ingress pour gérer le cluster via une interface graphique web.

---

## 🚀 Déploiement Rapide

### Étape 1 : Lancer le Script

```bash
./scripts/deploy-kubernetes-dashboard.sh
```

Le script va automatiquement :
1. ✅ Créer le namespace `kubernetes-dashboard`
2. ✅ Déployer le Dashboard officiel (v2.7.0)
3. ✅ Créer un ServiceAccount avec permissions admin
4. ✅ Générer un token d'authentification
5. ✅ Configurer l'Ingress pour l'accès externe
6. ✅ Afficher le token et les instructions

---

### Étape 2 : Configuration /etc/hosts

Récupérez l'IP MetalLB :

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$INGRESS_IP dashboard.local.lab" | sudo tee -a /etc/hosts
```

Exemple :
```
172.18.255.200 dashboard.local.lab
```

---

### Étape 3 : Accès au Dashboard

1. **Ouvrez votre navigateur** : `https://dashboard.local.lab:8443/`

2. **Acceptez le certificat auto-signé** (erreur SSL normale)

3. **Choisissez "Token"** comme méthode d'authentification

4. **Collez le token** affiché par le script (ou récupérez-le avec la commande ci-dessous)

5. **Cliquez "Sign In"**

---

## 🔐 Récupération du Token

### Méthode 1 : Via le fichier sauvegardé

```bash
cat /tmp/k8s-dashboard-token.txt
```

### Méthode 2 : Via kubectl

```bash
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

### Méthode 3 : Créer un nouveau token temporaire

```bash
kubectl create token admin-user -n kubernetes-dashboard --duration=24h
```

---

## 🌐 Architecture

```
Utilisateur
   ↓
/etc/hosts (dashboard.local.lab → MetalLB IP)
   ↓
MetalLB Load Balancer
   ↓
NGINX Ingress Controller
   ↓
Service: kubernetes-dashboard:443 (HTTPS)
   ↓
Pod: kubernetes-dashboard
   ↓
Kubernetes API Server (avec token auth)
```

---

## 📊 Fonctionnalités du Dashboard

### Vue d'Ensemble
- ✅ **Cluster** : Nodes, Namespaces, Persistent Volumes
- ✅ **Workloads** : Deployments, StatefulSets, DaemonSets, Pods
- ✅ **Services** : Services, Ingresses, Endpoints
- ✅ **Storage** : PVC, PV, StorageClasses
- ✅ **Config** : ConfigMaps, Secrets

### Actions Possibles
- 📝 Créer des ressources (YAML ou formulaire)
- 🔍 Voir les logs des pods
- 🖥️ Shell dans les pods (kubectl exec)
- ⚙️ Éditer les ressources (YAML)
- 🗑️ Supprimer des ressources
- 📊 Voir les métriques (CPU/RAM)
- 🔄 Scaler les déploiements

---

## 🔒 Sécurité

### Permissions du ServiceAccount

Le ServiceAccount `admin-user` créé a les permissions **cluster-admin** (accès complet).

**Pour limiter les permissions** (recommandé en production) :

```yaml
# Créer un rôle en lecture seule
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view  # Lecture seule
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
```

### Authentification

Le Dashboard utilise **Bearer Token** pour l'authentification :
- ✅ Chaque token est lié à un ServiceAccount
- ✅ Les permissions sont celles du ServiceAccount
- ✅ Token stocké dans un Secret Kubernetes
- ✅ Token peut expirer (configurable)

### HTTPS et Certificats

- ✅ Le Dashboard écoute uniquement sur HTTPS
- ✅ Certificat auto-signé par défaut
- ⚠️ Navigateur affichera un warning (normal)
- 🔒 Pour production : utiliser cert-manager + Let's Encrypt

---

## 🛠️ Configuration Avancée

### Utiliser cert-manager pour TLS

```bash
# Créer un Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dashboard-tls
  namespace: kubernetes-dashboard
spec:
  secretName: dashboard-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - dashboard.local.lab
EOF

# Mettre à jour l'Ingress pour utiliser le certificat
kubectl patch ingress kubernetes-dashboard-ingress -n kubernetes-dashboard --type=merge -p '
{
  "spec": {
    "tls": [{
      "hosts": ["dashboard.local.lab"],
      "secretName": "dashboard-tls-secret"
    }]
  }
}'
```

---

## 📋 Commandes Utiles

### Vérifier le Déploiement

```bash
# État des pods
kubectl get pods -n kubernetes-dashboard

# État du service
kubectl get svc -n kubernetes-dashboard

# État de l'Ingress
kubectl get ingress -n kubernetes-dashboard

# Logs du dashboard
kubectl logs -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard
```

### Redémarrer le Dashboard

```bash
kubectl rollout restart deployment/kubernetes-dashboard -n kubernetes-dashboard
```

### Désinstaller le Dashboard

```bash
# Supprimer le Dashboard
kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Supprimer le ServiceAccount et Ingress
kubectl delete clusterrolebinding admin-user
kubectl delete namespace kubernetes-dashboard
```

---

## 🧪 Test du Dashboard

### Vérifications

1. **Test d'accès** :
```bash
curl -k https://dashboard.local.lab:8443/
# Devrait retourner du HTML
```

2. **Vérifier les endpoints** :
```bash
kubectl get endpoints -n kubernetes-dashboard kubernetes-dashboard
# Devrait afficher l'IP du pod
```

3. **Vérifier le token** :
```bash
TOKEN=$(kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
echo $TOKEN | wc -c
# Devrait retourner un nombre > 500 (token valide)
```

---

## 🔍 Troubleshooting

### Problème 1 : 404 Not Found

**Symptôme** : `https://dashboard.local.lab:8443/` retourne 404

**Solution** :
```bash
# Vérifier que l'Ingress existe
kubectl get ingress -n kubernetes-dashboard

# Vérifier les endpoints
kubectl get endpoints -n kubernetes-dashboard kubernetes-dashboard

# Si endpoints vides, redémarrer le pod
kubectl delete pod -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard
```

---

### Problème 2 : Certificat Invalide

**Symptôme** : Navigateur bloque l'accès (ERR_CERT_INVALID)

**Solution** :
- C'est normal avec un certificat auto-signé
- Cliquez sur "Advanced" → "Proceed to dashboard.local.lab (unsafe)"
- OU utilisez cert-manager pour un vrai certificat

---

### Problème 3 : Token Refusé

**Symptôme** : "Invalid token" lors du login

**Solution** :
```bash
# Régénérer un nouveau token
kubectl delete secret admin-user-token -n kubernetes-dashboard

# Recréer le secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF

# Attendre 10 secondes
sleep 10

# Récupérer le nouveau token
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

---

### Problème 4 : Pas d'IP MetalLB

**Symptôme** : Ingress sans EXTERNAL-IP

**Solution** :
```bash
# Vérifier MetalLB
kubectl get pods -n metallb-system

# Vérifier l'Ingress Controller
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Si EXTERNAL-IP = <pending>, vérifier la config MetalLB
kubectl get ipaddresspool -n metallb-system
```

---

## 📊 Comparaison avec Alternatives

| Dashboard | Type | Avantage | Inconvénient |
|-----------|------|----------|--------------|
| **Kubernetes Dashboard** | Web | Officiel, simple | Fonctionnalités limitées |
| **Lens** | Desktop | Puissant, multi-cluster | Pas web-based |
| **K9s** | Terminal | Léger, rapide | Pas de GUI |
| **Headlamp** | Web | Moderne, extensible | Moins mature |
| **Rancher** | Web | Complet, multi-cluster | Lourd, complexe |

---

## 🎯 Cas d'Usage

### Développement
- ✅ Visualiser les pods et logs rapidement
- ✅ Débugger les déploiements
- ✅ Tester des configurations YAML

### Production (avec limitations)
- ⚠️ Lecture seule recommandée (role: view)
- ⚠️ Authentification forte requise
- ⚠️ Audit logging activé
- ⚠️ Accès via VPN uniquement

### Formation
- ✅ Apprendre Kubernetes visuellement
- ✅ Comprendre les relations entre ressources
- ✅ Voir l'impact des commandes kubectl

---

## 🔗 Ressources

- **Documentation officielle** : https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
- **GitHub** : https://github.com/kubernetes/dashboard
- **Releases** : https://github.com/kubernetes/dashboard/releases
- **Troubleshooting** : https://github.com/kubernetes/dashboard/wiki/Troubleshooting

---

## 📝 Notes

### Version Déployée
- **Dashboard** : v2.7.0
- **Kubernetes** : Compatible 1.21+
- **RBAC** : Activé (cluster-admin)

### Limites Connues
- ⚠️ Pas de multi-tenancy natif
- ⚠️ Pas de gestion GitOps
- ⚠️ Métriques limitées (utiliser Grafana pour plus)
- ⚠️ Pas de gestion Helm charts

### Prochaines Étapes
- [ ] Intégrer SSO Keycloak pour auth
- [ ] Activer les métriques (metrics-server)
- [ ] Configurer Let's Encrypt pour TLS
- [ ] Limiter les permissions (role: view)
- [ ] Ajouter audit logging

---

**✅ Avec ce Dashboard, vous avez maintenant une interface graphique complète pour gérer votre cluster Kubernetes !**
