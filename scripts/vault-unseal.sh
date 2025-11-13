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
if ! kubectl get pod -n security-iam vault-0 &>/dev/null; then
  echo -e "${RED}❌ Erreur: Pod vault-0 non trouvé dans namespace security-iam${NC}"
  exit 1
fi

# Vérifier le statut actuel
echo -e "${BLUE}📊 Vérification du statut de Vault...${NC}"
if kubectl exec -n security-iam vault-0 -- vault status &>/dev/null; then
  SEALED=$(kubectl exec -n security-iam vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed')
  if [ "$SEALED" = "false" ]; then
    echo -e "${GREEN}✅ Vault est déjà unsealed !${NC}"
    kubectl exec -n security-iam vault-0 -- vault status
    exit 0
  fi
fi

echo -e "${YELLOW}🔒 Vault est sealed. Unseal en cours...${NC}"
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

# Unseal avec la clé 1
echo -e "${BLUE}🔓 Unseal avec clé 1/3...${NC}"
kubectl exec -n security-iam vault-0 -- vault operator unseal "$KEY1" > /dev/null 2>&1
echo -e "${GREEN}  ✅ Clé 1 acceptée (Progression: 1/3)${NC}"

# Unseal avec la clé 2
echo -e "${BLUE}🔓 Unseal avec clé 2/3...${NC}"
kubectl exec -n security-iam vault-0 -- vault operator unseal "$KEY2" > /dev/null 2>&1
echo -e "${GREEN}  ✅ Clé 2 acceptée (Progression: 2/3)${NC}"

# Unseal avec la clé 3
echo -e "${BLUE}🔓 Unseal avec clé 3/3...${NC}"
kubectl exec -n security-iam vault-0 -- vault operator unseal "$KEY3" > /dev/null 2>&1
echo -e "${GREEN}  ✅ Clé 3 acceptée (Progression: 3/3)${NC}"
echo

# Vérifier le statut final
echo -e "${BLUE}📊 Statut final de Vault :${NC}"
echo -e "${GREEN}"
kubectl exec -n security-iam vault-0 -- vault status
echo -e "${NC}"

# Vérifier que c'est bien unsealed
SEALED=$(kubectl exec -n security-iam vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed')
if [ "$SEALED" = "false" ]; then
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║              ✅ Vault unsealed avec succès !              ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
  exit 0
else
  echo -e "${RED}❌ Erreur: Vault est toujours sealed${NC}"
  exit 1
fi
