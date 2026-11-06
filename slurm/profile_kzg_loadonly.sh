#!/bin/bash
#SBATCH --account=ALLOCATION
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --time=00:45:00
#SBATCH --mem=64G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

source "$SLURM_SUBMIT_DIR/slurm/common.sh" || exit 1

for k in 20 22; do
  micro kzg "$k" 1
  env LD_PRELOAD="$SAMPLER" PROF_OUT="bench-out/prof-kzg-k$k-loadonly.bin" PROF_HZ=50 \
    "$BENCH" kzg "$k" 0 "$PARAMS/kzg-$k.params" \
    > "bench-out/kzg-k$k-loadonly.csv" 2> "bench-out/kzg-k$k-loadonly.log"
  echo "loadonly kzg $k exit $?"
done
echo DONE
