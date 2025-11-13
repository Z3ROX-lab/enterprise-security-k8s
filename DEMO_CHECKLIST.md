# Checklist de Tests pour la Démo Finale

## Vue d'ensemble
Cette checklist contient tous les tests à effectuer pour démontrer le fonctionnement de la stack de sécurité Kubernetes.

## 📚 Documentation complémentaire
- **[DASHBOARDS_GUIDE.md](./DASHBOARDS_GUIDE.md)** : Guide complet pour configurer et interpréter les dashboards Kibana et Grafana
- **[CREDENTIALS.md](./CREDENTIALS.md)** : Toutes les commandes pour récupérer les credentials des services

---

## 1. Tests Trivy - Vulnérabilités

### Test 1.1: Déploiement d'une image vulnérable
**Objectif:** Vérifier que Trivy détecte les vulnérabilités et les exporte vers Elasticsearch/Kibana

**Commandes:**
```bash
# Déployer une image vulnérable (Alpine 3.12)
kubectl run vulnerable-test -n default --image=alpine:3.12 --command -- sleep 3600

# Attendre 2-3 minutes pour le scan automatique
sleep 180

# Vérifier le rapport de vulnérabilités
kubectl get vulnerabilityreports -n default | grep vulnerable-test

# Voir le résumé des vulnérabilités
kubectl get vulnerabilityreport -n default -l trivy-operator.resource.name=vulnerable-test -o jsonpath='{.items[0].report.summary}' | jq

# Forcer l'export vers Elasticsearch
kubectl create job -n trivy-system trivy-export-demo --from=cronjob/trivy-exporter

# Attendre l'export (30 secondes)
sleep 30

# Vérifier les logs
kubectl logs -n trivy-system job/trivy-export-demo
```

**Vérification dans Kibana:**
1. Ouvrir Kibana: `kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601`
2. Aller dans Analytics → Discover
3. Sélectionner le data view "Trivy Vulnerabilities"
4. Chercher: `namespace: "default" AND report_name: *vulnerable-test*`
5. Vérifier la présence de vulnérabilités CRITICAL et HIGH

**Temps estimé:** 3-4 minutes

**Cleanup:**
```bash
kubectl delete pod vulnerable-test -n default
kubectl delete job trivy-export-demo -n trivy-system
```

---

### Test 1.2: Vérification des dashboards Grafana
**Objectif:** Visualiser les métriques Trivy dans Grafana

**Commandes:**
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

**Vérification:**
1. Ouvrir http://localhost:3000
2. Login avec admin/prom-operator
3. Chercher le dashboard Trivy
4. Vérifier les métriques: nombre de vulnérabilités par sévérité, par namespace, etc.

**Temps estimé:** 2 minutes

---

## 2. Tests Gatekeeper - Policy Enforcement

### Test 2.1: Bloquer un pod sans labels requis
**Objectif:** Vérifier que Gatekeeper bloque les déploiements non conformes

**Commandes:**
```bash
# Tenter de créer un pod sans labels (devrait être bloqué)
kubectl run test-no-labels --image=nginx

# La commande devrait échouer avec un message de Gatekeeper
```

**Résultat attendu:** Rejet avec message explicatif

**Temps estimé:** 1 minute

---

### Test 2.2: Bloquer une image non sécurisée
**Objectif:** Vérifier que Gatekeeper bloque les images de registres non autorisés

**Commandes:**
```bash
# Tenter d'utiliser une image non approuvée
kubectl run test-bad-registry --image=docker.io/nginx

# Devrait être bloqué si la policy de registre approuvé est active
```

**Résultat attendu:** Rejet ou acceptation selon les policies configurées

**Temps estimé:** 1 minute

---

## 3. Tests Falco - Runtime Security

### Test 3.1: Détection de shell interactif dans un conteneur
**Objectif:** Vérifier que Falco détecte un shell interactif (comportement suspect)

**Commandes:**
```bash
# Créer un pod de test
kubectl run falco-test --image=nginx

# Attendre que le pod démarre
kubectl wait --for=condition=ready pod/falco-test --timeout=60s

# Exécuter un shell interactif (comportement suspect)
kubectl exec -it falco-test -- /bin/bash
# Taper quelques commandes puis exit

# Vérifier les logs Falco
kubectl logs -n security-detection daemonset/falco | grep -i "shell"
```

