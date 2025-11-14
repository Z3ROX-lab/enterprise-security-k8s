# Accès aux Services via Port-Forward (Windows)

## 🎯 Problème

L'IP MetalLB (`172.19.255.200`) est interne au cluster Kind/WSL2 et **n'est pas accessible depuis Windows**.

## ✅ Solution

Utiliser un port-forward du service Ingress NGINX vers `localhost:8443`.

---

## 📋 Étape 1 : Configurer les Ingress avec HTTPS

```bash
# Exécuter depuis WSL2
cd ~/work/enterprise-security-k8s
./scripts/setup-keycloak-vault-https.sh
```

Ce script configure les Ingress Keycloak et Vault avec TLS.

---

## 🌐 Étape 2 : Configurer le fichier hosts Windows

**Sur Windows (EN TANT QU'ADMINISTRATEUR)**, éditez :

`C:\Windows\System32\drivers\etc\hosts`

**Ajoutez ces lignes :**

```
127.0.0.1 grafana.local.lab
127.0.0.1 kibana.local.lab
127.0.0.1 prometheus.local.lab
127.0.0.1 falco-ui.local.lab
127.0.0.1 keycloak.local.lab
127.0.0.1 vault.local.lab
```

**💡 Astuce :**
- Ouvrir **Notepad en tant qu'Administrateur**
- File → Open → `C:\Windows\System32\drivers\etc\hosts`
- Ajouter les lignes ci-dessus
- Save

---

## 🚀 Étape 3 : Démarrer le Port-Forward

**Dans un terminal WSL2 dédié** (ce terminal restera occupé) :

```bash
cd ~/work/enterprise-security-k8s
./scripts/port-forward-ingress.sh
```

**Sortie attendue :**
```
✅ Port-forward actif ! Accédez aux services depuis Windows.

Forwarding from 0.0.0.0:8443 -> 443
```

⚠️ **Important** : Laissez ce terminal ouvert en arrière-plan.

---

## 🌐 Étape 4 : Accéder aux Services

### Depuis Windows (Navigateur)

Ouvrez ces URLs :

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | https://grafana.local.lab:8443 | admin / (voir commande) |
| **Kibana** | https://kibana.local.lab:8443 | - |
| **Prometheus** | https://prometheus.local.lab:8443 | - |
| **Falco UI** | https://falco-ui.local.lab:8443 | admin / admin |
| **Keycloak** | https://keycloak.local.lab:8443 | admin / (voir commande) |
| **Keycloak Admin** | https://keycloak.local.lab:8443/admin | admin / (voir commande) |
| **Vault** | https://vault.local.lab:8443 | (voir commande) |
| **Vault UI** | https://vault.local.lab:8443/ui | (voir commande) |

⚠️ **Avertissement de certificat** : Le navigateur affichera un avertissement car le certificat est auto-signé. C'est **NORMAL**.
- Cliquez sur **"Avancé"** ou **"Advanced"**
- Cliquez sur **"Continuer vers le site (non sécurisé)"** ou **"Proceed to site (unsafe)"**

---

## 🔑 Récupérer les Credentials

### Keycloak

```bash
# Username
echo "admin"

# Password
kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d && echo
```

### Vault

```bash
# Token (dev mode)
echo "root"

# OU Token (production)
kubectl get secret vault-unseal-keys -n security-iam -o jsonpath='{.data.root-token}' | base64 -d && echo
```

### Grafana

```bash
# Username
echo "admin"

# Password
kubectl get secret prometheus-grafana -n security-siem -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

---

## 🔍 Vérifications

### Vérifier que le port-forward est actif

Dans un **nouveau terminal WSL2** :

```bash
# Test depuis WSL2
curl -k -I https://localhost:8443 -H "Host: keycloak.local.lab"

# Devrait retourner HTTP 200, 302 ou 303
```

### Vérifier les Ingress

```bash
kubectl get ingress -A
```

Vous devriez voir :
```
NAMESPACE            NAME                       HOSTS                    TLS
security-iam         keycloak-ingress           keycloak.local.lab       keycloak-tls
security-iam         vault-ingress              vault.local.lab          vault-tls
security-siem        grafana-ingress            grafana.local.lab        grafana-tls
security-siem        kibana-ingress             kibana.local.lab         kibana-tls
security-siem        prometheus-ingress         prometheus.local.lab     prometheus-tls
security-detection   falcosidekick-ui-ingress   falco-ui.local.lab       falco-ui-tls
```

### Vérifier les certificats TLS

```bash
kubectl get certificate -A
```

Tous les certificats doivent être **READY = True**.

---

## 🛑 Arrêter le Port-Forward

Dans le terminal où le port-forward est actif :
- Appuyez sur **Ctrl+C**

---

## 🔄 Automatisation (Optionnel)

Pour démarrer automatiquement le port-forward au démarrage de WSL2, ajoutez dans `~/.bashrc` :

```bash
# Auto-start Ingress port-forward in background
if ! pgrep -f "kubectl port-forward.*ingress-nginx-controller" > /dev/null; then
    echo "🚀 Starting Ingress port-forward..."
    nohup kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443 --address 0.0.0.0 > /tmp/ingress-pf.log 2>&1 &
fi
```

Puis :
```bash
source ~/.bashrc
```

---

## 🛠️ Troubleshooting

### Problème : "Connection Refused" depuis Windows

**Cause** : Le port-forward n'est pas démarré ou est tombé

**Solution** :
```bash
# Vérifier le processus
ps aux | grep "kubectl port-forward"

# Redémarrer
./scripts/port-forward-ingress.sh
```

### Problème : "This site can't be reached" dans le navigateur

**Cause** : Le fichier hosts Windows n'est pas configuré

**Solution** : Vérifier `C:\Windows\System32\drivers\etc\hosts` contient bien :
```
127.0.0.1 keycloak.local.lab
127.0.0.1 vault.local.lab
```

### Problème : "502 Bad Gateway"

**Cause** : Les pods backend ne sont pas prêts

**Solution** :
```bash
# Vérifier les pods
kubectl get pods -n security-iam

# Redémarrer si nécessaire
kubectl rollout restart deployment keycloak -n security-iam
kubectl rollout restart statefulset vault -n security-iam
```

### Problème : Certificat expiré ou invalide

**Cause** : Les certificats TLS ne sont pas générés

**Solution** :
```bash
# Vérifier les certificats
kubectl get certificate -n security-iam

# Recréer si nécessaire
./scripts/setup-keycloak-vault-https.sh
```

---

## 📊 Architecture Réseau

```
┌─────────────────────────────────────────┐
│         Navigateur Windows              │
│   https://keycloak.local.lab:8443       │
└──────────────┬──────────────────────────┘
               │
               │ Fichier hosts Windows
               │ keycloak.local.lab → 127.0.0.1
               │
┌──────────────▼──────────────────────────┐
│      Windows Networking Layer           │
│         localhost:8443                  │
└──────────────┬──────────────────────────┘
               │
               │ Network bridge WSL2 ↔ Windows
               │
┌──────────────▼──────────────────────────┐
│        WSL2 Ubuntu                      │
│   kubectl port-forward 0.0.0.0:8443    │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      Kind Cluster Network               │
│   NGINX Ingress Controller :443         │
│   (TLS termination)                     │
└──────────────┬──────────────────────────┘
               │
               │ Host header routing
               │
     ┌─────────┴─────────┐
     │                   │
┌────▼───────┐    ┌──────▼────┐
│  Keycloak  │    │   Vault   │
│  :80       │    │   :8200   │
└────────────┘    └───────────┘
```

---

## 📚 Références

- [kubectl port-forward documentation](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Guide Principal](README.md)
- [Troubleshooting](TROUBLESHOOTING.md)

---

**Auteur** : Z3ROX
**Projet** : Enterprise Security Stack on Kubernetes
**Date** : 2025-01
