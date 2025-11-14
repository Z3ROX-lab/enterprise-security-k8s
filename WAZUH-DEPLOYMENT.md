# Guide de Déploiement Wazuh

## Contexte

Wazuh ne fournit plus de chart Helm officiel public. Ils utilisent maintenant des **manifests Kubernetes** déployables via **Kustomize**.

**Wazuh** est désactivé par défaut dans le module `security-stack` car il nécessite un déploiement manuel.

---

## Option 1 : Déploiement Rapide avec Kustomize (Recommandé)

### Prérequis

```bash
# Vérifier que kubectl et kustomize sont installés
kubectl version --client
kubectl kustomize --help
```

### Déploiement

```bash
# 1. Créer le namespace
kubectl create namespace security-detection

# 2. Déployer Wazuh avec Kustomize (version single-node pour dev/test)
kubectl apply -k https://github.com/wazuh/wazuh-kubernetes//deployments/kubernetes/

# Alternative : Cloner le repo et personnaliser
git clone https://github.com/wazuh/wazuh-kubernetes.git
cd wazuh-kubernetes/deployments/kubernetes

# Éditer kustomization.yaml si nécessaire
nano kustomization.yaml

# Déployer
kubectl apply -k .
```

### Vérification

```bash
# Vérifier les pods
kubectl get pods -n wazuh

# Attendre que tous les pods soient Running (peut prendre 5-10 minutes)
watch -n 3 'kubectl get pods -n wazuh'
```

**Pods attendus** :
- `wazuh-manager-master-0` (StatefulSet)
- `wazuh-indexer-0` (StatefulSet)
- `wazuh-dashboard-xxxxx` (Deployment)

---

## Option 2 : Déploiement avec Helm (Chart Community)

Bien que Wazuh n'ait plus de chart officiel, il existe un chart community :

```bash
# Ajouter le repository community
helm repo add wazuh https://wazuh.github.io/wazuh-helm

# Note: Ce repo peut ne pas être maintenu à jour
# Vérifier la disponibilité
helm search repo wazuh

# Déployer (si disponible)
helm install wazuh wazuh/wazuh \
  --namespace security-detection \
  --create-namespace \
  --set wazuh-manager.replicas=1 \
  --set wazuh-indexer.replicas=1 \
  --set wazuh-dashboard.replicas=1
```

---

## Option 3 : Déploiement Manuel avec Manifests

### Étape 1 : Cloner le Repository

```bash
cd ~/
git clone https://github.com/wazuh/wazuh-kubernetes.git
cd wazuh-kubernetes
```

### Étape 2 : Choisir le Type de Déploiement

Wazuh propose plusieurs configurations :

```bash
cd deployments/kubernetes

ls -la
# single-node/     - Pour dev/test (1 nœud de chaque)
# multi-node/      - Pour production (3+ nœuds Indexer)
```

### Étape 3 : Déployer

```bash
# Pour dev/test (single-node)
cd single-node
kubectl apply -f .

# Pour production (multi-node)
cd multi-node
kubectl apply -f .
```

### Étape 4 : Vérifier

```bash
kubectl get all -n wazuh
kubectl logs -n wazuh wazuh-manager-master-0
```

---

## Configuration du Namespace

Si vous utilisez le namespace `security-detection` défini dans Terraform :

```bash
# 1. Créer le namespace avec les labels Terraform
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: security-detection
  labels:
    security-tier: edr
    pod-security.kubernetes.io/enforce: privileged
EOF

# 2. Déployer Wazuh dans ce namespace
kubectl apply -k https://github.com/wazuh/wazuh-kubernetes//deployments/kubernetes/ -n security-detection
```

---

## Accès au Dashboard Wazuh

### Port-Forward

```bash
# Dashboard (Kibana fork)
kubectl port-forward -n wazuh svc/wazuh-dashboard 5443:5601

# Ou si namespace security-detection
kubectl port-forward -n security-detection svc/wazuh-dashboard 5443:5601
```

**Accès** : https://localhost:5443

### Credentials Par Défaut

- **Username** : `admin`
- **Password** : `SecretPassword`

**⚠️ IMPORTANT** : Changez ces credentials en production !

```bash
# Se connecter au pod Manager
kubectl exec -it -n wazuh wazuh-manager-master-0 -- bash

# Changer le mot de passe API
/var/ossec/bin/wazuh-passwords-tool
```

---

## Configuration de l'Intégration Elasticsearch (ELK)

Pour envoyer les alertes Wazuh vers votre stack ELK :