**Résultat attendu:** Alerte Falco détectant le shell interactif

**Temps estimé:** 2 minutes

**Cleanup:**
```bash
kubectl delete pod falco-test
```

---

### Test 3.2: Détection d'écriture dans /etc
**Objectif:** Vérifier que Falco détecte les modifications suspectes dans /etc

**Commandes:**
```bash
# Créer un pod
kubectl run falco-test-etc --image=nginx

# Modifier un fichier dans /etc (comportement suspect)
kubectl exec falco-test-etc -- sh -c "echo 'test' >> /etc/passwd"

# Vérifier les logs Falco
kubectl logs -n security-detection daemonset/falco | grep -i "etc"
```

**Résultat attendu:** Alerte Falco sur modification de /etc

**Temps estimé:** 2 minutes

**Cleanup:**
```bash
kubectl delete pod falco-test-etc
```

---

### Test 3.3: Vérification des alertes dans Falcosidekick UI et Kibana
**Objectif:** Vérifier que les alertes Falco sont visibles dans les deux interfaces (temps réel + SIEM)

**Partie A: Falcosidekick UI (Interface temps réel)**

**Commandes:**
```bash
# Ouvrir l'interface Falcosidekick UI
kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802
```

**Vérification dans le navigateur:**
1. Ouvrir http://localhost:2802
2. Login avec:
   - Username: `admin`
   - Password: `admin`
3. Vérifier que des alertes sont présentes dans l'interface
4. Tester les filtres par Priority (Critical, Warning, Notice)
5. Tester les filtres par Rule

**Générer une alerte de test:**
```bash
# Dans un autre terminal
kubectl run test-falco-alert --image=nginx
kubectl exec test-falco-alert -- /bin/bash -c "ls /etc"
kubectl delete pod test-falco-alert
```

**Résultat attendu:** L'alerte apparaît dans Falcosidekick UI en quelques secondes

---

**Partie B: Kibana (Analyse SIEM)**

**Commandes:**
```bash
# Ouvrir Kibana
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601
```

**Vérification dans Kibana:**
1. Ouvrir http://localhost:5601
2. Login avec:
   - Username: `elastic`
   - Password: (obtenir avec `kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d`)
3. Créer le Data View si pas encore fait:
   - Stack Management → Data Views
   - Create data view
   - Name: `Falco Alerts`
   - Index pattern: `falco-*`
   - Timestamp field: `time`
   - Save
4. Analytics → Discover → Sélectionner "Falco Alerts"
5. Ajuster la plage de temps (Last 24 hours ou plus)
6. Vérifier la présence d'alertes

**Vérifier le nombre d'alertes dans Elasticsearch:**
```bash
ELASTIC_PASSWORD=$(kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d)
POD=$(kubectl get pod -n security-siem -l app=elasticsearch-master -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n security-siem $POD -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/falco-*/_count" | jq
```

**Résultat attendu:**
- Count > 0 dans Elasticsearch
- Alertes visibles dans Kibana Discover
- Champs disponibles: output, priority, rule, output_fields.*, hostname

**Exemples de recherches dans Kibana:**
```
priority: "Critical"
rule: "Terminal shell in container"
output_fields.k8s_ns_name: "default"
```

**Temps estimé:** 5 minutes

---

### Test 3.4: Vérification des métriques Falco dans Grafana
**Objectif:** Vérifier que les métriques Falco sont collectées par Prometheus et visualisables dans Grafana

**Partie A: Accès au dashboard Grafana Falco**

**Commandes:**
```bash
# Ouvrir Grafana
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80
```

**Vérification dans le navigateur:**
1. Ouvrir http://localhost:3000
2. Login avec:
   - Username: `admin`
   - Password: (obtenir avec `kubectl get secret -n security-siem prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d`)
3. Cliquer sur **☰ (menu hamburger)** → **Dashboards**
4. Chercher et ouvrir **"Falco Security Alerts"**

**Dashboard panels disponibles:**
- Panel 1: Taux d'alertes Falco (par seconde) - Graphique temporel
- Panel 2: Total alertes reçues - Compteur unique
- Panel 3: Alertes par destination (Elasticsearch, WebUI) - Pie chart
- Panel 4: Alertes Falco par priorité (Critical, Notice) - Graphique multi-séries
- Panel 5: Top 5 règles Falco - Table triée
- Panel 6: Alertes par heure - Stat unique avec graphique

