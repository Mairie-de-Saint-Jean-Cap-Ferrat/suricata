#!/bin/bash
# Script helper interactif pour construire l'image Docker de Suricata

set -e

# Répertoire du script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${SCRIPT_DIR}/suricata-build.conf"

# Options par défaut
IPS_MODE="false"
RUST_SUPPORT="true"
AUTO_SETUP="install-full"
BRANCH="master"
INTERFACE=""
HOME_NET="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
EXTRA_CONFIGURE_OPTIONS=""
DOCKER_TAG="suricata:latest"

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

# Fonction pour afficher une question
ask_question() {
  echo -e "${CYAN}$1${NC}"
}

# Fonction pour afficher une information
print_info() {
  echo -e "${GREEN}$1${NC}"
}

# Fonction pour afficher une erreur
print_error() {
  echo -e "${RED}$1${NC}"
}

# Fonction pour afficher un avertissement
print_warning() {
  echo -e "${YELLOW}$1${NC}"
}

# Fonction pour charger une configuration existante
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    print_title "Configuration trouvée"
    echo "Une configuration existante a été trouvée:"
    cat "$CONFIG_FILE"
    
    ask_question "Voulez-vous utiliser cette configuration? (o/n)"
    read -r response
    if [[ "$response" =~ ^[oOyY]$ ]]; then
      source "$CONFIG_FILE"
      print_info "Configuration chargée"
      return 0
    fi
  fi
  return 1
}

# Fonction pour demander si on veut le mode IPS
ask_ips_mode() {
  print_title "Configuration du mode IPS"
  echo "Le mode IPS (Intrusion Prevention System) permet à Suricata de bloquer activement le trafic malveillant."
  echo "Par défaut, Suricata fonctionne en mode IDS (détection uniquement)."
  
  ask_question "Activer le mode IPS? (o/n) [défaut: n]"
  read -r response
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    IPS_MODE="true"
    print_info "Mode IPS activé"
  else
    IPS_MODE="false"
    print_info "Mode IDS activé (par défaut)"
  fi
}

# Fonction pour demander le support Rust
ask_rust_support() {
  print_title "Configuration du support Rust"
  echo "Rust est utilisé pour améliorer les performances et la sécurité de Suricata."
  
  ask_question "Activer le support Rust? (o/n) [défaut: o]"
  read -r response
  if [[ "$response" =~ ^[nN]$ ]]; then
    RUST_SUPPORT="false"
    print_info "Support Rust désactivé"
  else
    RUST_SUPPORT="true"
    print_info "Support Rust activé (par défaut)"
  fi
}

# Fonction pour demander le type d'installation
ask_auto_setup() {
  print_title "Type d'installation automatique"
  echo "1) install-conf  : Installation de base + configuration automatique"
  echo "2) install-rules : Installation de base + téléchargement des règles"
  echo "3) install-full  : Installation complète (configuration + règles)"
  
  ask_question "Choisissez le type d'installation [1-3, défaut: 3]"
  read -r choice
  
  case $choice in
    1)
      AUTO_SETUP="install-conf"
      print_info "Installation avec configuration automatique sélectionnée"
      ;;
    2)
      AUTO_SETUP="install-rules"
      print_info "Installation avec téléchargement des règles sélectionnée"
      ;;
    *)
      AUTO_SETUP="install-full"
      print_info "Installation complète sélectionnée (par défaut)"
      ;;
  esac
}

# Fonction pour demander la branche ou le tag
ask_branch() {
  print_title "Branche ou tag Git"
  echo "Vous pouvez spécifier une branche particulière (ex: master) ou un tag de version (ex: suricata-6.0.0)"
  
  ask_question "Entrez la branche ou le tag [défaut: master]"
  read -r branch
  
  if [ -n "$branch" ]; then
    BRANCH="$branch"
  fi
  print_info "Branche/tag sélectionné: $BRANCH"
}

# Fonction pour demander l'interface réseau
ask_interface() {
  print_title "Interface réseau"
  echo "Interfaces réseau disponibles:"
  
  # Lister les interfaces réseau disponibles (fonctionne sur la plupart des systèmes Linux)
  interfaces=$(ip -o link show | grep -v 'lo:' | awk -F': ' '{print $2}')
  echo "$interfaces"
  
  ask_question "Entrez l'interface réseau à surveiller [laisser vide pour configuration manuelle ultérieure]"
  read -r interface
  
  INTERFACE="$interface"
  if [ -n "$INTERFACE" ]; then
    print_info "Interface sélectionnée: $INTERFACE"
  else
    print_info "Aucune interface sélectionnée, configuration manuelle requise"
  fi
}

# Fonction pour demander le réseau HOME_NET
ask_home_net() {
  print_title "Configuration du réseau HOME_NET"
  echo "HOME_NET définit les réseaux considérés comme 'locaux' par Suricata."
  echo "Format: [192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
  
  ask_question "Entrez votre HOME_NET [défaut: $HOME_NET]"
  read -r home_net
  
  if [ -n "$home_net" ]; then
    HOME_NET="$home_net"
  fi
  print_info "HOME_NET configuré: $HOME_NET"
}

