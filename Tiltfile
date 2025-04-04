# Tiltfile
# Charger l'extension pour Docker Compose
load('ext://docker_compose', 'docker_compose')

# --- Important ---
# Prérequis: Le fichier ./docker/run/etc/suricata.yaml DOIT être généré AVANT de lancer Tilt
#            (par exemple, en exécutant ./scripts/docker-build.sh une première fois sans lancer les services,
#             ou en exécutant manuellement la fonction generate_suricata_yaml du script).
#            Tilt ne gère pas nativement l'exécution de ce script de génération avant le build.

print("------ Tiltfile Chargé ------")
print("Services gérés via docker-compose.yml")
print("N'oubliez pas de générer ./docker/run/etc/suricata.yaml via docker-build.sh si ce n'est pas déjà fait.")
print("Live update activé pour le service 'web'.")
print("-----------------------------")


# Définir les services à gérer via docker-compose.yml
# Tilt lira le fichier docker-compose.yml et gérera les builds et le lancement.
docker_compose(
    'docker-compose.yml',
    services=['suricata', 'web'], # Spécifier les services explicitement si besoin
    # Configurer le live update pour le service 'web'
    # Cela synchronise les fichiers modifiés directement dans le conteneur sans rebuild complet.
    live_update=[
        live_update_step(
            service='web',
            # Synchroniser tout le contenu du dossier local 'web' vers '/app/web' dans le conteneur
            sync=('web/', '/app/web/'),
            # Ignorer les fichiers/dossiers non nécessaires à la synchro live
            # (ex: __pycache__, .git, etc. - Tilt a des ignorés par défaut aussi)
            ignore=['web/__pycache__', 'web/*.pyc']
            # Optionnel: Déclencher une commande après la synchro si nécessaire
            # Par exemple, pour redémarrer un serveur. Flask en mode debug devrait recharger automatiquement pour les .py
            # run='commande_a_executer_dans_le_conteneur_web'
        )
    ]
)

# Tilt gérera automatiquement les dépendances de build basées sur les contextes
# et Dockerfiles spécifiés dans docker-compose.yml.
# Les changements dans les fichiers sources (Dockerfile, scripts/entrypoint.sh pour suricata;
# Dockerfile.webinterface, web/* pour web) déclencheront les rebuilds nécessaires.
# Les changements dans les fichiers synchronisés par live_update ('web/') déclencheront une synchro rapide.
