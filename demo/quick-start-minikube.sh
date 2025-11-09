#!/bin/bash
#
# Enterprise Security Stack - Quick Demo
# Déploiement rapide sur Minikube pour démonstration
#
# Prérequis: minikube, kubectl, helm
# Durée: ~10 minutes
#

set -e

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Enterprise Security Stack - Demo Rapide                 ║"
echo "║  Cloud-Native Security Architecture sur Kubernetes       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Fonction de vérification
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 n'est pas installé${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $1 installé"
}

# Vérification des prérequis
echo -e "\n${YELLOW}Vérification des prérequis...${NC}"
check_command minikube
check_command kubectl
check_command helm

# Démarrage Minikube avec ressources adaptées
echo -e "\n${YELLOW}Démarrage cluster Minikube...${NC}"
minikube start \
    --cpus=4 \
    --memory=8192 \
    --disk-size=20g \
    --driver=docker \
    --kubernetes-version=v1.28.0 \
    --addons=ingress,metrics-server

echo -e "${GREEN}✓${NC} Cluster Kubernetes prêt"
kubectl cluster-info

# Création des namespaces
echo -e "\n${YELLOW}Création des namespaces...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: security-iam
  labels:
    security-tier: identity
---
apiVersion: v1
kind: Namespace
metadata:
  name: security-detection
  labels:
    security-tier: edr
---
apiVersion: v1
kind: Namespace
metadata:
  name: security-siem
  labels:
    security-tier: logging
---
apiVersion: v1
kind: Namespace
metadata:
  name: security-network
  labels:
    security-tier: network
EOF

echo -e "${GREEN}✓${NC} Namespaces créés"

# Installation Calico (Network Policies)
echo -e "\n${YELLOW}Installation Calico CNI...${NC}"
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
echo -e "${GREEN}✓${NC} Calico installé (NetworkPolicy enabled)"

# Installation cert-manager (PKI)
echo -e "\n${YELLOW}Installation cert-manager...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
echo -e "${GREEN}✓${NC} cert-manager prêt"

# Installation ELK Stack (SIEM)
echo -e "\n${YELLOW}Installation ELK Stack (SIEM)...${NC}"
helm repo add elastic https://helm.elastic.co
helm repo update

# Elasticsearch
helm install elasticsearch elastic/elasticsearch \
    --namespace security-siem \
    --set replicas=1 \
    --set minimumMasterNodes=1 \
    --set resources.requests.memory=2Gi \
    --set persistence.enabled=false \
    --wait --timeout=10m

# Kibana
helm install kibana elastic/kibana \
    --namespace security-siem \
    --set resources.requests.memory=1Gi \
    --set persistence.enabled=false \
    --wait --timeout=10m

echo -e "${GREEN}✓${NC} ELK Stack déployé"

# Installation Prometheus + Grafana (Observability)
echo -e "\n${YELLOW}Installation Prometheus + Grafana...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace security-siem \
    --set prometheus.prometheusSpec.resources.requests.memory=1Gi \
    --set grafana.adminPassword=admin123 \
    --wait --timeout=10m

echo -e "${GREEN}✓${NC} Prometheus + Grafana déployés"

# Installation Keycloak (IAM)
echo -e "\n${YELLOW}Installation Keycloak (IAM)...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install keycloak bitnami/keycloak \
    --namespace security-iam \
    --set auth.adminUser=admin \
    --set auth.adminPassword=admin123 \
    --set postgresql.enabled=true \
    --wait --timeout=10m

echo -e "${GREEN}✓${NC} Keycloak déployé"

# Installation HashiCorp Vault (Secrets)
echo -e "\n${YELLOW}Installation HashiCorp Vault...${NC}"
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
    --namespace security-iam \
    --set server.dev.enabled=true \
    --wait --timeout=5m

echo -e "${GREEN}✓${NC} Vault déployé (mode dev)"

# Déploiement sample app avec NetworkPolicy
echo -e "\n${YELLOW}Déploiement application test avec NetworkPolicy...${NC}"
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: demo-app
  labels:
    app: demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: demo-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: demo-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: api
    spec:
      containers:
      - name: api
        image: httpd:2.4-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: demo-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: demo-app
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-to-frontend
  namespace: demo-app
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 80
EOF

echo -e "${GREEN}✓${NC} Application test déployée avec NetworkPolicies"

# Attente stabilisation
echo -e "\n${YELLOW}Attente stabilisation des pods...${NC}"
kubectl wait --for=condition=Ready pods --all -n demo-app --timeout=300s

