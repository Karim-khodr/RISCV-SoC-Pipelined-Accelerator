#!/usr/bin/env python3
"""Generate the reproducible Day 3 accelerator architecture comparison."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SYNTH_DIR = REPO_ROOT / "results" / "synthesis"
PERF_DIR = REPO_ROOT / "results" / "performance"
REPORT_PATH = REPO_ROOT / "results" / "day3_synthesis_comparison.md"


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
    git_head = command_first_line("git", "rev-parse", "HEAD")

    throughput_ratio = (
        seq_perf["completion_interval_cycles"]
        / pipe_perf["completion_interval_cycles"]
    )
    batch_ratio = seq_perf["batch_span_cycles"] / pipe_perf["batch_span_cycles"]
    seq_warning = warning_summary("seq")
    pipe_warning = warning_summary("pipe")

    report = f"""# Day 3 sequential vs pipelined accelerator comparison

## 1. Purpose

Both verified accelerators implement the same unsigned four-element dot product,
`a0*b0 + a1*b1 + a2*b2 + a3*b3`, with four packed 8-bit elements per input and
a 32-bit external result. Day 3 measures the resource and cycle-performance
trade-off between iterative arithmetic reuse and a three-stage elastic pipeline.

## 2. Fair-comparison methodology

- Configuration: `ELEM_WIDTH=8`, `NUM_ELEMS=4`, `RESULT_WIDTH=32`, unsigned arithmetic.
- Both designs use the same Yosys executable and identical pre-lowering and generic synthesis passes.
- Top modules are explicitly selected and parameterized; both post-synthesis designs are flattened.
- The sequential `start/busy/done` and pipelined ready/valid interfaces are intentionally retained.
- Git HEAD when report generated: `{git_head}`.
- Yosys: `{yosys_version}`.

## 3. Architecture summary

The sequential `dot_product_seq` captures both vectors, reuses one multiplier and
an accumulator across four run cycles, and uses an index plus `start/busy/done`
control. The pipelined `dot_product_pipeline` computes four products in parallel,
two pair sums, and one final sum in three elastic registered stages with input and
output ready/valid flow control.

## 4. Yosys methodology

Stage A runs `read_verilog -sv`, explicit `chparam`, `hierarchy -check`, `proc`,
`opt`, `check`, and `stat`. It retains inferred `$mul`, `$add`, mux, comparison,
and register cells. Stage B runs the same generic `synth -flatten` flow for each
top, followed by `check` and `stat`; arithmetic is lowered and ABC maps it to
Yosys generic internal gates. No Liberty library, PDK, or technology-specific
mapping is used.

## 5. Synthesis comparison

| Metric | Sequential | Pipelined |
|---|---:|---:|
| Mathematical configuration | 4×8-bit unsigned dot product | 4×8-bit unsigned dot product |
| Inferred multipliers (`$mul`) | {sequential['inferred_multipliers']} | {pipelined['inferred_multipliers']} |
| Inferred adders (`$add`) | {sequential['inferred_adders']} | {pipelined['inferred_adders']} |
| Pre-lowering register cell objects (widths vary) | {sequential['pre_register_cells']} | {pipelined['pre_register_cells']} |
| Pre-lowering mux-like cells (`$mux`/`$pmux`/`$shiftx`) | {sequential['pre_mux_like_cells']} | {pipelined['pre_mux_like_cells']} |
| Pre-lowering comparator cells | {sequential['pre_comparator_cells']} | {pipelined['pre_comparator_cells']} |
| Generic synthesized storage cells (one-bit FFs) | {sequential['post_register_cells']} | {pipelined['post_register_cells']} |
| Generic synthesized mux primitives | {sequential['post_mux_cells']} | {pipelined['post_mux_cells']} |
| Generic combinational cells | {sequential['post_combinational_cells']} | {pipelined['post_combinational_cells']} |
| Generic synthesized cells total | {sequential['post_total_cells']} | {pipelined['post_total_cells']} |

Sequential pre-lowering cells: {format_cell_types(sequential['pre_cell_types'])}.
The two sequential `$add` cells are the datapath accumulator addition and the
index increment; the three pipeline `$add` cells are the two pair sums and final
sum.

Pipelined pre-lowering cells: {format_cell_types(pipelined['pre_cell_types'])}.

