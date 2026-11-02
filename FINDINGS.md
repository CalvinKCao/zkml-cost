# Artemis commitment cost: findings

Hardware: one Killarney node, 16 vCPU (Xeon, AVX-512), L40S GPU allocated but unused (Halo2 MSMs here are CPU-only). Repo: pps-lab/artemis at commit 69dff50, built with current nightly (see 4).
Every number is a single job; microbenchmarks have 2 passes per size except IPA 2^22 (1 pass).

## 1. Reproduced vs the paper

Only MNIST ships a runnable model with inputs, so only MNIST was compared (paper Fig. 7 / Table 1, KZG).

| | paper | here |
|---|---|---|
| Artemis prover overhead vs no-commitment | 1.01x-1.15x | **1.29x** (6.18 s vs 4.80 s) |
| Verifier time, no-com / Artemis | 7 ms / 8 ms | 6.4 ms / 12.9 ms |
| Lunar-style CP-link overhead | not extracted | 7.9x (37.96 s) |

The Artemis overhead is outside the paper's range. Different hardware (16 vCPU vs 32), `poly_cols=3` chosen by me from `test.zsh`, single run. Of the 6.18 s, 5.45 s is the halo2 proof and 0.73 s is two external KZG weight openings (326 ms and 406 ms), i.e. 11.8%. Not reproduced: absolute times, other models, IPA end-to-end.

## 2. Scaling result

- KZG commit+open of a random length-n vector: 0.27 s at 2^16, 3.2 s at 2^20, 11.8 s at 2^22, 44.4 s at 2^24. Log-log slope 0.92 (5 points, 2^16 to 2^24).
- IPA commit+open: 1.4 s at 2^16, 20.9 s at 2^20, 81.9 s at 2^22. Slope 0.97. IPA opening is 7-10x slower than KZG opening and dominates; IPA verify grows linearly (0.003 s to 0.07 s).
- Peak memory is linear, about 0.5 GiB per 2^20 elements for KZG (8.5 GiB at 2^24).
- Rough cross-experiment comparison only: truncated MobileNet's no-commitment proof took 2880 s (155 GiB peak), so one 2^22-element KZG opening (11.8 s) is about 0.4% of that. These are different circuits and were not measured inside one run.
- No evidence that commitment cost becomes the bottleneck at the sizes measured, but no end-to-end fraction was measured above MNIST.

## 3. What this does NOT show

- No end-to-end Artemis-vs-baseline ratio beyond MNIST. The Artemis-style MobileNet run did not finish in 55 min (about 47 min of proving) on 16 vCPU; the no-commitment run took 48 min. Their ratio is unknown.
- Nothing about "base proof gets much faster". I did not speed up the base proof; the experiment only gives commitment cost as a function of n.
- Microbenchmarks use random dense vectors and one opening point, not the repo's batched openings of real weight tensors.
- Nothing above KZG 2^24 / IPA 2^22. No extrapolation made. Slope fits cannot separate linear from n log n with these points.
- No profile (see 4). The commit vs open split is from timers, not from where cycles go.
- GPU MSMs were not tested; the repo has none.

## 4. Things to double-check

- `perf` is unusable on Killarney (`perf_event_paranoid=4`), so step 5 was not done. `results/raw/perf-*.txt` are empty/error output.
- `rust-toolchain.toml` pins nightly-2024-05-09, which cannot resolve crates.io today (`constant_time_eq 0.4.2` needs edition 2024) and there is no `Cargo.lock`. The README's `rustup override set nightly` was used instead.
- The repo ships a stale `results/output.csv` (67.9 s MNIST row). It was copied by an early run after the first no-commitment run crashed (missing `params_kzg_Bn256/`); that number is not a measurement and is not used. The rerun gave 4.80 s.
- MobileNet jobs failed twice on memory (128 GB, 96 GB) before succeeding with 200 GB / 400 GB; SRS construction at k=23 took 981 s once and 120-160 s from the cached file. Setup time is excluded from prover time everywhere.
- Single runs everywhere, so no run-to-run variance estimate; treat the 1.29x MNIST ratio as rough.
- The MobileNet model is the repo's truncated `v2_1.0_224_truncated`, paired with `examples/train_graph/input.msgpack` (my guess, since the files are byte-identical to the model and the only input shipped); rows=23, cols=20 copied from `test.zsh`.

## Repo modifications

None to the Artemis repo's existing files. Added one file, `src/bin/commit_microbench.rs` (`rust/commit_microbench.rs` here), which calls the repo's own `ParamsKZG`/`ParamsIPA` commit and prover/verifier APIs.

## Email summary

I timed Artemis's commitment and opening step on its own, using the repo's KZG and IPA code, for vectors from 65 thousand to 16 million elements: cost grows roughly linearly in size (KZG 44 s at 2^24, IPA 82 s at 2^22), and verification stays tiny for KZG. On the one small model I could fully reproduce (MNIST) the commitment overhead was 1.29x versus 1.01-1.15x in the paper, and on a larger MobileNet the commitment-enabled run did not finish within my one-hour budget, so I cannot yet say what fraction of total prover time it is at scale. I would be glad to share the scripts and raw numbers.
