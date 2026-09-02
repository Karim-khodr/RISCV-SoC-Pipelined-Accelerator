# System Architecture

The system connects a small single-cycle RISC-V CPU to data RAM and a pipelined dot-product accelerator. The CPU accesses both through the same data-memory interface. `soc_data_fabric` sends normal addresses to RAM and accelerator addresses to the MMIO wrapper.

```text
RISC-V CPU -> address decoder -> data RAM
                              -> accelerator MMIO -> dot-product pipeline
```

## CPU Interface

Instruction reads use a 32-bit address and 32-bit instruction data. The data interface has read and write enables, a 32-bit byte address, write data, and read data. Reads are combinational, and writes are accepted on the rising clock edge. There is no ready or stall signal, so the current memories and MMIO peripheral use zero-wait-state accesses.

## Memory Map

| Region | Address range | Description |
| --- | --- | --- |
| Data RAM | `0x0000_0000`–`0x0000_03ff` | 256 32-bit words |
| Accelerator | `0x0000_0400`–`0x0000_041f` | 32-byte MMIO window |
| Unmapped | `0x0000_0420` and above | Reads return zero; writes are ignored |

The fabric subtracts `0x400` from accelerator addresses before passing them to the MMIO wrapper.

## Accelerator Registers

| Register | CPU address | Local offset | Access |
| --- | ---: | ---: | :---: |
| `CONTROL` | `0x0000_0400` | `0x00` | WO |
| `STATUS` | `0x0000_0404` | `0x04` | RO |
| `VEC_A` | `0x0000_0408` | `0x08` | RW |
| `VEC_B` | `0x0000_040c` | `0x0c` | RW |
| `RESULT` | `0x0000_0410` | `0x10` | RO |

| `STATUS` bit | Name |
| ---: | --- |
| 0 | `READY` |
| 1 | `BUSY` |
| 2 | `RESULT_VALID` |

Each vector register holds four packed unsigned 8-bit values, with element 0 in the least-significant byte. Vector writes and `START` are only accepted while the accelerator is `READY`; otherwise, they are ignored.

Software uses the accelerator as follows:

1. Write `VEC_A` and `VEC_B`.
2. Write `1` to `CONTROL` to start.
3. Poll `STATUS.RESULT_VALID`.
4. Read `RESULT`.
5. Store the result in RAM or start another operation.

The MMIO wrapper allows one software-visible operation at a time. Reading a valid result clears `RESULT_VALID` and makes the peripheral ready again.

## Reset and Limitations

The CPU uses synchronous active-low reset. The accelerator wrapper and pipeline use asynchronous active-low reset on the same `rst_n` signal. Reset clears the accelerator registers and discards any pending operation or unread result.

Current limitations:

- Small RV32I subset with no `MUL`, jumps, or shifts
- No caches, wait states, DMA, or interrupts
- Polling-based accelerator completion
- One outstanding MMIO accelerator command
- Simulation and generic Yosys synthesis only; no FPGA or physical ASIC results
