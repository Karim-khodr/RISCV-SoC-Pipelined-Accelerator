# Verification summary

The current repository was checked with:

```bash
make test
make compare-accel
```

## CPU

- ALU: 1,009 tests, 0 failures.
- Register file: 506 tests, 0 failures.
- Immediate generator: 1,514 tests, 0 failures.
- Decoder: 114 tests, 0 failures.
- Integrated CPU programs: 3 passed.

## Accelerators

- Sequential accelerator: 113 tests, 0 failures, including 100 randomized
  vectors and the measured 4-cycle result latency.
- Pipelined accelerator directed test: 7 tests, 0 test or protocol failures.
- Pipelined randomized test, seed 12345: 3,000 random inputs accepted; 3,013
  total inputs accepted; 2,998 outputs consumed and checked; 15 transactions
  deliberately discarded across seven reset events.
- The randomized run completed in 6,688 cycles with zero protocol failures,
  unexpected outputs, data mismatches, or timeouts. The scoreboard reached the
  full pipeline depth of three entries.

## MMIO and SoC integration

- Accelerator MMIO: 17 tests, 0 test or protocol failures. Accounting closed
  with 42 accepted START writes, 42 pipeline accepts, 41 completions, and one
  deliberate reset discard.
- SoC data fabric: 17 tests, 0 failures. Accounting closed with three accepted
  START writes, three pipeline accepts, two completions, and one deliberate
  reset discard.
- Integrated SoC RAM-only CPU program: passed with zero accelerator accesses.
- CPU-controlled accelerator program: passed with result 100 in the accelerator,
  CPU register file, and final RAM word. It completed its final RAM store in 17
  CPU cycles after one START, one pipeline accept, one completion, three STATUS
  reads, and one RESULT read.
- CPU-only repeated-add program: passed with products 2, 12, 30, and 56 and final
  result 100 in 87 CPU cycles. It made zero accelerator reads, writes, STARTs,
  pipeline accepts, or completions.
- Both tracked `.hex` program images matched the independently encoded expected
  machine words and the fixed instruction/immediate audits.

## Models, lint, and comparison

- Python golden model: 6 tests passed.
- Verilator lint: passed for CPU, accelerator, performance, MMIO, and SoC test
  targets.
- Standalone performance benches: 100 checked transactions per accelerator,
  zero mismatches.
- Yosys comparison: pre- and post-synthesis checks reported zero structural
  problems; both JSON result files validated for each architecture; no Yosys
  warnings were reported.
- Complete `make test` regression: passed.
- Complete `make compare-accel` flow: passed.
