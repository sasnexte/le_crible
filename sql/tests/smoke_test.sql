-- Test de fumée du schéma le_crible : insère un jeu fictif, interroge les vues,
-- vérifie quelques contraintes, puis annule tout (ROLLBACK). Ne laisse aucune donnée.
-- psql -d <base> -v ON_ERROR_STOP=1 -f sql/tests/smoke_test.sql

BEGIN;
SET LOCAL search_path = le_crible, public;

INSERT INTO candidat (initiales, prenom, nom, statut) VALUES ('XX', 'Candidat', 'Fictif', 'declare');
INSERT INTO media (slug, nom, genre) VALUES ('journal-test', 'Journal Test', 'quotidien');
INSERT INTO mot_cle (slug, libelle, sous_theme_code) VALUES ('rer-metropolitain', 'RER métropolitain', 'transports_collectifs');

INSERT INTO publication (code_inventaire, candidat_id, type_code, date_publication, media_id, titre)
SELECT 'XX_270219_journal-test-E', c.id, 'E', '2027-02-19', m.id, 'Interview fictive'
FROM candidat c, media m WHERE c.initiales = 'XX' AND m.slug = 'journal-test';

INSERT INTO fiche (publication_id, chemin_md)
SELECT id, 'XX_270219_journal-test-E.md' FROM publication WHERE code_inventaire = 'XX_270219_journal-test-E';

INSERT INTO extrait (publication_id, texte, localisation, theme_code)
SELECT id, 'Texte fictif sur les transports du quotidien.', '§3', 'mobilites'
FROM publication WHERE code_inventaire = 'XX_270219_journal-test-E';

INSERT INTO proposition (candidat_id, sous_theme_code, intitule, nature, echelle, enjeu_climat)
SELECT id, 'transports_collectifs', 'Proposition fictive de test', 'budgetaire', 'nationale', 'attenuation'
FROM candidat WHERE initiales = 'XX';

INSERT INTO proposition_extrait SELECT p.id, e.id FROM proposition p, extrait e;
INSERT INTO proposition_mot_cle SELECT p.id, m.id FROM proposition p, mot_cle m;
INSERT INTO fiche_mot_cle SELECT f.id, m.id FROM fiche f, mot_cle m;

SELECT code_inventaire, candidat, media, fiche_statut, nb_extraits FROM v_inventaire;
SELECT candidat, theme, sous_theme, intitule, sources, mots_cles FROM v_proposition;
SELECT theme, nb_propositions FROM v_couverture_theme WHERE candidat_initiales = 'XX' ORDER BY theme_ordre;
SELECT mot_cle, nb_usages, nb_fiches, nb_propositions FROM v_nuage_mots_cles;

-- Contraintes : chaque bloc doit échouer
DO $$
BEGIN
  BEGIN
    INSERT INTO le_crible.publication (code_inventaire, candidat_id, type_code, date_publication)
    SELECT 'mauvais code', id, 'E', '2027-01-01' FROM le_crible.candidat WHERE initiales = 'XX';
    RAISE EXCEPTION 'ÉCHEC : code_inventaire invalide accepté';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK : code_inventaire invalide refusé';
  END;
  BEGIN
    UPDATE le_crible.fiche SET statut = 'publiee';
    RAISE EXCEPTION 'ÉCHEC : fiche publiée sans relecture acceptée';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK : publication sans relecture refusée';
  END;
  BEGIN
    UPDATE le_crible.mot_cle SET statut = 'valide';
    RAISE EXCEPTION 'ÉCHEC : mot clé validé sans validateur accepté';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK : validation de mot clé sans signataire refusée';
  END;
END;
$$;

ROLLBACK;
