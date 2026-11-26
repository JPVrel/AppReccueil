# Application de recueil de données

Application Shiny locale en cours d'expérimentation pour préparer et gérer un recueil de données de recherche.

> [!CAUTION]
> **Prototype réalisé en vibecoding, à utiliser à vos risques et périls.** Le code a été développé avec assistance d'IA et n'a pas fait l'objet d'un audit professionnel indépendant. Il peut contenir des défauts, perdre ou altérer des données, ou présenter des vulnérabilités. Ne l'utilisez pas comme système de production et n'y importez pas de données personnelles, confidentielles, médicales ou réglementées. Testez uniquement sur des copies et conservez des sauvegardes indépendantes.

## Démarrage rapide

### Prérequis communs

- R 4.4 ou supérieur et un accès à CRAN pendant l'installation.
- Le profil `runtime` installe les packages utilisés par l'application : `shiny`, `DT`, `DBI`, `RSQLite`, `yaml`, `writexl`, `readxl` et `openssl`.
- Le profil `development` ajoute `testthat` et `htmltools`, utilisés directement par les tests.
- Le profil `postgres` ajoute `RPostgres` pour le mode distant optionnel.

`renv.lock` contient actuellement les versions résolues avec R 4.6.2. Le script d'installation installe les versions CRAN compatibles avec la version de R présente ; pour reproduire exactement le verrou, utilisez la version de R inscrite dans le lockfile et `renv::restore()`.

### Windows

Installez R pour Windows depuis CRAN. Rtools n'est généralement pas nécessaire : `install.packages()` utilise les binaires Windows lorsqu'ils sont disponibles. Rtools n'est requis que si un package doit être compilé depuis les sources.

Dans PowerShell, depuis la racine du dépôt :

```powershell
Rscript --vanilla .\scripts\install_dependencies.R
Rscript --vanilla .\shiny\run_app.R 8000
```

Ouvrez ensuite <http://127.0.0.1:8000>. Pour utiliser la fenêtre Tcl/Tk, démarrez RStudio ou Positron avec Tcl/Tk disponible, puis exécutez depuis la racine `source("launcher.R")`.

### Linux

Sur Ubuntu/Debian, installez R et les bibliothèques nécessaires à la compilation des dépendances CRAN :

```sh
sudo apt update
sudo apt install r-base r-base-dev libssl-dev libcurl4-openssl-dev libxml2-dev
```

Le lanceur graphique est facultatif. Pour l'utiliser, installez aussi Tcl/Tk et un outil de détection de processus (`lsof` ou `iproute2`, qui fournit `ss`) :

```sh
sudo apt install tcl tk lsof
```

Puis, depuis la racine du dépôt :

```sh
Rscript --vanilla scripts/install_dependencies.R
Rscript --vanilla shiny/run_app.R 8000
```

Ouvrez <http://127.0.0.1:8000>. Pour utiliser la fenêtre Tcl/Tk dans une session graphique, lancez depuis RStudio/Positron `source("launcher.R")`. Sur les autres distributions, installez l'équivalent de `r-base`, `r-base-dev`, `libssl-dev`, `libcurl` et `libxml2` avec le gestionnaire de paquets de la distribution. RSQLite embarque SQLite ; `libsqlite3-dev` n'est pas requis.

### macOS

Installez R 4.4 ou supérieur et OpenSSL 3 avec Homebrew :

```sh
brew install openssl@3
```

Depuis RStudio/Positron, à la racine du projet :

```r
source("scripts/install_dependencies.R")
source("launcher.R")
```

Ou démarrez directement le serveur :

```sh
Rscript --vanilla shiny/run_app.R 8000
```

Dans tous les cas, ouvrez <http://127.0.0.1:8000>. Arrêtez un serveur lancé directement avec `Control-C` dans le terminal. La fenêtre Tcl/Tk lance le serveur comme processus séparé et l'arrête en cliquant sur **Tout quitter**.

## Ce que l'application fait

- Crée ou ouvre une base locale SQLite, avec ou sans mot de passe.
- Importe CSV, Excel (`.xlsx`) ou RDS ; demande un type pour chaque colonne à la création.
- Fusionne un fichier dans une base existante à partir d'une clé unique, avec arbitrage des conflits.
- Affiche les observations dans un tableur avec recherche, filtres, tri et pagination.
- Gère les variables typées, catégories, formules dérivées et champs masqués.
- Exporte en CSV, Excel ou RDS ; le chiffrement de chaque export est facultatif.

La saisie manuelle se fait dans l'onglet **Questionnaire**, avec les champs générés selon la structure de la base.

## Installer les dépendances

Le script installe uniquement les packages absents. Sans option, il installe le profil `runtime`. On peut aussi le lancer depuis RStudio/Positron avec `source("scripts/install_dependencies.R")`.

```sh
Rscript --vanilla scripts/install_dependencies.R
```

Pour exécuter les tests, installez le profil `development` :

