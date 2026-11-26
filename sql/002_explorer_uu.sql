-- LE CRIBLE / EXPLORER : référentiel des unités urbaines INSEE 2020 et stockage des indicateurs
-- Échelle d'analyse unique : unité urbaine (UU2020), jamais la commune ni l'EPCI.
-- Idempotent. À exécuter sur la base le_crible (VPS Alteris), extension PostGIS requise.
-- Documentation : BookStack, livre Le_Crible_Explorer, chapitre « Infrastructure géomatique et statistique ».

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS explorer;
COMMENT ON SCHEMA explorer IS 'LE CRIBLE - volet EXPLORER : référentiels et indicateurs à l''échelle des unités urbaines INSEE 2020';

-- 1. Sources : toute valeur stockée renvoie à une source datée
CREATE TABLE IF NOT EXISTS explorer.source (
    id               serial PRIMARY KEY,
    code             text UNIQUE NOT NULL,          -- ex. INSEE_UU2020_GEO2026
    producteur       text NOT NULL,                 -- INSEE, SDES, DGFiP...
    libelle          text NOT NULL,
    millesime_donnee text,                          -- ex. RP2023
    millesime_geo    int,                           -- géographie communale de référence (ex. 2026)
    url              text,
    date_mise_en_ligne date,
    date_import      date NOT NULL DEFAULT current_date,
    licence          text DEFAULT 'Licence Ouverte Etalab 2.0'
);

-- 2. Référentiel des unités urbaines 2020 (toutes, ~2 470)
CREATE TABLE IF NOT EXISTS explorer.uu2020 (
    code_uu       char(5) PRIMARY KEY,              -- ex. 00851 (Paris), 9D603 (Saint-Denis, La Réunion)
    libelle       text NOT NULL,
    type_uu       smallint,                         -- 1 ville isolée ... 5 agglomération internationale
    tuu2017       smallint,
    tduu2017      text,
    nb_communes   int,
    millesime_geo int NOT NULL,
    geom          geometry(MultiPolygon, 4326)      -- fonds INSEE fonds_uu2020_<millésime> (WGS84)
);
CREATE INDEX IF NOT EXISTS uu2020_geom_gix ON explorer.uu2020 USING gist (geom);

