# Base de données du Crible (PostgreSQL)

Postgres, sur le VPS Alteris, est la **référence unique** des données du Crible :
inventaire des sources, fiches, verbatim, propositions et thésaurus. Les CSV ne
sont que des exports, et Metabase lit la base en lecture seule.

## Contenu

| Fichier | Rôle |
|---|---|
| `001_schema.sql` | Crée le schéma `le_crible` : tables, contraintes, index, commentaires, vues et rôle de lecture. Idempotent. |
| `tests/smoke_test.sql` | Insère un jeu fictif, interroge les vues, vérifie les contraintes, puis annule tout (`ROLLBACK`). |

### Tables

- **Référentiels** : `candidat`, `type_source` (L livre, P internet, E presse, D discours, G programme), `media`, `theme`, `sous_theme`, `mot_cle` (thésaurus fermé NEXTE/RAW).
- **Inventaire et verbatim** : `publication` (code `INITIALES_AAMMJJ_media-TYPE`, suffixe `-2` en cas de collision), `fiche` (fiche Markdown/Obsidian), `extrait` (citations textuelles).
- **Propositions** : `proposition` (rattachée à un sous-thème, avec nature, échelle, chiffrage et lien au climat) et `proposition_extrait` (les extraits qui la fondent).
- **Indexation** : `fiche_mot_cle`, `extrait_mot_cle`, `proposition_mot_cle`.

Les cinq thèmes du périmètre sont pré-remplis : urbanisme, aménagement du
territoire, logement, cadre de vie, **mobilités**. Les mobilités ont dix
sous-thèmes (transports collectifs, ferroviaire, modes actifs, automobile, routes
et voirie, territoires peu denses, tarification, logistique, aérien,
accessibilité). Le thésaurus `mot_cle` est vide : il sera rempli une fois la
liste validée par NEXTE et RAW. Une fiche ou un mot clé ne peut passer en
statut `relue`/`publiee`/`valide` sans le nom et la date de la personne qui a
validé.

## Exécuter le script sur le VPS

```bash
cd /home/debian/le_crible
git pull
psql -h localhost -U <utilisateur> -d <base> -v ON_ERROR_STOP=1 -f sql/001_schema.sql
psql -h localhost -U <utilisateur> -d <base> -v ON_ERROR_STOP=1 -f sql/tests/smoke_test.sql   # facultatif
```

Si Postgres tourne dans Docker :

```bash
docker exec -i <conteneur_postgres> psql -U <utilisateur> -d <base> -v ON_ERROR_STOP=1 < sql/001_schema.sql
```

Le script tourne dans une transaction : en cas d'erreur, rien n'est créé. On peut
le relancer sans risque ; les messages `NOTICE ... already exists, skipping` sont
normaux. Il ne supprime jamais de données. Le mot de passe se donne par
`~/.pgpass` ou la variable `PGPASSWORD`, jamais dans le dépôt.

PostGIS n'est pas utilisé à ce stade : rien dans le schéma ne dépend d'une
géométrie.

## Export CSV

Le CSV est une photo de la base, à régénérer, jamais à modifier à la main.
L'inventaire à plat est dans la vue `v_inventaire` :

```bash
psql -d <base> -c "\copy (SELECT * FROM le_crible.v_inventaire ORDER BY code_inventaire) TO 'exports/inventaire.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8')"
psql -d <base> -c "\copy (SELECT * FROM le_crible.v_proposition ORDER BY candidat, theme_code) TO 'exports/propositions.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8')"
```

`\copy` écrit le fichier côté client (dans le répertoire courant), sans droit
superutilisateur. Pour un import par lot, charger d'abord le CSV dans une table
temporaire puis l'insérer dans `publication` : les contraintes vérifient le code
d'inventaire et l'empreinte SHA-256.

## Metabase

Le script crée le rôle `le_crible_lecture` (sans connexion, sans mot de passe)
avec un droit `SELECT` sur tout le schéma, y compris les tables créées plus tard.
Pour Metabase, créer un utilisateur de connexion et lui donner ce rôle :

```sql
CREATE ROLE metabase_crible LOGIN PASSWORD '...';  -- mot de passe hors dépôt
GRANT le_crible_lecture TO metabase_crible;
```

Dans Metabase, ajouter la base avec cet utilisateur et limiter les schémas à
`le_crible`. Les vues prévues pour les tableaux de bord :

| Vue | Question |
|---|---|
| `v_inventaire` | Qu'avons-nous inventorié, et où en sont les fiches ? |
| `v_proposition` | Que propose chaque candidat, par thème et sous-thème, avec ses sources ? |
| `v_couverture_theme` | Combien de propositions par candidat et par thème, zéros compris ? |
| `v_couverture_mobilites` | Le même détail pour les sous-thèmes des mobilités. |
| `v_nuage_mots_cles` | Quels mots clés chaque candidat emploie-t-il le plus ? |
| `v_mots_cles_partages` | Sur quels mots clés les candidats se rejoignent-ils ? |

Pour le site public, filtrer sur `statut = 'publiee'`.
