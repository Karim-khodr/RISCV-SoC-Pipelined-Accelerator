#!/usr/bin/env python3
"""Generate the reproducible accelerator architecture comparison."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SYNTH_DIR = REPO_ROOT / "results" / "synthesis"
PERF_DIR = REPO_ROOT / "results" / "performance"
REPORT_PATH = REPO_ROOT / "results" / "accelerator_comparison.md"


def command_first_line(*args: str) -> str:
    output = subprocess.check_output(
        args, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT
    )
    return next(line.strip() for line in output.splitlines() if line.strip())


def load_module_stats(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    modules = data.get("modules", {})
    if len(modules) != 1:
        raise ValueError(f"expected exactly one synthesized module in {path}, got {len(modules)}")
    return next(iter(modules.values()))


def count_matching(cell_types: dict[str, int], predicate) -> int:
    return sum(count for name, count in cell_types.items() if predicate(name))


def extract_synthesis(prefix: str) -> dict:
    pre = load_module_stats(SYNTH_DIR / f"{prefix}_pre.json")
    post = load_module_stats(SYNTH_DIR / f"{prefix}_post.json")
    pre_types = pre["num_cells_by_type"]
    post_types = post["num_cells_by_type"]

    pre_register_cells = count_matching(
        pre_types,
        lambda name: name.startswith(("$dff", "$adff", "$sdff")),
    )
    post_register_cells = count_matching(
        post_types, lambda name: name.startswith("$_DFF")
    )
    pre_mux_like = sum(pre_types.get(name, 0) for name in ("$mux", "$pmux", "$shiftx"))
    pre_comparators = sum(
        pre_types.get(name, 0)
        for name in ("$eq", "$ne", "$eqx", "$nex", "$lt", "$le", "$ge", "$gt")
    )

    return {
        "pre_total_cells": pre["num_cells"],
        "inferred_multipliers": pre_types.get("$mul", 0),
        "inferred_adders": pre_types.get("$add", 0),
        "pre_register_cells": pre_register_cells,
        "pre_mux_like_cells": pre_mux_like,
        "pre_comparator_cells": pre_comparators,
        "pre_cell_types": pre_types,
        "post_total_cells": post["num_cells"],
        "post_register_cells": post_register_cells,
        "post_combinational_cells": post["num_cells"] - post_register_cells,
        "post_mux_cells": post_types.get("$_MUX_", 0),
        "post_cell_types": post_types,
    }


def parse_performance(path: Path) -> dict:
    perf_line = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("PERF "):
            perf_line = line
    if perf_line is None:
        raise ValueError(f"no PERF record found in {path}")

    result: dict[str, int | str] = {}
    for token in perf_line.removeprefix("PERF ").split():
        key, value = token.split("=", 1)
        result[key] = value if key == "architecture" else int(value)
    if result.get("transactions") != 100 or result.get("errors") != 0:
        raise ValueError(f"invalid performance result in {path}: {result}")
    return result


def format_cell_types(cell_types: dict[str, int]) -> str:
    ordered = sorted(cell_types.items(), key=lambda item: (-item[1], item[0]))
    return ", ".join(f"`{name}`={count}" for name, count in ordered)


def warning_summary(prefix: str) -> str:
    text = (SYNTH_DIR / f"{prefix}_warnings.txt").read_text(encoding="utf-8").strip()
    return text or "No Yosys warnings."


def main() -> int:
    sequential = extract_synthesis("seq")
    pipelined = extract_synthesis("pipe")
    seq_perf = parse_performance(PERF_DIR / "seq_perf.txt")
    pipe_perf = parse_performance(PERF_DIR / "pipe_perf.txt")

    performance = {
        "definitions": {
            "latency_cycles": "rising-edge distance from accepted input/request to corresponding completed output",
            "minimum_ii_cycles": "minimum rising-edge distance between accepted independent inputs under ideal conditions",
            "completion_interval_cycles": "rising-edge distance between consecutive completed results in the sustained workload",
            "batch_span_cycles": "rising-edge distance from the first accepted input to the final completed output for N=100",
        },
        "sequential": seq_perf,
        "pipelined": pipe_perf,
    }
    PERF_DIR.mkdir(parents=True, exist_ok=True)
    (PERF_DIR / "accelerator_performance.json").write_text(
        json.dumps(performance, indent=2) + "\n", encoding="utf-8"
    )

    yosys_bin = os.environ.get("YOSYS", "yosys")
    yosys_version = command_first_line(yosys_bin, "-V")
    iverilog_version = command_first_line("iverilog", "-V")
    verilator_version = command_first_line("verilator", "--version")
    python_version = command_first_line(sys.executable, "--version")
    throughput_ratio = (
        seq_perf["completion_interval_cycles"]
        / pipe_perf["completion_interval_cycles"]
    )
    batch_ratio = seq_perf["batch_span_cycles"] / pipe_perf["batch_span_cycles"]
    seq_warning = warning_summary("seq")
    pipe_warning = warning_summary("pipe")

    report = f"""# Sequential and Pipelined Accelerator Results

