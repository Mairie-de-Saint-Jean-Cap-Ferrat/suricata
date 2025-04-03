#!/bin/bash
# Script helper interactif pour construire l'image Docker de Suricata

set -e

# Répertoire du script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${SCRIPT_DIR}/suricata-build.conf"

# Options par défaut
MODE="ids"
INTERFACE="eth0"
HOME_NET="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
DOCKER_TAG="suricata:latest"
BUILD_ARGS=""
VOLUME_LOGS="/var/log/suricata"
VOLUME_CONFIG="/etc/suricata"
RUN_DETACHED=false

# Couleurs pour une meilleure lisibilité
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonction pour afficher un titre
print_title() {
  echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Fonction pour afficher une information
print_info() {
  echo -e "${GREEN}$1${NC}"
}

# Fonction pour afficher une erreur
print_error() {
  echo -e "${RED}$1${NC}"
}

# Fonction pour afficher une question
ask_question() {
  echo -e "${CYAN}$1${NC}"
}

# Fonction pour afficher un avertissement
print_warning() {
  echo -e "${YELLOW}$1${NC}"
}

# Charger la configuration existante si elle existe
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    print_info "Chargement de la configuration depuis $CONFIG_FILE"
    source "$CONFIG_FILE"
  fi
}

# Sauvegarder la configuration
save_config() {
  print_info "Sauvegarde de la configuration dans $CONFIG_FILE"
  cat > "$CONFIG_FILE" << EOF
MODE=$MODE
INTERFACE=$INTERFACE
HOME_NET=$HOME_NET
DOCKER_TAG=$DOCKER_TAG
VOLUME_LOGS=$VOLUME_LOGS
VOLUME_CONFIG=$VOLUME_CONFIG
RUN_DETACHED=$RUN_DETACHED
EOF
}

# Vérifier que Docker est installé
if ! command -v docker &> /dev/null; then
  print_error "Erreur: Docker n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi

# Charger la configuration existante
load_config

# Fonction pour demander le mode (IDS/IPS)
ask_mode() {
  print_title "MODE DE FONCTIONNEMENT"
  echo "Modes disponibles:"
  echo "1) IDS - Détection d'intrusion uniquement (par défaut)"
  echo "2) IPS - Prévention d'intrusion (bloque les attaques)"
  
  ask_question "Choisissez le mode [1-2, défaut: $MODE]: "
  read -r choice
  
  case $choice in
    2)
      MODE="ips"
      print_info "Mode IPS sélectionné"
      ;;
    *)
      MODE="ids"
      print_info "Mode IDS sélectionné (par défaut)"
      ;;
  esac
}

# Fonction pour demander l'interface réseau
ask_interface() {
  print_title "INTERFACE RÉSEAU"
  echo "Interfaces réseau disponibles:"
  
  # Lister les interfaces réseau disponibles
  available_interfaces=$(ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}')
  echo "$available_interfaces"
  
  ask_question "Entrez l'interface réseau à surveiller [défaut: $INTERFACE]: "
  read -r input_interface
  
  if [ -n "$input_interface" ]; then
    INTERFACE="$input_interface"
  fi
  print_info "Interface sélectionnée: $INTERFACE"
}

# Fonction pour demander HOME_NET
ask_home_net() {
  print_title "RÉSEAU HOME_NET"
  echo "HOME_NET définit les réseaux considérés comme votre réseau interne."
  echo "Format: [192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
  
  ask_question "Entrez votre HOME_NET [défaut: $HOME_NET]: "
  read -r input_home_net
  
  if [ -n "$input_home_net" ]; then
    HOME_NET="$input_home_net"
  fi
  print_info "HOME_NET configuré: $HOME_NET"
}

# Fonction pour demander le tag Docker
ask_docker_tag() {
  print_title "TAG DOCKER"
  echo "Le tag permet d'identifier votre image Docker (ex: suricata:ips, suricata:latest)"
  
  ask_question "Entrez le tag pour l'image Docker [défaut: $DOCKER_TAG]: "
  read -r input_tag
  
  if [ -n "$input_tag" ]; then
    DOCKER_TAG="$input_tag"
  fi
  print_info "Tag Docker: $DOCKER_TAG"
}

# Fonction pour demander le chemin du volume de logs
ask_volume_logs() {
  print_title "VOLUME DE LOGS"
  echo "Chemin sur l'hôte où les logs de Suricata seront stockés"
  
  ask_question "Entrez le chemin pour les logs [défaut: $VOLUME_LOGS]: "
  read -r input_volume_logs
  
  if [ -n "$input_volume_logs" ]; then
    VOLUME_LOGS="$input_volume_logs"
  fi
  print_info "Volume logs: $VOLUME_LOGS"
}

# Fonction pour demander le chemin du volume de configuration
ask_volume_config() {
  print_title "VOLUME DE CONFIGURATION"
  echo "Chemin sur l'hôte où la configuration de Suricata sera stockée"
  
  ask_question "Entrez le chemin pour la configuration [défaut: $VOLUME_CONFIG]: "
  read -r input_volume_config
  
  if [ -n "$input_volume_config" ]; then
    VOLUME_CONFIG="$input_volume_config"
  fi
  print_info "Volume configuration: $VOLUME_CONFIG"
}

