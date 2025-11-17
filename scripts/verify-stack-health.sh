#!/bin/bash

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Vérification Complète de la Stack de Sécurité        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

NAMESPACE="security-iam"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    1. KEYCLOAK (IAM)                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 État des Pods Keycloak:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o wide

echo ""
echo "🌐 Services Keycloak:"
kubectl get svc -n "$NAMESPACE" | grep keycloak | grep -v postgresql

echo ""
echo "🔌 Endpoints Keycloak:"
kubectl get endpoints -n "$NAMESPACE" | grep keycloak | grep -v postgresql

echo ""
echo "🌍 Ingress Keycloak:"
kubectl get ingress -n "$NAMESPACE" 2>/dev/null | grep keycloak || echo "   Aucun Ingress Keycloak trouvé"

echo ""
echo "💾 Base de Données Keycloak:"
KC_DB=$(kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak --tail=50 2>/dev/null | grep -i "database info" | tail -1)
if [ -n "$KC_DB" ]; then
    echo "   $KC_DB"
else
    echo "   ⚠️  Impossible de récupérer l'info DB"
fi

echo ""
echo "🔐 Test de Connexion Keycloak:"
KC_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')
if [ -n "$KC_POD" ]; then
    KC_HTTP=$(kubectl exec -n "$NAMESPACE" "$KC_POD" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/auth/ --connect-timeout 5 2>/dev/null || echo "000")
    if [ "$KC_HTTP" = "200" ] || [ "$KC_HTTP" = "303" ]; then
        echo "   ✅ Keycloak répond (HTTP $KC_HTTP)"
    else
        echo "   ❌ Keycloak ne répond pas (HTTP $KC_HTTP)"
    fi
else
    echo "   ⚠️  Aucun pod Keycloak trouvé"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              2. VAULT (Secrets Management)                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 État des Pods Vault:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o wide

echo ""
echo "🌐 Services Vault:"
kubectl get svc -n "$NAMESPACE" | grep vault

echo ""
echo "🌍 Ingress Vault:"
kubectl get ingress -n "$NAMESPACE" 2>/dev/null | grep vault || echo "   Aucun Ingress Vault trouvé"

echo ""
echo "🔒 Statut Vault (vault-0):"
VAULT_STATUS=$(kubectl exec -n "$NAMESPACE" vault-0 -- vault status 2>/dev/null || echo "Erreur")

if [ "$VAULT_STATUS" != "Erreur" ]; then
    echo "$VAULT_STATUS" | grep -E "Sealed|Initialized|HA Mode"

    # Vérifier si sealed
    if echo "$VAULT_STATUS" | grep -q "Sealed.*false"; then
        echo "   ✅ Vault-0 est UNSEALED (opérationnel)"
    else
        echo "   ⚠️  Vault-0 est SEALED (nécessite unseal)"
    fi

    # Vérifier HA
    if echo "$VAULT_STATUS" | grep -q "HA Mode.*raft"; then
        echo "   ✅ Mode Haute Disponibilité (Raft) activé"
    fi
else
    echo "   ❌ Impossible de récupérer le statut de Vault"
fi

echo ""
echo "🔒 Statut Vault (vault-1):"
kubectl exec -n "$NAMESPACE" vault-1 -- vault status 2>/dev/null | grep -E "Sealed|HA Mode" || echo "   ⚠️  Vault-1 non disponible"

echo ""
echo "🔒 Statut Vault (vault-2):"
kubectl exec -n "$NAMESPACE" vault-2 -- vault status 2>/dev/null | grep -E "Sealed|HA Mode" || echo "   ⚠️  Vault-2 non disponible"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              3. POSTGRESQL (Keycloak DB)                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 État du Pod PostgreSQL:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql -o wide

echo ""
echo "💾 PVC PostgreSQL:"
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql

echo ""
echo "🔍 Tables Keycloak dans PostgreSQL:"
PG_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
if [ -n "$PG_POD" ]; then
    TABLE_COUNT=$(kubectl exec -n "$NAMESPACE" "$PG_POD" -- \
        psql -U keycloak -d keycloak -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ' || echo "0")

    if [ "$TABLE_COUNT" != "0" ]; then
        echo "   ✅ PostgreSQL contient $TABLE_COUNT tables Keycloak"
    else
        echo "   ⚠️  PostgreSQL semble vide"
    fi
else
    echo "   ❌ Pod PostgreSQL introuvable"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                   4. INGRESS CONTROLLER                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 NGINX Ingress Controller:"
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller

echo ""
echo "🌐 Service Ingress (MetalLB):"
kubectl get svc -n ingress-nginx ingress-nginx-controller

echo ""
echo "🔗 IP Externe (MetalLB):"
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -n "$INGRESS_IP" ]; then
    echo "   ✅ IP MetalLB: $INGRESS_IP"
else
    echo "   ❌ Aucune IP externe assignée"
fi

echo ""
echo "📋 Liste des Ingress dans security-iam:"
kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "   Aucun Ingress configuré"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                     5. RÉSUMÉ GLOBAL                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Compte les composants opérationnels
KEYCLOAK_OK=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c "Running" || echo "0")
VAULT_OK=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c "Running" || echo "0")
PG_OK=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c "Running" || echo "0")

echo "État des Composants:"
echo "   Keycloak:   $KEYCLOAK_OK pod(s) Running"
echo "   Vault:      $VAULT_OK pod(s) Running"
echo "   PostgreSQL: $PG_OK pod(s) Running"

echo ""
echo "🔗 URLs d'Accès (si Ingress configuré):"
if [ -n "$INGRESS_IP" ]; then
    echo "   Keycloak: https://keycloak.local.lab:8443/auth/admin/"
    echo "   Vault:    https://vault.local.lab:8443/ui/"
    echo ""
    echo "   Vérifiez /etc/hosts:"
    echo "   $INGRESS_IP keycloak.local.lab vault.local.lab"
else
    echo "   ⚠️  Ingress IP non disponible"
fi

echo ""
echo "🔐 Credentials par Défaut:"
echo "   Keycloak Admin: admin / admin123"
echo "   PostgreSQL:     keycloak / keycloak123"
echo "   Vault Root:     Voir vault-keys.txt (si disponible)"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  ✅ VÉRIFICATION TERMINÉE                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
