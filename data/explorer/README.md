# Données EXPLORER (exports)

Postgres (schéma `explorer`) est la référence ; ces CSV sont des exports reproductibles.

- `uu2020_perimetre.csv` : les 135 unités urbaines INSEE 2020 de 50 000 habitants et plus (France entière, DROM compris), classées par population municipale RP 2023, avec étiquettes (métropole, diagonale du vide, outre-mer, tranche) et portrait population / logement / revenus.
- `uu2020_perimetre_communes.csv` : composition communale de ces 135 UU (code INSEE, statut C ville-centre / B banlieue, population 2023).

Générés par `scripts/explorer/uu_perimetre.py` (sources INSEE : zonage UU2020 géo 2026, base du comparateur de territoires, historique des populations communales). Séparateur `;`, encodage UTF-8.
Documentation : BookStack, livre Le_Crible_Explorer, chapitre « Infrastructure géomatique et statistique ».
