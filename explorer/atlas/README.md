# Atlas des 50 unités urbaines

Carte interactive (D3, sans fond de tuiles) des 50 plus grandes unités urbaines INSEE 2020, métropole + encarts outre-mer.

- `data/top50.json` : portrait des 50 UU (issu de `data/explorer/uu2020_top50*.csv`).
- `data/*.json` (TopoJSON) : contours INSEE `fonds_uu2020_2026` simplifiés pour l'affichage avec mapshaper (départements 4 %, toutes UU 8 %, UU du top 50 25 %, communes du top 50 15 %). Ne pas utiliser pour des calculs : la géométrie de référence est celle chargée dans PostGIS (`explorer.uu2020`).

Régénérer les contours (depuis le dossier où `fonds_uu2020_2026.zip` est décompressé) :

    mapshaper com_uu2020_2026.shp -filter "[<codes>].indexOf(uu2020)>-1" -simplify 15% keep-shapes -filter-fields codgeo,libgeo,uu2020,type_com -o communes_top50.json format=topojson quantization=1e5

`index.html` est un fragment publié comme Artifact (sans balises html/head/body).
