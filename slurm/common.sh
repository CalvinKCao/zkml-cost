set -uo pipefail
cd "$SLURM_SUBMIT_DIR"
mkdir -p results/logs bench-out params_kzg_Bn256 params_kzg_Bls12 params_ipa
exec >>"results/logs/$(date +%m-%d)-${SLURM_JOB_ID: -3}-$SLURM_JOB_NAME.log" 2>&1

export RUSTUP_HOME="$SCRATCH/artemis-toolchain/rustup"
export CARGO_HOME="$SCRATCH/artemis-toolchain/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
export RAYON_NUM_THREADS=16

SAMPLER="$PWD/profiler/libsampler.so"
BENCH=./target/release/commit_microbench
CIRCUIT=./target/release/time_circuit
PARAMS="$SLURM_TMPDIR/params"
mkdir -p "$PARAMS"

micro() {
  scheme="$1"; k="$2"; passes="$3"
  "$BENCH" "$scheme" "$k" "$passes" "$PARAMS/$scheme-$k.params" \
    > "bench-out/$scheme-k$k-r2.csv" 2> "bench-out/$scheme-k$k-r2.log"
  echo "micro $scheme $k exit $?"
}

profiled_micro() {
  scheme="$1"; k="$2"
  micro "$scheme" "$k" 2
  env LD_PRELOAD="$SAMPLER" PROF_OUT="bench-out/prof-$scheme-k$k.bin" PROF_HZ=50 \
    "$BENCH" "$scheme" "$k" 2 "$PARAMS/$scheme-$k.params" \
    > "bench-out/$scheme-k$k-prof.csv" 2> "bench-out/$scheme-k$k-prof.log"
  echo "profiled $scheme $k exit $?"
}

mnist() {
  tag="$1"; shift
  rm -f results/output.csv
  env LD_PRELOAD="$SAMPLER" PROF_OUT="bench-out/prof-mnist-$tag.bin" PROF_HZ=100 \
    "$CIRCUIT" examples/mnist/model.msgpack examples/mnist/inp.msgpack "$@" \
    > "bench-out/mnist3-$tag.log" 2>&1
  echo "mnist $tag exit $?"
  cp results/output.csv "bench-out/mnist3-$tag.csv"
}

mobilenet() {
  tag="$1"; limit="$2"; shift 2
  work="$SLURM_TMPDIR/run-$tag"
  mkdir -p "$work/results" "$work/params_kzg_Bls12" "$work/params_ipa"
  ln -sfn "$SLURM_SUBMIT_DIR/params_kzg_Bn256" "$work/params_kzg_Bn256"
  cd "$work"
  /usr/bin/time -v timeout --signal=TERM "$limit" \
    env LD_PRELOAD="$SAMPLER" PROF_OUT="$SLURM_SUBMIT_DIR/bench-out/prof-mobilenet-$tag.bin" PROF_HZ=5 \
    "$SLURM_SUBMIT_DIR/$CIRCUIT" \
    "$SLURM_SUBMIT_DIR/examples/v2_1.0_224_truncated/model.msgpack" \
    "$SLURM_SUBMIT_DIR/examples/train_graph/input.msgpack" "$@" \
    > "$SLURM_SUBMIT_DIR/bench-out/mobilenet5-$tag.log" 2> "$SLURM_SUBMIT_DIR/bench-out/mobilenet5-$tag.time"
  echo "mobilenet $tag exit $?"
  cp results/output.csv "$SLURM_SUBMIT_DIR/bench-out/mobilenet5-$tag.csv" 2>/dev/null
  grep -E "Proving time|Verifying time|KZG proof time|panicked" "$SLURM_SUBMIT_DIR/bench-out/mobilenet5-$tag.log"
  grep -E "Maximum resident|Elapsed" "$SLURM_SUBMIT_DIR/bench-out/mobilenet5-$tag.time"
  cd "$SLURM_SUBMIT_DIR"
}
