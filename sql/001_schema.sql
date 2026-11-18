-- =============================================================================
-- LE CRIBLE · 001_schema.sql
-- Schéma de référence de l'observatoire des propositions des candidats à la
-- présidentielle 2027 sur l'urbanisme, l'aménagement, le logement, le cadre de
-- vie et les mobilités.
--
-- Postgres est la référence unique des données. Les CSV ne sont que des
-- exports (voir README). Metabase lit les vues v_* en lecture seule.
--
-- Script idempotent : il peut être relancé sans erreur ni doublon.
-- Il ne supprime jamais de données. Aucun secret dans ce fichier.
-- Compatible PostgreSQL 12 et plus. PostGIS n'est pas requis à ce stade.
--
-- Exécution :  psql -d <base> -v ON_ERROR_STOP=1 -f sql/001_schema.sql
-- =============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS le_crible;
COMMENT ON SCHEMA le_crible IS
  'LE CRIBLE (NEXTE + RAW) : inventaire des sources, fiches, verbatim, propositions et thésaurus des candidats à la présidentielle 2027. Périmètre : urbanisme, aménagement, logement, cadre de vie, mobilités.';

SET LOCAL search_path = le_crible, public;

-- -----------------------------------------------------------------------------
-- Fonction utilitaire : met à jour la colonne modifie_le
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION le_crible.maj_modifie_le()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.modifie_le := now();
  RETURN NEW;
END;
$$;
COMMENT ON FUNCTION le_crible.maj_modifie_le() IS
  'Trigger BEFORE UPDATE : renseigne modifie_le avec l''heure courante.';

-- =============================================================================
-- 1. RÉFÉRENTIELS
-- =============================================================================

-- 1.1 Candidats ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.candidat (
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  initiales        text NOT NULL UNIQUE
                   CHECK (initiales ~ '^[A-Z]{2,4}$'),
  prenom           text,
  nom              text NOT NULL,
  parti            text,
  statut           text NOT NULL DEFAULT 'pressenti'
                   CHECK (statut IN ('pressenti','declare','investi','officiel','retire')),
  date_declaration date,
  date_retrait     date,
  site_web         text,
  notes            text,
  cree_le          timestamptz NOT NULL DEFAULT now(),
  modifie_le       timestamptz NOT NULL DEFAULT now(),
  CHECK (date_retrait IS NULL OR statut = 'retire')
);
COMMENT ON TABLE  le_crible.candidat IS 'Candidats suivis. La liste officielle n''est arrêtée qu''au printemps 2027 : le statut suit leur parcours.';
COMMENT ON COLUMN le_crible.candidat.initiales IS 'Initiales en majuscules, utilisées dans le code d''inventaire (ex. DL, GA, JLM).';
COMMENT ON COLUMN le_crible.candidat.statut IS 'pressenti | declare | investi | officiel (liste du Conseil constitutionnel) | retire.';

-- 1.2 Types de source -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.type_source (
  code        char(1) PRIMARY KEY CHECK (code ~ '^[A-Z]$'),
  libelle     text NOT NULL UNIQUE,
  description text
);
COMMENT ON TABLE le_crible.type_source IS 'Types de source inventoriés. Lettre reprise en suffixe du code d''inventaire.';

INSERT INTO le_crible.type_source (code, libelle, description) VALUES
  ('L', 'Livre',                 'Ouvrage publié par le candidat ou sous sa signature.'),
  ('P', 'Publication internet',  'Site de campagne, billet, post de réseau social, vidéo en ligne.'),
  ('E', 'Extrait de presse',     'Interview, tribune ou article de presse écrite, radio ou télévision.'),
  ('D', 'Discours',              'Discours, meeting, conférence de presse (transcription).'),
  ('G', 'Programme',             'Programme ou livret thématique officiel de campagne.')
ON CONFLICT (code) DO NOTHING;

