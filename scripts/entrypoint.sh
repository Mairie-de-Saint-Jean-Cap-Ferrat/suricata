#!/bin/bash

# Script d'entrée pour conteneur Suricata basé sur PPA
set -e

# Valeurs par défaut (lues depuis les variables d'env du docker run)
INTERFACE=${INTERFACE:-"eth0"}
MODE=${MODE:-"ids"}
CONFIG_FILE="/etc/suricata/suricata.yaml"
CONFIG_STAGING_DIR="/config-staging"
CONFIG_STAGING_FILE="$CONFIG_STAGING_DIR/suricata.yaml"

echo "Démarrage Suricata..."
echo "Interface spécifiée (via env): $INTERFACE"
echo "Mode spécifié (via env): $MODE"
echo "Configuration finale attendue: $CONFIG_FILE"
echo "Recherche de la configuration fournie via volume dans $CONFIG_STAGING_FILE"

# Vérifier si la config fournie existe dans le staging
if [ -f "$CONFIG_STAGING_FILE" ]; then
    echo "Configuration trouvée dans $CONFIG_STAGING_FILE. Copie vers $CONFIG_FILE..."
    # Assurer que le répertoire /etc/suricata existe (créé dans le Dockerfile)
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cp "$CONFIG_STAGING_FILE" "$CONFIG_FILE"
    # Définir les permissions correctes après copie
    chown suricata:suricata "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
else
    echo "Attention: Aucune configuration fournie dans $CONFIG_STAGING_DIR via volume."
    # Vérifier si le fichier de base existe (installé par PPA)
    if [ -f "$CONFIG_FILE" ]; then
        echo "Utilisation de la configuration par défaut trouvée dans $CONFIG_FILE."
    # Ou essayer de restaurer depuis la sauvegarde si elle existe
    elif [ -f /etc/suricata.yaml.default ]; then
        echo "Utilisation de la sauvegarde /etc/suricata.yaml.default."
        cp /etc/suricata.yaml.default "$CONFIG_FILE"
        chown suricata:suricata "$CONFIG_FILE"
        chmod 640 "$CONFIG_FILE"
    else
        echo "ERREUR FATALE: Aucune configuration fournie et aucune configuration par défaut ou sauvegarde trouvée."
        exit 1
    fi
fi

# Vérification que le fichier de configuration final existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERREUR FATALE: Fichier de configuration $CONFIG_FILE non trouvé après tentative de copie/restauration."
    exit 1
fi

# Vérification des permissions sur les répertoires de logs (toujours utile)
if [ ! -w "/var/log/suricata" ]; then
    echo "Création/correction des permissions du répertoire /var/log/suricata"
    mkdir -p /var/log/suricata
    chown suricata:suricata /var/log/suricata || echo "Impossible de changer le propriétaire de /var/log/suricata"
    chmod 750 /var/log/suricata
fi

# Vérification des permissions sur le répertoire du fichier PID (toujours utile)
mkdir -p /var/run/suricata
chown suricata:suricata /var/run/suricata || echo "Impossible de changer le propriétaire de /var/run/suricata"

# Mise à jour des règles Suricata (toujours utile)
echo "Mise à jour des règles Suricata..."
suricata-update --no-test 2>/dev/null || echo "Erreur lors de la mise à jour des règles, utilisation des règles existantes"

# Choix du mode de démarrage basé sur la variable MODE
case $MODE in
    "ips")
        echo "Démarrage de Suricata en mode IPS avec NFQ"
        # Utilisation de exec pour remplacer le processus shell par suricata
        exec suricata -c $CONFIG_FILE --pidfile /var/run/suricata/suricata.pid -q 0 -v "$@"
        ;;
    "ids"|*)
        echo "Démarrage de Suricata en mode IDS"
        # Utilisation de exec pour remplacer le processus shell par suricata
        exec suricata -c $CONFIG_FILE --pidfile /var/run/suricata/suricata.pid -i $INTERFACE -v "$@"
        ;;
esac
