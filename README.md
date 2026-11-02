# artemis-commit-bench

Wrapper benchmarks for [pps-lab/artemis](https://github.com/pps-lab/artemis): cost of committing to and opening a weight vector (KZG / Bn256 and IPA / pasta) as a function of length, plus a few end-to-end runs.

- `rust/commit_microbench.rs`: drop into `src/bin/` of the Artemis checkout, then `cargo build --release`. Usage: `commit_microbench <kzg|ipa> <k> [passes] [params_path]`.
- `slurm/`: the job scripts used on Killarney. Set the account and `$SCRATCH` layout for your cluster.
- `scripts/analyze.py`: builds `results/microbench_summary.csv`, `results/scaling_fits.csv` and plots from `results/raw/`.
- `results/e2e_summary.csv`: end-to-end runs (MNIST, truncated MobileNet).
- `FINDINGS.md`: results and caveats.
