FROM ubuntu:22.04

LABEL maintainer="Maintainer <maintainer@example.com>"
LABEL description="Image Docker pour Suricata IDS/IPS"

# Éviter les interactions pendant l'installation
ARG DEBIAN_FRONTEND=noninteractive

# Copier les fichiers de configuration
COPY scripts/suricata-build.conf /tmp/

# Mise à jour du système et installation des dépendances de base
RUN apt-get update && \
    apt-get -y install --no-install-recommends \
    libpcre2-dev build-essential autoconf automake \
    libtool libpcap-dev libnet1-dev libyaml-0-2 libyaml-dev \
    pkg-config zlib1g zlib1g-dev libcap-ng-dev libcap-ng0 make \
    libmagic-dev libjansson-dev rustc cargo jq git-core \
    ca-certificates python3-pip python3-yaml curl wget \
    ethtool sudo libpcap0.8-dev libhtp-dev liblz4-dev \
    procps net-tools iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Chargement des variables de configuration et installation des dépendances IPS
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    if [ "$IPS_MODE" = "true" ]; then \
        echo "Installation des dépendances IPS..." && \
        apt-get update && \
        apt-get -y install --no-install-recommends \
        libnetfilter-queue-dev libnetfilter-queue1 \
        libnfnetlink-dev libnfnetlink0 && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* ; \
    fi

# Installation de cbindgen pour Rust - version corrigée
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    if [ "$RUST_SUPPORT" = "true" ]; then \
        echo "Installation de cbindgen..." && \
        export CARGO_HOME="/root/.cargo" && \
        mkdir -p $CARGO_HOME/bin && \
        export PATH="$CARGO_HOME/bin:$PATH" && \
        echo "PATH avant: $PATH" && \
        cargo install --version 0.24.3 cbindgen && \
        which cbindgen || echo "cbindgen non trouvé dans PATH" && \
        ls -la $CARGO_HOME/bin/ && \
        # Créer un lien symbolique explicite
        ln -sf $CARGO_HOME/bin/cbindgen /usr/local/bin/cbindgen && \
        echo "PATH après: $PATH" && \
        cbindgen --version || echo "cbindgen n'est pas correctement installé"; \
    fi

# Clonage du dépôt Suricata
WORKDIR /opt
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    echo "Clonage du dépôt Suricata..." && \
    git clone https://github.com/OISF/suricata.git && \
    cd suricata && \
    # Utiliser une version stable spécifique au lieu de master
    git checkout $BRANCH && \
    # Afficher la version utilisée
    git describe --always

# Préparation du build
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    cd /opt/suricata && \
    echo "Exécution du script bundle.sh..." && \
    ./scripts/bundle.sh && \
    echo "Exécution du script autogen.sh..." && \
    ./autogen.sh

# Configuration et compilation - avec plus de verbosité pour identifier les erreurs
RUN set -e && set -a && . /tmp/suricata-build.conf && set +a && \
    cd /opt/suricata && \
    # Ajout de cbindgen au PATH
    export CARGO_HOME="/root/.cargo" && \
    export PATH="/usr/local/bin:$CARGO_HOME/bin:$PATH" && \
    echo "===== Début de la configuration de Suricata =====" && \
    echo "Vérification des dépendances..." && \
    ls -la && \
    echo "Vérification de cbindgen:" && \
    which cbindgen || echo "cbindgen introuvable" && \
    echo "Vérification des paramètres de configuration..." && \
    CONFIGURE_OPTIONS="" && \
    if [ "$IPS_MODE" = "true" ]; then \
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --enable-nfqueue"; \
    fi && \
    if [ -n "$EXTRA_CONFIGURE_OPTIONS" ]; then \
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS $EXTRA_CONFIGURE_OPTIONS"; \
    fi && \
    echo "Options de configuration: $CONFIGURE_OPTIONS" && \
    echo "Lancement du configure avec options minimales pour debug..." && \
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-suricata-update $CONFIGURE_OPTIONS --disable-rust || { echo "Configure a échoué"; cat config.log; exit 1; } && \
    echo "===== Début de la compilation de Suricata =====" && \
    echo "Compilation avec nombre de processeurs: $(nproc)" && \
    make -j$(nproc) || { echo "Make a échoué"; exit 1; }