### Étape 1 : Configurer le Manager

```bash
kubectl exec -it -n wazuh wazuh-manager-master-0 -- bash

# Éditer la configuration
vi /var/ossec/etc/ossec.conf
```

Ajouter :

```xml
<integration>
  <name>elasticsearch</name>
  <hook_url>http://elasticsearch-master.security-siem:9200</hook_url>
  <level>3</level>
  <alert_format>json</alert_format>
</integration>
```

### Étape 2 : Redémarrer le Manager

```bash
kubectl rollout restart statefulset/wazuh-manager-master -n wazuh
```

---

## Configuration des Agents Wazuh

Pour monitorer les nœuds Kubernetes :

### Déployer l'Agent comme DaemonSet

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: wazuh-agent
  namespace: wazuh
spec:
  selector:
    matchLabels:
      app: wazuh-agent
  template:
    metadata:
      labels:
        app: wazuh-agent
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: wazuh-agent
        image: wazuh/wazuh-agent:4.7.0
        env:
        - name: WAZUH_MANAGER
          value: "wazuh-manager-master-0.wazuh-cluster.wazuh.svc.cluster.local"
        - name: WAZUH_AGENT_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          privileged: true
        volumeMounts:
        - name: host
          mountPath: /host
          readOnly: true
      volumes:
      - name: host
        hostPath:
          path: /
EOF
```

---

## Intégration avec Falco

Envoyer les alertes Falco vers Wazuh :

### Via Filebeat (Recommandé)

Filebeat collecte les logs Falco et les envoie à Wazuh Indexer :

```yaml
# Configurer Filebeat output
output.elasticsearch:
  hosts: ["wazuh-indexer.wazuh:9200"]
  username: "admin"
  password: "SecretPassword"
  index: "falco-%{+yyyy.MM.dd}"
```

### Via Falcosidekick

Modifier le Helm release Falco pour ajouter Wazuh comme output :

```hcl
set {
  name  = "falcosidekick.config.webhook.address"
  value = "http://wazuh-manager-master-0.wazuh:55000"
}
```

---

## Ressources Requises

### Minimum (Single-Node)

- **CPU** : 4 cores
- **RAM** : 8 GB
- **Storage** : 20 GB

**Pods** :
- Wazuh Manager : 2 CPU, 4 GB RAM
- Wazuh Indexer : 1 CPU, 2 GB RAM
- Wazuh Dashboard : 0.5 CPU, 1 GB RAM

### Recommandé (Production Multi-Node)

- **CPU** : 12+ cores
- **RAM** : 24+ GB
- **Storage** : 100+ GB

**Pods** :
- Wazuh Manager : 3 replicas × (2 CPU, 4 GB RAM)
- Wazuh Indexer : 3 replicas × (2 CPU, 4 GB RAM)
- Wazuh Dashboard : 2 replicas × (0.5 CPU, 1 GB RAM)

---

## Dépannage

### Pods en CrashLoopBackOff

**Cause** : Ressources insuffisantes ou configuration incorrecte

**Solution** :

```bash
# Vérifier les logs
kubectl logs -n wazuh wazuh-manager-master-0
kubectl logs -n wazuh wazuh-indexer-0

# Augmenter les ressources
kubectl edit statefulset/wazuh-manager-master -n wazuh
```

### Indexer ne démarre pas

**Cause** : Problème de discovery des nœuds

**Solution** :

```bash
kubectl exec -it -n wazuh wazuh-indexer-0 -- bash

# Vérifier la configuration cluster
cat /usr/share/wazuh-indexer/config/opensearch.yml

# Vérifier les logs
tail -f /var/log/wazuh-indexer/wazuh-cluster.log
```

### Dashboard ne se connecte pas

**Cause** : Indexer pas prêt ou credentials incorrects

**Solution** :

```bash
# Vérifier que l'Indexer est Ready
kubectl get pods -n wazuh

# Tester la connexion depuis le Dashboard pod
kubectl exec -it -n wazuh <dashboard-pod> -- curl -k https://wazuh-indexer:9200
```

### Connection Refused sur Port-Forward

**Cause** : Service pas créé ou nom incorrect

**Solution** :

```bash
# Lister les services
kubectl get svc -n wazuh

# Vérifier le nom exact
kubectl describe svc wazuh-dashboard -n wazuh

# Port-forward avec le bon nom
kubectl port-forward -n wazuh svc/<nom-exact-service> 5443:443
```

---

## Surveillance et Monitoring

### Vérifier la Santé du Cluster

```bash
# Status global
kubectl get pods -n wazuh

