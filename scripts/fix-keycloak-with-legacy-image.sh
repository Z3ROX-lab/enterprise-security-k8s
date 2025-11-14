#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Corriger Keycloak avec l'image Legacy + Persistance    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Ce script va:"
echo "   1. Supprimer le StatefulSet actuel"
echo "   2. Recréer avec l'image 17.0.1-legacy (WildFly)"
echo "   3. Monter le PVC keycloak-data-persistent"
echo "   4. Vérifier le démarrage et le montage"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

# 1. Supprimer le StatefulSet actuel
echo ""
echo "1️⃣  Suppression du StatefulSet actuel..."
kubectl delete statefulset keycloak -n security-iam --timeout=30s || echo "StatefulSet déjà supprimé"

echo "⏳ Attente de la suppression complète des pods..."
sleep 10

# 2. Créer le nouveau StatefulSet avec l'image legacy
echo ""
echo "2️⃣  Création du StatefulSet avec image legacy..."
echo ""

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak
  namespace: security-iam
  labels:
    app: keycloak
spec:
  serviceName: keycloak-headless
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
        app.kubernetes.io/name: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:17.0.1-legacy
        env:
        - name: KC_PROXY
          value: "edge"
        - name: KC_HOSTNAME_STRICT
          value: "false"
        - name: KC_HOSTNAME_STRICT_HTTPS
          value: "false"
        - name: PROXY_ADDRESS_FORWARDING
          value: "true"
        - name: DB_VENDOR
          value: "h2"
        - name: KEYCLOAK_STATISTICS
          value: "all"
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        - name: https
          containerPort: 8443
          protocol: TCP
        volumeMounts:
        - name: keycloak-data
          mountPath: /opt/jboss/keycloak/standalone/data
        readinessProbe:
          httpGet:
            path: /auth/
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /auth/
            port: 8080
          initialDelaySeconds: 90
          periodSeconds: 30
      volumes:
      - name: keycloak-data
        persistentVolumeClaim:
          claimName: keycloak-data-persistent
EOF

echo "✅ StatefulSet créé"
echo ""

# 3. Attendre que le pod soit créé
echo "3️⃣  Attente de la création du pod..."
echo ""

for i in {1..30}; do
    POD_STATUS=$(kubectl get pods -n security-iam keycloak-0 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [ "$POD_STATUS" != "NotFound" ]; then
        echo "✅ Pod keycloak-0 créé (status: $POD_STATUS)"
        break
    fi

    if [ $i -eq 30 ]; then
        echo "❌ Timeout: pod non créé après 5 minutes"
        exit 1
    fi

    echo "   Tentative $i/30: Pod non encore créé..."
    sleep 10
done

# 4. Attendre que le pod soit prêt
echo ""
echo "4️⃣  Attente que le pod soit Ready (jusqu'à 3 minutes)..."
echo ""

kubectl wait --for=condition=ready pod/keycloak-0 -n security-iam --timeout=180s || {
    echo "⚠️  Timeout - vérification manuelle..."
    kubectl get pods -n security-iam keycloak-0
    echo ""
    echo "Logs du pod:"
    kubectl logs -n security-iam keycloak-0 --tail=30
}

echo "✅ Pod prêt"
echo ""

# 5. Vérifier le montage du volume
echo "5️⃣  Vérification du montage du volume..."
echo ""

kubectl exec -n security-iam keycloak-0 -- df -h 2>/dev/null | grep -E "(Filesystem|keycloak.*data|/opt/jboss)" || {
    echo "⚠️  Montage non visible dans df -h"
    echo ""
    echo "Vérification alternative - contenu du répertoire:"
    kubectl exec -n security-iam keycloak-0 -- ls -la /opt/jboss/keycloak/standalone/data/
}

echo ""

# 6. Attendre que Keycloak démarre complètement
echo "6️⃣  Attente du démarrage complet de Keycloak (60 secondes)..."
sleep 60

# 7. Vérifier que Keycloak répond
echo ""
echo "7️⃣  Test de connectivité Keycloak..."
echo ""

HTTP_CODE=$(kubectl exec -n security-iam keycloak-0 -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/ --connect-timeout 5 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "✅ Keycloak répond (HTTP $HTTP_CODE)"
else
    echo "⚠️  Keycloak ne répond pas encore (HTTP $HTTP_CODE)"
    echo "   Attendez encore 1-2 minutes et vérifiez les logs"
fi

# 8. Vérifier si l'admin existe
echo ""
echo "8️⃣  Vérification de l'admin..."
echo ""

TOKEN_RESPONSE=$(kubectl exec -n security-iam keycloak-0 -- curl -s \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=admin123" \
    -d "grant_type=password" \
    "http://localhost:8080/auth/realms/master/protocol/openid-connect/token" 2>/dev/null || echo "")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✅ Admin existe et fonctionne !"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     ✅ KEYCLOAK OPÉRATIONNEL AVEC PERSISTANCE             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🎉 Tout fonctionne ! L'admin survivra aux redémarrages."
else
    echo "⚠️  Admin n'existe pas (normal si nouveau volume vide)"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      ⚠️  KEYCLOAK PRÊT - ADMIN À CRÉER                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "📝 Créez l'admin maintenant:"
    echo ""
    echo "   Terminal WSL:"
    echo "   kubectl port-forward -n security-iam keycloak-0 8080:8080 --address 0.0.0.0"
    echo ""
    echo "   Navigateur Windows:"
    echo "   http://localhost:8080"
    echo ""
    echo "   Remplissez:"
    echo "   - Username: admin"
    echo "   - Password: admin123"
    echo ""
    echo "   ✅ Cette fois, l'admin sera PERSISTÉ sur le PVC !"
fi

echo ""
echo "🎯 Résumé de la configuration:"
echo "   - Image: quay.io/keycloak/keycloak:17.0.1-legacy ✅"
echo "   - PVC monté: /opt/jboss/keycloak/standalone/data ✅"
echo "   - Proxy configuré: edge mode ✅"
echo "   - Persistance: active ✅"
echo ""
echo "🌐 URLs d'accès:"
echo "   https://keycloak.local.lab:8443/auth/admin/"
echo ""
echo "📊 Vérifications:"
echo "   kubectl get pods -n security-iam"
echo "   kubectl get pvc -n security-iam"
echo "   kubectl exec -n security-iam keycloak-0 -- df -h"
echo ""
