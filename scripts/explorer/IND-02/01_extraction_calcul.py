#!/usr/bin/env python3
"""IND-02 - Des documents d'urbanisme qui servent l'intérêt des habitants ?
Étape 1 : rapport [évolution de la population] / [évolution du parc de résidences principales]
pour les 135 UU du périmètre, sur 2012-2023 et les sous-périodes 2012-2017 et 2017-2023.

Source : INSEE, base du comparateur de territoires (niveau UU2020, géographie 2026) :
  POP (population municipale, RP) et DWELLINGS_OCS_DW_MAIN (résidences principales, RP),
  DWELLINGS_POPSIZE (population des ménages).
Usage : python3 01_extraction_calcul.py <comparateur_csv.zip> <uu2020_perimetre.csv> <sortie_dir>
Sorties : ind02_resultats.csv (une ligne par UU) et ind02_valeurs.csv (format long pour explorer.valeur).
"""
import csv, io, os, sys, zipfile, collections

ANS = ('2012', '2017', '2023')
# Typologie provisoire (à valider) sur 2012-2023 ; repère France entière : 0,97 habitant supplémentaire par résidence principale
SEUIL_TENSION, SEUIL_DETENTE = 1.2, 0.6
CLASSES = {
    'A': 'Croissance démographique, parc en retard (plus de 1,2 hab. par RP supplémentaire)',
    'B': 'Croissance accompagnée par le parc (0,6 à 1,2 hab. par RP supplémentaire)',
    'C': 'Parc en avance sur la population (moins de 0,6 hab. par RP supplémentaire)',
    'D': 'Population en baisse, parc en hausse',
    'E': 'Population et parc en baisse',
}


def classe(dp, dr):
    if dp > 0 and dr > 0:
        q = dp / dr
        return 'A' if q > SEUIL_TENSION else ('B' if q >= SEUIL_DETENTE else 'C')
    return 'D' if dr > 0 else 'E'
MES = {'POP': 'pop', 'DWELLINGS_OCS_DW_MAIN': 'rp', 'DWELLINGS_POPSIZE': 'popm'}


def main(zip_path, perimetre_csv, out):
    per = list(csv.DictReader(open(perimetre_csv, encoding='utf-8'), delimiter=';'))
    codes = {p['code_uu'] for p in per}
    M = collections.defaultdict(dict)
    with zipfile.ZipFile(zip_path) as z, z.open('comparateur.csv') as f:
        for r in csv.reader(io.TextIOWrapper(f, 'utf-8'), delimiter=';'):
            geo = r[2] if r[1] == 'UU2020' else ('FRANCE' if r[1] == 'FRANCE' and r[2] == 'F' else None)
            if geo and (geo in codes or geo == 'FRANCE') and r[3] in ANS and r[5] in MES and r[6]:
                M[geo][(MES[r[5]], r[3])] = float(r[6])

    def calc(g):
        m = M[g]; o = {}
        for a, b in (('2012', '2023'), ('2012', '2017'), ('2017', '2023')):
            dp, dr = m[('pop', b)] - m[('pop', a)], m[('rp', b)] - m[('rp', a)]
            o[f'dpop_{a}_{b}'] = round(dp); o[f'drp_{a}_{b}'] = round(dr)
            o[f'ratio_{a}_{b}'] = round(dp / dr, 2) if dr else None
        # taille moyenne des ménages et décomposition de la variation du parc (identité RP = ménages)
        s12, s23 = m[('popm', '2012')] / m[('rp', '2012')], m[('popm', '2023')] / m[('rp', '2023')]
        o['taille_menages_2012'], o['taille_menages_2023'] = round(s12, 3), round(s23, 3)
        o['drp_croissance'] = round((m[('popm', '2023')] - m[('popm', '2012')]) / s23)
        o['drp_desserrement'] = round(m[('popm', '2012')] * (1 / s23 - 1 / s12))
        o['tcam_pop'] = round(100 * ((m[('pop', '2023')] / m[('pop', '2012')]) ** (1 / 11) - 1), 2)
        o['tcam_rp'] = round(100 * ((m[('rp', '2023')] / m[('rp', '2012')]) ** (1 / 11) - 1), 2)
        o['ecart_tcam_pts'] = round(o['tcam_pop'] - o['tcam_rp'], 2)
        o['classe'] = classe(o['dpop_2012_2023'], o['drp_2012_2023'])
        o['classe_libelle'] = CLASSES[o['classe']]
        return o

    ref = calc('FRANCE')
    rows = []
    for p in per:
        o = {'rang': p['rang'], 'code_uu': p['code_uu'], 'libelle': p['libelle']}
        o.update(calc(p['code_uu']))
        rows.append(o)
    rows.append({'rang': '', 'code_uu': 'FRANCE', 'libelle': 'France entière', **ref})
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'ind02_resultats.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), delimiter=';'); w.writeheader(); w.writerows(rows)
    with open(os.path.join(out, 'ind02_valeurs.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, delimiter=';'); w.writerow(['code_uu', 'code_indicateur', 'millesime', 'valeur', 'valeur_num', 'valeur_den', 'statut'])
        for o in rows[:-1]:
            for a, b in (('2012', '2023'), ('2012', '2017'), ('2017', '2023')):
                w.writerow([o['code_uu'], 'IND02_RATIO_POP_RP', f'{a}-{b}', o[f'ratio_{a}_{b}'] if o[f'ratio_{a}_{b}'] is not None else '',
                            o[f'dpop_{a}_{b}'], o[f'drp_{a}_{b}'], 'A' if o[f'ratio_{a}_{b}'] is not None else 'NA'])
    print(len(rows) - 1, 'UU ; France ratio 2012-2023 =', ref['ratio_2012_2023'])


if __name__ == '__main__':
    main(*sys.argv[1:4])
