#!/bin/bash
# Script helper interactif pour construire et lancer les services Suricata via Docker Compose

set -e

# Répertoire du script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${SCRIPT_DIR}/suricata-build.conf"
ENTRYPOINT_FILE="${SCRIPT_DIR}/entrypoint.sh"
# Chemin où générer suricata.yaml sur l'hôte
SURICATA_YAML_HOST_PATH="${ROOT_DIR}/docker/run/etc/suricata.yaml"
DOCKER_COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"

# Options par défaut
MODE="ids"
INTERFACE="eth0"
HOME_NET="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
BUILD_NO_CACHE=false
RUN_DETACHED=false
RUNMODE="auto"

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
    # Assurer la compatibilité si l'ancien config existe
    BUILD_NO_CACHE=${BUILD_NO_CACHE:-false}
  fi
}

# Sauvegarder la configuration
save_config() {
  print_info "Sauvegarde de la configuration dans $CONFIG_FILE"
  cat > "$CONFIG_FILE" << EOF
MODE=$MODE
INTERFACE=$INTERFACE
HOME_NET=$HOME_NET
RUN_DETACHED=$RUN_DETACHED
RUNMODE=$RUNMODE
BUILD_NO_CACHE=$BUILD_NO_CACHE
EOF
}

# Vérifier que Docker et docker-compose sont installés
if ! command -v docker &> /dev/null; then
  print_error "Erreur: Docker n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi
if ! command -v docker-compose &> /dev/null; then
  print_error "Erreur: docker-compose n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi

# Charger la configuration existante
load_config

# Fonction pour demander le mode (IDS/IPS)
ask_mode() {
  print_title "MODE DE FONCTIONNEMENT SURICATA (IDS/IPS)"
  echo "Ce choix détermine si Suricata ajoute l'option '-q 0' (IPS) ou '-i <interface>' (IDS) au démarrage."
  echo "Il est passé au conteneur via la variable d'environnement MODE."
  echo "Modes disponibles:"
  echo "1) IDS - Détection seule (défaut)"
  echo "2) IPS - Prévention active (nécessite configuration NFQ ou autre)"
  
  ask_question "Choisissez le mode (sera passé via env var MODE) [1-2, défaut: $MODE]: "
  read -r choice
  
  case $choice in
    2)
      MODE="ips"
      print_info "Mode IPS sélectionné (Variable MODE='ips')"
      ;;
    *)
      MODE="ids"
      print_info "Mode IDS sélectionné (Variable MODE='ids')"
      ;;
  esac
}

# Fonction pour demander l'interface réseau
ask_interface() {
  print_title "INTERFACE RÉSEAU SURICATA (si mode IDS)"
  echo "Nom de l'interface réseau que Suricata écoutera DANS le conteneur (ex: eth0, enp0s3)."
  echo "Ce paramètre est utilisé par entrypoint.sh via la variable d'environnement INTERFACE uniquement si MODE=ids."
  echo "Avec network_mode: host, cela correspond généralement à une interface de l'hôte."
  echo "Interfaces réseau disponibles sur l'hôte (pour information):"
  
  # Lister les interfaces réseau disponibles sur l'hôte
  available_interfaces=$(ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}')
  echo "$available_interfaces"
  
  ask_question "Entrez l'interface réseau (sera passée via env var INTERFACE) [défaut: $INTERFACE]: "
  read -r input_interface
  
  if [ -n "$input_interface" ]; then
    INTERFACE="$input_interface"
  fi
  print_info "Interface sélectionnée pour Suricata (Variable INTERFACE='$INTERFACE')"
}

# Fonction pour demander HOME_NET
ask_home_net() {
  print_title "CONFIGURATION DE HOME_NET (pour suricata.yaml)"
  echo "Définit les réseaux considérés comme internes dans le fichier de configuration suricata.yaml."
  echo "Format: [192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
  
  ask_question "Entrez votre HOME_NET (sera écrit dans suricata.yaml) [défaut: $HOME_NET]: "
  read -r input_home_net
  
  if [ -n "$input_home_net" ]; then
    HOME_NET="$input_home_net"
  fi
  print_info "HOME_NET configuré pour suricata.yaml: $HOME_NET"
}

