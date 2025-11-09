#!/bin/bash
#
# Enterprise Security Stack - Vérification de l'environnement
# Ce script vérifie que tous les prérequis sont installés
#

set -e

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Enterprise Security Stack - Environment Check          ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

check_ok=true

# Fonction de vérification
check_tool() {
    local tool=$1
    local min_version=$2

    if command -v $tool &> /dev/null; then
        local version=$($tool --version 2>/dev/null | head -n1 || $tool version --short 2>/dev/null | head -n1)
        echo -e "${GREEN}✓${NC} $tool installé: $version"
    else
        echo -e "${RED}✗${NC} $tool n'est pas installé"
        check_ok=false
    fi
}

# Vérifications
echo -e "\n${YELLOW}Vérification des outils...${NC}"
check_tool docker
check_tool kubectl
check_tool helm
check_tool terraform
check_tool kind
check_tool git

# Vérifier Python et Ansible
if command -v python3 &> /dev/null; then
    python_version=$(python3 --version)
    echo -e "${GREEN}✓${NC} python3 installé: $python_version"

    if python3 -m pip show ansible &> /dev/null; then
        ansible_version=$(ansible --version | head -n1)
        echo -e "${GREEN}✓${NC} ansible installé: $ansible_version"
    else
        echo -e "${RED}✗${NC} ansible n'est pas installé"
        echo -e "${YELLOW}→${NC} Installer avec: pip3 install ansible kubernetes"
        check_ok=false
    fi
else
    echo -e "${RED}✗${NC} python3 n'est pas installé"
    check_ok=false
fi

# Vérifier Docker
echo -e "\n${YELLOW}Vérification de Docker...${NC}"
if docker info &> /dev/null; then
    docker_version=$(docker version --format '{{.Server.Version}}')
    echo -e "${GREEN}✓${NC} Docker fonctionne (version: $docker_version)"

    # Vérifier les ressources Docker
    echo -e "\n${YELLOW}Ressources Docker Desktop:${NC}"
    docker info 2>/dev/null | grep -E "CPUs:|Total Memory:" || echo "  Info non disponible"
else
    echo -e "${RED}✗${NC} Docker n'est pas démarré ou accessible"
    echo -e "${YELLOW}→${NC} Démarrer Docker Desktop"
    check_ok=false
fi

# Vérifier WSL2 (si Windows)
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "\n${YELLOW}Environnement WSL2 détecté${NC}"
    wsl_version=$(grep -oP '(?<=WSL)[0-9]+' /proc/version 2>/dev/null || echo "Unknown")
    echo -e "${GREEN}✓${NC} Running in WSL"
    echo -e "  Distro: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
fi

# Vérifier l'espace disque
echo -e "\n${YELLOW}Vérification de l'espace disque...${NC}"
available_space=$(df -h . | tail -1 | awk '{print $4}')
echo -e "  Espace disponible: $available_space"

required_space_gb=20
available_gb=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$available_gb" -lt "$required_space_gb" ]; then
    echo -e "${YELLOW}⚠${NC} Moins de ${required_space_gb}GB disponibles"
else
    echo -e "${GREEN}✓${NC} Espace disque suffisant"
fi

# Vérifier la connexion au cluster (si existe)
echo -e "\n${YELLOW}Vérification cluster Kubernetes...${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Cluster Kubernetes accessible"
    kubectl get nodes 2>/dev/null || true
else
    echo -e "${YELLOW}ℹ${NC} Aucun cluster Kubernetes actif (normal avant déploiement)"
fi

# Résumé final
echo ""
echo "═══════════════════════════════════════════════════════════"
if [ "$check_ok" = true ]; then
    echo -e "${GREEN}✓ Tous les prérequis sont installés !${NC}"
    echo ""
    echo "Vous pouvez maintenant déployer la stack:"
    echo -e "${YELLOW}  ./scripts/deploy-all.sh${NC}"
else
    echo -e "${RED}✗ Certains prérequis sont manquants${NC}"
    echo ""
    echo "Installez les outils manquants puis relancez ce script"
    echo ""
    echo "Guide d'installation : docs/WINDOWS11-SETUP.md"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""

$check_ok
