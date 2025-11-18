# Demo Security - Application avec Détection Falco

Cette application démontre l'intégration de la sécurité runtime avec Falco dans le pipeline GitOps.

## Description

Application Alpine Linux qui peut déclencher des alertes Falco pour démontrer la détection de menaces.

## Scénarios de Sécurité

### 1. Détection de Shell Interactif
```bash
kubectl exec -it deployment/demo-security -- sh
# Falco détectera cette action suspecte
```

### 2. Détection d'Accès Fichiers Sensibles
```bash
kubectl exec deployment/demo-security -- cat /etc/shadow
# Falco alerte sur l'accès aux fichiers sensibles
```

### 3. Détection de Modification Système
```bash
kubectl exec deployment/demo-security -- apk add curl
# Falco détecte l'installation de packages
```

## Visualisation

### Kibana
Les alertes Falco sont envoyées vers Elasticsearch:
```
Index: falco-*
Filtre: kubernetes.namespace_name:"default" AND kubernetes.pod_name:"demo-security*"
```

### Grafana
Dashboard Falco:
- Nombre d'alertes par sévérité
- Top pods avec alertes
- Timeline des événements

## Architecture de Sécurité

```
┌──────────────┐    ┌──────────┐    ┌──────────────┐
│ demo-security│───▶│  Falco   │───▶│     ELK      │
│  (Pod)       │    │ (eBPF)   │    │   (SIEM)     │
└──────────────┘    └──────────┘    └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Prometheus  │
                    │  (Metrics)   │
                    └──────────────┘
```

## Règles Falco Déclenchées

Cette application peut déclencher les règles Falco suivantes:
- `Terminal shell in container`
- `Read sensitive file untrusted`
- `Write below etc`
- `Package management process launched`
- `Change thread namespace`

## Utilisation GitOps

### Déployer via ArgoCD
```bash
kubectl apply -f ../argocd-apps/demo-security-app.yaml
```

### Tester les alertes
```bash
# Exécuter un shell (déclenche alerte)
kubectl exec -it deployment/demo-security -- sh

# Lire un fichier sensible (déclenche alerte)
kubectl exec deployment/demo-security -- cat /etc/shadow

# Consulter les logs Falco
kubectl logs -n security-detection -l app.kubernetes.io/name=falco
```

### Visualiser dans Kibana
1. Allez sur https://kibana.local.lab:8443
2. Index Pattern: `falco-*`
3. Filtrez par `kubernetes.pod_name: demo-security*`
4. Observez les alertes en temps réel

## Intégration avec le Pipeline

Ce composant s'intègre dans le pipeline GitOps complet:

1. **Code** → Gitea
2. **Sync** → ArgoCD
3. **Deploy** → Kubernetes
4. **Monitor** → Falco détecte les comportements suspects
5. **Alert** → ELK + Prometheus
6. **Visualize** → Kibana + Grafana
