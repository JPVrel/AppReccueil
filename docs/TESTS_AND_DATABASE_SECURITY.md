# Historique des tests et sécurité de la BDD

Ce document garde une trace des validations effectuées et des mesures à prévoir avant un usage multi-utilisateur ou en ligne.

## Historique des tests

| Date | Périmètre | Résultat |
| --- | --- | --- |
| 2026-11-25 | Parcours adversarial demandé | Tentatives SQL/HTML littérales, formules CSV, fichiers/formats invalides, tailles/lignes au-delà des limites, chemins hors dossier, noms de base hostiles, valeurs entières extrêmes, clés dupliquées, conflit périmé, changement de base durant arbitrage, verrous/copies simultanés, coffres altérés et RDS non confirmé. Cas bloqués par message/assertion ; aucune écriture hors base temporaire. |
| 2026-11-25 | Revue de sécurité avant publication | Entiers hors plage refusés ; bcrypt-PBKDF limité au coût du format ; copies checkpointées et verrouillées ; récupération des verrous sérialisée avec validation des coffres abandonnés ; créations échouées nettoyées. Test parallèle : un seul processus récupère un verrou périmé. |
| 2026-11-25 | Essais adversariaux supplémentaires | Contrôle propriétaire des chemins, plan de fusion lié à sa base, confirmation RDS avant désérialisation, enveloppe binaire sans `readRDS`, plafonds parsing/chiffrement et récupération de sauvegarde `.previous`. |
| 2026-11-25 | Suite complète après tests adversariaux | 124 cas, 431 assertions, 0 échec, 0 erreur et 0 avertissement. |
| 2026-11-25 | Suite complète après essais adversariaux | 123 cas, 425 assertions, 0 échec, 0 erreur et 0 avertissement. |
| 2026-11-25 | Suite finale après confirmation RDS et limites de parsing | 124 cas, 431 assertions, 0 échec, 0 erreur et 0 avertissement. |
| 2026-11-25 | Suite complète après audit de sécurité | 110 cas, 382 assertions, 0 échec, 0 erreur et 0 avertissement. |
| 2026-11-25 | Accueil, coffre et import | Tests couvrent création/ouverture/fermeture avec ou sans mot de passe, copie protégée d'une SQLite ancienne, import CSV/XLSX/RDS, typage, fusion par clé, remplissage, ajout et choix de conflits. Exports protégés réimportables avec mot de passe ; les exports sans mot de passe restent en clair. |
| 2026-11-25 | Suite complète après parcours d'accueil | 100 cas de test, 345 assertions, 0 échec, 0 erreur et 0 avertissement. |
| 2026-11-25 | Vérification navigateur isolée | Création sans mot de passe depuis CSV synthétique ; CSV et XLSX clairs HTTP 200 ; XLSX/RDS protégés `.enc` HTTP 200 ; RDS chiffré relu après déchiffrement. Aucune donnée réelle n'a été modifiée. |
| 2026-11-25 | Exports CSV, Excel et data frame R | Écriture et archivage testés pour CSV, XLSX et RDS ; valeurs dérivées présentes, colonnes masquées et `payload` absents. Le CSV neutralise les valeurs texte commençant par une formule. Dépendance `writexl` ajoutée aux packages d'exécution. |
| 2026-11-25 | Réservation des archives | Noms créés via verrou de répertoire atomique ; test parallèle de réservations simultanées sans collision. |
| 2026-11-25 | Exports depuis le navigateur | Les trois endpoints répondent HTTP 200 avec un nom d'archive horodaté ; XLSX vérifié comme classeur ZIP valide, RDS relu par `readRDS()` comme data frame. |
| 2026-11-25 | Suite complète après audit des exports | 88 assertions réussies, 0 échec ; aucun diagnostic R dans les modules et tests modifiés. |
| 2026-11-25 | Suite automatisée après ajout du dossier d'exports | 87 assertions réussies, 0 échec. |
| 2026-11-25 | Base vide dans le navigateur | Session fraîche sur `8000` : WebSocket connecté, table vide avec les colonnes système visibles, bouton CSV actif et endpoint d'export vérifié. |
| 2026-11-25 | Régression après correction de l'initialisation Shiny et des opérations SQL | 75 assertions réussies ; la session réelle a été vérifiée sur navigateur : WebSocket connecté, overlay absent, onglet BDD accessible. |
| 2026-11-25 | Suite automatisée après ajout du tableur et de l'édition par en-tête | 84 assertions réussies, 0 échec. |
| 2026-11-25 | Vue tableur DT et double-clic d'en-tête | Base de test temporaire : 31 lignes ; recherche exacte/sans résultat ; pagination 25 + 6 ; tri ascendant ; filtre `cohort=control` donnant 16 résultats ; double-clic stocké/catégoriel/dérivé, refus de `id`, renommage prérempli, puis en-tête actualisé vérifiés dans le navigateur. |
| 2026-11-25 | Rafraîchissement de la table | Ajout d'une variable via Gestion des variables ; le nouvel en-tête apparaît immédiatement dans Base de données, sans rechargement. |
| 2026-11-25 | Export CSV | Endpoint navigateur `fetch` : réponse HTTP 200, `text/csv`, disposition `attachment`, 31 observations et variable dérivée incluses, `payload` absent. Test unitaire : export archivé dans un dossier dédié, nom horodaté sans écrasement, valeurs masquées et payload exclus. Le navigateur intégré ne relaie pas toujours son événement natif `download`, le corps CSV a donc aussi été contrôlé via la réponse HTTP. |
| 2026-11-25 | Session Shiny réelle | WebSocket actif, overlay absent, navigation vers Base de données et Gestion des variables validée ; la session de test utilise une copie temporaire de l'application et de SQLite. |

