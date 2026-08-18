# Phase 0 verified baseline

## CPU

The migrated and subsequently bus-refactored single-cycle CPU passes:

| Test | Tests | Failures |
|---|---:|---:|
| ALU | 1,009 | 0 |
| Register file | 506 | 0 |
| Immediate generator | 1,514 | 0 |
| Decoder | 114 | 0 |
| CPU Program 1 | PASS | 0 |
| CPU Program 2 | PASS | 0 |
| CPU Program 3 | PASS | 0 |

The CPU programs were rerun after extracting `rv32i_core`; architectural
results were unchanged.

## Sequential dot-product accelerator

The original migrated regression was reproduced before testbench expansion:

| Checkpoint | Tests | Failures |
|---|---:|---:|
| Original Architecture A baseline | 109 | 0 |
| Expanded Phase 0 verification | 113 | 0 |

The expanded suite preserves the original directed and 100 randomized vector
tests and adds explicit checks for:

- Four-clock acceptance-to-result latency.
- Earliest legal restart and back-to-back operation.
- Level-sensitive held-high `start` behavior.
- Reset during an active operation and post-reset recovery.

Existing checks also cover reset state, maximum operands, `start` while busy,
one-clock `done`, result correctness, and result stability.

## Latency and throughput terminology

For the default four-element sequential state machine:

- **Result latency:** 4 clock intervals from accepted `start` to registered
  result with `done=1`.
- **Minimum initiation interval:** 5 clocks between accepted operations.

The fifth clock arises because the acceptance edge captures and initializes
the request; the four following edges perform the multiply-accumulate steps.
The next operation can be accepted on the first edge after completion.

## Python model

The Python golden model passes six fixed, self-checking examples. Assertion
failure produces a nonzero process exit.
