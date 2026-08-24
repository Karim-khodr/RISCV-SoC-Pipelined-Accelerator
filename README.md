# RISC-V SoC with Pipelined Dot-Product Accelerator

This project combines a small single-cycle RISC-V CPU with a pipelined dot-product accelerator written in SystemVerilog.

The accelerator is connected to the CPU through memory-mapped I/O, so software can load the input vectors, start the accelerator, check its status, read the result, and store it back to RAM using normal `lw` and `sw` instructions.

The repository also includes self-checking testbenches, randomized verification, a Python golden model, synthesis comparison scripts, and CPU programs used to test the full hardware/software path.

## CPU

The CPU is a small educational RV32I-subset implementation.

Supported instructions include:

* `add`, `sub`, `and`, `or`, `xor`
* `addi`, `andi`, `ori`, `xori`
* `lw`, `sw`
* `beq`

Instructions such as `MUL`, shifts, jumps, `LUI`, `AUIPC`, and `SLT` are not implemented.

## Dot-product accelerator

The accelerator computes a four-element unsigned dot product:

```text
result = a0*b0 + a1*b1 + a2*b2 + a3*b3
```

Each input contains four packed 8-bit values.

Two implementations are included:

* Sequential version that reuses one multiplier
* Three-stage pipelined version that computes the products in parallel

The pipelined version was measured at:

* 3-cycle latency
* initiation interval of 1 cycle
* up to 1 result per cycle once the pipeline is full

The MMIO interface currently allows one software-visible operation at a time.

## Memory-mapped interface

The accelerator is mapped at `0x0000_0400`.

| Address       | Register  |
| ------------- | --------- |
| `0x0000_0400` | `CONTROL` |
| `0x0000_0404` | `STATUS`  |
| `0x0000_0408` | `VEC_A`   |
| `0x0000_040C` | `VEC_B`   |
| `0x0000_0410` | `RESULT`  |

The CPU writes the two input vectors, writes `START`, polls `RESULT_VALID`, then reads the result.

Normal data RAM occupies `0x0000_0000` through `0x0000_03FF`.

## Hardware/software test

The CPU-controlled program uses:

```text
A = {2,4,6,8}
B = {1,3,5,7}
```

which gives:

```text
2*1 + 4*3 + 6*5 + 8*7 = 100
```

The accelerator result, CPU-visible result, and final RAM value are all checked against `100`.

A separate CPU-only version calculates the same result using repeated addition because the CPU does not implement `MUL`.

## Verification

The project includes:

* CPU unit and program tests
* Directed accelerator tests
* Randomized pipeline testing with stalls and resets
* Scoreboarding and transaction accounting
* MMIO testing
* SoC address-routing tests
* CPU-to-accelerator-to-RAM integration testing
* Python golden-model checks
* Verilator lint

The full regression passes with no test or protocol failures.

Detailed counts are available in [results/verification_summary.md](results/verification_summary.md).

## Performance

The standalone accelerator comparison measured:

* Sequential: 4-cycle latency, II = 5, 0.2 results/cycle
* Pipelined: 3-cycle latency, II = 1, 1.0 result/cycle

The pipelined design uses four multipliers instead of one, trading more hardware for higher throughput.

For the CPU benchmark:

```text
CPU-only program:    87 cycles
Accelerated program: 17 cycles
```

For this specific benchmark, this is a `5.12x` cycle-count improvement and an `80.46%` reduction in CPU cycles.

The two programs do not use identical input representations, so this should be treated as an end-to-end result for this particular CPU and benchmark, not as a general hardware speedup.

More details are available in:

* [Accelerator architecture comparison](results/accelerator_architecture_comparison.md)
* [CPU accelerator benchmark](results/cpu_accelerator_performance.md)

## Repository structure

```text
rtl/        RTL for the CPU, memories, accelerator, and SoC
tb/         SystemVerilog testbenches
software/   CPU program listings and machine-code images
model/      Python golden model
scripts/    Regression and comparison scripts
docs/       Additional architecture notes
results/    Verification and performance results
```

## Running the tests

Run the full regression:

```bash
make test
```

Run the sequential versus pipelined comparison:

```bash
make compare-accel
```

The project uses GNU Make, Bash, Verilator, Icarus Verilog, Python 3, and Yosys.

## Current limitations

This is an educational CPU and SoC rather than a complete RISC-V system.

The design currently has:

* a limited RV32I instruction subset
* no caches
* polling-based accelerator completion
* one outstanding software-visible accelerator command
* no DMA or interrupts
* no FPGA or physical ASIC implementation

The synthesis results are generic Yosys structural comparisons, not physical timing, power, area, or PPA measurements.
