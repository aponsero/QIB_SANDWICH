#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh

# ── Load environments ─────────────────────────────────────────────────────────
source package $PKG_HOSTILE
source package $PKG_TRIMGALORE

export HOSTILE_CACHE_DIR=$HOSTILE_CACHE_DIR

echo "Job started"; hostname; date

# ── Parse sample sheet ────────────────────────────────────────────────────────
LINE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" $SAMPLE_SHEET | tr -d '\r')
SAMPLE_ID=$(echo "$LINE" | awk '{print $1}')
READ1=$(echo "$LINE"     | awk '{print $2}')
READ2=$(echo "$LINE"     | awk '{print $3}')
SAMPLE_FOOD_HOST=$(echo "$LINE" | awk '{print $4}' | tr -d '\r')

# ── Resolve effective food host ───────────────────────────────────────────────
# Priority: sample sheet column > config FOOD_HOST_REF > "none"
# Column 4 is optional — empty or absent falls back to config value
if [[ -n "$SAMPLE_FOOD_HOST" ]]; then
    EFFECTIVE_FOOD_HOST="$SAMPLE_FOOD_HOST"
    echo "Food host source: sample sheet ($EFFECTIVE_FOOD_HOST)"
else
    EFFECTIVE_FOOD_HOST="$FOOD_HOST_REF"
    echo "Food host source: config default ($EFFECTIVE_FOOD_HOST)"
fi

echo "Processing sample: $SAMPLE_ID"
echo "  REMOVE_HUMAN       : $REMOVE_HUMAN"
echo "  EFFECTIVE_FOOD_HOST: $EFFECTIVE_FOOD_HOST"

# ── Sanity check ──────────────────────────────────────────────────────────────
if [[ "$REMOVE_HUMAN" != true && "$EFFECTIVE_FOOD_HOST" == "none" ]]; then
    echo "WARNING: Both REMOVE_HUMAN=false and effective food host=none."
    echo "No host removal will be performed. Reads will proceed directly to trimming."
fi

# ── Output directories ────────────────────────────────────────────────────────
QC_DIR="$OUT_DIR/01_qc"
HOST_DIR="$QC_DIR/host_removal"
TRIM_DIR="$QC_DIR/trimming"
FASTQC_DIR="$QC_DIR/fastqc"

[[ ! -d "$HOST_DIR" ]]   && mkdir -p "$HOST_DIR"
[[ ! -d "$TRIM_DIR" ]]   && mkdir -p "$TRIM_DIR"
[[ ! -d "$FASTQC_DIR" ]] && mkdir -p "$FASTQC_DIR"
[[ ! -d "$LOG_DIR" ]]    && mkdir -p "$LOG_DIR"

# ── Food host index selection ─────────────────────────────────────────────────
if [[ "$EFFECTIVE_FOOD_HOST" != "none" ]]; then
    case "$EFFECTIVE_FOOD_HOST" in
        cow)     FOOD_INDEX="cow-argos985" ;;
        salmon)  FOOD_INDEX="salmon-argos985" ;;
        soybean) FOOD_INDEX="soybean-argos985" ;;
        pig)     FOOD_INDEX="pig-argos985" ;;
        spinach) FOOD_INDEX="spinach-argos985" ;;
        *)
            echo "ERROR: Unknown food host '$EFFECTIVE_FOOD_HOST' for sample $SAMPLE_ID."
            echo "Choose: cow, salmon, soybean, pig, spinach, or none"
            exit 1
            ;;
    esac
fi