-- 1.3 Médias / éditeurs ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.media (
  id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug    text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  nom     text NOT NULL,
  genre   text CHECK (genre IN ('quotidien','hebdomadaire','radio','television',
                                'pure_player','editeur','site_candidat',
                                'reseau_social','agence','autre')),
  url     text,
  notes   text
);
COMMENT ON TABLE  le_crible.media IS 'Référentiel normalisé des médias et éditeurs, pour éviter lesechos / les-echos / LesEchos.';
COMMENT ON COLUMN le_crible.media.slug IS 'Identifiant court en minuscules, repris dans le code d''inventaire (ex. lesechos).';

-- 1.4 Thèmes du périmètre ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.theme (
  code        text PRIMARY KEY CHECK (code ~ '^[a-z_]+$'),
  libelle     text NOT NULL UNIQUE,
  ordre       smallint NOT NULL DEFAULT 0,
  description text
);
COMMENT ON TABLE le_crible.theme IS 'Les cinq thèmes du périmètre du Crible. Tout ce qui en sort (sécurité, défense, emploi, culture...) n''est pas inventorié.';

INSERT INTO le_crible.theme (code, libelle, ordre, description) VALUES
  ('urbanisme',    'Urbanisme',                  1, 'Planification, droit des sols, sobriété foncière, formes urbaines.'),
  ('amenagement',  'Aménagement du territoire',  2, 'Équilibre des territoires, ruralité, littoral et montagne, grands projets, risques.'),
  ('logement',     'Logement',                   3, 'Production, accès, parc social et privé, rénovation, normes de l''habitat.'),
  ('cadre_de_vie', 'Cadre de vie',               4, 'Espaces publics, nature en ville, îlots de chaleur, bruit, qualité de l''air, paysage.'),
  ('mobilites',    'Mobilités',                  5, 'Transports collectifs, modes actifs, automobile, ferroviaire, logistique, accessibilité.')
ON CONFLICT (code) DO NOTHING;

-- 1.5 Sous-thèmes -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.sous_theme (
  code        text PRIMARY KEY CHECK (code ~ '^[a-z_]+$'),
  theme_code  text NOT NULL REFERENCES le_crible.theme (code) ON UPDATE CASCADE,
  libelle     text NOT NULL,
  ordre       smallint NOT NULL DEFAULT 0,
  description text,
  UNIQUE (theme_code, libelle)
);
COMMENT ON TABLE le_crible.sous_theme IS 'Découpage de chaque thème. Sert à classer les propositions et à structurer le thésaurus.';

INSERT INTO le_crible.sous_theme (code, theme_code, libelle, ordre) VALUES
  -- Urbanisme
  ('zan_foncier',            'urbanisme',    'Sobriété foncière et ZAN',                   1),
  ('planification',          'urbanisme',    'Planification et documents d''urbanisme',    2),
  ('densification',          'urbanisme',    'Densification et formes urbaines',           3),
  ('droit_construire',       'urbanisme',    'Droit de construire et autorisations',       4),
  ('renouvellement_urbain',  'urbanisme',    'Renouvellement urbain et friches',           5),
  -- Aménagement
  ('equilibre_territorial',  'amenagement',  'Équilibre des territoires et ruralité',      1),
  ('littoral_montagne',      'amenagement',  'Littoral, montagne et recul du trait de côte', 2),
  ('risques_adaptation',     'amenagement',  'Risques naturels et adaptation climatique',  3),
  ('services_publics',       'amenagement',  'Services publics et centralités',            4),
  ('grands_projets',         'amenagement',  'Grands projets et infrastructures',          5),
  -- Logement
  ('production_logement',    'logement',     'Production de logements',                    1),
  ('logement_social',        'logement',     'Logement social',                            2),
  ('loyers_acces',           'logement',     'Loyers, accès et accession à la propriété',  3),
  ('renovation_energetique', 'logement',     'Rénovation énergétique et DPE',              4),
  ('normes_habitat',         'logement',     'Normes de l''habitat et construction',        5),
  ('hebergement',            'logement',     'Hébergement, mal-logement et habitat indigne', 6),
  ('fiscalite_immobiliere',  'logement',     'Fiscalité immobilière',                      7),
  -- Cadre de vie
  ('espaces_publics',        'cadre_de_vie', 'Espaces publics',                            1),
  ('nature_en_ville',        'cadre_de_vie', 'Nature en ville et îlots de chaleur',        2),
  ('air_bruit',              'cadre_de_vie', 'Qualité de l''air et bruit',                  3),
  ('patrimoine_paysage',     'cadre_de_vie', 'Patrimoine et paysage',                      4),
  ('eau',                    'cadre_de_vie', 'Eau et sobriété en eau',                     5),
  -- Mobilités
  ('transports_collectifs',  'mobilites',    'Transports collectifs urbains et interurbains', 1),
  ('ferroviaire',            'mobilites',    'Ferroviaire (trains du quotidien, petites lignes, grande vitesse)', 2),
  ('modes_actifs',           'mobilites',    'Vélo, marche et modes actifs',               3),
  ('automobile',             'mobilites',    'Automobile, carburants et véhicules électriques', 4),
  ('routes_voirie',          'mobilites',    'Routes, voirie, vitesse et stationnement',   5),
  ('mobilite_rurale',        'mobilites',    'Mobilité dans les territoires peu denses',   6),
  ('tarification',           'mobilites',    'Tarification, gratuité et financement des transports', 7),
  ('logistique_fret',        'mobilites',    'Logistique et fret',                         8),
  ('aerien',                 'mobilites',    'Transport aérien',                           9),
  ('accessibilite',          'mobilites',    'Accessibilité et mobilité des personnes vulnérables', 10)
