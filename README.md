# RISC-V SoC with Pipelined Dot-Product Accelerator

This project integrates a small single-cycle RISC-V CPU, instruction and data
memory, and a memory-mapped four-element dot-product accelerator. Software
running on the CPU uses normal `lw` and `sw` instructions to write packed input
vectors, start the accelerator, poll its status, read the result, and store it
back to data RAM.

The repository includes the RTL, self-checking SystemVerilog testbenches, two
tracked CPU program images, a Python reference model, and scripts for regression,
cycle measurements, and a structural Yosys comparison.

## Architecture

```text
          +--------------------+
          | Instruction Memory |
          +---------+----------+
                    |
                    v
             +-------------+
             | RV32I-subset|
             |     CPU     |
             +------+------+
                    |
             data interface
                    |
                    v
             +-------------+
             | SoC Data    |
             | Fabric      |
             +------+------+
                   / \
                  /   \
                 v     v
          +----------+  +------------+
          | Data RAM |  | Accel MMIO |
          +----------+  +-----+------+
                              |
                              v
                       +--------------+
                       | 3-stage      |
                       | Dot Product  |
                       +--------------+
```

Instruction fetch is a direct combinational path between the CPU and
instruction memory. Loads and stores use the CPU data-memory interface. The SoC
data fabric routes each data access either to RAM or to the accelerator and
returns read data through a combinational mux.

## CPU

The processor is an educational single-cycle RV32I-subset implementation. The
decoder supports:

- R-type: `add`, `sub`, `and`, `or`, `xor`
- Immediate: `addi`, `andi`, `ori`, `xori`
- Memory: `lw`, `sw`
- Branch: `beq`

Instructions outside this subset are reported as illegal. In particular, the
CPU does not implement `MUL`, shifts, `LUI`, `BNE`, jumps, `AUIPC`, or `SLT`.

## Accelerator

Both accelerator implementations compute an unsigned dot product of four packed
8-bit elements:

```text
result = a0*b0 + a1*b1 + a2*b2 + a3*b3
```

Element 0 is stored in bits `[7:0]`. The sequential version reuses one
multiplier over four calculation cycles. The pipelined version computes four
products in parallel, forms two pair sums, and then forms the final sum in three
elastic ready/valid stages.

With continuous input traffic and an always-ready output, the pipeline has a
measured latency of 3 cycles and an initiation interval of 1 cycle. This is the
raw datapath capability. The MMIO wrapper intentionally allows one
software-visible operation at a time, so software cannot submit one command per
CPU cycle.

## Memory-mapped interface

Data RAM occupies byte addresses `0x0000_0000` through `0x0000_03ff`. The
accelerator window is `0x0000_0400` through `0x0000_041f`; reads above that
window return zero and writes are ignored.

| Address | Register | Important behavior |
|---:|---|---|
| `0x0000_0400` | `CONTROL` | Write bit 0 to start when ready |
| `0x0000_0404` | `STATUS` | Bit 0 `READY`, bit 1 `BUSY`, bit 2 `RESULT_VALID` |
| `0x0000_0408` | `VEC_A` | Packed input vector A |
| `0x0000_040c` | `VEC_B` | Packed input vector B |
| `0x0000_0410` | `RESULT` | Completed 32-bit result |

The normal sequence is to write `VEC_A`, write `VEC_B`, write `CONTROL.START`,
poll `STATUS.RESULT_VALID`, and read `RESULT`. Reading a valid result consumes
the completion and makes the wrapper ready for another command.

## Hardware/software flow

The accelerated test program loads packed vectors from RAM, writes them to the
MMIO registers, starts the accelerator, polls `RESULT_VALID` with `lw`, `andi`,
and `beq`, reads the result, and stores it at RAM address `0x30`. For
`A={2,4,6,8}` and `B={1,3,5,7}`, the accelerator result, CPU register result,
and final RAM value are all checked against 100.

The CPU-only reference program computes the same value with repeated addition
because the CPU does not implement `MUL`. It uses scalar lane values and is
checked to make zero accelerator reads, writes, starts, pipeline accepts, and
completions.

