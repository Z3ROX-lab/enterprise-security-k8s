# Architecture Technique Détaillée

## Vue d'ensemble

Cette stack de cybersécurité est construite sur les principes modernes de **Cloud-Native Security**, **Zero Trust Architecture** et **Defense in Depth**. Elle implémente l'équivalent open-source des solutions commerciales entreprise (CrowdStrike, Splunk, Okta, Zscaler, etc.).

---

## 🏗️ Architecture Globale

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Kind)                     │
│                    4 nodes (1 control + 3 workers)               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Ingress Layer                            │ │
│  │  NGINX Ingress Controller → mTLS → cert-manager           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                 IAM & Identity Layer                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │  Keycloak    │  │  HashiCorp   │  │  cert-manager   │  │ │
│  │  │  (SSO/OIDC)  │  │    Vault     │  │     (PKI)       │  │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │ │
│  │        Namespace: security-iam                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Detection & Response Layer (EDR/XDR)          │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │    Falco     │  │    Wazuh     │  │  OPA Gatekeeper │  │ │
│  │  │  (Runtime)   │  │   (HIDS)     │  │    (Policies)   │  │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │ │
│  │        Namespace: security-detection                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                Network Security Layer                       │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │  Calico CNI + NetworkPolicy Engine                    │  │ │
│  │  │  - Default Deny All                                   │  │ │
│  │  │  - Micro-segmentation by namespace/labels            │  │ │
│  │  │  - eBPF dataplane                                     │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Workload Layer                             │ │
│  │  ┌────────────┐  ┌────────────┐  ┌─────────────────────┐  │ │
│  │  │  Frontend  │→→│  Backend   │→→│  Database / Cache   │  │ │
│  │  │   Pods     │  │    Pods    │  │       Pods          │  │ │
│  │  └────────────┘  └────────────┘  └─────────────────────┘  │ │
│  │        Namespace: demo-app (avec NetworkPolicies)          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │            Observability & SIEM Layer                       │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │     ELK      │  │  Prometheus  │  │    Grafana      │  │ │
│  │  │   (SIEM)     │  │  (Metrics)   │  │  (Dashboards)   │  │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │ │
│  │  ┌──────────────┐  ┌──────────────┐                        │ │
│  │  │  Filebeat    │  │ Alertmanager │                        │ │
│  │  │  (Shipper)   │  │   (Alerts)   │                        │ │
│  │  └──────────────┘  └──────────────┘                        │ │
│  │        Namespace: security-siem                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Supply Chain Security Layer                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │    Trivy     │  │   Cosign     │  │     SBOM        │  │ │
│  │  │  Operator    │  │  (Signing)   │  │   Generator     │  │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │ │
│  │        Namespace: trivy-system                              │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Composants Détaillés

### 1. IAM & Identity Management

#### Keycloak (SSO/OIDC Provider)
- **Protocoles** : OIDC, SAML 2.0, OAuth 2.0
- **Backend** : PostgreSQL
- **MFA** : TOTP support
- **Déploiement** : Helm (bitnami/keycloak) dans security-iam

**Équivalent Commercial** : Okta, Azure AD, Auth0

#### HashiCorp Vault (Secrets Management)
- **Storage** : Raft HA ou dev mode
- **Auth Methods** : Kubernetes, OIDC, AppRole
- **Secret Engines** : KV v2, Database, PKI
- **Déploiement** : Helm (hashicorp/vault) dans security-iam

**Équivalent Commercial** : AWS Secrets Manager, Azure Key Vault

#### cert-manager (PKI Automation)
- **Issuers** : SelfSigned, CA, Let's Encrypt
- **CRDs** : Certificate, Issuer, ClusterIssuer
- **Déploiement** : Helm (jetstack/cert-manager)

**Équivalent Commercial** : Venafi, DigiCert

---

### 2. Detection & Response (EDR/XDR)

#### Falco (Runtime Security)
- **Driver** : eBPF probes (kernel syscalls)
- **Rules** : 10+ custom rules (crypto-mining, reverse shell, etc.)
- **Export** : Falcosidekick → Elasticsearch + WebUI
- **Déploiement** : Helm (falcosecurity/falco) dans security-detection

**Rules Personnalisées** : `terraform/modules/security-stack/falco-rules/custom-rules.yaml`
- Crypto-mining detection
- Reverse shell attempts
- Container drift detection
- Kubernetes secret access
- Privilege escalation

**Équivalent Commercial** : CrowdStrike Falcon, Sysdig Secure

#### Wazuh (Host Intrusion Detection)
- **Manager** : Collecte et corrélation
- **Indexer** : Elasticsearch fork
- **Dashboard** : Kibana fork
- **Agents** : DaemonSet sur chaque node
- **Déploiement** : Helm (wazuh/wazuh) dans security-detection