# Logs Manager
kubectl logs -n wazuh wazuh-manager-master-0 -f

# Logs Indexer
kubectl logs -n wazuh wazuh-indexer-0 -f

# Status via API
kubectl exec -n wazuh wazuh-manager-master-0 -- /var/ossec/bin/cluster_control -l
```

### Métriques Prometheus

Wazuh expose des métriques pour Prometheus :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: wazuh-metrics
  namespace: wazuh
  labels:
    app: wazuh
spec:
  ports:
  - name: metrics
    port: 55000
    targetPort: 55000
  selector:
    app: wazuh-manager
  type: ClusterIP
```

Ajouter ServiceMonitor :

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: wazuh-metrics
  namespace: wazuh
spec:
  selector:
    matchLabels:
      app: wazuh
  endpoints:
  - port: metrics
    interval: 30s
```

---

## Mise à Jour

### Avec Kustomize

```bash
# Pull les derniers manifests
cd ~/wazuh-kubernetes
git pull

# Redéployer
kubectl apply -k deployments/kubernetes/
```

### Rollback en cas de Problème

```bash
# Via kubectl
kubectl rollout undo statefulset/wazuh-manager-master -n wazuh
kubectl rollout undo statefulset/wazuh-indexer -n wazuh
```

---

## Désinstallation

```bash
# Supprimer tous les composants Wazuh
kubectl delete -k https://github.com/wazuh/wazuh-kubernetes//deployments/kubernetes/

# Ou manuellement
kubectl delete namespace wazuh

# Supprimer les PVCs (données perdues !)
kubectl delete pvc -n wazuh --all
```

---

## Intégration avec Terraform (Futur)

Pour activer Wazuh via Terraform (une fois que le chart est disponible) :

```bash
cd ~/enterprise-security-k8s/terraform

# Option 1 : Via variable
echo 'enable_wazuh = true' >> terraform.tfvars
terraform apply

# Option 2 : Via CLI
terraform apply -var="enable_wazuh=true"
```

**Note** : Actuellement, cela affiche seulement un message avec les instructions de déploiement manuel.

---

## Comparaison : Wazuh Dashboard vs Kibana ELK

| Fonctionnalité | Kibana (ELK) | Wazuh Dashboard |
|----------------|--------------|-----------------|
| Base | Kibana Open Source | Fork de Kibana |
| Visualisation Logs | ✅ | ✅ |
| MITRE ATT&CK | ❌ | ✅ Intégré |
| CIS Compliance | ❌ | ✅ Intégré |
| PCI-DSS | ❌ | ✅ Intégré |
| GDPR | ❌ | ✅ Intégré |
| File Integrity (FIM) | ❌ | ✅ Intégré |
| Rootkit Detection | ❌ | ✅ Intégré |
| Vulnerability Scanning | ❌ | ✅ Intégré |
| Agent Management | ❌ | ✅ Intégré |
| Security Events | ⚠️ À configurer | ✅ Pré-configuré |
| Règles Custom | ✅ | ✅ |
| Alerting | ✅ Via Watcher | ✅ Natif |

**Verdict** : **Wazuh Dashboard est supérieur pour la sécurité** car il inclut des dashboards et analyses pré-configurés pour la cybersécurité.

---

## Ressources Officielles

- **Documentation** : https://documentation.wazuh.com/current/
- **Kubernetes Deployment** : https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/
- **GitHub Repository** : https://github.com/wazuh/wazuh-kubernetes
- **Docker Hub** : https://hub.docker.com/u/wazuh
- **Community Forum** : https://groups.google.com/g/wazuh

---

## Checklist Post-Installation

- [ ] Pods `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` en Running
- [ ] Accès au Dashboard via port-forward (https://localhost:5443)
- [ ] Connexion avec credentials admin/SecretPassword
- [ ] Changement des mots de passe par défaut
- [ ] Déploiement des agents Wazuh (DaemonSet)
- [ ] Configuration de l'intégration Elasticsearch (optionnel)
- [ ] Configuration de l'intégration Falco (optionnel)
- [ ] Création d'alertes custom
- [ ] Configuration des règles de compliance (CIS, PCI-DSS)
- [ ] Test de File Integrity Monitoring
- [ ] Test de détection de vulnérabilités
- [ ] Configuration du backup des données Indexer
- [ ] Configuration de Prometheus ServiceMonitor

---

**Auteur** : Z3ROX
**Date** : 2025-11-09
**Version Wazuh** : 4.7.0
**Status** : ✅ Guide Testé
