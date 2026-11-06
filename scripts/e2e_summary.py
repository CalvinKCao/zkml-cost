import csv
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
raw = root / "results" / "raw"

RUNS = [
    ("mnist", 1, "no commitment", "mnist-nocom-kzg"),
    ("mnist", 1, "artemis-style", "mnist-poly-kzg"),
    ("mnist", 1, "cp_link", "mnist-cplink-kzg"),
    ("mnist", 2, "no commitment", "mnist3-nocom"),
    ("mnist", 2, "artemis-style", "mnist3-poly"),
    ("mnist", 2, "cp_link", "mnist3-cplink"),
    ("mobilenet-truncated", 1, "no commitment", "mobilenet4-nocom"),
    ("mobilenet-truncated", 2, "no commitment", "mobilenet5-nocom"),
    ("mobilenet-truncated", 1, "artemis-style", "mobilenet5-poly"),
]

UNITS = {"ns": 1e-9, "µs": 1e-6, "ms": 1e-3, "s": 1.0}


def seconds(text):
    m = re.fullmatch(r"([\d.]+)(ns|µs|ms|s)", text.strip())
    return float(m.group(1)) * UNITS[m.group(2)]


def parse(stem):
    log = (raw / f"{stem}.log").read_text(errors="replace")
    proving = [seconds(x) for x in re.findall(r"^Proving time: (\S+)", log, re.M)]
    external = [seconds(x) for x in re.findall(r"^KZG proof time: (\S+)", log, re.M)]
    csv_path = raw / f"{stem}.csv"
    total = None
    if csv_path.exists():
        total = seconds(csv_path.read_text().splitlines()[1].split(",")[0])
    rss = None
    time_path = raw / f"{stem}.time"
    if time_path.exists():
        m = re.search(r"Maximum resident set size \(kbytes\): (\d+)", time_path.read_text())
        rss = int(m.group(1)) / 2**20 if m else None
    return proving, external, total, rss


rows = []
for model, run, config, stem in RUNS:
    proving, external, total, rss = parse(stem)
    rows.append({
        "model": model,
        "run": run,
        "config": config,
        "total_prover_s": round(total, 3),
        "halo2_proof_s": round(proving[0], 3),
        "weight_commit_open_s": round(external[0], 3) if external else 0,
        "linking_open_s": round(external[1], 3) if external else 0,
        "weight_commit_open_share": round(external[0] / total, 4) if external else 0,
        "linking_open_share": round(external[1] / total, 4) if external else 0,
        "peak_rss_gib": round(rss, 1) if rss else "",
        "source": stem,
    })

with open(root / "results" / "e2e_summary.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
for r in rows:
    print(r)
