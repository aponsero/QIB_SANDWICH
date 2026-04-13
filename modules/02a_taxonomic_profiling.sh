#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh

source package $PKG_METAPHLAN
source package $PKG_KRAKEN2
source package $PKG_SAMESTR

echo "Job started"; hostname; date

# ── Parse sample sheet ────────────────────────────────────────────────────────
LINE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" $SAMPLE_SHEET)
SAMPLE_ID=$(echo "$LINE" | awk '{print $1}')

echo "Processing sample: $SAMPLE_ID"

# ── Input reads from module 01 ────────────────────────────────────────────────
READ1="$OUT_DIR/01_qc/trimming/${SAMPLE_ID}_clean_R1.fq.gz"
READ2="$OUT_DIR/01_qc/trimming/${SAMPLE_ID}_clean_R2.fq.gz"

if [[ ! -f "$READ1" || ! -f "$READ2" ]]; then
    echo "ERROR: Clean reads not found for $SAMPLE_ID. Has 01_qc completed successfully?"
    exit 1
fi

# ── Output directories ────────────────────────────────────────────────────────
MET_DIR="$OUT_DIR/02_taxonomic_profiling/metaphlan"
KRA_DIR="$OUT_DIR/02_taxonomic_profiling/kraken2"
CONVERT_DIR="$OUT_DIR/02_taxonomic_profiling/samestr/convert"

[[ "$RUN_METAPHLAN" == true && ! -d "$MET_DIR" ]]  && mkdir -p "$MET_DIR"
[[ "$RUN_SAMESTR" == true && ! -d "$CONVERT_DIR" ]] && mkdir -p "$CONVERT_DIR"
[[ "$RUN_KRAKEN" == true && ! -d "$KRA_DIR" ]]      && mkdir -p "$KRA_DIR"

# ── MetaPhlAn4 ────────────────────────────────────────────────────────────────
if [[ "$RUN_METAPHLAN" == true ]]; then
    echo "Running MetaPhlAn4 for $SAMPLE_ID"
    metaphlan $READ1,$READ2 \
        -o $MET_DIR/${SAMPLE_ID}.profile.txt \
        -x mpa_vJun23_CHOCOPhlAnSGB_202403 \
        --bowtie2db $MET_DB \
        --input_type fastq \
        --nproc $CPUS_TAX \
        -t rel_ab \
        --bowtie2out $MET_DIR/${SAMPLE_ID}.bowtie2out \
        --samout $MET_DIR/${SAMPLE_ID}.sam.bz2

    echo "Running MetaPhlAn4 with unclassified estimation for $SAMPLE_ID"
    metaphlan $MET_DIR/${SAMPLE_ID}.bowtie2out \
        --nproc $CPUS_TAX \
        --unclassified_estimation \
        --input_type bowtie2out \
        -o $MET_DIR/${SAMPLE_ID}.unclprofile.txt \
        -x mpa_vJun23_CHOCOPhlAnSGB_202403 \
        --bowtie2db $MET_DB

    # ── SameStr convert ───────────────────────────────────────────────────────
    if [[ "$RUN_SAMESTR" == true ]]; then
        echo "Running SameStr convert for $SAMPLE_ID"
        samestr convert \
            --input-files $MET_DIR/${SAMPLE_ID}.sam.bz2 \
            --marker-dir $SAMEST_DB \
            --nprocs $CPUS_TAX \
            --min-vcov 5 \
            --output-dir $CONVERT_DIR
    fi
fi

# ── Kraken2 ───────────────────────────────────────────────────────────────────
if [[ "$RUN_KRAKEN" == true ]]; then
    echo "Running Kraken2 for $SAMPLE_ID"
    kraken2 \
        --threads $CPUS_TAX \
        --paired \
        --db $KRAKENDB_DIR \
        --report $KRA_DIR/${SAMPLE_ID}_kraken_report.txt \
        $READ1 $READ2 \
        > /dev/null
fi

echo "Job done"; date
