# Project Provenance

This repository combines components from two earlier projects.

## CPU

- Source: [RISC-V-CPU-Core](https://github.com/Karim-khodr/RISC-V-CPU-Core)
- Commit: `73052ea31d7bfe7774978fcfb7c342686790b56e`
- Used here: CPU package, ALU, register file, immediate generator, decoder, memories, CPU RTL, and testbenches

The CPU datapath is now in `rv32i_core`. `cpu_core` remains as the standalone compatibility wrapper used by the original CPU tests.

## Sequential Accelerator

- Source: [RISC-V Hardware Acceleration Matrix Multiply Dot Product Coprocessor](https://github.com/Karim-khodr/RISC-V-Hardware-Acceleration-Matrix-Multiply-Dot-Product-Coprocessor)
- Commit: `34365622f02aeedbfe9baf822f5ded4cc3b61616`
- Used here: sequential dot-product RTL, its testbench, and the Python reference model

The sequential accelerator is kept as the baseline for comparison with the pipelined design developed in this repository.
