#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

mkdir -p sim/build sim/logs sim/waveforms

echo "[LINT] Linting RTL and testbenches..."
make -s lint 2>&1 | tee sim/logs/lint.log

echo "[CPU] Running CPU tests..."
make -s test-cpu 2>&1 | tee sim/logs/cpu.log

echo "[ACCEL SEQ] Running sequential accelerator tests..."
make -s test-accel-seq 2>&1 | tee sim/logs/accel_seq.log

echo "[ACCEL PIPE] Running pipelined accelerator directed tests..."
make -s test-accel-pipe 2>&1 | tee sim/logs/accel_pipe.log

echo "[ACCEL RANDOM] Running pipelined accelerator randomized tests..."
make -s test-accel-pipe-random 2>&1 | tee sim/logs/accel_pipe_random.log

echo "[MMIO] Running standalone accelerator MMIO tests..."
make -s test-accel-mmio 2>&1 | tee sim/logs/accel_mmio.log

echo "[SOC] Running data-fabric and top-level integration tests..."
make -s test-soc 2>&1 | tee sim/logs/soc.log

echo "[SOC SOFTWARE] Running CPU-controlled accelerator and software reference..."
make -s test-soc-software 2>&1 | tee sim/logs/soc_software.log

echo "[MODEL] Running Python golden model..."
make -s test-golden 2>&1 | tee sim/logs/golden_model.log

echo "========================================"
echo "RTL LINT                  PASS"
echo "CPU BASELINE              PASS"
echo "SEQUENTIAL ACCELERATOR    PASS"
echo "PIPELINED ACCELERATOR     PASS"
echo "PIPELINE RANDOM STRESS    PASS"
echo "ACCELERATOR MMIO          PASS"
echo "SOC INTEGRATION           PASS"
echo "SOC SOFTWARE              PASS"
echo "PYTHON GOLDEN MODEL       PASS"
echo "========================================"
echo "FULL REGRESSION PASSED"
echo "========================================"
