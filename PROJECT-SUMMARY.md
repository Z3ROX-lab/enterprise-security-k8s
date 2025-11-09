# Enterprise Security Stack - Vue d'Ensemble du Projet

## 🎯 Objectif

Stack de cybersécurité complète pour Kubernetes, démontrant l'équivalence fonctionnelle entre solutions open-source et commerciales (CrowdStrike, Splunk, Okta, Zscaler, etc.).

---

## 📁 Structure du Projet

```
enterprise-security-k8s/
├── terraform/                          # Infrastructure as Code
│   ├── main.tf                         # Orchestration principale
│   ├── modules/
│   │   ├── kind-cluster/              # Cluster Kubernetes (Kind)
│   │   ├── monitoring/                # ELK + Prometheus/Grafana
│   │   └── security-stack/            # IAM, EDR, Network Security
│   └── environments/
│       ├── local/                     # Config environnement local
│       └── dev/                       # Config environnement dev
│
├── ansible/                            # Configuration Management
│   ├── ansible.cfg                    # Configuration Ansible
│   ├── inventory/                     # Inventaires
│   ├── playbooks/
│   │   └── site.yml                   # Playbook principal
│   └── roles/
│       ├── cluster-hardening/         # PSS, Quotas, Limits
│       ├── network-policies/          # Zero Trust networking
│       └── security-automation/       # SOAR playbooks
│
├── scripts/                            # Scripts d'automatisation
│   ├── deploy-all.sh                  # Déploiement complet
│   └── check-environment.sh           # Vérification prérequis
│
├── demo/                               # Démo rapide Minikube
│   └── quick-start-minikube.sh
│
├── docs/                               # Documentation
│   ├── architecture.md                # Architecture technique détaillée
│   ├── equivalences.md                # Mapping OSS ↔ Commercial
│   ├── WINDOWS11-SETUP.md             # Guide Windows 11 complet
│   └── pitch-entretien-architecte-cyber.md
│
├── helm-charts/                        # Helm charts (futurs customs)
│   ├── custom/
│   │   ├── security-iam/
│   │   ├── security-detection/
│   │   └── security-network/
│   └── values/
│
└── README.md                           # Documentation principale
```

---

## 🛠️ Stack Technique Déployée

### Infrastructure (Terraform)
- **Kind Cluster** : 4 nodes (1 control-plane + 3 workers)
- **Calico CNI** : NetworkPolicy enforcement
- **Ingress NGINX** : Layer 7 routing
- **cert-manager** : PKI automation

### IAM & Secrets (`security-iam` namespace)
- **Keycloak** : SSO, OIDC, SAML
- **HashiCorp Vault** : Secrets management (dev ou Raft HA)
- **PostgreSQL** : Backend Keycloak

### Detection & Response (`security-detection` namespace)
- **Falco** : Runtime security (eBPF)
  - 10+ custom rules (crypto-mining, reverse shell, drift, etc.)
  - Falcosidekick export vers Elasticsearch
- **Wazuh** : HIDS + compliance scanning
  - Manager + Indexer + Dashboard
- **OPA Gatekeeper** : Policy enforcement
  - ConstraintTemplates Rego

### Observability & SIEM (`security-siem` namespace)
- **ELK Stack** :
  - Elasticsearch (indexing)
  - Kibana (visualization)
  - Filebeat (log shipping)
- **Prometheus Stack** :
  - Prometheus (metrics)
  - Grafana (dashboards)
  - Alertmanager (alerting)

### Supply Chain Security (`trivy-system` namespace)
- **Trivy Operator** : Vulnerability scanning
  - VulnerabilityReports
  - ConfigAuditReports

### Network Security (cluster-wide)
- **NetworkPolicies** :
  - Default deny-all (tous namespaces)
  - Allow DNS (kube-system)
  - Allow metrics scraping (Prometheus)
  - Allow logs (Elasticsearch)

### Hardening (Ansible)
- **Pod Security Standards** : Restricted/Baseline/Privileged par namespace
- **ResourceQuotas** : CPU, Memory, Pods limits
- **LimitRanges** : Default resource limits
- **ServiceAccount** : Auto-mount disabled

---

## 🚀 Déploiement

### Méthode 1 : Automatique (Recommandé)
```bash
./scripts/check-environment.sh      # Vérifier prérequis
./scripts/deploy-all.sh             # Déploiement complet
```

