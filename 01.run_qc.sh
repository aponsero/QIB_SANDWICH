#!/bin/bash -l
source config.sh

echo "=== QC + Host Removal ==="
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

# ── Sequencing type ───────────────────────────────────────────────────────────
if [[ -z "$TYPE" ]]; then
    echo "ERROR: TYPE is not set in config.sh"
    exit 1
fi
TYPE_LOWER=$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')
if [[ "$TYPE_LOWER" != "illumina" && "$TYPE_LOWER" != "mgi" ]]; then
    echo "ERROR: TYPE must be 'illumina' or 'mgi'. Current value: $TYPE"
    exit 1
fi
echo "Sequencing type: $TYPE"

# ── Host reference ────────────────────────────────────────────────────────────
if [[ -z "$REMOVE_HUMAN" ]]; then
    echo "ERROR: REMOVE_HUMAN is not set in config.sh"
    exit 1
fi

# ── Output and log directories ────────────────────────────────────────────────
[[ ! -d "$OUT_DIR" ]] && mkdir -p "$OUT_DIR"
[[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

# ── Submit per-sample array job ───────────────────────────────────────────────
echo ""
echo "Submitting QC + host removal for $NUM_JOBS samples..."
JOB=$(sbatch \
    --job-name=01a_qc_host \
    --partition="$PARTITION_QC" \
    --time="$TIME_QC" \
    --cpus-per-task="$CPUS_QC" \
    --mem-per-cpu="$MEM_PER_CPU_QC" \
    --output="$LOG_DIR/%x_%A_%a.out" \
    --error="$LOG_DIR/%x_%A_%a.err" \
    --array=1-${NUM_JOBS} \
    modules/01a_qc_host_removal.sh)
echo "$JOB"
JOB_ID=$(echo "$JOB" | awk '{print $NF}')

# ── Submit merge job ──────────────────────────────────────────────────────────
echo ""
echo "Submitting QC merge + aggregation (depends on 01a: $JOB_ID)..."
JOB_MERGE=$(sbatch \
    --job-name=01b_qc_merge \
    --partition="$PARTITION_QC_MERGE" \
    --time="$TIME_QC_MERGE" \
    --cpus-per-task=2 \
    --mem-per-cpu="4G" \
    --output="$LOG_DIR/%x_%A_%a.out" \
    --error="$LOG_DIR/%x_%A_%a.err" \
    --dependency=afterok:${JOB_ID} \
    modules/01b_qc_merge.sh)
echo "$JOB_MERGE"

echo ""
echo "When complete, run: bash 01.check_qc.sh"
