# Verification Results

The full test and comparison flows pass:

```bash
make test
make compare-accel
```

## CPU

| Test | Checks | Result |
| --- | ---: | --- |
| ALU | 1,009 | PASS |
| Register file | 506 | PASS |
| Immediate generator | 1,514 | PASS |
| Decoder | 114 | PASS |
| Integrated CPU programs | 3 | PASS |

## Accelerator and SoC

| Test | Result |
| --- | --- |
| Sequential accelerator | 113 checks, 0 failures |
| Pipelined accelerator directed test | 7 checks, 0 failures |
| Accelerator MMIO | 17 checks, 0 failures |
| SoC data fabric | 17 checks, 0 failures |
| RAM-only CPU program | PASS, no accelerator accesses |
| CPU-controlled accelerator program | PASS, result 100 in the accelerator, CPU register, and RAM |
| CPU-only repeated-add program | PASS, result 100 in RAM and no accelerator accesses |
| Python golden model | 6 checks passed |
| Performance benches | 100 results checked per accelerator, 0 mismatches |
| Verilator lint | PASS |
| Yosys structural checks | PASS, no warnings |

The tracked machine-code files were also checked against independently encoded instructions before the CPU programs ran.

## Randomized Pipeline Test

The randomized test used ready/valid backpressure, output stalls, bubbles, simultaneous input/output transfers, and resets with data in flight.

| Measurement | Result |
| --- | ---: |
| Seed | 12345 |
| Random inputs accepted | 3,000 |
| Total inputs accepted | 3,013 |
| Outputs consumed and checked | 2,998 |
| Transactions discarded by reset | 15 |
| Reset events | 7 |
| Test cycles | 6,688 |
| Maximum scoreboard depth | 3 |
| Maximum stalled-valid run | 38 cycles |
| Protocol failures | 0 |
| Unexpected outputs | 0 |
| Data mismatches | 0 |
| Timeouts | 0 |

The test reached the full three-entry pipeline depth and checked recovery after resets. Accepted transactions balanced with checked outputs and the transactions deliberately discarded by reset.

Run this test by itself with:

```bash
make test-accel-pipe-random
```
