#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh
source package $PKG_METAPHLAN

echo "Job started"; hostname; date

MET_DIR="$OUT_DIR/02_taxonomic_profiling/metaphlan"
AGG_DIR="$OUT_DIR/04_aggregated/02_taxonomic_profiling"

[[ ! -d "$AGG_DIR" ]] && mkdir -p "$AGG_DIR"

# ── Sanity check ──────────────────────────────────────────────────────────────
PROFILE_COUNT=$(find "$MET_DIR" -name "*.unclprofile.txt" | wc -l)
if [[ "$PROFILE_COUNT" -eq 0 ]]; then
    echo "ERROR: No .unclprofile.txt files found in $MET_DIR"
    exit 1
fi
echo "Found $PROFILE_COUNT unclassified profiles to merge"

# ── Merge MetaPhlAn profiles ──────────────────────────────────────────────────
echo "Merging MetaPhlAn profiles..."
merge_metaphlan_tables.py $MET_DIR/*.unclprofile.txt \
    -o $AGG_DIR/metaphlan_merged.tsv
echo "Merged table written to $AGG_DIR/metaphlan_merged.tsv"

# ── copy markdown file  ───────────────────────────────────────────────────────
cp scripts/02_taxonomic_report.Rmd $AGG_DIR

echo "Job done"; date
