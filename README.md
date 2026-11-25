# Application de recueil de données

Application Shiny locale destinée à accompagner le recueil de données d'un projet de recherche. Le projet est volontairement petit et évolutif : les fonctions sont isolées, testées et pourront être enrichies progressivement.

## Premier état du projet

Cette première version établit le socle technique de l'application. Elle permet de démarrer localement un serveur Shiny depuis une boîte de dialogue, d'ouvrir l'application dans le navigateur par défaut et d'arrêter le serveur proprement.

Le parcours Shiny actuel reste volontairement minimal. L'onglet « Colonnes de la BDD » permet de définir les champs, dictionnaires et calculs ; le formulaire de saisie des réponses sera ajouté ensuite.

Cette étape prépare les évolutions suivantes : définir le formulaire de recueil, ajouter les règles de validation, enregistrer les observations, puis préparer l'utilisation par plusieurs personnes.

## Architecture

```text
.
├── app.R                         # Point d'entrée Shiny reconnu par Positron
├── launcher.R                    # Boîte de dialogue de lancement local
├── R/
│   ├── database/
│   │   ├── archive.R             # Masquage réversible et restauration
│   │   ├── catalog.R             # Métadonnées et identifiants stables
│   │   ├── categories.R          # Dictionnaires catégoriels
│   │   ├── columns.R             # Opérations sur les colonnes SQL
│   │   ├── config.R              # Lecture de la configuration DB
│   │   ├── connection.R          # Connexions SQLite ou driver distant DBI
│   │   ├── dates.R               # Validation des dates ISO
│   │   ├── fields.R              # Création des champs typés
│   │   ├── formulas.R            # Validation et calcul des variables dérivées
│   │   ├── records.R             # Lecture avec recalcul des formules
│   │   └── schema.R              # Création des tables et synchronisation du catalogue
│   ├── launcher/
│   │   ├── config.R              # Chemins et paramètres du lanceur
│   │   ├── server_process.R      # Démarrage, attente et arrêt du serveur
│   │   └── ui.R                  # Fenêtre Tcl/Tk
│   ├── shiny/
│   │   ├── app.R                 # Interface et logique Shiny
│   │   └── database_management.R # Tableaux et contrôles de gestion des variables
│   ├── dependencies.R            # Détection et installation des packages
│   └── load_modules.R             # Chargement récursif des modules R
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

Au démarrage, l'application crée les tables `app_metadata`, `collection_records`, `column_definitions` et `category_dictionary`. `collection_records` contient un identifiant, une date de création, un payload et les colonnes physiques définies par l'utilisateur. `column_definitions` conserve les types métier, noms logiques, formules et états masqués ; `category_dictionary` conserve les codes et libellés catégoriels. Les identifiants internes stables permettent aux formules et dictionnaires de suivre un champ même s'il est renommé ou masqué.

L'onglet **Colonnes de la BDD** présente les champs actifs et masqués dans des tableaux indiquant leur nom, leur type, leur nature et, pour les variables dérivées, leur formule. Il permet :

- d'ajouter des champs texte, entiers, décimaux, dates et catégoriels ;
- de renommer les champs personnalisés ; les valeurs existantes sont conservées ;
- de masquer et restaurer un champ sans supprimer ses données ;
- de gérer les entrées des dictionnaires catégoriels ;
- de définir et modifier des variables dérivées à l'aide d'un constructeur visuel.

Les colonnes techniques `id`, `created_at` et `payload` sont protégées. Le masquage déplace le nom SQL physique vers un nom interne `__hidden_N`, sans supprimer la colonne ni ses valeurs. À la restauration, le nom d'origine est repris s'il est libre ; sinon, un suffixe `_2`, `_3`, etc. est ajouté. Les formules suivent les identifiants internes et continuent de fonctionner si leur source est renommée ou masquée.

Les champs catégoriels sont stockés par code texte, avec un libellé séparé. Modifier un code met à jour les réponses existantes ; supprimer une catégorie exige de choisir une catégorie de remplacement, puis réaffecte les réponses avant de retirer l'entrée. Les champs date sont des dates sans heure, validées au format strict `YYYY-MM-DD`.

Les variables dérivées sont des colonnes virtuelles : leur formule est conservée dans `column_definitions`, et `read_collection_records()` les recalcule à chaque lecture. Le constructeur propose l'arithmétique numérique, les comparaisons, les différences de dates en jours et les conditions SI/SINON. Les formules ne sont jamais exécutées comme du code R libre. Une source manquante ou une division par zéro donne une valeur manquante ; les références incompatibles et les dépendances circulaires sont refusées.

Les nouveaux champs sont nullable, ce qui permet de les ajouter même si la table contient déjà des lignes. Le formulaire de collecte et l'écriture des réponses ne sont pas encore implémentés. En mode local, tous les utilisateurs peuvent gérer le schéma ; avant un déploiement partagé, il faudra ajouter l'authentification et des droits d'administration.

La création d'un champ et de ses métadonnées est transactionnelle : en cas d'échec du catalogue, la colonne SQL est annulée aussi. Les opérations arithmétiques sur des champs entiers sont promues en décimal avant calcul afin d'éviter les débordements des entiers R.

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

Dans l'application, ouvrez l'onglet **Colonnes de la BDD** pour créer des champs, configurer leurs dictionnaires, définir des formules, les renommer, les masquer ou les restaurer.

Pour lancer directement l'application Shiny dans Positron, utilisez **Run App** sur `app.R`.

## Tests

Après l'installation des dépendances :

```r
testthat::test_dir("tests/testthat")
```

Les tests suivent une boucle de développement inspirée de l'Extreme Programming : écrire un test ciblé, implémenter le comportement minimal, exécuter toute la suite, puis refactorer sans changer le comportement attendu.

## État actuel

La version actuelle fournit un parcours d'accueil, un lanceur local, une base SQLite configurable et un gestionnaire de champs avec dictionnaires, dates, formules dynamiques et archivage réversible. Le formulaire de recueil, la validation complète des réponses et l'écriture des observations restent à ajouter.
