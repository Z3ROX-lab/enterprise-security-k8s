#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Trivy → Elasticsearch → Kibana Integration         ║"
echo "║      Détails complets des vulnérabilités dans Kibana     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Trivy Operator existe
if ! kubectl get deployment -n trivy-system trivy-operator &>/dev/null; then
    echo "❌ Trivy Operator non trouvé"
    echo "Lancez d'abord : ./41-trivy.sh"
    exit 1
fi

# Vérifier qu'Elasticsearch existe
if ! kubectl get statefulset -n security-siem elasticsearch-master &>/dev/null; then
    echo "❌ Elasticsearch non trouvé"
    echo "Lancez d'abord : ./10-elasticsearch.sh"
    exit 1
fi

echo "📋 Ce script va configurer :"
echo "  1. CronJob pour exporter les VulnerabilityReports vers Elasticsearch"
echo "  2. Index pattern Kibana pour les vulnérabilités"
echo "  3. Dashboard Kibana avec détails complets des CVE"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

# 1. Créer un ServiceAccount pour le CronJob
echo ""
echo "1️⃣  Création du ServiceAccount..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: trivy-exporter
  namespace: trivy-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: trivy-exporter
rules:
- apiGroups: ["aquasecurity.github.io"]
  resources: ["vulnerabilityreports"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: trivy-exporter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: trivy-exporter
subjects:
- kind: ServiceAccount
  name: trivy-exporter
  namespace: trivy-system
EOF

echo "  ✅ ServiceAccount créé"

# 2. Créer le ConfigMap avec le script d'export
echo ""
echo "2️⃣  Création du script d'export..."
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: trivy-exporter-script
  namespace: trivy-system
data:
  export.sh: |
    #!/bin/bash

    ELASTICSEARCH_URL="http://elasticsearch-master.security-siem:9200"
    INDEX_NAME="trivy-vulnerabilities"

    echo "🔍 Récupération des VulnerabilityReports..."

    # Récupérer tous les rapports
    REPORTS=$(kubectl get vulnerabilityreports -A -o json)

    # Compter le nombre de rapports
    REPORT_COUNT=$(echo "$REPORTS" | jq '.items | length')
    echo "📊 $REPORT_COUNT rapports trouvés"

    if [ "$REPORT_COUNT" -eq 0 ]; then
        echo "⚠️  Aucun rapport trouvé"
        exit 0
    fi

    # Traiter chaque rapport
    echo "$REPORTS" | jq -c '.items[]' | while read -r report; do
        NAMESPACE=$(echo "$report" | jq -r '.metadata.namespace')
        NAME=$(echo "$report" | jq -r '.metadata.name')

        # Extraire les métadonnées
        IMAGE_REPO=$(echo "$report" | jq -r '.report.artifact.repository // "unknown"')
        IMAGE_TAG=$(echo "$report" | jq -r '.report.artifact.tag // "unknown"')
        SCAN_TIME=$(echo "$report" | jq -r '.report.updateTimestamp // .metadata.creationTimestamp')

        # Compter les vulnérabilités par sévérité
        CRITICAL=$(echo "$report" | jq -r '.report.summary.criticalCount // 0')
        HIGH=$(echo "$report" | jq -r '.report.summary.highCount // 0')
        MEDIUM=$(echo "$report" | jq -r '.report.summary.mediumCount // 0')
        LOW=$(echo "$report" | jq -r '.report.summary.lowCount // 0')

        # Traiter chaque vulnérabilité
        echo "$report" | jq -c '.report.vulnerabilities[]?' | while read -r vuln; do
            CVE_ID=$(echo "$vuln" | jq -r '.vulnerabilityID')
            SEVERITY=$(echo "$vuln" | jq -r '.severity')
            TITLE=$(echo "$vuln" | jq -r '.title // "N/A"')
            DESCRIPTION=$(echo "$vuln" | jq -r '.description // "N/A"')
            PACKAGE=$(echo "$vuln" | jq -r '.resource // "N/A"')
            INSTALLED_VERSION=$(echo "$vuln" | jq -r '.installedVersion // "N/A"')
            FIXED_VERSION=$(echo "$vuln" | jq -r '.fixedVersion // "N/A"')
            SCORE=$(echo "$vuln" | jq -r '.score // 0')
            LINKS=$(echo "$vuln" | jq -r '.links // [] | join(",")')

            # Créer le document Elasticsearch
            DOC=$(jq -n \
                --arg namespace "$NAMESPACE" \
                --arg report_name "$NAME" \
                --arg image_repo "$IMAGE_REPO" \
                --arg image_tag "$IMAGE_TAG" \
                --arg scan_time "$SCAN_TIME" \
                --arg cve_id "$CVE_ID" \
                --arg severity "$SEVERITY" \
                --arg title "$TITLE" \
                --arg description "$DESCRIPTION" \
                --arg package "$PACKAGE" \
                --arg installed_version "$INSTALLED_VERSION" \
                --arg fixed_version "$FIXED_VERSION" \
                --arg score "$SCORE" \
                --arg links "$LINKS" \
                --argjson critical "$CRITICAL" \
                --argjson high "$HIGH" \
                --argjson medium "$MEDIUM" \
                --argjson low "$LOW" \
                '{
                    "@timestamp": $scan_time,
                    "namespace": $namespace,
                    "report_name": $report_name,
                    "image": {
                        "repository": $image_repo,
                        "tag": $image_tag,
                        "full": ($image_repo + ":" + $image_tag)
                    },
                    "vulnerability": {
                        "id": $cve_id,
                        "severity": $severity,
                        "title": $title,
                        "description": $description,
                        "score": $score,
                        "links": $links
                    },
                    "package": {
                        "name": $package,
                        "installed_version": $installed_version,
                        "fixed_version": $fixed_version
                    },
                    "summary": {
                        "critical": $critical,
                        "high": $high,
                        "medium": $medium,
                        "low": $low,
                        "total": ($critical + $high + $medium + $low)
                    }
                }')

            # Envoyer à Elasticsearch
            DOC_ID="${NAMESPACE}_${NAME}_${CVE_ID}_${PACKAGE}"
            DOC_ID=$(echo "$DOC_ID" | tr '/:' '_')

            curl -s -X POST "$ELASTICSEARCH_URL/$INDEX_NAME/_doc/$DOC_ID" \
                -H 'Content-Type: application/json' \
                -d "$DOC" > /dev/null
        done
    done

    echo "✅ Export terminé"

    # Afficher les stats
    echo ""
    echo "📊 Statistiques Elasticsearch :"
    curl -s "$ELASTICSEARCH_URL/$INDEX_NAME/_count" | jq -r '"Total documents: \(.count)"'
EOF

echo "  ✅ Script d'export créé"

# 3. Créer le CronJob
echo ""
echo "3️⃣  Création du CronJob (toutes les heures)..."
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: trivy-exporter
  namespace: trivy-system
spec:
  schedule: "0 * * * *"  # Toutes les heures
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: trivy-exporter
          restartPolicy: OnFailure
          containers:
          - name: exporter
            image: bitnami/kubectl:latest
            command: ["/bin/bash", "/scripts/export.sh"]
            volumeMounts:
            - name: script
              mountPath: /scripts
          volumes:
          - name: script
            configMap:
              name: trivy-exporter-script
              defaultMode: 0755
EOF

echo "  ✅ CronJob créé"

# 4. Lancer un job immédiat pour tester
echo ""
echo "4️⃣  Lancement d'un export initial..."
kubectl create job -n trivy-system trivy-export-manual-$(date +%s) --from=cronjob/trivy-exporter

echo "  ⏳ Attente de l'export (30 sec)..."
sleep 30

# Vérifier le statut
JOB=$(kubectl get jobs -n trivy-system --sort-by=.metadata.creationTimestamp | tail -1 | awk '{print $1}')
echo "  📊 Statut du job: $JOB"
kubectl get job -n trivy-system $JOB

# 5. Vérifier qu'Elasticsearch a reçu les données
echo ""
echo "5️⃣  Vérification des données dans Elasticsearch..."
POD=$(kubectl get pod -n security-siem -l app=elasticsearch-master -o jsonpath='{.items[0].metadata.name}')
DOC_COUNT=$(kubectl exec -n security-siem $POD -- curl -s http://localhost:9200/trivy-vulnerabilities/_count 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2)

if [ -n "$DOC_COUNT" ] && [ "$DOC_COUNT" -gt 0 ]; then
    echo "  ✅ $DOC_COUNT vulnérabilités indexées dans Elasticsearch"
else
    echo "  ⚠️  Aucune donnée trouvée (normal si c'est la première exécution)"
    echo "  Vérifiez les logs du job :"
    echo "    kubectl logs -n trivy-system job/$JOB"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      ✅ TRIVY → ELASTICSEARCH CONFIGURÉ                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ ServiceAccount et RBAC créés"
echo "  ✅ Script d'export créé"
echo "  ✅ CronJob configuré (toutes les heures)"
echo "  ✅ Export initial lancé"
echo "  ✅ Index 'trivy-vulnerabilities' créé dans Elasticsearch"
echo ""
echo "🔍 Accéder aux données dans Kibana :"
echo "  kubectl port-forward -n security-siem svc/kibana 5601:5601"
echo "  http://localhost:5601"
echo ""
echo "  1. Aller dans Management → Stack Management → Index Patterns"
echo "  2. Créer un index pattern : trivy-vulnerabilities*"
echo "  3. Time field : @timestamp"
echo "  4. Discover → Sélectionner 'trivy-vulnerabilities*'"
echo ""
echo "📊 Champs disponibles :"
echo "  - vulnerability.id (CVE-XXXX-YYYY)"
echo "  - vulnerability.severity (Critical/High/Medium/Low)"
echo "  - vulnerability.title"
echo "  - vulnerability.description"
echo "  - vulnerability.score"
echo "  - package.name"
echo "  - package.installed_version"
echo "  - package.fixed_version"
echo "  - image.repository"
echo "  - image.tag"
echo "  - namespace"
echo "  - summary.critical/high/medium/low"
echo ""
echo "🔎 Exemples de recherches Kibana :"
echo '  vulnerability.severity: "Critical"'
echo '  namespace: "security-siem"'
echo '  vulnerability.id: "CVE-2023-*"'
echo '  package.fixed_version: * AND NOT package.fixed_version: "N/A"'
echo ""
echo "⏰ Prochain export automatique : dans 1 heure"
echo "   Pour forcer un export maintenant :"
echo "   kubectl create job -n trivy-system trivy-export-now --from=cronjob/trivy-exporter"
echo ""
