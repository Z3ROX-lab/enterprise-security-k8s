# Credentials et Accès aux Services

Ce fichier contient les commandes pour récupérer les credentials et accéder à tous les services déployés dans le cluster.

---

## 1. Elasticsearch

**Namespace:** `security-siem`

**Username:**
```bash
echo "elastic"
```

**Password:**
```bash
kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d
```

**Accès:**
```bash
kubectl port-forward -n security-siem svc/elasticsearch-master 9200:9200
# https://localhost:9200
```

**Test de connexion:**
```bash
ELASTIC_PASSWORD=$(kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d)
curl -k -u "elastic:$ELASTIC_PASSWORD" https://localhost:9200
```

---

## 2. Kibana

**Namespace:** `security-siem`

**Username:**
```bash
echo "elastic"
```

**Password:** (même que Elasticsearch)
```bash
kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d
```

**Accès:**
```bash
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601
# http://localhost:5601
```

**Data Views créés:**
- `trivy-vulnerabilities*` : Rapports de vulnérabilités Trivy (timestamp: `@timestamp`)
- `falco-*` : Alertes runtime Falco (timestamp: `time`)

---

## 3. Grafana

**Namespace:** `security-siem`

**Username:**
```bash
echo "admin"
```

**Password:**
```bash
kubectl get secret -n security-siem prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

**Accès:**
```bash
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
# http://localhost:3000
```

**Dashboards disponibles:**
- Falco Security Alerts (métriques Falcosidekick)
- Trivy Operator (métriques de vulnérabilités - si créé)

---

## 4. Prometheus

**Namespace:** `security-siem`

**Authentification:** Aucune (accès direct)

**Accès:**
```bash
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090
```

**Targets utiles:**
- Falcosidekick: `security-detection/falcosidekick`
- Trivy Operator: Vérifier dans Targets

---

## 5. Falcosidekick UI

**Namespace:** `security-detection`

**Username:**
```bash
echo "admin"
```

**Password:**
```bash
kubectl get secret -n security-detection falco-falcosidekick-ui -o jsonpath='{.data.FALCOSIDEKICK_UI_USER}' | base64 -d | cut -d: -f2
# Ou directement: echo "admin"
```

**Accès:**
```bash
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
# http://localhost:2802
```

**Fonction:** Visualisation temps réel des alertes Falco

---

## 6. Vault

**Namespace:** `security-iam`

**Mode:** Production (Raft) ou Dev

**Root Token (Production uniquement):**
```bash
kubectl get secret -n security-iam vault-init -o jsonpath='{.data.root-token}' | base64 -d
```

**Root Token (Dev mode):**
```bash
echo "root"
```

**Unseal Keys (Production uniquement):**
```bash
# Key 1
kubectl get secret -n security-iam vault-init -o jsonpath='{.data.unseal-key-1}' | base64 -d

# Key 2
kubectl get secret -n security-iam vault-init -o jsonpath='{.data.unseal-key-2}' | base64 -d

# Key 3
kubectl get secret -n security-iam vault-init -o jsonpath='{.data.unseal-key-3}' | base64 -d
```

**Accès:**
```bash
kubectl port-forward -n security-iam svc/vault 8200:8200
# http://localhost:8200
```

**Vérifier le statut:**
```bash
kubectl exec -n security-iam vault-0 -- vault status
```

---

## 7. Keycloak

**Namespace:** `security-iam`

**Username Admin:** (à définir lors du déploiement)
```bash
kubectl get secret -n security-iam keycloak-admin -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "Credentials non configurés"
```

**Password Admin:**
```bash
kubectl get secret -n security-iam keycloak-admin -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "Credentials non configurés"
```

**Accès:**
```bash
kubectl port-forward -n security-iam svc/keycloak 8080:80
# http://localhost:8080
```

**Note:** Si Keycloak n'a pas de secret admin configuré, vérifier la documentation du chart Helm utilisé.

---

## 8. PostgreSQL (pour Keycloak)

**Namespace:** `security-iam`

**Username:**
```bash
echo "postgres"
```

**Password:**
```bash
kubectl get secret -n security-iam keycloak-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d 2>/dev/null || echo "Secret non trouvé"
```

**Accès:** (usage interne uniquement)
```bash
kubectl port-forward -n security-iam svc/keycloak-postgresql 5432:5432
```

---

## 9. Falco

**Namespace:** `security-detection`

**Authentification:** Aucune (DaemonSet, pas d'interface web)

**Voir les logs:**
```bash
# Logs d'un pod Falco spécifique
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=100

# Logs avec filtre sur les alertes
kubectl logs -n security-detection -l app.kubernetes.io/name=falco --tail=100 | grep -i "warning\|error\|critical"
```

---

## 10. Trivy Operator

**Namespace:** `trivy-system`

**Authentification:** Aucune (Operator, pas d'interface web)

**Voir les rapports:**
```bash
# Lister tous les rapports de vulnérabilités
kubectl get vulnerabilityreports -A

# Voir un rapport spécifique
kubectl get vulnerabilityreport <nom> -n <namespace> -o yaml

