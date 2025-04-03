#!/bin/bash

# Script de configuration pour Suricata
set -e

# Options par défaut
IPS_MODE="false"
RUST_SUPPORT="true"
AUTO_SETUP="install-full"
BRANCH="master"
INTERFACE=""
HOME_NET="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
EXTRA_CONFIGURE_OPTIONS=""

# Fonction d'affichage d'aide
show_help() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --ips                       Active le mode IPS (Intrusion Prevention System)"
  echo "  --no-rust                   Désactive le support Rust"
  echo "  --auto-setup=TYPE           Type d'installation automatique (install-conf, install-rules, install-full)"
  echo "  --branch=BRANCH             Branche ou tag Git à utiliser"
  echo "  --interface=INTERFACE       Interface réseau principale à surveiller"
  echo "  --home-net=NETWORK          Réseau HOME_NET (format: [192.168.0.0/16,10.0.0.0/8])"
  echo "  --configure-options=OPTIONS Options supplémentaires pour ./configure"
  echo "  --help                      Affiche cette aide"
  exit 0
}

# Traitement des arguments
for arg in "$@"; do
  case $arg in
    --ips)
      IPS_MODE="true"
      shift
      ;;
    --no-rust)
      RUST_SUPPORT="false"
      shift
      ;;
    --auto-setup=*)
      AUTO_SETUP="${arg#*=}"
      shift
      ;;
    --branch=*)
      BRANCH="${arg#*=}"
      shift
      ;;
    --interface=*)
      INTERFACE="${arg#*=}"
      shift
      ;;
    --home-net=*)
      HOME_NET="${arg#*=}"
      shift
      ;;
    --configure-options=*)
      EXTRA_CONFIGURE_OPTIONS="${arg#*=}"
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      echo "Option inconnue: $arg"
      show_help
      ;;
  esac
done

# Création du fichier de configuration pour le Dockerfile
cat > suricata-build.conf << EOF
IPS_MODE=$IPS_MODE
RUST_SUPPORT=$RUST_SUPPORT
AUTO_SETUP=$AUTO_SETUP
BRANCH=$BRANCH
INTERFACE=$INTERFACE
HOME_NET=$HOME_NET
EXTRA_CONFIGURE_OPTIONS=$EXTRA_CONFIGURE_OPTIONS
EOF

echo "Configuration enregistrée dans suricata-build.conf:"
cat suricata-build.conf
echo ""
echo "Vous pouvez maintenant construire l'image Docker avec:"
echo "docker build -t suricata-image ." 