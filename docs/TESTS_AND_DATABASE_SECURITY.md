# Historique des tests et sécurité de la BDD

Ce document garde une trace des validations effectuées et des mesures à prévoir avant un usage multi-utilisateur ou en ligne.

## Historique des tests

| Date | Périmètre | Résultat |
| --- | --- | --- |
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
- Tableur central : lignes vides ou renseignées, colonnes dérivées, sélection par en-tête et téléchargement CSV.
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
- La vue tableur et son export CSV omettent `payload`, colonne technique non nécessaire à l'utilisateur.
- Les archives CSV côté serveur sont conservées dans `exports/`, mais ignorées par Git pour ne pas versionner des observations.
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
- Table alimentée : lignes, tri, filtres globaux/par colonne, pagination et export CSV.
- Double-clic sur un champ modifiable : passage à Gestion des variables, choix et nom préremplis.
- Double-clic sur une variable catégorielle ou dérivée : dictionnaire ou formule correspondante chargés.
- Double-clic sur une colonne technique, en-tête inconnu ou champ masqué : aucune édition, message clair.
- Après ajout, renommage, masquage ou changement de catégorie : tableur rafraîchi et valeurs cohérentes.
