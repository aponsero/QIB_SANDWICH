#!/bin/bash -l
source config.sh

echo "=== Functional Annotation Check ==="
echo ""
echo "  HUMAnN3   : $RUN_HUMANN"
echo "  ARG       : $RUN_ARG"
echo "  Virulence : $RUN_VIRULENCE"
echo ""

PASS=0
FAIL=0
MISSING=0
EMPTY=0

HUMANN_DIR="$OUT_DIR/03_functional_annotation/humann3"
DIAMOND_DIR="$OUT_DIR/03_functional_annotation/diamond"

# ── Per-sample checks ─────────────────────────────────────────────────────────
while IFS=$'\t' read -r SAMPLE_ID READ1 READ2; do
    [[ "$SAMPLE_ID" == "sample_id" ]] && continue  # skip header

    SAMPLE_FAIL=false

    # ── HUMAnN3 ───────────────────────────────────────────────────────────────
    if [[ "$RUN_HUMANN" == true ]]; then
        for FILE in \
            "$HUMANN_DIR/${SAMPLE_ID}_pathabundance.tsv" \
            "$HUMANN_DIR/${SAMPLE_ID}_pathcoverage.tsv" \
            "$HUMANN_DIR/${SAMPLE_ID}_genefamilies.tsv"; do
            if [[ ! -f "$FILE" ]]; then
                echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
                ((MISSING++)); SAMPLE_FAIL=true
            elif [[ ! -s "$FILE" ]]; then
                echo "EMPTY   : $SAMPLE_ID -- $(basename $FILE)"
                ((EMPTY++)); SAMPLE_FAIL=true
            fi
        done
    fi

    # ── Diamond CARD (ARG) ────────────────────────────────────────────────────
    if [[ "$RUN_ARG" == true ]]; then
        FILE="$DIAMOND_DIR/${SAMPLE_ID}_card.tsv"
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        elif [[ ! -s "$FILE" ]]; then
            # Empty CARD output is not necessarily an error
            echo "NO HITS : $SAMPLE_ID -- $(basename $FILE) (no ARGs detected)"
        fi
    fi

    # ── Diamond VFDB (virulence) ──────────────────────────────────────────────
    if [[ "$RUN_VIRULENCE" == true ]]; then
        FILE="$DIAMOND_DIR/${SAMPLE_ID}_vfdb.tsv"
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        elif [[ ! -s "$FILE" ]]; then
            echo "NO HITS : $SAMPLE_ID -- $(basename $FILE) (no virulence factors detected)"
        fi
    fi

    # ── Read counts file ──────────────────────────────────────────────────────
    if [[ "$RUN_ARG" == true || "$RUN_VIRULENCE" == true ]]; then
        FILE="$DIAMOND_DIR/${SAMPLE_ID}_readcounts.txt"
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $SAMPLE_ID -- $(basename $FILE)"
            ((MISSING++)); SAMPLE_FAIL=true
        fi
    fi

    if [[ "$SAMPLE_FAIL" == false ]]; then
        ((PASS++))
    else
        ((FAIL++))
    fi

done < "$SAMPLE_SHEET"

# ── HUMAnN3 merge outputs (not per-sample) ────────────────────────────────────
HUMANN_MERGE_FAIL=false
if [[ "$RUN_HUMANN" == true ]]; then
    echo ""
    echo "=== HUMAnN3 Merge Outputs ==="
    for FILE in \
        "$HUMANN_DIR/result_tables/humann_pathabundance.tsv" \
        "$HUMANN_DIR/result_tables/humann_pathabundance_unstratified.tsv" \
        "$HUMANN_DIR/result_tables/humann_pathabundance_stratified.tsv"; do
        if [[ ! -f "$FILE" ]]; then
            echo "MISSING : $(basename $FILE)"
            HUMANN_MERGE_FAIL=true
        elif [[ ! -s "$FILE" ]]; then
            echo "EMPTY   : $(basename $FILE)"
            HUMANN_MERGE_FAIL=true
        else
            echo "OK      : $(basename $FILE)"
        fi
    done
fi

# ── Diamond merge outputs (not per-sample) ────────────────────────────────────
DIAMOND_MERGE_FAIL=false
if [[ "$RUN_ARG" == true || "$RUN_VIRULENCE" == true ]]; then
    echo ""
    echo "=== Diamond Merge Outputs ==="

    if [[ "$RUN_ARG" == true ]]; then
        for FILE in \
            "$DIAMOND_DIR/normalized_results/card_all_samples_long.tsv" \
            "$DIAMOND_DIR/normalized_results/card_all_samples_wide.tsv"; do
            if [[ ! -f "$FILE" ]]; then
                echo "MISSING : $(basename $FILE)"
                DIAMOND_MERGE_FAIL=true
            elif [[ ! -s "$FILE" ]]; then
                echo "EMPTY   : $(basename $FILE)"
                DIAMOND_MERGE_FAIL=true
            else
                echo "OK      : $(basename $FILE)"
            fi
        done
    fi

    if [[ "$RUN_VIRULENCE" == true ]]; then
        for FILE in \
            "$DIAMOND_DIR/normalized_results/vfdb_all_samples_long.tsv" \
            "$DIAMOND_DIR/normalized_results/vfdb_all_samples_wide.tsv"; do
            if [[ ! -f "$FILE" ]]; then
                echo "MISSING : $(basename $FILE)"
                DIAMOND_MERGE_FAIL=true
            elif [[ ! -s "$FILE" ]]; then
                echo "EMPTY   : $(basename $FILE)"
                DIAMOND_MERGE_FAIL=true
            else
                echo "OK      : $(basename $FILE)"
            fi
        done
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

if [[ "$RUN_HUMANN" == true ]]; then
    if [[ "$HUMANN_MERGE_FAIL" == true ]]; then
        echo "  HUMAnN3 merge outputs : INCOMPLETE"
    else
        echo "  HUMAnN3 merge outputs : OK"
    fi
fi

if [[ "$RUN_ARG" == true || "$RUN_VIRULENCE" == true ]]; then
    if [[ "$DIAMOND_MERGE_FAIL" == true ]]; then
        echo "  Diamond merge outputs : INCOMPLETE"
    else
        echo "  Diamond merge outputs : OK"
    fi
fi

echo ""
if [[ "$FAIL" -gt 0 || "$HUMANN_MERGE_FAIL" == true || "$DIAMOND_MERGE_FAIL" == true ]]; then
    echo "WARNING: Some outputs are missing. Check logs in $LOG_DIR before proceeding."
    echo "Note: If merge outputs are missing, check if 03b job is still running."
else
    echo "All checks passed. Pipeline complete."
fi