---

**Partie B: Générer des alertes et observer les métriques**

**Générer plusieurs alertes de test:**
```bash
# Test 1: Shell dans un conteneur
kubectl run grafana-test-1 --image=nginx
kubectl exec grafana-test-1 -- /bin/bash -c "ls /etc"
kubectl delete pod grafana-test-1

# Test 2: Modification de /etc
kubectl run grafana-test-2 --image=nginx
kubectl exec grafana-test-2 -- sh -c "echo test >> /etc/hosts"
kubectl delete pod grafana-test-2

# Test 3: Lecture de fichier sensible
kubectl run grafana-test-3 --image=nginx
kubectl exec grafana-test-3 -- cat /etc/shadow 2>/dev/null || true
kubectl delete pod grafana-test-3
```

**Observer les changements dans Grafana:**
1. Attendre 30 secondes (auto-refresh du dashboard)
2. Observer l'augmentation du "Taux d'alertes Falco"
3. Vérifier l'incrémentation du "Total alertes reçues"
4. Observer la distribution dans "Alertes par destination"
5. Vérifier que "Alertes par heure" augmente

---

**Partie C: Vérifier les métriques dans Prometheus (optionnel)**

**Commandes:**
```bash
# Ouvrir Prometheus
kubectl port-forward -n security-siem svc/prometheus-kube-prometheus-prometheus 9090:9090
```

**Vérification dans Prometheus:**
1. Ouvrir http://localhost:9090
2. Aller dans **Graph** → **Query**
3. Tester les requêtes PromQL:

```promql
# Taux d'alertes par seconde
rate(falcosidekick_inputs[5m])

# Total d'alertes reçues
falcosidekick_inputs

# Alertes par destination
sum by (destination) (falcosidekick_outputs)

# Alertes Falco par priorité
sum by (priority) (falco_events)

# Top 5 règles Falco
topk(5, sum by (rule) (falco_events))
```

4. Cliquer sur **Execute**
5. Vérifier que les métriques retournent des valeurs

---

**Résultat attendu:**
- Dashboard Falco accessible dans Grafana
- Métriques se mettent à jour après génération d'alertes
- Graphiques montrent l'activité en temps réel
- Aucune erreur dans le panel "Taux d'erreurs"
- Latence Elasticsearch < 1 seconde

**Temps estimé:** 5 minutes

**Note importante:**
- **Grafana** affiche des **métriques agrégées** (statistiques, tendances)
- Pour voir les **descriptions détaillées** des alertes, utiliser **Kibana** ou **Falcosidekick UI**
- Différence :
  - Grafana = Vue d'ensemble statistique (combien, quand, où)
  - Kibana = Détails complets (quoi, pourquoi, comment)
  - Falcosidekick UI = Temps réel (alertes individuelles)

**📘 Guide complet des dashboards : Voir [DASHBOARDS_GUIDE.md](./DASHBOARDS_GUIDE.md)**

---

### Test 3.5: Falco Tuning - Réduction des faux positifs
**Objectif:** Réduire le bruit des alertes en filtrant les namespaces de confiance (monitoring, système)

**Contexte:**
- Avant tuning : ~2000 alertes/h (beaucoup de bruit des outils de monitoring)
- Après tuning : ~50-100 alertes/h (uniquement alertes pertinentes)

**Commandes:**
```bash
# Exécuter le script de tuning
./deploy/34-falco-tuning.sh

# Le script va :
# 1. Créer des règles Falco custom
# 2. Filtrer les namespaces de confiance :
#    - security-siem (Grafana, Prometheus, Elasticsearch, Kibana)
#    - trivy-system (scans de vulnérabilités)
#    - kube-system (composants système, CNI)
#    - security-detection (Falco, Falcosidekick)
# 3. Redémarrer Falco avec les nouvelles règles

# Répondre 'y' quand demandé pour appliquer la mise à jour
```

**Vérification après 5-10 minutes:**

1. **Dans Grafana** (Dashboard Falco Security Alerts):
   - Panel "Alertes par heure" devrait montrer ~50-100 au lieu de ~2000
   - Panel "Top 5 règles Falco" devrait montrer principalement des règles sur namespaces applicatifs

