# Configuration de l'Ingress pour Keycloak et Vault

Ce guide vous explique comment exposer Keycloak et Vault via l'Ingress NGINX avec MetalLB.

## 📋 Prérequis

Avant de commencer, assurez-vous que :
- ✅ MetalLB est déployé (`./deploy/50-metallb.sh`)
- ✅ NGINX Ingress Controller est déployé (`./deploy/51-nginx-ingress.sh`)
- ✅ Keycloak et Vault sont déployés dans le namespace `security-iam`

## 🚀 Déploiement

### Option 1 : Script Automatique (Recommandé)

```bash
cd /home/user/enterprise-security-k8s
./deploy/52b-ingress-keycloak-vault.sh
```

Le script va :
1. Vérifier que l'Ingress Controller est installé
2. Récupérer l'IP du LoadBalancer MetalLB
3. Créer les Ingress pour Keycloak et Vault
4. Tester la connectivité
5. Afficher les instructions de configuration DNS

### Option 2 : Manifeste YAML Direct

```bash
kubectl apply -f /home/user/enterprise-security-k8s/deploy/keycloak-vault-ingress.yaml
```

## 🌐 Configuration DNS Locale

### 1. Récupérer l'IP du LoadBalancer

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Exemple de sortie : `172.18.255.200`

### 2a. Sur Windows (Hôte)

**En tant qu'Administrateur**, éditez `C:\Windows\System32\drivers\etc\hosts` :

```
172.18.255.200 keycloak.local.lab
172.18.255.200 vault.local.lab
172.18.255.200 grafana.local.lab
172.18.255.200 kibana.local.lab
172.18.255.200 prometheus.local.lab
172.18.255.200 falco-ui.local.lab
```

### 2b. Sur WSL2/Linux

```bash
# Récupérer l'IP
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Ajouter au fichier hosts
sudo tee -a /etc/hosts <<EOF
# Enterprise Security Stack
$INGRESS_IP keycloak.local.lab
$INGRESS_IP vault.local.lab
$INGRESS_IP grafana.local.lab
$INGRESS_IP kibana.local.lab
$INGRESS_IP prometheus.local.lab
$INGRESS_IP falco-ui.local.lab
EOF
```

## 🔐 Accès aux Services

### Keycloak

**URL** : http://keycloak.local.lab

**Récupérer le mot de passe admin** :

```bash
# Méthode 1 : Via secret Kubernetes
kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d && echo

# Méthode 2 : Via variables Terraform
grep keycloak_admin_password terraform/terraform.tfvars 2>/dev/null || echo "admin123 (default)"
```

**Connexion** :
- Username: `admin`
- Password: (résultat de la commande ci-dessus)

**Console Admin** : http://keycloak.local.lab/admin

### Vault

**URL** : http://vault.local.lab

**Récupérer le root token** :

```bash
# Mode dev (token = "root")
echo "root"

# Mode production (si configuré)
kubectl get secret vault-unseal-keys -n security-iam -o jsonpath='{.data.root-token}' | base64 -d && echo
```

**Vault UI** : http://vault.local.lab/ui

## 🔍 Vérification

### 1. Vérifier les Ingress

```bash
# Lister tous les Ingress
kubectl get ingress -A

# Détails Keycloak Ingress
kubectl describe ingress keycloak-ingress -n security-iam

# Détails Vault Ingress
kubectl describe ingress vault-ingress -n security-iam
```

### 2. Tester la Connectivité

```bash
# Obtenir l'IP
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test Keycloak
curl -I -H "Host: keycloak.local.lab" http://$INGRESS_IP

# Test Vault
curl -H "Host: vault.local.lab" http://$INGRESS_IP/v1/sys/health
```

### 3. Tester depuis le Navigateur

Une fois le fichier hosts configuré :

- Keycloak : http://keycloak.local.lab
- Vault : http://vault.local.lab/ui

## 🛠️ Troubleshooting

### Problème : "502 Bad Gateway"

**Cause** : Le service backend n'est pas prêt

**Solution** :
```bash
# Vérifier les pods Keycloak
kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak

# Vérifier les logs
kubectl logs -n security-iam -l app.kubernetes.io/name=keycloak --tail=50

# Redémarrer si nécessaire
kubectl rollout restart deployment keycloak -n security-iam
```

