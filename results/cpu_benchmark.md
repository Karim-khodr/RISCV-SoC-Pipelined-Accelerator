# CPU and Accelerator Benchmark

This test compares two programs running on the same single-cycle RISC-V CPU. One program uses the pipelined accelerator through MMIO. The other calculates the dot product with repeated addition because the CPU does not support `MUL`.

The test vector was:

```text
A = {2, 4, 6, 8}
B = {1, 3, 5, 7}
result = 2*1 + 4*3 + 6*5 + 8*7 = 100
```

## Results

| Program | Result | CPU cycles |
| --- | ---: | ---: |
| CPU with pipelined accelerator | 100 | 17 |
| CPU-only repeated addition | 100 | 87 |

For this test, the accelerator program used 5.117647x fewer CPU cycles (`87 / 17`), or 5.12x when rounded. The cycle reduction was 80.459770%, or 80.46% when rounded.

The counter starts on the first executed instruction and includes the cycle that stores the final result in RAM. The accelerator run includes the input loads, MMIO setup, one accepted START, three STATUS reads, one RESULT read, and the final RAM store. The CPU-only run includes eight scalar loads, the repeated-add loops, and the final store. Both runs produced `100`, and the CPU-only run made no accelerator accesses.

## Limitation

The programs do not use the same input layout. The accelerator loads two packed words, while the CPU-only program loads eight 32-bit values because the CPU has no byte-unpacking shifts or multiply instruction. The 5.12x result therefore applies to this vector, CPU, program, and memory setup. It is not a general dot-product speedup or a physical timing result.

## Reproduce

```bash
make test-soc-software
```
