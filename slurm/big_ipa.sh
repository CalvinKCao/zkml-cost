#!/bin/bash
#SBATCH --account=ALLOCATION
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --time=03:00:00
#SBATCH --mem=64G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

source "$SLURM_SUBMIT_DIR/slurm/common.sh" || exit 1

micro ipa 22 2
micro ipa 24 2
echo DONE
