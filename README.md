# Application de recueil de données

Application de bureau locale pour créer un recueil de données, importer des fichiers, saisir et consulter des observations, puis les exporter. L’interface s’ouvre dans votre navigateur, mais les données restent sur votre ordinateur.

> **À lire avant utilisation.** Cette application est expérimentale et n’a pas été auditée professionnellement. Elle peut contenir des défauts et entraîner une perte ou une altération de données. N’y mettez pas de données personnelles, médicales, confidentielles ou réglementées. Ne l’utilisez pas pour un projet de production. Faites d’abord vos essais sur des copies et gardez des sauvegardes séparées.

## Télécharger

Choisissez le fichier correspondant au système de votre ordinateur :

- **Windows** : ouvrir les [builds Windows, Linux et macOS](https://github.com/JPVrel/AppReccueil/actions/workflows/build-portable-releases.yml), puis télécharger l’artefact `AppReccueil-windows` dans le dernier run réussi.
- **Linux** : ouvrir les [builds Windows, Linux et macOS](https://github.com/JPVrel/AppReccueil/actions/workflows/build-portable-releases.yml), puis télécharger l’artefact `AppReccueil-linux` dans le dernier run réussi.
- **macOS** : ouvrir les [builds Windows, Linux et macOS](https://github.com/JPVrel/AppReccueil/actions/workflows/build-portable-releases.yml), puis télécharger l’artefact `AppReccueil-macos` dans le dernier run réussi.
- [Voir la page des versions publiées](https://github.com/JPVrel/AppReccueil/releases).

Les ZIP du dernier build réussi sont disponibles dans les artefacts du workflow. Ces téléchargements temporaires expirent après 30 jours. Une version publiée apparaîtra sur la page des versions lorsqu’un tag de release sera créé.

L’archive contient l’application et ses packages R. **R doit quand même être installé** sur votre ordinateur. Utilisez R 4.6.x, la famille de version avec laquelle ces archives sont construites. Il n’est pas nécessaire d’installer les packages de l’application séparément.

## Installer et lancer

1. Téléchargez le ZIP correspondant à votre système, puis extrayez-le dans un dossier où vous avez le droit d’écrire.
2. Ouvrez le dossier extrait `AppReccueil`.
3. Ouvrez un terminal dans ce dossier et lancez la commande correspondante.

**Windows, dans PowerShell :**

```powershell
Rscript --vanilla .\shiny\run_app.R 8000
```

**Linux, dans un terminal :**

```sh
Rscript --vanilla shiny/run_app.R 8000
```

**macOS, dans Terminal :**

```sh
Rscript --vanilla shiny/run_app.R 8000
```

4. Ouvrez <http://127.0.0.1:8000> dans votre navigateur.
5. Pour arrêter l’application, revenez au terminal et appuyez sur `Ctrl+C`.

Si la commande `Rscript` est introuvable, installez R 4.6.x ou demandez à la personne qui gère votre ordinateur de l’ajouter au chemin système. Au premier lancement, votre système peut demander de confirmer l’ouverture d’un fichier téléchargé.

## Vos données

Au premier lancement, l’application crée les dossiers `data` et `exports` à côté du programme. Vos bases et fichiers exportés y seront enregistrés. Conservez des copies de sauvegarde, notamment avant une mise à jour ou une opération de fusion.

Vous pouvez créer une base SQLite avec ou sans mot de passe. Sans mot de passe, le fichier de base n’est pas chiffré. Avec mot de passe, la base est conservée dans un coffre chiffré ; le mot de passe n’est pas récupérable par l’application.

L’application sait notamment :

- importer des fichiers CSV, Excel (`.xlsx`) ou RDS ;
- saisir et modifier des observations dans **Questionnaire** ;
- consulter les données dans **Base de données** ;
- organiser les variables, catégories et formules ;
- masquer puis restaurer des observations ou variables ;
- exporter en CSV, Excel ou RDS, avec chiffrement facultatif de l’export.

Les imports sont limités à 25 Mio, 50 000 lignes, 500 colonnes et 1 million de cellules. RDS est un format sérialisé par R : ne chargez que des fichiers provenant d’une source de confiance. Lors d’une fusion, choisissez une clé unique commune aux deux fichiers ; les conflits sont présentés pour arbitrage.

**Attention aux fichiers non chiffrés :** les bases SQLite créées sans mot de passe et les exports sans mot de passe sont lisibles par toute personne ayant accès à ces fichiers.

## Aide et versions

- [Versions publiées](https://github.com/JPVrel/AppReccueil/releases)
- [Derniers ZIP Windows, Linux et macOS](https://github.com/JPVrel/AppReccueil/actions/workflows/build-portable-releases.yml)
- [Signaler un problème](https://github.com/JPVrel/AppReccueil/issues)

## Informations développeur

Cette section regroupe les détails de développement, de maintenance et de vérification. Les instructions destinées aux personnes qui veulent simplement utiliser l’application se trouvent plus haut.

### Prérequis et dépendances R

Le projet demande R 4.4 ou supérieur pour le développement. `renv.lock` contient actuellement les versions résolues avec R 4.6.2. Les archives distribuées sont construites sous R 4.6.2 ; leur bibliothèque embarquée est séparée par système, architecture et famille de version R.

Le profil `runtime` comprend `shiny`, `DT`, `DBI`, `RSQLite`, `yaml`, `writexl`, `readxl` et `openssl`. Le profil `development` ajoute `testthat` et `htmltools`. Le profil optionnel `postgres` ajoute `RPostgres`.

Installer les dépendances runtime depuis la racine du dépôt :

```sh
Rscript --vanilla scripts/install_dependencies.R
```

Installer les outils de test et lancer la suite :

```sh
Rscript --vanilla scripts/install_dependencies.R --profile development
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

Pour le mode PostgreSQL distant :

```sh
Rscript --vanilla scripts/install_dependencies.R --profile postgres
```

Sur Ubuntu/Debian, les prérequis système conseillés pour compiler les dépendances CRAN sont `r-base`, `r-base-dev`, `libssl-dev`, `libcurl4-openssl-dev` et `libxml2-dev`. Le lanceur graphique facultatif demande Tcl/Tk et `lsof` ou `ss`. RSQLite embarque SQLite ; `libsqlite3-dev` n’est pas requis. Sur macOS, installez OpenSSL 3 avec `brew install openssl@3` ; le script configure le package R `openssl` s’il trouve Homebrew. Sous Windows, CRAN fournit normalement des binaires ; Rtools n’est utile que lorsqu’une compilation locale est nécessaire.

### Construire les archives

Construire une archive pour le système courant, depuis la racine du dépôt :

```sh
Rscript --vanilla scripts/build_release.R
```

Le ZIP est écrit dans `dist/`. Pour spécifier un autre chemin, utilisez `--output chemin/vers/release.zip`. Le script refuse d’écraser une archive existante. Il copie le code, crée une configuration SQLite locale standard ainsi que des dossiers `data/` et `exports/` vides, puis embarque les packages runtime. Il n’inclut pas les bases, exports ni secrets du poste de build.

Sans bibliothèque source fournie, le script restaure les packages runtime depuis `renv.lock` et installe `renv` si besoin. La CI définit `APPRECUEIL_BUILD_LIBRARY` pour réutiliser sa bibliothèque de packages déjà installée : les tests et la release partagent alors les mêmes compilations, et seule la fermeture des dépendances runtime est copiée dans le ZIP.

Pour construire hors CI, faites le build sur chaque système cible : Linux, Windows et macOS. Les packages compilés ne sont pas interchangeables entre systèmes ou architectures. La release contient les packages R, mais certaines bibliothèques natives peuvent encore être fournies par le système. Testez chaque archive extraite sur une installation propre de la plateforme visée.

### CI et publications GitHub

Le workflow [build-portable-releases.yml](.github/workflows/build-portable-releases.yml) utilise des runners natifs Ubuntu, Windows et macOS avec R 4.6.2. Sur chaque push vers `main` et lors d’un lancement manuel depuis l’onglet **Actions**, il installe les dépendances de développement dans une bibliothèque temporaire, exécute les tests, construit les trois ZIP puis les publie comme artefacts conservés 30 jours.

Un tag commençant par `v` déclenche aussi la création ou la mise à jour d’une release GitHub avec les trois ZIP. La page des releases est [ici](https://github.com/JPVrel/AppReccueil/releases). Une release taguée est le lien de téléchargement durable ; les artefacts d’un run Actions sont temporaires.

### Développement local

Sur macOS, installez OpenSSL 3 avec Homebrew :

```sh
brew install openssl@3
```

Depuis RStudio ou Positron, ouvrez la racine du dépôt et lancez :

```r
source("scripts/install_dependencies.R")
source("launcher.R")
```

La fenêtre Tcl/Tk démarre un processus serveur séparé et ouvre le navigateur. Elle est facultative ; le serveur peut aussi être lancé directement avec `Rscript --vanilla shiny/run_app.R 8000`. Il écoute uniquement sur `127.0.0.1`. Sous Linux, la fenêtre graphique demande Tcl/Tk et un outil de détection de processus (`lsof` ou `ss`). Sous Windows, la détection utilise `netstat`.

### PostgreSQL distant

Le mode distant se configure dans `config/database.yml`. Il ne bénéficie pas du coffre local `.sqlite.enc`. Configurez TLS côté serveur, un compte SQL aux droits minimaux et une authentification avant toute mise en réseau. Installez le profil `postgres`, puis définissez les identifiants `RECUEIL_DB_USER` et `RECUEIL_DB_PASSWORD` dans l’environnement. Ne mettez jamais de secrets dans le fichier de configuration ou dans Git.

Exemple de configuration :

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

### Tests et analyse

Après installation du profil `development` :

```sh
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

Les versions verrouillées sont dans `renv.lock`. Pour vérifier les vulnérabilités des packages R avec OSV-Scanner :

```sh
osv-scanner scan source -r .
```

Trivy reste utile pour les secrets et les mauvaises configurations, mais ne prend pas en charge les dépendances CRAN/R. Pour analyser toutes les sources R et les tests, y compris les fichiers ignorés par Git :

```sh
sh scripts/run_semgrep.sh
```

Le journal des validations adversariales et les limites connues sont décrits dans [docs/TESTS_AND_DATABASE_SECURITY.md](docs/TESTS_AND_DATABASE_SECURITY.md).

### Données, sécurité et limites connues

Avec un mot de passe, une base est conservée dans un coffre AES-256-GCM ; le mot de passe n’est pas stocké. Pour l’ouvrir, l’application la déchiffre dans un dossier temporaire privé et la rechiffre à la fermeture. Un arrêt brutal peut nécessiter une récupération. Si l’état d’un verrou ou d’une copie temporaire est ambigu, l’application refuse l’ouverture afin d’éviter d’écraser des données ; voir le journal de sécurité pour les procédures de récupération.

Le chiffrement actuel charge les fichiers en mémoire et refuse les bases ou exports de plus de 256 Mio. Les fichiers `data/` et `exports/` sont ignorés par Git. Une base ou un export sans mot de passe reste en clair.

Les formules sont structurées et ne sont pas exécutées comme du code R libre. Les colonnes techniques `id`, `created_at`, `payload` et `is_deleted` ne sont pas éditables ; `payload` et `is_deleted` sont exclus des vues et exports. Une observation supprimée est masquée, pas effacée. Les champs masqués restent stockés.

Le mode PostgreSQL et tout hébergement réseau nécessitent une authentification, des rôles, TLS, des sauvegardes et une revue de sécurité professionnelle. Le dépôt reste expérimental et n’est pas validé pour un usage clinique, de recherche en production ou d’autres usages réglementés.

### Architecture

| Couche | Responsabilité | Technologie principale |
| --- | --- | --- |
| Lanceur local | Démarre/arrête Shiny sur `127.0.0.1` | R, Tcl/Tk ou terminal |
| Interface | Accueil, questionnaire, tableur, variables et éléments supprimés | Shiny, HTML/CSS |
| Schéma | Catalogue stable des colonnes, types, masquage et formules | SQLite, YAML |
| Données | CRUD, valeurs dérivées et restauration logique | DBI, RSQLite |
| Import/export | CSV, XLSX, RDS, fusion par clé et arbitrage | readxl, writexl, openssl |
| Sécurité locale | Verrous, coffre, copie temporaire privée | openssl, RSQLite |
| Tests | Fonctions, Shiny, interface, coffres, imports et processus | testthat |

Le code des données se trouve dans `R/database/`, l’interface dans `R/shiny/`, le lanceur dans `R/launcher/`, les scripts dans `scripts/` et les tests dans `tests/testthat/`.
