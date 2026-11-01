#!/usr/bin/env bash
# Fetch the data files that are deliberately NOT in git.
#
# Large sequence data and compiled outputs are released through Zenodo; the
# third-party trait databases are downloaded from their own sources rather than
# redistributed here. Run from the repository root:
#     bash scripts/fetch-data.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1. Database Darkly data release (Zenodo 10.5281/zenodo.15496977) =="
echo "   Open https://zenodo.org/records/15496977 and place files as follows:"
cat <<'MAP'
     deepsea-18s-merged-asv-table-05022025.tsv  -> db-update-may_2025/
     deepsea-18s-merged-asv-table-05022025.qza  -> db-update-may_2025/
     deepsea-18s-merged-seqs-05022025.qza       -> db-update-may_2025/
     taxonomy-05022025.tsv                      -> db-update-may_2025/
     ref-seqs-deepsea-DB_052025.fasta           -> qiime2-code-may2025/
MAP

echo
echo "== 2. PR2 reference taxonomy =="
mkdir -p input-data
for V in 5.1.1 5.0.0; do
  F="input-data/pr2_version_${V}_taxonomy.xlsx"
  if [[ -f "$F" ]]; then
    echo "   have ${F}"
  else
    echo "   downloading PR2 ${V} taxonomy table"
    curl -fsSL -o "$F" \
      "https://github.com/pr2database/pr2database/releases/download/v${V}/pr2_version_${V}_taxonomy.xlsx"
  fi
done

echo
echo "== 3. Third-party trait databases (not redistributed - download manually) =="
cat <<'SRC'
   Mixoplankton Database (MDB), Mitra et al. 2023
     -> input-data/DATABASE_The Mixoplankton Database - MDB (20230418).xlsx
        https://doi.org/10.1111/jeu.12972  (supplementary material)

   Functional trait database, Ramond et al. 2019
     -> input-data/DATABASE_functional-traits-ramond.csv
        https://doi.org/10.1111/1462-2920.14537  (supplementary material)

   PIDA v1.11, Bjorbaekmo et al. 2020
     -> input-data/DATABASE_PIDA_v_1.11_FORMATTED.csv
        https://github.com/ramalok/PIDA

   TMD v1.1 (Jones)
     -> input-data/DATABASE_TMDv1.1_Jones.csv
        (source to be recorded - see annotation-pipeline/VERSIONS.md)
SRC

echo
echo "== 4. v1 inputs (Zenodo 10.5281/zenodo.5959694) =="
echo "   microeuk-merged-asv-table.tsv, taxonomy.tsv -> input-data/"
echo
echo "Done. Re-run annotation-pipeline/build/*.py once files are in place."
