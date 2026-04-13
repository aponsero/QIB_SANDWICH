#!/usr/bin/env python3
# normalize_and_summarize.py - Process all Diamond results
# Usage: python3 normalize_and_summarize.py <sample_list.txt>

import sys
import pandas as pd
from pathlib import Path
from collections import defaultdict

def calculate_rpkm(read_count, gene_length, total_reads):
    """Calculate RPKM: (reads * 10^9) / (gene_length * total_reads)"""
    if total_reads == 0:
        return 0
    return (read_count * 1e9) / (gene_length * total_reads)

def process_sample(sample_name, total_reads, diamond_dir, database_type):
    """Process Diamond output for one sample"""
    
    diamond_file = Path(diamond_dir) / f"{sample_name}_{database_type}.tsv"
    
    # Check if file exists
    if not diamond_file.exists():
        print(f"Warning: {diamond_file} not found, skipping {sample_name}")
        return pd.DataFrame()
    
    # Check if file is empty
    if diamond_file.stat().st_size == 0:
        print(f"Note: {diamond_file} is empty (no hits for {sample_name})")
        return pd.DataFrame()
    
    # Read Diamond output
    cols = ['qseqid', 'sseqid', 'pident', 'length', 'qlen', 'slen', 'evalue', 'bitscore', 'qcovhsp']
    try:
        df = pd.read_csv(diamond_file, sep='\t', names=cols)
    except pd.errors.EmptyDataError:
        print(f"Note: {diamond_file} is empty (no hits for {sample_name})")
        return pd.DataFrame()
    
    if df.empty:
        print(f"Note: No hits in {diamond_file} for {sample_name}")
        return pd.DataFrame()
    
    # Keep best hit per read (redundant with --max-target-seqs 1, but safe)
    df = df.sort_values('bitscore', ascending=False).drop_duplicates('qseqid', keep='first')
    
    # Count reads per gene
    gene_counts = df.groupby('sseqid').agg({
        'qseqid': 'count',
        'slen': 'first'
    }).rename(columns={'qseqid': 'read_count'})
    
    # Calculate RPKM
    gene_counts['RPKM'] = gene_counts.apply(
        lambda row: calculate_rpkm(row['read_count'], row['slen'], total_reads),
        axis=1
    )
    
    gene_counts['sample'] = sample_name
    gene_counts['total_reads'] = total_reads
    
    return gene_counts.reset_index()

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 normalize_and_summarize.py <sample_list.txt>")
        print("\nExpected format of sample_list.txt (comma-separated):")
        print("sample_name,total_reads")
        print("sample1,1000000")
        print("sample2,1500000")
        sys.exit(1)
    
    sample_info_file = sys.argv[1]
    diamond_dir = "."
    output_dir = "normalized_results"
    Path(output_dir).mkdir(exist_ok=True)
    
    # Read sample information (comma-separated)
    sample_info = pd.read_csv(sample_info_file, sep=',', names=['sample_name', 'total_reads'])
    print(f"Processing {len(sample_info)} samples...")
    
    # Track samples with no hits
    no_hits_card = []
    no_hits_vfdb = []
    
    # Process CARD results
    print("\n" + "="*60)
    print("Processing CARD results...")
    print("="*60)
    card_all = []
    for _, row in sample_info.iterrows():
        result = process_sample(row['sample_name'], row['total_reads'], diamond_dir, 'card')
        if not result.empty:
            card_all.append(result)
        else:
            no_hits_card.append(row['sample_name'])
    
    if card_all:
        card_df = pd.concat(card_all, ignore_index=True)
        
        # Create wide format for easier viewing
        card_wide = card_df.pivot_table(
            index='sseqid',
            columns='sample',
            values='RPKM',
            fill_value=0
        )
        
        # Save results
        card_df.to_csv(f"{output_dir}/card_all_samples_long.tsv", sep='\t', index=False)
        card_wide.to_csv(f"{output_dir}/card_all_samples_wide.tsv", sep='\t')
        
        print(f"\nCARD Summary:")
        print(f"  - {len(card_wide)} unique ARGs detected")
        print(f"  - {len(card_df['sample'].unique())} samples with hits")
        print(f"  - {len(no_hits_card)} samples with no hits")
    else:
        print("\nCARD: No ARGs detected in any sample")
    
    # Process VFDB results
    print("\n" + "="*60)
    print("Processing VFDB results...")
    print("="*60)
    vfdb_all = []
    for _, row in sample_info.iterrows():
        result = process_sample(row['sample_name'], row['total_reads'], diamond_dir, 'vfdb')
        if not result.empty:
            vfdb_all.append(result)
        else:
            no_hits_vfdb.append(row['sample_name'])
    
    if vfdb_all:
        vfdb_df = pd.concat(vfdb_all, ignore_index=True)
        
        # Create wide format
        vfdb_wide = vfdb_df.pivot_table(
            index='sseqid',
            columns='sample',
            values='RPKM',
            fill_value=0
        )
        
        # Save results
        vfdb_df.to_csv(f"{output_dir}/vfdb_all_samples_long.tsv", sep='\t', index=False)
        vfdb_wide.to_csv(f"{output_dir}/vfdb_all_samples_wide.tsv", sep='\t')
        
        print(f"\nVFDB Summary:")
        print(f"  - {len(vfdb_wide)} unique virulence factors detected")
        print(f"  - {len(vfdb_df['sample'].unique())} samples with hits")
        print(f"  - {len(no_hits_vfdb)} samples with no hits")
    else:
        print("\nVFDB: No virulence factors detected in any sample")
    
    # Save summary of samples with no hits
    if no_hits_card:
        with open(f"{output_dir}/card_no_hits_samples.txt", 'w') as f:
            f.write('\n'.join(no_hits_card))
        print(f"\nList of samples with no CARD hits saved to: {output_dir}/card_no_hits_samples.txt")
    
    if no_hits_vfdb:
        with open(f"{output_dir}/vfdb_no_hits_samples.txt", 'w') as f:
            f.write('\n'.join(no_hits_vfdb))
        print(f"List of samples with no VFDB hits saved to: {output_dir}/vfdb_no_hits_samples.txt")
    
    print(f"\n" + "="*60)
    print(f"All results saved to {output_dir}/")
    print("="*60)

if __name__ == "__main__":
    main()