**Capacités** :
- File Integrity Monitoring
- Rootkit detection
- CIS compliance scanning
- MITRE ATT&CK mapping

**Équivalent Commercial** : Carbon Black, Trend Micro

#### OPA Gatekeeper (Policy Enforcement)
- **Architecture** : Validating Admission Webhook
- **Language** : Rego policies
- **Templates** : K8sRequiredLabels, K8sBlockPrivileged, etc.
- **Déploiement** : Helm (gatekeeper/gatekeeper)

**Équivalent Commercial** : Prisma Cloud, Aqua Security

---

### 3. Network Security

#### Calico CNI + NetworkPolicy Engine
- **Dataplane** : eBPF (kernel bypass for performance)
- **Policies** : Default deny-all + explicit allows
- **Micro-segmentation** : Par namespace et labels
- **Déploiement** : Manifest YAML via Terraform

**NetworkPolicies Implémentées** : `ansible/roles/network-policies/`
- default-deny-all (tous namespaces)
- allow-dns (kube-system:53)
- allow-logs-to-elasticsearch
- allow-prometheus-scraping

**Équivalent Commercial** : Palo Alto Prisma, Zscaler, Cisco ACI

---

### 4. Observability & SIEM

#### ELK Stack (Elasticsearch + Kibana + Filebeat)
- **Elasticsearch** : Indexing et stockage logs
- **Kibana** : Visualisation et threat hunting (KQL)
- **Filebeat** : Log shipping (DaemonSet)
- **Déploiement** : Helm (elastic/*) dans security-siem

**Index Patterns** :
- `filebeat-*` : Logs Kubernetes
- `falco-*` : Alertes Falco
- `wazuh-alerts-*` : Alertes Wazuh

**Équivalent Commercial** : Splunk Enterprise, IBM QRadar

#### Prometheus + Grafana
- **Prometheus** : Metrics collection (9090)
- **Grafana** : Dashboards et alerting (3000)
- **Alertmanager** : Notification routing
- **Déploiement** : Helm (prometheus-community/kube-prometheus-stack)

**Dashboards** :
- Security Overview (custom)
- Kubernetes Resources
- Falco Alerts
- NetworkPolicy Violations

**Équivalent Commercial** : Datadog, New Relic

---

### 5. Supply Chain Security

#### Trivy Operator
- **Fonction** : Continuous vulnerability scanning
- **CRDs** : VulnerabilityReport, ConfigAuditReport
- **Database** : CVE database (auto-update)
- **Déploiement** : Helm (aquasecurity/trivy-operator)

**Équivalent Commercial** : Snyk, JFrog Xray

---

## 🔄 Flux de Données Critiques

### Flux 1 : Authentification
```
User → Keycloak (OIDC) → MFA → JWT token → Application
Logs → Filebeat → Elasticsearch → Kibana
```

### Flux 2 : Détection de Menace
```
Attacker → exec shell → Kernel → Falco eBPF → Alert
→ Falcosidekick → Elasticsearch + Alertmanager → SOC
Timeline: < 5 secondes
```

### Flux 3 : Secrets Rotation
```
App → Vault API → Dynamic credentials → PostgreSQL
TTL expires → Auto-rotation → New credentials
```

---

## 🛡️ Security Hardening

### Pod Security Standards (PSS)
- **Restricted** : security-iam, demo-app
- **Baseline** : security-siem
- **Privileged** : security-detection (eBPF requis)

### Resource Quotas
- CPU : 4 cores request, 8 cores limit par namespace
- Memory : 8Gi request, 16Gi limit
- Pods : Max 20 par namespace

### NetworkPolicy Zero Trust
- Default deny all ingress/egress
- Allow explicite uniquement

---

## 📈 Métriques de Performance

**Environnement** : Windows 11 + WSL2 + Docker Desktop
**Cluster** : Kind 4 nodes (1 CP + 3 workers)

```
Ressources Totales Utilisées:
- CPU : ~4 cores
- Memory : ~9 Gi
- Pods : ~40 total
```

---

## 🚀 Déploiement

### Automatique (Recommandé)
```bash
./scripts/deploy-all.sh
```

### Manuel
```bash
cd terraform && terraform apply
cd ../ansible && ansible-playbook playbooks/site.yml
```

**Durée** : 30-40 minutes

---

## 🔧 Infrastructure as Code

**Terraform** : `terraform/` - Infrastructure et Helm releases
**Ansible** : `ansible/` - Configuration et hardening
**Scripts** : `scripts/` - Orchestration

---

## 📚 Références

- CNCF Security Whitepaper
- NSA Kubernetes Hardening Guide
- Falco Rules Documentation
- OPA Gatekeeper Library
- Calico NetworkPolicy Documentation

---

**Auteur** : Z3ROX
**Dernière mise à jour** : 2025-01
