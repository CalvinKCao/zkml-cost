#!/bin/bash
#SBATCH --account=ALLOCATION
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

set -uo pipefail

cd "$SLURM_SUBMIT_DIR"
mkdir -p results/logs bench-out
tag="$1"
exec >>"results/logs/$(date +%m-%d)-${SLURM_JOB_ID: -3}-artemis-mobilenet-$tag.log" 2>&1

export RUSTUP_HOME="$SCRATCH/artemis-toolchain/rustup"
export CARGO_HOME="$SCRATCH/artemis-toolchain/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
export RAYON_NUM_THREADS=16

MODEL=examples/v2_1.0_224_truncated/model.msgpack
INPUT=examples/train_graph/input.msgpack

case "$tag" in
  nocom) args="kzg false 0 23 20 false false 1 . false false false" ;;
  poly)  args="kzg true 1 23 20 false false 1 . false false false" ;;
esac

work="$SLURM_TMPDIR/run-$tag"
mkdir -p "$work/results"
ln -sfn "$PWD/params_kzg_Bn256" "$work/params_kzg_Bn256"
mkdir -p "$work/params_kzg_Bls12" "$work/params_ipa"
cd "$work"
/usr/bin/time -v timeout --signal=TERM 3300 "$SLURM_SUBMIT_DIR/target/release/time_circuit" \
  "$SLURM_SUBMIT_DIR/$MODEL" "$SLURM_SUBMIT_DIR/$INPUT" $args \
  > "$SLURM_SUBMIT_DIR/bench-out/mobilenet4-$tag.log" 2> "$SLURM_SUBMIT_DIR/bench-out/mobilenet4-$tag.time"
echo "mobilenet $tag exit $?"
cp results/output.csv "$SLURM_SUBMIT_DIR/bench-out/mobilenet4-$tag.csv" 2>/dev/null
grep -E "Proving time|Verifying time|panicked|KZG proof time" "$SLURM_SUBMIT_DIR/bench-out/mobilenet4-$tag.log"
grep -E "Maximum resident|Elapsed" "$SLURM_SUBMIT_DIR/bench-out/mobilenet4-$tag.time"
echo DONE
