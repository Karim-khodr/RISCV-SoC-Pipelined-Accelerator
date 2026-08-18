# RISC-V SoC with a Pipelined Dot-Product and Matrix Accelerator

A SystemVerilog portfolio project that combines a verified single-cycle
RISC-V CPU baseline with a verified sequential dot-product accelerator. The
long-term goal is a memory-mapped SoC with a high-throughput pipelined
accelerator and a measured hardware/software performance study.

The repository is currently at the **Phase 0 verified-baseline checkpoint**.
It does not yet contain the pipelined accelerator, MMIO register block,
address decoder, or SoC top level.

## Implemented and verified

- Single-cycle RV32I subset processor.
- R-type instructions: `add`, `sub`, `and`, `or`, and `xor`.
- Immediate instructions: `addi`, `andi`, `ori`, and `xori`.
- Word memory and branch instructions: `lw`, `sw`, and `beq`.
- ALU, register-file, immediate-generator, and decoder unit tests.
- Three integrated CPU program tests.
- Bus-facing `rv32i_core` with separate instruction and data interfaces.
- Compatibility `cpu_core` wrapper with instruction and data memories.
- Architecture A: sequential four-element unsigned dot-product accelerator.
- Directed, protocol, reset, maximum-value, and randomized accelerator tests.
- Self-checking Python dot-product reference model.
- Unified lint and regression flow.

## Planned work

- Architecture B: three-stage pipelined dot-product accelerator.
- Ready/valid streaming interface and backpressure handling.
- Queue-based randomized scoreboard and temporal assertions.
- Accelerator MMIO register block.
- CPU address decoder and SoC integration.
- RISC-V software that controls the accelerator through `lw` and `sw`.
- Software, sequential-hardware, and pipelined-hardware performance comparison.
- Yosys synthesis and fair area/timing/resource comparisons.
- Matrix-multiplication scheduling and buffering.
- Optional OpenROAD implementation.

## Current architecture

The compatibility system used by the CPU regression is:

```text
Instruction memory --> rv32i_core --> data memory
                           |
                           +--> debug/status signals
```

For future SoC integration, `rv32i_core` exposes instruction address/data and
data read-enable, write-enable, address, write-data, and read-data signals.
The future address decoder will connect that data interface to RAM and MMIO
peripherals without pipelining the CPU.

The sequential accelerator computes:

```text
result = a0*b0 + a1*b1 + a2*b2 + a3*b3
```

Each vector contains four packed unsigned bytes, with element 0 in bits
`[7:0]`. The baseline performs one multiply-accumulate per cycle.

## Verification summary

| Component | Result |
|---|---:|
| ALU | 1,009 tests, 0 failures |
| Register file | 506 tests, 0 failures |
| Immediate generator | 1,514 tests, 0 failures |
| Decoder | 114 tests, 0 failures |
| CPU programs | 3 passed |
| Sequential accelerator | 113 tests, 0 failures |
| Python golden model | 6 tests passed |

See [Phase 0 baseline results](results/baseline/phase0_baseline.md) for the
original and expanded accelerator counts and the latency definitions.

## Running the project

The tested flow uses Verilator, Icarus Verilog, GNU Make, Bash, and Python 3:

```bash
make test
make lint
make clean
```

Useful individual targets include:

```bash
make test-cpu
make test-accel-seq
make test-alu
make test-regfile
make test-imm
make test-decoder
make test-cpu-core
```

An optional deterministic seed can be supplied to randomized SystemVerilog
tests:

```bash
make test-cpu TEST_ARGS=+SEED=12345
```

Build products, logs, and waveforms are isolated under `sim/` and ignored by
Git. Because Verilator's generated GNU Make flow cannot build below a path
containing spaces, the helper script stages compilation in a temporary
space-free directory and copies retained build output back to `sim/build/`.

## Repository layout

```text
rtl/cpu/                         CPU datapath and compatibility wrapper
rtl/memory/                      Instruction and data memories
rtl/accelerator/sequential/      Architecture A accelerator
tb/cpu/                          CPU unit and program tests
tb/accelerator/sequential/       Architecture A verification
model/                           Python reference models
filelists/                       Ordered synthesis/source filelists
scripts/                         Build and regression helpers
docs/                            Architecture and verification documentation
results/baseline/                Verified baseline records
sim/                             Ignored generated output
```

## Project history

This repository incorporates selected verified components from two earlier
projects while preserving those repositories unchanged. See
[project provenance](docs/architecture/project_provenance.md) for source
commits and migration details.

## License

MIT License. See [LICENSE](LICENSE).
