# Application de recueil de données

Application Shiny locale destinée à accompagner le recueil de données d'un projet de recherche. Le projet est volontairement petit et évolutif : les fonctions sont isolées, testées et pourront être enrichies progressivement.

## Architecture

```text
.
├── app.R                         # Point d'entrée Shiny reconnu par Positron
├── launcher.R                    # Boîte de dialogue de lancement local
├── R/
│   ├── config.R                  # Configuration des chemins et du serveur
│   ├── dependencies.R            # Détection et installation des packages
│   ├── launcher_ui.R             # Fenêtre Tcl/Tk
│   ├── load_modules.R            # Chargement des modules R
│   ├── server_process.R          # Démarrage, attente et arrêt du serveur
│   └── shiny_app.R               # Interface et logique Shiny
├── scripts/
│   └── install_dependencies.R    # Installation des dépendances
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

Le script installe les packages nécessaires à l'application (`shiny`) et au développement (`testthat`). Le lanceur propose également l'installation de `shiny` si celui-ci est absent.

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

La première version fournit un parcours d'accueil et un bouton de démarrage. Les champs de recueil, la validation métier et le stockage seront ajoutés progressivement.