# Fonction pour demander le mode d'exécution (Runmode)
ask_runmode() {
  print_title "CONFIGURATION DU RUNMODE (pour suricata.yaml)"
  echo "Définit comment Suricata utilise les threads pour traiter les paquets (paramètre 'runmode' dans suricata.yaml)."
  echo "Modes disponibles:"
  echo "1) auto   - Automatique (défaut)"
  echo "2) workers - Un thread par CPU pour capture/traitement"
  echo "3) autofp  - Tente d'équilibrer les flux sur les threads"

  ask_question "Choisissez le mode d'exécution (sera écrit dans suricata.yaml) [1-3, défaut: $RUNMODE]: "
  read -r runmode_choice

  case $runmode_choice in
    2)
      RUNMODE="workers"
      print_info "Runmode 'workers' sélectionné pour suricata.yaml"
      ;;
    3)
      RUNMODE="autofp"
      print_info "Runmode 'autofp' sélectionné pour suricata.yaml"
      ;;
    *)
      RUNMODE="auto"
      print_info "Runmode 'auto' sélectionné pour suricata.yaml"
      ;;
  esac
}

# Fonction pour générer suricata.yaml sur l'hôte EN UTILISANT suricata.yaml.in comme modèle
generate_suricata_yaml() {
  local template_file="${ROOT_DIR}/suricata.yaml.in"
  local config_path="$SURICATA_YAML_HOST_PATH"
  print_info "Génération du fichier de configuration sur l'hôte ($config_path) à partir du modèle ($template_file)"

  # Vérifier si le fichier modèle existe
  if [ ! -f "$template_file" ]; then
    print_error "Erreur: Fichier modèle suricata.yaml.in non trouvé dans $template_file"
    exit 1
  fi

  # Créer le répertoire parent si nécessaire
  mkdir -p "$(dirname "$config_path")"

  # Copier d'abord le modèle vers la destination
  print_info "Copie de $template_file vers $config_path..."
  cp "$template_file" "$config_path"
  if [ $? -ne 0 ]; then
    print_error "Erreur lors de la copie du modèle vers $config_path"
    exit 1
  fi

  # Utiliser sed pour remplacer les placeholders DANS LE FICHIER COPIÉ (-i)
  # Adapter si d'autres placeholders sont utilisés.
  # Note: ceci est une approche simple. Une méthode plus robuste utiliserait peut-être un outil comme yq ou un script dédié.
  print_info "Application des modifications (HOME_NET, RUNMODE, chemins Docker...) à $config_path..."
  sed -i \
    -e "s|\$HOME_NET|$HOME_NET|g" \
    -e "s|\$RUNMODE|$RUNMODE|g" \
    -e "s|@e_logdir@|/var/log/suricata|g" \
    -e "s|@e_sysconfdir@|/etc/suricata|g" \
    -e "s|@e_rundir@|/var/run/suricata|g" \
    -e "s|@e_defaultruledir@|/etc/suricata/rules|g" \
    -e "s|@e_magic_file_comment@|# |g" \
    -e "s|@e_magic_file@|/usr/share/file/magic.mgc|g" \
    -e "s|@e_sghcachedir@|/var/lib/suricata/rules|g" \
    -e "s|@e_enable_evelog@|yes|g" \
    -e "s|@pfring_comment@|# |g" \
    -e "s|@napatech_comment@|# |g" \
    -e "s|@ndpi_comment@|# |g" \
    -e "/^suricata-version:/d" \
    -e "/^# This configuration file was generated by Suricata/d" \
    -e 's|rule-files:\n    - rules/suricata.rules|rule-files:\n    - /var/lib/suricata/rules/suricata.rules|g' \
    -e 's/request-body-limit: 100 KiB/request-body-limit: 100kB/g' \
    -e 's/response-body-limit: 100 KiB/response-body-limit: 100kB/g' \
    -e 's/ KiB/kB/g' \
    -e 's/ MiB/mb/g' \
    "$config_path"

  # Ajouter l'en-tête YAML requis s'il n'est pas déjà dans le .in (il l'est)
  # sed -i '1i %YAML 1.1\n---' "$config_path" # Déjà fait par le sed ci-dessus ou présent dans le .in

  # Vérifier la génération et les permissions
  if [ $? -ne 0 ]; then
    print_error "Erreur lors de l'application des modifications sed à $config_path"
    exit 1
  fi

  chmod 644 "$config_path"
  print_info "Vérification du fichier de configuration généré sur l'hôte :"
  ls -l "$config_path"
  # Afficher les premières lignes pour vérifier l'en-tête et les remplacements
  print_info "Contenu initial de $config_path :"
  head -n 20 "$config_path"
}