ON CONFLICT (code) DO NOTHING;

-- 1.6 Thésaurus des mots clés --------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.mot_cle (
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug             text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  libelle          text NOT NULL UNIQUE,
  sous_theme_code  text NOT NULL REFERENCES le_crible.sous_theme (code) ON UPDATE CASCADE,
  definition       text,
  statut           text NOT NULL DEFAULT 'propose'
                   CHECK (statut IN ('propose','valide','obsolete')),
  valide_par       text,
  valide_le        date,
  cree_le          timestamptz NOT NULL DEFAULT now(),
  CHECK (statut <> 'valide' OR (valide_par IS NOT NULL AND valide_le IS NOT NULL))
);
COMMENT ON TABLE  le_crible.mot_cle IS 'Thésaurus fermé NEXTE/RAW. Seuls les mots clés au statut valide sont utilisables en production.';
COMMENT ON COLUMN le_crible.mot_cle.slug IS 'Forme utilisée dans le frontmatter des fiches (ex. encadrement-des-loyers).';

-- =============================================================================
-- 2. INVENTAIRE ET VERBATIM
-- =============================================================================

-- 2.1 Publications (inventaire des sources) -------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.publication (
  id                integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code_inventaire   text NOT NULL UNIQUE
                    CHECK (code_inventaire ~ '^[A-Z]{2,4}_[0-9]{6}_[a-z0-9]+(-[a-z0-9]+)*-[A-Z](-[0-9]+)?$'),
  candidat_id       integer NOT NULL REFERENCES le_crible.candidat (id),
  type_code         char(1) NOT NULL REFERENCES le_crible.type_source (code),
  date_publication  date NOT NULL,
  media_id          integer REFERENCES le_crible.media (id),
  titre             text,
  auteur_signataire text,
  url               text,
  chemin_nas        text,
  sha256            text CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  pertinence        text NOT NULL DEFAULT 'a_evaluer'
                    CHECK (pertinence IN ('a_evaluer','dans_perimetre','hors_perimetre')),
  ajoute_le         timestamptz NOT NULL DEFAULT now(),
  ajoute_par        text,
  modifie_le        timestamptz NOT NULL DEFAULT now(),
  notes             text
);
COMMENT ON TABLE  le_crible.publication IS 'Inventaire de référence des sources (une ligne = une publication d''un candidat).';
COMMENT ON COLUMN le_crible.publication.code_inventaire IS 'INITIALES_AAMMJJ_media-TYPE, date de publication. En cas de collision le même jour, suffixe -2, -3... Ex. DL_270219_lesechos-E, DL_270219_lesechos-E-2.';
COMMENT ON COLUMN le_crible.publication.date_publication IS 'Date de publication de la source (et non date de création de la fiche).';
COMMENT ON COLUMN le_crible.publication.chemin_nas IS 'Chemin du fichier source sur le NAS : /volume1/crible/le-crible-decrypter/<Candidat>/<type>/...';
COMMENT ON COLUMN le_crible.publication.sha256 IS 'Empreinte SHA-256 du fichier source (hexadécimal minuscule), pour garantir l''intégrité de l''inventaire.';
COMMENT ON COLUMN le_crible.publication.pertinence IS 'a_evaluer | dans_perimetre | hors_perimetre (la source ne dit rien du périmètre : pas de fiche).';

