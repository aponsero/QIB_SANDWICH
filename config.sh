#!/bin/bash

# ══════════════════════════════════════════════════════════════════════════════
# INPUT / OUTPUT
# ══════════════════════════════════════════════════════════════════════════════
SAMPLE_SHEET="/path/to/samples.tsv"
OUT_DIR="/path/to//results"
LOG_DIR="/path/to/logs"

# ══════════════════════════════════════════════════════════════════════════════
# SEQUENCING
# ══════════════════════════════════════════════════════════════════════════════
TYPE="illumina"   # "illumina" or "mgi"

# ══════════════════════════════════════════════════════════════════════════════
# HOST REMOVAL
# ══════════════════════════════════════════════════════════════════════════════

# Set to false only if you are certain no human contamination is possible
REMOVE_HUMAN=true

# Food/environmental host to remove after human decontamination
# Options: "cow", "salmon", "soybean", "pig", "spinach"
# Set to "none" to skip food host removal
FOOD_HOST_REF="none"
HOSTILE_CACHE_DIR="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases/hostile"

# ══════════════════════════════════════════════════════════════════════════════
# MODULE SWITCHES
# ══════════════════════════════════════════════════════════════════════════════
RUN_METAPHLAN=true
RUN_SAMESTR=false      # requires RUN_METAPHLAN=true
RUN_KRAKEN=true
RUN_HUMANN=true
RUN_ARG=true
RUN_VIRULENCE=true

# ══════════════════════════════════════════════════════════════════════════════
# DATABASES
# ══════════════════════════════════════════════════════════════════════════════
# MetaPhlAn4 / SameStr
MET_DB="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases/SameStr_mpa_vJun23_CHOCOPhlAnSGB_202403/metaphlan_databases"
SAMEST_DB="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases/SameStr_mpa_vJun23_CHOCOPhlAnSGB_202403/database_sameStr/samestr_CHOCOPhlAnSGB_202403"

# Kraken2
KRAKENDB_DIR="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases//k2_standard_20250402"

# HUMAnN3
HUMANN_DB_DIR="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases/humann_3.9"
HUMANN_NUC="$HUMANN_DB_DIR/chocophlan"
HUMANN_PROT="$HUMANN_DB_DIR/uniref"
HUMANN_MPA="$HUMANN_DB_DIR"

# CARD (ARG)
CARD_DB="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases/diamond_db/card_protein_homolog_dbMay2025"

# VFDB (virulence factors)
VFDB_DB="/qib/platforms/Informatics/transfer/outgoing/qib_pipelines/SANDWICH_pipeline/databases/diamond_db/vfdb_protein_db"

# ══════════════════════════════════════════════════════════════════════════════
# DIAMOND PARAMETERS
# ══════════════════════════════════════════════════════════════════════════════
DIAMOND_EVALUE="1e-5"
DIAMOND_IDENTITY=80
DIAMOND_QCOV=80

# ══════════════════════════════════════════════════════════════════════════════
# PACKAGES
# ══════════════════════════════════════════════════════════════════════════════
PKG_HOSTILE="/nbi/software/testing/bin/hostile__2.0.0"
PKG_TRIMGALORE="04b61fb6-8090-486d-bc13-1529cd1fb791"
PKG_MULTIQC="a8a18f99-1c90-4175-8f58-330b0ad61cad"
PKG_METAPHLAN="/nbi/software/testing/bin/metaphlan__4.1.1"
PKG_SAMESTR="/nbi/software/testing/bin/samestr__1.2024.8"
PKG_KRAKEN2="/nbi/software/testing/bin/kraken2-2.1.3"
PKG_HUMANN="/nbi/software/testing/bin/humann__3.9"
PKG_HUMANN_UTILS="e59dcdcb-efe4-4b6c-90fc-f35899b7e1a2"
PKG_DIAMOND="/nbi/software/testing/bin/diamond__2.1.9"

# ══════════════════════════════════════════════════════════════════════════════
# SINGULARITY CONTAINERS
# ══════════════════════════════════════════════════════════════════════════════
MERGING_SIF="$SLURM_SUBMIT_DIR/scripts/merging_results.sif"

# ══════════════════════════════════════════════════════════════════════════════
# SLURM — MODULE 01a: QC + HOST REMOVAL (array)
# ══════════════════════════════════════════════════════════════════════════════
PARTITION_QC="qib-compute"
TIME_QC="12:00:00"
CPUS_QC=5
MEM_PER_CPU_QC="32G"

# ══════════════════════════════════════════════════════════════════════════════
# SLURM — MODULE 01b: QC MERGE (single job)
# ══════════════════════════════════════════════════════════════════════════════
PARTITION_QC_MERGE="qib-compute"
TIME_QC_MERGE="01:00:00"

# ══════════════════════════════════════════════════════════════════════════════
# SLURM — MODULE 02a: TAXONOMIC PROFILING (array)
# ══════════════════════════════════════════════════════════════════════════════
PARTITION_TAX="qib-compute"
TIME_TAX="03:00:00"
CPUS_TAX=30
MEM_PER_CPU_TAX="5000M"

# ══════════════════════════════════════════════════════════════════════════════
# SLURM — MODULE 02b: SAMESTR POPULATION (single job)
# ══════════════════════════════════════════════════════════════════════════════
PARTITION_SAMESTR="qib-compute"
TIME_SAMESTR="05:00:00"

# ══════════════════════════════════════════════════════════════════════════════
# SLURM — MODULE 03a: FUNCTIONAL ANNOTATION (array)
# ══════════════════════════════════════════════════════════════════════════════
PARTITION_FUNC="qib-compute"
TIME_FUNC="24:00:00"
CPUS_FUNC=10
MEM_PER_CPU_FUNC="40G"

# ══════════════════════════════════════════════════════════════════════════════
# SLURM — MODULE 03b: FUNCTIONAL MERGE (single job)
# ══════════════════════════════════════════════════════════════════════════════
PARTITION_FUNC_MERGE="qib-compute"
TIME_FUNC_MERGE="01:00:00"
