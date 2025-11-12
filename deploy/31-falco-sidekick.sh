#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              Falco → Sidekick → Elasticsearch             ║"
echo "║         Alertes runtime dans UI + Kibana SIEM             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que Falco existe
if ! kubectl get daemonset -n falco falco &>/dev/null; then
    echo "❌ Falco non trouvé"
    echo "Lancez d'abord : ./30-falco.sh"
    exit 1
fi

# Vérifier qu'Elasticsearch existe
if ! kubectl get statefulset -n security-siem elasticsearch-master &>/dev/null; then
    echo "❌ Elasticsearch non trouvé"
    echo "Lancez d'abord : ./10-elasticsearch.sh"
    exit 1
fi

echo "📋 Ce script va configurer :"
echo "  1. Falcosidekick - Router d'alertes Falco"
echo "  2. Falcosidekick UI - Interface web pour visualiser les alertes"
echo "  3. Export vers Elasticsearch - Alertes dans Kibana"
echo "  4. Reconfiguration de Falco pour utiliser Falcosidekick"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation annulée."
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

# 2. Créer un secret avec les credentials pour Falcosidekick
echo ""
echo "2️⃣  Création du secret Elasticsearch pour Falcosidekick..."

kubectl create secret generic falcosidekick-elasticsearch -n falco \
  --from-literal=username=elastic \
  --from-literal=password="$ELASTIC_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  ✅ Secret créé"

# 3. Ajouter le repo Helm Falcosecurity
echo ""
echo "3️⃣  Configuration du repository Helm..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

echo "  ✅ Repository configuré"

# 4. Créer le fichier de configuration pour Falcosidekick
echo ""
echo "4️⃣  Création de la configuration Falcosidekick..."

cat > /tmp/falcosidekick-values.yaml <<EOF
# Configuration Falcosidekick
config:
  debug: false

  # Elasticsearch configuration
  elasticsearch:
    hostport: https://elasticsearch-master.security-siem:9200
    index: falco
    type: _doc
    minimumpriority: ""
    suffix: daily
    username: elastic
    password: "${ELASTIC_PASSWORD}"
    customHeaders: ""
    checkcert: false

  # Webhook pour Falcosidekick UI
  webhook:
    address: http://falcosidekick-ui:2802/events
    minimumpriority: ""

webui:
  enabled: true

  # Configuration Redis pour stockage des événements
  redis:
    enabled: true
    storageEnabled: true

  service:
    type: ClusterIP
    port: 2802

  ingress:
    enabled: false

  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Service pour Falcosidekick
service:
  type: ClusterIP
  port: 2801

# Pas d'ingress pour l'instant (on utilisera port-forward)
ingress:
  enabled: false
EOF

echo "  ✅ Configuration créée"

# 5. Déployer Falcosidekick avec UI
echo ""
echo "5️⃣  Déploiement de Falcosidekick + UI..."

helm upgrade --install falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  --values /tmp/falcosidekick-values.yaml \
  --wait

echo "  ✅ Falcosidekick déployé"

# 6. Reconfigurer Falco pour envoyer les alertes à Falcosidekick
echo ""
echo "6️⃣  Reconfiguration de Falco pour utiliser Falcosidekick..."

# Obtenir les valeurs actuelles de Falco
helm get values falco -n falco > /tmp/falco-current-values.yaml 2>/dev/null || echo "{}" > /tmp/falco-current-values.yaml

# Ajouter la configuration pour Falcosidekick
cat > /tmp/falco-sidekick-config.yaml <<'EOF'
# Configuration Falco avec Falcosidekick
driver:
  kind: modern_ebpf
  ebpf:
    hostNetwork: true

falcosidekick:
  enabled: true
  fullfqdn: true

http_output:
  enabled: true
  url: http://falcosidekick:2801

json_output: true
json_include_output_property: true

resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1024Mi
EOF

# Upgrader Falco avec la nouvelle configuration
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/falco-sidekick-config.yaml \
  --wait

echo "  ✅ Falco reconfiguré"

# 7. Attendre que tous les pods soient prêts
echo ""
echo "7️⃣  Vérification du déploiement..."

echo "  ⏳ Attente des pods Falcosidekick..."
kubectl wait --for=condition=ready pod -n falco -l app.kubernetes.io/name=falcosidekick --timeout=120s 2>/dev/null || true

echo "  ⏳ Attente des pods Falcosidekick UI..."
kubectl wait --for=condition=ready pod -n falco -l app.kubernetes.io/name=falcosidekick-ui --timeout=120s 2>/dev/null || true

