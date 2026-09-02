# Sequential and Pipelined Accelerator Results

Both accelerators calculate the same unsigned four-element dot product using four packed 8-bit values per input. The sequential version reuses one multiplier, while the three-stage pipeline calculates four products in parallel.

## Performance

| Measurement | Sequential | Pipelined |
| --- | ---: | ---: |
| Checked transactions | 100 | 100 |
| Latency | 4 cycles | 3 cycles |
| Minimum initiation interval | 5 cycles | 1 cycle |
| Completion interval | 5 cycles | 1 cycle |
| Throughput | 0.200 results/cycle | 1.000 result/cycle |
| First input to final output | 499 cycles | 102 cycles |
| Mismatches | 0 | 0 |

The pipeline produced one result per cycle after filling. Its steady-state throughput was 5.000x higher. The 100-input test completed in 4.892x fewer cycles (`499 / 102`).

## Synthesis

| Yosys result | Sequential | Pipelined |
| --- | ---: | ---: |
| Inferred multipliers | 1 | 4 |
| Inferred adders | 2 | 3 |
| Generic flip-flop cells | 132 | 119 |
| Generic combinational cells | 660 | 1,769 |
| Total generic cells | 792 | 1,888 |

The pipeline uses more arithmetic and combinational logic to get the higher throughput. The sequential design has fewer arithmetic units but needs control and mux logic to reuse them.

These are generic Yosys cell counts, not physical area results. No standard-cell library, static timing analysis, power analysis, or physical implementation was used, so the results do not include area, Fmax, power, or PPA measurements. The detailed Yosys data is kept in `results/synthesis/`.

## Reproduce

```bash
make compare-accel
```

Recorded tool versions:

- `Yosys 0.33 (git sha1 2584903a060)`
- `Icarus Verilog version 12.0 (stable) ()`
- `Verilator 5.020 2024-01-01 rev (Debian 5.020-1)`
- `Python 3.12.3`

Both synthesis checks completed without structural errors.

- Sequential: No Yosys warnings.
- Pipelined: No Yosys warnings.
