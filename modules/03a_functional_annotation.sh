#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh

source package $PKG_HUMANN
source package $PKG_DIAMOND

echo "Job started"; hostname; date

# ── Parse sample sheet ────────────────────────────────────────────────────────
LINE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" $SAMPLE_SHEET)
SAMPLE_ID=$(echo "$LINE" | awk '{print $1}')

echo "Processing sample: $SAMPLE_ID"

# ── Input reads from module 01 (R1 only) ──────────────────────────────────────
READ1="$OUT_DIR/01_qc/trimming/${SAMPLE_ID}_clean_R1.fq.gz"

if [[ ! -f "$READ1" ]]; then
    echo "ERROR: Clean R1 not found for $SAMPLE_ID. Has 01_qc completed successfully?"
    exit 1
fi

# ── Output directories ────────────────────────────────────────────────────────
HUMANN_DIR="$OUT_DIR/03_functional_annotation/humann3"
DIAMOND_DIR="$OUT_DIR/03_functional_annotation/diamond"

[[ "$RUN_HUMANN" == true && ! -d "$HUMANN_DIR" ]]  && mkdir -p "$HUMANN_DIR"
[[ ( "$RUN_ARG" == true || "$RUN_VIRULENCE" == true ) && ! -d "$DIAMOND_DIR" ]] && mkdir -p "$DIAMOND_DIR"

# ── HUMAnN3 ───────────────────────────────────────────────────────────────────
if [[ "$RUN_HUMANN" == true ]]; then
    echo "Running HUMAnN3 for $SAMPLE_ID"
    HUMANN_SAMPLE_DIR="$HUMANN_DIR/${SAMPLE_ID}"
    [[ ! -d "$HUMANN_SAMPLE_DIR" ]] && mkdir -p "$HUMANN_SAMPLE_DIR"

    humann \
        --threads $CPUS_FUNC \
        --input $READ1 \
        --nucleotide-database $HUMANN_NUC \
        --protein-database $HUMANN_PROT \
        --metaphlan-options "--offline --bowtie2db $HUMANN_MPA" \
        --output $HUMANN_SAMPLE_DIR

    # Move TSV outputs to shared humann3 folder and clean up
    mv $HUMANN_SAMPLE_DIR/*.tsv $HUMANN_DIR/
    rm -rf $HUMANN_SAMPLE_DIR
    echo "HUMAnN3 complete for $SAMPLE_ID"
fi

# ── Diamond CARD (ARG) ────────────────────────────────────────────────────────
if [[ "$RUN_ARG" == true ]]; then
    echo "Running Diamond against CARD for $SAMPLE_ID"
    diamond blastx \
        --db $CARD_DB \
        --query $READ1 \
        --out $DIAMOND_DIR/${SAMPLE_ID}_card.tsv \
        --outfmt 6 qseqid sseqid pident length qlen slen evalue bitscore qcovhsp \
        --evalue $DIAMOND_EVALUE \
        --id $DIAMOND_IDENTITY \
        --query-cover $DIAMOND_QCOV \
        --threads $CPUS_FUNC \
        --max-target-seqs 1 \
        --sensitive
    echo "Diamond CARD complete for $SAMPLE_ID"
fi

# ── Diamond VFDB (virulence factors) ─────────────────────────────────────────
if [[ "$RUN_VIRULENCE" == true ]]; then
    echo "Running Diamond against VFDB for $SAMPLE_ID"
    diamond blastx \
        --db $VFDB_DB \
        --query $READ1 \
        --out $DIAMOND_DIR/${SAMPLE_ID}_vfdb.tsv \
        --outfmt 6 qseqid sseqid pident length qlen slen evalue bitscore qcovhsp \
        --evalue $DIAMOND_EVALUE \
        --id $DIAMOND_IDENTITY \
        --query-cover $DIAMOND_QCOV \
        --threads $CPUS_FUNC \
        --max-target-seqs 1 \
        --sensitive
    echo "Diamond VFDB complete for $SAMPLE_ID"
fi

# ── Read count for Diamond normalisation ──────────────────────────────────────
if [[ "$RUN_ARG" == true || "$RUN_VIRULENCE" == true ]]; then
    TOTAL_READS=$(zcat $READ1 | awk 'NR % 4 == 2' | wc -l)
    echo "${SAMPLE_ID},${TOTAL_READS}" > $DIAMOND_DIR/${SAMPLE_ID}_readcounts.txt
    echo "Total reads for $SAMPLE_ID: $TOTAL_READS"
fi

echo "Job done"; date