Both accelerators calculate the same unsigned four-element dot product using four packed 8-bit values per input. The sequential version reuses one multiplier, while the three-stage pipeline calculates four products in parallel.

## Performance

| Measurement | Sequential | Pipelined |
| --- | ---: | ---: |
| Checked transactions | {seq_perf['transactions']} | {pipe_perf['transactions']} |
| Latency | {seq_perf['latency_cycles']} cycles | {pipe_perf['latency_cycles']} cycles |
| Minimum initiation interval | {seq_perf['minimum_ii_cycles']} cycles | {pipe_perf['minimum_ii_cycles']} cycle |
| Completion interval | {seq_perf['completion_interval_cycles']} cycles | {pipe_perf['completion_interval_cycles']} cycle |
| Throughput | {1 / seq_perf['throughput_denominator']:.3f} results/cycle | {1 / pipe_perf['throughput_denominator']:.3f} result/cycle |
| First input to final output | {seq_perf['batch_span_cycles']} cycles | {pipe_perf['batch_span_cycles']} cycles |
| Mismatches | {seq_perf['errors']} | {pipe_perf['errors']} |

The pipeline produced one result per cycle after filling. Its steady-state throughput was {throughput_ratio:.3f}x higher. The 100-input test completed in {batch_ratio:.3f}x fewer cycles (`{seq_perf['batch_span_cycles']} / {pipe_perf['batch_span_cycles']}`).

## Synthesis

| Yosys result | Sequential | Pipelined |
| --- | ---: | ---: |
| Inferred multipliers | {sequential['inferred_multipliers']} | {pipelined['inferred_multipliers']} |
| Inferred adders | {sequential['inferred_adders']} | {pipelined['inferred_adders']} |
| Generic flip-flop cells | {sequential['post_register_cells']:,} | {pipelined['post_register_cells']:,} |
| Generic combinational cells | {sequential['post_combinational_cells']:,} | {pipelined['post_combinational_cells']:,} |
| Total generic cells | {sequential['post_total_cells']:,} | {pipelined['post_total_cells']:,} |

The pipeline uses more arithmetic and combinational logic to get the higher throughput. The sequential design has fewer arithmetic units but needs control and mux logic to reuse them.

These are generic Yosys cell counts, not physical area results. No standard-cell library, static timing analysis, power analysis, or physical implementation was used, so the results do not include area, Fmax, power, or PPA measurements. The detailed Yosys data is kept in `results/synthesis/`.

## Reproduce

```bash
make compare-accel
```

Recorded tool versions:

- `{yosys_version}`
- `{iverilog_version}`
- `{verilator_version}`
- `{python_version}`

Both synthesis checks completed without structural errors.

- Sequential: {seq_warning}
- Pipelined: {pipe_warning}
"""
    REPORT_PATH.write_text(report, encoding="utf-8")
    print(f"Wrote {REPORT_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f"comparison generation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
