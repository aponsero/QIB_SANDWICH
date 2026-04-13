#!/bin/bash -l
source config.sh

echo "=== Taxonomic Profiling Check ==="
echo ""
echo "  MetaPhlAn4 : $RUN_METAPHLAN"
echo "  SameStr    : $RUN_SAMESTR"
echo "  Kraken2    : $RUN_KRAKEN"
echo ""

PASS=0
FAIL=0
MISSING=0
EMPTY=0

# ── Per-sample checks ─────────────────────────────────────────────────────────
while IFS=$'\t' read -r SAMPLE_ID READ1 READ2; do
    [[ "$SAMPLE_ID" == "sample_id" ]] && continue  # skip header

    SAMPLE_FAIL=false

    # ── MetaPhlAn4 ────────────────────────────────────────────────────────────
    if [[ "$RUN_METAPHLAN" == true ]]; then
        for FILE in \
            "$OUT_DIR/02_taxonomic_profiling/metaphlan/${SAMPLE_ID}.profile.txt" \
            "$OUT_DIR/02_taxonomic_profiling/metaphlan/${SAMPLE_ID}.unclprofile.txt"; do
            if [[ ! -f "$FILE" ]]; then
                echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
                ((MISSING++)); SAMPLE_FAIL=true
            elif [[ ! -s "$FILE" ]]; then
                echo "EMPTY   : $SAMPLE_ID -- $(basename $FILE)"
                ((EMPTY++)); SAMPLE_FAIL=true
            fi
        done
    fi

    # ── SameStr convert ───────────────────────────────────────────────────────
    if [[ "$RUN_SAMESTR" == true ]]; then
        CONVERT_COUNT=$(find "$OUT_DIR/02_taxonomic_profiling/samestr/convert/${SAMPLE_ID}" \
            -name "*.npz" 2>/dev/null | wc -l)
        if [[ "$CONVERT_COUNT" -eq 0 ]]; then
            echo "MISSING : $SAMPLE_ID -- no SameStr convert .npz files found"
            ((MISSING++)); SAMPLE_FAIL=true
        else
            echo "OK      : $SAMPLE_ID -- $CONVERT_COUNT SameStr .npz files found"
        fi
    fi

    # ── Kraken2 ───────────────────────────────────────────────────────────────
    if [[ "$RUN_KRAKEN" == true ]]; then
        FILE="$OUT_DIR/02_taxonomic_profiling/kraken2/${SAMPLE_ID}_kraken_report.txt"
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        elif [[ ! -s "$FILE" ]]; then
            echo "EMPTY   : $SAMPLE_ID -- $(basename $FILE)"
            ((EMPTY++)); SAMPLE_FAIL=true
        fi
    fi

    if [[ "$SAMPLE_FAIL" == false ]]; then
        ((PASS++))
    else
        ((FAIL++))
    fi

done < "$SAMPLE_SHEET"

# ── SameStr population outputs (not per-sample) ───────────────────────────────
SAMESTR_FAIL=false
if [[ "$RUN_SAMESTR" == true ]]; then
    echo ""
    echo "=== SameStr Population Steps ==="
    for DIR in merge filter compare summarize; do
        FILE_COUNT=$(find "$OUT_DIR/02_taxonomic_profiling/samestr/${DIR}" \
            -type f 2>/dev/null | wc -l)
        if [[ "$FILE_COUNT" -eq 0 ]]; then
            echo "MISSING : samestr/${DIR} -- no output files found"
            SAMESTR_FAIL=true
        else
            echo "OK      : samestr/${DIR} -- $FILE_COUNT files found"
        fi
    done
fi

# ── MetaPhlAn merged output (not per-sample) ─────────────────────────────────
METAPHLAN_MERGE_FAIL=false
if [[ "$RUN_METAPHLAN" == true ]]; then
    echo ""
    echo "=== MetaPhlAn Merged Output ==="
    MERGED_FILE="$OUT_DIR/04_aggregated/02_taxonomic_profiling/metaphlan_merged.tsv"
    if [[ ! -f "$MERGED_FILE" ]]; then
        echo "MISSING : metaphlan_merged.tsv -- check if 02c job completed"
        METAPHLAN_MERGE_FAIL=true
    elif [[ ! -s "$MERGED_FILE" ]]; then
        echo "EMPTY   : metaphlan_merged.tsv"
        METAPHLAN_MERGE_FAIL=true
    else
        # Count sample columns: header line, skip first column (clade name)
        SAMPLE_COUNT=$(head -1 "$MERGED_FILE" | tr '\t' '\n' | grep -v "^#\?clade\|^NCBI" | wc -l)
        echo "OK      : metaphlan_merged.tsv -- $SAMPLE_COUNT samples found"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL ))
echo ""
echo "=== Summary ==="
echo "  Total samples : $TOTAL"
echo "  Passed        : $PASS"
echo "  Failed        : $FAIL"
echo "  (missing files: $MISSING | empty files: $EMPTY)"

if [[ "$RUN_SAMESTR" == true ]]; then
    if [[ "$SAMESTR_FAIL" == true ]]; then
        echo "  SameStr population steps  : INCOMPLETE"
    else
        echo "  SameStr population steps  : OK"
    fi
fi

if [[ "$RUN_METAPHLAN" == true ]]; then
    if [[ "$METAPHLAN_MERGE_FAIL" == true ]]; then
        echo "  MetaPhlAn merged output   : INCOMPLETE"
    else
        echo "  MetaPhlAn merged output   : OK"
    fi
fi

echo ""
if [[ "$FAIL" -gt 0 || "$SAMESTR_FAIL" == true || "$METAPHLAN_MERGE_FAIL" == true ]]; then
    echo "WARNING: Some outputs are missing. Check logs in $LOG_DIR before proceeding."
    echo "Note: If merge outputs are missing, check if 02b or 02c jobs are still running."
    echo "When issues are resolved, run: bash 03.run_functional.sh"
else
    echo "All checks passed. You can now run: bash 03.run_functional.sh"
fi
