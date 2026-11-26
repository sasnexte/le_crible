#!/usr/bin/env python3
"""IND-03 - Le ZAN est-il un frein à la production de logements ?
Consommation d'espaces naturels, agricoles et forestiers (NAF) 2011-2020 par habitant supplémentaire,
dans les communes de moins de 5 000 habitants (population 2011) des 135 UU du périmètre.

Sources :
  - Cerema, CONSOENAF 2011-2025, fichier communal conso-com.csv (data.gouv.fr, maj 24/07/2026) :
    naf11art21 = consommation NAF du 01/01/2011 au 01/01/2021 (m²), art11hab21 = dont habitat.
  - INSEE, historique des populations communales (PMUN2011, PMUN2021, géographie 2025).
  - Composition communale des UU (data/explorer/uu2020_perimetre_communes.csv, géographie 2026).
Usage : python3 01_calcul.py <conso-com.csv> <base-pop-historiques-1876-2023.xlsx> <uu2020_perimetre.csv> <uu2020_perimetre_communes.csv> <sortie_dir>
"""
import csv, os, sys, collections
from python_calamine import CalamineWorkbook

SEUIL_POP = 5000          # communes retenues : population municipale 2011 < SEUIL_POP
AN0, AN1 = 2011, 2021     # population au début et à la fin de la période de consommation 2011-2020
SEUIL_FRAGILE = 500       # gain de population inférieur : ratio peu robuste (petit dénominateur)


def main(conso_csv, pop_xlsx, perimetre_csv, communes_csv, out):
    per = {p['code_uu']: p for p in csv.DictReader(open(perimetre_csv, encoding='utf-8'), delimiter=';')}
    com = list(csv.DictReader(open(communes_csv, encoding='utf-8'), delimiter=';'))
    rows = CalamineWorkbook.from_path(pop_xlsx).get_sheet_by_name('pop_1876_2023').to_python()
    i0, i1 = rows[5].index(f'PMUN{AN0}'), rows[5].index(f'PMUN{AN1}')
    pop = {}
    for r in rows[6:]:
        c = '75056' if r[0].startswith('751') else r[0]
        a = pop.setdefault(c, [0.0, 0.0]); a[0] += r[i0] or 0; a[1] += r[i1] or 0
    conso = {}
    with open(conso_csv, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            conso[r['idcom']] = (float(r['naf11art21'] or 0), float(r['art11hab21'] or 0))

    agg = collections.defaultdict(lambda: collections.Counter())
    manquants = []
    for c in com:
        if c['codgeo'] not in pop or c['codgeo'] not in conso:
            manquants.append(c['codgeo']); continue
        p0, p1 = pop[c['codgeo']]
        if p0 >= SEUIL_POP:
            continue
        a = agg[c['code_uu']]
        a['nb_communes'] += 1; a['pop_2011'] += p0; a['pop_2021'] += p1
        a['conso_m2'] += conso[c['codgeo']][0]; a['conso_hab_m2'] += conso[c['codgeo']][1]

    res = []
    for u, p in per.items():
        a = agg.get(u)
        o = {'rang': p['rang'], 'code_uu': u, 'libelle': p['libelle']}
        if not a:
            o.update(classe='SO', classe_libelle='Sans objet : aucune commune de moins de 5 000 hab. en 2011'); res.append(o); continue
        dp = a['pop_2021'] - a['pop_2011']
        o.update(nb_petites_communes=a['nb_communes'], pop_2011=round(a['pop_2011']), pop_2021=round(a['pop_2021']), dpop=round(dp),
                 conso_ha=round(a['conso_m2'] / 1e4, 1), conso_habitat_ha=round(a['conso_hab_m2'] / 1e4, 1),
                 part_habitat_pct=round(100 * a['conso_hab_m2'] / a['conso_m2'], 1) if a['conso_m2'] else None,
                 m2_par_hab_supp=round(a['conso_m2'] / dp) if dp > 0 else None,
                 m2_habitat_par_hab_supp=round(a['conso_hab_m2'] / dp) if dp > 0 else None,
                 m2_pour_1000_hab=round(1000 * a['conso_m2'] / a['pop_2011']),
                 fragile='oui' if 0 < dp < SEUIL_FRAGILE else '',
                 classe='P' if dp > 0 else 'N',
                 classe_libelle='Gain de population' if dp > 0 else 'Consommation sans gain de population')
        res.append(o)
    os.makedirs(out, exist_ok=True)
    cols = ['rang', 'code_uu', 'libelle', 'classe', 'classe_libelle', 'nb_petites_communes', 'pop_2011', 'pop_2021', 'dpop',
            'conso_ha', 'conso_habitat_ha', 'part_habitat_pct', 'm2_par_hab_supp', 'm2_habitat_par_hab_supp', 'm2_pour_1000_hab', 'fragile']
    with open(os.path.join(out, 'ind03_resultats.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter=';'); w.writeheader(); w.writerows(res)
    with open(os.path.join(out, 'ind03_valeurs.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, delimiter=';'); w.writerow(['code_uu', 'code_indicateur', 'millesime', 'valeur', 'valeur_num', 'valeur_den', 'statut'])
        for o in res:
            if o['classe'] == 'SO':
                w.writerow([o['code_uu'], 'IND03_CONSO_NAF_HAB_SUPP', '2011-2020', '', '', '', 'NA']); continue
            w.writerow([o['code_uu'], 'IND03_CONSO_NAF_HAB_SUPP', '2011-2020', o['m2_par_hab_supp'] if o['m2_par_hab_supp'] is not None else '',
                        round(o['conso_ha'] * 1e4), o['dpop'], ('F' if o.get('fragile') else 'A') if o['classe'] == 'P' else 'NA'])
    print(len(res), 'UU ;', collections.Counter(o['classe'] for o in res), '; communes sans correspondance :', len(manquants), manquants[:10])


if __name__ == '__main__':
    main(*sys.argv[1:6])
