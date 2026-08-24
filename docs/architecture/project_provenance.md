# Project provenance

This combined repository was created from selected verified components in two
earlier repositories. The original repositories remain separate and were
treated as read-only historical references during migration.

## CPU source

- Repository: [RISC-V-CPU-Core](https://github.com/Karim-khodr/RISC-V-CPU-Core)
- Source commit: `73052ea31d7bfe7774978fcfb7c342686790b56e`
- Migrated content: CPU package, ALU, register file, immediate generator,
  decoder, instruction memory, data memory, integrated CPU, and their
  verification testbenches.
- Role here: verified single-cycle RV32I-subset system foundation.

The original RTL was first copied without functional changes and its known
regression was reproduced. The processor datapath was then extracted into
`rv32i_core`, while `cpu_core` became a compatibility wrapper containing the
original memories. All original CPU tests still pass after this separation.

## Accelerator source

- Repository:
  [RISC-V Hardware Acceleration Matrix Multiply Dot Product Coprocessor](https://github.com/Karim-khodr/RISC-V-Hardware-Acceleration-Matrix-Multiply-Dot-Product-Coprocessor)
- Source commit: `34365622f02aeedbfe9baf822f5ded4cc3b61616`
- Migrated content: standalone sequential dot-product RTL, its SystemVerilog
  testbench, and the Python reference model.
- Role here: **Architecture A**, the verified low-area sequential baseline.

The accelerator module and testbench were renamed to `dot_product_seq` and
`dot_product_seq_tb` to make the architectural role explicit. The original
109-test regression was reproduced before verification was expanded.

## Deliberately not migrated

Empty or unfinished accelerator register-wrapper, top-level, testbench,
synthesis, and report placeholders were not treated as implementations.
Generated build products, waveforms, binaries, and logs were also excluded.

## Current combined architecture

The repository now contains both the sequential baseline and a three-stage
ready/valid pipelined dot-product accelerator. The pipelined design is connected
to an MMIO wrapper and an SoC data fabric so CPU software can control it through
loads and stores. Matrix multiplication and a physical implementation flow are
not part of the current design.
