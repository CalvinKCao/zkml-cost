#!/bin/bash

#SBATCH --job-name=artemis-commit
#SBATCH --account=ALLOCATION
#SBATCH --time=00:50:00
#SBATCH --nodes=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  cd "$SCRATCH/artemis"
  sbatch "$SCRATCH/artemis/slurm_commit_bench.sh"
  exit 0
fi

cd "$SLURM_SUBMIT_DIR"
mkdir -p ./results/logs ./bench-out
STEM="$(date +%m-%d)-${SLURM_JOB_ID: -3}-artemis-commit"
LOG="./results/logs/${STEM}.log"
exec >>"$LOG" 2>&1

echo "job $SLURM_JOB_ID node ${SLURMD_NODENAME:-?} cpus ${SLURM_CPUS_PER_TASK:-?} $(date)"
nvidia-smi -L || true
nvidia-smi || true
lscpu | sed -n '1,25p' || true

export RUSTUP_HOME="${RUSTUP_HOME:-$SCRATCH/artemis-toolchain/rustup}"
export CARGO_HOME="${CARGO_HOME:-$SCRATCH/artemis-toolchain/cargo}"
export PATH="$CARGO_HOME/bin:$PATH"
export RAYON_NUM_THREADS="${SLURM_CPUS_PER_TASK:-16}"
export CARGO_BUILD_JOBS="${SLURM_CPUS_PER_TASK:-16}"
mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"

if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
  echo "ERROR: rustup missing at $CARGO_HOME"
  exit 1
fi

echo "=== toolchain (README: rustup override set nightly) ==="
rustup override set nightly
rustup show
rustc --version

echo "=== cargo build --release ==="
cargo build --release
echo "BUILD_OK $(date)"

BIN_BENCH=./target/release/commit_microbench
BIN_TIME=./target/release/time_circuit
PARAMS="${SLURM_TMPDIR:-/tmp}/artemis-params"
mkdir -p "$PARAMS" ./bench-out ./params_kzg_Bn256 ./params_kzg_Bls12 ./params_ipa ./results

seconds_left() {
  local end
  end=$(scontrol show job "$SLURM_JOB_ID" | sed -n 's/.*EndTime=\([^ ]*\).*/\1/p' | head -1)
  if [[ -z "$end" || "$end" == "Unknown" ]]; then
    echo 99999
    return
  fi
  local now end_s
  now=$(date +%s)
  end_s=$(date -d "$end" +%s)
  echo $((end_s - now))
}

run_micro() {
  local scheme="$1" k="$2" passes="$3" tmo="$4"
  local left
  left=$(seconds_left)
  echo "time_left_s=$left before $scheme k=$k"
  if (( left < tmo + 120 )); then
    echo "SKIP $scheme k=$k not enough wallclock"
    return 0
  fi
  echo "=== micro $scheme k=$k passes=$passes timeout=$tmo ==="
  set +e
  timeout --signal=TERM "$tmo" \
    "$BIN_BENCH" "$scheme" "$k" "$passes" "$PARAMS/${scheme}-${k}.params" \
    > "./bench-out/${scheme}-k${k}.csv" \
    2> "./bench-out/${scheme}-k${k}.log"
  local rc=$?
  set -e
  echo "micro $scheme k=$k exit $rc"
  if [[ -f "./bench-out/${scheme}-k${k}.csv" ]]; then
    cat "./bench-out/${scheme}-k${k}.csv"
  fi
}

run_mnist() {
  local tag="$1"
  shift
  local left
  left=$(seconds_left)
  echo "time_left_s=$left before mnist $tag"
  if (( left < 180 )); then
    echo "SKIP mnist $tag"
    return 0
  fi
  local tmo=600
  if (( left < 700 )); then
    tmo=$((left - 90))
  fi
  echo "=== mnist $tag timeout=$tmo args: $* ==="
  set +e
  timeout --signal=TERM "$tmo" \
    "$BIN_TIME" "$@" \
    > "./bench-out/mnist-${tag}.log" \
    2>&1
  local rc=$?
  set -e
  echo "mnist $tag exit $rc"
  if [[ -f results/output.csv ]]; then
    cp results/output.csv "./bench-out/mnist-${tag}.csv"
  fi
  tail -n 40 "./bench-out/mnist-${tag}.log" || true
}

run_mnist nocom-kzg \
  examples/mnist/model.msgpack examples/mnist/inp.msgpack \
  kzg false 0 15 10 false false 1 . false false false

run_micro kzg 16 2 180
run_micro kzg 18 2 180
run_micro kzg 20 2 240
run_micro kzg 22 2 300
run_micro ipa 16 2 180
run_micro ipa 18 2 240
run_micro ipa 20 2 300

run_mnist poly-kzg \
  examples/mnist/model.msgpack examples/mnist/inp.msgpack \
  kzg true 3 15 10 false false 1 . false false false

run_micro kzg 24 2 420
run_micro ipa 22 2 360

run_mnist cplink-kzg \
  examples/mnist/model.msgpack examples/mnist/inp.msgpack \
  kzg false 0 15 10 true false 1 . true false false

PROF_K=""
for k in 20 22 18 16 24; do
  if [[ -s "./bench-out/kzg-k${k}.csv" && -f "$PARAMS/kzg-${k}.params" ]]; then
    PROF_K="$k"
    break
  fi
done

if [[ -n "$PROF_K" ]]; then
  left=$(seconds_left)
  echo "time_left_s=$left profile k=$PROF_K"
  if (( left > 180 )); then
    echo "=== perf stat kzg k=$PROF_K (cached params, 1 pass) ==="
    set +e
    perf stat -o "./bench-out/perf-stat-kzg-k${PROF_K}.txt" -- \
      "$BIN_BENCH" kzg "$PROF_K" 1 "$PARAMS/kzg-${PROF_K}.params" \
      > "./bench-out/kzg-k${PROF_K}-perfpass.csv" \
      2> "./bench-out/kzg-k${PROF_K}-perfpass.log"
    echo "perf stat exit $?"
    if (( $(seconds_left) > 150 )); then
      echo "=== perf record kzg k=$PROF_K ==="
      perf record -F 99 -g --call-graph dwarf -o "./bench-out/perf-kzg-k${PROF_K}.data" -- \
        "$BIN_BENCH" kzg "$PROF_K" 1 "$PARAMS/kzg-${PROF_K}.params" \
        > "./bench-out/kzg-k${PROF_K}-perrecord.csv" \
        2> "./bench-out/kzg-k${PROF_K}-perrecord.log"
      echo "perf record exit $?"
      perf report --stdio --no-children -i "./bench-out/perf-kzg-k${PROF_K}.data" \
        > "./bench-out/perf-report-kzg-k${PROF_K}.txt" 2>&1 || true
      sz=$(stat -c%s "./bench-out/perf-kzg-k${PROF_K}.data" 2>/dev/null || echo 0)
      if (( sz > 200000000 )); then
        rm -f "./bench-out/perf-kzg-k${PROF_K}.data"
        echo "removed large perf.data ($sz bytes); report kept"
      fi
    fi
    set -e
  else
    echo "SKIP perf, not enough time"
  fi
else
  echo "SKIP perf, no cached kzg params"
fi

echo "=== nvidia-smi at end ==="
nvidia-smi || true
echo "DONE $(date)"
ls -lah ./bench-out || true
