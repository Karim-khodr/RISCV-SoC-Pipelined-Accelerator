#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

iverilog_bin="${IVERILOG:-iverilog}"
vvp_bin="${VVP:-vvp}"
selection="${1:-all}"

mkdir -p sim/build/performance results/performance

run_seq() {
    "${iverilog_bin}" -g2012 -Wall -s dot_product_seq_perf_tb \
        -o sim/build/performance/dot_product_seq_perf_tb.vvp \
        rtl/accelerator/sequential/dot_product_seq.sv \
        tb/accelerator/performance/dot_product_seq_perf_tb.sv
    "${vvp_bin}" sim/build/performance/dot_product_seq_perf_tb.vvp \
        | tee results/performance/seq_perf.txt
}

run_pipe() {
    "${iverilog_bin}" -g2012 -Wall -s dot_product_pipeline_perf_tb \
        -o sim/build/performance/dot_product_pipeline_perf_tb.vvp \
        rtl/accelerator/pipelined/dot_product_pipeline.sv \
        tb/accelerator/performance/dot_product_pipeline_perf_tb.sv
    "${vvp_bin}" sim/build/performance/dot_product_pipeline_perf_tb.vvp \
        | tee results/performance/pipe_perf.txt
}

case "${selection}" in
    seq) run_seq ;;
    pipe) run_pipe ;;
    all)
        run_seq
        run_pipe
        ;;
    *)
        echo "usage: $0 [seq|pipe|all]" >&2
        exit 2
        ;;
esac
