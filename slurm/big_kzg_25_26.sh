#!/bin/bash
#SBATCH --account=ALLOCATION
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --time=05:30:00
#SBATCH --mem=96G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

source "$SLURM_SUBMIT_DIR/slurm/common.sh" || exit 1

micro kzg 25 2
micro kzg 26 2
echo DONE
