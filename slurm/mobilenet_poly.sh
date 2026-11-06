#!/bin/bash
#SBATCH --account=ALLOCATION
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --time=03:00:00
#SBATCH --mem=250G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

source "$SLURM_SUBMIT_DIR/slurm/common.sh" || exit 1

mobilenet poly 10200 kzg true 1 23 20 false false 1 . false false false
echo DONE
