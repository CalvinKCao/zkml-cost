import glob
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

root = Path(__file__).resolve().parent.parent
raw = root / "results" / "raw"
plots = root / "results" / "plots"
plots.mkdir(exist_ok=True)

frames = [pd.read_csv(f) for f in sorted(glob.glob(str(raw / "*-k*.csv")))
          if Path(f).name.split("-")[0] in ("kzg", "ipa") and "pass" not in f and "per" not in f]
df = pd.concat(frames, ignore_index=True)
df["peak_gib"] = df.peak_rss_kib / 2**20
agg = (df.groupby(["scheme", "k", "n"])
         .agg(commit_s=("commit_s", "median"), open_s=("open_s", "median"),
              verify_s=("verify_s", "median"), setup_s=("setup_or_load_s", "first"),
              peak_gib=("peak_gib", "max"), passes=("pass", "count"))
         .reset_index())
agg["commit_open_s"] = agg.commit_s + agg.open_s
agg.to_csv(root / "results" / "microbench_summary.csv", index=False)
print(agg.to_string(index=False))

fits = []
for scheme, g in agg.groupby("scheme"):
    for col in ["commit_s", "open_s", "commit_open_s", "peak_gib"]:
        slope, icpt = np.polyfit(np.log2(g.n), np.log2(g[col]), 1)
        fits.append((scheme, col, slope, len(g)))
fit = pd.DataFrame(fits, columns=["scheme", "metric", "loglog_slope", "points"])
fit.to_csv(root / "results" / "scaling_fits.csv", index=False)
print(fit.to_string(index=False))

fig, axes = plt.subplots(1, 3, figsize=(14, 4))
for scheme, g in agg.groupby("scheme"):
    axes[0].plot(g.n, g.commit_s, "o-", label=f"{scheme} commit")
    axes[0].plot(g.n, g.open_s, "s--", label=f"{scheme} open")
    axes[1].plot(g.n, g.verify_s, "o-", label=scheme)
    axes[2].plot(g.n, g.peak_gib, "o-", label=scheme)
axes[0].set(title="prover-side cost", ylabel="seconds")
axes[1].set(title="verification", ylabel="seconds")
axes[2].set(title="peak RSS", ylabel="GiB")
for ax in axes:
    ax.set(xscale="log", yscale="log", xlabel="vector length n")
    ax.legend()
fig.tight_layout()
fig.savefig(plots / "microbench_scaling.png", dpi=130)

e2e_path = root / "results" / "e2e_summary.csv"
if e2e_path.exists():
    e2e = pd.read_csv(e2e_path)
    print(e2e.to_string(index=False))
