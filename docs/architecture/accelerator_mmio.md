# Standalone accelerator MMIO peripheral

## Purpose and scope

`dot_product_accel_mmio` gives the existing ready/valid pipelined dot-product
accelerator a small software-like register interface. The peripheral is
verified standalone in Day 4; it is not connected to the CPU and does not own
a system-level base address.

```text
MMIO reads and writes
        |
        v
+-------------------+
| MMIO register and |
| protocol wrapper  |
+-------------------+
        |
        | ready / valid
        v
+----------------------+
| Dot Product Pipeline |
|   MUL -> ADD -> ADD  |
+----------------------+
```

## External interface

```systemverilog
module dot_product_accel_mmio #(
    parameter int ELEM_WIDTH   = 8,
    parameter int NUM_ELEMS    = 4,
    parameter int RESULT_WIDTH = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] mmio_addr,
    input  logic        mmio_read,
    input  logic        mmio_write,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata
);
```

`mmio_addr` is a local 32-bit byte offset. A later system address decoder can
subtract or otherwise form this offset after selecting the peripheral. Reads
are combinational and zero-wait-state. Writes are accepted on the rising clock
edge. There is no response handshake and no byte-enable interface, matching
the current CPU data port. Only exact 32-bit word-aligned offsets decode.

The software-visible configuration is intentionally fixed at two 32-bit
packed vectors and a 32-bit result. The wrapper checks at elaboration that its
pipeline parameter values preserve those widths.

## Register map

| Offset | Register | Access | Meaning |
|---:|---|:---:|---|
| `0x00` | `CONTROL` | WO | Bit 0 submits one command when `READY`; other bits are ignored |
| `0x04` | `STATUS` | RO | Peripheral lifecycle status |
| `0x08` | `VEC_A` | RW | Packed unsigned input vector A |
| `0x0c` | `VEC_B` | RW | Packed unsigned input vector B |
| `0x10` | `RESULT` | RO | Most recently completed dot product |

Reading `CONTROL` returns zero. Writes to `STATUS` and `RESULT` are ignored.
Unknown and unaligned reads return zero; unknown and unaligned writes are
ignored. Accesses do not alias neighboring registers.

## CONTROL and START

`CONTROL[0]` is `START`. It is a write event, not stored state. A write with
bit 0 set is accepted only when `READY` is one. Writing zero or reserved bits
has no effect. A START while the peripheral is unavailable is ignored and is
not queued.

On an accepted START, the wrapper snapshots both operand registers and raises
an internal pending command. It holds pipeline `in_valid` and both snapshots
stable until `in_valid && in_ready`. The input handshake clears pending and
marks the operation in flight.

## STATUS

| Bit | Name | Definition |
|---:|---|---|
| 0 | `READY` | Operand writes and one START can be accepted |
| 1 | `BUSY` | A command is pending or in flight and has not completed |
| 2 | `RESULT_VALID` | `RESULT` contains an unread completion |
| 31:3 | Reserved | Always zero |

The exact equations are:

```text
READY = !(command_pending || inflight || result_valid)
BUSY  = command_pending || inflight
```

The normal lifecycle is:

```text
idle                 READY=1 BUSY=0 RESULT_VALID=0
pending/in flight    READY=0 BUSY=1 RESULT_VALID=0
completed unread     READY=0 BUSY=0 RESULT_VALID=1
RESULT consumed      READY=1 BUSY=0 RESULT_VALID=0
```

Polling `STATUS` has no side effect.

## Operand packing

The instantiated pipeline selects element `i` from
`vector[i*8 +: 8]`. Therefore element 0 occupies the least-significant byte:

```text
31          24 23          16 15           8 7            0
+--------------+--------------+--------------+--------------+
|      a3      |      a2      |      a1      |      a0      |
+--------------+--------------+--------------+--------------+
```

`VEC_B` uses the same layout. Elements and arithmetic are unsigned. Operand
registers reset to zero and accept writes only while `READY`; writes while
busy or while an unread result is present are ignored.

## Result handling

The wrapper asserts pipeline `out_ready` only when its single result slot is
free. On `out_valid && out_ready`, it captures the pipeline result, clears the
in-flight state, and sets `RESULT_VALID`. An unread result therefore cannot be
overwritten.

Reading `RESULT` returns the stored value combinationally. If `RESULT_VALID`
is set, the read clears the flag on the rising edge. The result data itself is
retained, so a read without a valid completion returns zero after reset or the
previous completed value later. Software must use `RESULT_VALID` to identify
a new unread completion. If a result capture and an early RESULT read coincide,
capture has priority so the new completion remains valid.

## Reset

`rst_n` is an asynchronous active-low reset for both the wrapper and pipeline.
It clears operands, command snapshots, pending and in-flight state, result
data, and `RESULT_VALID`. A reset discards any outstanding operation or unread
result. After release the peripheral is ready, and no pre-reset pipeline
transaction can later produce a stale completion.

## Programming sequence

1. Check `STATUS.READY` if desired.
2. Write `VEC_A`.
3. Write `VEC_B`.
4. Write `CONTROL.START = 1`.
5. Poll `STATUS.RESULT_VALID`.
6. Read `RESULT`; this consumes the completion.
7. The peripheral becomes ready for another operation on the state update.

The underlying three-stage datapath supports initiation interval 1 under
ideal streaming conditions. This Day 4 MMIO interface intentionally supports
one software-visible operation outstanding at a time for a simple, robust
programming model. It does not provide one MMIO command per cycle.

## Day 5 boundary

Day 4 verification drives this local interface directly from a testbench. A
later SoC address decoder may route selected CPU load/store operations to it
and provide local offsets. No CPU connection, global accelerator base address,
read-data mux, SoC top level, or accelerator-control software is implemented
here.