The `.S` files under `software/asm/` are manually synchronized readable
listings; the build does not assemble them. The testbench independently encodes
the expected machine words, loads the tracked `.hex` images, compares every word,
and checks important instruction values, MMIO immediates, and branch offsets.

## Verification

The regression covers CPU ALU, register file, immediate generation, decoding,
and three CPU programs; sequential and pipelined accelerator behavior;
randomized pipeline traffic with stalls and resets; MMIO protocol behavior; SoC
address routing; RAM-only CPU execution through the SoC; and the complete
CPU-to-accelerator-to-RAM software path. Transaction accounting and protocol
checkers verify that accepted work is either completed or deliberately discarded
by reset.

The regression also includes Verilator lint and the six-case Python golden model.
See [verification summary](results/verification_summary.md) for the measured
counts from the final repository state.

## Performance

The standalone architecture comparison checks 100 transactions per design:

| Metric | Sequential | Pipelined |
|---|---:|---:|
| Latency | 4 cycles | 3 cycles |
| Initiation interval | 5 cycles | 1 cycle |
| Steady-state throughput | 0.200 results/cycle | 1.000 result/cycle |
| Generic Yosys cells | 792 | 1,888 |

The pipelined RTL infers four multipliers and three adders, compared with one
multiplier and two adders in the sequential RTL. These are structural Yosys
results from generic synthesis, not physical area, timing, power, or PPA
measurements. Details are in the
[accelerator architecture comparison](results/accelerator_architecture_comparison.md).

For the implemented four-element CPU benchmark, the accelerated program reaches
its final RAM store in 17 CPU cycles while the repeated-add software program
takes 87 cycles. For this specific benchmark, `87/17 = 5.12x`, corresponding to
an 80.46% reduction in CPU cycles.

This benchmark compares the complete programs as implemented. The accelerated
program loads two packed words, while the CPU-only program loads eight scalar
values because this CPU lacks both shifts for convenient packed-byte extraction
and `MUL`. It is not a general dot-product, wall-clock, Fmax, or silicon speedup
claim. See [CPU benchmark results](results/cpu_accelerator_performance.md) for
the measurement boundaries and transaction counts.

## Repository structure

```text
rtl/cpu/          CPU datapath, decoder, ALU, and register file
rtl/memory/       Instruction and data memories
rtl/accelerator/  Sequential, pipelined, and MMIO accelerator RTL
rtl/soc/          Address fabric and integrated SoC top level
tb/               Self-checking SystemVerilog testbenches
software/         Readable assembly listings and tracked program images
model/            Python golden model
filelists/        Ordered simulation source lists
scripts/          Regression, performance, and synthesis helpers
synth/            Yosys scripts
docs/             Additional architecture notes
results/          Verification, benchmark, and synthesis results
```

## Running the tests

The tested flow uses GNU Make, Bash, Verilator, Icarus Verilog, Python 3, and
Yosys. Run the full simulation and lint regression with:

```bash
make test
```

Run the separate accelerator performance and structural synthesis comparison
with:

```bash
make compare-accel
```

Individual targets such as `make test-cpu`, `make test-accel-pipe-random`,
`make test-soc-software`, and `make lint` are also available. Randomized
pipeline testing can be reproduced with a different seed using:

```bash
make test-accel-pipe-random SEED=98765 RANDOM_TXNS=3000
```

Generated build files, logs, and waveforms are kept under `sim/` and ignored by
Git. The Verilator helper stages compilation in a temporary path without spaces
because the repository path may contain spaces.

## Limitations and possible future work

The CPU implements only the instruction subset listed above and has no caches.
Accelerator completion is polling-based, and the MMIO wrapper has no interrupt,
DMA, or command queue. Measurements are from RTL simulation and generic Yosys
synthesis; no FPGA or physical ASIC implementation, Fmax, power, or physical PPA
results are included.

Possible extensions include broader RISC-V instruction support,
interrupt-driven completion, command/result buffering, a standard interconnect,
and FPGA implementation.
