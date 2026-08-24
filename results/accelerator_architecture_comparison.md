# Sequential vs pipelined accelerator comparison

## 1. Purpose

Both verified accelerators implement the same unsigned four-element dot product,
`a0*b0 + a1*b1 + a2*b2 + a3*b3`, with four packed 8-bit elements per input and
a 32-bit external result. This report measures the resource and cycle-performance
trade-off between iterative arithmetic reuse and a three-stage elastic pipeline.

## 2. Fair-comparison methodology

- Configuration: `ELEM_WIDTH=8`, `NUM_ELEMS=4`, `RESULT_WIDTH=32`, unsigned arithmetic.
- Both designs use the same Yosys executable and identical pre-lowering and generic synthesis passes.
- Top modules are explicitly selected and parameterized; both post-synthesis designs are flattened.
- The sequential `start/busy/done` and pipelined ready/valid interfaces are intentionally retained.
- Yosys: `Yosys 0.33 (git sha1 2584903a060)`.

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
| Inferred multipliers (`$mul`) | 1 | 4 |
| Inferred adders (`$add`) | 2 | 3 |
| Pre-lowering register cell objects (widths vary) | 8 | 10 |
| Pre-lowering mux-like cells (`$mux`/`$pmux`/`$shiftx`) | 14 | 0 |
| Pre-lowering comparator cells | 2 | 0 |
| Generic synthesized storage cells (one-bit FFs) | 132 | 119 |
| Generic synthesized mux primitives | 49 | 0 |
| Generic combinational cells | 660 | 1769 |
| Generic synthesized cells total | 792 | 1888 |

Sequential pre-lowering cells: `$mux`=8, `$adffe`=5, `$pmux`=4, `$adff`=3, `$add`=2, `$reduce_and`=2, `$shiftx`=2, `$eq`=1, `$mul`=1, `$ne`=1, `$not`=1.
The two sequential `$add` cells are the datapath accumulator addition and the
index increment; the three pipeline `$add` cells are the two pair sums and final
sum.

Pipelined pre-lowering cells: `$adffe`=10, `$mul`=4, `$add`=3, `$logic_not`=3, `$logic_or`=3, `$reduce_and`=3.

Sequential post-synthesis cells: `$_ANDNOT_`=188, `$_XOR_`=140, `$_DFFE_PN0P_`=130, `$_OR_`=81, `$_NAND_`=58, `$_MUX_`=49, `$_NOT_`=46, `$_AND_`=45, `$_XNOR_`=24, `$_ORNOT_`=17, `$_NOR_`=12, `$_DFF_PN0_`=2.

Pipelined post-synthesis cells: `$_ANDNOT_`=480, `$_XOR_`=392, `$_AND_`=239, `$_OR_`=178, `$_XNOR_`=152, `$_NAND_`=147, `$_DFFE_PN0P_`=118, `$_NOR_`=118, `$_ORNOT_`=33, `$_NOT_`=30, `$_DFFE_PN0N_`=1.

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
| Checked transactions | 100 | 100 |
| Latency (cycles) | 4 | 3 |
| Minimum initiation interval (cycles) | 5 | 1 |
| Completion interval (cycles) | 5 | 1 |
| Steady-state throughput (results/cycle) | 1/5 = 0.200 | 1/1 = 1.000 |
| N=100 first-accept-to-last-completion span | 499 cycles | 102 cycles |
| Errors/mismatches | 0 | 0 |

The measured steady-state throughput ratio is `5.000×`, computed
as `(1/1) / (1/5)`.
The separate N=100 batch speedup is `4.892×`, computed as
`499 / 102` using the
defined edge-distance span.

## 7. Interpretation

The sequential design exposes one multiplier and reuses it across elements,
trading a longer initiation interval for reduced arithmetic parallelism. Its
variable element selection and iterative state also produce mux and comparison
logic. The pipeline exposes four multipliers and three adders plus elastic-stage
storage/control. The post-synthesis storage result is nuanced: the pipeline has
119 one-bit FF cells versus
132 for the sequential design. The sequential
core stores both complete input vectors, its accumulator, its retained result,
index, and control state; the pipeline instead stores intermediate products and
sums, and Yosys removes the constant-zero upper result bits. Thus pipeline stages
do not automatically imply more total storage bits for these particular RTLs.

The pipeline's extra arithmetic parallelism permits a measured II of
1 and one completed result per cycle after fill
with `out_ready=1`.

Generic cell totals are an implementation-complexity observation, not a direct
area metric; individual generic primitives do not have equal physical area.

## 8. Area qualification

Generic Yosys resource/cell counts are used only for relative architectural
comparison. **No physical ASIC area is claimed** because no standard-cell
Liberty library or physical implementation flow is used.

## 9. Timing qualification

This comparison performs no technology-specific static timing analysis or physical
implementation. **No physical Fmax is claimed.** The simulation clock period is
only testbench scheduling and is not a silicon timing measurement.

## 10. Synthesis checks and warnings

Both explicit top-module checks passed, parameters are the intended 8/4/32
configuration, `check` reported zero structural problems at both stages, no
unintended latches were inferred, and both results retained plausible arithmetic,
storage, and output-driving logic.

- Sequential warnings: No Yosys warnings.
- Pipelined warnings: No Yosys warnings.

## 11. Tool versions

- `Yosys 0.33 (git sha1 2584903a060)`
- `Icarus Verilog version 12.0 (stable) ()`
- `Verilator 5.020 2024-01-01 rev (Debian 5.020-1)`
- `Python 3.12.3`

## 12. Reproduction

```bash
make synth-accel-seq
make synth-accel-pipe
make synth-accel
make perf-accel
make compare-accel
```
