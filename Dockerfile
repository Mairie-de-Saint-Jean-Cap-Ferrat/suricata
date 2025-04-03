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
    ca-certificates python3-pip python3-yaml curl \
    ethtool sudo && \
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

# Installation de cbindgen pour Rust (séparé pour isoler les problèmes)
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    if [ "$RUST_SUPPORT" = "true" ]; then \
        echo "Installation de cbindgen..." && \
        mkdir -p /root/.cargo/bin && \
        echo "PATH actuel: $PATH" && \
        export PATH="/root/.cargo/bin:$PATH" && \
        echo "PATH après modification: $PATH" && \
        cargo --version && \
        rustc --version && \
        cargo install --force cbindgen || echo "Installation de cbindgen échouée mais on continue" ; \
    fi

# Clonage du dépôt Suricata
WORKDIR /opt
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    echo "Clonage du dépôt Suricata..." && \
    git clone https://github.com/OISF/suricata.git && \
    cd suricata && \
    git checkout $BRANCH

# Préparation du build
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    cd /opt/suricata && \
    echo "Exécution du script bundle.sh..." && \
    ./scripts/bundle.sh && \
    echo "Exécution du script autogen.sh..." && \
    ./autogen.sh

# Configuration et compilation
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    cd /opt/suricata && \
    echo "Configuration de Suricata..." && \
    CONFIGURE_OPTIONS="" && \
    if [ "$IPS_MODE" = "true" ]; then \
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --enable-nfqueue"; \
    fi && \
    if [ -n "$EXTRA_CONFIGURE_OPTIONS" ]; then \
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS $EXTRA_CONFIGURE_OPTIONS"; \
    fi && \
    echo "Options de configuration: $CONFIGURE_OPTIONS" && \
    ./configure $CONFIGURE_OPTIONS && \
    echo "Compilation de Suricata..." && \
    make -j$(nproc)

# Installation
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    cd /opt/suricata && \
    echo "Installation de Suricata avec: make install-$AUTO_SETUP" && \
    make install-$AUTO_SETUP && \
    ldconfig

# Configuration de Suricata
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    if [ -n "$INTERFACE" ] && [ -n "$HOME_NET" ]; then \
        # Configurer l'interface et HOME_NET dans le fichier de configuration
        sed -i "s/^  - interface: .*/  - interface: $INTERFACE/" /etc/suricata/suricata.yaml && \
        sed -i "s/HOME_NET:.*$/HOME_NET: $HOME_NET/" /etc/suricata/suricata.yaml; \
    fi

# Création d'un entrypoint pour démarrer Suricata
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration du volume pour les règles et logs
VOLUME ["/etc/suricata", "/var/log/suricata"]

# Configuration des ports
EXPOSE 80 443 53/udp 53/tcp

ENTRYPOINT ["/entrypoint.sh"]