CREATE INDEX IF NOT EXISTS publication_candidat_date_idx ON le_crible.publication (candidat_id, date_publication);
CREATE INDEX IF NOT EXISTS publication_type_idx          ON le_crible.publication (type_code);
CREATE INDEX IF NOT EXISTS publication_media_idx         ON le_crible.publication (media_id);
CREATE UNIQUE INDEX IF NOT EXISTS publication_sha256_uidx ON le_crible.publication (sha256) WHERE sha256 IS NOT NULL;

-- 2.2 Fiches de synthèse ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.fiche (
  id              integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  publication_id  integer NOT NULL UNIQUE REFERENCES le_crible.publication (id) ON DELETE CASCADE,
  chemin_md       text NOT NULL UNIQUE CHECK (chemin_md ~ '\.md$'),
  synthese        text,
  statut          text NOT NULL DEFAULT 'brouillon'
                  CHECK (statut IN ('brouillon','relue','publiee','retiree')),
  redigee_par     text,
  relue_par       text,
  relue_le        timestamptz,
  publiee_le      timestamptz,
  cree_le         timestamptz NOT NULL DEFAULT now(),
  modifie_le      timestamptz NOT NULL DEFAULT now(),
  CHECK (statut NOT IN ('relue','publiee') OR (relue_par IS NOT NULL AND relue_le IS NOT NULL)),
  CHECK (statut <> 'publiee' OR publiee_le IS NOT NULL)
);
COMMENT ON TABLE  le_crible.fiche IS 'Fiche Markdown (Obsidian) de synthèse d''une publication. Le frontmatter de la fiche reprend code_inventaire.';
COMMENT ON COLUMN le_crible.fiche.statut IS 'brouillon | relue | publiee | retiree. Une fiche ne passe à relue ou publiee qu''après relecture humaine signée.';
COMMENT ON COLUMN le_crible.fiche.redigee_par IS 'IA ou nom de la personne.';

CREATE INDEX IF NOT EXISTS fiche_statut_idx ON le_crible.fiche (statut);

-- 2.3 Extraits (verbatim) -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS le_crible.extrait (
  id              integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  publication_id  integer NOT NULL REFERENCES le_crible.publication (id) ON DELETE CASCADE,
  texte           text NOT NULL CHECK (length(btrim(texte)) > 0),
  localisation    text,
  theme_code      text REFERENCES le_crible.theme (code) ON UPDATE CASCADE,
  cree_le         timestamptz NOT NULL DEFAULT now(),
  cree_par        text
);
COMMENT ON TABLE  le_crible.extrait IS 'Verbatim : citation textuelle d''une publication. Le site public ne diffuse que des citations courtes avec leur source.';
COMMENT ON COLUMN le_crible.extrait.localisation IS 'Page, minute ou paragraphe dans la source (ex. p. 142, 12:35).';

CREATE INDEX IF NOT EXISTS extrait_publication_idx ON le_crible.extrait (publication_id);
CREATE INDEX IF NOT EXISTS extrait_theme_idx       ON le_crible.extrait (theme_code);
CREATE INDEX IF NOT EXISTS extrait_texte_fts_idx   ON le_crible.extrait
  USING gin (to_tsvector('french', texte));