# Affichage résumé
echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Déploiement terminé avec succès ! ✓             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "\n${YELLOW}📊 Composants déployés:${NC}"
echo -e "${GREEN}✓${NC} IAM (Keycloak) - namespace: security-iam"
echo -e "${GREEN}✓${NC} Secrets Management (Vault) - namespace: security-iam"
echo -e "${GREEN}✓${NC} SIEM (ELK Stack) - namespace: security-siem"
echo -e "${GREEN}✓${NC} Observability (Prometheus+Grafana) - namespace: security-siem"
echo -e "${GREEN}✓${NC} Network Security (Calico) - cluster-wide"
echo -e "${GREEN}✓${NC} PKI (cert-manager) - cluster-wide"
echo -e "${GREEN}✓${NC} Demo App avec NetworkPolicies - namespace: demo-app"

echo -e "\n${YELLOW}🌐 Accès aux interfaces:${NC}"
echo ""
echo "Pour accéder aux UIs, ouvrez des terminaux séparés et lancez:"
echo ""
echo -e "${GREEN}# Kibana (SIEM)${NC}"
echo "kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
echo "→ http://localhost:5601"
echo ""
echo -e "${GREEN}# Grafana (Monitoring)${NC}"
echo "kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
echo "→ http://localhost:3000 (admin/admin123)"
echo ""
echo -e "${GREEN}# Keycloak (IAM)${NC}"
echo "kubectl port-forward -n security-iam svc/keycloak 8080:80"
echo "→ http://localhost:8080 (admin/admin123)"
echo ""
echo -e "${GREEN}# Vault (Secrets)${NC}"
echo "kubectl port-forward -n security-iam svc/vault 8200:8200"
echo "→ http://localhost:8200 (token: root)"
echo ""

echo -e "\n${YELLOW}🔍 Commandes utiles:${NC}"
echo ""
echo -e "${GREEN}# Vérifier les NetworkPolicies${NC}"
echo "kubectl get networkpolicies -n demo-app"
echo ""
echo -e "${GREEN}# Voir les pods de sécurité${NC}"
echo "kubectl get pods -n security-iam"
echo "kubectl get pods -n security-siem"
echo ""
echo -e "${GREEN}# Tester l'isolation réseau${NC}"
echo "kubectl exec -n demo-app deploy/frontend -- wget -O- backend:8080"
echo ""
echo -e "${GREEN}# Logs Elasticsearch${NC}"
echo "kubectl logs -n security-siem -l app=elasticsearch --tail=50"
echo ""

echo -e "\n${YELLOW}🧪 Tests de sécurité:${NC}"
cat <<'TESTS'

# Test 1: Vérifier que les NetworkPolicies bloquent le trafic non autorisé
kubectl run test-pod --rm -i --tty --image=busybox -n demo-app -- sh
# Dans le pod, essayer de contacter backend directement (doit échouer car pas label frontend)
wget -O- backend:8080

# Test 2: Vérifier les secrets Vault
kubectl exec -n security-iam vault-0 -- vault status

# Test 3: Accéder aux dashboards Grafana
# Port-forward puis naviguer vers http://localhost:3000
# Dashboards pré-configurés pour Kubernetes

# Test 4: Vérifier les certificats cert-manager
kubectl get certificates --all-namespaces

TESTS

echo -e "\n${YELLOW}📚 Architecture déployée:${NC}"
cat <<'ARCH'

┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ IAM Layer (Keycloak + Vault)                          │  │
│  │  • SSO / OIDC                                          │  │
│  │  • Secrets Management                                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↓                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Network Security (Calico + NetworkPolicy)             │  │
│  │  • Micro-segmentation                                  │  │
│  │  • Zero Trust Network                                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↓                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Workloads (demo-app)                                   │  │
│  │  Frontend ←→ Backend (via NetworkPolicy)             │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↓                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Observability (SIEM + Monitoring)                      │  │
│  │  • ELK Stack (logs)                                    │  │
│  │  • Prometheus + Grafana (metrics)                      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘

ARCH

echo -e "\n${GREEN}✨ Équivalences avec solutions commerciales:${NC}"
cat <<'EQUIV'

┌──────────────────────────┬───────────────────────────┐
│ Composant Open-Source    │ Équivalent Commercial     │
├──────────────────────────┼───────────────────────────┤
│ Keycloak + RBAC          │ Okta, Azure AD            │
│ ELK Stack                │ Splunk, QRadar            │
│ Calico + NetworkPolicy   │ Palo Alto, Zscaler        │
│ Vault                    │ AWS Secrets Manager       │
│ cert-manager             │ Venafi, DigiCert          │
│ Prometheus + Grafana     │ Datadog, New Relic        │
└──────────────────────────┴───────────────────────────┘

EQUIV

echo -e "\n${YELLOW}📖 Documentation complète:${NC}"
echo "Voir README.md et docs/equivalences.md pour détails"

echo -e "\n${YELLOW}🧹 Pour nettoyer la démo:${NC}"
echo "minikube delete"

echo -e "\n${GREEN}Demo prête ! 🚀${NC}\n"
