# Day 3 regression summary

Day 3 started from clean commit `b2d160486fb89b6f73a48346754496f4f43e6773`
on branch `main`. No commit or push was created.

## Synthesis and comparison

| Command | Result |
|---|---:|
| `make synth-accel-seq` | PASS |
| `make synth-accel-pipe` | PASS |
| `make synth-accel` | PASS |
| `make perf-accel` | PASS |
| `make compare-accel` | PASS |

Both pre-lowering and post-synthesis `check` passes reported zero problems.
All four synthesis JSON files passed Python JSON validation. Neither Yosys run
emitted a warning.

## Performance measurement

Both deterministic performance benches checked 100 identical generated input
pairs with zero mismatches. The sequential measurement observed latency 4, II 5,
completion interval 5, and a 499-cycle first-accept-to-last-completion span. The
pipelined measurement observed latency 3, II 1, completion interval 1, and a
102-cycle span. Cycle fields use rising-edge distance.

## Targeted verification

| Command | Result |
|---|---:|
| `make test-accel-seq` | PASS: 113 tests, 0 failures |
| `make test-accel-pipe` | PASS: 7 tests, 0 test/protocol failures |
| `make test-accel-pipe-random` | PASS: 3,000 random accepts, 0 protocol failures, unexpected outputs, mismatches, or timeouts |
| `make lint-accel-seq lint-accel-pipe lint-accel-pipe-random lint-accel-performance` | PASS |

The default randomized run again recorded 3,013 total accepted transactions,
2,998 consumed and checked results, and 15 intentional reset discards.

## Complete regression

| Command | Result |
|---|---:|
| `make lint` | PASS |
| `make test` | PASS |

The full regression reported:

```text
RTL LINT                  PASS
CPU BASELINE              PASS
SEQUENTIAL ACCELERATOR    PASS
PIPELINED ACCELERATOR     PASS
PIPELINE RANDOM STRESS    PASS
PYTHON GOLDEN MODEL       PASS
FULL REGRESSION PASSED
```

The Python golden model passed all six checks.
