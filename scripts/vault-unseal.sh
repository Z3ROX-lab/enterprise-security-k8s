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

# Vérifier que le secret existe
if ! kubectl get secret -n security-iam vault-init &>/dev/null; then
  echo -e "${RED}❌ Erreur: Secret vault-init non trouvé${NC}"
  echo -e "${YELLOW}💡 Vault n'a peut-être pas été initialisé correctement${NC}"
  exit 1
fi

# Récupérer les 3 clés d'unseal
echo -e "${BLUE}🔑 Récupération des clés d'unseal depuis Kubernetes secret...${NC}"
KEY1=$(kubectl get secret -n security-iam vault-init -o jsonpath='{.data.unseal-key-1}' | base64 -d)
KEY2=$(kubectl get secret -n security-iam vault-init -o jsonpath='{.data.unseal-key-2}' | base64 -d)
KEY3=$(kubectl get secret -n security-iam vault-init -o jsonpath='{.data.unseal-key-3}' | base64 -d)

if [ -z "$KEY1" ] || [ -z "$KEY2" ] || [ -z "$KEY3" ]; then
  echo -e "${RED}❌ Erreur: Impossible de récupérer les clés d'unseal${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 3 clés récupérées${NC}"
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