2. **Dans Kibana** (Discover → Falco Alerts):
   ```
   # Vérifier que les alertes système sont filtrées
   NOT k8s.ns.name: (kube-system OR security-siem OR trivy-system OR security-detection)
   ```
   - La plupart des alertes devraient être sur namespaces applicatifs (`default`, vos apps)

3. **Tester avec un pod dans namespace par défaut** (devrait générer une alerte):
   ```bash
   kubectl run test-tuning --image=nginx -n default
   kubectl exec -n default test-tuning -- /bin/bash -c "ls /etc"
   kubectl delete pod test-tuning -n default
   ```
   - Cette alerte DOIT apparaître dans Grafana/Kibana (namespace non filtré)

4. **Tester avec un pod dans namespace filtré** (ne devrait PAS générer d'alerte):
   ```bash
   kubectl run test-filtered --image=nginx -n security-siem
   kubectl exec -n security-siem test-filtered -- /bin/bash -c "ls /etc"
   kubectl delete pod test-filtered -n security-siem
   ```
   - Cette alerte NE DOIT PAS apparaître (namespace filtré)

**Résultat attendu:**
- ✅ Volume d'alertes réduit de ~95%
- ✅ Alertes sur namespaces applicatifs toujours présentes
- ✅ Alertes sur namespaces système/monitoring filtrées
- ✅ Dashboard Grafana plus lisible avec des alertes pertinentes

**Temps estimé:** 3-5 minutes

**Ajuster le tuning:**
```bash
# Pour ajouter d'autres namespaces à filtrer
kubectl edit cm falco-rules-custom -n security-detection

# Ajouter votre namespace dans la liste trusted_namespaces
# Puis redémarrer Falco
kubectl rollout restart daemonset falco -n security-detection
```

**📘 Pour comprendre comment interpréter les alertes restantes : Voir [DASHBOARDS_GUIDE.md](./DASHBOARDS_GUIDE.md) section "Interprétation des données"**

---

## 4. Tests Vault - PKI et Certificats

### Test 4.1: Création automatique de certificat via cert-manager
**Objectif:** Vérifier que cert-manager peut obtenir des certificats de Vault

**Commandes:**
```bash
# Créer un certificat de test
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo-certificate
  namespace: default
spec:
  secretName: demo-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: demo.example.com
  dnsNames:
  - demo.example.com
  - www.demo.example.com
EOF

# Vérifier le statut
kubectl get certificate demo-certificate -n default
kubectl describe certificate demo-certificate -n default

# Vérifier que le secret TLS est créé
kubectl get secret demo-tls -n default
```

**Résultat attendu:** Certificat créé avec statut "Ready: True"

**Temps estimé:** 1 minute

**Cleanup:**
```bash
kubectl delete certificate demo-certificate -n default
kubectl delete secret demo-tls -n default
```

---

## 5. Tests Keycloak - IAM/SSO

### Test 5.1: Authentification via Keycloak
**Objectif:** Vérifier que Keycloak fonctionne et peut authentifier les utilisateurs

**Commandes:**
```bash
# Port-forward Keycloak
kubectl port-forward -n security-iam svc/keycloak 8080:80
```

**Vérification:**
1. Ouvrir http://localhost:8080
2. Login sur la console admin
3. Créer un realm de test
4. Créer un utilisateur de test
5. Vérifier l'authentification

**Temps estimé:** 3-5 minutes

---

### Test 5.2: Intégration OIDC (Option A ou B)
**Objectif:** Authentification Kubernetes via Keycloak OIDC

**Note:** À définir selon l'option choisie (Option A: kubelogin, Option B: gangway/dex)

**Temps estimé:** TBD

---

## 6. Tests d'intégration

### Test 6.1: Visualisation complète des données
**Objectif:** Vérifier que toutes les sources de données sont visibles dans les dashboards

**Vérifications:**
- [ ] Grafana affiche les métriques Prometheus de tous les services
- [ ] Grafana affiche les métriques Trivy
- [ ] Kibana affiche les rapports de vulnérabilités Trivy
- [ ] Elasticsearch contient les données (vérifier le count)

**Commandes:**
```bash
# Vérifier le nombre de documents dans Elasticsearch
ELASTIC_PASSWORD=$(kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n security-siem elasticsearch-master-0 -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/_cat/indices?v"
```

**Temps estimé:** 5 minutes

---

### Test 6.2: Workflow complet de sécurité
**Objectif:** Démonstration bout en bout du workflow de sécurité

**Scénario:**
1. Déployer une application avec une image vulnérable
2. Vérifier que Gatekeeper valide les policies
3. Trivy scanne et détecte les vulnérabilités
4. Visualiser dans Kibana les CVE détaillés
5. Visualiser dans Grafana les métriques agrégées
6. Falco détecte des comportements runtime suspects
7. Corriger l'image et redéployer
8. Vérifier que les vulnérabilités diminuent

**Temps estimé:** 10-15 minutes

---

## 7. Tests de haute disponibilité

### Test 7.1: Résilience Vault
**Objectif:** Vérifier que Vault en mode Raft survit à la perte d'un pod

**Commandes:**
```bash
# Vérifier l'état initial
kubectl exec -n security-iam vault-0 -- vault status

# Supprimer un pod
kubectl delete pod -n security-iam vault-1 --force --grace-period=0

# Vérifier que le cluster reste opérationnel
kubectl exec -n security-iam vault-0 -- vault status

# Attendre que le pod redémarre
kubectl wait --for=condition=ready pod/vault-1 -n security-iam --timeout=120s
```

**Résultat attendu:** Cluster Vault reste opérationnel

**Temps estimé:** 3 minutes

---

### Test 7.2: Résilience Elasticsearch
**Objectif:** Vérifier la réplication et disponibilité

**Commandes:**
```bash
# Vérifier l'état du cluster
ELASTIC_PASSWORD=$(kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n security-siem elasticsearch-master-0 -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/_cluster/health?pretty"

# Supprimer un pod
kubectl delete pod -n security-siem elasticsearch-master-1 --force --grace-period=0

# Vérifier que le cluster reste green/yellow
kubectl exec -n security-siem elasticsearch-master-0 -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/_cluster/health?pretty"
```

**Résultat attendu:** Cluster reste opérationnel (yellow acceptable temporairement)

**Temps estimé:** 3 minutes

---

## 8. Tests de performance (optionnel)

### Test 8.1: Charge sur Trivy
**Objectif:** Vérifier les performances de scan à grande échelle

**Commandes:**
```bash
# Déployer plusieurs pods
for i in {1..10}; do
  kubectl run load-test-$i --image=nginx:1.21
done

# Attendre et vérifier les scans
sleep 300
kubectl get vulnerabilityreports -A | wc -l
```

**Temps estimé:** 10 minutes

---

## Notes importantes

### Ordre des tests
1. Commencer par les tests unitaires (chaque service individuellement)
2. Puis les tests d'intégration
3. Finir par les tests de résilience

### Environnement
- Cluster Kind 4 nœuds
- Windows 11 + Docker Desktop + WSL2 Ubuntu
- Tous les services déployés et opérationnels

### Cleanup général après la démo
```bash
# Supprimer tous les pods de test
kubectl delete pod -l demo=test --all-namespaces

# Supprimer tous les jobs de test
kubectl delete job -l demo=test --all-namespaces
```

---

## Checklist de préparation

Avant de lancer la démo, vérifier que :
- [ ] Tous les pods sont Running
- [ ] Elasticsearch est accessible et contient des données
- [ ] Kibana est accessible et le data view est créé
- [ ] Grafana est accessible avec les dashboards configurés
- [ ] Vault est initialisé et unsealed
- [ ] Keycloak est accessible
- [ ] Falco est running sur tous les nœuds
- [ ] Gatekeeper a des policies configurées
- [ ] Trivy Operator scanne activement
- [ ] Le CronJob d'export Trivy fonctionne

---

## Temps total estimé
- Tests rapides (essentiels): ~30 minutes
- Tests complets: ~1-2 heures
- Avec troubleshooting: prévoir 3 heures

---

## Ressources utiles

### Port-forwards pour la démo
```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Kibana
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601

# Vault
kubectl port-forward -n security-iam svc/vault 8200:8200

# Keycloak
kubectl port-forward -n security-iam svc/keycloak 8080:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

### Credentials
```bash
# Elasticsearch
kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d

# Grafana
# User: admin
# Password: prom-operator

# Vault root token
kubectl get secret -n security-iam vault-init -o jsonpath='{.data.root-token}' | base64 -d
```
