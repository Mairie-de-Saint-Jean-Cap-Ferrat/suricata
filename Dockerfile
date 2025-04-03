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
    ethtool && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Chargement des variables de configuration
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    # Installation des dépendances IPS si nécessaire
    if [ "$IPS_MODE" = "true" ]; then \
        apt-get update && \
        apt-get -y install --no-install-recommends \
        libnetfilter-queue-dev libnetfilter-queue1 \
        libnfnetlink-dev libnfnetlink0 && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* ; \
    fi && \
    # Installation de cbindgen pour Rust si supporté
    if [ "$RUST_SUPPORT" = "true" ]; then \
        mkdir -p /root/.cargo/bin && \
        export PATH="/root/.cargo/bin:$PATH" && \
        cargo install --force cbindgen ; \
    fi

# Clonage et compilation de Suricata
WORKDIR /opt
RUN set -a && . /tmp/suricata-build.conf && set +a && \
    export PATH="/root/.cargo/bin:$PATH" && \
    git clone https://github.com/OISF/suricata.git && \
    cd suricata && \
    git checkout $BRANCH && \
    ./scripts/bundle.sh && \
    ./autogen.sh && \
    # Configuration avec les options spécifiées
    CONFIGURE_OPTIONS="" && \
    if [ "$IPS_MODE" = "true" ]; then \
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --enable-nfqueue"; \
    fi && \
    if [ -n "$EXTRA_CONFIGURE_OPTIONS" ]; then \
        CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS $EXTRA_CONFIGURE_OPTIONS"; \
    fi && \
    ./configure $CONFIGURE_OPTIONS && \
    make && \
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
