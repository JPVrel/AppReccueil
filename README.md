# Application de recueil de données

Application Shiny locale destinée à accompagner le recueil de données d'un projet de recherche. Le projet est volontairement petit et évolutif : les fonctions sont isolées, testées et pourront être enrichies progressivement.

## Premier état du projet

Cette première version établit le socle technique de l'application. Elle permet de démarrer localement un serveur Shiny depuis une boîte de dialogue, d'ouvrir l'application dans le navigateur par défaut et d'arrêter le serveur proprement.

Le parcours Shiny actuel est volontairement minimal : une page d'accueil et un bouton simulant le démarrage d'un recueil. Aucun champ métier ni donnée de recherche réelle n'est encore enregistré.

Cette étape prépare les évolutions suivantes : définir le formulaire de recueil, ajouter les règles de validation, choisir le stockage des données, puis préparer l'utilisation par plusieurs personnes.

## Architecture

```text
.
├── app.R                         # Point d'entrée Shiny reconnu par Positron
├── launcher.R                    # Boîte de dialogue de lancement local
├── R/
│   ├── config.R                  # Configuration des chemins et du serveur
│   ├── database_config.R         # Lecture et validation de la configuration DB
│   ├── database_connection.R     # Connexions SQLite ou driver distant DBI
│   ├── database_schema.R          # Création des tables initiales
│   ├── dependencies.R            # Détection et installation des packages
│   ├── launcher_ui.R             # Fenêtre Tcl/Tk
│   ├── load_modules.R            # Chargement des modules R
│   ├── server_process.R          # Démarrage, attente et arrêt du serveur
│   └── shiny_app.R               # Interface et logique Shiny
├── scripts/
│   └── install_dependencies.R    # Installation des dépendances
├── config/
│   └── database.yml               # Paramètres locaux ou distants à modifier
├── data/
│   └── .gitkeep                   # Dossier de la base SQLite locale
├── shiny/
│   ├── app.R                     # Application exécutée par le serveur local
│   └── run_app.R                 # Runner du processus R indépendant
└── tests/testthat/               # Tests unitaires et tests du serveur Shiny
```

## Installation

Depuis la racine du projet, dans R :

```r
source("scripts/install_dependencies.R")
```

Le script installe les packages nécessaires à l'application (`shiny`, `DBI`, `RSQLite`, `yaml`) et au développement (`testthat`). Le lanceur propose également l'installation des dépendances d'exécution si elles sont absentes.

## Base de données

Les paramètres se trouvent dans [config/database.yml](config/database.yml). Par défaut, l'application utilise SQLite et crée automatiquement `data/recueil.sqlite` au premier démarrage d'une session Shiny.

Le schéma initial contient deux tables techniques : `app_metadata` et `collection_records`. La table des recueils utilise pour l'instant un identifiant, une date de création et un payload texte ; elle sera spécialisée lorsque les premiers champs métier seront définis.

Pour passer à une base distante, le fichier de configuration pourra définir `mode: remote`, le package DBI du driver (`RPostgres`, par exemple), sa classe et les paramètres de connexion. Les identifiants doivent être fournis par des variables d'environnement indiquées par `user_env` et `password_env`, jamais écrits dans le fichier YAML.

## Lancer l'application

Pour afficher la boîte de dialogue locale :

```r
source("launcher.R")
```

Elle permet de lancer le serveur Shiny, d'ouvrir `http://127.0.0.1:8000` dans le navigateur par défaut et d'arrêter proprement le serveur.

Pour lancer directement l'application Shiny dans Positron, utilisez **Run App** sur `app.R`.

## Tests

Après l'installation des dépendances :

```r
testthat::test_dir("tests/testthat")
```

Les tests suivent une boucle de développement inspirée de l'Extreme Programming : écrire un test ciblé, implémenter le comportement minimal, exécuter toute la suite, puis refactorer sans changer le comportement attendu.

## État actuel

La première version fournit un parcours d'accueil, une base SQLite locale et un bouton de démarrage. Les champs de recueil, la validation métier et l'écriture des observations seront ajoutés progressivement.