# Fonction pour demander si le conteneur doit tourner en mode détaché
ask_detached() {
  print_title "MODE DÉTACHÉ"
  echo "Le mode détaché permet d'exécuter le conteneur en arrière-plan"
  
  ask_question "Exécuter en mode détaché? (o/n) [défaut: non]: "
  read -r response
  
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    RUN_DETACHED=true
    print_info "Mode détaché activé"
  else
    RUN_DETACHED=false
    print_info "Mode détaché désactivé (par défaut)"
  fi
}

# Fonction pour demander si le cache Docker doit être utilisé
ask_no_cache() {
  print_title "UTILISATION DU CACHE"
  echo "Désactiver le cache permet d'obtenir les versions les plus récentes des paquets"
  
  ask_question "Désactiver le cache Docker? (o/n) [défaut: non]: "
  read -r response
  
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    BUILD_ARGS="$BUILD_ARGS --no-cache"
    print_info "Cache Docker désactivé"
  else
    print_info "Cache Docker activé (par défaut)"
  fi
}

# Afficher le titre principal
clear
print_title "ASSISTANT DE CONSTRUCTION D'IMAGE DOCKER SURICATA"
echo "Ce script va vous aider à construire une image Docker pour Suricata."
echo "À chaque étape, vous pourrez choisir les options souhaitées ou accepter les valeurs par défaut."
echo

# Demander toutes les options à l'utilisateur
ask_mode
ask_interface
ask_home_net
ask_docker_tag
ask_volume_logs
ask_volume_config
ask_detached
ask_no_cache

# Sauvegarder la configuration mise à jour
save_config

# Afficher le récapitulatif
print_title "RÉCAPITULATIF DE LA CONFIGURATION"
print_info "Mode: $MODE"
print_info "Interface: $INTERFACE"
print_info "HOME_NET: $HOME_NET"
print_info "Tag Docker: $DOCKER_TAG"
print_info "Volume logs: $VOLUME_LOGS"
print_info "Volume config: $VOLUME_CONFIG"
print_info "Mode détaché: $RUN_DETACHED"

# Demander confirmation
ask_question "Continuer avec ces paramètres? (o/n)"
read -r confirm
if [[ ! "$confirm" =~ ^[oOyY]$ ]]; then
  print_warning "Construction annulée"
  exit 0
fi

# Vérifier si le fichier entrypoint.sh existe
if [ ! -f "${SCRIPT_DIR}/entrypoint.sh" ]; then
  print_error "Erreur: Script entrypoint.sh non trouvé dans ${SCRIPT_DIR}"
  exit 1
fi

# Construire l'image Docker
print_title "CONSTRUCTION DE L'IMAGE DOCKER"
print_info "Exécution de la commande de build Docker..."

# Construire l'image Docker
docker build $BUILD_ARGS \
  --build-arg MODE="$MODE" \
  --build-arg INTERFACE="$INTERFACE" \
  --build-arg HOME_NET="$HOME_NET" \
  -t "$DOCKER_TAG" \
  -f "${ROOT_DIR}/Dockerfile" \
  "${ROOT_DIR}"

# Vérifier si la construction a réussi
if [ $? -eq 0 ]; then
  print_title "CONSTRUCTION RÉUSSIE"
  print_info "L'image Docker a été construite avec succès: $DOCKER_TAG"
  echo ""
  
  # Préparer la commande d'exécution
  DETACHED_FLAG=""
  if [ "$RUN_DETACHED" = true ]; then
    DETACHED_FLAG="-d"
  fi
  
  # Générer la commande d'exécution complète
  DOCKER_RUN_CMD="docker run $DETACHED_FLAG --name suricata --net=host --cap-add=NET_ADMIN --cap-add=NET_RAW"
  
  # Ajouter les volumes
  if [ -n "$VOLUME_LOGS" ]; then
    DOCKER_RUN_CMD="$DOCKER_RUN_CMD -v $VOLUME_LOGS:/var/log/suricata"
  fi
  
  if [ -n "$VOLUME_CONFIG" ]; then
    DOCKER_RUN_CMD="$DOCKER_RUN_CMD -v $VOLUME_CONFIG:/etc/suricata"
  fi
  
  # Ajouter les variables d'environnement
  DOCKER_RUN_CMD="$DOCKER_RUN_CMD -e INTERFACE=$INTERFACE -e HOME_NET=\"$HOME_NET\""
  
  # Ajouter le mode si c'est IPS
  if [ "$MODE" = "ips" ]; then
    DOCKER_RUN_CMD="$DOCKER_RUN_CMD -e MODE=ips"
  fi
  
  # Ajouter le tag de l'image
  DOCKER_RUN_CMD="$DOCKER_RUN_CMD $DOCKER_TAG"
  
  # Afficher la commande d'exécution
  echo "Pour exécuter le conteneur avec les paramètres actuels:"
  echo "$DOCKER_RUN_CMD"
  echo ""
  echo "Commandes utiles:"
  echo "- Voir les logs: docker logs suricata"
  echo "- Arrêter le conteneur: docker stop suricata"
  echo "- Redémarrer le conteneur: docker restart suricata"
  echo "- Supprimer le conteneur: docker rm suricata"
  echo ""
  
  # Demander à l'utilisateur s'il souhaite exécuter l'image maintenant
  ask_question "Voulez-vous exécuter l'image maintenant? (o/n)"
  read -r response
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    print_info "Exécution de l'image Docker..."
    eval $DOCKER_RUN_CMD
  fi
else
  print_error "La construction de l'image Docker a échoué."
  exit 1
fi