# ── Step 1: Human host removal ────────────────────────────────────────────────
# Outputs intermediate files if food host removal follows, otherwise final files
if [[ "$REMOVE_HUMAN" == true ]]; then
    echo "--- Step 1: Human host removal ---"

    HUMAN_LOG="$HOST_DIR/${SAMPLE_ID}_human_hostmap.json"

    # If food host removal will follow, write to intermediate files
    # Otherwise write directly to final hostremoved files
    if [[ "$EFFECTIVE_FOOD_HOST" != "none" ]]; then
        HUMAN_OUT_DIR="$HOST_DIR/tmp_human_${SAMPLE_ID}"
        mkdir -p "$HUMAN_OUT_DIR"
    else
        HUMAN_OUT_DIR="$HOST_DIR"
    fi

    hostile clean \
        --fastq1 "$READ1" \
        --fastq2 "$READ2" \
        --index "human-t2t-hla" \
        --output "$HUMAN_OUT_DIR" \
        --airplane \
        > "$HUMAN_LOG"

    # Hostile output naming: {basename}.clean_1.fastq.gz
    BASE1=$(basename "$READ1" .fastq.gz)
    BASE2=$(basename "$READ2" .fastq.gz)

    if [[ "$EFFECTIVE_FOOD_HOST" != "none" ]]; then
        # Rename to intermediate files
        INTER_R1="$HUMAN_OUT_DIR/${SAMPLE_ID}_human_removed_R1.fastq.gz"
        INTER_R2="$HUMAN_OUT_DIR/${SAMPLE_ID}_human_removed_R2.fastq.gz"
        mv "$HUMAN_OUT_DIR/${BASE1}.clean_1.fastq.gz" "$INTER_R1"
        mv "$HUMAN_OUT_DIR/${BASE2}.clean_2.fastq.gz" "$INTER_R2"
        echo "Human removal complete. Intermediate reads: $INTER_R1"
    else
        # Rename directly to final hostremoved files
        HOSTILE_R1="$HOST_DIR/${SAMPLE_ID}_hostremoved_R1.fastq.gz"
        HOSTILE_R2="$HOST_DIR/${SAMPLE_ID}_hostremoved_R2.fastq.gz"
        mv "$HUMAN_OUT_DIR/${BASE1}.clean_1.fastq.gz" "$HOSTILE_R1"
        mv "$HUMAN_OUT_DIR/${BASE2}.clean_2.fastq.gz" "$HOSTILE_R2"
        echo "Human removal complete (only step). Final reads: $HOSTILE_R1"
    fi
else
    echo "--- Step 1: Human host removal skipped (REMOVE_HUMAN=false) ---"
    # Write a zero-count placeholder JSON so 01b parser does not fail
    echo '[{"reads_in":0,"reads_out":0,"reads_removed":0,"reads_removed_proportion":0.0,"aligner":"none","index":"none"}]' \
        > "$HOST_DIR/${SAMPLE_ID}_human_hostmap.json"
fi

# ── Step 2: Food host removal ─────────────────────────────────────────────────
if [[ "$EFFECTIVE_FOOD_HOST" != "none" ]]; then
    echo "--- Step 2: Food host removal ($EFFECTIVE_FOOD_HOST) ---"

    FOOD_LOG="$HOST_DIR/${SAMPLE_ID}_food_hostmap.json"

    # Input is intermediate files if human step ran, otherwise raw reads
    if [[ "$REMOVE_HUMAN" == true ]]; then
        FOOD_IN_R1="$INTER_R1"
        FOOD_IN_R2="$INTER_R2"
    else
        FOOD_IN_R1="$READ1"
        FOOD_IN_R2="$READ2"
    fi

    FOOD_OUT_DIR="$HOST_DIR/tmp_food_${SAMPLE_ID}"
    mkdir -p "$FOOD_OUT_DIR"

    hostile clean \
        --fastq1 "$FOOD_IN_R1" \
        --fastq2 "$FOOD_IN_R2" \
        --index "$FOOD_INDEX" \
        --output "$FOOD_OUT_DIR" \
        --airplane \
        > "$FOOD_LOG"

    BASE_F1=$(basename "$FOOD_IN_R1" .fastq.gz)
    BASE_F2=$(basename "$FOOD_IN_R2" .fastq.gz)

    HOSTILE_R1="$HOST_DIR/${SAMPLE_ID}_hostremoved_R1.fastq.gz"
    HOSTILE_R2="$HOST_DIR/${SAMPLE_ID}_hostremoved_R2.fastq.gz"

    mv "$FOOD_OUT_DIR/${BASE_F1}.clean_1.fastq.gz" "$HOSTILE_R1"
    mv "$FOOD_OUT_DIR/${BASE_F2}.clean_2.fastq.gz" "$HOSTILE_R2"

    # Clean up intermediate files and tmp dirs
    [[ "$REMOVE_HUMAN" == true ]] && rm -f "$INTER_R1" "$INTER_R2"
    rm -rf "$FOOD_OUT_DIR"
    [[ "$REMOVE_HUMAN" == true ]] && rm -rf "$HUMAN_OUT_DIR"

    echo "Food host removal complete. Final reads: $HOSTILE_R1"
