FROM ubuntu:22.04

LABEL maintainer="Maintainer <maintainer@example.com>"
LABEL description="Image Docker pour Suricata IDS/IPS via PPA"

# Éviter les interactions pendant l'installation
ARG DEBIAN_FRONTEND=noninteractive

# Mise à jour du système et installation des dépendances de base
RUN apt-get update && \
    apt-get install -y \
    software-properties-common \
    ca-certificates \
    curl \
    gnupg \
    gpg-agent \
    gnupg2 \
    dirmngr \
    apt-transport-https \
    python3-pip \
    python3-yaml \
    ethtool \
    iproute2 \
    procps \
    net-tools \
    sudo

# Installation de Suricata via PPA
RUN add-apt-repository ppa:oisf/suricata-stable && \
    apt-get update && \
    apt-get install -y suricata && \
    apt-get update && \
    apt-get install -y \
    libpcre2-dev \
    build-essential \
    autoconf \
    automake \
    libtool \
    libpcap-dev \
    libnet1-dev \
    libyaml-0-2 \
    libyaml-dev \
    pkg-config \
    zlib1g \
    zlib1g-dev \
    libcap-ng-dev \
    libcap-ng0 \
    make \
    libmagic-dev \
    libjansson-dev \
    rustc \
    cargo \
    jq \
    git-core \
    libnetfilter-queue-dev \
    libnetfilter-queue1 \
    libnfnetlink-dev \
    libnfnetlink0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Vérifier que Suricata est bien installé
RUN suricata --build-info && \
    suricata -V

# Mise à jour des règles Suricata
RUN suricata-update update-sources && \
    suricata-update enable-source et/open && \
    suricata-update

# Création de répertoires pour les volumes
RUN mkdir -p /var/log/suricata /var/lib/suricata /etc/suricata /var/run/suricata

# Configuration pour utiliser community-id
RUN if grep -q "community-id:" /etc/suricata/suricata.yaml; then \
        sed -i 's/^  community-id: false/  community-id: true/' /etc/suricata/suricata.yaml; \
    else \
        echo "  community-id: true" >> /etc/suricata/suricata.yaml; \
    fi

# Copier le script d'entrée
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration des volumes pour les règles et logs
VOLUME ["/etc/suricata", "/var/log/suricata"]

# Exposition des ports pour l'interface HTTP (optionnel)
EXPOSE 80 443 53/udp 53/tcp

# Utiliser tini pour une meilleure gestion des signaux
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Point d'entrée
ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]