# Fonction pour demander des options de configuration supplémentaires
ask_configure_options() {
  print_title "Options de configuration supplémentaires"
  echo "Vous pouvez spécifier des options supplémentaires pour le script ./configure"
  echo "Exemple: --enable-debug --enable-profiling"
  
  ask_question "Entrez les options supplémentaires [laisser vide si aucune]"
  read -r options
  
  EXTRA_CONFIGURE_OPTIONS="$options"
  if [ -n "$EXTRA_CONFIGURE_OPTIONS" ]; then
    print_info "Options supplémentaires: $EXTRA_CONFIGURE_OPTIONS"
  else
    print_info "Aucune option supplémentaire"
  fi
}

# Fonction pour demander le tag Docker
ask_docker_tag() {
  print_title "Tag de l'image Docker"
  echo "Le tag permet d'identifier votre image Docker (ex: suricata:ips, suricata:latest)"
  
  ask_question "Entrez le tag pour l'image Docker [défaut: suricata:latest]"
  read -r tag
  
  if [ -n "$tag" ]; then
    DOCKER_TAG="$tag"
  fi
  print_info "Tag Docker: $DOCKER_TAG"
}

# Vérifier que Docker est installé
if ! command -v docker &> /dev/null; then
  print_error "Erreur: Docker n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi

# Vérifier si les scripts nécessaires existent
if [ ! -f "${SCRIPT_DIR}/entrypoint.sh" ]; then
  print_error "Erreur: Script entrypoint.sh non trouvé"
  exit 1
fi

# Afficher le titre principal
clear
print_title "ASSISTANT DE CONSTRUCTION D'IMAGE DOCKER SURICATA"
echo "Ce script va vous aider à configurer et construire une image Docker pour Suricata."
echo "À chaque étape, vous pourrez choisir les options souhaitées ou accepter les valeurs par défaut."
echo 

# Tenter de charger une configuration existante
if ! load_config; then
  # Si pas de configuration existante ou utilisateur ne veut pas l'utiliser, demander chaque option
  ask_ips_mode
  ask_rust_support
  ask_auto_setup
  ask_branch
  ask_interface
  ask_home_net
  ask_configure_options
  ask_docker_tag
  
  # Enregistrer la configuration
  mkdir -p "$SCRIPT_DIR"
  cat > "$CONFIG_FILE" << EOF
IPS_MODE=$IPS_MODE
RUST_SUPPORT=$RUST_SUPPORT
AUTO_SETUP=$AUTO_SETUP
BRANCH=$BRANCH
INTERFACE=$INTERFACE
HOME_NET=$HOME_NET
EXTRA_CONFIGURE_OPTIONS=$EXTRA_CONFIGURE_OPTIONS
DOCKER_TAG=$DOCKER_TAG
EOF
  print_info "Configuration enregistrée dans $CONFIG_FILE"
fi

# Afficher le récapitulatif
print_title "RÉCAPITULATIF DE LA CONFIGURATION"
echo "Tag Docker:               $DOCKER_TAG"
echo "Mode IPS:                 $IPS_MODE"
echo "Support Rust:             $RUST_SUPPORT"
echo "Installation automatique: $AUTO_SETUP"
echo "Branche Git:              $BRANCH"
echo "Interface:                $INTERFACE"
echo "HOME_NET:                 $HOME_NET"
echo "Options configure:        $EXTRA_CONFIGURE_OPTIONS"

# Demander confirmation
ask_question "Continuer avec ces paramètres? (o/n)"
read -r confirm
if [[ ! "$confirm" =~ ^[oOyY]$ ]]; then
  print_warning "Construction annulée"
  exit 0
fi

# Construire l'image Docker
print_title "CONSTRUCTION DE L'IMAGE DOCKER"
echo "Cette opération peut prendre plusieurs minutes..."
docker build -t "$DOCKER_TAG" -f "$ROOT_DIR/Dockerfile" "$ROOT_DIR"

# Vérifier le succès de la construction
if [ $? -eq 0 ]; then
  print_title "CONSTRUCTION TERMINÉE AVEC SUCCÈS"
  echo "Image Docker:  $DOCKER_TAG"
  echo 
  echo "Pour exécuter Suricata en mode IDS:"
  echo "docker run --rm --net=host $DOCKER_TAG --runmode=ids"
  echo 
  echo "Pour exécuter Suricata en mode IPS (nécessite CAP_NET_ADMIN):"
  echo "docker run --rm --net=host --cap-add=NET_ADMIN $DOCKER_TAG --runmode=ips"
  echo 
  echo "Pour analyser un fichier PCAP:"
  echo "docker run --rm -v /chemin/vers/pcaps:/pcaps $DOCKER_TAG --runmode=pcap -r /pcaps/capture.pcap"
else
  print_error "Erreur lors de la construction de l'image Docker"
  exit 1
fi
