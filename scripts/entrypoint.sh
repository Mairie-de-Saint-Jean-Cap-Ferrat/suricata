#!/bin/bash

# Script d'entrée pour conteneur Suricata basé sur PPA
set -e

# Valeurs par défaut (lues depuis les variables d'env du docker run)
INTERFACE=${INTERFACE:-"eth0"}
MODE=${MODE:-"ids"}
CONFIG_FILE="/etc/suricata/suricata.yaml"

echo "Démarrage Suricata..."
echo "Interface spécifiée (via env): $INTERFACE"
echo "Mode spécifié (via env): $MODE"
echo "Configuration attendue: $CONFIG_FILE"

# --- DEBUT DIAGNOSTIC --- #
echo "Vérification du point de montage /etc/suricata ..."
ls -ld /etc/suricata
echo "Vérification du contenu de /etc/suricata ..."
ls -l /etc/suricata/
echo "Tentative de lecture de $CONFIG_FILE ..."
cat "$CONFIG_FILE" || echo "ERREUR: Impossible de lire $CONFIG_FILE"
echo "Vérification des montages avec findmnt ..."
findmnt /etc/suricata || echo "ERREUR: findmnt n'a pas trouvé le montage pour /etc/suricata"
sleep 1
# --- FIN DIAGNOSTIC --- #

# Vérification que le fichier de configuration existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERREUR FATALE: Fichier de configuration $CONFIG_FILE non trouvé après diagnostics. Problème de montage de volume ?"
    exit 1
fi

# Les commandes sed pour modifier HOME_NET, INTERFACE et RUNMODE sont retirées
# car le fichier est maintenant généré par docker-build.sh et fourni via volume.

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
