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

echo "[PHASE 0] Running Python golden model..."
make -s test-golden 2>&1 | tee sim/logs/golden_model.log

echo "========================================"
echo "RTL LINT                  PASS"
echo "CPU BASELINE              PASS"
echo "SEQUENTIAL ACCELERATOR    PASS"
echo "PIPELINED ACCELERATOR     PASS"
echo "PYTHON GOLDEN MODEL       PASS"
echo "========================================"
echo "FULL REGRESSION PASSED"
echo "========================================"