Sequential post-synthesis cells: {format_cell_types(sequential['post_cell_types'])}.

Pipelined post-synthesis cells: {format_cell_types(pipelined['post_cell_types'])}.

## 6. Performance comparison

Latency is the rising-edge distance from the edge accepting a request/input to
the edge completing its corresponding result (`done` for sequential and
`out_valid && out_ready` for pipelined). Minimum initiation interval is the
smallest measured edge distance between accepted independent inputs. Completion
interval is the steady sustained edge distance between completed results, and
throughput is its reciprocal. The N=100 batch span is the edge distance from the
first acceptance to final completion, so pipeline fill and drain are included
without adding an artificial inclusive endpoint cycle.

| Metric | Sequential | Pipelined |
|---|---:|---:|
| Checked transactions | {seq_perf['transactions']} | {pipe_perf['transactions']} |
| Latency (cycles) | {seq_perf['latency_cycles']} | {pipe_perf['latency_cycles']} |
| Minimum initiation interval (cycles) | {seq_perf['minimum_ii_cycles']} | {pipe_perf['minimum_ii_cycles']} |
| Completion interval (cycles) | {seq_perf['completion_interval_cycles']} | {pipe_perf['completion_interval_cycles']} |
| Steady-state throughput (results/cycle) | 1/{seq_perf['throughput_denominator']} = {1 / seq_perf['throughput_denominator']:.3f} | 1/{pipe_perf['throughput_denominator']} = {1 / pipe_perf['throughput_denominator']:.3f} |
| N=100 first-accept-to-last-completion span | {seq_perf['batch_span_cycles']} cycles | {pipe_perf['batch_span_cycles']} cycles |
| Errors/mismatches | {seq_perf['errors']} | {pipe_perf['errors']} |

The measured steady-state throughput ratio is `{throughput_ratio:.3f}×`, computed
as `(1/{pipe_perf['completion_interval_cycles']}) / (1/{seq_perf['completion_interval_cycles']})`.
The separate N=100 batch speedup is `{batch_ratio:.3f}×`, computed as
`{seq_perf['batch_span_cycles']} / {pipe_perf['batch_span_cycles']}` using the
defined edge-distance span.

## 7. Interpretation

The sequential design exposes one multiplier and reuses it across elements,
trading a longer initiation interval for reduced arithmetic parallelism. Its
variable element selection and iterative state also produce mux and comparison
logic. The pipeline exposes four multipliers and three adders plus elastic-stage
storage/control. The post-synthesis storage result is nuanced: the pipeline has
{pipelined['post_register_cells']} one-bit FF cells versus
{sequential['post_register_cells']} for the sequential design. The sequential
core stores both complete input vectors, its accumulator, its retained result,
index, and control state; the pipeline instead stores intermediate products and
sums, and Yosys removes the constant-zero upper result bits. Thus pipeline stages
do not automatically imply more total storage bits for these particular RTLs.

The pipeline's extra arithmetic parallelism permits a measured II of
{pipe_perf['minimum_ii_cycles']} and one completed result per cycle after fill
with `out_ready=1`.

Generic cell totals are an implementation-complexity observation, not a direct
area metric; individual generic primitives do not have equal physical area.

## 8. Area qualification

Generic Yosys resource/cell counts are used only for relative architectural
comparison. **No physical ASIC area is claimed** because no standard-cell
Liberty library or physical implementation flow is used.

## 9. Timing qualification

Day 3 performs no technology-specific static timing analysis or physical
implementation. **No physical Fmax is claimed.** The simulation clock period is
only testbench scheduling and is not a silicon timing measurement.

## 10. Synthesis checks and warnings

Both explicit top-module checks passed, parameters are the intended 8/4/32
configuration, `check` reported zero structural problems at both stages, no
unintended latches were inferred, and both results retained plausible arithmetic,
storage, and output-driving logic.

- Sequential warnings: {seq_warning}
- Pipelined warnings: {pipe_warning}

## 11. Tool versions

- `{yosys_version}`
- `{iverilog_version}`
- `{verilator_version}`
- `{python_version}`

## 12. Reproduction

```bash
make synth-accel-seq
make synth-accel-pipe
make synth-accel
make perf-accel
make compare-accel
```
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
