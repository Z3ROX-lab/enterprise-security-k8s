# Services URLs - Enterprise Security Stack

Ce document liste toutes les URLs d'accès aux services de la stack de sécurité.

## 📋 Prérequis

### 1. Port-Forward Ingress Actif

Le port-forward doit être actif pour accéder aux services via les URLs ci-dessous :

```bash
# Démarrer le port-forward
./scripts/start-ingress-portforward.sh

# Vérifier le statut
./scripts/status-ingress-portforward.sh
```

### 2. Configuration du fichier hosts

Ajoutez ces lignes dans votre fichier hosts :

**Windows** : `C:\Windows\System32\drivers\etc\hosts` (nécessite droits administrateur)
**Linux/WSL** : `/etc/hosts` (nécessite sudo)

```
127.0.0.1 keycloak.local.lab
127.0.0.1 vault.local.lab
127.0.0.1 kibana.local.lab
127.0.0.1 dashboard.local.lab
127.0.0.1 grafana.local.lab
127.0.0.1 prometheus.local.lab
```

---

## 🌐 URLs d'Accès

### IAM & Secrets Management

| Service | URL | Credentials | Notes |
|---------|-----|-------------|-------|
| **Keycloak** | https://keycloak.local.lab:8443/admin/ | admin / admin123 | Console d'administration IAM |
| **Vault UI** | https://vault.local.lab:8443/ui/ | Token (voir ci-dessous) | Secrets Management |

**Récupérer le token Vault** :
```bash
# Si vous avez le fichier vault-keys.txt
cat vault-keys.txt | jq -r '.root_token'

# OU directement depuis le secret
kubectl get secret vault-init -n security-iam -o jsonpath='{.data.root_token}' | base64 -d
```

---

### Observabilité & SIEM

| Service | URL | Credentials | Notes |
|---------|-----|-------------|-------|
| **Kibana** | https://kibana.local.lab:8443/ | elastic / <voir ci-dessous> | SIEM Dashboard |
| **Grafana** | Port-forward requis | admin / prom-operator | Métriques & Dashboards |
| **Prometheus** | Port-forward requis | - | Métriques brutes |

**Récupérer le password Elasticsearch/Kibana** :
```bash
kubectl get secret elasticsearch-master-credentials -n security-siem \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

**Accès Grafana via port-forward** :
```bash
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
# Accès: http://localhost:3000
```

**Accès Prometheus via port-forward** :
```bash
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# Accès: http://localhost:9090
```

---

### Kubernetes Management

| Service | URL | Credentials | Notes |
|---------|-----|-------------|-------|
| **Kubernetes Dashboard** | https://dashboard.local.lab:8443/ | Token (voir ci-dessous) | Interface Web GUI |

**Récupérer le token Dashboard** :
```bash
# Méthode 1: Depuis le fichier sauvegardé
cat /tmp/k8s-dashboard-token.txt

# Méthode 2: Depuis le secret
kubectl get secret admin-user-token -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d && echo

# Méthode 3: Créer un nouveau token (24h)
kubectl create token admin-user -n kubernetes-dashboard --duration=24h
```

---

## 🔐 Résumé des Credentials par Défaut

⚠️ **IMPORTANT** : Ces credentials sont pour l'environnement de développement uniquement. **NE PAS** utiliser en production !

| Service | Username | Password | Localisation |
|---------|----------|----------|--------------|
| Keycloak | admin | admin123 | PostgreSQL backend |
| Vault | - | Root Token (vault-keys.txt) | Raft backend |
| Kibana | elastic | Auto-généré | Secret K8s |
| Grafana | admin | prom-operator | ConfigMap |
| Dashboard | - | Token JWT | Secret K8s |
| PostgreSQL (Keycloak) | keycloak | keycloak123 | StatefulSet |

---

## 🧪 Tests de Connectivité

### Test 1 : Vérifier le Port-Forward

```bash
curl -k -s -o /dev/null -w "HTTP %{http_code}\n" https://localhost:8443

# Devrait retourner : HTTP 404 (c'est normal, NGINX répond)
```

### Test 2 : Vérifier les Endpoints Kubernetes

```bash
kubectl get endpoints -n security-iam keycloak-http
kubectl get endpoints -n security-iam vault
kubectl get endpoints -n security-siem kibana-kibana
kubectl get endpoints -n kubernetes-dashboard kubernetes-dashboard
```

Les endpoints ne doivent **PAS** être vides.

### Test 3 : Vérifier les Pods

```bash
kubectl get pods -n security-iam
kubectl get pods -n security-siem
kubectl get pods -n kubernetes-dashboard

# Tous les pods doivent être Running et Ready (1/1)
```

---

## 🚨 Troubleshooting

### Erreur 503 Service Temporarily Unavailable

**Cause** : Le backend n'est pas disponible ou les endpoints sont vides.

**Solution** :
```bash
# Vérifier l'état du pod
kubectl get pods -n <namespace>

# Vérifier les endpoints
kubectl get endpoints -n <namespace> <service-name>

# Voir les logs
kubectl logs -n <namespace> <pod-name> --tail=50
```

### Erreur : Page not found (/auth/)

**Cause** : Keycloak 18+ n'utilise plus le contexte `/auth` par défaut.

**Solution** : Utiliser `/admin/` au lieu de `/auth/admin/`
- ❌ Ancienne URL : https://keycloak.local.lab:8443/auth/admin/
- ✅ Nouvelle URL : https://keycloak.local.lab:8443/admin/

### Certificat SSL Invalide

**Cause** : Certificats auto-signés utilisés pour le développement.

**Solution** : Accepter l'exception de sécurité dans le navigateur (normal en dev).

---

## 📝 Notes Importantes

### Keycloak URL Change (v18+)

Keycloak 18.0.0 a supprimé le contexte `/auth` par défaut. Les nouvelles URLs sont :
- Console admin : `/admin/`
- API : `/realms/`
- Anciennes URLs avec `/auth` : **Non supportées**

Si vous avez absolument besoin de restaurer `/auth`, ajoutez cette variable d'environnement :
```bash
kubectl patch statefulset keycloak -n security-iam --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "KC_HTTP_RELATIVE_PATH",
      "value": "/auth"
    }
  }
]'
```

### Vault Unseal

Vault en mode Raft nécessite un **unseal** après chaque redémarrage :

```bash
# Vérifier le statut
kubectl exec -n security-iam vault-0 -- vault status

# Unseal avec 3 clés (threshold)
kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY1>
kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY2>
kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY3>
```

Les clés sont dans `vault-keys.txt` (créé lors de l'init).

---

## 🔗 Références

- **Documentation Keycloak** : https://www.keycloak.org/docs/18.0/
- **Documentation Vault** : https://developer.hashicorp.com/vault/docs
- **Documentation Kubernetes Dashboard** : https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
- **Documentation Ingress NGINX** : https://kubernetes.github.io/ingress-nginx/

---

**Dernière mise à jour** : 2025-11-17
**Version Keycloak** : 18.0.0
**Version Kubernetes** : 1.27.3