-- =============================================================================
-- 3. PROPOSITIONS (l'unité de comparaison entre candidats)
-- =============================================================================
CREATE TABLE IF NOT EXISTS le_crible.proposition (
  id                integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  candidat_id       integer NOT NULL REFERENCES le_crible.candidat (id),
  sous_theme_code   text NOT NULL REFERENCES le_crible.sous_theme (code) ON UPDATE CASCADE,
  intitule          text NOT NULL,
  description       text,
  nature            text CHECK (nature IN ('legislative','reglementaire','fiscale','budgetaire',
                                           'institutionnelle','contractuelle','incitative','autre')),
  echelle           text CHECK (echelle IN ('nationale','regionale','departementale',
                                            'intercommunale','communale','europeenne')),
  chiffrage         text,
  enjeu_climat      text CHECK (enjeu_climat IN ('attenuation','adaptation','les_deux','aucun','a_qualifier')),
  statut            text NOT NULL DEFAULT 'brouillon'
                    CHECK (statut IN ('brouillon','relue','publiee','retiree')),
  premiere_mention  date,
  cree_le           timestamptz NOT NULL DEFAULT now(),
  cree_par          text,
  modifie_le        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE  le_crible.proposition IS 'Proposition d''un candidat, formulée de façon neutre et rattachée à un sous-thème. Une proposition s''appuie sur un ou plusieurs extraits.';
COMMENT ON COLUMN le_crible.proposition.nature IS 'Instrument mobilisé : legislative, reglementaire, fiscale, budgetaire, institutionnelle, contractuelle, incitative, autre.';
COMMENT ON COLUMN le_crible.proposition.echelle IS 'Échelle de mise en œuvre principale.';
COMMENT ON COLUMN le_crible.proposition.chiffrage IS 'Chiffrage annoncé par le candidat, tel quel (texte libre).';
COMMENT ON COLUMN le_crible.proposition.enjeu_climat IS 'Lien avec le changement climatique : attenuation | adaptation | les_deux | aucun | a_qualifier.';
COMMENT ON COLUMN le_crible.proposition.premiere_mention IS 'Date de la première source connue où la proposition apparaît.';

CREATE INDEX IF NOT EXISTS proposition_candidat_idx   ON le_crible.proposition (candidat_id);
CREATE INDEX IF NOT EXISTS proposition_sous_theme_idx ON le_crible.proposition (sous_theme_code);
CREATE INDEX IF NOT EXISTS proposition_statut_idx     ON le_crible.proposition (statut);

-- 3.1 Proposition ↔ extraits (sources du verbatim) -------------------------------
CREATE TABLE IF NOT EXISTS le_crible.proposition_extrait (
  proposition_id integer NOT NULL REFERENCES le_crible.proposition (id) ON DELETE CASCADE,
  extrait_id     integer NOT NULL REFERENCES le_crible.extrait (id) ON DELETE CASCADE,
  PRIMARY KEY (proposition_id, extrait_id)
);
COMMENT ON TABLE le_crible.proposition_extrait IS 'Extraits textuels qui fondent une proposition.';
CREATE INDEX IF NOT EXISTS proposition_extrait_extrait_idx ON le_crible.proposition_extrait (extrait_id);

-- =============================================================================
-- 4. INDEXATION PAR MOTS CLÉS
-- =============================================================================
CREATE TABLE IF NOT EXISTS le_crible.fiche_mot_cle (
  fiche_id   integer NOT NULL REFERENCES le_crible.fiche (id) ON DELETE CASCADE,
  mot_cle_id integer NOT NULL REFERENCES le_crible.mot_cle (id),
  PRIMARY KEY (fiche_id, mot_cle_id)
);
CREATE INDEX IF NOT EXISTS fiche_mot_cle_mot_idx ON le_crible.fiche_mot_cle (mot_cle_id);
COMMENT ON TABLE le_crible.fiche_mot_cle IS 'Mots clés d''une fiche (repris dans son frontmatter).';

CREATE TABLE IF NOT EXISTS le_crible.extrait_mot_cle (
  extrait_id integer NOT NULL REFERENCES le_crible.extrait (id) ON DELETE CASCADE,
  mot_cle_id integer NOT NULL REFERENCES le_crible.mot_cle (id),
  PRIMARY KEY (extrait_id, mot_cle_id)
);
CREATE INDEX IF NOT EXISTS extrait_mot_cle_mot_idx ON le_crible.extrait_mot_cle (mot_cle_id);
COMMENT ON TABLE le_crible.extrait_mot_cle IS 'Mots clés d''un extrait de verbatim.';

CREATE TABLE IF NOT EXISTS le_crible.proposition_mot_cle (
  proposition_id integer NOT NULL REFERENCES le_crible.proposition (id) ON DELETE CASCADE,
  mot_cle_id     integer NOT NULL REFERENCES le_crible.mot_cle (id),
  PRIMARY KEY (proposition_id, mot_cle_id)
);
CREATE INDEX IF NOT EXISTS proposition_mot_cle_mot_idx ON le_crible.proposition_mot_cle (mot_cle_id);
COMMENT ON TABLE le_crible.proposition_mot_cle IS 'Mots clés d''une proposition.';

-- =============================================================================
-- 5. TRIGGERS modifie_le
-- =============================================================================
DROP TRIGGER IF EXISTS candidat_modifie_le    ON le_crible.candidat;
CREATE TRIGGER candidat_modifie_le    BEFORE UPDATE ON le_crible.candidat
  FOR EACH ROW EXECUTE FUNCTION le_crible.maj_modifie_le();
DROP TRIGGER IF EXISTS publication_modifie_le ON le_crible.publication;
CREATE TRIGGER publication_modifie_le BEFORE UPDATE ON le_crible.publication
  FOR EACH ROW EXECUTE FUNCTION le_crible.maj_modifie_le();
DROP TRIGGER IF EXISTS fiche_modifie_le       ON le_crible.fiche;
CREATE TRIGGER fiche_modifie_le       BEFORE UPDATE ON le_crible.fiche
  FOR EACH ROW EXECUTE FUNCTION le_crible.maj_modifie_le();
DROP TRIGGER IF EXISTS proposition_modifie_le ON le_crible.proposition;
CREATE TRIGGER proposition_modifie_le BEFORE UPDATE ON le_crible.proposition
  FOR EACH ROW EXECUTE FUNCTION le_crible.maj_modifie_le();

-- =============================================================================
-- 6. VUES (exports CSV et Metabase)
-- =============================================================================

-- 6.1 Inventaire à plat : la vue à exporter en CSV
CREATE OR REPLACE VIEW le_crible.v_inventaire AS
SELECT p.code_inventaire,
       c.initiales           AS candidat_initiales,
       concat_ws(' ', c.prenom, c.nom) AS candidat,
       p.type_code,
       ts.libelle            AS type_libelle,
       p.date_publication,
       m.slug                AS media_slug,
       m.nom                 AS media,
       p.titre,
       p.url,
       p.chemin_nas,
       p.sha256,
       p.pertinence,
       f.statut              AS fiche_statut,
       f.chemin_md           AS fiche_chemin,
       (SELECT count(*) FROM le_crible.extrait e WHERE e.publication_id = p.id) AS nb_extraits,
       p.ajoute_le,
       p.ajoute_par
FROM le_crible.publication p
JOIN le_crible.candidat    c  ON c.id = p.candidat_id
JOIN le_crible.type_source ts ON ts.code = p.type_code
LEFT JOIN le_crible.media  m  ON m.id = p.media_id
LEFT JOIN le_crible.fiche  f  ON f.publication_id = p.id;
COMMENT ON VIEW le_crible.v_inventaire IS 'Inventaire à plat, une ligne par publication. Source de l''export CSV.';

-- 6.2 Propositions à plat
CREATE OR REPLACE VIEW le_crible.v_proposition AS
SELECT pr.id                 AS proposition_id,
       c.initiales           AS candidat_initiales,
       concat_ws(' ', c.prenom, c.nom) AS candidat,
       c.parti,
       t.code                AS theme_code,
       t.libelle             AS theme,
       st.code               AS sous_theme_code,
       st.libelle            AS sous_theme,
       pr.intitule,
       pr.description,
       pr.nature,
       pr.echelle,
       pr.chiffrage,
       pr.enjeu_climat,
       pr.statut,
       pr.premiere_mention,
       (SELECT string_agg(DISTINCT p.code_inventaire, ', ' ORDER BY p.code_inventaire)
          FROM le_crible.proposition_extrait pe
          JOIN le_crible.extrait e     ON e.id = pe.extrait_id
          JOIN le_crible.publication p ON p.id = e.publication_id
         WHERE pe.proposition_id = pr.id) AS sources,
       (SELECT string_agg(mc.slug, ', ' ORDER BY mc.slug)
          FROM le_crible.proposition_mot_cle pm
          JOIN le_crible.mot_cle mc ON mc.id = pm.mot_cle_id
         WHERE pm.proposition_id = pr.id) AS mots_cles
FROM le_crible.proposition pr
JOIN le_crible.candidat   c  ON c.id = pr.candidat_id
JOIN le_crible.sous_theme st ON st.code = pr.sous_theme_code
JOIN le_crible.theme      t  ON t.code = st.theme_code;
COMMENT ON VIEW le_crible.v_proposition IS 'Propositions à plat avec thème, sous-thème, sources et mots clés. Base des comparaisons dans Metabase.';

-- 6.3 Couverture candidat × thème (fait apparaître les silences, dont les mobilités)
CREATE OR REPLACE VIEW le_crible.v_couverture_theme AS
SELECT c.initiales AS candidat_initiales,
       concat_ws(' ', c.prenom, c.nom) AS candidat,
       c.statut    AS candidat_statut,
       t.code      AS theme_code,
       t.libelle   AS theme,
       t.ordre     AS theme_ordre,
       count(pr.id)                                    AS nb_propositions,
       count(pr.id) FILTER (WHERE pr.statut = 'publiee') AS nb_propositions_publiees
FROM le_crible.candidat c
CROSS JOIN le_crible.theme t
LEFT JOIN le_crible.sous_theme st ON st.theme_code = t.code
LEFT JOIN le_crible.proposition pr ON pr.sous_theme_code = st.code AND pr.candidat_id = c.id
GROUP BY c.id, c.initiales, c.prenom, c.nom, c.statut, t.code, t.libelle, t.ordre;
COMMENT ON VIEW le_crible.v_couverture_theme IS 'Nombre de propositions par candidat et par thème, zéros compris : montre qui ne dit rien sur un thème.';

-- 6.4 Couverture candidat × sous-thème des mobilités
CREATE OR REPLACE VIEW le_crible.v_couverture_mobilites AS
SELECT c.initiales AS candidat_initiales,
       concat_ws(' ', c.prenom, c.nom) AS candidat,
       st.code     AS sous_theme_code,
       st.libelle  AS sous_theme,
       st.ordre    AS sous_theme_ordre,
       count(pr.id) AS nb_propositions
FROM le_crible.candidat c
CROSS JOIN le_crible.sous_theme st
LEFT JOIN le_crible.proposition pr ON pr.sous_theme_code = st.code AND pr.candidat_id = c.id
WHERE st.theme_code = 'mobilites'
GROUP BY c.id, c.initiales, c.prenom, c.nom, st.code, st.libelle, st.ordre;
COMMENT ON VIEW le_crible.v_couverture_mobilites IS 'Détail des mobilités par sous-thème et par candidat, zéros compris.';

-- 6.5 Nuage de mots clés par candidat
CREATE OR REPLACE VIEW le_crible.v_nuage_mots_cles AS
WITH usages AS (
  SELECT p.candidat_id, fm.mot_cle_id, 'fiche'::text AS origine
    FROM le_crible.fiche_mot_cle fm
    JOIN le_crible.fiche f       ON f.id = fm.fiche_id
    JOIN le_crible.publication p ON p.id = f.publication_id
  UNION ALL
  SELECT p.candidat_id, em.mot_cle_id, 'extrait'
    FROM le_crible.extrait_mot_cle em
    JOIN le_crible.extrait e     ON e.id = em.extrait_id
    JOIN le_crible.publication p ON p.id = e.publication_id
  UNION ALL
  SELECT pr.candidat_id, pm.mot_cle_id, 'proposition'
    FROM le_crible.proposition_mot_cle pm
    JOIN le_crible.proposition pr ON pr.id = pm.proposition_id
)
SELECT c.initiales AS candidat_initiales,
       concat_ws(' ', c.prenom, c.nom) AS candidat,
       mc.slug     AS mot_cle,
       mc.libelle  AS mot_cle_libelle,
       st.theme_code,
       count(*)                                           AS nb_usages,
       count(*) FILTER (WHERE u.origine = 'fiche')        AS nb_fiches,
       count(*) FILTER (WHERE u.origine = 'extrait')      AS nb_extraits,
       count(*) FILTER (WHERE u.origine = 'proposition')  AS nb_propositions
FROM usages u
JOIN le_crible.candidat   c  ON c.id = u.candidat_id
JOIN le_crible.mot_cle    mc ON mc.id = u.mot_cle_id
JOIN le_crible.sous_theme st ON st.code = mc.sous_theme_code
GROUP BY c.initiales, c.prenom, c.nom, mc.slug, mc.libelle, st.theme_code;
COMMENT ON VIEW le_crible.v_nuage_mots_cles IS 'Fréquence des mots clés par candidat (fiches, extraits, propositions).';

-- 6.6 Mots clés partagés entre candidats
CREATE OR REPLACE VIEW le_crible.v_mots_cles_partages AS
SELECT mot_cle, mot_cle_libelle, theme_code,
       count(DISTINCT candidat_initiales) AS nb_candidats,
       string_agg(DISTINCT candidat_initiales, ', ' ORDER BY candidat_initiales) AS candidats,
       sum(nb_usages) AS nb_usages
FROM le_crible.v_nuage_mots_cles
GROUP BY mot_cle, mot_cle_libelle, theme_code;
COMMENT ON VIEW le_crible.v_mots_cles_partages IS 'Mots clés employés par plusieurs candidats : points de convergence.';

-- =============================================================================
-- 7. RÔLES DE LECTURE (Metabase) ET D'ÉCRITURE LIMITÉE
-- Rôles sans mot de passe ni droit de connexion. Créer à part l'utilisateur
-- Metabase et lui donner ce rôle (voir README). Nécessite les droits CREATEROLE ;
-- sinon, le bloc est ignoré avec un simple avertissement.
-- =============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'le_crible_lecture') THEN
    CREATE ROLE le_crible_lecture NOLOGIN;
  END IF;
  GRANT USAGE ON SCHEMA le_crible TO le_crible_lecture;
  GRANT SELECT ON ALL TABLES IN SCHEMA le_crible TO le_crible_lecture;
  ALTER DEFAULT PRIVILEGES IN SCHEMA le_crible GRANT SELECT ON TABLES TO le_crible_lecture;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE WARNING 'Rôle le_crible_lecture non créé ou non autorisé (droits insuffisants). Voir README.';
END;
$$;

-- Rôle d'écriture limitée (contributeurs : NEXTE, RAW). Lecture + ajout +
-- modification, mais pas de suppression ni de changement de structure.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'le_crible_ecriture') THEN
    CREATE ROLE le_crible_ecriture NOLOGIN;
  END IF;
  GRANT le_crible_lecture TO le_crible_ecriture;
  GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA le_crible TO le_crible_ecriture;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA le_crible TO le_crible_ecriture;
  ALTER DEFAULT PRIVILEGES IN SCHEMA le_crible GRANT INSERT, UPDATE ON TABLES TO le_crible_ecriture;
  ALTER DEFAULT PRIVILEGES IN SCHEMA le_crible GRANT USAGE ON SEQUENCES TO le_crible_ecriture;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE WARNING 'Rôle le_crible_ecriture non créé ou non autorisé (droits insuffisants). Voir README.';
END;
$$;

COMMIT;