### Matrice des tentatives adversariales

| Tentative | Contrôle observé | Décision |
| --- | --- | --- |
| Chemin SQLite forgé (`../`, absolu, fichier sibling) | Chemin canonique vérifié sous `data/` avant l'ouverture ou la copie | Rejeté ; fichier extérieur inchangé |
| Nom de base avec séparateur, extension ou `..` | Liste blanche de caractères et nommage serveur de l'extension | Rejeté avec erreur de nom |
| Mot de passe vide, confirmation absente ou différente | Les deux champs doivent être vides, ou correspondre avec 12 caractères minimum | Rejeté avec erreur explicite |
| RDS sans confirmation | La désérialisation n'est appelée qu'après la case de confiance | Import bloqué ; l'utilisateur doit confirmer une source de confiance |
| RDS malformé après confirmation | Erreur du désérialiseur convertie en message utilisateur | Rejeté comme RDS invalide/incompatible |
| `.enc` RDS/ancien envelope ou magic invalide | En-tête binaire fixe contrôlé avant AES-GCM ; aucune désérialisation RDS de l'enveloppe | Rejeté comme coffre invalide |
| Mauvais mot de passe ou ciphertext/tag altéré | Authentification AES-GCM | Déchiffrement refusé |
| Itérations KDF modifiées ou paramètres tronqués | Coût KDF exact et dimensions fixes validés avant dérivation | Rejeté avant bcrypt-PBKDF |
| CSV de plus de 25 Mio, classeur expansé >100 Mio, import >50 000 lignes/500 colonnes/1 million de cellules | Contrôles de taille archive/fichier et lecture CSV/XLSX bornée | Import refusé avec limite affichée |
| XLSX faux/corrompu | Archive ZIP inspectée avant `readxl` | Rejeté avec erreur de classeur |
| En-têtes vides ou doublons insensibles à la casse | Validation avant normalisation des noms | Rejetés, pas de collision SQL |
| Texte ressemblant à SQL ou HTML dans une ligne importée | Valeurs DBI citées, nom de champ validé ; rendu Shiny/DT échappé | Conservé comme donnée littérale, aucune requête/markup exécuté |
| Cellule texte CSV commençant par `=`, `+`, `-` ou `@` (espaces compris) | Neutralisation formule dans le writer CSV | Export préfixé par apostrophe ; XLSX garde les textes comme cellules partagées, sans formule |
| Entier décimal, `Inf`, valeurs hors bornes R ou limite décimale ambiguë | Parse exact des chaînes et borne représentable vérifiée avant coercition | Rejeté au lieu de devenir `NA` |
| Clé de fusion vide, dupliquée ou collision après conversion | Unicité revérifiée après conversion de type | Fusion refusée avant écriture |
| Base modifiée après aperçu de fusion | Plan recalculé dans la transaction avant application | Plan périmé rejeté, aucune valeur écrasée |
| Changement de base pendant la boîte de conflit | Plan lié au chemin de la base source | Choix refusé sur la nouvelle base |
| Erreur après création de quelques colonnes d'import | Transaction DBI et suppression du fichier créé par la tentative | Pas de base partielle ; même nom réutilisable |
| Deux réservations d'export simultanées | Répertoire de verrou atomique pour chaque nom | Noms uniques générés |
| Deux accès à une base ouverte | Verrou `.active` exclusif propriétaire/PID | Second accès refusé |
| Arrêt pendant une session coffre | Verrou abandonné sérialisé ; workspace privé contrôlé, SQLite integrity-check et WAL checkpoint avant rechiffrement | Récupéré si intègre ; sinon verrou/fichiers conservés et message d'action manuelle |
| Récupération interrompue, PID/propriétaire/path incohérent | Claim `.recovery` exclusif et correspondance hôte/PID/mode/chemin | Échec fermé ; vérification/suppression manuelle nécessaire |
| Copie d'une SQLite active ou checkpoint WAL incomplet | Verrou source et statut checkpoint vérifié | Copie protégée refusée, source préservée |
| Fichier base/export au-delà de 256 Mio à chiffrer | Taille contrôlée avant chargement du buffer AES | Refusé avec message, source préservée |

