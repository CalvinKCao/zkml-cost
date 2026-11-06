import bisect
import re
import subprocess
import sys
from collections import Counter

import numpy as np


def load_samples(path):
    raw = np.fromfile(path, dtype=np.uint64)
    magic, base, depth, count, period_ns = (int(x) for x in raw[:5])
    rows = raw[5:].reshape(count, depth + 1)
    return base, period_ns, rows


def load_symbols(binary):
    out = subprocess.run(["nm", "-n", "-C", "-S", "--defined-only", binary],
                         capture_output=True, text=True, check=True).stdout
    addrs, sizes, names = [], [], []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        try:
            addr, size = int(parts[0], 16), int(parts[1], 16)
        except ValueError:
            continue
        addrs.append(addr)
        sizes.append(size)
        names.append(re.sub(r"::h[0-9a-f]{16}$", "", parts[3]))
    return addrs, sizes, names


def make_lookup(binary, base):
    addrs, sizes, names = load_symbols(binary)
    cache = {}

    def lookup(pc):
        hit = cache.get(pc)
        if hit is not None:
            return hit
        off = pc - base
        i = bisect.bisect_right(addrs, off) - 1
        name = "?"
        if i >= 0 and off - addrs[i] <= max(sizes[i], 1) + 0x1000:
            name = names[i]
        cache[pc] = name
        return name

    return lookup


def resolved_stacks(path, binary):
    base, period_ns, rows = load_samples(path)
    lookup = make_lookup(binary, base)
    for row in rows:
        depth = int(row[0])
        yield [lookup(int(pc)) for pc in row[1:1 + depth]]


def main():
    path, binary = sys.argv[1], sys.argv[2]
    top = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    selfs = Counter()
    total = 0
    for stack in resolved_stacks(path, binary):
        if not stack:
            continue
        total += 1
        selfs[stack[0]] += 1
    print(f"samples {total}")
    for name, n in selfs.most_common(top):
        print(f"{100 * n / total:6.2f}%  {n:8d}  {name}")


if __name__ == "__main__":
    main()