else
    echo "--- Step 2: Food host removal skipped (effective host=none) ---"
    # Write a zero-count placeholder JSON so 01b parser does not fail
    echo '[{"reads_in":0,"reads_out":0,"reads_removed":0,"reads_removed_proportion":0.0,"aligner":"none","index":"none"}]' \
        > "$HOST_DIR/${SAMPLE_ID}_food_hostmap.json"
fi

# ── At this point HOSTILE_R1/R2 are set regardless of which steps ran ─────────
# If neither step ran, point directly to raw reads for trimming
if [[ "$REMOVE_HUMAN" != true && "$EFFECTIVE_FOOD_HOST" == "none" ]]; then
    HOSTILE_R1="$READ1"
    HOSTILE_R2="$READ2"
fi

# ── Trimming + FastQC with TrimGalore ─────────────────────────────────────────
TMPDIR="$TRIM_DIR/tmp"
mkdir -p "$TMPDIR"
export TMPDIR

TYPE_LOWER=$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')

echo "Running TrimGalore ($TYPE_LOWER)"

if [[ "$TYPE_LOWER" == "mgi" ]]; then
    trim_galore --paired \
        -o "$TRIM_DIR" \
        -a GCTCACAGAACGACATGGCTACGATCCGACTT \
        -a2 TTGTCTTCCTAAGACCGCTTGGCCTCCGACTT \
        --fastqc --fastqc_args "-d $TMPDIR" \
        "$HOSTILE_R1" "$HOSTILE_R2"

elif [[ "$TYPE_LOWER" == "illumina" ]]; then
    trim_galore --paired \
        -o "$TRIM_DIR" \
        --fastqc --fastqc_args "-d $TMPDIR" \
        "$HOSTILE_R1" "$HOSTILE_R2"

else
    echo "ERROR: Unknown TYPE '$TYPE'. Choose: illumina or mgi"
    exit 1
fi

# ── Organise outputs ──────────────────────────────────────────────────────────
BASE_HR1=$(basename "$HOSTILE_R1" .fastq.gz)
BASE_HR2=$(basename "$HOSTILE_R2" .fastq.gz)

CLEAN_R1="$TRIM_DIR/${SAMPLE_ID}_clean_R1.fq.gz"
CLEAN_R2="$TRIM_DIR/${SAMPLE_ID}_clean_R2.fq.gz"

mv "$TRIM_DIR/${BASE_HR1}_val_1.fq.gz" "$CLEAN_R1"
mv "$TRIM_DIR/${BASE_HR2}_val_2.fq.gz" "$CLEAN_R2"

# FastQC reports
mv "$TRIM_DIR/${BASE_HR1}_val_1_fastqc.html" "$FASTQC_DIR/${SAMPLE_ID}_R1_fastqc.html" 2>/dev/null
mv "$TRIM_DIR/${BASE_HR2}_val_2_fastqc.html" "$FASTQC_DIR/${SAMPLE_ID}_R2_fastqc.html" 2>/dev/null
mv "$TRIM_DIR/${BASE_HR1}_val_1_fastqc.zip"  "$FASTQC_DIR/${SAMPLE_ID}_R1_fastqc.zip"  2>/dev/null
mv "$TRIM_DIR/${BASE_HR2}_val_2_fastqc.zip"  "$FASTQC_DIR/${SAMPLE_ID}_R2_fastqc.zip"  2>/dev/null

# Trimming reports
mv "$TRIM_DIR/${BASE_HR1}_val_1_trimming_report.txt" "$FASTQC_DIR/${SAMPLE_ID}_R1_trimming_report.txt" 2>/dev/null
mv "$TRIM_DIR/${BASE_HR2}_val_2_trimming_report.txt" "$FASTQC_DIR/${SAMPLE_ID}_R2_trimming_report.txt" 2>/dev/null

# Clean up final hostile outputs and tmp
[[ "$REMOVE_HUMAN" == true || "$EFFECTIVE_FOOD_HOST" != "none" ]] && rm -f "$HOSTILE_R1" "$HOSTILE_R2"
rm -rf "$TMPDIR"

echo "Clean reads: $CLEAN_R1 / $CLEAN_R2"
echo "Job done"; date
