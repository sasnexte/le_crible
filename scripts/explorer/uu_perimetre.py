#!/usr/bin/env python3
"""LE CRIBLE / EXPLORER - Périmètre d'étude : unités urbaines INSEE 2020 de 50 000 habitants et plus (135 UU).

Télécharge les fichiers INSEE officiels, classe les unités urbaines 2020
(France entière, DROM compris) par population municipale du dernier
recensement, retient celles de 50 000 habitants et plus, les étiquette (métropole, diagonale du vide), et produit les CSV à charger dans Postgres (schéma explorer).

Sources (INSEE) :
  - Zonage UU2020, géographie au 01/01/2026 : https://www.insee.fr/fr/information/4802589
  - Base du comparateur de territoires (niveau UU2020, RP 2012/2023, Filosofi 2023) :
    https://www.insee.fr/fr/statistiques/2521169
  - Historique des populations communales 1876-2023 : https://www.insee.fr/fr/statistiques/3698339

Usage : python3 uu_perimetre.py <dossier_telechargement> <dossier_sortie>
Dépendance : python-calamine (pip install python-calamine)
"""
import csv, io, os, sys, urllib.request, zipfile, collections
from python_calamine import CalamineWorkbook

URL_UU = "https://www.insee.fr/fr/statistiques/fichier/4802589/UU2020_au_01-01-2026.zip"
URL_COMP = "https://www.insee.fr/fr/statistiques/fichier/2521169/comparateur_csv.zip"
URL_POP = "https://www.insee.fr/fr/statistiques/fichier/3698339/base-pop-historiques-1876-2023.xlsx"
SEUIL = 50000          # périmètre : UU de 50 000 habitants et plus au RP 2023 (décision du 26/11/2026)
AN_REF, AN_BASE = "2023", "2012"
# UU dont la ville-centre est le siège d'une des 22 Métropoles (loi MAPTAM et suivantes) : simple étiquette,
# l'échelle d'analyse reste l'unité urbaine.
METROPOLES = {'00851', '00760', '00759', '59702', '33701', '00758', '44701', '06701', '67701', '34701', '35701',
              '38701', '00755', '00757', '37701', '29701', '54701', '57701', '45701', '21701', '00753', '63701'}
# Diagonale du vide : départements métropolitains de moins de 50 hab/km² (RP 2023) situés sur l'axe Meuse-Landes,
# hors massifs alpins (04, 05), Corse et Orne. Une UU y appartient si son département principal (le plus de communes) en fait partie.
DIAGONALE = {'03', '09', '12', '15', '18', '19', '23', '24', '32', '36', '40', '43', '46', '48', '52', '55', '58', '70', '89'}
REG = {'01': 'Guadeloupe', '02': 'Martinique', '03': 'Guyane', '04': 'La Réunion', '06': 'Mayotte',
       '11': 'Île-de-France', '24': 'Centre-Val de Loire', '27': 'Bourgogne-Franche-Comté', '28': 'Normandie',
       '32': 'Hauts-de-France', '44': 'Grand Est', '52': 'Pays de la Loire', '53': 'Bretagne',
       '75': 'Nouvelle-Aquitaine', '76': 'Occitanie', '84': 'Auvergne-Rhône-Alpes',
       '93': "Provence-Alpes-Côte d'Azur", '94': 'Corse'}
TYPE_UU = {1: 'Ville isolée', 2: 'Agglomération intra-départementale', 3: 'Agglomération inter-départementale',
           4: 'Agglomération inter-régionale', 5: 'Agglomération internationale'}


def get(url, dl):
    path = os.path.join(dl, url.rsplit('/', 1)[1])
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path)
    return path


def sheet(path, name, skip=6):
    return CalamineWorkbook.from_path(path).get_sheet_by_name(name).to_python()[skip:]


