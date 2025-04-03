#!/bin/bash

# Script de configuration pour Suricata
set -e

# Mode de fonctionnement par défaut
RUNMODE="auto"
ARGS=""

# Vérifier les arguments
for arg in "$@"; do
  case $arg in
    --runmode=*)
      RUNMODE="${arg#*=}"
      shift
      ;;
    *)
      # Passer les autres arguments à Suricata
      ARGS="$ARGS $arg"
      ;;
  esac
done

# Déterminer l'interface si non spécifiée
if ! grep -q "^  - interface:" /etc/suricata/suricata.yaml || grep -q "^  - interface: default" /etc/suricata/suricata.yaml; then
  # Trouver l'interface avec une adresse IP (exclut lo)
  INTERFACE=$(ip -o addr show | grep -v "lo:" | grep "inet " | head -n1 | awk '{print $2}')
  if [ -n "$INTERFACE" ]; then
    echo "Aucune interface spécifiée, utilisation automatique de: $INTERFACE"
    sed -i "s/^  - interface:.*$/  - interface: $INTERFACE/" /etc/suricata/suricata.yaml
  else
    echo "Aucune interface réseau trouvée, utilisation du mode pcap-file par défaut"
  fi
fi

# Mise à jour des règles de Suricata
echo "Mise à jour des règles Suricata..."
suricata-update

# Démarrage de Suricata en fonction du mode
case $RUNMODE in
  "ids")
    echo "Démarrage de Suricata en mode IDS"
    exec suricata -c /etc/suricata/suricata.yaml $ARGS
    ;;
  "ips")
    echo "Démarrage de Suricata en mode IPS inline"
    exec suricata -c /etc/suricata/suricata.yaml --runmode=workers $ARGS
    ;;
  "pcap")
    if [ -z "$ARGS" ]; then
      echo "Erreur: Le mode pcap nécessite de spécifier un fichier pcap"
      echo "Exemple: docker run --rm -v /path/to/pcaps:/pcaps suricata-image --runmode=pcap -r /pcaps/capture.pcap"
      exit 1
    fi
    echo "Analyse du fichier pcap"
    exec suricata -c /etc/suricata/suricata.yaml $ARGS
    ;;
  "auto"|*)
    # Vérifier si on peut utiliser NFQ pour le mode IPS
    if [ -d "/proc/sys/net/netfilter" ] && [ -e "/usr/lib/x86_64-linux-gnu/libnetfilter_queue.so.1" ]; then
      echo "Démarrage de Suricata en mode IPS avec NFQ"
      exec suricata -c /etc/suricata/suricata.yaml --runmode=workers $ARGS
    else
      echo "Démarrage de Suricata en mode IDS"
      exec suricata -c /etc/suricata/suricata.yaml $ARGS
    fi
    ;;
esac