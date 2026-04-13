#!/bin/bash -l
source config.sh

echo "=== QC Check ==="
echo ""
echo "  Sequencing type  : $TYPE"
echo "  Remove human     : $REMOVE_HUMAN"
echo "  Food host        : $FOOD_HOST_REF"
echo ""

PASS=0
FAIL=0
MISSING=0
EMPTY=0

# ── Per-sample checks ─────────────────────────────────────────────────────────
while IFS=$'\t' read -r SAMPLE_ID READ1 READ2 SAMPLE_FOOD_HOST; do
    [[ "$SAMPLE_ID" == "sample_id" ]] && continue

    # Strip carriage returns (Windows Excel TSV safety)
    SAMPLE_ID=$(echo "$SAMPLE_ID" | tr -d '\r')

    SAMPLE_FAIL=false

    # ── Cleaned reads ─────────────────────────────────────────────────────────
    for FILE in \
        "$OUT_DIR/01_qc/trimming/${SAMPLE_ID}_clean_R1.fq.gz" \
        "$OUT_DIR/01_qc/trimming/${SAMPLE_ID}_clean_R2.fq.gz"; do
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        elif [[ ! -s "$FILE" ]]; then
            echo "EMPTY   : $SAMPLE_ID -- $(basename $FILE)"
            ((EMPTY++)); SAMPLE_FAIL=true
        fi
    done

    # ── FastQC outputs ────────────────────────────────────────────────────────
    for FILE in \
        "$OUT_DIR/01_qc/fastqc/${SAMPLE_ID}_R1_fastqc.zip" \
        "$OUT_DIR/01_qc/fastqc/${SAMPLE_ID}_R2_fastqc.zip"; do
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        fi
    done

    # ── Host removal logs ─────────────────────────────────────────────────────
    # Both JSON files are always written by 01a (skipped steps write placeholder)
    for FILE in \
        "$OUT_DIR/01_qc/host_removal/${SAMPLE_ID}_human_hostmap.json" \
        "$OUT_DIR/01_qc/host_removal/${SAMPLE_ID}_food_hostmap.json"; do
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        fi
    done

    if [[ "$SAMPLE_FAIL" == false ]]; then
        echo "OK      : $SAMPLE_ID"
        ((PASS++))
    else
        ((FAIL++))
    fi

done < "$SAMPLE_SHEET"

# ── Aggregated outputs (not per-sample) ───────────────────────────────────────
AGG_FAIL=false
echo ""
echo "=== Aggregated Outputs ==="

# hostile_summary.csv
FILE="$OUT_DIR/04_aggregated/01_qc/hostile_summary.csv"
if [[ ! -f "$FILE" ]]; then
    echo "MISSING : hostile_summary.csv -- check if 01b job completed"
    AGG_FAIL=true
elif [[ ! -s "$FILE" ]]; then
    echo "EMPTY   : hostile_summary.csv"
    AGG_FAIL=true
else
    N_LINES=$(tail -n +2 "$FILE" | wc -l)
    echo "OK      : hostile_summary.csv -- $N_LINES samples found"
fi

# MultiQC report
FILE="$OUT_DIR/04_aggregated/01_qc/multiqc/multiqc_report.html"
if [[ ! -f "$FILE" ]]; then
    echo "MISSING : multiqc_report.html -- check if 01b job completed"
    AGG_FAIL=true
else
    echo "OK      : multiqc_report.html"
fi

# metadata.tsv reminder
META="$OUT_DIR/04_aggregated/metadata.tsv"
if [[ ! -f "$META" ]]; then
    echo "MISSING : metadata.tsv -- please add before rendering the Rmarkdown report"
    echo "          Expected location: $META"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL ))
echo ""
echo "=== Summary ==="
echo "  Total samples    : $TOTAL"
echo "  Passed           : $PASS"
echo "  Failed           : $FAIL"
echo "  (missing files   : $MISSING | empty files: $EMPTY)"
echo "  Aggregated QC    : $(if [[ "$AGG_FAIL" == false ]]; then echo OK; else echo INCOMPLETE; fi)"
echo ""

if [[ "$FAIL" -gt 0 || "$AGG_FAIL" == true ]]; then
    echo "WARNING: Some outputs are missing. Check logs in $LOG_DIR before proceeding."
    echo "Note: If aggregated outputs are missing, check if 01b job is still running."
    echo "When issues are resolved, run: bash 02.run_taxonomic.sh"
else
    echo "All checks passed. You can now run: bash 02.run_taxonomic.sh"
fi
