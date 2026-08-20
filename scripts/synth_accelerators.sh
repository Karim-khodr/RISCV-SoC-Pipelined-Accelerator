#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

yosys_bin="${YOSYS:-yosys}"
selection="${1:-all}"

mkdir -p results/synthesis sim/logs/synthesis

run_one() {
    local architecture="$1"
    local yosys_script="$2"
    local log_file="sim/logs/synthesis/${architecture}_yosys.log"
    local warning_file="results/synthesis/${architecture}_warnings.txt"

    echo "[SYNTH] ${architecture}"
    "${yosys_bin}" -Q -l "${log_file}" -s "${yosys_script}"

    python3 -m json.tool "results/synthesis/${architecture}_pre.json" >/dev/null
    python3 -m json.tool "results/synthesis/${architecture}_post.json" >/dev/null

    if grep -Ei '(^|[[:space:]])warning:' "${log_file}" >"${warning_file}"; then
        echo "[SYNTH] ${architecture}: warnings captured in ${warning_file}"
    else
        printf 'No Yosys warnings.\n' >"${warning_file}"
    fi
}

case "${selection}" in
    seq)
        run_one seq synth/yosys/accel_seq.ys
        ;;
    pipe)
        run_one pipe synth/yosys/accel_pipe.ys
        ;;
    all)
        run_one seq synth/yosys/accel_seq.ys
        run_one pipe synth/yosys/accel_pipe.ys
        ;;
    *)
        echo "usage: $0 [seq|pipe|all]" >&2
        exit 2
        ;;
esac