### Problème : "404 Not Found"

**Cause** : L'Ingress n'est pas créé ou le hostname ne correspond pas

**Solution** :
```bash
# Vérifier que l'Ingress existe
kubectl get ingress keycloak-ingress -n security-iam

# Vérifier le hostname dans le header Host
curl -v -H "Host: keycloak.local.lab" http://<INGRESS_IP>
```

### Problème : "Connection Refused" ou Timeout

**Cause** : L'Ingress Controller n'est pas démarré

**Solution** :
```bash
# Vérifier les pods Ingress
kubectl get pods -n ingress-nginx

# Vérifier le service LoadBalancer
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Vérifier MetalLB
kubectl get pods -n metallb-system
```

### Problème : Redirection infinie sur Keycloak

**Cause** : Headers de proxy manquants

**Solution** : Les annotations dans l'Ingress doivent inclure :
```yaml
nginx.ingress.kubernetes.io/configuration-snippet: |
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_set_header X-Forwarded-Host $host;
```

Vérifiez que le manifeste contient ces annotations (déjà présentes dans les fichiers fournis).

## 📊 Architecture Réseau

```
┌─────────────────────────────────────────────────────────┐
│                   Navigateur Client                     │
│                                                         │
│  http://keycloak.local.lab                             │
│  http://vault.local.lab                                │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ DNS local (/etc/hosts)
                     │ keycloak.local.lab → 172.18.255.200
                     │
┌────────────────────▼────────────────────────────────────┐
│              MetalLB LoadBalancer                       │
│                 172.18.255.200                          │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│          NGINX Ingress Controller                       │
│           (namespace: ingress-nginx)                    │
│                                                         │
│  ┌─────────────────────────────────────────────┐       │
│  │  Routing basé sur Host header:              │       │
│  │  - keycloak.local.lab → keycloak:80         │       │
│  │  - vault.local.lab → vault:8200             │       │
│  └─────────────────────────────────────────────┘       │
└──────────────────┬──────────────────┬───────────────────┘
                   │                  │
      ┌────────────▼────────┐    ┌───▼──────────────┐
      │  Service: keycloak  │    │  Service: vault  │
      │  namespace:         │    │  namespace:      │
      │  security-iam       │    │  security-iam    │
      │  Port: 80           │    │  Port: 8200      │
      └────────────┬────────┘    └───┬──────────────┘
                   │                  │
      ┌────────────▼────────┐    ┌───▼──────────────┐
      │  Pod: keycloak-xxx  │    │  Pod: vault-0    │
      └─────────────────────┘    └──────────────────┘
```

## 🔐 Sécurité

### HTTP vs HTTPS

**Actuellement** : HTTP (non chiffré)

**Pour activer HTTPS** :

1. Déployer cert-manager (si pas déjà fait)
2. Configurer Vault PKI
3. Créer des certificats TLS
4. Appliquer le script TLS :

```bash
./deploy/53-ingress-tls.sh
```

Voir le guide détaillé : [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

### NetworkPolicies

Les NetworkPolicies du namespace `security-iam` doivent autoriser :
- Ingress depuis `ingress-nginx` namespace
- Egress vers PostgreSQL (pour Keycloak)

Vérifier :
```bash
kubectl get networkpolicies -n security-iam
kubectl describe networkpolicy <policy-name> -n security-iam
```

## 📝 Prochaines Étapes

Une fois Keycloak accessible via Ingress :

1. **Configurer des Realms** dans Keycloak
2. **Créer des Clients OIDC** pour vos applications
3. **Intégrer l'authentification** Keycloak avec Grafana, Kibana, etc.
4. **Configurer Vault PKI** pour générer des certificats
5. **Activer HTTPS** avec cert-manager

## 📚 Références

- [Documentation Keycloak](https://www.keycloak.org/documentation)
- [Documentation Vault](https://www.vaultproject.io/docs)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Guide du projet](README.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Credentials](CREDENTIALS.md)

---

**Auteur** : Z3ROX
**Projet** : Enterprise Security Stack on Kubernetes
**Date** : 2025-01