# Afficher le titre principal
clear
print_title "ASSISTANT DE BUILD ET RUN POUR SURICATA AVEC DOCKER COMPOSE"
echo "Ce script va configurer suricata.yaml, construire les images et lancer les services définis dans docker-compose.yml."
echo

# Demander toutes les options à l'utilisateur
ask_mode
ask_interface
ask_home_net
ask_runmode

# Sauvegarder la configuration mise à jour
save_config

# Générer le fichier suricata.yaml sur l'hôte avant le build/run
generate_suricata_yaml

# Afficher le récapitulatif
print_title "RÉCAPITULATIF DE LA CONFIGURATION"
print_info "- Mode Suricata (via env var MODE): $MODE"
print_info "- Interface Suricata (via env var INTERFACE, si MODE=ids): $INTERFACE"
print_info "- HOME_NET (dans $SURICATA_YAML_HOST_PATH): $HOME_NET"
print_info "- Runmode (dans $SURICATA_YAML_HOST_PATH): $RUNMODE"
print_info "- Fichier de config généré: $SURICATA_YAML_HOST_PATH"
print_info "- Utilisation de Tilt pour le développement et le lancement."

# Demander confirmation
ask_question "Continuer avec ces paramètres pour générer la config et lancer avec Tilt? (o/n)"
read -r confirm
if [[ ! "$confirm" =~ ^[oOyY]$ ]]; then
  print_warning "Opération annulée"
  exit 0
fi

# Vérifier si le fichier entrypoint.sh existe
if [ ! -f "$ENTRYPOINT_FILE" ]; then
  print_error "Erreur: Script entrypoint.sh non trouvé dans $ENTRYPOINT_FILE"
  exit 1
fi

# Vérifier si le fichier docker-compose.yml existe
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
  print_error "Erreur: Fichier docker-compose.yml non trouvé dans $DOCKER_COMPOSE_FILE"
  exit 1
fi

# Vérifier si le fichier Tiltfile existe
if [ ! -f "${ROOT_DIR}/Tiltfile" ]; then
  print_error "Erreur: Fichier Tiltfile non trouvé à la racine du projet."
  exit 1
fi

# Vérifier si Tilt est installé
if ! command -v tilt &> /dev/null; then
  print_error "Erreur: Tilt n'est pas installé ou n'est pas dans le PATH."
  print_info "Installation: https://docs.tilt.dev/install.html"
  exit 1
fi

print_title "LANCEMENT AVEC TILT"
print_info "Tilt va maintenant prendre en charge le build, le lancement et le live-reloading."

# La configuration est maintenant dans suricata.yaml et gérée par docker-compose.yml (lu par Tilt)
# Les variables MODE et INTERFACE sont passées via l'environnement dans docker-compose.yml
# Tilt les utilisera lors du lancement des conteneurs.

# Afficher la commande d'exécution
echo "Pour exécuter les services avec Tilt (interface web et live-reloading):"
echo "(Assurez-vous que le fichier $SURICATA_YAML_HOST_PATH existe)"
echo "tilt up"

echo ""
echo "Commandes utiles (une fois Tilt lancé):"
echo "- Interface web Tilt: Généralement http://localhost:10350 (vérifier la sortie de Tilt)"
echo "- Logs des services visibles dans l'interface Tilt."
echo "- Arrêter Tilt et les services: Ctrl+C dans le terminal où 'tilt up' est lancé."
echo "- Pour arrêter et supprimer les volumes (après arrêt de Tilt): docker-compose -f \"$DOCKER_COMPOSE_FILE\" down -v"
echo "- Accéder à l'interface web Suricata: http://localhost:5001 (ou l'IP de votre hôte Docker)"
echo ""

# Demander à l'utilisateur s'il souhaite exécuter maintenant
ask_question "Voulez-vous lancer les services avec 'tilt up' maintenant? (o/n)"
read -r response
if [[ "$response" =~ ^[oOyY]$ ]]; then
  print_info "Lancement de 'tilt up'... (Appuyez sur Ctrl+C pour arrêter)"
  tilt up
fi