# Compter les vulnérabilités par sévérité
kubectl get vulnerabilityreports -A -o json | jq '.items[].report.summary'
```

---

## 11. Gatekeeper

**Namespace:** `gatekeeper-system`

**Authentification:** Aucune (Policy engine, pas d'interface web)

**Voir les constraints:**
```bash
# Lister toutes les constraints
kubectl get constraints

# Voir les violations
kubectl get <constraint-kind> <constraint-name> -o yaml
```

---

## Récapitulatif des Services avec UI Web

| Service | Namespace | URL | Username | Password Command |
|---------|-----------|-----|----------|------------------|
| **Kibana** | security-siem | http://localhost:5601 | elastic | `kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' \| base64 -d` |
| **Grafana** | security-siem | http://localhost:3000 | admin | `kubectl get secret -n security-siem prometheus-grafana -o jsonpath='{.data.admin-password}' \| base64 -d` |
| **Prometheus** | security-siem | http://localhost:9090 | - | Pas d'authentification |
| **Falcosidekick UI** | security-detection | http://localhost:2802 | admin | admin |
| **Vault** | security-iam | http://localhost:8200 | Token | `kubectl get secret -n security-iam vault-init -o jsonpath='{.data.root-token}' \| base64 -d` |
| **Keycloak** | security-iam | http://localhost:8080 | (variable) | (variable) |
| **Elasticsearch** | security-siem | https://localhost:9200 | elastic | (même que Kibana) |

---

## Port-Forwards Multiples (pour la démo)

**Script pour ouvrir tous les port-forwards en parallèle:**

```bash
#!/bin/bash
# Lancer tous les port-forwards en background

echo "🚀 Lancement des port-forwards..."

kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601 > /dev/null 2>&1 &
echo "✅ Kibana: http://localhost:5601"

kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
echo "✅ Grafana: http://localhost:3000"

kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090 > /dev/null 2>&1 &
echo "✅ Prometheus: http://localhost:9090"

kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802 > /dev/null 2>&1 &
echo "✅ Falcosidekick UI: http://localhost:2802"

kubectl port-forward -n security-iam svc/vault 8200:8200 > /dev/null 2>&1 &
echo "✅ Vault: http://localhost:8200"

kubectl port-forward -n security-iam svc/keycloak 8080:80 > /dev/null 2>&1 &
echo "✅ Keycloak: http://localhost:8080"

kubectl port-forward -n security-siem svc/elasticsearch-master 9200:9200 > /dev/null 2>&1 &
echo "✅ Elasticsearch: https://localhost:9200"

echo ""
echo "🎯 Tous les services sont accessibles !"
echo "   Pour arrêter : pkill -f 'kubectl port-forward'"
```

**Sauvegarder dans:** `scripts/start-all-port-forwards.sh`

**Arrêter tous les port-forwards:**
```bash
pkill -f 'kubectl port-forward'
```

---

## Commandes Utiles

### Lister tous les secrets d'un namespace
```bash
kubectl get secrets -n <namespace>
```

### Voir le contenu complet d'un secret
```bash
kubectl get secret <secret-name> -n <namespace> -o yaml
```

### Décoder une valeur base64
```bash
echo "<valeur-base64>" | base64 -d
```

### Vérifier qu'un service est accessible
```bash
# Kibana
curl -s -o /dev/null -w "%{http_code}" http://localhost:5601

# Grafana
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000

# Prometheus
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090

# Falcosidekick UI
curl -s -o /dev/null -w "%{http_code}" http://localhost:2802
```

---

## Notes de Sécurité

⚠️ **IMPORTANT:**

1. **Ces credentials sont pour un environnement de test/dev local**
2. **Ne JAMAIS commit ce fichier avec des credentials réels dans un repository public**
3. **En production:**
   - Utiliser un gestionnaire de secrets (Vault, AWS Secrets Manager, etc.)
   - Activer RBAC strict
   - Utiliser des certificats TLS pour toutes les communications
   - Changer tous les mots de passe par défaut
   - Implémenter la rotation automatique des credentials
   - Utiliser des service accounts avec permissions minimales

4. **Pour ce lab:**
   - Les credentials sont stockés dans des secrets Kubernetes
   - Accès restreint au cluster Kind local
   - Communications HTTPS avec certificats auto-signés (Vault PKI)

---

## Troubleshooting

### Le port-forward échoue
```bash
# Vérifier que le service existe
kubectl get svc -n <namespace>

# Vérifier que le pod est running
kubectl get pods -n <namespace>

# Vérifier les logs du pod
kubectl logs -n <namespace> <pod-name>
```

### Impossible de récupérer un mot de passe
```bash
# Vérifier que le secret existe
kubectl get secret <secret-name> -n <namespace>

# Voir les clés disponibles dans le secret
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}' | jq 'keys'
```

### L'authentification échoue
```bash
# Vérifier que vous utilisez le bon username
# Vérifier que le mot de passe n'a pas d'espaces ou caractères spéciaux
# Essayer de reset le mot de passe (voir documentation du service)
```

---

**Dernière mise à jour:** 2025-11-13
