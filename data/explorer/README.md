# Données EXPLORER (exports)

Postgres (schéma `explorer`) est la référence ; ces CSV sont des exports reproductibles.

- `uu2020_top50.csv` : les 50 plus grandes unités urbaines INSEE 2020 (France entière, DROM compris), classées par population municipale RP 2023, avec portrait population / logement / revenus.
- `uu2020_top50_communes.csv` : composition communale de ces 50 UU (code INSEE, statut C ville-centre / B banlieue, population 2023).

Générés par `scripts/explorer/uu_top50.py` (sources INSEE : zonage UU2020 géo 2026, base du comparateur de territoires, historique des populations communales). Séparateur `;`, encodage UTF-8.
Documentation : BookStack, livre Le_Crible_Explorer, chapitre « Infrastructure géomatique et statistique ».
