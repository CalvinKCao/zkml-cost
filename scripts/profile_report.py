import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / "profiler"))
from resolve import load_samples, resolved_stacks

PROFILES = [
    ("mnist-nocom", "time_circuit"),
    ("mnist-poly", "time_circuit"),
    ("mnist-cplink", "time_circuit"),
    ("kzg-k20", "commit_microbench"),
    ("kzg-k22", "commit_microbench"),
    ("ipa-k18", "commit_microbench"),
    ("ipa-k20", "commit_microbench"),
    ("mobilenet-nocom", "time_circuit"),
    ("mobilenet-poly", "time_circuit"),
]

MSM = re.compile(r"multiexp|msm", re.I)
FFT = re.compile(r"fft", re.I)
COLLAPSE = re.compile(r"generator_collapse")
MAIN = re.compile(r"time_circuit::main|commit_microbench::main|::bench_(kzg|ipa)")


def classify(stack):
    if any(COLLAPSE.search(f) for f in stack):
        return "ipa_collapse"
    if any(MSM.search(f) for f in stack):
        return "msm"
    if any(FFT.search(f) for f in stack):
        return "fft"
    return "other"


def tally(path, binary):
    cats, selfs = Counter(), Counter()
    main_thread = total = 0
    for stack in resolved_stacks(path, binary):
        if not stack:
            continue
        total += 1
        cats[classify(stack)] += 1
        selfs[stack[0]] += 1
        if any(MAIN.search(f) for f in stack):
            main_thread += 1
    return cats, selfs, main_thread, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bindir")
    args = ap.parse_args()
    bindir = Path(args.bindir)
    rows = []
    top_lines = []
    for name, binary in PROFILES:
        path = root / "results" / "raw" / f"prof-{name}.bin"
        if not path.exists():
            continue
        _, period_ns, _ = load_samples(path)
        cats, selfs, main_thread, total = tally(path, bindir / binary)
        note = ""
        loadonly = root / "results" / "raw" / f"prof-{name}-loadonly.bin"
        if loadonly.exists():
            lcats, lselfs, lmain, ltotal = tally(loadonly, bindir / binary)
            cats = cats - lcats
            selfs = selfs - lselfs
            main_thread = max(main_thread - lmain, 0)
            total = total - ltotal
            note = "load-only profile subtracted"
        elif name.startswith("kzg-"):
            note = "includes parameter loading"
        cpu_s = total * period_ns / 1e9
        row = {"profile": name, "samples": total, "cpu_seconds": round(cpu_s, 1)}
        for key in ("msm", "fft", "ipa_collapse", "other"):
            row[f"{key}_pct"] = round(100 * cats[key] / total, 1)
        row["main_thread_pct"] = round(100 * main_thread / total, 1)
        row["note"] = note
        rows.append(row)
        top_lines.append(f"== {name} ({total} samples, {cpu_s:.0f} cpu-s) {note}")
        for sym, n in selfs.most_common(8):
            top_lines.append(f"{100 * n / total:6.2f}%  {sym[:140]}")
    out = root / "results"
    with open(out / "profile_shares.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    (out / "profile_top_self.txt").write_text("\n".join(top_lines) + "\n")
    print("\n".join(top_lines))

    fig, ax = plt.subplots(figsize=(9, 4))
    plotted = [r for r in rows if r["note"] != "includes parameter loading"]
    names = [r["profile"] for r in plotted]
    bottom = [0] * len(plotted)
    palette = [("msm_pct", "#2a7"), ("fft_pct", "#c52"), ("ipa_collapse_pct", "#27c"), ("other_pct", "#888")]
    for key, color in palette:
        vals = [r[key] for r in plotted]
        ax.bar(names, vals, bottom=bottom, label=key[:-4], color=color)
        bottom = [b + v for b, v in zip(bottom, vals)]
    ax.set(ylabel="% of CPU samples", title="Sampled CPU time by work type")
    ax.legend(loc='center left', bbox_to_anchor=(1.01, 0.5))
    ax.tick_params(axis="x", rotation=30)
    fig.tight_layout()
    fig.savefig(out / "plots" / "profile_shares.png", dpi=130)


main()
