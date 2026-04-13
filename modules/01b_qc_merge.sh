#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

source config.sh
source package $PKG_MULTIQC

echo "Job started"; hostname; date

# ── Directories ───────────────────────────────────────────────────────────────
FASTQC_DIR="$OUT_DIR/01_qc/fastqc"
HOST_DIR="$OUT_DIR/01_qc/host_removal"
AGG_DIR="$OUT_DIR/04_aggregated/01_qc"
MULTIQC_DIR="$AGG_DIR/multiqc"

[[ ! -d "$MULTIQC_DIR" ]] && mkdir -p "$MULTIQC_DIR"

cp config.sh "$OUT_DIR/04_aggregated/"
cp scripts/01_qc_report.Rmd "$OUT_DIR/04_aggregated/01_qc/"

# ── MultiQC ───────────────────────────────────────────────────────────────────
echo "Running MultiQC..."

FASTQC_COUNT=$(find "$FASTQC_DIR" -name "*_fastqc.zip" | wc -l)
if [[ "$FASTQC_COUNT" -eq 0 ]]; then
    echo "ERROR: No FastQC zip files found in $FASTQC_DIR"
    exit 1
fi
echo "Found $FASTQC_COUNT FastQC zip files"

multiqc "$FASTQC_DIR" \
    --outdir "$MULTIQC_DIR" \
    --filename multiqc_report \
    --force

echo "MultiQC complete"

# ── Clean up tmp folders ──────────────────────────────────────────────────────
find "$OUT_DIR/01_qc/trimming" -type d -name "tmp" -exec rm -rf {} + 2>/dev/null
echo "Tmp folders cleaned"

# ── Parse Hostile JSON files ──────────────────────────────────────────────────
echo "Parsing Hostile JSON files..."

HUMAN_JSON_COUNT=$(find "$HOST_DIR" -name "*_human_hostmap.json" | wc -l)
FOOD_JSON_COUNT=$(find  "$HOST_DIR" -name "*_food_hostmap.json"  | wc -l)

if [[ "$HUMAN_JSON_COUNT" -eq 0 && "$FOOD_JSON_COUNT" -eq 0 ]]; then
    echo "ERROR: No Hostile JSON files found in $HOST_DIR"
    exit 1
fi
echo "Found $HUMAN_JSON_COUNT human JSON files and $FOOD_JSON_COUNT food JSON files"

OUTPUT_CSV="$AGG_DIR/hostile_summary.csv"

# Write header
echo "sample_name,reads_in,reads_after_human,reads_out,\
reads_removed_human,reads_removed_proportion_human,\
reads_removed_food,reads_removed_proportion_food,food_host" \
    > "$OUTPUT_CSV"

# ── Iterate over samples ──────────────────────────────────────────────────────
while IFS=$'\t' read -r SAMPLE_ID READ1 READ2 SAMPLE_FOOD_HOST; do
    [[ "$SAMPLE_ID" == "sample_id" ]] && continue

    # Strip carriage returns from all fields (Windows Excel TSV safety)
    SAMPLE_ID=$(echo "$SAMPLE_ID" | tr -d '\r')
    READ1=$(echo "$READ1"         | tr -d '\r')
    READ2=$(echo "$READ2"         | tr -d '\r')

    HUMAN_JSON="$HOST_DIR/${SAMPLE_ID}_human_hostmap.json"
    FOOD_JSON="$HOST_DIR/${SAMPLE_ID}_food_hostmap.json"

    # ── Parse human JSON ──────────────────────────────────────────────────────
    if [[ -f "$HUMAN_JSON" ]]; then
        human_index=$(jq -r '.[0].index' "$HUMAN_JSON")

        if [[ "$human_index" == "none" ]]; then
            # Placeholder: human step was skipped
            # reads_in comes from the food JSON or raw read count
            reads_removed_human=0
            reads_removed_prop_human=0
            reads_after_human=""   # will be set after food JSON is parsed
        else
            reads_in=$(jq -r            '.[0].reads_in'                 "$HUMAN_JSON")
            reads_after_human=$(jq -r   '.[0].reads_out'                "$HUMAN_JSON")
            reads_removed_human=$(jq -r '.[0].reads_removed'            "$HUMAN_JSON")
            reads_removed_prop_human=$(jq -r \
                                        '.[0].reads_removed_proportion'  "$HUMAN_JSON")
        fi
    else
        echo "WARNING: No human JSON found for $SAMPLE_ID — filling with NA"
        reads_in="NA"
        reads_after_human="NA"
        reads_removed_human="NA"
        reads_removed_prop_human="NA"
    fi

    # ── Parse food JSON ───────────────────────────────────────────────────────
    if [[ -f "$FOOD_JSON" ]]; then
        food_index=$(jq -r '.[0].index' "$FOOD_JSON")

        if [[ "$food_index" == "none" ]]; then
            # Placeholder: food step was skipped for this sample
            reads_removed_food=0
            reads_removed_prop_food=0
            food_host="none"
            # reads_out is whatever came out of the human step (or raw reads)
            if [[ -n "$reads_after_human" ]]; then
                reads_out="$reads_after_human"
            else
                # Neither step ran — count raw reads directly
                reads_out=$(zcat "$READ1" | awk 'NR % 4 == 2' | wc -l)
            fi
        else
            # Food step actually ran — extract short host name from index
            # e.g. "cow-argos985" → "cow", "human-t2t-hla" → "human"
            food_host=$(echo "$food_index" | cut -d'-' -f1)
            reads_removed_food=$(jq -r      '.[0].reads_removed'            "$FOOD_JSON")
            reads_removed_prop_food=$(jq -r '.[0].reads_removed_proportion' "$FOOD_JSON")
            reads_out=$(jq -r               '.[0].reads_out'                "$FOOD_JSON")

            # If human step was skipped, reads_in comes from food JSON
            if [[ "$human_index" == "none" ]]; then
                reads_in=$(jq -r '.[0].reads_in' "$FOOD_JSON")
                reads_after_human="$reads_in"
            fi
        fi
    else
        echo "WARNING: No food JSON found for $SAMPLE_ID — filling with NA"
        reads_removed_food="NA"
        reads_removed_prop_food="NA"
        food_host="NA"
        reads_out="NA"
    fi

    # ── Edge case: neither step ran ───────────────────────────────────────────
    if [[ "$human_index" == "none" && "$food_index" == "none" ]]; then
        reads_in=$(zcat "$READ1" | awk 'NR % 4 == 2' | wc -l)
        reads_after_human="$reads_in"
        reads_out="$reads_in"
        food_host="none"
    fi

    echo "$SAMPLE_ID,$reads_in,$reads_after_human,$reads_out,\
$reads_removed_human,$reads_removed_prop_human,\
$reads_removed_food,$reads_removed_prop_food,$food_host" \
        >> "$OUTPUT_CSV"

done < "$SAMPLE_SHEET"

echo "Hostile summary written to $OUTPUT_CSV"

# ── Print reminder for user ───────────────────────────────────────────────────
echo ""
echo "======================================================================"
echo "Aggregated QC outputs are ready in: $AGG_DIR"
echo ""
echo "Before running the Rmarkdown report, add your metadata file:"
echo "  $OUT_DIR/04_aggregated/metadata.tsv"
echo ""
echo "Expected metadata format (tab-separated):"
echo "  sequence_id    sample_name    sample_group"
echo "  sample1        Sample 1       Group1"
echo "  blank1         Blank 1        blank"
echo "======================================================================"
echo "Job done"; date