# Installation
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    cd /opt/suricata && \
    echo "Valeur de AUTO_SETUP: $AUTO_SETUP" && \
    # Création des répertoires nécessaires
    mkdir -p /var/log/suricata /var/lib/suricata /etc/suricata /var/run/suricata && \
    # Déterminer la cible d'installation correcte
    if [ "$AUTO_SETUP" = "install-full" ] || [ "$AUTO_SETUP" = "install-conf" ] || [ "$AUTO_SETUP" = "install-rules" ]; then \
        # Si AUTO_SETUP contient déjà "install-", utiliser tel quel
        echo "Installation de Suricata avec: make $AUTO_SETUP" && \
        make $AUTO_SETUP; \
    else \
        # Sinon, ajouter le préfixe "install-"
        echo "Installation de Suricata avec: make install-$AUTO_SETUP" && \
        make install-$AUTO_SETUP; \
    fi && \
    ldconfig && \
    # Vérifier si le fichier de configuration a été installé
    if [ ! -f "/etc/suricata/suricata.yaml" ]; then \
        echo "Fichier de configuration non trouvé, installation manuelle..." && \
        # Copier le fichier de configuration par défaut
        if [ -f "/opt/suricata/suricata.yaml" ]; then \
            cp /opt/suricata/suricata.yaml /etc/suricata/; \
        elif [ -f "/opt/suricata/suricata.yaml.in" ]; then \
            cp /opt/suricata/suricata.yaml.in /etc/suricata/suricata.yaml; \
        else \
            # Utiliser la commande make pour installer uniquement la configuration
            cd /opt/suricata && make install-conf; \
        fi; \
    fi && \
    # Installation des règles par défaut si non présentes
    if [ ! -d "/etc/suricata/rules" ] || [ -z "$(ls -A /etc/suricata/rules)" ]; then \
        echo "Installation des règles par défaut..." && \
        mkdir -p /etc/suricata/rules && \
        if [ -d "/opt/suricata/rules" ]; then \
            cp /opt/suricata/rules/* /etc/suricata/rules/ 2>/dev/null || echo "Pas de règles dans /opt/suricata/rules"; \
        fi && \
        # Téléchargement de règles Emerging Threats si aucune règle n'est encore présente
        if [ -z "$(ls -A /etc/suricata/rules)" ]; then \
            echo "Téléchargement des règles Emerging Threats..." && \
            mkdir -p /tmp/et-rules && \
            cd /tmp/et-rules && \
            wget https://rules.emergingthreats.net/open/suricata-6.0/emerging.rules.tar.gz && \
            tar -xzf emerging.rules.tar.gz && \
            cp rules/*.rules /etc/suricata/rules/ && \
            cp *.config /etc/suricata/ 2>/dev/null || echo "Pas de fichiers config" && \
            rm -rf /tmp/et-rules; \
        fi; \
    fi && \
    # Créer un fichier de règles vide si toujours aucune règle
    touch /etc/suricata/rules/suricata.rules && \
    # Vérifier à nouveau que le fichier est présent
    ls -la /etc/suricata/ || echo "Impossible de lister le contenu de /etc/suricata/"

# Configuration de Suricata
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    if [ -n "$INTERFACE" ] && [ -n "$HOME_NET" ]; then \
        # Vérifier que le fichier de configuration existe
        if [ -f "/etc/suricata/suricata.yaml" ]; then \
            echo "Configuration de l'interface $INTERFACE et HOME_NET $HOME_NET" && \
            # Configurer l'interface et HOME_NET dans le fichier de configuration
            sed -i "s/^  - interface: .*/  - interface: $INTERFACE/" /etc/suricata/suricata.yaml && \
            sed -i "s/HOME_NET:.*$/HOME_NET: $HOME_NET/" /etc/suricata/suricata.yaml; \
        else \
            echo "ERREUR: Fichier de configuration /etc/suricata/suricata.yaml non trouvé"; \
            exit 1; \
        fi; \
    else \
        echo "Aucune interface ou HOME_NET définie, configuration de base conservée"; \
    fi && \
    # Configurer pour un mode conteneur
    sed -i 's/^  community-id: false/  community-id: true/' /etc/suricata/suricata.yaml && \
    # Ajuster les chemins des logs
    sed -i 's|default-log-dir: /var/log/suricata/|default-log-dir: /var/log/suricata/|' /etc/suricata/suricata.yaml

# Création du script de démarrage de Suricata
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Si le script entrypoint.sh n'existe pas, on le crée
RUN if [ ! -f "/entrypoint.sh" ]; then \
    echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Vérifie si nous avons une interface spécifiée' >> /entrypoint.sh && \
    echo 'if [ -z "$INTERFACE" ]; then' >> /entrypoint.sh && \
    echo '    INTERFACE=eth0' >> /entrypoint.sh && \
    echo '    echo "Interface non spécifiée, utilisation par défaut: $INTERFACE"' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Vérifie si nous avons un HOME_NET spécifié' >> /entrypoint.sh && \
    echo 'if [ -z "$HOME_NET" ]; then' >> /entrypoint.sh && \
    echo '    HOME_NET="[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"' >> /entrypoint.sh && \
    echo '    echo "HOME_NET non spécifié, utilisation par défaut: $HOME_NET"' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Met à jour le fichier de configuration avec les valeurs' >> /entrypoint.sh && \
    echo 'sed -i "s/^  - interface: .*/  - interface: $INTERFACE/" /etc/suricata/suricata.yaml' >> /entrypoint.sh && \
    echo 'sed -i "s/HOME_NET:.*$/HOME_NET: $HOME_NET/" /etc/suricata/suricata.yaml' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Mode IDS ou IPS' >> /entrypoint.sh && \
    echo 'if [ "$MODE" = "ips" ]; then' >> /entrypoint.sh && \
    echo '    echo "Démarrage de Suricata en mode IPS (prévention d'\''intrusion)"' >> /entrypoint.sh && \
    echo '    ARGS="-c /etc/suricata/suricata.yaml --af-packet=$INTERFACE -v"' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '    echo "Démarrage de Suricata en mode IDS (détection d'\''intrusion)"' >> /entrypoint.sh && \
    echo '    ARGS="-c /etc/suricata/suricata.yaml --af-packet=$INTERFACE -v"' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Exécute Suricata avec les bons paramètres' >> /entrypoint.sh && \
    echo 'exec /usr/bin/suricata $ARGS "$@"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh; \
fi

# Crée un utilisateur non-root pour exécuter Suricata
RUN groupadd -r suricata && \
    useradd -r -g suricata -s /sbin/nologin suricata && \
    chown -R suricata:suricata /var/log/suricata /var/lib/suricata /etc/suricata /var/run/suricata

# Configuration des volumes pour les règles et logs
VOLUME ["/etc/suricata", "/var/log/suricata"]

# Exposition des ports pour l'interface HTTP (optionnel)
EXPOSE 80 443 53/udp 53/tcp

# Utilisation des capacités Linux pour permettre la capture réseau
# sans nécessiter les privilèges root complets
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Utiliser tini comme point d'entrée pour une meilleure gestion des signaux
ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]