**Limite assumée :** RDS reste un format sérialisé. L'application exige une confirmation de confiance, mais ne peut pas démontrer la provenance d'un objet RDS ; ne charge pas de RDS provenant d'une source inconnue. Les coffres sont locaux et accessibles aux personnes ayant le compte système et le mot de passe ; le chiffrement ne remplace ni l'authentification multi-utilisateur ni la sécurité du poste.

### Cas couverts par la suite automatisée existante

- Initialisation et intégrité SQLite, catalogue des champs et import des colonnes existantes.
- Ajout, renommage, masquage et restauration des colonnes avec conservation des valeurs.
- Types, validations de dates, dictionnaires catégoriels et réaffectation des réponses.
- Variables dérivées : compatibilité des types, comparateurs, valeurs manquantes, divisions par zéro, chaînage et cycles.
- Connexion et déconnexion DBI, configuration locale/distante et dépendances.
- Contrôles Shiny, table de variables, callbacks et affichage des erreurs.
- Tableur central : lignes vides ou renseignées, colonnes dérivées, sélection par en-tête et téléchargements CSV, XLSX et RDS.
- Accueil : inventaire, ouverture/création de coffre, conversion par copie des anciennes bases, typage des colonnes importées et fusion par clé avec arbitrage.
- Double-clic navigateur sur les colonnes stockées, catégorielles, dérivées et système ; les champs système sont refusés.
- Recherche globale avec résultat et sans résultat, pagination au-delà de 25 lignes, et rafraîchissement après renommage.

Commande de référence :

```r
testthat::test_dir("tests/testthat")
```

## Sécurité actuelle

