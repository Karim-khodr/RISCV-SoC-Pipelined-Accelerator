# Day 6 CPU-controlled accelerator performance

## Scope

This benchmark measures CPU clock cycles required by two programs running on
the same educational single-cycle RISC-V CPU model. The accelerated program
uses ordinary `lw`/`sw` MMIO operations and polls `STATUS.RESULT_VALID`; the
CPU-only program uses repeated addition because the implemented ISA has no
`MUL`. This is cycle-level RTL simulation, not wall-clock, Fmax, physical
timing, power, energy, or silicon PPA measurement.

The implemented instructions used here are `add`, `sub`, `addi`, `andi`,
`lw`, `sw`, and `beq`. The CPU has no `MUL`, `LUI`, shifts, `BNE`, `JAL`,
`JALR`, `AUIPC`, or `SLT`. Signed 12-bit I/S immediates directly reach the
global accelerator registers at `0x400` through `0x410` from `x0`.

## Benchmark and RAM map

The deterministic vector is:

```text
A = {2, 4, 6, 8}, packed as 0x08060402
B = {1, 3, 5, 7}, packed as 0x07050301
2*1 + 4*3 + 6*5 + 8*7 = 2 + 12 + 30 + 56 = 100
```

| Purpose | RAM byte address | Word index | Initial/final value |
|---|---:|---:|---:|
| Packed VEC_A | `0x000` | 0 | `0x08060402` |
| Packed VEC_B | `0x004` | 1 | `0x07050301` |
| Scalar A0 | `0x010` | 4 | 2 |
| Scalar A1 | `0x014` | 5 | 4 |
| Scalar A2 | `0x018` | 6 | 6 |
| Scalar A3 | `0x01c` | 7 | 8 |
| Scalar B0 | `0x020` | 8 | 1 |
| Scalar B1 | `0x024` | 9 | 3 |
| Scalar B2 | `0x028` | 10 | 5 |
| Scalar B3 | `0x02c` | 11 | 7 |
| Accelerated result | `0x030` | 12 | 100 after execution |
| Software result | `0x034` | 13 | 100 after execution |

`DMEM_DEPTH=256` means 256 32-bit words (1,024 bytes), so the highest Day 6
RAM address, `0x034`, is within the `0x000`-`0x3ff` RAM window.

## Execution and measurement

The files in `software/asm/` are manually synchronized human-readable listings;
they are not assembled or parsed by the build. After the memory modules'
time-zero clearing blocks have completed and while reset remains asserted, the
testbench independently constructs the expected executable words with
instruction encoders, loads each tracked `.hex` image with `$readmemh`, compares
the image word-for-word with the generated words, and checks fixed machine-code
audit values before execution. No external assembler is used.

The cycle counter starts with the rising edge that executes the instruction at
entry PC `0x0000`. The final count is captured on the rising edge that commits
the normal-RAM result store. Both boundary cycles are included. Reset cycles
and the subsequent intentional illegal-halt convention are excluded. The same
rule is used for both programs.

| Implementation | Result | CPU cycles | Notes |
|---|---:|---:|---|
| CPU-controlled pipelined accelerator | 100 | 17 | Includes packed input loads, MMIO setup, START, three STATUS reads, RESULT load, and final RAM store |
| CPU-only repeated addition | 100 | 87 | Includes eight scalar loads, all repeated-add loops, accumulation, and final RAM store |

```text
speedup = software_cycles / accelerator_cycles
        = 87 / 17
        = 5.1176470588

cycle reduction = 1 - (17 / 87)
                = 0.8045977011
                = 80.45977011%
```

Repeated identical Day 6 runs produced the same 17-cycle and 87-cycle counts
and the same three STATUS reads.

## Observed accelerated path

| Event | Observed count/value |
|---|---:|
| VEC_A writes at `0x408` | 1, data `0x08060402` |
| VEC_B writes at `0x40c` | 1, data `0x07050301` |
| CONTROL writes at `0x400` | 1, data `0x00000001` |
| STATUS reads at `0x404` | 3 |
| RESULT reads at `0x410` | 1, data 100 |
| Accepted STARTs | 1 |
| Pipeline input handshakes | 1 |
| Pipeline completion handshakes | 1 |
| Intentional reset discards | 0 |
| Other accelerator MMIO reads/writes | 0 |

The CPU RESULT register and accelerated-result RAM word both held 100.
Reading RESULT cleared `RESULT_VALID` (STATUS bit 2, mask `0x4`), cleared BUSY,
and restored READY. The CPU-only run produced products 2, 12, 30, and 56,
stored 100, and caused zero MMIO accesses, STARTs, pipeline accepts, or
completions.

## Fairness and interpretation

Both paths use preinitialized memory and calculate the same four numerical
lanes, but this is not an apples-to-apples memory-format comparison. The
accelerator path loads two packed vector words. The software path loads eight
scalar 32-bit lane words because the CPU has neither shifts for efficient byte
unpacking nor hardware `MUL`. Its straightforward repeated-add runtime also
depends on multiplier values; here the natural multipliers are 1, 3, 5, and 7.

Therefore the 5.1176470588x result is an end-to-end CPU-program cycle speedup
for this specific vector, input setup, CPU, memory representations, MMIO
policy, and final-store-inclusive endpoint. It is not a general dot-product
speedup, raw pipeline throughput, an Fmax claim, or a silicon performance
claim.

Day 3 measured standalone accelerator behavior: approximately four-cycle
latency/II=5 for the sequential architecture and three-cycle latency/II=1 for
the pipelined architecture. Day 6 is different: it includes real CPU
instruction execution, MMIO setup, STATUS polling, RESULT consumption, and
the final normal-RAM store. The Day 3 and Day 6 numbers must not be combined
or described as the same metric.
