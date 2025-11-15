#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Diagnostic et Correction Kibana Authentication       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

NAMESPACE="security-siem"
ES_POD="elasticsearch-master-0"

echo "1️⃣  Récupération des credentials du secret Kubernetes..."
USERNAME=$(kubectl get secret elasticsearch-master-credentials -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 -d)
PASSWORD=$(kubectl get secret elasticsearch-master-credentials -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

echo "   Username: $USERNAME"
echo "   Password: $PASSWORD"
echo ""

echo "2️⃣  Test de connexion à Elasticsearch avec ces credentials..."
AUTH_TEST=$(kubectl exec -n "$NAMESPACE" "$ES_POD" -- \
  curl -k -s -o /dev/null -w "%{http_code}" -u "$USERNAME:$PASSWORD" \
  https://localhost:9200/_cluster/health 2>/dev/null || echo "000")

if [ "$AUTH_TEST" = "200" ]; then
    echo "   ✅ Authentification Elasticsearch réussie (HTTP $AUTH_TEST)"
    echo ""
    echo "   Le problème vient probablement de Kibana, pas d'Elasticsearch."
    echo ""

    echo "3️⃣  Vérification de la configuration Kibana..."

    # Vérifier les logs Kibana
    echo "   Logs Kibana (erreurs récentes):"
    kubectl logs -n "$NAMESPACE" -l app=kibana --tail=20 2>/dev/null | grep -i "error\|authentication\|elastic" || echo "   Aucune erreur trouvée"

    echo ""
    echo "   Solution recommandée:"
    echo "   Redémarrer Kibana pour forcer la reconnexion :"
    echo "   kubectl rollout restart deployment/kibana-kibana -n $NAMESPACE"

else
    echo "   ❌ Authentification Elasticsearch ÉCHOUÉE (HTTP $AUTH_TEST)"
    echo ""
    echo "   Le mot de passe dans le secret ne correspond PAS au mot de passe Elasticsearch."
    echo ""

    echo "3️⃣  Réinitialisation du mot de passe 'elastic' dans Elasticsearch..."
    echo ""

    read -p "   Voulez-vous réinitialiser le mot de passe maintenant ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Opération annulée."
        echo ""
        echo "   Pour réinitialiser manuellement plus tard:"
        echo "   kubectl exec -n $NAMESPACE $ES_POD -- /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b"
        exit 0
    fi

    echo ""
    echo "   Génération d'un nouveau mot de passe..."

    # Réinitialiser le mot de passe
    RESET_OUTPUT=$(kubectl exec -n "$NAMESPACE" "$ES_POD" -- \
      /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b 2>&1)

    # Extraire le nouveau mot de passe
    NEW_PASSWORD=$(echo "$RESET_OUTPUT" | grep -oP "New value: \K.*" || echo "")

    if [ -z "$NEW_PASSWORD" ]; then
        echo "   ❌ Impossible d'extraire le nouveau mot de passe"
        echo "   Sortie complète:"
        echo "$RESET_OUTPUT"
        exit 1
    fi

    echo "   ✅ Nouveau mot de passe généré: $NEW_PASSWORD"
    echo ""

    echo "4️⃣  Mise à jour du secret Kubernetes..."

    kubectl create secret generic elasticsearch-master-credentials \
      --from-literal=username=elastic \
      --from-literal=password="$NEW_PASSWORD" \
      --namespace "$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f -

    echo "   ✅ Secret mis à jour"
    echo ""

    echo "5️⃣  Redémarrage de Kibana..."
    kubectl rollout restart deployment/kibana-kibana -n "$NAMESPACE"

    echo "   ⏳ Attente du redémarrage de Kibana (30 sec)..."
    sleep 30

    kubectl wait --for=condition=available deployment/kibana-kibana -n "$NAMESPACE" --timeout=180s || true

    echo ""
    echo "   ✅ Kibana redémarré"
    echo ""

    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              ✅ CORRECTION TERMINÉE !                     ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🔐 Nouveaux credentials Kibana:"
    echo "   Username: elastic"
    echo "   Password: $NEW_PASSWORD"
    echo ""
    echo "🌐 Accès Kibana:"
    echo "   URL: https://kibana.local.lab:8443/ (via Ingress)"
    echo "   OU"
    echo "   Port-forward: kubectl port-forward -n security-siem svc/kibana-kibana 5601:5601"
    echo "   URL: http://localhost:5601"
    echo ""
fi

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                   VÉRIFICATIONS FINALES                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 État des pods ELK Stack:"
kubectl get pods -n "$NAMESPACE" -l app=elasticsearch
kubectl get pods -n "$NAMESPACE" -l app=kibana

echo ""
echo "🌐 Services ELK Stack:"
kubectl get svc -n "$NAMESPACE" | grep -E "elasticsearch|kibana"

echo ""
echo "🌍 Ingress Kibana:"
kubectl get ingress -n "$NAMESPACE" 2>/dev/null | grep kibana || echo "   Aucun Ingress Kibana trouvé"

echo ""
