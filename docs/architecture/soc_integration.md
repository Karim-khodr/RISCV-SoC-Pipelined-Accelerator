# Single-cycle CPU and accelerator SoC integration

## Purpose

`riscv_accel_soc` connects the verified single-cycle CPU to normal data RAM
and the verified dot-product MMIO peripheral through one byte-addressed data
space. `soc_data_fabric` owns global address decoding, request gating, the
global-to-local MMIO translation, and the combinational CPU read-data mux.

```text
              +----------------------+
              |     RISC-V CPU       |
              |    SINGLE CYCLE      |
              +----------+-----------+
                         |
                         | dmem interface
                         v
                +----------------+
                | DATA ADDRESS   |
                | DECODER / MUX  |
                +----------------+
                    /         \
                   /           \
                  v             v
          +-------------+   +----------------+
          |  DATA RAM   |   | MMIO WRAPPER   |
          +-------------+   +-------+--------+
                                    |
                                    v
                             +-------------+
                             | PIPELINED   |
                             | DOT PRODUCT |
                             +-------------+
```

Instruction fetch remains a direct combinational connection between
`rv32i_core` and `instr_mem`. Testbenches can initialize `u_imem.mem` through
the same hierarchy used by the existing CPU regression.

## System memory map

All boundaries below are inclusive and use byte addresses.

| System region | Start address | End address | Size | Purpose |
|---|---:|---:|---:|---|
| Data RAM | `0x0000_0000` | `0x0000_03ff` | 1,024 bytes | 256 32-bit words; highest aligned word starts at `0x0000_03fc` |
| Accelerator | `0x0000_0400` | `0x0000_041f` | 32 bytes | Dot-product MMIO window |
| Unmapped | `0x0000_0420` | `0xffff_ffff` | remainder | Reads return zero; writes are ignored |

The CPU is word-only. Normal software accesses use aligned addresses even
though decode windows are stated as byte ranges.

## Accelerator global register map

| Register | Global CPU address | Local MMIO offset | Access |
|---|---:|---:|:---:|
| `CONTROL` | `0x0000_0400` | `0x00` | WO |
| `STATUS` | `0x0000_0404` | `0x04` | RO |
| `VEC_A` | `0x0000_0408` | `0x08` | RW |
| `VEC_B` | `0x0000_040c` | `0x0c` | RW |
| `RESULT` | `0x0000_0410` | `0x10` | RO |

Offsets `0x14` through `0x1f` are reserved inside the selected window. The
existing MMIO wrapper returns zero for unknown offsets and ignores writes.

## Accelerator base rationale

The implemented constants are:

```text
ACCEL_BASE         = 0x0000_0400
ACCEL_WINDOW_BYTES = 0x0000_0020
ACCEL_END          = 0x0000_041f  (inclusive)
```

The 256-word RAM occupies exactly `0x0000_0000` through `0x0000_03ff`, so the
base is the first clean power-of-two boundary outside RAM. A 32-byte window is
also power-of-two aligned and covers the highest implemented register offset,
`0x10`, without reserving an unnecessarily large region.

The decoder implements no `LUI`, `AUIPC`, `JAL`, or `JALR`. Address-producing
operations use sign-extended 12-bit I- or S-type immediates. Decimal 1024
(`0x400`) and all register offsets through `0x10` are therefore directly
practical with the existing ISA subset; no high-address construction or ISA
extension is needed. Existing RAM-only programs use low addresses within the
RAM window and remain compatible.

## Decode and global-to-local translation

The fabric computes explicit, non-overlapping selections:

```text
ram_select   = global_cpu_addr < 0x0000_0400
accel_select = global_cpu_addr >= 0x0000_0400
               && global_cpu_addr < 0x0000_0420
```

The upper accelerator comparison is exclusive. Once selected, the fabric
forms:

```text
local_mmio_addr = global_cpu_addr - ACCEL_BASE
```

Both values are byte addresses. The MMIO address is never shifted. For
example, global `0x0000_0408` becomes local `0x0000_0008`, not word index 2.
RAM independently performs its existing `addr >> 2` word-index conversion.

## Write routing

Write data fans out, but only a selected device receives a write enable:

```text
ram_we           = cpu_dmem_we && ram_select
accel_mmio_write = cpu_dmem_we && accel_select
```

The fabric adds no register or clock stage. RAM and MMIO writes retain their
existing rising-edge behavior. An unmapped write enables neither destination.

## Read routing

Read enables are selected in the same way:

```text
ram_re          = cpu_dmem_re && ram_select
accel_mmio_read = cpu_dmem_re && accel_select
```

The CPU return path is a deterministic combinational mux. Accelerator data is
selected only for an active accelerator read, RAM data only for an active RAM
read, and every other condition returns `0x0000_0000`. There is no added load
latency, wait state, or request/response protocol.

## Reset and preserved component behavior

The SoC shares `rst_n` with the CPU and accelerator. This preserves the CPU's
existing synchronous active-low reset and the MMIO wrapper/pipeline's existing
asynchronous active-low reset. The memories retain their previous initialized
array behavior and receive no new reset.

The CPU remains single-cycle, its ISA is unchanged, and normal RAM `lw`/`sw`
behavior is preserved.

## Verification scope

The data-fabric test drives CPU-style accesses through the real RAM and MMIO
wrapper. It covers decode, byte-offset translation, RAM load/store,
global register accesses, START/STATUS/RESULT, an independently calculated
dot product, mux and write isolation, window boundaries, reserved offsets,
consecutive writes, reset, and unmapped accesses. A separate top-level test
runs a RAM-only CPU program through `riscv_accel_soc` and confirms that it never
accesses the accelerator. The software integration test loads tracked machine
code into instruction memory and verifies the complete CPU-controlled sequence,
including the final result stored back to normal RAM. It also runs the CPU-only
repeated-add program and checks that it produces no accelerator traffic.
