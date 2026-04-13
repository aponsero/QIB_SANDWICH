#!/bin/bash -l
source config.sh

echo "=== Taxonomic Profiling ==="
echo ""

# ── Sample sheet ──────────────────────────────────────────────────────────────
if [[ ! -f "$SAMPLE_SHEET" ]]; then
    echo "ERROR: Sample sheet not found at $SAMPLE_SHEET"
    exit 1
fi

NUM_JOBS=$(( $(wc -l < "$SAMPLE_SHEET") - 1 ))

# Strip Windows carriage returns from sample sheet if present
sed -i 's/\r//' "$SAMPLE_SHEET"

if [[ "$NUM_JOBS" -lt 1 ]]; then
    echo "ERROR: No samples found in $SAMPLE_SHEET"
    exit 1
fi
echo "Samples to process: $NUM_JOBS"

# ── Module dependency check ───────────────────────────────────────────────────
if [[ "$RUN_SAMESTR" == true && "$RUN_METAPHLAN" != true ]]; then
    echo "ERROR: RUN_SAMESTR=true requires RUN_METAPHLAN=true"
    exit 1
fi

if [[ "$RUN_METAPHLAN" != true && "$RUN_KRAKEN" != true ]]; then
    echo "ERROR: Both RUN_METAPHLAN and RUN_KRAKEN are false. Nothing to run."
    exit 1
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo "  MetaPhlAn4 : $RUN_METAPHLAN"
echo "  SameStr    : $RUN_SAMESTR"
echo "  Kraken2    : $RUN_KRAKEN"
echo ""

# ── Output and log directories ────────────────────────────────────────────────
[[ ! -d "$OUT_DIR" ]] && mkdir -p "$OUT_DIR"
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# ── Submit per-sample array job ───────────────────────────────────────────────
echo "Submitting per-sample taxonomic profiling for $NUM_JOBS samples..."
JOB=$(sbatch \
    --job-name=02a_taxonomic \
    --partition="$PARTITION_TAX" \
    --time="$TIME_TAX" \
    --cpus-per-task="$CPUS_TAX" \
    --mem-per-cpu="$MEM_PER_CPU_TAX" \
    --output="$LOG_DIR/%x_%A_%a.out" \
    --error="$LOG_DIR/%x_%A_%a.err" \
    --array=1-${NUM_JOBS} \
    modules/02a_taxonomic_profiling.sh)
echo "$JOB"
JOB_ID=$(echo "$JOB" | awk '{print $NF}')

# ── Submit MetaPhlAn merge job ────────────────────────────────────────────────
if [[ "$RUN_METAPHLAN" == true ]]; then
    echo ""
    echo "Submitting MetaPhlAn merge job (depends on 02a: $JOB_ID)..."
    JOB_MERGE=$(sbatch \
        --job-name=02c_metaphlan_merge \
        --partition="$PARTITION_QC_MERGE" \
        --time="$TIME_QC_MERGE" \
        --cpus-per-task=1 \
        --mem-per-cpu="8G" \
        --output="$LOG_DIR/%x_%A_%a.out" \
        --error="$LOG_DIR/%x_%A_%a.err" \
        --dependency=afterok:${JOB_ID} \
        modules/02c_metaphlan_merge.sh)
    echo "$JOB_MERGE"
fi


# ── Submit SameStr population job if needed ───────────────────────────────────
if [[ "$RUN_SAMESTR" == true ]]; then
    echo ""
    echo "Submitting SameStr population job (depends on 02a: $JOB_ID)..."
    JOB_POP=$(sbatch \
        --job-name=02b_samestr_pop \
        --partition="$PARTITION_SAMESTR" \
        --time="$TIME_SAMESTR" \
        --cpus-per-task="$CPUS_TAX" \
        --mem-per-cpu="$MEM_PER_CPU_TAX" \
        --output="$LOG_DIR/%x_%A_%a.out" \
        --error="$LOG_DIR/%x_%A_%a.err" \
        --dependency=afterok:${JOB_ID} \
        modules/02b_samestr_population.sh)
    echo "$JOB_POP"
fi

echo ""
echo "When complete, run: bash 02.check_taxonomic.sh"
