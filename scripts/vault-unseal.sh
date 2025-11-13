#!/bin/bash

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              Vault Auto-Unseal Script                    ║"
echo "║           Récupération automatique des clés              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Aide
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage:"
    echo "  1. Depuis un fichier contenant la sortie de 'vault operator init' :"
    echo "     ./scripts/vault-unseal.sh vault-keys.txt"
    echo ""
    echo "  2. Depuis le secret Kubernetes (par défaut) :"
    echo "     ./scripts/vault-unseal.sh"
    echo ""
    exit 0
fi

# Vérifier que Vault pod existe
if ! kubectl get pod -n security-iam -l app.kubernetes.io/name=vault &>/dev/null; then
  echo -e "${RED}❌ Erreur: Aucun pod Vault trouvé dans namespace security-iam${NC}"
  exit 1
fi

# Détecter tous les pods Vault
VAULT_PODS=$(kubectl get pods -n security-iam -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^vault-[0-9]' || echo "")

if [ -z "$VAULT_PODS" ]; then
  echo -e "${RED}❌ Erreur: Aucun pod Vault trouvé${NC}"
  exit 1
fi

VAULT_PODS_ARRAY=($VAULT_PODS)
echo -e "${BLUE}📋 Pods Vault détectés: ${VAULT_PODS_ARRAY[@]}${NC}"

# Vérifier le statut de tous les pods
echo -e "${BLUE}📊 Vérification du statut de tous les pods Vault...${NC}"
ALL_UNSEALED=true
for POD in "${VAULT_PODS_ARRAY[@]}"; do
  if kubectl exec -n security-iam $POD -- vault status &>/dev/null; then
    SEALED=$(kubectl exec -n security-iam $POD -- vault status -format=json 2>/dev/null | jq -r '.sealed')
    if [ "$SEALED" = "true" ]; then
      ALL_UNSEALED=false
      echo -e "${YELLOW}  🔒 $POD est sealed${NC}"
    else
      echo -e "${GREEN}  ✅ $POD est unsealed${NC}"
    fi
  else
    ALL_UNSEALED=false
    echo -e "${YELLOW}  🔒 $POD est sealed${NC}"
  fi
done

if [ "$ALL_UNSEALED" = "true" ]; then
  echo -e "${GREEN}✅ Tous les pods Vault sont déjà unsealed !${NC}"
  exit 0
fi

echo -e "${YELLOW}🔒 Certains pods sont sealed. Unseal en cours...${NC}"
echo

# Déterminer la source des clés (fichier ou Kubernetes secret)
if [ -n "$1" ]; then
  # Mode FICHIER : lire depuis le fichier passé en argument
  if [ ! -f "$1" ]; then
    echo -e "${RED}❌ Erreur: Fichier '$1' non trouvé${NC}"
    exit 1
  fi

  echo -e "${BLUE}📄 Lecture des clés depuis le fichier: $1${NC}"

  # Parser les clés du fichier
  KEY1=$(grep "Unseal Key 1:" "$1" | awk '{print $NF}')
  KEY2=$(grep "Unseal Key 2:" "$1" | awk '{print $NF}')
  KEY3=$(grep "Unseal Key 3:" "$1" | awk '{print $NF}')

  if [ -z "$KEY1" ] || [ -z "$KEY2" ] || [ -z "$KEY3" ]; then
    echo -e "${RED}❌ Erreur: Impossible de lire les clés depuis le fichier${NC}"
    echo -e "${YELLOW}💡 Format attendu : sortie de 'vault operator init'${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ 3 clés récupérées depuis le fichier${NC}"
else
  # Mode KUBERNETES : lire depuis le secret (comportement par défaut)
  if ! kubectl get secret -n security-iam vault-unseal-keys &>/dev/null; then
    echo -e "${RED}❌ Erreur: Secret vault-unseal-keys non trouvé${NC}"
    echo -e "${YELLOW}💡 Utilisez: ./scripts/vault-unseal.sh vault-keys.txt${NC}"
    echo -e "${YELLOW}   Ou créez le secret avec: ./scripts/vault-save-keys.sh${NC}"
    exit 1
  fi

  echo -e "${BLUE}🔑 Récupération des clés depuis Kubernetes secret...${NC}"

  KEY1=$(kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data.unseal-key-1}' | base64 -d)
  KEY2=$(kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data.unseal-key-2}' | base64 -d)
  KEY3=$(kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data.unseal-key-3}' | base64 -d)

  if [ -z "$KEY1" ] || [ -z "$KEY2" ] || [ -z "$KEY3" ]; then
    echo -e "${RED}❌ Erreur: Impossible de récupérer les clés depuis le secret${NC}"
    echo -e "${YELLOW}💡 Utilisez: ./scripts/vault-unseal.sh vault-keys.txt${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ 3 clés récupérées depuis Kubernetes${NC}"
fi

echo

# Unseal tous les pods Vault
UNSEALED_COUNT=0
FAILED_COUNT=0

for POD in "${VAULT_PODS_ARRAY[@]}"; do
  # Vérifier si ce pod est déjà unsealed
  if kubectl exec -n security-iam $POD -- vault status &>/dev/null; then
    SEALED=$(kubectl exec -n security-iam $POD -- vault status -format=json 2>/dev/null | jq -r '.sealed')
    if [ "$SEALED" = "false" ]; then
      echo -e "${GREEN}⏭️  $POD déjà unsealed, skip${NC}"
      ((UNSEALED_COUNT++))
      continue
    fi
  fi

  echo -e "${BLUE}🔓 Unseal de $POD...${NC}"

  # Unseal avec les 3 clés
  kubectl exec -n security-iam $POD -- vault operator unseal "$KEY1" > /dev/null 2>&1
  echo -e "${GREEN}  ✅ Clé 1/3 acceptée${NC}"

  kubectl exec -n security-iam $POD -- vault operator unseal "$KEY2" > /dev/null 2>&1
  echo -e "${GREEN}  ✅ Clé 2/3 acceptée${NC}"

  kubectl exec -n security-iam $POD -- vault operator unseal "$KEY3" > /dev/null 2>&1
  echo -e "${GREEN}  ✅ Clé 3/3 acceptée${NC}"

  # Vérifier que l'unseal a réussi
  SEALED=$(kubectl exec -n security-iam $POD -- vault status -format=json 2>/dev/null | jq -r '.sealed')
  if [ "$SEALED" = "false" ]; then
    echo -e "${GREEN}  ✅ $POD unsealed avec succès${NC}"
    ((UNSEALED_COUNT++))
  else
    echo -e "${RED}  ❌ $POD toujours sealed${NC}"
    ((FAILED_COUNT++))
  fi
  echo
done

# Résumé final
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Résumé final                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

for POD in "${VAULT_PODS_ARRAY[@]}"; do
  SEALED=$(kubectl exec -n security-iam $POD -- vault status -format=json 2>/dev/null | jq -r '.sealed')
  HA_MODE=$(kubectl exec -n security-iam $POD -- vault status -format=json 2>/dev/null | jq -r '.ha_mode' || echo "unknown")

  if [ "$SEALED" = "false" ]; then
    if [ "$HA_MODE" = "active" ]; then
      echo -e "${GREEN}  ✅ $POD: unsealed (HA Mode: active - LEADER)${NC}"
    else
      echo -e "${GREEN}  ✅ $POD: unsealed (HA Mode: $HA_MODE)${NC}"
    fi
  else
    echo -e "${RED}  ❌ $POD: sealed${NC}"
  fi
done

echo
if [ $FAILED_COUNT -eq 0 ]; then
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║         ✅ Tous les pods Vault unsealed avec succès !     ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
  exit 0
else
  echo -e "${RED}⚠️  $FAILED_COUNT pod(s) n'ont pas pu être unsealed${NC}"
  exit 1
fi
