#!/bin/bash
# generate_samplesheet.sh
# Usage: bash 0.generate_samplesheet.sh /path/to/reads R1_suffix R2_suffix
# Example: bash 0.generate_samplesheet.sh /path/to/reads _R1_001.fastq.gz _R2_001.fastq.gz

READS_DIR=${1:?ERROR: Please provide a reads directory}
R1_SUFFIX=${2:-"_R1_001.fastq.gz"}
R2_SUFFIX=${3:-"_R2_001.fastq.gz"}

OUTPUT="samples.tsv"

echo -e "sample_id\tread1\tread2" > "$OUTPUT"

for R1 in "$READS_DIR"/*${R1_SUFFIX}; do
  if [[ ! -f "$R1" ]]; then
    echo "WARNING: No files found matching *${R1_SUFFIX} in $READS_DIR"
    exit 1
  fi

  SAMPLE_ID=$(basename "$R1" "$R1_SUFFIX")
  R2="${READS_DIR}/${SAMPLE_ID}${R2_SUFFIX}"

  if [[ ! -f "$R2" ]]; then
    echo "WARNING: No R2 found for sample $SAMPLE_ID, skipping"
    continue
  fi

  echo -e "${SAMPLE_ID}\t${R1}\t${R2}" >> "$OUTPUT"
done

echo "Sample sheet written to $OUTPUT"
echo "$(grep -c "^[^s]" $OUTPUT) samples found"
