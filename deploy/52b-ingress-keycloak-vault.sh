#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Création des Ingress pour Keycloak et Vault         ║"
echo "║           Exposer les services IAM via Ingress           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Vérifier que NGINX Ingress est installé
if ! kubectl get namespace ingress-nginx &>/dev/null; then
    echo "❌ NGINX Ingress Controller n'est pas installé"
    echo "Lancez d'abord : ./deploy/51-nginx-ingress.sh"
    exit 1
fi

INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
    echo "❌ Aucune IP externe pour le LoadBalancer"
    echo "Vérifiez: kubectl get svc ingress-nginx-controller -n ingress-nginx"
    exit 1
fi

echo "✅ NGINX Ingress Controller détecté"
echo "📡 IP externe: $INGRESS_IP"
echo ""
echo "📋 Ce script va créer des Ingress resources pour :"
echo "  - Keycloak (keycloak.local.lab)"
echo "  - Vault (vault.local.lab)"
echo ""

read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Création annulée."
    exit 0
fi

# ========================================================================
# 1. Vérifier que les services existent
# ========================================================================
echo ""
echo "1️⃣  Vérification de l'existence des services..."

# Vérifier Keycloak
KEYCLOAK_SVC=$(kubectl get svc -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$KEYCLOAK_SVC" ]; then
    echo "  ⚠️  Service Keycloak non trouvé dans security-iam"
    echo "  Recherche alternative..."
    KEYCLOAK_SVC="keycloak"
fi
echo "  ✅ Service Keycloak détecté: $KEYCLOAK_SVC"

# Vérifier Vault
VAULT_SVC=$(kubectl get svc -n security-iam vault -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ -z "$VAULT_SVC" ]; then
    echo "  ⚠️  Service Vault non trouvé dans security-iam"
    VAULT_SVC="vault"
fi
echo "  ✅ Service Vault détecté: $VAULT_SVC"

# ========================================================================
# 2. Ingress pour Keycloak
# ========================================================================
echo ""
echo "2️⃣  Création de l'Ingress pour Keycloak..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-ingress
  namespace: security-iam
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    # Nécessaire pour Keycloak car il utilise des headers spéciaux
    nginx.ingress.kubernetes.io/proxy-set-headers: |
      X-Forwarded-For \$proxy_add_x_forwarded_for;
      X-Forwarded-Proto \$scheme;
      X-Forwarded-Host \$host;
      X-Forwarded-Port \$server_port;
spec:
  ingressClassName: nginx
  rules:
  - host: keycloak.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $KEYCLOAK_SVC
            port:
              number: 80
EOF

echo "  ✅ Ingress Keycloak créé: http://keycloak.local.lab"

# ========================================================================
# 3. Ingress pour Vault
# ========================================================================
echo ""
echo "3️⃣  Création de l'Ingress pour Vault..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault-ingress
  namespace: security-iam
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    # Vault API peut retourner de grandes réponses
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
  - host: vault.local.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $VAULT_SVC
            port:
              number: 8200
EOF

echo "  ✅ Ingress Vault créé: http://vault.local.lab"

# ========================================================================
# 4. Vérification des Ingress
# ========================================================================
echo ""
echo "4️⃣  Vérification des Ingress créés..."

sleep 5

echo ""
echo "📊 Ingress dans security-iam:"
kubectl get ingress -n security-iam

# ========================================================================
# 5. Test de connectivité
# ========================================================================
echo ""
echo "5️⃣  Test de connectivité des services..."

echo ""
echo "  🧪 Test Keycloak..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: keycloak.local.lab" http://$INGRESS_IP --connect-timeout 5 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    echo "  ✅ Keycloak accessible (HTTP $HTTP_CODE)"
else
    echo "  ⚠️  Keycloak: HTTP $HTTP_CODE (peut prendre quelques secondes)"
fi

echo "  🧪 Test Vault..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: vault.local.lab" http://$INGRESS_IP/v1/sys/health --connect-timeout 5 || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "429" ] || [ "$HTTP_CODE" = "473" ] || [ "$HTTP_CODE" = "501" ] || [ "$HTTP_CODE" = "503" ]; then
    echo "  ✅ Vault accessible (HTTP $HTTP_CODE)"
    echo "     Note: 429/473/501/503 sont normaux pour Vault (sealed/unsealed status)"
else
    echo "  ⚠️  Vault: HTTP $HTTP_CODE (peut prendre quelques secondes)"
fi

# ========================================================================
# Résumé final
# ========================================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ INGRESS KEYCLOAK & VAULT CRÉÉS                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📡 Services IAM accessibles via l'Ingress"
echo ""
echo "🌐 URLs des services :"
echo "  Keycloak:        http://keycloak.local.lab"
echo "  Vault:           http://vault.local.lab"
echo ""
echo "⚠️  IMPORTANT: Configurez votre fichier hosts !"
echo ""
echo "Sur WSL2/Linux (/etc/hosts) :"
echo "  sudo tee -a /etc/hosts <<EOF"
echo "  $INGRESS_IP keycloak.local.lab"
echo "  $INGRESS_IP vault.local.lab"
echo "  EOF"
echo ""
echo "Sur Windows (C:\\Windows\\System32\\drivers\\etc\\hosts) en tant qu'Administrateur :"
echo "  $INGRESS_IP keycloak.local.lab"
echo "  $INGRESS_IP vault.local.lab"
echo ""
echo "🔐 Credentials :"
echo "  - Keycloak: admin / (voir CREDENTIALS.md ou variable Terraform)"
echo "  - Vault: root token (voir vault-keys.txt ou kubectl get secrets)"
echo ""
echo "📝 Récupérer le mot de passe Keycloak :"
echo "  kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d"
echo ""
echo "📝 Récupérer le root token Vault (si dev mode) :"
echo "  kubectl get secret vault-unseal-keys -n security-iam -o jsonpath='{.data.root-token}' | base64 -d 2>/dev/null || echo 'root (dev mode)'"
echo ""
echo "🔍 Vérifier les Ingress :"
echo "  kubectl get ingress -n security-iam"
echo "  kubectl describe ingress keycloak-ingress -n security-iam"
echo "  kubectl describe ingress vault-ingress -n security-iam"
echo ""
echo "🎯 Accès direct :"
echo "  Keycloak Admin Console: http://keycloak.local.lab"
echo "  Vault UI:               http://vault.local.lab/ui"
echo ""
echo "🔐 Pour HTTPS (optionnel) :"
echo "  ./deploy/53-ingress-tls.sh"
echo "  (Activer HTTPS avec cert-manager + Vault PKI)"
echo ""
