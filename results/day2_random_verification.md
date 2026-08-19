# Day 2 randomized pipeline verification

The Day 2 testbench stress-tests the existing three-stage elastic dot-product
pipeline without changing its RTL. It uses a handshake-driven three-entry ring
FIFO scoreboard (portable to both Icarus and Verilator):
expected results are added only on `in_valid && in_ready`, and checked/removed
only on `out_valid && out_ready`. Output processing occurs before input processing
on simultaneous handshakes.

The default run accepts 3,000 randomized transactions using seed 12345. The
source offers traffic with an 80% probability when it is not holding a blocked
request. The sink is normally ready with 72% probability and also inserts
explicit 1-cycle, 2-4-cycle, 5-10-cycle, and 11-30-cycle stall bursts. A directed
episode guarantees a full blocked pipeline. Directed resets discard one, two,
and three accepted outstanding transactions, and three additional in-flight
resets occur during randomized traffic.

Clocked protocol checkers verify output stability during stalls, source stability
while blocked, and cleared `out_valid` during active reset. They are used instead
of concurrent SVA because Icarus Verilog is the repository's accelerator runtime
and does not provide sufficiently portable concurrent-property support for this
flow. Every checker violation contributes to the final failure decision.

Reproduce the default run with:

```bash
make test-accel-pipe-random
```

Override the deterministic seed or accepted-transaction target with:

```bash
make test-accel-pipe-random SEED=98765 RANDOM_TXNS=3000
```

The random test is also included in `make test` through the repository regression
script.

## Default passing run

The final seed-12345 run completed in 6,695 cycles. It accepted 3,000 randomized
transactions (3,013 including directed setup/recovery traffic), consumed and
checked 2,998 outputs, and intentionally discarded 15 accepted transactions over
seven reset events. It observed 801 input-bubble cycles, 2,859 input-backpressure
cycles, 3,366 stalled-valid output cycles, 2,554 simultaneous input/output
handshakes, a maximum 38-cycle stalled-valid run, and the full three-entry
scoreboard depth. Protocol failures, unexpected outputs, data mismatches, and
timeouts were all zero. The complete `make test` regression passed.
