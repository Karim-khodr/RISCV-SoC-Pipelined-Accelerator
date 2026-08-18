# Bus-facing CPU architecture

## Purpose

`rv32i_core` separates the single-cycle processor datapath from instruction
and data storage. This gives the future SoC direct access to CPU memory
transactions without changing instruction behavior or adding a pipeline.

## Interfaces

The instruction interface is combinational:

- `imem_addr`: current 32-bit byte address.
- `imem_rdata`: 32-bit instruction returned by instruction memory.

The data interface contains:

- `dmem_re`: asserted for a valid word load.
- `dmem_we`: asserted for a valid word store.
- `dmem_addr`: ALU-generated 32-bit byte address.
- `dmem_wdata`: register operand written by a store.
- `dmem_rdata`: combinational word-load result.

There is no ready/stall signal in Phase 0. Memories and future initial MMIO
targets must therefore provide zero-wait-state reads and accept writes on the
request edge.

## Compatibility wrapper

`cpu_core` retains the original top-level ports and instantiates:

```text
instr_mem --> rv32i_core --> data_mem
```

This wrapper preserves the existing CPU program regression. Future
`riscv_accel_soc` integration will instantiate `rv32i_core` directly and
place an address decoder on its data interface.
