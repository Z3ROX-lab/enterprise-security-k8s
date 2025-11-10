#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           OPTIONNEL : Kibana Dashboard                   ║"
echo "║   (Problèmes connus - Utilisez Grafana à la place)       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  ATTENTION : Kibana a des problèmes de déploiement récurrents"
echo "   (pre-install hooks qui timeout)"
echo ""
echo "   Alternative recommandée : Grafana (déjà installé)"
echo "   - Ajouter Elasticsearch comme data source dans Grafana"
echo "   - Visualiser les logs via Grafana"
echo ""

read -p "Voulez-vous quand même installer Kibana ? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Installation annulée (recommandé)."
    exit 0
fi

# Vérifier qu'Elasticsearch est déployé
if ! kubectl get pod -n security-siem -l app=elasticsearch-master &>/dev/null; then
    echo "❌ Elasticsearch non trouvé"
    echo "Exécutez d'abord : ./02-monitoring.sh"
    exit 1
fi

echo ""
echo "📊 Déploiement de Kibana..."
helm upgrade --install kibana elastic/kibana \
  --namespace security-siem \
  --version 8.5.1 \
  --set resources.requests.memory=1Gi \
  --set persistence.enabled=false \
  --set elasticsearchHosts=http://elasticsearch-master:9200 \
  --timeout 15m \
  --wait || {
    echo ""
    echo "❌ Échec du déploiement de Kibana (attendu)"
    echo ""
    echo "Nettoyage recommandé :"
    echo "  helm uninstall kibana -n security-siem"
    echo "  kubectl delete job,pod -n security-siem -l app=kibana"
    echo ""
    echo "Utilisez Grafana à la place :"
    echo "  kubectl port-forward -n security-siem svc/prometheus-grafana 3000:80"
    echo "  http://localhost:3000 (admin/admin123)"
    exit 1
}

echo ""
echo "✅ Kibana déployé (rare !)"
echo ""
echo "Accès :"
echo "  kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
echo "  http://localhost:5601"
echo ""
