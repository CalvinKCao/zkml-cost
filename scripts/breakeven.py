import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

root = Path(__file__).resolve().parent.parent
res = root / "results"

e2e = pd.read_csv(res / "e2e_summary.csv")
micro = pd.read_csv(res / "microbench_summary.csv")
shares = pd.read_csv(res / "profile_shares.csv").set_index("profile")


def micro_commit_open(k):
    row = micro[(micro.scheme == "kzg") & (micro.k == k)].iloc[0]
    return row.commit_open_s


settings = []
for _, r in e2e[e2e.config == "artemis-style"].iterrows():
    label = "MNIST" if r.model == "mnist" else "MobileNet"
    settings.append((f"{label} run {r.run}, weight commit and open", r.weight_commit_open_share))
    settings.append((f"{label} run {r.run}, commit and open plus linking open",
                     r.weight_commit_open_share + r.linking_open_share))

mob = e2e[(e2e.model == "mobilenet-truncated") & (e2e.config == "artemis-style")].iloc[0]
for k, tag in [(22, "2^22"), (24, "2^24")]:
    settings.append((f"MobileNet, microbenchmark commit and open at {tag}",
                     micro_commit_open(k) / mob.total_prover_s))

msm = shares.loc["mobilenet-poly", "msm_pct"] / 100
settings.append(("MobileNet, all MSM samples in the profile", msm))

TARGETS = [0.25, 0.5, 0.9]
rows = []
for name, f in settings:
    row = {"setting": name, "commit_share_now": round(f, 4)}
    for p in TARGETS:
        need = (1 - f) / f * p / (1 - p)
        row[f"speedup_for_{int(p * 100)}pct"] = round(need, 1) if need > 1 else "already above"
    rows.append(row)

with open(res / "breakeven.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
print(pd.DataFrame(rows).to_string(index=False))

s = np.logspace(0, 3, 200)
fig, ax = plt.subplots(figsize=(8, 4.5))
for name, f in [x for x in settings if not x[0].startswith('MNIST run 2') and 'plus linking' not in x[0]]:
    ax.plot(s, f / (f + (1 - f) / s), label=name)
ax.axhline(0.5, color="k", lw=0.6, ls=":")
ax.set(xscale="log", xlabel="base-proof speedup s (commitment time held fixed)",
       ylabel="commitment share of prover time",
       title="Arithmetic on measured shares, not a measurement")
ax.legend(fontsize=8, loc='lower right')
fig.tight_layout()
fig.savefig(res / "plots" / "breakeven.png", dpi=130)
