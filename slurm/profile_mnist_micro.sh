#!/bin/bash
#SBATCH --account=ALLOCATION
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --time=02:30:00
#SBATCH --mem=64G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

source "$SLURM_SUBMIT_DIR/slurm/common.sh" || exit 1

mnist nocom kzg false 0 15 10 false false 3 . false false false
mnist poly kzg true 3 15 10 false false 3 . false false false
mnist cplink kzg false 0 15 10 true false 3 . true false false
profiled_micro kzg 20
profiled_micro ipa 18
profiled_micro kzg 22
profiled_micro ipa 20
echo DONE