echo "  ⏳ Attente des pods Falco..."
kubectl wait --for=condition=ready pod -n falco -l app.kubernetes.io/name=falco --timeout=120s 2>/dev/null || true

echo ""
echo "📊 État des pods :"
kubectl get pods -n falco

# 8. Générer une alerte de test
echo ""
echo "8️⃣  Génération d'une alerte de test..."

# Créer un pod de test
kubectl run falco-test-alert --image=nginx --restart=Never 2>/dev/null || true
sleep 2

# Exécuter un shell (déclenche une alerte Falco)
echo "  🔔 Déclenchement d'une alerte en exécutant un shell..."
kubectl exec falco-test-alert -- /bin/bash -c "echo 'Falco test alert'" 2>/dev/null || true

# Nettoyer
kubectl delete pod falco-test-alert --force --grace-period=0 2>/dev/null || true

echo "  ✅ Alerte de test générée"

# 9. Vérifier que les alertes arrivent dans Elasticsearch
echo ""
echo "9️⃣  Vérification des alertes dans Elasticsearch..."
sleep 5

POD=$(kubectl get pod -n security-siem -l app=elasticsearch-master -o jsonpath='{.items[0].metadata.name}')
ALERT_COUNT=$(kubectl exec -n security-siem $POD -- curl -k -s -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/falco-*/_count" 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2)

if [ -n "$ALERT_COUNT" ] && [ "$ALERT_COUNT" -gt 0 ]; then
    echo "  ✅ $ALERT_COUNT alertes indexées dans Elasticsearch"
else
    echo "  ⚠️  Aucune alerte trouvée pour l'instant"
    echo "  Cela peut prendre quelques minutes pour les premières alertes"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        ✅ FALCOSIDEKICK + UI DÉPLOYÉS                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration terminée :"
echo "  ✅ Falcosidekick déployé et configuré"
echo "  ✅ Falcosidekick UI accessible"
echo "  ✅ Export vers Elasticsearch activé"
echo "  ✅ Falco reconfiguré pour utiliser Falcosidekick"
echo ""
echo "🖥️  Accès aux interfaces :"
echo ""
echo "  📊 Falcosidekick UI (vue temps réel des alertes) :"
echo "     kubectl port-forward -n falco svc/falcosidekick-ui 2802:2802"
echo "     http://localhost:2802"
echo ""
echo "  🔍 Kibana (analyse SIEM) :"
echo "     kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
echo "     http://localhost:5601"
echo ""
echo "  Pour créer le Data View dans Kibana :"
echo "     1. Stack Management → Data Views"
echo "     2. Create data view"
echo "     3. Name: 'Falco Alerts'"
echo "     4. Index pattern: 'falco-*'"
echo "     5. Timestamp field: '@timestamp' ou 'time'"
echo "     6. Save"
echo ""
echo "🧪 Générer des alertes de test :"
echo ""
echo "  # Test 1: Shell dans un conteneur"
echo "  kubectl run test-shell --image=nginx"
echo "  kubectl exec -it test-shell -- /bin/bash"
echo ""
echo "  # Test 2: Modification de /etc"
echo "  kubectl run test-etc --image=nginx"
echo "  kubectl exec test-etc -- sh -c 'echo test >> /etc/passwd'"
echo ""
echo "  # Test 3: Accès à des fichiers sensibles"
echo "  kubectl exec test-shell -- cat /etc/shadow"
echo ""
echo "📊 Champs disponibles dans Kibana :"
echo "  - output (description de l'alerte)"
echo "  - priority (Emergency/Alert/Critical/Error/Warning/Notice/Info/Debug)"
echo "  - rule (nom de la règle Falco déclenchée)"
echo "  - source (fichier ou process source)"
echo "  - tags (catégories)"
echo "  - output_fields.* (détails de l'événement)"
echo "  - hostname (nœud Kubernetes)"
echo ""
echo "🔍 Exemples de recherches Kibana :"
echo '  priority: "Critical"'
echo '  rule: "Terminal shell in container"'
echo '  output_fields.k8s.ns.name: "default"'
echo '  tags: "filesystem" OR tags: "network"'
echo ""
echo "💡 Architecture :"
echo "  Falco (DaemonSet) → Falcosidekick → ┬→ Falcosidekick UI"
echo "                                      └→ Elasticsearch → Kibana"
echo ""
