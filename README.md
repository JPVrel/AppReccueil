# Application de recueil de données

Application Shiny locale destinée à accompagner le recueil de données d'un projet de recherche. Le projet est volontairement petit et évolutif : les fonctions sont isolées, testées et pourront être enrichies progressivement.

## Premier état du projet

Cette première version établit le socle technique de l'application. Elle permet de démarrer localement un serveur Shiny depuis une boîte de dialogue, d'ouvrir l'application dans le navigateur par défaut et d'arrêter le serveur proprement.

Le parcours Shiny actuel reste volontairement minimal. L'onglet « Colonnes de la BDD » permet d'adapter la structure de la table des recueils ; les écrans de saisie et l'enregistrement des réponses seront ajoutés ensuite.

Cette étape prépare les évolutions suivantes : définir le formulaire de recueil, ajouter les règles de validation, enregistrer les observations, puis préparer l'utilisation par plusieurs personnes.

## Architecture

```text
.
├── app.R                         # Point d'entrée Shiny reconnu par Positron
├── launcher.R                    # Boîte de dialogue de lancement local
├── R/
│   ├── config.R                  # Configuration des chemins et du serveur
│   ├── database_columns.R        # Lecture, ajout et renommage des colonnes SQL
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

Les paramètres se trouvent dans [config/database.yml](config/database.yml). L'application lit cette configuration au démarrage, ouvre une connexion au début de chaque session Shiny, initialise les tables si elles n'existent pas, puis ferme la connexion quand la session se termine.

### Mode local : SQLite

La configuration par défaut est :

```yaml
database:
	mode: local
	local:
		path: data/recueil.sqlite
```

SQLite enregistre la base dans un fichier local. Le dossier parent est créé automatiquement. Le fichier `data/recueil.sqlite` est ignoré par Git : il reste sur l'ordinateur et ne doit pas être ajouté au dépôt. Ce mode convient au développement et à un usage local, mais un fichier SQLite partagé n'est pas le bon choix pour plusieurs utilisateurs qui accèdent à une application hébergée.

Le schéma initial contient deux tables techniques : `app_metadata` et `collection_records`. La seconde contient un identifiant, une date de création et un payload texte. Ces tables sont créées au démarrage, mais l'interface actuelle n'enregistre pas encore de données de recherche ; les champs et opérations métier viendront ensuite.

L'onglet **Colonnes de la BDD** liste les colonnes de `collection_records` et permet :

- d'ajouter une colonne de type `TEXT`, `INTEGER`, `REAL`, `NUMERIC`, `DATE` ou `BOOLEAN` ;
- de renommer une colonne personnalisée ; le renommage conserve les valeurs déjà présentes.

Les colonnes techniques `id`, `created_at` et `payload` sont protégées. Il n'y a pas de commande pour supprimer une colonne : cette première interface évite donc la suppression accidentelle de données. Le nom doit commencer par une lettre et ne contenir que des lettres, chiffres et underscores. Les nouvelles colonnes sont nullable, ce qui permet de les ajouter même si la table contient déjà des lignes.

### Mode distant : PostgreSQL

Pour une base hébergée, créez d'abord une base PostgreSQL auprès d'un fournisseur de votre choix. Récupérez son hôte, son port, le nom de la base et les exigences TLS/SSL. Dans `config/database.yml`, remplacez la configuration locale par un bloc distant comme celui-ci :

```yaml
database:
	mode: remote
	remote:
		driver_package: RPostgres
		driver_class: Postgres
		connection:
			dbname: nom_de_la_base
			host: votre-hote.postgres.example
			port: 5432
			sslmode: require
		credentials:
			user_env: RECUEIL_DB_USER
			password_env: RECUEIL_DB_PASSWORD
```

Installez le driver choisi dans la même version de R que celle qui lance l'application. Pour l'exemple PostgreSQL :

```r
install.packages("RPostgres")
```

Fournissez ensuite les identifiants à l'environnement avant de démarrer le lanceur. Dans le terminal macOS/Linux qui ouvre Positron :

```sh
export RECUEIL_DB_USER="nom_utilisateur"
export RECUEIL_DB_PASSWORD="mot_de_passe"
```

Ne mettez jamais les identifiants dans `database.yml`, dans le code ou dans Git. Si Positron est déjà ouvert, vous pouvez définir les variables dans sa console R avant de lancer `source("launcher.R")` :

```r
Sys.setenv(
	RECUEIL_DB_USER = "nom_utilisateur",
	RECUEIL_DB_PASSWORD = "mot_de_passe"
)
source("launcher.R")
```

Remplacez les valeurs d'exemple par celles fournies par votre hébergeur. Configurez également le fournisseur pour autoriser les connexions depuis le réseau où l'application s'exécute, appliquez les paramètres TLS recommandés, et accordez au compte uniquement les droits nécessaires à l'application. Les noms `RPostgres` et `Postgres` sélectionnent le driver ; les autres clés de `connection` sont transmises à `DBI::dbConnect()`.

La couche de connexion est basée sur DBI : un autre moteur pourra être utilisé en changeant `driver_package`, `driver_class` et les paramètres acceptés par son driver, sans réécrire le code de l'application. Le package du driver distant est à installer séparément ; le script général d'installation installe les dépendances communes et SQLite, pas un driver distant optionnel.

## Lancer l'application

Pour afficher la boîte de dialogue locale :

```r
source("launcher.R")
```

Elle permet de lancer le serveur Shiny, d'ouvrir `http://127.0.0.1:8000` dans le navigateur par défaut et d'arrêter proprement le serveur.

Dans l'application, ouvrez l'onglet **Colonnes de la BDD** pour consulter les colonnes de la table des recueils, en ajouter une ou renommer une colonne personnalisée.

Pour lancer directement l'application Shiny dans Positron, utilisez **Run App** sur `app.R`.

## Tests

Après l'installation des dépendances :

```r
testthat::test_dir("tests/testthat")
```

Les tests suivent une boucle de développement inspirée de l'Extreme Programming : écrire un test ciblé, implémenter le comportement minimal, exécuter toute la suite, puis refactorer sans changer le comportement attendu.

## État actuel

La version actuelle fournit un parcours d'accueil, un lanceur local, une base SQLite configurable et un onglet de gestion des colonnes. Les champs de recueil, la validation métier et l'écriture des observations ne sont pas encore implémentés ; les prochaines étapes les ajouteront progressivement.
