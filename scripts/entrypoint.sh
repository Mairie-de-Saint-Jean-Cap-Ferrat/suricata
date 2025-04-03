#!/bin/bash

# Script d'entrée pour conteneur Suricata basé sur PPA
set -e

# Valeurs par défaut
INTERFACE=${INTERFACE:-"eth0"}
HOME_NET=${HOME_NET:-"[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"}
MODE=${MODE:-"ids"}
RUNMODE=${RUNMODE:-"auto"}
CONFIG_FILE="/etc/suricata/suricata.yaml"

echo "Configuration Suricata..."
echo "Interface: $INTERFACE"
echo "HOME_NET: $HOME_NET"
echo "Mode: $MODE"

# Vérification des paramètres de configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERREUR: Fichier de configuration $CONFIG_FILE non trouvé"
    exit 1
fi

# Mettre à jour l'interface dans la configuration
sed -i "s/^  - interface:.*$/  - interface: $INTERFACE/" $CONFIG_FILE 2>/dev/null || echo "Impossible de mettre à jour l'interface"

# Mettre à jour HOME_NET dans la configuration
sed -i "s/HOME_NET:.*$/HOME_NET: $HOME_NET/" $CONFIG_FILE 2>/dev/null || echo "Impossible de mettre à jour HOME_NET"

# Vérification des permissions sur les répertoires de logs
if [ ! -w "/var/log/suricata" ]; then
    echo "Création/correction des permissions du répertoire /var/log/suricata"
    mkdir -p /var/log/suricata
    chmod 755 /var/log/suricata
fi

# Mise à jour des règles Suricata
echo "Mise à jour des règles Suricata..."
suricata-update 2>/dev/null || echo "Erreur lors de la mise à jour des règles, utilisation des règles existantes"

# Choix du mode de démarrage
case $MODE in
    "ips")
        echo "Démarrage de Suricata en mode IPS avec NFQ"
        exec suricata -c $CONFIG_FILE --pidfile /var/run/suricata.pid -q 0 -v "$@"
        ;;
    "ids"|*)
        echo "Démarrage de Suricata en mode IDS"
        exec suricata -c $CONFIG_FILE --pidfile /var/run/suricata.pid -i $INTERFACE -v "$@"
        ;;
esac 