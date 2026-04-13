#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh

source package $PKG_SAMESTR

echo "Job started"; hostname; date

# ── Directories ───────────────────────────────────────────────────────────────
MET_DIR="$OUT_DIR/02_taxonomic_profiling/metaphlan"
CONVERT_DIR="$OUT_DIR/02_taxonomic_profiling/samestr/convert"
MERGE_DIR="$OUT_DIR/02_taxonomic_profiling/samestr/merge"
FILTER_DIR="$OUT_DIR/02_taxonomic_profiling/samestr/filter"
COMPARE_DIR="$OUT_DIR/02_taxonomic_profiling/samestr/compare"
SUMMARIZE_DIR="$OUT_DIR/02_taxonomic_profiling/samestr/summarize"

[[ ! -d "$MERGE_DIR" ]]    && mkdir -p "$MERGE_DIR"
[[ ! -d "$FILTER_DIR" ]]   && mkdir -p "$FILTER_DIR"
[[ ! -d "$COMPARE_DIR" ]]  && mkdir -p "$COMPARE_DIR"
[[ ! -d "$SUMMARIZE_DIR" ]] && mkdir -p "$SUMMARIZE_DIR"

# ── Sanity check ──────────────────────────────────────────────────────────────
NPZ_COUNT=$(find "$CONVERT_DIR" -name "*.npz" 2>/dev/null | wc -l)
if [[ "$NPZ_COUNT" -eq 0 ]]; then
    echo "ERROR: No .npz files found in $CONVERT_DIR. Cannot proceed."
    exit 1
fi
echo "Found $NPZ_COUNT .npz files across $(ls -d $CONVERT_DIR/*/ 2>/dev/null | wc -l) samples"

# ── Merge ─────────────────────────────────────────────────────────────────────
echo "Starting merge step"
find $CONVERT_DIR -name "*.npz" | xargs -n 1 basename | cut -d "." -f 1 | sort | uniq > $MERGE_DIR/clades.txt
echo "Found $(wc -l < $MERGE_DIR/clades.txt) clades to process"

cd $CONVERT_DIR
while read clade; do
    echo "Merging clade: $clade"
    samestr merge \
        --input-files */${clade}.*.npz \
        --marker-dir $SAMEST_DB \
        --nprocs $CPUS_TAX \
        --output-dir $MERGE_DIR
done < $MERGE_DIR/clades.txt
cd $SLURM_SUBMIT_DIR

# ── Filter ────────────────────────────────────────────────────────────────────
echo "Starting filter step"
find $MERGE_DIR -name "*.npz" | xargs -n 1 basename | sed 's/\.npz$//' > $FILTER_DIR/clades.txt
echo "Found $(wc -l < $FILTER_DIR/clades.txt) clades to filter"

cd $MERGE_DIR
while read clade; do
    echo "Filtering clade: $clade"
    if [[ -f "${clade}.npz" && -f "${clade}.names.txt" ]]; then
        samestr filter \
            --input-files ${clade}.npz \
            --input-names ${clade}.names.txt \
            --marker-dir $SAMEST_DB \
            --nprocs $CPUS_TAX \
            --output-dir $FILTER_DIR
    else
        echo "WARNING: Missing files for clade $clade, skipping"
    fi
done < $FILTER_DIR/clades.txt
cd $SLURM_SUBMIT_DIR
echo "Filter step completed"

# ── Compare ───────────────────────────────────────────────────────────────────
echo "Starting compare step"
samestr compare \
    --input-files $FILTER_DIR/*.npz \
    --input-names $FILTER_DIR/*.names.txt \
    --marker-dir $SAMEST_DB \
    --nprocs $CPUS_TAX \
    --output-dir $COMPARE_DIR
echo "Compare step completed"

# ── Summarize ─────────────────────────────────────────────────────────────────
echo "Starting summarize step"
samestr summarize \
    --input-dir $COMPARE_DIR/ \
    --tax-profiles-dir $MET_DIR/ \
    --marker-dir $SAMEST_DB \
    --output-dir $SUMMARIZE_DIR/
echo "Summarize step completed"

# ── Copy final outputs to 04_aggregated ───────────────────────────────────────
AGG_DIR="$OUT_DIR/04_aggregated/02_strain_tracking"
[[ ! -d "$AGG_DIR" ]] && mkdir -p "$AGG_DIR"

echo "Copying SameStr summary outputs to $AGG_DIR"

for FILE in "$SUMMARIZE_DIR"/*; do
    if [[ -f "$FILE" ]]; then
        cp "$FILE" "$AGG_DIR/"
        echo "Copied: $(basename $FILE)"
    else
        echo "WARNING: Expected file not found: $(basename $FILE)"
    fi
done

echo "SameStr aggregation complete. Files written to $AGG_DIR"
echo "Job done"; date
