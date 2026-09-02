# RISC-V SoC with Pipelined Dot-Product Accelerator

This project implements a small single-cycle RISC-V CPU connected to a dot-product accelerator in SystemVerilog. The CPU controls the accelerator through memory-mapped registers and runs a test program that stores the final result in RAM. I also compared sequential and pipelined versions of the accelerator.

## What I Built

- A single-cycle CPU supporting a small RV32I subset
- Sequential and three-stage pipelined dot-product accelerators
- A memory-mapped interface connecting the pipelined accelerator to the CPU
- Self-checking unit, randomized, and full-system testbenches

## How It Works

The accelerator calculates a four-element unsigned dot product from two packed 32-bit inputs. Each input contains four 8-bit values.

```text
result = a0*b0 + a1*b1 + a2*b2 + a3*b3
```

The accelerator registers are mapped from `0x400` to `0x410`. Software loads the vectors, starts the accelerator, polls the status register, reads the result, and writes it to RAM using normal `lw` and `sw` instructions. The CPU does not support `MUL`, so the CPU-only comparison uses repeated addition.

## Results

| Measurement | Sequential | Pipelined |
| --- | ---: | ---: |
| Latency | 4 cycles | 3 cycles |
| Initiation interval | 5 cycles | 1 cycle |
| Throughput | 0.2 results/cycle | 1.0 result/cycle |
| 100-result test | 499 cycles | 102 cycles |

The CPU-only dot-product program took 87 cycles. The program using the accelerator took 17 cycles, which was a 5.12x improvement and an 80.46% cycle reduction for this test. Both programs produced a result of `100`.

The two programs use different input layouts, so these cycle counts apply to this CPU and test program rather than a general hardware speedup. More detail is in [results/accelerator_comparison.md](results/accelerator_comparison.md) and [results/cpu_benchmark.md](results/cpu_benchmark.md).

## Testing / Verification

I tested the CPU blocks, both accelerators, the memory-mapped interface, address routing, and the full CPU-to-accelerator-to-RAM path. The randomized pipeline test accepted 3,000 random inputs and checked stalls and resets. The full regression and accelerator comparison both pass with no mismatches or protocol failures.

Detailed test counts are in [results/verification.md](results/verification.md).

## Repository Structure

```text
rtl/        CPU, memory, accelerator, and SoC RTL
tb/         SystemVerilog testbenches
software/   CPU programs and machine-code files
model/      Python golden model
scripts/    Test and comparison scripts
results/    Verification and performance results
```

## Build / Run

Run the full regression:

```bash
make test
```

Run the sequential and pipelined comparison:

```bash
make compare-accel
```

## Tools

SystemVerilog, Verilator, Icarus Verilog, Yosys, Python 3, GNU Make, and Bash.
