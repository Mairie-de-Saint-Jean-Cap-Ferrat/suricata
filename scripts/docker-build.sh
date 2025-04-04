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
  print_title "MODE DE FONCTIONNEMENT (pour entrypoint.sh)"
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
  print_title "INTERFACE RÉSEAU (pour entrypoint.sh)"
  echo "Interfaces réseau disponibles sur l'hôte (pour info):"
  
  # Lister les interfaces réseau disponibles sur l'hôte
  available_interfaces=$(ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}')
  echo "$available_interfaces"
  
  ask_question "Entrez l'interface réseau à surveiller par Suricata DANS le conteneur [défaut: $INTERFACE]: "
  read -r input_interface
  
  if [ -n "$input_interface" ]; then
    INTERFACE="$input_interface"
  fi
  print_info "Interface sélectionnée pour Suricata: $INTERFACE"
  print_warning "Assurez-vous que cette interface est accessible avec network_mode: host"
}

# Fonction pour demander HOME_NET
ask_home_net() {
  print_title "RÉSEAU HOME_NET (pour suricata.yaml)"
  echo "HOME_NET définit les réseaux considérés comme votre réseau interne."
  echo "Format: [192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
  
  ask_question "Entrez votre HOME_NET [défaut: $HOME_NET]: "
  read -r input_home_net
  
  if [ -n "$input_home_net" ]; then
    HOME_NET="$input_home_net"
  fi
  print_info "HOME_NET configuré: $HOME_NET"
}

# Fonction pour demander le mode d'exécution (Runmode)
ask_runmode() {
  print_title "MODE D'EXÉCUTION (RUNMODE pour suricata.yaml)"
  echo "Définit comment Suricata gère les threads et les paquets."
  echo "Modes disponibles:"
  echo "1) auto   - Automatique (par défaut, recommandé pour commencer)"
  echo "2) workers - Un thread par CPU pour la capture et le traitement"
  echo "3) autofp  - Mode "Auto Flow Pinned", essaie d'équilibrer les flux sur les threads"

  ask_question "Choisissez le mode d'exécution [1-3, défaut: $RUNMODE]: "
  read -r runmode_choice

  case $runmode_choice in
    2)
      RUNMODE="workers"
      print_info "Mode workers sélectionné"
      ;;
    3)
      RUNMODE="autofp"
      print_info "Mode autofp sélectionné"
      ;;
    *)
      RUNMODE="auto"
      print_info "Mode auto sélectionné (par défaut)"
      ;;
  esac
}

# Fonction pour demander si le conteneur doit tourner en mode détaché
ask_detached() {
  print_title "MODE DÉTACHÉ (pour docker-compose up)"
  echo "Le mode détaché permet d'exécuter les conteneurs en arrière-plan"
  
  ask_question "Exécuter en mode détaché? (o/n) [défaut: $(if $RUN_DETACHED; then echo oui; else echo non; fi)]: "
  read -r response
  
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    RUN_DETACHED=true
    print_info "Mode détaché activé"
  else
    RUN_DETACHED=false
    print_info "Mode détaché désactivé"
  fi
}

# Fonction pour demander si le cache Docker doit être utilisé pour le build
ask_no_cache() {
  print_title "UTILISATION DU CACHE (pour docker-compose build)"
  echo "Désactiver le cache force la reconstruction de toutes les étapes"
  
  ask_question "Désactiver le cache Docker pendant le build? (o/n) [défaut: $(if $BUILD_NO_CACHE; then echo oui; else echo non; fi)]: "
  read -r response
  
  if [[ "$response" =~ ^[oOyY]$ ]]; then
    BUILD_NO_CACHE=true
    print_info "Cache Docker désactivé pour le build"
  else
    BUILD_NO_CACHE=false
    print_info "Cache Docker activé pour le build (par défaut)"
  fi
}

