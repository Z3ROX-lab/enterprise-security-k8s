#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Falco → Elasticsearch Configuration                ║"
echo "║     Alertes Falco dans Kibana via Falcosidekick          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Falco existe
if ! kubectl get daemonset -n security-detection falco &>/dev/null; then
    echo "❌ Falco non trouvé dans le namespace security-detection"
    echo "Vérifiez que Falco est déployé"
    exit 1
fi

# Vérifier que Falcosidekick existe
if ! kubectl get deployment -n security-detection falco-falcosidekick &>/dev/null; then
    echo "❌ Falcosidekick non trouvé"
    echo "Falcosidekick doit être déployé avec Falco"
    exit 1
fi

# Vérifier qu'Elasticsearch existe
if ! kubectl get statefulset -n security-siem elasticsearch-master &>/dev/null; then
    echo "❌ Elasticsearch non trouvé"
    echo "Lancez d'abord : ./10-elasticsearch.sh"
    exit 1
fi

echo "✅ Tous les prérequis sont présents"
echo ""
echo "📋 Ce script va configurer :"
echo "  1. Récupération des credentials Elasticsearch"
echo "  2. Configuration de Falcosidekick pour exporter vers Elasticsearch"
echo "  3. Redémarrage de Falcosidekick"
echo "  4. Test avec génération d'alerte"
echo "  5. Vérification des données dans Elasticsearch"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuration annulée."
    exit 0
fi

# 1. Récupérer les credentials Elasticsearch
echo ""
echo "1️⃣  Récupération des credentials Elasticsearch..."

ELASTIC_PASSWORD=$(kubectl get secret -n security-siem elasticsearch-master-credentials -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$ELASTIC_PASSWORD" ]; then
    echo "❌ Échec de récupération du mot de passe Elasticsearch"
    exit 1
fi

echo "  ✅ Credentials récupérés"

# 2. Mettre à jour le secret Falcosidekick
echo ""
echo "2️⃣  Configuration de Falcosidekick pour Elasticsearch..."

# Encoder les valeurs en base64
ES_HOSTPORT=$(echo -n "https://elasticsearch-master.security-siem:9200" | base64 -w0)
ES_USERNAME=$(echo -n "elastic" | base64 -w0)
ES_PASSWORD=$(echo -n "$ELASTIC_PASSWORD" | base64 -w0)
ES_CHECKCERT=$(echo -n "false" | base64 -w0)

# Patcher le secret
kubectl patch secret falco-falcosidekick -n security-detection --type='json' -p='[
  {"op": "replace", "path": "/data/ELASTICSEARCH_HOSTPORT", "value": "'"$ES_HOSTPORT"'"},
  {"op": "replace", "path": "/data/ELASTICSEARCH_USERNAME", "value": "'"$ES_USERNAME"'"},
  {"op": "replace", "path": "/data/ELASTICSEARCH_PASSWORD", "value": "'"$ES_PASSWORD"'"},
  {"op": "replace", "path": "/data/ELASTICSEARCH_CHECKCERT", "value": "'"$ES_CHECKCERT"'"}
]'

echo "  ✅ Secret mis à jour"

# 3. Redémarrer Falcosidekick pour prendre en compte la nouvelle config
echo ""
echo "3️⃣  Redémarrage de Falcosidekick..."

kubectl rollout restart deployment -n security-detection falco-falcosidekick

echo "  ⏳ Attente du redémarrage..."
kubectl rollout status deployment -n security-detection falco-falcosidekick --timeout=120s

echo "  ✅ Falcosidekick redémarré"

# 4. Générer une alerte de test
echo ""
echo "4️⃣  Génération d'une alerte de test..."

# Créer un pod de test
kubectl run falco-test-alert --image=nginx --restart=Never 2>/dev/null || kubectl delete pod falco-test-alert --force --grace-period=0 2>/dev/null && kubectl run falco-test-alert --image=nginx --restart=Never

# Attendre que le pod démarre
sleep 3

# Exécuter un shell (déclenche une alerte Falco)
echo "  🔔 Déclenchement d'une alerte en exécutant un shell..."
kubectl exec falco-test-alert -- /bin/bash -c "echo 'Falco test alert'" 2>/dev/null || true

# Modifier /etc (autre alerte)
echo "  🔔 Déclenchement d'une alerte en modifiant /etc..."
kubectl exec falco-test-alert -- sh -c "echo 'test' >> /etc/hosts" 2>/dev/null || true