```sh
Rscript --vanilla scripts/install_dependencies.R --profile development
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

Pour le mode PostgreSQL distant, installez `RPostgres` avec le profil dédié, puis configurez les identifiants par variables d'environnement comme décrit plus bas :

```sh
Rscript --vanilla scripts/install_dependencies.R --profile postgres
```

Sur Linux, `libssl-dev`, `libcurl4-openssl-dev` et `libxml2-dev` sont les prérequis système conseillés pour compiler les dépendances R depuis CRAN. Sur macOS, le script configure OpenSSL depuis Homebrew lorsqu'il trouve `openssl@3`. Sur Windows, les binaires CRAN évitent normalement la compilation locale.

## Construire une release

Depuis la racine du dépôt, sur le système cible, créez une archive avec l'application et les packages R restaurés depuis `renv.lock` :

```sh
Rscript --vanilla scripts/build_release.R
```

Le ZIP apparaît dans `dist/` avec un nom qui indique le système, l'architecture et la version majeure/mineure de R. Pour choisir un autre emplacement, passez `--output chemin/vers/release.zip`. Le script n'écrase jamais un ZIP existant. Il copie le code, crée une configuration locale standard et des dossiers `data/` et `exports/` vides, puis installe la bibliothèque verrouillée dans `renv/library/`. Les bases, exports et éventuels secrets de la configuration de la machine de build ne sont pas inclus.

La construction nécessite un accès à CRAN et installe `renv` si nécessaire ; l'utilisateur final n'a pas besoin de `renv` ni d'un accès à CRAN. Construisez séparément sous Windows, macOS et Linux avec R 4.6.x pour obtenir des bibliothèques compilées pour chaque plateforme. Après extraction, depuis le dossier `AppReccueil`, démarrez l'application avec :

```sh
Rscript --vanilla shiny/run_app.R 8000
```

Ouvrez ensuite <http://127.0.0.1:8000>. Le lanceur Tcl/Tk reste optionnel. Cette release embarque les packages R ; certaines bibliothèques natives peuvent encore être fournies par le système d'exploitation, donc testez chaque archive sur une installation propre de la plateforme visée.

Le workflow [build-portable-releases.yml](.github/workflows/build-portable-releases.yml) installe le profil de développement dans une bibliothèque temporaire unique, exécute les tests avec celle-ci, puis copie seulement la fermeture runtime dans le ZIP : les packages ne sont pas recompilés une seconde fois. Il construit les archives Linux et Windows sur des runners natifs avec R 4.6.2. Il se lance sur chaque push vers `main` ou manuellement depuis l'onglet **Actions** ; les ZIP sont alors disponibles comme artefacts du workflow. Un tag commençant par `v` déclenche aussi la création ou la mise à jour d'une release GitHub avec les deux archives. Les builds locaux sans bibliothèque fournie continuent à restaurer les packages runtime depuis `renv.lock`.

## Utiliser l'accueil

Au démarrage, l'application recherche les bases dans `data/` et vous propose :

- d'ouvrir une base SQLite sans chiffrement ;
- d'ouvrir un coffre `.sqlite.enc` avec son mot de passe ;
- de créer une base, avec mot de passe facultatif ;
- de créer une copie chiffrée d'une ancienne SQLite.

La copie chiffrée d'une ancienne base ne supprime pas l'original : celui-ci reste en clair jusqu'à une suppression manuelle, après vérification de la copie.

### Importer ou fusionner

L'accueil accepte CSV, Excel (`.xlsx`) et RDS. Les limites sont 25 Mio, 50 000 lignes, 500 colonnes et 1 million de cellules. À la création depuis un fichier, choisissez le type de chaque colonne.

**Attention au format RDS :** c'est une sérialisation d'objets R. Une case de confirmation est obligatoire ; ne chargez que des fichiers provenant d'une source de confiance. Les fichiers chiffrés `.enc` demandent leur mot de passe.

Pour fusionner dans une base déjà ouverte, choisissez une colonne identifiante unique présente dans les deux sources. Les nouvelles observations sont ajoutées, les cellules vides sont complétées et chaque conflit demande quelle valeur conserver. La structure de la base est préservée : les colonnes inconnues du fichier sont ignorées. Si la base change pendant la boîte d'arbitrage, l'opération est annulée et doit être relancée.

### Consulter et gérer les données

**Base de données** fournit le tableur central en lecture seule : tri, recherche, filtres, pagination et export CSV, Excel ou RDS. Un double-clic sur une ligne ouvre cette observation dans **Questionnaire** pour la modifier. Le questionnaire permet aussi de créer une observation et de choisir son ID.

Une observation supprimée est masquée, pas effacée. L'onglet **Éléments supprimés** liste séparément les colonnes et observations masquées et permet de les restaurer. Si l'ID ou l'entête d'origine est déjà utilisé, renseignez un nouvel ID ou une nouvelle entête avant la restauration.

**Gestion des variables** permet d'ajouter, renommer, masquer/restaurer des champs, gérer les catégories et construire des formules dérivées. Le double-clic sur un en-tête ouvre l'édition de la variable correspondante. Les champs masqués restent stockés ; ils ne sont pas supprimés.

Les dates sont au format `YYYY-MM-DD`. Les formules sont structurées et ne sont pas exécutées comme du code R libre. Les colonnes techniques `id`, `created_at`, `payload` et `is_deleted` ne sont pas éditables ; `payload` et `is_deleted` sont exclus des vues et exports.

### Interface

L'application utilise une mise en page responsive avec des cartes par tâche, une navigation en onglets et des actions principales mises en évidence. Les écrans étroits regroupent les contrôles en une seule colonne sans débordement horizontal. Les actions de masquage demandent confirmation ; elles restent réversibles depuis **Éléments supprimés**.

## Données et protection

Une base créée sans mot de passe est un fichier SQLite ordinaire, lisible par toute personne ayant accès au compte et au fichier. Avec un mot de passe, elle est conservée sous forme de coffre AES-256-GCM ; le mot de passe n'est pas enregistré.

Pour travailler, l'application déchiffre le coffre dans un dossier temporaire privé, puis le rechiffre à la fermeture. Un arrêt brutal peut nécessiter une récupération. Si l'état du verrou ou la copie temporaire est ambigu, l'application refuse l'ouverture pour éviter d'écraser des données ; le journal de sécurité décrit la récupération manuelle.

Le chiffrement actuel bufferise les fichiers et refuse les bases/exports supérieurs à 256 Mio. Les fichiers `data/` et `exports/` sont ignorés par Git. Les exports sans mot de passe et les bases sans mot de passe restent en clair.

Le lanceur local écoute uniquement sur `127.0.0.1`. Le mode PostgreSQL distant reste configurable dans [config/database.yml](config/database.yml), mais une utilisation hébergée demande une authentification, des rôles, TLS, des sauvegardes et une revue de sécurité professionnelle.

## PostgreSQL (option avancée)

Le mode distant se configure dans `config/database.yml`. Il ne bénéficie pas du coffre local `.sqlite.enc` : configurez TLS côté serveur, un compte SQL aux droits minimaux et une authentification avant toute mise en réseau.

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

Installez le profil `postgres` et définissez `RECUEIL_DB_USER` et `RECUEIL_DB_PASSWORD` dans l'environnement avant le lancement. Ne placez jamais de secrets dans ce fichier ou dans Git.

## Vérification

Après avoir installé le profil `development`, lancez les tests unitaires et d'intégration :

```sh
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

