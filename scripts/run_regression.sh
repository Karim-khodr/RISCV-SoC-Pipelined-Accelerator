#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

mkdir -p sim/build sim/logs sim/waveforms

echo "[PHASE 0] Linting RTL and testbenches..."
make -s lint 2>&1 | tee sim/logs/lint.log

echo "[PHASE 0] Running CPU baseline..."
make -s test-cpu 2>&1 | tee sim/logs/cpu.log

echo "[PHASE 0] Running sequential accelerator baseline..."
make -s test-accel-seq 2>&1 | tee sim/logs/accel_seq.log

echo "[DAY 1] Running pipelined accelerator deterministic tests..."
make -s test-accel-pipe 2>&1 | tee sim/logs/accel_pipe.log

echo "[DAY 2] Running pipelined accelerator randomized tests..."
make -s test-accel-pipe-random 2>&1 | tee sim/logs/accel_pipe_random.log

echo "[DAY 4] Running standalone accelerator MMIO tests..."
make -s test-accel-mmio 2>&1 | tee sim/logs/accel_mmio.log

echo "[DAY 5] Running SoC data-fabric and top-level integration tests..."
make -s test-soc 2>&1 | tee sim/logs/soc.log

echo "[PHASE 0] Running Python golden model..."
make -s test-golden 2>&1 | tee sim/logs/golden_model.log

echo "========================================"
echo "RTL LINT                  PASS"
echo "CPU BASELINE              PASS"
echo "SEQUENTIAL ACCELERATOR    PASS"
echo "PIPELINED ACCELERATOR     PASS"
echo "PIPELINE RANDOM STRESS    PASS"
echo "ACCELERATOR MMIO          PASS"
echo "SOC INTEGRATION           PASS"
echo "PYTHON GOLDEN MODEL       PASS"
echo "========================================"
echo "FULL REGRESSION PASSED"
echo "========================================"
