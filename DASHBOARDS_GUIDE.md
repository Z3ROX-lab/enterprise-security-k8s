# Guide des Dashboards - Kibana & Grafana

Ce guide explique comment configurer et utiliser les dashboards de visualisation pour le monitoring de sécurité.

## Table des matières

1. [Grafana - Dashboard Falco](#grafana-dashboard-falco)
2. [Kibana - Analyse des alertes Falco](#kibana-analyse-des-alertes-falco)
3. [Interprétation des données](#interprétation-des-données)

---

## Grafana - Dashboard Falco

### Accès au dashboard

```bash
# Port-forward Grafana
kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80

# Ouvrir dans le navigateur
# URL: http://localhost:3000
# Username: admin
# Password: admin123 (ou récupérer via: kubectl get secret -n security-siem prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
```

### Import automatique du dashboard

Le dashboard "Falco Security Alerts" peut être importé automatiquement :

```bash
./deploy/33-falco-dashboard-import.sh
```

Ce script crée un dashboard avec 6 panels pré-configurés.

### Panels du dashboard Grafana

#### 1. Taux d'alertes Falco (par seconde)
- **Type** : Time series (graphique temporel)
- **Requête PromQL** : `rate(falcosidekick_inputs[5m])`
- **Interprétation** :
  - Montre la tendance des alertes en temps réel
  - Pic soudain = activité suspecte ou déploiement
  - Taux stable = activité normale du cluster

#### 2. Total alertes reçues
- **Type** : Stat (chiffre unique)
- **Requête PromQL** : `falcosidekick_inputs`
- **Interprétation** :
  - Compteur cumulatif depuis le démarrage de Falcosidekick
  - Augmente continuellement
  - Utile pour voir l'activité totale

#### 3. Alertes par destination
- **Type** : Pie chart (camembert)
- **Requête PromQL** : `sum by (destination) (falcosidekick_outputs)`
- **Interprétation** :
  - **Elasticsearch** : Alertes stockées pour analyse SIEM dans Kibana
  - **WebUI** : Alertes visibles dans Falcosidekick UI en temps réel
  - Les deux destinations doivent avoir le même nombre (chaque alerte va aux 2 outputs)

#### 4. Alertes Falco par priorité
- **Type** : Time series (graphique temporel multi-séries)
- **Requête PromQL** : `sum by (priority) (falco_events)`
- **Interprétation** :
  - **Critical** (rouge) : Menaces graves (exécution de binaires, shells interactifs)
  - **Warning** (orange) : Comportements suspects
  - **Notice** (bleu) : Informations, souvent bénignes
  - **Si tuning appliqué** : Principalement des Critical sur namespaces applicatifs

#### 5. Top 5 règles Falco
- **Type** : Table
- **Requête PromQL** : `topk(5, sum by (rule) (falco_events))`
- **Interprétation** :
  - Liste des 5 règles les plus déclenchées
  - **Avant tuning** :
    - "Contact K8S API Server" → Normal pour monitoring/Trivy
    - "Drop and execute binary" → Builds, compilations
    - "Redirect STDOUT/STDIN" → CNI, networking
  - **Après tuning** :
    - Devrait montrer principalement des règles sur namespaces applicatifs
    - Moins de règles système/monitoring

#### 6. Alertes par heure
- **Type** : Stat (chiffre unique avec mini-graphique)
- **Requête PromQL** : `sum(increase(falcosidekick_inputs[1h]))`
- **Interprétation** :
  - Nombre total d'alertes dans la dernière heure
  - **Avant tuning** : ~2000/h (beaucoup de bruit)
  - **Après tuning** : ~50-100/h (alertes pertinentes uniquement)
  - **Threshold colors** :
    - Vert (< 50) : Très calme
    - Jaune (50-100) : Activité normale après tuning
    - Rouge (> 100) : Activité élevée, à investiguer

---

## Kibana - Analyse des alertes Falco

### Accès à Kibana

```bash
# Port-forward Kibana
kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601

# Récupérer les credentials
echo "Username: elastic"
kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d
echo

# Ouvrir dans le navigateur
# URL: http://localhost:5601
```

### Configuration initiale - Créer le Data View

**Première connexion uniquement** :

1. Menu (☰) → **Stack Management** → **Data Views**
2. Cliquer sur **"Create data view"**
3. Remplir :
   - **Name** : `Falco Alerts`
   - **Index pattern** : `falco-*`
   - **Timestamp field** : `@timestamp`
4. Cliquer sur **"Save data view to Kibana"**

### Utiliser Discover pour analyser les alertes

#### Accéder à Discover

1. Menu (☰) → **Discover**
2. Sélectionner le Data View : **"Falco Alerts"** (en haut à gauche)
3. Ajuster la période : **"Last 24 hours"** (en haut à droite)

#### Colonnes recommandées

Dans la section **"Available fields"** (à gauche), ajouter ces champs en cliquant dessus :

- `rule` ou `rule.keyword` : Nom de la règle Falco déclenchée
- `priority` : Niveau de sévérité (Critical, Warning, Notice)
- `output` : Message détaillé de l'alerte
- `k8s.ns.name` : Namespace Kubernetes
- `k8s.pod.name` : Nom du pod concerné
- `container.name` : Nom du container
- `container.image.repository` : Image Docker utilisée
- `proc.cmdline` : Ligne de commande du processus

#### Recherches utiles dans Kibana

**1. Alertes Critical uniquement**
```
priority: "Critical"
```

**2. Alertes sur un namespace spécifique**
```
k8s.ns.name: "default"
```

**3. Alertes sur une règle spécifique**
```
rule: "Contact K8S API Server From Container"
```

**4. Exclure les namespaces système (simulation du tuning)**
```
NOT k8s.ns.name: (kube-system OR security-siem OR trivy-system OR security-detection)
```

**5. Alertes shell dans les containers**
```
rule: "Terminal shell in container"
```

#### Visualisations dans Kibana

##### Top règles déclenchées

1. Dans **"Available fields"**, cliquer sur `rule.keyword`
2. Voir le Top 5 avec les comptes

##### Distribution par priorité

1. Cliquer sur `priority.keyword`
2. Voir la répartition Critical/Warning/Notice

##### Alertes par namespace

1. Cliquer sur `k8s.ns.name.keyword`
2. Identifier les namespaces les plus bruyants

##### Timeline des alertes

1. Le graphique en haut de Discover montre la distribution temporelle
2. Cliquer sur une barre pour zoomer sur cette période
3. Pics = déploiements, incidents, ou activité suspecte

### Créer un Dashboard Kibana personnalisé

1. Menu (☰) → **Dashboard** → **Create dashboard**
2. Cliquer sur **"Create visualization"**

**Visualisation 1 : Top 10 des règles Falco**
- Type : **Bar Horizontal**
- Data source : **Falco Alerts**
- Vertical axis : Count
- Horizontal axis : `rule.keyword` (Top 10)

**Visualisation 2 : Alertes par priorité**
- Type : **Pie chart**
- Data source : **Falco Alerts**
- Slice by : `priority.keyword`

**Visualisation 3 : Timeline des alertes**
- Type : **Area chart**
- Data source : **Falco Alerts**
- Horizontal axis : `@timestamp`
- Vertical axis : Count

**Visualisation 4 : Top namespaces**
- Type : **Data table**
- Data source : **Falco Alerts**
- Rows : `k8s.ns.name.keyword`
- Metrics : Count

3. Cliquer sur **"Save"** pour chaque visualisation
4. Arranger les visualisations sur le dashboard
5. **Save dashboard** : "Falco Security Overview"

---

## Interprétation des données

### Scénarios normaux

#### 1. Après un déploiement
- **Symptôme** : Pic d'alertes sur 5-10 minutes
- **Règles** : "Drop and execute binary", "Contact K8S API Server"
- **Action** : Normal, surveiller que ça redescende

#### 2. CronJobs Trivy
- **Symptôme** : Alertes régulières toutes les heures
- **Règles** : "Contact K8S API Server From Container"
- **Namespace** : `trivy-system`
- **Action** : Normal si tuning pas appliqué, devrait être filtré après tuning

#### 3. Monitoring actif (Grafana, Prometheus)
- **Symptôme** : Flux constant d'alertes
- **Règles** : "Contact K8S API Server"
- **Namespace** : `security-siem`
- **Action** : Normal si tuning pas appliqué

### Scénarios suspects

#### 1. Shell interactif dans un container
- **Règle** : "Terminal shell in container"
- **Priorité** : Critical
- **Action** :
  1. Vérifier dans Kibana : quel pod, quelle image ?
  2. Est-ce un debug légitime ou une intrusion ?
  3. Si légitime : OK
  4. Si suspect : isoler le pod, investiguer

#### 2. Exécution de binaires inconnus
- **Règle** : "Drop and execute new binary in container"
- **Priorité** : Critical
- **Action** :
  1. Identifier le processus dans `proc.cmdline`
  2. Vérifier l'image : est-ce un build, un malware ?
  3. Si namespace applicatif : très suspect
  4. Analyser avec Trivy si possible

#### 3. Connexions réseau suspectes
- **Règle** : "Outbound connection to C2 server", "Network connection outside local subnet"
- **Priorité** : Critical
- **Action** :
  1. Noter l'IP de destination (`fd.rip`)
  2. Vérifier la réputation de l'IP
  3. Bloquer au niveau réseau si malveillant
  4. Investiguer le pod compromis

#### 4. Modification de fichiers système
- **Règle** : "Write below etc", "Write below binary dir"
- **Priorité** : Critical
- **Action** :
  1. Quel fichier a été modifié ? (`fd.name`)
  2. Par quel processus ? (`proc.cmdline`)
  3. Si non-légitime : container compromis
  4. Supprimer et redéployer

#### 5. Accès à des secrets/credentials
- **Règle** : "Read sensitive file untrusted", "The docker client is executed in a container"
- **Priorité** : Critical
- **Action** :
  1. Identifier le fichier accédé
  2. Vérifier si c'est un attaquant qui exfiltre des secrets
  3. Changer les credentials compromis
  4. Investiguer la source de l'intrusion

### Indicateurs de compromission (IoC)

**Alertes multiples en cascade** :
- Shell → Download binary → Execute → Outbound connection
- = Scénario d'attaque classique

**Actions recommandées** :
1. Isoler immédiatement le pod
2. Capturer les logs avec `kubectl logs`
3. Analyser l'image avec Trivy
4. Redéployer depuis une image propre
5. Investiguer comment l'attaquant est entré

---

## Alertes après tuning - À quoi s'attendre

### Volume d'alertes

**Avant tuning** :
- ~2000 alertes/h
- Beaucoup de bruit (monitoring, Trivy, système)

**Après tuning** (script 34-falco-tuning.sh) :
- ~50-100 alertes/h
- Principalement sur namespaces applicatifs
- Focus sur les vraies menaces

### Namespaces filtrés (considérés de confiance)

Les alertes de ces namespaces sont **exclues** après tuning :
- `kube-system` : Composants système K8s
- `kube-public`, `kube-node-lease` : Système K8s
- `security-siem` : Grafana, Prometheus, Elasticsearch, Kibana
- `security-detection` : Falco, Falcosidekick
- `trivy-system` : Scans de vulnérabilités
- `monitoring` : Outils de monitoring additionnels

### Alertes qui restent

Après tuning, vous verrez principalement :
- Alertes sur les **namespaces applicatifs** (`default`, vos apps)
- Activités **réellement suspectes** :
  - Shells interactifs non-prévus
  - Exécution de binaires téléchargés
  - Connexions réseau suspectes
  - Modifications de fichiers système

---

## Métriques Prometheus - Référence

Pour créer vos propres dashboards Grafana :

### Métriques disponibles

```promql
# Compteurs
falcosidekick_inputs                           # Total d'alertes reçues
falcosidekick_outputs{destination="..."}       # Alertes envoyées par destination
falco_events{rule="...", priority="..."}       # Événements par règle et priorité

# Taux
rate(falcosidekick_inputs[5m])                 # Taux d'alertes/sec
increase(falcosidekick_inputs[1h])             # Augmentation sur 1h

# Agrégations
sum by (destination) (falcosidekick_outputs)   # Total par destination
sum by (priority) (falco_events)               # Total par priorité
sum by (rule) (falco_events)                   # Total par règle

# Top N
topk(5, sum by (rule) (falco_events))          # Top 5 règles
topk(10, sum by (k8s_ns_name) (falco_events))  # Top 10 namespaces
```

---

## Maintenance et ajustements

### Ajouter des exclusions supplémentaires

Si vous avez d'autres namespaces de confiance à filtrer :

1. Éditer la ConfigMap :
   ```bash
   kubectl edit cm falco-rules-custom -n security-detection
   ```

2. Ajouter le namespace dans la liste `trusted_namespaces` :
   ```yaml
   - list: trusted_namespaces
     items: [kube-system, security-siem, trivy-system, mon-namespace-confiance]
   ```

3. Redémarrer Falco :
   ```bash
   kubectl rollout restart daemonset falco -n security-detection
   ```

### Ajuster les règles custom

Éditer les règles dans la ConfigMap `falco-rules-custom` :

```bash
kubectl edit cm falco-rules-custom -n security-detection
```

Après modification, redémarrer Falco pour appliquer.

---

## Ressources supplémentaires

- [Documentation Falco](https://falco.org/docs/)
- [Règles Falco par défaut](https://github.com/falcosecurity/rules)
- [Grafana Dashboards](https://grafana.com/docs/)
- [Kibana Query Language (KQL)](https://www.elastic.co/guide/en/kibana/current/kuery-query.html)

---

**Date de création** : 2025-11-13
**Version** : 1.0
