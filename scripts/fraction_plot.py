from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

root = Path(__file__).resolve().parent.parent
res = root / "results"
micro = pd.read_csv(res / "microbench_summary.csv")
e2e = pd.read_csv(res / "e2e_summary.csv")
art = e2e[e2e.config == "artemis-style"].copy()
art["domain"] = art.model.map({"mnist": 2**15, "mobilenet-truncated": 2**23})
art["per_open_s"] = art.weight_commit_open_s

fig, ax = plt.subplots(figsize=(6, 4))
for scheme, g in micro.groupby("scheme"):
    ax.plot(g.n, g.commit_open_s, "o-", label=f"{scheme.upper()} microbenchmark, commit + open")
ax.plot(art.domain, art.per_open_s, "k*", ms=12, label="weight commit + open inside the full proof")
ax.set(xscale="log", yscale="log", xlabel="vector length, or circuit size 2^k for the full proofs",
       ylabel="seconds")
ax.legend(fontsize=8)
fig.tight_layout()
fig.savefig(res / "plots" / "open_time_vs_size.png", dpi=130)

base = e2e[e2e.config == "no commitment"].groupby("model").total_prover_s.mean()
labels, halo2, wco, link = [], [], [], []
for _, r in art.iterrows():
    b = base[r.model]
    labels.append(f"{r.model.replace('-truncated', '')}\nrun {r.run}")
    halo2.append(r.halo2_proof_s / b)
    wco.append(r.weight_commit_open_s / b)
    link.append(r.linking_open_s / b)
fig, ax = plt.subplots(figsize=(6, 4))
ax.bar(labels, halo2, label="halo2 proof, with Artemis columns", color="#2a7")
ax.bar(labels, link, bottom=halo2, label="linking opening", color="#27c")
ax.bar(labels, wco, bottom=[h + l for h, l in zip(halo2, link)], label="weight commit + open", color="#c52")
ax.axhline(1.0, color="k", lw=0.6, ls=":")
ax.set(ylabel="prover time / mean time without commitment")
ax.legend(fontsize=8, loc="upper right")
fig.tight_layout()
fig.savefig(res / "plots" / "e2e_breakdown.png", dpi=130)