-- 3. Table de passage commune -> UU (seul chemin d'agrégation autorisé)
CREATE TABLE IF NOT EXISTS explorer.uu2020_commune (
    codgeo        char(5) NOT NULL,
    millesime_geo int NOT NULL,
    libgeo        text,
    code_uu       char(5) NOT NULL,                 -- pseudo-code dd000 = hors UU du département
    statut        char(1) NOT NULL CHECK (statut IN ('C','B','I','H')),
    dep           text,
    reg           text,
    PRIMARY KEY (codgeo, millesime_geo)
);
CREATE INDEX IF NOT EXISTS uu2020_commune_uu_idx ON explorer.uu2020_commune (code_uu);

-- 4. Périmètre d'étude : les 135 UU de 50 000 habitants et plus (RP 2023), décision du 26/11/2026
CREATE TABLE IF NOT EXISTS explorer.perimetre (
    code_uu          char(5) PRIMARY KEY,
    rang             int NOT NULL,
    libelle          text NOT NULL,
    pop_reference    int NOT NULL,
    millesime_pop    text NOT NULL DEFAULT 'RP2023',
    tranche          text,                          -- '100 000 hab. et plus' | '50 000 à 99 999 hab.'
    drom             boolean NOT NULL DEFAULT false,
    metropole        boolean NOT NULL DEFAULT false, -- ville-centre siège d'une des 22 Métropoles
    commentaire      text
);

-- 5. Portrait de cadrage (sortie de scripts/explorer/uu_perimetre.py, data/explorer/uu2020_perimetre.csv)
CREATE TABLE IF NOT EXISTS explorer.portrait (
    rang int, code_uu char(5) PRIMARY KEY, libelle text, type_uu text, nb_communes int,
    communes_centre text, regions text, departements text, drom boolean,
    metropole boolean, tranche text,
    pop_2023 int, pop_2012 int, evol_pop int, tcam_pop_pct numeric,
    superficie_km2 numeric, densite_hab_km2 numeric,
    logements_2023 int, logements_2012 int, evol_logements_pct numeric,
    part_rp_pct numeric, part_rs_pct numeric, part_vacants_pct numeric, part_vacants_2012_pct numeric,
    part_proprietaires_pct numeric, part_proprietaires_2012_pct numeric,
    niveau_vie_median_eur numeric, taux_pauvrete_pct numeric
);

-- 6. Catalogue des indicateurs (thématiques fournies par l'équipe, rien de pré-rempli)
CREATE TABLE IF NOT EXISTS explorer.indicateur (
    code        text PRIMARY KEY,                   -- ex. LOG_VAC_PART
    libelle     text NOT NULL,
    thematique  text,
    unite       text,                               -- %, nb, €/m², hab/km²...
    definition  text,
    numerateur  text,                               -- pour les ratios : agréger num et dén, puis diviser
    denominateur text,
    source_id   int REFERENCES explorer.source(id)
);

-- 7. Valeurs (format long) : une ligne = une UU x un indicateur x un millésime
CREATE TABLE IF NOT EXISTS explorer.valeur (
    code_uu          char(5) NOT NULL REFERENCES explorer.uu2020(code_uu),
    code_indicateur  text NOT NULL REFERENCES explorer.indicateur(code),
    millesime        text NOT NULL,                 -- ex. 2023
    valeur           numeric,
    valeur_num       numeric,
    valeur_den       numeric,
    statut           text DEFAULT 'A',              -- A définitif, P provisoire, S secret statistique, NA
    source_id        int REFERENCES explorer.source(id),
    PRIMARY KEY (code_uu, code_indicateur, millesime)
);

-- Vue de travail : les UU du périmètre avec leur géométrie
CREATE OR REPLACE VIEW explorer.v_perimetre AS
SELECT p.rang, p.code_uu, p.libelle, p.pop_reference, p.tranche, p.drom, p.metropole, u.type_uu, u.nb_communes, u.geom
FROM explorer.perimetre p JOIN explorer.uu2020 u USING (code_uu)
ORDER BY p.rang;

-- Droits (rôles créés par sql/001_schema.sql)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'le_crible_lecture') THEN
    GRANT USAGE ON SCHEMA explorer TO le_crible_lecture;
    GRANT SELECT ON ALL TABLES IN SCHEMA explorer TO le_crible_lecture;
    ALTER DEFAULT PRIVILEGES IN SCHEMA explorer GRANT SELECT ON TABLES TO le_crible_lecture;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'le_crible_ecriture') THEN
    GRANT USAGE ON SCHEMA explorer TO le_crible_ecriture;
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA explorer TO le_crible_ecriture;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA explorer TO le_crible_ecriture;
  END IF;
END $$;

-- Chargement (psql, depuis la racine du dépôt) :
-- \copy explorer.portrait FROM 'data/explorer/uu2020_perimetre.csv' WITH (FORMAT csv, HEADER, DELIMITER ';')
-- INSERT INTO explorer.perimetre (code_uu, rang, libelle, pop_reference, tranche, drom, metropole)
--   SELECT code_uu, rang, libelle, pop_2023, tranche, drom, metropole FROM explorer.portrait
--   ON CONFLICT (code_uu) DO UPDATE SET rang = EXCLUDED.rang, pop_reference = EXCLUDED.pop_reference, tranche = EXCLUDED.tranche,
--     drom = EXCLUDED.drom, metropole = EXCLUDED.metropole;
-- Géométries (GDAL), après décompression de fonds_uu2020_2026.zip :
-- ogr2ogr -f PostgreSQL PG:"dbname=le_crible" uu2020_2026.shp -nln explorer.uu2020_import -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -t_srs EPSG:4326 -overwrite
-- INSERT INTO explorer.uu2020 (code_uu, libelle, nb_communes, millesime_geo, geom)
--   SELECT uu2020, libuu2020, nb_com::int, 2026, geom FROM explorer.uu2020_import
--   ON CONFLICT (code_uu) DO UPDATE SET geom = EXCLUDED.geom, libelle = EXCLUDED.libelle;
