#!/bin/bash

#SBATCH --job-name=artemis-commit2
#SBATCH --account=ALLOCATION
#SBATCH --time=00:50:00
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

set -euo pipefail

cd "$SLURM_SUBMIT_DIR"
mkdir -p ./results/logs ./bench-out ./params_kzg_Bn256 ./params_ipa ./results
STEM="$(date +%m-%d)-${SLURM_JOB_ID: -3}-artemis-commit2"
LOG="./results/logs/${STEM}.log"
exec >>"$LOG" 2>&1

echo "job $SLURM_JOB_ID node ${SLURMD_NODENAME:-?} $(date)"
nvidia-smi -L || true

export RUSTUP_HOME="${RUSTUP_HOME:-$SCRATCH/artemis-toolchain/rustup}"
export CARGO_HOME="${CARGO_HOME:-$SCRATCH/artemis-toolchain/cargo}"
export PATH="$CARGO_HOME/bin:$PATH"
export RAYON_NUM_THREADS="${SLURM_CPUS_PER_TASK:-16}"

BIN_BENCH=./target/release/commit_microbench
BIN_TIME=./target/release/time_circuit
[[ -x "$BIN_BENCH" && -x "$BIN_TIME" ]] || { echo "ERROR: release binaries missing"; exit 1; }

PARAMS="${SLURM_TMPDIR:-/tmp}/artemis-params"
mkdir -p "$PARAMS"

seconds_left() {
  local end now end_s
  end=$(scontrol show job "$SLURM_JOB_ID" | sed -n 's/.*EndTime=\([^ ]*\).*/\1/p' | head -1 || true)
  if [[ -z "$end" || "$end" == "Unknown" ]]; then
    echo 99999
    return
  fi
  now=$(date +%s)
  end_s=$(date -d "$end" +%s)
  echo $((end_s - now))
}

echo "=== mnist nocom-kzg ==="
set +e
timeout --signal=TERM 600 \
  "$BIN_TIME" examples/mnist/model.msgpack examples/mnist/inp.msgpack \
  kzg false 0 15 10 false false 1 . false false false \
  > ./bench-out/mnist-nocom-kzg.log 2>&1
echo "mnist nocom exit $?"
set -e
if [[ -f results/output.csv ]]; then
  cp results/output.csv ./bench-out/mnist-nocom-kzg.csv
fi
grep -E "Proving time|Verifying time|Proof size|panicked" ./bench-out/mnist-nocom-kzg.log || true

run_micro() {
  local scheme="$1" k="$2" tmo="$3"
  local left
  left=$(seconds_left)
  echo "time_left_s=$left before $scheme k=$k"
  if (( left < tmo / 2 )); then
    echo "SKIP $scheme k=$k"
    return 0
  fi
  set +e
  timeout --signal=TERM "$tmo" \
    "$BIN_BENCH" "$scheme" "$k" 2 "$PARAMS/${scheme}-${k}.params" \
    > "./bench-out/${scheme}-k${k}.csv" \
    2> "./bench-out/${scheme}-k${k}.log"
  echo "micro $scheme k=$k exit $?"
  set -e
  cat "./bench-out/${scheme}-k${k}.csv" || true
}

run_micro kzg 24 2400
run_micro kzg 22 900

left=$(seconds_left)
echo "time_left_s=$left before ipa 22"
if (( left > 900 )); then
  run_micro ipa 22 800
fi

echo "=== nvidia-smi at end ==="
nvidia-smi || true
echo "DONE $(date)"