- Les valeurs des en-têtes sont résolues dans le catalogue actif ; elles ne sont jamais interpolées dans du SQL.
- Les requêtes SQL utilisent DBI pour citer les identifiants et les valeurs.
- Les types de formules sont en liste blanche ; aucune expression utilisateur n'est évaluée comme du code R.
- Les changements de code catégoriel, réaffectations et changements de schéma sont transactionnels.
- Le masquage conserve les colonnes et valeurs ; il n'existe pas de suppression physique depuis l'interface.
- Les secrets d'une base distante sont attendus via des variables d'environnement, pas dans le dépôt.
- Les bases et exports pour lesquels un mot de passe est défini utilisent AES-256-GCM et une clé dérivée du mot de passe ; aucune clé n'est stockée avec les données. Laisser le mot de passe vide crée ou exporte un fichier en clair.
- Les imports sont plafonnés à 25 Mio, 50 000 lignes, 500 colonnes et 1 million de cellules. Les fichiers RDS sont des objets sérialisés ; l'UI demande une confirmation et seules des sources de confiance doivent être chargées.
- Le chiffrement AES bufferise le fichier ; les bases et exports de plus de 256 Mio sont refusés avant lecture en mémoire.
- Les chemins reçus depuis les sélecteurs Shiny sont canonicalisés et doivent pointer directement dans le dossier `data/` configuré.
- Un plan de fusion est recalculé dans la transaction avant écriture ; tout changement entre aperçu et validation annule l'opération.
- Pendant une session, SQLite utilise une copie temporaire déchiffrée, dans un répertoire privé. Après un arrêt brutal, la prochaine ouverture vérifie puis rechiffre la copie ; si elle est invalide, les fichiers temporaires sont conservés pour récupération manuelle.
- Si l'application est interrompue pendant la récupération d'un verrou, le marqueur `.recovery` est volontairement conservé ; après avoir vérifié qu'aucun processus ne travaille sur cette base, retire ce marqueur manuellement avant de rouvrir.
- La conversion d'une ancienne SQLite conserve la source en clair ; l'accueil avertit et ne la supprime pas automatiquement.
- La vue tableur et ses exports omettent `payload`, colonne technique non nécessaire à l'utilisateur.
- Les archives côté serveur sont conservées dans `exports/`, mais ignorées par Git pour ne pas versionner des observations.
- L'application est actuellement locale et ne possède pas d'authentification ni de rôles.

## À sécuriser avant une mise en ligne

1. Ajouter une authentification et des rôles : seuls les administrateurs pourront modifier le schéma, les dictionnaires et les formules.
2. Définir les droits SQL minimaux pour le compte applicatif et séparer les identifiants d'administration.
3. Ajouter des migrations versionnées, sauvegardes vérifiées et procédure de restauration avant tout changement de schéma.
4. Activer TLS, restreindre les réseaux autorisés et stocker les secrets dans le gestionnaire de secrets de l'hébergeur.
5. Ajouter un journal d'audit append-only (utilisateur, action, horodatage, ancienne/nouvelle valeur) pour les changements de schéma et de dictionnaire.
6. Définir les règles de confidentialité, pseudonymisation, rétention, export et suppression des données de recherche.
7. Tester les accès concurrents, conflits de renommage, transactions interrompues, sauvegardes et migrations sur PostgreSQL.
8. Ajouter des tests de permissions qui prouvent qu'un utilisateur standard ne peut pas appeler les opérations administratives.

## Parcours navigateur à valider pour l'onglet tableur

- Table vide : en-têtes de base présents, message de table vide, aucun voile Shiny.
- Table alimentée : lignes, tri, filtres globaux/par colonne, pagination et exports CSV, XLSX et RDS chiffrés.
- Double-clic sur un champ modifiable : passage à Gestion des variables, choix et nom préremplis.
- Double-clic sur une variable catégorielle ou dérivée : dictionnaire ou formule correspondante chargés.
- Double-clic sur une colonne technique, en-tête inconnu ou champ masqué : aucune édition, message clair.
- Après ajout, renommage, masquage ou changement de catégorie : tableur rafraîchi et valeurs cohérentes.

## Résultat du parcours utilisateur hostile

- Sécurisé par rejet : SQL/HTML littéral n'est pas exécuté ; séparateurs de chemin, noms invalides, ID trop longs, valeurs entières hors plage, dates impossibles, noms de colonnes longs, réponses longues et catégories longues sont refusés.
- Sécurisé par traitement littéral : HTML, SQL ressemblant, apostrophes, Unicode et valeurs commençant par `=`, `+`, `-` ou `@` restent des données sans interprétation comme code ou formule ; les exports CSV neutralisent les cellules formule.
- Cas débile mais impossible : octet NUL et caractères de contrôle non représentables dans R/SQLite sont rejetés ou ne peuvent pas être transmis comme chaîne valide.
- Cas possible mais interdit : texte >10 000 caractères par réponse, entête >64 caractères, catégorie >255 caractères et années hors 1000–9999. Des messages explicites expliquent les limites.
- Limite assumée : aucune authentification ni rôles dans l'application locale. Elle ne doit pas être exposée comme application multi-utilisateur sur Internet sans TLS, autorisations serveur et journal d'audit.
