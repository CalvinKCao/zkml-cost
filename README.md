# artemis-commit-bench

Wrapper benchmarks for pps-lab/artemis. They time committing to and opening a weight vector with KZG on Bn256 and IPA on pasta as the vector grows, and they run a few full proofs to see how much of the prover time the weight commitment takes.

rust/commit_microbench.rs goes into src/bin/ of the Artemis checkout and builds with cargo build --release. It is run as commit_microbench <kzg|ipa> <k> [passes] [params_path].

slurm/ has the job scripts used on Killarney. They expect the Artemis checkout in the submit directory and need the account name and scratch paths changed for another cluster.

profiler/sampler.c is an LD_PRELOAD sampler used in place of perf, and profiler/resolve.py maps its samples to symbol names with nm.

scripts/ has the analysis. Run e2e_summary.py, analyze.py, profile_report.py, breakeven.py and fraction_plot.py in this order. profile_report.py takes the directory holding copies of the commit_microbench and time_circuit binaries.

results/ has the raw logs and csv files, the summary tables and the plots. FINDINGS.md has the write-up.

The raw sampler files (results/raw/prof-*.bin, about 120 MB) are not in git. profile_shares.csv and profile_top_self.txt hold the numbers resolved from them.
