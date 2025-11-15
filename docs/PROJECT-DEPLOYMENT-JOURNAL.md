# Journal de Déploiement - Enterprise Security Stack sur Kubernetes

> Documentation complète et chronologique du projet de stack de cybersécurité d'entreprise

**Auteur** : Z3ROX
**Date de création** : Novembre 2025
**Objectif** : Déployer une stack de sécurité production-ready équivalente aux solutions commerciales (CrowdStrike, Splunk, Okta, etc.)

---

## 📋 Table des Matières

1. [Vue d'Ensemble du Projet](#vue-densemble-du-projet)
2. [Architecture Globale](#architecture-globale)
3. [Installation Chronologique des Composants](#installation-chronologique-des-composants)
4. [Problèmes Rencontrés et Solutions](#problèmes-rencontrés-et-solutions)
5. [Configuration Réseau et Ingress](#configuration-réseau-et-ingress)
6. [État Actuel du Projet](#état-actuel-du-projet)
7. [Accès et Credentials](#accès-et-credentials)
8. [Scripts et Outils Créés](#scripts-et-outils-créés)

---

## 🎯 Vue d'Ensemble du Projet

### Objectif

Démonstrer comment construire une **stack de cybersécurité d'entreprise moderne** sur Kubernetes, équivalente aux solutions commerciales utilisées dans les grandes organisations.

### Équivalences Commerciales

| Composant Déployé | Équivalent Commercial | Rôle |
|-------------------|----------------------|------|
| Keycloak | Okta, Azure AD | IAM / SSO |
| HashiCorp Vault | AWS Secrets Manager, CyberArk | Secrets Management |
| ELK Stack | Splunk, QRadar | SIEM |
| Falco | CrowdStrike Falcon | Runtime Security |
| Wazuh | SentinelOne | EDR/XDR |
| Trivy | Snyk, Aqua | Vulnerability Scanning |
| OPA Gatekeeper | Prisma Cloud | Policy Enforcement |

### Infrastructure de Base

- **Cluster Kubernetes** : Kind (Kubernetes in Docker)
- **Namespaces** :
  - `security-iam` : IAM et Secrets Management
  - `security-siem` : Observabilité et SIEM
  - `security-detection` : Runtime Security
  - `ingress-nginx` : Ingress Controller
  - `metallb-system` : Load Balancer
  - `cert-manager` : Gestion des certificats TLS

---

## 🏗️ Architecture Globale

### Schéma d'Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    COUCHE D'ACCÈS (Ingress)                     │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  MetalLB (Load Balancer) → NGINX Ingress Controller     │   │
│  │  IP: <MetalLB_IP>                                        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    COUCHE SERVICES (HTTPS)                      │
│  ┌───────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │   Keycloak    │  │    Vault     │  │     Kibana         │   │
│  │ :8443/auth    │  │   :8443/ui   │  │     :8443/         │   │
│  └───────┬───────┘  └──────┬───────┘  └─────────┬──────────┘   │
└──────────┼──────────────────┼───────────────────┼───────────────┘
           │                  │                   │
           ↓                  ↓                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                  COUCHE DONNÉES (Persistence)                   │
│  ┌───────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │  PostgreSQL   │  │  Vault Raft  │  │  Elasticsearch     │   │
│  │  PVC 10Gi     │  │  PVC 10Gi×3  │  │  StatefulSet       │   │
│  └───────────────┘  └──────────────┘  └────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
           │                  │                   │
           ↓                  ↓                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                COUCHE STOCKAGE (Persistent Volumes)             │
│  Standard StorageClass (dynamic provisioning)                   │
└─────────────────────────────────────────────────────────────────┘
```

### Flux de Données

```
Utilisateur
   ↓
DNS (keycloak.local.lab, vault.local.lab, kibana.local.lab)
   ↓
/etc/hosts → IP MetalLB
   ↓
MetalLB Load Balancer
   ↓
NGINX Ingress Controller
   ↓
Services Kubernetes (keycloak-http, vault, kibana-kibana)
   ↓
Pods Applications (Keycloak, Vault, Kibana)
   ↓
Bases de Données (PostgreSQL, Elasticsearch, Vault Raft)
   ↓
Persistent Volumes (PVC)
```

---

## 📦 Installation Chronologique des Composants

### Phase 1 : Infrastructure de Base

#### Étape 1 : Cluster Kubernetes (Kind)
**Script** : `deploy/01-cluster-kind.sh`

```bash
# Création du cluster Kind
kind create cluster --config kind-config.yaml
```

**Résultat** :
- Cluster Kubernetes local multi-node
- Support pour Ingress et LoadBalancer
- Port mapping pour accès externe

---

### Phase 2 : Observabilité (SIEM)

#### Étape 2 : Elasticsearch
**Script** : `deploy/10-elasticsearch.sh`
**Namespace** : `security-siem`

```bash
helm install elasticsearch elastic/elasticsearch \
  --namespace security-siem \
  --set replicas=1 \
  --set minimumMasterNodes=1
```

**Composants installés** :
- ✅ Elasticsearch StatefulSet
- ✅ Service `elasticsearch-master:9200`
- ✅ Secret `elasticsearch-master-credentials`

**Configuration** :
- **Replicas** : 1 (single-node pour dev)
- **Sécurité** : X-Pack Security activé
- **Credentials** : User `elastic` + password auto-généré

---

#### Étape 3 : Kibana
**Script** : `deploy/11-kibana.sh`
**Namespace** : `security-siem`

```bash
helm install kibana elastic/kibana \
  --namespace security-siem \
  --set elasticsearchHosts="http://elasticsearch-master:9200"
```

**Composants installés** :
- ✅ Kibana Deployment
- ✅ Service `kibana-kibana:5601`
- ✅ Connexion à Elasticsearch

**Interface** :
- Port : 5601
- URL : `http://localhost:5601` (via port-forward)

---

#### Étape 4 : Filebeat
**Script** : `deploy/12-filebeat.sh`
**Namespace** : `security-siem`

```bash
helm install filebeat elastic/filebeat \
  --namespace security-siem
```

**Rôle** : Collecte des logs Kubernetes → Elasticsearch

---

#### Étape 5 : Prometheus + Grafana
**Script** : `deploy/13-prometheus.sh`
**Namespace** : `security-siem`

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace security-siem
```

**Composants installés** :
- ✅ Prometheus (métriques)
- ✅ Grafana (visualisation)
- ✅ Alertmanager (alertes)
- ✅ Node Exporter
- ✅ Kube-state-metrics

---

### Phase 3 : IAM et Secrets Management

#### Étape 6 : cert-manager
**Script** : `deploy/20-cert-manager.sh`
**Namespace** : `cert-manager`

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true
```

**Rôle** : Gestion automatique des certificats TLS (Let's Encrypt, auto-signés)

---

#### Étape 7 : Keycloak (IAM)
**Script** : `deploy/21-keycloak.sh`
**Namespace** : `security-iam`

```bash
# Déploiement PostgreSQL pour Keycloak
helm install keycloak-postgresql bitnami/postgresql \
  --namespace security-iam \
  --set auth.username=keycloak \
  --set auth.password=keycloak123 \
  --set auth.database=keycloak \
  --set primary.persistence.enabled=false  # ⚠️ Pas de persistence initialement

# Déploiement Keycloak
helm install keycloak codecentric/keycloak \
  --namespace security-iam \
  --set keycloak.username=admin \
  --set keycloak.password=admin123 \
  --set postgresql.enabled=false \
  --set keycloak.extraEnv="DB_VENDOR=postgres,DB_ADDR=keycloak-postgresql,..."
```

**⚠️ Problème Détecté Plus Tard** :
Keycloak utilisait en réalité **H2 embarqué** au lieu de PostgreSQL !
Voir [Phase 6 : Corrections et Migrations](#phase-6-corrections-et-migrations)

**Composants installés** :
- ✅ Keycloak StatefulSet
- ✅ PostgreSQL StatefulSet (non utilisé initialement)
- ✅ Services : `keycloak-http`, `keycloak-headless`

**Credentials par défaut** :
- Username : `admin`
- Password : `admin123`

---

#### Étape 8 : HashiCorp Vault (Mode Dev)
**Script** : `deploy/22-vault-dev.sh`
**Namespace** : `security-iam`

```bash
helm install vault hashicorp/vault \
  --namespace security-iam \
  --set server.dev.enabled=true
```

**Rôle** : Déploiement rapide en mode développement (données en RAM)

---

#### Étape 9 : HashiCorp Vault (Mode Raft HA)
**Script** : `deploy/23-vault-raft.sh`
**Namespace** : `security-iam`

```bash
helm install vault hashicorp/vault \
  --namespace security-iam \
  --set server.ha.enabled=true \
  --set server.ha.raft.enabled=true \
  --set server.dataStorage.enabled=true \
  --set server.dataStorage.size=10Gi
```

**Composants installés** :
- ✅ 3 pods Vault (vault-0, vault-1, vault-2)
- ✅ Mode Haute Disponibilité (Raft consensus)
- ✅ 3 PVC 10Gi pour persistence
- ✅ Services : `vault`, `vault-active`, `vault-standby`, `vault-ui`

**Initialisation** :
```bash
kubectl exec -n security-iam vault-0 -- vault operator init -format=json > vault-keys.txt
```

**Unseal** (nécessaire après chaque redémarrage) :
```bash
# Unseal avec 3 clés (threshold de 3 sur 5)
kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY1>
kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY2>
kubectl exec -n security-iam vault-0 -- vault operator unseal <KEY3>
```

---

#### Étape 10 : Vault PKI (Certificats internes)
**Script** : `deploy/24-vault-pki.sh`
**Namespace** : `security-iam`

```bash
# Configuration PKI dans Vault
vault secrets enable pki
vault write pki/root/generate/internal \
  common_name="Enterprise Security CA" \
  ttl=87600h
```

**Rôle** : Autorité de Certification (CA) interne pour mTLS

---

### Phase 4 : Runtime Security

#### Étape 11 : Falco (eBPF Runtime Security)
**Script** : `deploy/30-falco.sh`
**Namespace** : `security-detection`

```bash
helm install falco falcosecurity/falco \
  --namespace security-detection \
  --set falco.grpc.enabled=true
```

**Rôle** : Détection de comportements suspects (shell inverse, privilege escalation, etc.)

---

#### Étape 12 : Falco Sidekick (Intégration Elasticsearch)
**Scripts** :
- `deploy/31-falco-sidekick.sh`
- `deploy/31-falco-elasticsearch-config.sh`

```bash
helm install falco-sidekick falcosecurity/falco-sidekick \
  --namespace security-detection \
  --set config.elasticsearch.hostport=http://elasticsearch-master.security-siem:9200
```

**Rôle** : Envoie les alertes Falco vers Elasticsearch pour corrélation SIEM

---

#### Étape 13 : Wazuh (EDR/HIDS)
**Script** : `deploy/31-wazuh.sh`
**Namespace** : `security-detection`

```bash
helm install wazuh wazuh/wazuh \
  --namespace security-detection
```

**Rôle** : Host Intrusion Detection System (HIDS)

---

#### Étape 14 : Intégration Falco + Grafana
**Scripts** :
- `deploy/32-falco-grafana.sh`
- `deploy/33-falco-dashboard-import.sh`
- `deploy/34-falco-tuning.sh`

**Rôle** : Dashboards Grafana pour visualiser les alertes Falco

---

### Phase 5 : Policy Enforcement et Compliance

#### Étape 15 : OPA Gatekeeper
**Script** : `deploy/40-gatekeeper.sh`
**Namespace** : `gatekeeper-system`

```bash
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system
```

**Rôle** : Policy Enforcement (PSP, admission control)

---

#### Étape 16 : Trivy Operator
**Script** : `deploy/41-trivy.sh`
**Namespace** : `trivy-system`

```bash
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system
```

**Rôle** : Scan automatique des vulnérabilités dans les images

---

#### Étape 17 : Trivy + Grafana
**Script** : `deploy/42-trivy-grafana.sh`

**Rôle** : Dashboards Grafana pour visualiser les vulnérabilités détectées

---

#### Étape 18 : Trivy + Elasticsearch
**Script** : `deploy/43-trivy-elasticsearch.sh`

**Rôle** : Envoie les résultats de scan vers Elasticsearch

---

### Phase 6 : Networking (Ingress + Load Balancer)

#### Étape 19 : MetalLB (Load Balancer)
**Script** : `deploy/50-metallb.sh`
**Namespace** : `metallb-system`

```bash
helm install metallb metallb/metallb \
  --namespace metallb-system
```

**Configuration** :
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250  # Plage d'IP pour LoadBalancer
```

**Rôle** : Fournit des IPs externes pour les services de type LoadBalancer

---

#### Étape 20 : NGINX Ingress Controller
**Script** : `deploy/51-nginx-ingress.sh`
**Namespace** : `ingress-nginx`

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer
```

**Résultat** :
- ✅ Service `ingress-nginx-controller` de type LoadBalancer
- ✅ IP externe assignée par MetalLB
- ✅ Ports : 80 (HTTP) et 443 (HTTPS)

**Vérification** :
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# EXTERNAL-IP: 172.18.255.200 (exemple)
```

---

#### Étape 21 : Ingress Resources (Keycloak + Vault)
**Scripts** :
- `deploy/52-ingress-resources.sh`
- `deploy/52b-ingress-keycloak-vault.sh`

**Configuration Ingress Keycloak** :
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: security-iam
spec:
  ingressClassName: nginx
  rules:
  - host: keycloak.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak-http
            port:
              number: 80
```

**Configuration Ingress Vault** :
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: security-iam
spec:
  ingressClassName: nginx
  rules:
  - host: vault.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vault
            port:
              number: 8200
```

**Configuration Ingress Kibana** :
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: security-siem
spec:
  ingressClassName: nginx
  rules:
  - host: kibana.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana-kibana
            port:
              number: 5601
```

---

#### Étape 22 : Configuration TLS
**Scripts** :
- `deploy/53-ingress-tls.sh`
- `deploy/54-cert-manager-rbac-fix.sh`
- `deploy/55-cert-manager-restart.sh`
- `deploy/56-certificates-force-retry.sh`
- `deploy/57-vault-pki-fix-cn.sh`

**Rôle** : Certificats TLS auto-signés pour les Ingress

---

## 🔧 Problèmes Rencontrés et Solutions

### Problème 1 : Keycloak Ingress - Endpoints Vides

**Date** : Novembre 2025
**Symptôme** : L'Ingress Keycloak ne fonctionnait pas, `kubectl get endpoints` montrait `<none>`

**Diagnostic** :
```bash
kubectl get endpoints -n security-iam keycloak-http
# NAME             ENDPOINTS
# keycloak-http    <none>
```

**Cause Racine** :
Les selectors du service `keycloak-http` cherchaient le label `app.kubernetes.io/instance=keycloak`, mais le pod Keycloak n'avait que `app.kubernetes.io/name=keycloak`.

**Solution** :
Script créé : `scripts/fix-keycloak-service-labels.sh`

```bash
# Ajouter le label manquant au StatefulSet
kubectl patch statefulset keycloak -n security-iam --type=merge -p '
{
  "spec": {
    "template": {
      "metadata": {
        "labels": {
          "app.kubernetes.io/instance": "keycloak"
        }
      }
    }
  }
}'

# Redémarrer le pod pour appliquer les labels
kubectl delete pod keycloak-0 -n security-iam
```

**Résultat** :
✅ Endpoints créés
✅ Ingress fonctionnel
✅ Accès via `https://keycloak.local.lab:8443/auth/admin/`

---

### Problème 2 : Keycloak utilisait H2 au lieu de PostgreSQL

**Date** : Novembre 2025
**Symptôme** : Découverte que Keycloak utilisait la base H2 embarquée malgré PostgreSQL déployé

**Diagnostic** :
```bash
kubectl describe pod keycloak-0 -n security-iam | grep DB_VENDOR
# DB_VENDOR: h2  ❌

kubectl logs keycloak-0 -n security-iam | grep database
# databaseUrl=jdbc:h2:/opt/jboss/keycloak/standalone/data/keycloak  ❌
```

**Cause Racine** :
La configuration Helm de Keycloak n'avait pas correctement appliqué les variables d'environnement PostgreSQL.

**Impact** :
- ❌ Données en H2 (non production-ready)
- ❌ PVC `keycloak-data-persistent` utilisé (2Gi)
- ❌ PostgreSQL déployé mais vide (pas utilisé)
- ❌ User admin stocké dans H2, pas dans PostgreSQL

**Solution** :
Migration complète H2 → PostgreSQL

Script créé : `scripts/migrate-keycloak-h2-to-postgresql.sh`

**Étapes de la migration** :

1. **Export des données H2**
```bash
# Export via Keycloak Admin API
curl -X GET "http://localhost:8080/auth/admin/realms/master" \
  -H "Authorization: Bearer $TOKEN" > realm-master.json
```

2. **Activation de la persistence PostgreSQL**
```bash
# ⚠️ Problème : Kubernetes interdit de modifier volumeClaimTemplates sur un StatefulSet existant
# Solution : Recréer le StatefulSet PostgreSQL

kubectl delete statefulset keycloak-postgresql -n security-iam --cascade=orphan
kubectl delete pod keycloak-postgresql-0 -n security-iam

helm upgrade --install keycloak-postgresql bitnami/postgresql \
  --namespace security-iam \
  --set primary.persistence.enabled=true \
  --set primary.persistence.size=10Gi
```

3. **Reconfiguration de Keycloak**
```bash
kubectl patch statefulset keycloak -n security-iam --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/env",
    "value": [
      {"name": "DB_VENDOR", "value": "postgres"},
      {"name": "DB_ADDR", "value": "keycloak-postgresql"},
      {"name": "DB_PORT", "value": "5432"},
      {"name": "DB_DATABASE", "value": "keycloak"},
      {"name": "DB_USER", "value": "keycloak"},
      {"name": "DB_PASSWORD", "value": "keycloak123"}
    ]
  }
]'

kubectl delete pod keycloak-0 -n security-iam
```

4. **Vérification**
```bash
kubectl logs keycloak-0 -n security-iam | grep database
# databaseUrl=jdbc:postgresql://keycloak-postgresql:5432/keycloak  ✅
# databaseProduct=PostgreSQL 18.1  ✅
```

**Résultat** :
- ✅ Keycloak utilise maintenant PostgreSQL
- ✅ PVC PostgreSQL 10Gi créé (`data-keycloak-postgresql-0`)
- ✅ Données persistantes et production-ready
- ✅ Admin user automatiquement recréé par Keycloak

**Documentation** :
- `docs/H2-TO-POSTGRESQL-MIGRATION.md`
- `docs/PERSISTENCE-ARCHITECTURE.md`

---

### Problème 3 : Kibana - Authentification Échouée

**Date** : Novembre 2025
**Symptôme** : Impossible de se connecter à Kibana avec les credentials décodés du secret

**Diagnostic** :
```bash
# Récupération des credentials du secret
kubectl get secret elasticsearch-master-credentials -n security-siem -o jsonpath='{.data.username}' | base64 -d
# elastic

kubectl get secret elasticsearch-master-credentials -n security-siem -o jsonpath='{.data.password}' | base64 -d
# 3Yk13LXAaWntSAHRv

# Test d'authentification
kubectl exec -n security-siem elasticsearch-master-0 -- \
  curl -k -u elastic:3Yk13LXAaWntSAHRv https://localhost:9200/_cluster/health

# {"error":{"type":"security_exception","reason":"unable to authenticate user [elastic]"},"status":401}  ❌
```

**Cause Racine** :
Le mot de passe dans le secret Kubernetes ne correspondait **pas** au mot de passe réellement configuré dans Elasticsearch.

**Solution** :
Réinitialisation du mot de passe Elasticsearch + synchronisation du secret

Script créé : `scripts/fix-kibana-auth.sh`

```bash
# Réinitialiser le mot de passe 'elastic'
kubectl exec -n security-siem elasticsearch-master-0 -- \
  /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b

# Récupérer le nouveau password
NEW_PASSWORD=<password_affiché>

# Mettre à jour le secret Kubernetes
kubectl create secret generic elasticsearch-master-credentials \
  --from-literal=username=elastic \
  --from-literal=password=$NEW_PASSWORD \
  --namespace security-siem \
  --dry-run=client -o yaml | kubectl apply -f -

# Redémarrer Kibana
kubectl rollout restart deployment/kibana-kibana -n security-siem
```

**Résultat** :
✅ Authentification Elasticsearch fonctionnelle
✅ Kibana accessible via `https://kibana.local.lab:8443/`
✅ Nouveaux credentials synchronisés

---

## 🌐 Configuration Réseau et Ingress

### Architecture Réseau

```
Internet / Utilisateur
         ↓
/etc/hosts (DNS local)
  keycloak.local.lab → 172.18.255.200
  vault.local.lab    → 172.18.255.200
  kibana.local.lab   → 172.18.255.200
         ↓
MetalLB Load Balancer (172.18.255.200)
         ↓
NGINX Ingress Controller (ingress-nginx-controller)
         ↓
         ├─→ Host: keycloak.local.lab → Service: keycloak-http:80  → Pod: keycloak-0
         ├─→ Host: vault.local.lab    → Service: vault:8200        → Pods: vault-{0,1,2}
         └─→ Host: kibana.local.lab   → Service: kibana-kibana:5601→ Pod: kibana-*
```

### Configuration `/etc/hosts`

Pour accéder aux services via Ingress, ajoutez ces lignes dans `/etc/hosts` :

```bash
# Récupérer l'IP MetalLB
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Ajouter dans /etc/hosts
echo "$INGRESS_IP keycloak.local.lab vault.local.lab kibana.local.lab" | sudo tee -a /etc/hosts
```

Exemple :
```
172.18.255.200 keycloak.local.lab vault.local.lab kibana.local.lab
```

### Ports et Protocoles

| Service | Port Interne | Port Ingress | Protocole |
|---------|--------------|--------------|-----------|
| Keycloak | 8080 | 8443 | HTTPS |
| Vault | 8200 | 8443 | HTTPS |
| Kibana | 5601 | 8443 | HTTPS |
| Elasticsearch | 9200 | - | HTTP (interne) |
| PostgreSQL | 5432 | - | TCP (interne) |
| Prometheus | 9090 | - | HTTP (interne) |
| Grafana | 3000 | - | HTTP (interne) |

### Services Kubernetes

```bash
# Namespace: security-iam
kubectl get svc -n security-iam
NAME                       TYPE        CLUSTER-IP       PORT(S)
keycloak-headless          ClusterIP   None             80/TCP
keycloak-http              ClusterIP   10.110.179.3     80/TCP,8443/TCP,9990/TCP
keycloak-postgresql        ClusterIP   10.99.244.42     5432/TCP
vault                      ClusterIP   10.99.132.254    8200/TCP,8201/TCP
vault-active               ClusterIP   10.100.26.242    8200/TCP,8201/TCP
vault-standby              ClusterIP   10.101.111.235   8200/TCP,8201/TCP
vault-ui                   ClusterIP   10.106.239.186   8200/TCP

# Namespace: security-siem
kubectl get svc -n security-siem
NAME                      TYPE        CLUSTER-IP       PORT(S)
elasticsearch-master      ClusterIP   10.96.128.45     9200/TCP,9300/TCP
kibana-kibana             ClusterIP   10.98.54.123     5601/TCP
prometheus-kube-state     ClusterIP   10.105.23.67     8080/TCP
prometheus-grafana        ClusterIP   10.107.89.234    80/TCP

# Namespace: ingress-nginx
kubectl get svc -n ingress-nginx
NAME                       TYPE           EXTERNAL-IP      PORT(S)
ingress-nginx-controller   LoadBalancer   172.18.255.200   80:30080/TCP,443:30443/TCP
```

---

## 📊 État Actuel du Projet

### Composants Déployés (✅ = Opérationnel)

| Composant | Namespace | Pods | Status | Accès |
|-----------|-----------|------|--------|-------|
| **Keycloak** | security-iam | 1 | ✅ Running | https://keycloak.local.lab:8443/auth/admin/ |
| **PostgreSQL (Keycloak)** | security-iam | 1 | ✅ Running | Interne (PVC 10Gi) |
| **Vault** | security-iam | 3 | ✅ Running (HA) | https://vault.local.lab:8443/ui/ |
| **Elasticsearch** | security-siem | 1 | ✅ Running | Interne (9200) |
| **Kibana** | security-siem | 1 | ✅ Running | https://kibana.local.lab:8443/ |
| **Prometheus** | security-siem | 1 | ✅ Running | Port-forward 9090 |
| **Grafana** | security-siem | 1 | ✅ Running | Port-forward 3000 |
| **Falco** | security-detection | 1 | ✅ Running | - |
| **Wazuh** | security-detection | - | ⚠️ Déployé | - |
| **Trivy Operator** | trivy-system | 1 | ✅ Running | - |
| **Gatekeeper** | gatekeeper-system | 3 | ✅ Running | - |
| **MetalLB** | metallb-system | 2 | ✅ Running | - |
| **NGINX Ingress** | ingress-nginx | 1 | ✅ Running | 172.18.255.200 |

### Persistent Volumes (PVC)

```bash
kubectl get pvc --all-namespaces

NAMESPACE       NAME                         STATUS   VOLUME     CAPACITY   STORAGECLASS
security-iam    data-keycloak-postgresql-0   Bound    pvc-001    10Gi       standard
security-iam    data-vault-0                 Bound    pvc-002    10Gi       standard
security-iam    data-vault-1                 Bound    pvc-003    10Gi       standard
security-iam    data-vault-2                 Bound    pvc-004    10Gi       standard
security-iam    keycloak-data-persistent     Bound    pvc-005    2Gi        standard  # ⚠️ Ancien (H2), peut être supprimé
```

**Total Stockage Utilisé** : 42 Gi

### Ingress Configurés

```bash
kubectl get ingress --all-namespaces

NAMESPACE       NAME               HOSTS                  ADDRESS          PORTS
security-iam    keycloak-ingress   keycloak.local.lab     172.18.255.200   80, 443
security-iam    vault-ingress      vault.local.lab        172.18.255.200   80, 443
security-siem   kibana-ingress     kibana.local.lab       172.18.255.200   80, 443
```

---

## 🔐 Accès et Credentials

### Services Accessibles via Ingress

| Service | URL | Username | Password | Notes |
|---------|-----|----------|----------|-------|
| **Keycloak** | https://keycloak.local.lab:8443/auth/admin/ | admin | admin123 | IAM / SSO |
| **Vault** | https://vault.local.lab:8443/ui/ | - | Voir vault-keys.txt | Root Token requis |
| **Kibana** | https://kibana.local.lab:8443/ | elastic | <nouveau_password> | SIEM |

### Services Accessibles via Port-Forward

```bash
# Grafana
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
# http://localhost:3000
# Username: admin
# Password: prom-operator (par défaut)

# Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090

# Elasticsearch (direct)
kubectl port-forward -n security-siem svc/elasticsearch-master 9200:9200
# http://localhost:9200

# PostgreSQL (Keycloak)
kubectl port-forward -n security-iam svc/keycloak-postgresql 5432:5432
# psql -h localhost -U keycloak -d keycloak
# Password: keycloak123
```

### Secrets Kubernetes Importants

```bash
# Credentials Elasticsearch
kubectl get secret elasticsearch-master-credentials -n security-siem -o jsonpath='{.data.username}' | base64 -d
kubectl get secret elasticsearch-master-credentials -n security-siem -o jsonpath='{.data.password}' | base64 -d

# Credentials PostgreSQL (Keycloak)
kubectl get secret keycloak-postgresql -n security-iam -o jsonpath='{.data.password}' | base64 -d

# Vault Root Token et Unseal Keys
cat vault-keys.txt  # Fichier créé lors de l'init Vault
```

### Vault - Unseal Process

Vault nécessite un **unseal** après chaque redémarrage :

```bash
# Vérifier le statut
kubectl exec -n security-iam vault-0 -- vault status
# Sealed: true  ← Nécessite unseal

# Unseal avec 3 clés (threshold)
kubectl exec -n security-iam vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n security-iam vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n security-iam vault-0 -- vault operator unseal <UNSEAL_KEY_3>

# Vérifier
kubectl exec -n security-iam vault-0 -- vault status
# Sealed: false  ✅
```

---

## 🛠️ Scripts et Outils Créés

### Scripts de Déploiement (deploy/)

| Script | Description |
|--------|-------------|
| `01-cluster-kind.sh` | Création du cluster Kind |
| `10-elasticsearch.sh` | Déploiement Elasticsearch |
| `11-kibana.sh` | Déploiement Kibana |
| `12-filebeat.sh` | Déploiement Filebeat |
| `13-prometheus.sh` | Déploiement Prometheus + Grafana |
| `20-cert-manager.sh` | Déploiement cert-manager |
| `21-keycloak.sh` | Déploiement Keycloak + PostgreSQL |
| `22-vault-dev.sh` | Déploiement Vault (mode dev) |
| `23-vault-raft.sh` | Déploiement Vault (HA Raft) |
| `24-vault-pki.sh` | Configuration Vault PKI |
| `30-falco.sh` | Déploiement Falco |
| `31-falco-sidekick.sh` | Déploiement Falco Sidekick |
| `40-gatekeeper.sh` | Déploiement OPA Gatekeeper |
| `41-trivy.sh` | Déploiement Trivy Operator |
| `50-metallb.sh` | Déploiement MetalLB |
| `51-nginx-ingress.sh` | Déploiement NGINX Ingress |
| `52-ingress-resources.sh` | Création des Ingress |
| `53-ingress-tls.sh` | Configuration TLS |

### Scripts de Correction (scripts/)

| Script | Description | Créé le |
|--------|-------------|---------|
| `fix-keycloak-service-labels.sh` | Correction labels Keycloak pour Ingress | Nov 2025 |
| `migrate-keycloak-h2-to-postgresql.sh` | Migration H2 → PostgreSQL | Nov 2025 |
| `enable-postgresql-persistence-safe.sh` | Activation persistence PostgreSQL (avec backup) | Nov 2025 |
| `fix-kibana-auth.sh` | Correction authentification Kibana | Nov 2025 |
| `verify-stack-health.sh` | Vérification complète de la stack | Nov 2025 |

### Scripts de Vérification

#### `verify-stack-health.sh`

Script complet de vérification de l'état de la stack :

```bash
./scripts/verify-stack-health.sh
```

**Vérifie** :
- ✅ Pods Keycloak, Vault, PostgreSQL, Elasticsearch, Kibana
- ✅ Services et Endpoints
- ✅ Ingress et IP MetalLB
- ✅ Statut Vault (sealed/unsealed)
- ✅ Connexion PostgreSQL
- ✅ Tables Keycloak dans PostgreSQL

**Affiche** :
- État des composants
- URLs d'accès
- Credentials par défaut
- PVC créés

---

## 📚 Documentation Créée

| Document | Description |
|----------|-------------|
| `README.md` | Documentation principale du projet |
| `docs/PERSISTENCE-ARCHITECTURE.md` | Architecture de persistence PostgreSQL |
| `docs/H2-TO-POSTGRESQL-MIGRATION.md` | Guide de migration H2 → PostgreSQL |
| `CREDENTIALS.md` | Liste des credentials de tous les services |
| `TROUBLESHOOTING.md` | Guide de dépannage |
| `KEYCLOAK-INGRESS-SETUP.md` | Configuration Ingress Keycloak |
| `KIBANA-CLEANUP.md` | Procédures de nettoyage Kibana |
| `PORT-FORWARD-GUIDE.md` | Guide port-forward pour tous les services |

---

## 🎯 Prochaines Étapes Recommandées

### Sécurité

- [ ] Rotation des credentials par défaut (admin/admin123)
- [ ] Configuration Let's Encrypt pour certificats TLS production
- [ ] Activation MFA sur Keycloak
- [ ] Configuration RBAC Kubernetes granulaire
- [ ] Scan de sécurité avec Trivy sur tous les pods

### Haute Disponibilité

- [ ] Réplication PostgreSQL (primary + replica)
- [ ] Scaling horizontal Keycloak (2-3 pods)
- [ ] Scaling Elasticsearch (3 nodes cluster)
- [ ] Configuration PodDisruptionBudget
- [ ] Backup automatique des PVC

### Monitoring

- [ ] Configuration Alertmanager (alertes Slack/Email)
- [ ] Dashboards Grafana personnalisés
- [ ] Corrélation logs Falco + Elasticsearch
- [ ] Métriques custom Prometheus
- [ ] Tracing distribué (Jaeger/Tempo)

### Intégrations

- [ ] SSO Keycloak pour Kibana
- [ ] SSO Keycloak pour Grafana
- [ ] SSO Keycloak pour Vault
- [ ] Integration Vault → Kubernetes (secrets injection)
- [ ] ArgoCD pour GitOps

### Compliance

- [ ] Scan CIS Benchmarks avec Kube-bench
- [ ] Audit Prowler (si cloud public)
- [ ] Policy OPA Gatekeeper (require labels, image scanning, etc.)
- [ ] Génération de rapports de conformité

---

## 📊 Métriques et KPI

### Ressources Cluster

```bash
# Utilisation CPU/RAM par namespace
kubectl top nodes
kubectl top pods --all-namespaces

# Nombre de pods par namespace
kubectl get pods --all-namespaces --no-headers | awk '{print $1}' | sort | uniq -c

# Stockage total utilisé
kubectl get pvc --all-namespaces -o json | jq '.items[].spec.resources.requests.storage' | awk '{sum+=$1} END {print sum " Gi"}'
```

### Disponibilité

| Service | Uptime Cible | Réplication |
|---------|--------------|-------------|
| Keycloak | 99.9% | 1 pod (à scaler) |
| Vault | 99.9% | 3 pods (HA Raft) |
| Elasticsearch | 99% | 1 node (à scaler) |
| Kibana | 99% | 1 pod |
| PostgreSQL | 99.9% | 1 pod (à répliquer) |

---

## 🔄 Changelog du Projet

### Novembre 2025

**15/11/2025** :
- ✅ Migration Keycloak : H2 → PostgreSQL
- ✅ Activation persistence PostgreSQL (10Gi PVC)
- ✅ Correction Ingress Keycloak (labels manquants)
- ✅ Correction authentification Kibana
- ✅ Création script `verify-stack-health.sh`
- ✅ Documentation complète de la migration
- ✅ Tous les services accessibles via Ingress

**12/11/2025** :
- ✅ Déploiement Ingress Keycloak, Vault, Kibana
- ✅ Configuration MetalLB + NGINX Ingress
- ⚠️ Problème endpoints Keycloak détecté

**10/11/2025** :
- ✅ Déploiement initial ELK Stack
- ✅ Déploiement Prometheus + Grafana
- ✅ Déploiement Keycloak + PostgreSQL (H2 utilisé par erreur)
- ✅ Déploiement Vault HA (Raft)

**Avant** :
- ✅ Création du cluster Kind
- ✅ Déploiement Falco, Trivy, Gatekeeper
- ✅ Configuration initiale des namespaces

---

## 🏆 Conclusion

### Points Forts du Projet

✅ **Architecture Production-Ready** :
- Keycloak + PostgreSQL avec persistence
- Vault en mode Haute Disponibilité (3 nodes Raft)
- ELK Stack pour SIEM
- Ingress + MetalLB pour accès externe

✅ **Sécurité Multi-Couches** :
- IAM (Keycloak)
- Secrets Management (Vault)
- Runtime Security (Falco)
- Vulnerability Scanning (Trivy)
- Policy Enforcement (Gatekeeper)

✅ **Observabilité Complète** :
- Logs centralisés (ELK)
- Métriques (Prometheus)
- Visualisation (Grafana + Kibana)

✅ **Infrastructure as Code** :
- Scripts Bash automatisés
- Configuration Helm
- Kubernetes manifests
- Documentation complète

### Équivalence Commerciale Démontrée

| Solution Commercial | Implémentation Open-Source | Status |
|---------------------|---------------------------|--------|
| Okta | Keycloak | ✅ Opérationnel |
| CyberArk / AWS Secrets Manager | HashiCorp Vault | ✅ Opérationnel |
| Splunk / QRadar | ELK Stack | ✅ Opérationnel |
| CrowdStrike | Falco | ✅ Opérationnel |
| Aqua / Prisma Cloud | Trivy + Gatekeeper | ✅ Opérationnel |

---

## 📞 Support et Ressources

### Documentation Officielle

- **Keycloak** : https://www.keycloak.org/documentation
- **HashiCorp Vault** : https://developer.hashicorp.com/vault/docs
- **Elasticsearch** : https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- **Kibana** : https://www.elastic.co/guide/en/kibana/current/index.html
- **Falco** : https://falco.org/docs/
- **Kubernetes** : https://kubernetes.io/docs/

### Commandes Utiles

```bash
# Vérification globale
./scripts/verify-stack-health.sh

# État des pods
kubectl get pods --all-namespaces

# Logs d'un service
kubectl logs -n security-iam keycloak-0 --tail=100

# Accès shell à un pod
kubectl exec -it -n security-iam keycloak-0 -- /bin/bash

# Redémarrer un deployment
kubectl rollout restart deployment/kibana-kibana -n security-siem

# Vérifier les Ingress
kubectl get ingress --all-namespaces

# Vérifier les PVC
kubectl get pvc --all-namespaces
```

---

**Document créé le** : 15 Novembre 2025
**Dernière mise à jour** : 15 Novembre 2025
**Version** : 1.0
**Auteur** : Z3ROX

---

> 💡 **Ce document doit être maintenu à jour** avec chaque modification importante du projet. Ajoutez une entrée dans le Changelog à chaque déploiement majeur.