# Nettoyer
kubectl delete pod falco-test-alert --force --grace-period=0 2>/dev/null || true

echo "  ✅ Alertes de test générées"

# 5. Vérifier que les alertes arrivent dans Elasticsearch
echo ""
echo "5️⃣  Vérification des alertes dans Elasticsearch..."
echo "  ⏳ Attente de 10 secondes pour l'indexation..."
sleep 10

POD=$(kubectl get pod -n security-siem -l app=elasticsearch-master -o jsonpath='{.items[0].metadata.name}')
ALERT_COUNT=$(kubectl exec -n security-siem $POD -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/falco-*/_count" 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2)

if [ -n "$ALERT_COUNT" ] && [ "$ALERT_COUNT" -gt 0 ]; then
    echo "  ✅ $ALERT_COUNT alertes indexées dans Elasticsearch"
else
    echo "  ⚠️  Aucune alerte trouvée pour l'instant"
    echo "  Cela peut prendre quelques minutes pour les premières alertes"
    echo ""
    echo "  Vérifiez les logs de Falcosidekick :"
    echo "    kubectl logs -n security-detection -l app.kubernetes.io/name=falcosidekick --tail=50"
fi

# 6. Afficher un exemple d'alerte
if [ -n "$ALERT_COUNT" ] && [ "$ALERT_COUNT" -gt 0 ]; then
    echo ""
    echo "📊 Exemple d'alerte récente :"
    kubectl exec -n security-siem $POD -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/falco-*/_search?size=1&sort=time:desc&pretty" 2>/dev/null | grep -A 30 '"_source"' || true
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     ✅ FALCO → ELASTICSEARCH CONFIGURÉ                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ Falcosidekick configuré pour Elasticsearch"
echo "  ✅ Alertes exportées vers l'index 'falco-*'"
echo "  ✅ Falcosidekick UI toujours accessible"
echo ""
echo "🖥️  Accès aux interfaces :"
echo ""
echo "  📊 Falcosidekick UI (vue temps réel) :"
echo "     kubectl port-forward -n security-detection svc/falco-falcosidekick-ui 2802:2802"
echo "     http://localhost:2802"
echo ""
echo "  🔍 Kibana (analyse SIEM) :"
echo "     kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
echo "     http://localhost:5601"
echo ""
echo "📋 Créer le Data View dans Kibana :"
echo "  1. Stack Management → Data Views"
echo "  2. Create data view"
echo "  3. Name: 'Falco Alerts'"
echo "  4. Index pattern: 'falco-*'"
echo "  5. Timestamp field: 'time'"
echo "  6. Save"
echo ""
echo "  Puis Analytics → Discover → Sélectionner 'Falco Alerts'"
echo ""
echo "🧪 Générer de nouvelles alertes de test :"
echo ""
echo "  # Test 1: Shell interactif"
echo "  kubectl run test-shell --image=nginx"
echo "  kubectl exec -it test-shell -- /bin/bash"
echo "  exit"
echo "  kubectl delete pod test-shell"
echo ""
echo "  # Test 2: Modification de /etc"
echo "  kubectl run test-etc --image=nginx"
echo "  kubectl exec test-etc -- sh -c 'echo test >> /etc/passwd'"
echo "  kubectl delete pod test-etc"
echo ""
echo "  # Test 3: Lecture de fichier sensible"
echo "  kubectl run test-sensitive --image=nginx"
echo "  kubectl exec test-sensitive -- cat /etc/shadow 2>/dev/null || true"
echo "  kubectl delete pod test-sensitive"
echo ""
echo "📊 Champs disponibles dans Kibana :"
echo "  - output (description de l'alerte)"
echo "  - priority (Critical/Error/Warning/Notice/Informational/Debug)"
echo "  - rule (nom de la règle Falco déclenchée)"
echo "  - source (fichier ou process source)"
echo "  - tags (catégories)"
echo "  - output_fields.* (détails: container, namespace, pod, etc.)"
echo "  - hostname (nœud Kubernetes)"
echo ""
echo "🔍 Exemples de recherches Kibana :"
echo '  priority: "Critical"'
echo '  rule: "Terminal shell in container"'
echo '  output_fields.k8s_ns_name: "default"'
echo '  tags: "filesystem"'
echo ""
echo "💡 Vous avez maintenant :"
echo "  - Falcosidekick UI pour vue temps réel des alertes"
echo "  - Kibana pour analyse approfondie et corrélation avec Trivy"
echo "  - Index falco-* dans Elasticsearch"
echo ""
