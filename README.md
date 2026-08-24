# RISC-V SoC with a Pipelined Dot-Product and Matrix Accelerator

A SystemVerilog portfolio project that combines a verified single-cycle
RISC-V CPU baseline with a verified sequential dot-product accelerator. The
long-term goal is a memory-mapped SoC with a high-throughput pipelined
accelerator and a measured hardware/software performance study.

The repository is currently at the **Day 5 integrated-SoC checkpoint**. The
single-cycle CPU, data RAM, and pipelined dot-product MMIO peripheral now share
one decoded data address space. Accelerator-control software and comparative
CPU/accelerator measurements remain Day 6 work.

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
- Three-stage ready/valid pipelined dot-product accelerator.
- Standalone MMIO register wrapper for accelerator control and status.
- SoC data fabric with explicit RAM/MMIO decode and combinational read mux.
- Integrated `riscv_accel_soc` top level and focused Day 5 verification.
- Yosys synthesis and behavioral performance comparison of the two accelerator
  architectures.

## Planned work

- RISC-V software that controls the accelerator through `lw` and `sw`.
- Software, sequential-hardware, and pipelined-hardware performance comparison.
- Matrix-multiplication scheduling and buffering.
- Optional OpenROAD implementation.

## Current architecture

The integrated Day 5 system is:

```text
Instruction memory --> rv32i_core --> data fabric --> data RAM
                                         |
                                         +----------> MMIO accelerator
```

The data RAM occupies byte addresses `0x0000_0000`–`0x0000_03ff`. The
accelerator occupies `0x0000_0400`–`0x0000_041f`; the fabric subtracts the
base before passing byte offsets to the MMIO wrapper. Reads remain
combinational and writes remain edge-triggered, so the CPU is still
single-cycle.

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
| Pipelined accelerator directed | 7 tests, 0 failures |
| Pipelined accelerator randomized | 3,000 random accepts, 0 protocol/checker failures |
| Accelerator MMIO | 17 tests, 0 failures |
| SoC data fabric | 17 tests, 0 failures |
| SoC RAM-only CPU integration | passed |
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
make test-accel-pipe
make test-accel-pipe-random
make test-accel-mmio
make test-soc
make lint-soc
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
rtl/accelerator/pipelined/       Three-stage accelerator datapath
rtl/accelerator/mmio/            Local MMIO wrapper
rtl/soc/                         Day 5 address fabric and integrated top
tb/cpu/                          CPU unit and program tests
tb/accelerator/sequential/       Architecture A verification
tb/soc/                          Day 5 fabric and SoC integration tests
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
