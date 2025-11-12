#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                        Kibana                             ║"
echo "║           Dashboard de Visualisation pour ELK            ║"
echo "║          ⚠️  ATTENTION : Problèmes Connus                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  AVERTISSEMENT : Kibana a des problèmes récurrents :"
echo "   - Pre-install hooks qui timeout"
echo "   - Démarrage très lent"
echo "   - Pods en Error fréquents"
echo ""
echo "💡 Alternative recommandée :"
echo "   - Grafana (script ./14-grafana.sh)"
echo "   - Configurer Elasticsearch comme data source"
echo ""

read -p "Voulez-vous quand même installer Kibana ? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Installation annulée. Utilisez Grafana à la place."
    exit 0
fi

# Vérifier qu'Elasticsearch existe
if ! kubectl get statefulset elasticsearch-master -n security-siem &>/dev/null; then
    echo "❌ Elasticsearch non trouvé"
    echo "Lancez d'abord : ./10-elasticsearch.sh"
    exit 1
fi

# Ajouter le repo Helm
echo ""
echo "📦 Configuration du repository Helm..."
helm repo add elastic https://helm.elastic.co
helm repo update

# Nettoyer les anciennes ressources Kibana
echo ""
echo "🧹 Nettoyage des anciennes ressources Kibana..."
helm uninstall kibana -n security-siem 2>/dev/null || true
kubectl delete job,pod,configmap,secret,serviceaccount,role,rolebinding -n security-siem -l app=kibana --ignore-not-found=true
sleep 5

# Créer un fichier de configuration personnalisé pour Kibana
cat > /tmp/kibana-values.yaml <<EOF
elasticsearchHosts: "https://elasticsearch-master:9200"

extraEnvs:
  - name: ELASTICSEARCH_USERNAME
    valueFrom:
      secretKeyRef:
        name: elasticsearch-master-credentials
        key: username
  - name: ELASTICSEARCH_PASSWORD
    valueFrom:
      secretKeyRef:
        name: elasticsearch-master-credentials
        key: password

kibanaConfig:
  kibana.yml: |
    elasticsearch.username: "\${ELASTICSEARCH_USERNAME}"
    elasticsearch.password: "\${ELASTICSEARCH_PASSWORD}"
    elasticsearch.ssl.verificationMode: none

resources:
  requests:
    memory: 1Gi

persistence:
  enabled: false
EOF

# Déployer Kibana
echo ""
echo "📊 Déploiement de Kibana 8.5.1..."
helm upgrade --install kibana elastic/kibana \
  --namespace security-siem \
  --version 8.5.1 \
  --values /tmp/kibana-values.yaml \
  --timeout 15m \
  --wait=false

echo ""
echo "⏳ Attente de Kibana (peut prendre 10-15 min ou échouer)..."
for i in {1..30}; do
    STATUS=$(kubectl get pod -n security-siem -l app=kibana --no-headers 2>/dev/null | awk '{print $3}' || echo "Unknown")
    echo "  Check $i/30 - Status: $STATUS"

    if echo "$STATUS" | grep -q "Running"; then
        echo "✅ Kibana est Running !"
        break
    elif echo "$STATUS" | grep -q "Error\|CrashLoop"; then
        echo "❌ Kibana a échoué (attendu)"
        echo ""
        echo "Nettoyage recommandé :"
        echo "  helm uninstall kibana -n security-siem"
        echo "  kubectl delete job,pod -n security-siem -l app=kibana"
        echo ""
        echo "Utilisez Grafana à la place : ./14-grafana.sh"
        exit 1
    fi

    sleep 30
done

echo ""
echo "📊 État des pods :"
kubectl get pods -n security-siem -l app=kibana

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ KIBANA DÉPLOYÉ (vérifiez l'état)          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Accès au dashboard :"
echo "  kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
echo "  http://localhost:5601"
echo ""