### Méthode 2 : Manuel
```bash
cd terraform && terraform apply
cd ../ansible && ansible-playbook playbooks/site.yml
```

### Méthode 3 : Demo Rapide
```bash
cd demo && ./quick-start-minikube.sh
```

**Durée** : 30-40 minutes (méthode 1 et 2), 10 minutes (méthode 3)

---

## 📊 Ressources Requises

**Minimum** :
- CPU : 4 cores
- RAM : 8 GB
- Disk : 20 GB
- OS : Windows 11 (WSL2) ou Linux

**Recommandé** :
- CPU : 6+ cores
- RAM : 12+ GB
- Disk : 30 GB

---

## 🌐 Accès aux Interfaces

Après déploiement, utiliser `kubectl port-forward` :

| Service | Namespace | Port | URL | Credentials |
|---------|-----------|------|-----|-------------|
| Grafana | security-siem | 3000:80 | http://localhost:3000 | admin/admin123 |
| Kibana | security-siem | 5601:5601 | http://localhost:5601 | - |
| Prometheus | security-siem | 9090:9090 | http://localhost:9090 | - |
| Keycloak | security-iam | 8080:80 | http://localhost:8080 | admin/admin123 |
| Vault | security-iam | 8200:8200 | http://localhost:8200 | root (dev) |
| Falco UI | security-detection | 2802:2802 | http://localhost:2802 | - |
| Wazuh | security-detection | 5443:5601 | https://localhost:5443 | admin/SecretPassword |

---

## 🧪 Tests et Validation

### Test 1 : NetworkPolicies
```bash
kubectl run test-pod --rm -it --image=busybox -n demo-app -- sh
# Essayer de contacter backend (doit échouer si pas label frontend)
wget -O- http://backend.demo-app:8080
```

### Test 2 : Falco Alerts
```bash
# Déclencher une alerte
kubectl exec -n demo-app deploy/frontend -- cat /etc/shadow

# Voir l'alerte
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=20
```

### Test 3 : Vulnerabilities Trivy
```bash
kubectl get vulnerabilityreports --all-namespaces
kubectl get vulnerabilityreport <name> -n <ns> -o yaml
```

### Test 4 : Metrics Prometheus
```bash
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# Ouvrir http://localhost:9090
# Query : kube_pod_status_phase{phase="Running"}
```

---

## 📈 Métriques de Performance

**Cluster Kind** : 4 nodes
**Pods totaux** : ~40
**CPU utilisé** : ~4 cores
**Memory utilisée** : ~9 Gi

**Components breakdown** :
- Elasticsearch : 1 core, 2Gi
- Prometheus : 0.5 core, 1Gi
- Grafana : 0.1 core, 256Mi
- Keycloak : 0.5 core, 1Gi
- Vault : 0.25 core, 256Mi
- Falco : 0.2 core, 512Mi (DaemonSet)
- Wazuh : 0.5 core, 1Gi

---

## 🔄 CI/CD Intégration (Future)

Prêt pour intégration avec :
- **ArgoCD** : GitOps continuous deployment
- **Flux** : Alternative GitOps
- **GitHub Actions** : Pipeline CI
- **GitLab CI** : Pipeline CI alternative

---

## 🛡️ Compliance Frameworks

Stack alignée avec :
- **CIS Kubernetes Benchmark** : kube-bench scanning
- **ANSSI Cloud Security** : Hardening appliqué
- **NIS2** : Incident response automation
- **ISO 27001** : Audit logs complets
- **RGPD** : Data protection practices

---

## 🎓 Use Cases

### 1. Portfolio Technique
Démonstration de maîtrise :
- Infrastructure as Code (Terraform)
- Configuration Management (Ansible)
- Kubernetes Security
- SIEM & EDR
- Zero Trust Networking

### 2. Formation & Apprentissage
Environnement complet pour apprendre :
- Cloud-native security
- Kubernetes hardening
- Detection engineering (Falco rules)
- Policy as Code (OPA)
- Supply chain security

### 3. Lab Personnel
Sandbox pour tester :
- Nouvelles vulnérabilités
- Security tools
- Network policies
- Runtime detection rules

### 4. Base pour Production
Template réutilisable pour :
- Clusters de développement sécurisés
- Proof of Concept clients
- Migration vers cloud (GKE, EKS, AKS)

