#!/bin/bash
# Script helper pour construire l'image Docker de Suricata

set -e

# Répertoire du script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Vérifier si le fichier de configuration existe
CONFIG_FILE="${SCRIPT_DIR}/suricata-build.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Erreur: Fichier de configuration non trouvé: $CONFIG_FILE"
  echo "Veuillez d'abord exécuter le script configure-suricata.sh"
  exit 1
fi

# Charger la configuration
source "$CONFIG_FILE"

# Vérifier que Docker est installé
if ! command -v docker &> /dev/null; then
  echo "Erreur: Docker n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi

# Configurer le tag Docker par défaut si non spécifié
if [ -z "$DOCKER_TAG" ]; then
  DOCKER_TAG="suricata:latest"
fi

echo "=========================="
echo "Construction de l'image Docker Suricata"
echo "=========================="
echo "Tag Docker:               $DOCKER_TAG"
echo "Mode IPS:                 $IPS_MODE"
echo "Support Rust:             $RUST_SUPPORT"
echo "Installation automatique: $AUTO_SETUP"
echo "Branche Git:              $BRANCH"
echo "Interface:                $INTERFACE"
echo "HOME_NET:                 $HOME_NET"
echo "=========================="

# Demander confirmation
read -p "Continuer avec ces paramètres? (o/n): " confirm
if [[ ! "$confirm" =~ ^[oOyY]$ ]]; then
  echo "Construction annulée"
  exit 0
fi

# Vérifier si les scripts nécessaires existent
if [ ! -f "${SCRIPT_DIR}/entrypoint.sh" ]; then
  echo "Erreur: Script entrypoint.sh non trouvé"
  exit 1
fi

# Construire l'image Docker
echo "Construction de l'image Docker..."
docker build -t "$DOCKER_TAG" -f "$ROOT_DIR/Dockerfile" "$ROOT_DIR"

# Vérifier le succès de la construction
if [ $? -eq 0 ]; then
  echo "=========================="
  echo "Image Docker construite avec succès!"
  echo "Tag: $DOCKER_TAG"
  echo ""
  echo "Pour exécuter Suricata en mode IDS:"
  echo "docker run --rm --net=host $DOCKER_TAG --runmode=ids"
  echo ""
  echo "Pour exécuter Suricata en mode IPS (nécessite CAP_NET_ADMIN):"
  echo "docker run --rm --net=host --cap-add=NET_ADMIN $DOCKER_TAG --runmode=ips"
  echo ""
  echo "Pour analyser un fichier PCAP:"
  echo "docker run --rm -v /chemin/vers/pcaps:/pcaps $DOCKER_TAG --runmode=pcap -r /pcaps/capture.pcap"
  echo "=========================="
else
  echo "Erreur lors de la construction de l'image Docker"
  exit 1
fi
