#!/bin/bash

# Script d'entrée pour conteneur Suricata basé sur PPA
set -e

# Valeurs par défaut (lues depuis les variables d'env du docker-compose)
INTERFACE=${INTERFACE:-"eth0"}
MODE=${MODE:-"ids"}
# Définir explicitement le chemin de configuration que nous allons utiliser
CONFIG_FILE="/etc/suricata/suricata.yaml"

echo "Démarrage Suricata (via entrypoint.sh)..."
echo "Interface spécifiée (via env): $INTERFACE"
echo "Mode spécifié (via env): $MODE"
echo "Utilisation du fichier de configuration: $CONFIG_FILE (monté via volume)"

# Vérifier que le fichier de configuration monté existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERREUR FATALE: Fichier de configuration $CONFIG_FILE non trouvé." 
    echo "Assurez-vous qu'il est correctement monté via le volume dans docker-compose.yml."
    exit 1
fi

# Vérification des permissions sur les répertoires de logs (toujours utile)
if [ ! -w "/var/log/suricata" ]; then
    echo "Création/correction des permissions du répertoire /var/log/suricata"
    mkdir -p /var/log/suricata
    chown suricata:suricata /var/log/suricata || echo "Impossible de changer le propriétaire de /var/log/suricata"
    chmod 750 /var/log/suricata
fi

# Vérification des permissions sur le répertoire du fichier PID et socket (toujours utile)
mkdir -p /var/run/suricata
chown suricata:suricata /var/run/suricata || echo "Impossible de changer le propriétaire de /var/run/suricata"

# Mise à jour des règles Suricata (toujours utile)
echo "Mise à jour des règles Suricata..."
suricata-update --no-test 2>/dev/null || echo "Avertissement: Erreur lors de la mise à jour des règles, utilisation des règles existantes."

# Choix du mode de démarrage basé sur la variable MODE
# Les arguments passés via `command:` dans docker-compose sont ignorés car nous ne les ajoutons plus
# Nous spécifions explicitement -c ici.
echo "Préparation de la commande d'exécution Suricata..."

case $MODE in
    "ips")
        echo "Mode IPS sélectionné. Ajout de -q 0."
        # Nous spécifions -c ici, le pidfile est dans le YAML
        exec suricata -c $CONFIG_FILE -q 0 -v
        ;;
    "ids"|*)
        echo "Mode IDS (ou par défaut) sélectionné. Ajout de -i $INTERFACE."
        # Nous spécifions -c ici, le pidfile est dans le YAML
        exec suricata -c $CONFIG_FILE -i $INTERFACE -v
        ;;
esac