---

## 📚 Documentation Complète

- **[README.md](README.md)** : Vue d'ensemble et quick start
- **[docs/architecture.md](docs/architecture.md)** : Architecture technique détaillée
- **[docs/equivalences.md](docs/equivalences.md)** : Mapping OSS ↔ Commercial
- **[docs/WINDOWS11-SETUP.md](docs/WINDOWS11-SETUP.md)** : Guide complet Windows 11
- **[docs/pitch-entretien-architecte-cyber.md](docs/pitch-entretien-architecte-cyber.md)** : Interview prep

---

## 🔧 Troubleshooting

### Pods en CrashLoopBackOff
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Cluster lent
Augmenter ressources Docker Desktop :
- Settings → Resources
- CPU : 6+, Memory : 12+ GB

### NetworkPolicy bloque tout
Vérifier les labels :
```bash
kubectl get networkpolicies -n <namespace> -o yaml
kubectl describe networkpolicy <policy-name> -n <namespace>
```

---

## 🧹 Nettoyage

### Supprimer workloads uniquement
```bash
cd terraform
terraform destroy -target=module.security_stack -auto-approve
terraform destroy -target=module.monitoring -auto-approve
```

### Supprimer tout
```bash
cd terraform
terraform destroy -auto-approve
# ou
kind delete cluster --name enterprise-security
```

---

## 🚀 Prochaines Étapes

### Phase 1 : Production Readiness
- [ ] Persistence (PVCs pour Elasticsearch, Prometheus, Vault)
- [ ] High Availability (Replicas 3+)
- [ ] Backup/Restore (Velero)
- [ ] Secrets sécurisés (Vault KMS auto-unseal)

### Phase 2 : Features Avancées
- [ ] ArgoCD GitOps
- [ ] Istio Service Mesh
- [ ] Cosign image signing
- [ ] SBOM generation (Syft)
- [ ] Chaos Engineering (Litmus)

### Phase 3 : Multi-Cluster
- [ ] Cluster Federation
- [ ] Prometheus Federation
- [ ] Centralized logging
- [ ] Multi-region DR

---

## 📊 Statistiques Projet

- **Fichiers Terraform** : 8
- **Playbooks Ansible** : 5
- **Scripts Shell** : 3
- **Documentation** : 5 fichiers
- **Custom Falco Rules** : 10+
- **NetworkPolicies** : 5+
- **Namespaces** : 7
- **Helm Releases** : 10+

---

## 🌟 Highlights Techniques

### 1. Infrastructure as Code
- Terraform modules réutilisables
- Environnements multiples (local, dev, prod)
- Outputs pour intégration

### 2. Security by Default
- Default deny NetworkPolicies
- Pod Security Standards enforced
- Resource quotas & limits
- Immutable infrastructure

### 3. Observability Complete
- Logs centralisés (ELK)
- Metrics & dashboards (Prometheus/Grafana)
- Alerting (Alertmanager)
- Distributed tracing ready

### 4. Detection Engineering
- Custom Falco rules (10+)
- MITRE ATT&CK mapped
- Real-time alerting (< 5s)
- SOAR automation ready

### 5. Compliance Automation
- CIS benchmarks (kube-bench)
- Vulnerability scanning (Trivy)
- Policy enforcement (OPA)
- Audit logging complet

---

## 🎯 Équivalences Commerciales

| Open-Source (ce projet) | Commercial | Économie/an |
|------------------------|------------|-------------|
| Keycloak | Okta | ~$15k |
| Wazuh + Falco | CrowdStrike | ~$50k |
| ELK Stack | Splunk | ~$100k |
| Calico + NetworkPolicy | Palo Alto Prisma | ~$30k |
| Vault | AWS Secrets Manager | ~$5k |
| Trivy Operator | Snyk | ~$10k |
| **Total** | **$210k+/an** | **$0 (infra uniquement)** |

---

## 📞 Support & Communauté

- **Issues** : GitHub Issues
- **Discussions** : GitHub Discussions
- **Contributions** : Pull Requests bienvenues
- **Documentation** : Voir `docs/`

---

## 📄 Licence

MIT License - Open Source et libre d'utilisation

---

**Auteur** : Z3ROX
**Projet** : https://github.com/Z3ROX-lab/enterprise-security-k8s
**Dernière mise à jour** : 2025-01
