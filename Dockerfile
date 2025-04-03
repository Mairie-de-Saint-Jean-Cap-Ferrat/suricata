FROM ubuntu:22.04

LABEL maintainer="Maintainer <maintainer@example.com>"
LABEL description="Image Docker pour Suricata IDS/IPS via PPA"

# Éviter les interactions pendant l'installation
ARG DEBIAN_FRONTEND=noninteractive

# Mise à jour du système et installation des dépendances de base et pour add-apt-repository
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    ca-certificates \
    curl \
    gnupg \
    python3-pip \
    python3-yaml \
    ethtool \
    iproute2 \
    procps \
    net-tools \
    sudo \
    jq \
    util-linux && \
    # Installation de Suricata via PPA
    add-apt-repository ppa:oisf/suricata-stable && \
    apt-get update && \
    # Installer suricata et suricata-update (qui est souvent un paquet séparé ou inclus)
    apt-get install -y --no-install-recommends suricata suricata-update && \
    # Nettoyage
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Créer explicitement le groupe et l'utilisateur suricata
RUN groupadd -r suricata && useradd -r -g suricata -d /var/lib/suricata -s /sbin/nologin -c "Suricata IDS/IPS User" suricata || \
    echo "Utilisateur/groupe suricata existe déjà ou erreur lors de la création"

# Vérifier que Suricata est bien installé
RUN suricata --build-info && \
    suricata -V

# Mise à jour initiale des règles Suricata (sera mis à jour au démarrage par entrypoint.sh)
RUN suricata-update update-sources && \
    suricata-update enable-source et/open && \
    suricata-update || echo "Première mise à jour des règles échouée, sera retentée au démarrage."

# Création de répertoires pour les volumes et PID file
RUN mkdir -p /var/log/suricata /var/lib/suricata /var/run/suricata && \
    chown -R suricata:suricata /var/log/suricata /var/lib/suricata /var/run/suricata

# Sauvegarder le fichier de configuration par défaut avant qu'il ne soit potentiellement masqué par un volume
RUN cp /etc/suricata/suricata.yaml /etc/suricata.yaml.default

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

# Exposition des ports (optionnel, dépend de la configuration du réseau hôte)
# EXPOSE 80 443 53/udp 53/tcp

# Utiliser tini pour une meilleure gestion des signaux
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Point d'entrée
ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]

# L'utilisateur par défaut n'est pas défini ici, car Suricata doit démarrer en root
# pour obtenir les capacités nécessaires avant de passer à un utilisateur non privilégié si configuré.
# CMD ["suricata", "-c", "/etc/suricata/suricata.yaml", "-i", "eth0"]
