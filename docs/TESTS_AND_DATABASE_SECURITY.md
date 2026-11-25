# Historique des tests et sécurité de la BDD

Ce document garde une trace des validations effectuées et des mesures à prévoir avant un usage multi-utilisateur ou en ligne.

## Historique des tests

| Date | Périmètre | Résultat |
| --- | --- | --- |
| 2026-11-25 | Revue de sécurité avant publication | Entiers hors plage refusés ; bcrypt-PBKDF limité au coût du format ; copies checkpointées et verrouillées ; récupération des verrous sérialisée avec validation des coffres abandonnés ; créations échouées nettoyées. Test parallèle : un seul processus récupère un verrou périmé. |
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
