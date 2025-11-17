# Kubernetes Dashboard - Notes de Déploiement

**Date** : 15 Novembre 2025
**Status** : ✅ Déployé et Opérationnel

---

## 🎯 Objectif

Déployer le Kubernetes Dashboard officiel pour avoir une interface graphique web de gestion du cluster, accessible via Ingress (https://dashboard.local.lab:8443/).

---

## 📦 Ce Qui a Été Fait

### 1. Déploiement du Dashboard

**Script utilisé** : `./scripts/deploy-kubernetes-dashboard.sh`

**Composants installés** :
- ✅ Namespace : `kubernetes-dashboard`
- ✅ Kubernetes Dashboard v2.7.0 (officiel)
- ✅ Dashboard Metrics Scraper (pour les métriques)
- ✅ ServiceAccount `admin-user` (permissions cluster-admin)
- ✅ Secret `admin-user-token` (token d'authentification)
- ✅ Ingress pour accès externe

**Commande de déploiement** :
```bash
./scripts/deploy-kubernetes-dashboard.sh
```

---

### 2. Configuration Ingress

**Ingress créé** :
- **Nom** : `kubernetes-dashboard-ingress`
- **Namespace** : `kubernetes-dashboard`
- **Host** : `dashboard.local.lab`
- **Backend** : `kubernetes-dashboard:443` (HTTPS)
- **Annotations** :
  - `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"`
  - `nginx.ingress.kubernetes.io/ssl-passthrough: "true"`

**Vérification** :
```bash
kubectl get ingress -n kubernetes-dashboard

# Résultat :
NAME                           CLASS   HOSTS                 ADDRESS          PORTS
kubernetes-dashboard-ingress   nginx   dashboard.local.lab   172.19.255.200   80
```

---

### 3. Configuration DNS et Port-Forward

**Avec Kind, l'IP MetalLB n'est pas accessible depuis l'hôte.**

**Configuration requise** :

#### a) `/etc/hosts`
```bash
echo "127.0.0.1 dashboard.local.lab" | sudo tee -a /etc/hosts
```

#### b) Port-Forward Ingress (obligatoire)
```bash
# Lancer en arrière-plan avec screen
./scripts/start-ingress-portforward.sh

# Vérifier le statut
./scripts/status-ingress-portforward.sh
```

Le port-forward redirige :
```
localhost:8443 → ingress-nginx-controller:443 → dashboard.local.lab
```

---

### 4. Authentification

**Token créé automatiquement** :

Le script de déploiement a généré un token Bearer avec permissions **cluster-admin**.

**Récupération du token** :
```bash
# Méthode 1 : Fichier sauvegardé
cat /tmp/k8s-dashboard-token.txt

# Méthode 2 : Via kubectl
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d

# Méthode 3 : Nouveau token temporaire
kubectl create token admin-user -n kubernetes-dashboard --duration=24h
```

---

## 🌐 Accès au Dashboard

### URL
```
https://dashboard.local.lab:8443/
```

### Étapes de Connexion

1. **Ouvrir l'URL** dans le navigateur
2. **Accepter le certificat auto-signé** (erreur SSL normale)
3. **Choisir "Token"** comme méthode d'authentification
4. **Coller le token** (voir section Authentification ci-dessus)
5. **Cliquer "Sign In"**

---

## 📊 Fonctionnalités Disponibles

### Navigation Principale

Le Dashboard permet de visualiser et gérer :

#### Cluster
- **Nodes** : Voir les nœuds du cluster, leur état, ressources
- **Namespaces** : Tous les namespaces du cluster
- **Persistent Volumes** : PV et PVC

#### Workloads
- **Deployments** : Gérer les déploiements
- **StatefulSets** : Keycloak, Vault, PostgreSQL, Elasticsearch
- **DaemonSets** : Falco, Node Exporter
- **Pods** : Voir tous les pods, leurs logs, métriques
- **Jobs / CronJobs** : Tâches planifiées

#### Services & Discovery
- **Services** : Tous les services (ClusterIP, LoadBalancer)
- **Ingresses** : Keycloak, Vault, Kibana, Dashboard
- **Endpoints** : Vérifier que les services ont des endpoints

#### Config & Storage
- **ConfigMaps** : Configurations applicatives
- **Secrets** : Credentials (en base64)
- **PVC** : Stockage persistant

---

## 🔧 Actions Possibles

### Consulter les Logs d'un Pod

1. **Workloads** → **Pods**
2. **Cliquer sur un pod** (ex: `keycloak-0`)
3. **Onglet "Logs"** en haut à droite
4. Logs en temps réel !

### Ouvrir un Shell dans un Pod

1. **Workloads** → **Pods**
2. **Cliquer sur un pod**
3. **Bouton "Exec"** en haut à droite (icône terminal)
4. Shell interactif s'ouvre !

### Scaler un Deployment

1. **Workloads** → **Deployments**
2. **Cliquer sur un deployment**
3. **Bouton "Scale"** en haut à droite
4. Modifier le nombre de replicas

### Créer une Ressource

1. **Bouton "+" en haut à droite**
2. **Option 1** : Coller du YAML
3. **Option 2** : Utiliser le formulaire
4. **Create**

---

## ⚠️ Problèmes Connus et Solutions

### Problème 1 : Pas de Workloads/Pods Visibles

**Symptôme** : Le Dashboard semble vide

**Cause** : Namespace sélectionné incorrectement

**Solution** :
- En haut à gauche, dans le **dropdown "Namespace"**
- Sélectionner **"All namespaces"** au lieu d'un namespace spécifique

### Problème 2 : Métriques (CPU/RAM) Non Disponibles

**Symptôme** : Pas de graphiques de métriques dans les pods

**Cause** : `metrics-server` non installé

**Solution** :
```bash
# Installer metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patcher pour Kind (désactiver vérification TLS)
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Vérifier
kubectl top nodes
kubectl top pods --all-namespaces
```

### Problème 3 : "Forbidden" sur Certaines Actions

**Symptôme** : Erreur 403 Forbidden lors d'une action

**Cause** : Le token utilisé n'a pas les permissions nécessaires

**Solution** : Vérifier que vous utilisez bien le token `admin-user` qui a les permissions `cluster-admin`

```bash
# Vérifier les permissions du ServiceAccount
kubectl describe clusterrolebinding admin-user
```

---

## 🗑️ Nettoyage : Ancien PVC Keycloak H2

### Contexte

Lors de la migration H2 → PostgreSQL, l'ancien PVC Keycloak est resté en place.

**PVC actuels dans `security-iam`** :
```bash
kubectl get pvc -n security-iam

# Résultat :
NAME                              STATUS   CAPACITY   USAGE
keycloak-data-persistent          Bound    2Gi        ❌ Ancien H2 (inutilisé)
data-keycloak-postgresql-0        Bound    10Gi       ✅ PostgreSQL actif
```

### Vérification Avant Suppression

**Confirmer que Keycloak utilise bien PostgreSQL** :
```bash
kubectl logs -n security-iam keycloak-0 --tail=20 | grep database

# Doit afficher :
# databaseUrl=jdbc:postgresql://keycloak-postgresql:5432/keycloak
# databaseProduct=PostgreSQL 18.1
```

### Suppression de l'Ancien PVC H2 (Optionnel)

**⚠️ Uniquement si vous êtes sûr que Keycloak utilise PostgreSQL !**

```bash
# Supprimer le PVC H2 inutilisé
kubectl delete pvc keycloak-data-persistent -n security-iam
```

**Recommandation** : Attendre quelques jours avant de supprimer, pour être sûr que tout fonctionne bien avec PostgreSQL.

---

## 📊 État Actuel du Dashboard

### Pods Déployés
```bash
kubectl get pods -n kubernetes-dashboard

NAME                                         READY   STATUS    RESTARTS   AGE
dashboard-metrics-scraper-5cb4f4bb9c-26g5q   1/1     Running   0          25m
kubernetes-dashboard-6967859bff-2qsqr        1/1     Running   0          25m
```

### Services
```bash
kubectl get svc -n kubernetes-dashboard

NAME                        TYPE        CLUSTER-IP      PORT(S)
dashboard-metrics-scraper   ClusterIP   10.96.x.x       8000/TCP
kubernetes-dashboard        ClusterIP   10.96.x.x       443/TCP
```

### Ingress
```bash
kubectl get ingress -n kubernetes-dashboard

NAME                           HOSTS                 ADDRESS          PORTS
kubernetes-dashboard-ingress   dashboard.local.lab   172.19.255.200   80
```

---

## 🔐 Sécurité

### Permissions Actuelles

Le ServiceAccount `admin-user` a des permissions **cluster-admin** (accès complet).

**Pour Production** : Limiter les permissions

```yaml
# Exemple : Créer un rôle en lecture seule
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
  name: dashboard-viewer
  namespace: kubernetes-dashboard
```

### Authentification

- ✅ Bearer Token (actuellement utilisé)
- ✅ Kubeconfig (alternative)
- ❌ Pas de login/password par défaut (sécurité)

### TLS

- ✅ Certificat auto-signé (développement OK)
- ⚠️ Pour production : utiliser cert-manager + Let's Encrypt

---

## 📝 Commandes Utiles

### Gestion du Dashboard

```bash
# Redémarrer le Dashboard
kubectl rollout restart deployment/kubernetes-dashboard -n kubernetes-dashboard

# Voir les logs du Dashboard
kubectl logs -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard

# Régénérer un nouveau token
kubectl create token admin-user -n kubernetes-dashboard --duration=24h

# Supprimer le Dashboard
kubectl delete namespace kubernetes-dashboard
```

### Gestion du Port-Forward

```bash
# Démarrer (en arrière-plan avec screen)
./scripts/start-ingress-portforward.sh

# Vérifier le statut
./scripts/status-ingress-portforward.sh

# Arrêter
./scripts/stop-ingress-portforward.sh

# Se rattacher à la session screen
screen -r ingress-pf
```

---

## 🎯 Prochaines Étapes Possibles

### Intégrations

- [ ] **SSO Keycloak** : Authentification via Keycloak au lieu du token
- [ ] **Metrics-Server** : Activer les métriques CPU/RAM dans le Dashboard
- [ ] **Alertes** : Configurer des alertes sur événements critiques
- [ ] **RBAC Granulaire** : Créer des utilisateurs avec permissions limitées

### Sécurité

- [ ] **Let's Encrypt** : Certificats TLS valides via cert-manager
- [ ] **Audit Logging** : Activer les logs d'audit Kubernetes
- [ ] **Network Policies** : Restreindre l'accès au Dashboard
- [ ] **Token Expiration** : Configurer une expiration automatique des tokens

---

## 📚 Ressources

- **Dashboard GitHub** : https://github.com/kubernetes/dashboard
- **Documentation Officielle** : https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
- **Troubleshooting** : https://github.com/kubernetes/dashboard/wiki/Troubleshooting
- **Releases** : https://github.com/kubernetes/dashboard/releases

---

## ✅ Checklist de Vérification

Après déploiement, vérifiez :

- [x] Dashboard accessible sur https://dashboard.local.lab:8443/
- [x] Authentification par token fonctionne
- [x] Pods visibles dans "Workloads" → "Pods"
- [x] Logs des pods accessibles
- [x] Shell dans les pods fonctionne (Exec)
- [ ] Métriques CPU/RAM affichées (nécessite metrics-server)
- [x] Port-forward actif en arrière-plan (screen)
- [x] Token sauvegardé dans /tmp/k8s-dashboard-token.txt

---

**✅ Le Kubernetes Dashboard est maintenant opérationnel et accessible via Ingress !**

**URLs de la Stack Complète** :
- Keycloak : https://keycloak.local.lab:8443/admin/
- Vault : https://vault.local.lab:8443/ui/
- Kibana : https://kibana.local.lab:8443/
- Dashboard : https://dashboard.local.lab:8443/ ✨
