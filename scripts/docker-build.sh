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

# Fonction pour demander si le conteneur doit tourner en mode détaché
ask_detached() {
  print_title "MODE DÉTACHÉ (pour docker-compose up)"
  echo "Exécute les conteneurs en arrière-plan (ajoute l'option '-d' à docker-compose up)."
  
  ask_question "Exécuter en mode détaché? (o/n) [défaut: $(if $RUN_DETACHED; then echo oui; else echo non; fi)]: "
  read -r response
  
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    RUN_DETACHED=true
    print_info "Mode détaché activé pour docker-compose up"
  else
    RUN_DETACHED=false
    print_info "Mode détaché désactivé pour docker-compose up"
  fi
}

# Fonction pour demander si le cache Docker doit être utilisé pour le build
ask_no_cache() {
  print_title "UTILISATION DU CACHE (pour docker-compose build)"
  echo "Désactiver le cache force la reconstruction de toutes les étapes du Dockerfile (ajoute `--no-cache` à docker-compose build)."
  
  ask_question "Désactiver le cache Docker pendant le build? (o/n) [défaut: $(if $BUILD_NO_CACHE; then echo oui; else echo non; fi)]: "
  read -r response
  
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    BUILD_NO_CACHE=true
    print_info "Cache Docker désactivé pour docker-compose build"
  else
    BUILD_NO_CACHE=false
    print_info "Cache Docker activé pour docker-compose build"
  fi
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
ask_no_cache
ask_detached

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
print_info "- Build sans cache: $BUILD_NO_CACHE"
print_info "- Exécution en mode détaché: $RUN_DETACHED"
print_info "- Fichier de config généré: $SURICATA_YAML_HOST_PATH"

# Demander confirmation
ask_question "Continuer avec ces paramètres pour construire et lancer avec docker-compose? (o/n)"
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

# Construire les images Docker via docker-compose
print_title "CONSTRUCTION DES IMAGES DOCKER VIA DOCKER-COMPOSE"
print_info "Exécution de la commande docker-compose build..."

COMPOSE_BUILD_ARGS=""
if [ "$BUILD_NO_CACHE" = true ]; then
  COMPOSE_BUILD_ARGS="--no-cache"
fi

docker-compose -f "$DOCKER_COMPOSE_FILE" build $COMPOSE_BUILD_ARGS

# Vérifier si la construction a réussi
if [ $? -eq 0 ]; then
  print_title "CONSTRUCTION RÉUSSIE"
  print_info "Les images Docker définies dans docker-compose.yml ont été construites avec succès."
  echo ""

  # Préparer la commande d'exécution docker-compose up
  COMPOSE_UP_ARGS=""
  if [ "$RUN_DETACHED" = true ]; then
    COMPOSE_UP_ARGS="-d"
  fi

  # La configuration est maintenant dans suricata.yaml et gérée par docker-compose.yml
  # Les variables MODE et INTERFACE sont passées via l'environnement dans docker-compose.yml
  # Si elles n'y sont pas, il faudrait les injecter ici :
  # export MODE=$MODE
  # export INTERFACE=$INTERFACE
  # (Mais docker-compose.yml les a déjà définies pour le service suricata)

  DOCKER_COMPOSE_UP_CMD="docker-compose -f \"$DOCKER_COMPOSE_FILE\" up $COMPOSE_UP_ARGS"

  # Afficher la commande d'exécution
  echo "Pour exécuter les services avec les paramètres actuels:"
  echo "(Assurez-vous que les variables d'environnement MODE et INTERFACE sont bien gérées par docker-compose.yml ou exportées)"
  echo "(Assurez-vous que le fichier $SURICATA_YAML_HOST_PATH existe et est correctement référencé dans docker-compose.yml)"
  echo "$DOCKER_COMPOSE_UP_CMD"
  echo ""
  echo "Commandes utiles (une fois lancé):"
  echo "- Voir les logs des services: docker-compose -f \"$DOCKER_COMPOSE_FILE\" logs -f"
  echo "- Voir les logs d'un service spécifique: docker-compose -f \"$DOCKER_COMPOSE_FILE\" logs -f suricata"
  echo "- Arrêter les services: docker-compose -f \"$DOCKER_COMPOSE_FILE\" down"
  echo "- Arrêter et supprimer les volumes: docker-compose -f \"$DOCKER_COMPOSE_FILE\" down -v"
  echo "- Accéder à l'interface web: http://localhost:5001 (ou l'IP de votre hôte Docker)"
  echo ""

  # Demander à l'utilisateur s'il souhaite exécuter maintenant
  ask_question "Voulez-vous lancer les services avec docker-compose up maintenant? (o/n)"
  read -r response
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    print_info "Lancement des services via docker-compose up..."
    eval $DOCKER_COMPOSE_UP_CMD
  fi
else
  print_error "La construction via docker-compose build a échoué."
  exit 1
fi

