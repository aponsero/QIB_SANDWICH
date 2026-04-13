#!/bin/bash -l
source config.sh

echo "=== Functional Annotation ==="
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

# ── Check at least one module is enabled ─────────────────────────────────────
if [[ "$RUN_HUMANN" != true && "$RUN_ARG" != true && "$RUN_VIRULENCE" != true ]]; then
    echo "ERROR: All functional modules are disabled. Nothing to run."
    exit 1
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo "  HUMAnN3   : $RUN_HUMANN"
echo "  ARG       : $RUN_ARG"
echo "  Virulence : $RUN_VIRULENCE"
echo ""

# ── Output and log directories ────────────────────────────────────────────────
[[ ! -d "$OUT_DIR" ]] && mkdir -p "$OUT_DIR"
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# ── Submit per-sample array job ───────────────────────────────────────────────
echo "Submitting per-sample functional annotation for $NUM_JOBS samples..."
JOB=$(sbatch \
    --job-name=03a_functional \
    --partition="$PARTITION_FUNC" \
    --time="$TIME_FUNC" \
    --cpus-per-task="$CPUS_FUNC" \
    --mem-per-cpu="$MEM_PER_CPU_FUNC" \
    --output="$LOG_DIR/%x_%A_%a.out" \
    --error="$LOG_DIR/%x_%A_%a.err" \
    --array=1-${NUM_JOBS} \
    modules/03a_functional_annotation.sh)
echo "$JOB"
JOB_ID=$(echo "$JOB" | awk '{print $NF}')

# ── Submit merge job ──────────────────────────────────────────────────────────
echo ""
echo "Submitting functional merge job (depends on 03a: $JOB_ID)..."
JOB_MERGE=$(sbatch \
    --job-name=03b_functional_merge \
    --partition="$PARTITION_FUNC_MERGE" \
    --time="$TIME_FUNC_MERGE" \
    --cpus-per-task=1 \
    --mem-per-cpu="8G" \
    --output="$LOG_DIR/%x_%A_%a.out" \
    --error="$LOG_DIR/%x_%A_%a.err" \
    --dependency=afterok:${JOB_ID} \
    modules/03b_functional_merge.sh)
echo "$JOB_MERGE"

echo ""
echo "When complete, run: bash 03.check_functional.sh"