def main(dl, out):
    os.makedirs(dl, exist_ok=True); os.makedirs(out, exist_ok=True)
    zuu = zipfile.ZipFile(get(URL_UU, dl)); xl = os.path.join(dl, zuu.namelist()[0]); zuu.extractall(dl)
    liste = {r[0]: r for r in sheet(xl, 'UU2020')}
    compo = collections.defaultdict(list)
    for r in sheet(xl, 'Composition_communale'):
        if r[5] != 'H':  # H = commune hors unité urbaine
            compo[r[2]].append(r)

    # population communale (géo 2025) ; Paris en arrondissements -> 75056
    pop = collections.defaultdict(float)
    rows = CalamineWorkbook.from_path(get(URL_POP, dl)).get_sheet_by_name('pop_1876_2023').to_python()
    i = rows[5].index('PMUN' + AN_REF)
    for r in rows[6:]:
        c = '75056' if r[0].startswith('751') else r[0]
        pop[c] += r[i] or 0

    # indicateurs au niveau UU2020 (comparateur, géo 2026)
    M = collections.defaultdict(dict)
    with zipfile.ZipFile(get(URL_COMP, dl)) as z:
        with z.open('comparateur.csv') as f:
            for r in csv.reader(io.TextIOWrapper(f, 'utf-8'), delimiter=';'):
                if r[1] == 'UU2020' and r[3] in (AN_REF, AN_BASE) and r[6]:
                    M[r[2]][(r[3], r[5])] = float(r[6])

    uu = sorted((u for u in compo if (AN_REF, 'POP') in M[u]), key=lambda u: -M[u][(AN_REF, 'POP')])
    top, lignes, comm = [u for u in uu if M[u][(AN_REF, 'POP')] >= SEUIL], [], []
    for rang, u in enumerate(top, 1):
        g = lambda an, v: M[u].get((an, v))
        rs = compo[u]
        regs = collections.Counter(r[7] for r in rs); deps = collections.Counter(r[6] for r in rs)
        p23, p12 = g(AN_REF, 'POP'), g(AN_BASE, 'POP')
        L, RP = g(AN_REF, 'DWELLINGS'), g(AN_REF, 'DWELLINGS_OCS_DW_MAIN')
        L0, RP0 = g(AN_BASE, 'DWELLINGS'), g(AN_BASE, 'DWELLINGS_OCS_DW_MAIN')
        pct = lambda a, b: round(100 * a / b, 1) if a is not None and b else None
        centres = [r[1] for r in sorted(rs, key=lambda r: -pop[r[0]]) if r[5] == 'C']
        lignes.append({
            'rang': rang, 'code_uu': u, 'libelle': liste[u][1], 'type_uu': TYPE_UU[int(liste[u][4])],
            'nb_communes': len(rs), 'communes_centre': ' ; '.join(centres),
            'regions': ' / '.join(REG[k] for k, _ in regs.most_common()),
            'departements': ' ; '.join(k for k, _ in deps.most_common()),
            'drom': u[:2] in ('9A', '9B', '9C', '9D', '9F'),
            'metropole': u in METROPOLES,
            'diagonale_vide': deps.most_common(1)[0][0] in DIAGONALE,
            'tranche': '100 000 hab. et plus' if p23 >= 100000 else '50 000 à 99 999 hab.',
            'pop_' + AN_REF: int(p23), 'pop_' + AN_BASE: int(p12), 'evol_pop': int(p23 - p12),
            'tcam_pop_pct': round(100 * ((p23 / p12) ** (1 / (int(AN_REF) - int(AN_BASE))) - 1), 2),
            'superficie_km2': g(AN_REF, 'SUP'), 'densite_hab_km2': round(p23 / g(AN_REF, 'SUP')),
            'logements_' + AN_REF: round(L), 'logements_' + AN_BASE: round(L0),
            'evol_logements_pct': round(100 * (L / L0 - 1), 1),
            'part_rp_pct': pct(RP, L),
            'part_rs_pct': pct(g(AN_REF, 'DWELLINGS_OCS_DW_SEC_DW_OCC'), L),
            'part_vacants_pct': pct(g(AN_REF, 'DWELLINGS_OCS_DW_VAC'), L),
            'part_vacants_' + AN_BASE + '_pct': pct(g(AN_BASE, 'DWELLINGS_OCS_DW_VAC'), L0),
            'part_proprietaires_pct': pct(g(AN_REF, 'DWELLINGS_OCS_DW_MAIN_TSH_100'), RP),
            'part_proprietaires_' + AN_BASE + '_pct': pct(g(AN_BASE, 'DWELLINGS_OCS_DW_MAIN_TSH_100'), RP0),
            'niveau_vie_median_eur': g(AN_REF, 'MED_SL'), 'taux_pauvrete_pct': g(AN_REF, 'PR_MD60'),
        })
        for r in sorted(rs, key=lambda r: -pop[r[0]]):
            comm.append({'code_uu': u, 'codgeo': r[0], 'libgeo': r[1], 'statut': r[5],
                         'dep': r[6], 'reg': r[7], 'pop_' + AN_REF: int(pop[r[0]]) if r[0] in pop else ''})
    for nom, data in (('uu2020_perimetre.csv', lignes), ('uu2020_perimetre_communes.csv', comm)):
        with open(os.path.join(out, nom), 'w', newline='', encoding='utf-8') as f:
            w = csv.DictWriter(f, fieldnames=list(data[0]), delimiter=';'); w.writeheader(); w.writerows(data)
    print(f"{len(lignes)} UU, {len(comm)} communes -> {out}")


if __name__ == '__main__':
    main(*sys.argv[1:3])
