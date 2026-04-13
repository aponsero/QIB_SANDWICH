#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh

echo "Job started"; hostname; date

HUMANN_DIR="$OUT_DIR/03_functional_annotation/humann3"
DIAMOND_DIR="$OUT_DIR/03_functional_annotation/diamond"

# ── HUMAnN3 merge ─────────────────────────────────────────────────────────────
if [[ "$RUN_HUMANN" == true ]]; then
    echo "Starting HUMAnN3 merge"
    source package $PKG_HUMANN_UTILS 

    HUMANN_NORM_DIR="$HUMANN_DIR/cpm_pathway_norm"
    HUMANN_RESULTS_DIR="$HUMANN_DIR/result_tables"
    [[ ! -d "$HUMANN_NORM_DIR" ]]    && mkdir -p "$HUMANN_NORM_DIR"
    [[ ! -d "$HUMANN_RESULTS_DIR" ]] && mkdir -p "$HUMANN_RESULTS_DIR"

    # Sanity check
    PAT_COUNT=$(find "$HUMANN_DIR" -maxdepth 1 -name "*_pathabundance.tsv" | wc -l)
    if [[ "$PAT_COUNT" -eq 0 ]]; then
        echo "ERROR: No pathabundance.tsv files found in $HUMANN_DIR"
        exit 1
    fi
    echo "Found $PAT_COUNT pathabundance files"

    cd $HUMANN_DIR

    # Normalize pathway abundance to CPM
    for f in *_pathabundance.tsv; do
        humann_renorm_table --input $f --output cpm_$f --units cpm
        mv cpm_$f $HUMANN_NORM_DIR/
    done

    # Merge and stratify
    humann_join_tables \
        --input $HUMANN_NORM_DIR \
        --output $HUMANN_RESULTS_DIR/humann_pathabundance.tsv \
        --file_name cpm_

    humann_split_stratified_table \
        --input $HUMANN_RESULTS_DIR/humann_pathabundance.tsv \
        --output $HUMANN_RESULTS_DIR

    cd $SLURM_SUBMIT_DIR
    echo "HUMAnN3 merge complete"
fi

# ── Diamond merge (ARG + virulence) ──────────────────────────────────────────
if [[ "$RUN_ARG" == true || "$RUN_VIRULENCE" == true ]]; then
    echo "Starting Diamond results merge"

    # Sanity check
    RC_COUNT=$(find "$DIAMOND_DIR" -name "*_readcounts.txt" | wc -l)
    if [[ "$RC_COUNT" -eq 0 ]]; then
        echo "ERROR: No readcount files found in $DIAMOND_DIR"
        exit 1
    fi
    echo "Found $RC_COUNT readcount files"

    # Concatenate per-sample read counts into single file
    READCOUNT_FILE="$DIAMOND_DIR/all_readcounts.txt"
    cat $DIAMOND_DIR/*_readcounts.txt > $READCOUNT_FILE

    # Run merging python script from diamond directory
    cd $DIAMOND_DIR 
    singularity exec $MERGING_SIF python3 $SLURM_SUBMIT_DIR/scripts/merging_results.py $READCOUNT_FILE 
    cd $SLURM_SUBMIT_DIR

    echo "Diamond merge complete"
fi

# ── Copy final outputs to 04_aggregated ───────────────────────────────────────

AGG_DIR="$OUT_DIR/04_aggregated/03_functional_annotation"
if [[ ! -d "$AGG_DIR" ]]; then
    mkdir -p $AGG_DIR
fi

echo "Copying merged outputs to $AGG_DIR"

if [[ "$RUN_HUMANN" == true ]]; then
    HUMANN_RESULTS_DIR="$HUMANN_DIR/result_tables"
    for FILE in \
        "$HUMANN_RESULTS_DIR/humann_pathabundance.tsv" \
        "$HUMANN_RESULTS_DIR/humann_pathabundance_unstratified.tsv" \
        "$HUMANN_RESULTS_DIR/humann_pathabundance_stratified.tsv"; do
        if [[ -f "$FILE" ]]; then
            cp "$FILE" "$AGG_DIR/"
            echo "Copied: $(basename $FILE)"
        else
            echo "WARNING: Expected file not found: $(basename $FILE)"
        fi
    done
fi

if [[ "$RUN_ARG" == true ]]; then
    for FILE in \
        "$DIAMOND_DIR/card_merged_long.tsv" \
        "$DIAMOND_DIR/card_merged_wide.tsv"; do
        if [[ -f "$FILE" ]]; then
            cp "$FILE" "$AGG_DIR/"
            echo "Copied: $(basename $FILE)"
        else
            echo "WARNING: Expected file not found: $(basename $FILE)"
        fi
    done
fi

if [[ "$RUN_VIRULENCE" == true ]]; then
    for FILE in \
        "$DIAMOND_DIR/vfdb_merged_long.tsv" \
        "$DIAMOND_DIR/vfdb_merged_wide.tsv"; do
        if [[ -f "$FILE" ]]; then
            cp "$FILE" "$AGG_DIR/"
            echo "Copied: $(basename $FILE)"
        else
            echo "WARNING: Expected file not found: $(basename $FILE)"
        fi
    done
fi

echo "Aggregation complete. Files written to $AGG_DIR"
echo "Job done"; date