Les dépendances R verrouillées sont consignées dans `renv.lock`. Pour vérifier les vulnérabilités des paquets R, utilisez OSV-Scanner, qui prend en charge ce format :

```sh
osv-scanner scan source -r .
```

Restaurer les versions verrouillées ou mettre le lockfile à jour :

```r
install.packages("renv")
renv::restore()
renv::snapshot(
  packages = c("shiny", "DT", "DBI", "RSQLite", "yaml", "writexl", "readxl", "openssl", "testthat", "htmltools"),
  prompt = FALSE
)
```

Trivy reste utile pour les secrets et les mauvaises configurations, mais ne prend pas en charge les dépendances CRAN/R.

Pour analyser toutes les sources R et tous les tests, y compris les fichiers ignorés par Git :

```sh
sh scripts/run_semgrep.sh
```

Le journal des validations adversariales et les limites connues sont consignés dans [docs/TESTS_AND_DATABASE_SECURITY.md](docs/TESTS_AND_DATABASE_SECURITY.md).

## État du projet

Le schéma, la gestion des variables, l'import, la fusion, le questionnaire et la suppression/restauration sont expérimentaux. Ce dépôt n'est pas un produit validé pour un déploiement ou un usage clinique/de recherche en production.

## Architecture V1

| Couche | Responsabilité | Technologie principale |
| --- | --- | --- |
| Lanceur local | Ouvre/arrête le serveur Shiny sur `127.0.0.1` | R, Tcl/Tk, PowerShell/terminal |
| Interface | Onglets Accueil, Questionnaire, Tableur, Variables et Éléments supprimés | Shiny, HTML/CSS |
| Schéma | Catalogue stable des colonnes, types, masquage et formules | SQLite, YAML |
| Données | CRUD des observations, valeurs dérivées et restauration logique | DBI, RSQLite |
| Import/export | CSV, XLSX, RDS, fusion par clé et arbitrage | readxl, writexl, openssl |
| Sécurité locale | Verrous, coffre AES-GCM, copie privée temporaire | openssl, RSQLite |
| Tests | Régression, fonctions, Shiny, UI, coffres, imports et processus | testthat |

Les fichiers applicatifs sous `R/database/` gèrent les données, sous `R/shiny/` l'interface, sous `R/launcher/` le processus local, sous `scripts/` l'installation et sous `tests/testthat/` les validations.
