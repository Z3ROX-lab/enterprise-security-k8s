#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Force retry des certificats TLS (reset backoff)     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📋 Problème détecté :"
echo "  Les certificats sont en exponential backoff à cause des"
echo "  échecs AVANT le fix RBAC. Ils ne réessayeront pas avant"
echo "  ~53 minutes !"
echo ""
echo "💡 Solution :"
echo "  Supprimer et recréer les Certificate resources pour forcer"
echo "  une nouvelle tentative immédiate (maintenant que le RBAC"
echo "  est corrigé)."
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Opération annulée."
    exit 0
fi

echo ""
echo "1️⃣  Vérification que le ClusterIssuer est Ready..."
ISSUER_READY=$(kubectl get clusterissuer vault-issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

if [ "$ISSUER_READY" != "True" ]; then
    echo "  ❌ Le ClusterIssuer n'est pas Ready !"
    echo "  État actuel :"
    kubectl get clusterissuer vault-issuer
    echo ""
    echo "  Vérifier les logs :"
    echo "  kubectl describe clusterissuer vault-issuer"
    exit 1
fi

echo "  ✅ ClusterIssuer Ready=True"

echo ""
echo "2️⃣  Liste des certificats actuels (en backoff) :"
kubectl get certificates -A

echo ""
echo "3️⃣  Suppression et recréation des Certificate resources..."
echo ""

# Grafana
echo "  🔄 Grafana..."
kubectl delete certificate grafana-tls -n security-siem --ignore-not-found=true
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-tls
  namespace: security-siem
spec:
  secretName: grafana-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  dnsNames:
    - grafana.local.lab
EOF
echo "     ✅ Grafana certificate recréé"

# Kibana
echo "  🔄 Kibana..."
kubectl delete certificate kibana-tls -n security-siem --ignore-not-found=true
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kibana-tls
  namespace: security-siem
spec:
  secretName: kibana-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  dnsNames:
    - kibana.local.lab
EOF
echo "     ✅ Kibana certificate recréé"

# Prometheus
echo "  🔄 Prometheus..."
kubectl delete certificate prometheus-tls -n security-siem --ignore-not-found=true
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: prometheus-tls
  namespace: security-siem
spec:
  secretName: prometheus-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  dnsNames:
    - prometheus.local.lab
EOF
echo "     ✅ Prometheus certificate recréé"

# Falco UI
echo "  🔄 Falco UI..."
kubectl delete certificate falco-ui-tls -n security-detection --ignore-not-found=true
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: falco-ui-tls
  namespace: security-detection
spec:
  secretName: falco-ui-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  dnsNames:
    - falco-ui.local.lab
EOF
echo "     ✅ Falco UI certificate recréé"

echo ""
echo "4️⃣  Attente de la génération des certificats (max 60s)..."
echo ""

for i in {1..12}; do
    READY_COUNT=$(kubectl get certificates -A -o json | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
    TOTAL_COUNT=$(kubectl get certificates -A -o json | jq '.items | length')

    echo "  Tentative $i/12: $READY_COUNT/$TOTAL_COUNT certificats prêts"

    if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
        echo "  ✅ Tous les certificats sont prêts !"
        break
    fi

    if [ $i -lt 12 ]; then
        sleep 5
    fi
done

echo ""
echo "5️⃣  État final des certificats :"
kubectl get certificates -A

echo ""

# Vérifier si tous les certificats sont prêts (sauf le test dans default)
READY_COUNT=$(kubectl get certificates -A -o json | jq '[.items[] | select(.metadata.namespace != "default") | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
EXPECTED_COUNT=4  # grafana, kibana, prometheus, falco-ui

if [ "$READY_COUNT" -eq "$EXPECTED_COUNT" ]; then
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║          ✅ TOUS LES CERTIFICATS TLS SONT PRÊTS           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🎉 Succès ! Le fix RBAC fonctionne et cert-manager génère"
    echo "   maintenant les certificats depuis Vault PKI."
    echo ""
    echo "🌐 Configuration du fichier hosts Windows :"
    echo "   Fichier : C:\\Windows\\System32\\drivers\\etc\\hosts"
    echo "   (Ouvrir en tant qu'administrateur avec Notepad)"
    echo ""
    LOADBALANCER_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "   Ajoutez ces lignes :"
    echo "   $LOADBALANCER_IP grafana.local.lab"
    echo "   $LOADBALANCER_IP kibana.local.lab"
    echo "   $LOADBALANCER_IP prometheus.local.lab"
    echo "   $LOADBALANCER_IP falco-ui.local.lab"
    echo ""
    echo "🔒 Accès HTTPS (après config hosts) :"
    echo "   - https://grafana.local.lab"
    echo "   - https://kibana.local.lab"
    echo "   - https://prometheus.local.lab"
    echo "   - https://falco-ui.local.lab"
    echo ""
    echo "⚠️  Note : Votre navigateur affichera un avertissement de sécurité"
    echo "   car le certificat est signé par une CA interne (Vault PKI)."
    echo "   C'est normal ! Cliquez sur 'Avancé' > 'Continuer vers le site'."
else
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║        ⚠️  CERTIFICATS PAS ENCORE PRÊTS ($READY_COUNT/$EXPECTED_COUNT)            ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "❌ Attendre quelques secondes de plus ou vérifier les logs :"
    echo ""
    echo "1. Vérifier les certificats individuellement :"
    echo "   kubectl describe certificate grafana-tls -n security-siem"
    echo ""
    echo "2. Vérifier les certificaterequests :"
    echo "   kubectl get certificaterequests -A"
    echo ""
    echo "3. Vérifier les logs cert-manager :"
    CERT_MANAGER_POD=$(kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[0].metadata.name}')
    echo "   kubectl logs -n cert-manager $CERT_MANAGER_POD --tail=50"
fi

echo ""