# Fonction pour générer suricata.yaml sur l'hôte
generate_suricata_yaml() {
  local config_path="$SURICATA_YAML_HOST_PATH"
  print_info "Génération du fichier de configuration sur l'hôte: $config_path"

  # Créer le répertoire parent si nécessaire (normalement docker/run/etc/)
  mkdir -p "$(dirname "$config_path")"

  # Générer le fichier YAML
  cat > "$config_path" << EOF
# Fichier suricata.yaml généré par docker-build.sh
# Ce fichier sera monté en lecture seule dans le conteneur suricata.

# Pourcentage de paquets à traiter avant d'abandonner
max-pending-packets: 1024

# Configuration de base des variables
vars:
  # Chemin vers les fichiers de règles (relatif à /etc/suricata/ dans le conteneur)
  rule-files:
    - rules/suricata.rules # Assurez-vous que ce fichier existe dans le volume suricata-rules ou l'image

  # Variables d'adresses réseau
  address-groups:
    # Réseau local principal
    HOME_NET: "$HOME_NET"

    # Serveurs externes (pas HOME_NET)
    EXTERNAL_NET: "!\$HOME_NET"

    # Serveurs HTTP
    HTTP_SERVERS: "\$HOME_NET"

    # Serveurs SMTP
    SMTP_SERVERS: "\$HOME_NET"

    # Serveurs DNS
    DNS_SERVERS: "\$HOME_NET"

  # Variables de ports
  port-groups:
    # Ports HTTP
    HTTP_PORTS: "80"

    # Ports SSL/TLS
    SSL_PORTS: "443"

    # Ports SMTP
    SMTP_PORTS: "25"

    # Ports DNS
    DNS_PORTS: "53"

# Répertoire par défaut pour les logs (dans le conteneur)
default-log-dir: /var/log/suricata/

# Paramètres de classification (relatif à /etc/suricata/ dans le conteneur)
classification-file: /etc/suricata/classification.config
reference-config-file: /etc/suricata/reference.config

# Configuration de la capture de paquets (AF_PACKET) - L'interface est définie par la variable d'env $INTERFACE
# af-packet: # Cette section sera gérée dynamiquement par entrypoint.sh si besoin
#   - interface: default

# Configuration des threads et du mode d'exécution
threading:
  # set-cpu-affinity: yes # Commenté par défaut, activer si nécessaire
  runmode: $RUNMODE

# Activer le socket Unix pour l'API
unix-command:
  enabled: yes
  filename: suricata-command.socket # Sera créé dans /var/run/suricata/ grâce au volume

# Chemin vers le fichier PID
pid-file: /var/run/suricata/suricata.pid # Sera créé dans /var/run/suricata/ grâce au volume

# Configuration des sorties
outputs:
  # Sortie EVE JSON (recommandée pour l'interface web ou autre traitement)
  - eve-log:
      enabled: yes
      type: file
      filename: eve.json
      # Types d'événements à inclure
      types:
        - alert: {payload: yes, payload-buffer-size: 4kb, payload-printable: yes}
        - http: {extended: yes}
        - dns
        - tls: {extended: yes}
        - files: {force-magic: yes, force-hash: [md5,sha1,sha256]}
        - smtp
        - flow
        - netflow
        - stats: {interval: 8} # Stats toutes les 8 secondes
        - anomaly # Inclus les événements d'anomalie
      community-id: true # Activer l'ID de communauté

  # Sortie "fast log" (simple, pour les alertes)
  - fast:
      enabled: yes
      filename: fast.log

  # Sortie "stats.log" (plus détaillée que eve stats)
  - stats:
      enabled: yes
      filename: stats.log
      interval: 8
      totals: yes      # include totals
      threads: yes     # per thread stats
      # Per-protocol stats
      # decoder-events: yes
      # stream-events: yes

  # Sortie "unified2" (format binaire, pour Barnyard2 etc.)
  # - unified2-alert:
  #     enabled: yes
  #     filename: unified2.alert

# Actions en cas d'erreur
# engine-analysis:
  # rules-fast-pattern: yes

# Option pour exécuter en tant qu'utilisateur non-root après démarrage
# run-as:
  # user: suricata
  # group: suricata
EOF

  # Définir des permissions raisonnables pour le fichier généré
  chmod 644 "$config_path"
  # Essayer de définir le groupe si possible (peut échouer si l'utilisateur n'a pas les droits sur l'hôte)
  # chgrp suricata "$config_path" 2>/dev/null || true

  # Vérifier explicitement la création du fichier sur l'hôte
  print_info "Vérification du fichier de configuration généré sur l'hôte :"
  ls -l "$config_path"
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
print_info "Mode (pour entrypoint.sh): $MODE"
print_info "Interface (pour entrypoint.sh): $INTERFACE"
print_info "HOME_NET (pour suricata.yaml): $HOME_NET"
print_info "Runmode (pour suricata.yaml): $RUNMODE"
print_info "Build sans cache: $BUILD_NO_CACHE"
print_info "Exécution en mode détaché: $RUN_DETACHED"
print_info "Chemin du fichier de config généré: $SURICATA_YAML_HOST_PATH"

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

