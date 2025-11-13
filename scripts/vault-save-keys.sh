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
echo "║         Vault - Sauvegarde des clés d'unseal             ║"
echo "║       Stockage dans Kubernetes secret vault-unseal-keys  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}📋 Ce script sauvegarde les clés Vault dans un secret Kubernetes${NC}"
echo -e "${YELLOW}   Utilisez-le après 'vault operator init'${NC}"
echo ""

# Fonction pour afficher l'aide
show_help() {
    echo "Usage:"
    echo "  1. Depuis un fichier vault-keys.txt :"
    echo "     ./scripts/vault-save-keys.sh vault-keys.txt"
    echo ""
    echo "  2. Depuis stdin (copier-coller la sortie de 'vault operator init') :"
    echo "     ./scripts/vault-save-keys.sh"
    echo ""
    echo "Format attendu (sortie de 'vault operator init') :"
    echo "  Unseal Key 1: xxxx"
    echo "  Unseal Key 2: xxxx"
    echo "  Unseal Key 3: xxxx"
    echo "  Unseal Key 4: xxxx"
    echo "  Unseal Key 5: xxxx"
    echo "  Initial Root Token: hvs.xxxx"
}

# Si --help demandé
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Déterminer la source des clés
if [ -n "$1" ]; then
    # Lecture depuis fichier
    if [ ! -f "$1" ]; then
        echo -e "${RED}❌ Erreur: Fichier '$1' non trouvé${NC}"
        exit 1
    fi
    echo -e "${BLUE}📄 Lecture des clés depuis le fichier: $1${NC}"
    INPUT_DATA=$(cat "$1")
else
    # Lecture depuis stdin
    echo -e "${BLUE}📝 Collez la sortie de 'vault operator init' (Ctrl+D pour terminer) :${NC}"
    echo ""
    INPUT_DATA=$(cat)
fi

# Parser les clés
echo -e "${BLUE}🔍 Extraction des clés...${NC}"

UNSEAL_KEY_1=$(echo "$INPUT_DATA" | grep "Unseal Key 1:" | awk '{print $NF}')
UNSEAL_KEY_2=$(echo "$INPUT_DATA" | grep "Unseal Key 2:" | awk '{print $NF}')
UNSEAL_KEY_3=$(echo "$INPUT_DATA" | grep "Unseal Key 3:" | awk '{print $NF}')
UNSEAL_KEY_4=$(echo "$INPUT_DATA" | grep "Unseal Key 4:" | awk '{print $NF}')
UNSEAL_KEY_5=$(echo "$INPUT_DATA" | grep "Unseal Key 5:" | awk '{print $NF}')
ROOT_TOKEN=$(echo "$INPUT_DATA" | grep "Initial Root Token:" | awk '{print $NF}')

# Vérifier que toutes les clés ont été trouvées
MISSING=0
if [ -z "$UNSEAL_KEY_1" ]; then echo -e "${RED}  ❌ Unseal Key 1 manquante${NC}"; MISSING=1; fi
if [ -z "$UNSEAL_KEY_2" ]; then echo -e "${RED}  ❌ Unseal Key 2 manquante${NC}"; MISSING=1; fi
if [ -z "$UNSEAL_KEY_3" ]; then echo -e "${RED}  ❌ Unseal Key 3 manquante${NC}"; MISSING=1; fi
if [ -z "$UNSEAL_KEY_4" ]; then echo -e "${RED}  ❌ Unseal Key 4 manquante${NC}"; MISSING=1; fi
if [ -z "$UNSEAL_KEY_5" ]; then echo -e "${RED}  ❌ Unseal Key 5 manquante${NC}"; MISSING=1; fi
if [ -z "$ROOT_TOKEN" ]; then echo -e "${RED}  ❌ Root Token manquant${NC}"; MISSING=1; fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo -e "${RED}❌ Erreur: Données incomplètes${NC}"
    echo ""
    show_help
    exit 1
fi

echo -e "${GREEN}✅ 5 clés d'unseal trouvées${NC}"
echo -e "${GREEN}✅ Root token trouvé${NC}"
echo ""

# Afficher un aperçu (masqué)
echo -e "${BLUE}📊 Aperçu des clés :${NC}"
echo -e "  Unseal Key 1: ${UNSEAL_KEY_1:0:10}...${UNSEAL_KEY_1: -5}"
echo -e "  Unseal Key 2: ${UNSEAL_KEY_2:0:10}...${UNSEAL_KEY_2: -5}"
echo -e "  Unseal Key 3: ${UNSEAL_KEY_3:0:10}...${UNSEAL_KEY_3: -5}"
echo -e "  Unseal Key 4: ${UNSEAL_KEY_4:0:10}...${UNSEAL_KEY_4: -5}"
echo -e "  Unseal Key 5: ${UNSEAL_KEY_5:0:10}...${UNSEAL_KEY_5: -5}"
echo -e "  Root Token: ${ROOT_TOKEN:0:10}...${ROOT_TOKEN: -5}"
echo ""

# Confirmation
read -p "Sauvegarder ces clés dans le secret Kubernetes ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Opération annulée${NC}"
    exit 0
fi

# Créer/Mettre à jour le secret Kubernetes
echo -e "${BLUE}💾 Sauvegarde dans le secret 'vault-unseal-keys' (namespace: security-iam)...${NC}"

kubectl create secret generic vault-unseal-keys -n security-iam \
  --from-literal=vault-root="$ROOT_TOKEN" \
  --from-literal=unseal-key-1="$UNSEAL_KEY_1" \
  --from-literal=unseal-key-2="$UNSEAL_KEY_2" \
  --from-literal=unseal-key-3="$UNSEAL_KEY_3" \
  --from-literal=unseal-key-4="$UNSEAL_KEY_4" \
  --from-literal=unseal-key-5="$UNSEAL_KEY_5" \
  --dry-run=client -o yaml | kubectl apply -f -

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Secret sauvegardé avec succès${NC}"
    echo ""
    echo -e "${BLUE}🔍 Vérification :${NC}"
    kubectl get secret -n security-iam vault-unseal-keys -o jsonpath='{.data}' | jq 'keys'
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    ✅ Clés Vault sauvegardées dans Kubernetes !          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}➡️  Prochaine étape :${NC}"
    echo -e "   Unseal Vault avec: ${GREEN}./scripts/vault-unseal.sh${NC}"
else
    echo -e "${RED}❌ Erreur lors de la sauvegarde du secret${NC}"
    exit 1
fi
