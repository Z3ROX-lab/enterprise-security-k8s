#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Diagnostic et Configuration Admin Keycloak          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Vérifier le déploiement Keycloak
echo "1️⃣  Vérification du déploiement Keycloak..."
echo ""

KEYCLOAK_DEPLOYMENT=$(kubectl get deployment -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$KEYCLOAK_DEPLOYMENT" ]; then
    # Peut-être un StatefulSet
    KEYCLOAK_DEPLOYMENT=$(kubectl get statefulset -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    RESOURCE_TYPE="statefulset"
else
    RESOURCE_TYPE="deployment"
fi

if [ -z "$KEYCLOAK_DEPLOYMENT" ]; then
    echo "❌ Déploiement Keycloak non trouvé"
    kubectl get all -n security-iam | grep keycloak
    exit 1
fi

echo "  ✅ Déploiement trouvé: $KEYCLOAK_DEPLOYMENT ($RESOURCE_TYPE)"
echo ""

# 2. Vérifier les variables d'environnement actuelles
echo "2️⃣  Variables d'environnement Keycloak actuelles..."
echo ""

POD_NAME=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    echo "  Pod: $POD_NAME"
    echo ""
    echo "  Variables KEYCLOAK_ADMIN* :"
    kubectl exec -n security-iam $POD_NAME -- env | grep -i "KEYCLOAK_ADMIN" || echo "    ⚠️  Aucune variable KEYCLOAK_ADMIN trouvée"
    echo ""
fi

# 3. Vérifier les secrets
echo "3️⃣  Secrets Keycloak..."
echo ""

kubectl get secrets -n security-iam | grep keycloak || echo "  ⚠️  Aucun secret keycloak trouvé"
echo ""

# 4. Vérifier si un secret avec password existe
if kubectl get secret keycloak-env -n security-iam &>/dev/null; then
    echo "  ✅ Secret 'keycloak-env' existe"
    ADMIN_PASSWORD=$(kubectl get secret keycloak-env -n security-iam -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d || echo "")
    if [ -n "$ADMIN_PASSWORD" ]; then
        echo "  ✅ Mot de passe admin trouvé dans le secret"
    else
        echo "  ⚠️  Secret existe mais pas de KEYCLOAK_ADMIN_PASSWORD"
    fi
else
    echo "  ⚠️  Secret 'keycloak-env' non trouvé"
    ADMIN_PASSWORD=""
fi

echo ""

# 5. Proposer la création de l'admin
echo "4️⃣  Configuration de l'utilisateur admin..."
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
    echo "  Aucun mot de passe admin configuré."
    echo ""
    read -p "  Voulez-vous créer un admin avec mot de passe 'admin123' ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuration annulée."
        exit 0
    fi
    ADMIN_PASSWORD="admin123"
else
    echo "  Mot de passe admin existant: $ADMIN_PASSWORD"
    echo ""
    read -p "  Voulez-vous reconfigurer l'admin avec ce mot de passe ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuration annulée."
        exit 0
    fi
fi

# 6. Créer/Mettre à jour le secret
echo ""
echo "5️⃣  Création du secret avec credentials admin..."

kubectl create secret generic keycloak-env -n security-iam \
    --from-literal=KEYCLOAK_ADMIN=admin \
    --from-literal=KEYCLOAK_ADMIN_PASSWORD=$ADMIN_PASSWORD \
    --dry-run=client -o yaml | kubectl apply -f -

echo "  ✅ Secret créé/mis à jour"
echo ""

# 7. Identifier le type de déploiement et patcher
echo "6️⃣  Application des variables d'environnement..."
echo ""

if [ "$RESOURCE_TYPE" = "deployment" ]; then
    # C'est un Deployment
    kubectl patch deployment $KEYCLOAK_DEPLOYMENT -n security-iam -p '{
      "spec": {
        "template": {
          "spec": {
            "containers": [
              {
                "name": "keycloak",
                "env": [
                  {
                    "name": "KEYCLOAK_ADMIN",
                    "valueFrom": {
                      "secretKeyRef": {
                        "name": "keycloak-env",
                        "key": "KEYCLOAK_ADMIN"
                      }
                    }
                  },
                  {
                    "name": "KEYCLOAK_ADMIN_PASSWORD",
                    "valueFrom": {
                      "secretKeyRef": {
                        "name": "keycloak-env",
                        "key": "KEYCLOAK_ADMIN_PASSWORD"
                      }
                    }
                  }
                ]
              }
            ]
          }
        }
      }
    }'
else
    # C'est un StatefulSet
    kubectl patch statefulset $KEYCLOAK_DEPLOYMENT -n security-iam -p '{
      "spec": {
        "template": {
          "spec": {
            "containers": [
              {
                "name": "keycloak",
                "env": [
                  {
                    "name": "KEYCLOAK_ADMIN",
                    "valueFrom": {
                      "secretKeyRef": {
                        "name": "keycloak-env",
                        "key": "KEYCLOAK_ADMIN"
                      }
                    }
                  },
                  {
                    "name": "KEYCLOAK_ADMIN_PASSWORD",
                    "valueFrom": {
                      "secretKeyRef": {
                        "name": "keycloak-env",
                        "key": "KEYCLOAK_ADMIN_PASSWORD"
                      }
                    }
                  }
                ]
              }
            ]
          }
        }
      }
    }'
fi

echo "  ✅ Variables d'environnement appliquées"
echo ""

# 8. Attendre le redémarrage
echo "7️⃣  Redémarrage des pods Keycloak..."
echo "  ⏳ Attente du redémarrage (cela peut prendre 30-60 secondes)..."
echo ""

kubectl rollout status $RESOURCE_TYPE/$KEYCLOAK_DEPLOYMENT -n security-iam --timeout=120s || echo "  ⚠️  Timeout, vérifier manuellement"

# 9. Vérifier que les variables sont présentes
echo ""
echo "8️⃣  Vérification post-redémarrage..."
sleep 10

NEW_POD=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
echo "  Nouveau pod: $NEW_POD"
echo ""
echo "  Variables d'environnement :"
kubectl exec -n security-iam $NEW_POD -- env | grep "KEYCLOAK_ADMIN"

# 10. Instructions finales
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         ✅ ADMIN KEYCLOAK CONFIGURÉ                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔐 Credentials Keycloak Admin:"
echo "   Username: admin"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "🌐 URLs d'accès:"
echo "   Console Admin:  https://keycloak.local.lab:8443/admin"
echo "   Page d'accueil: https://keycloak.local.lab:8443"
echo ""
echo "⏳ Attendre 30 secondes supplémentaires pour que Keycloak démarre complètement"
echo ""
echo "🔍 Vérifier les logs si problème:"
echo "   kubectl logs -n security-iam $NEW_POD --tail=50"
echo ""
echo "🔄 Si le message 'local access required' persiste:"
echo "   1. Attendre 1-2 minutes (Keycloak initialise la DB)"
echo "   2. Rafraîchir la page"
echo "   3. Vider le cache du navigateur (Ctrl+Shift+R)"
echo ""
