#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 3 ]]; then
  echo "Usage: $0 <build-name> <top-module> <source-or-option>..." >&2
  exit 2
fi

build_name="$1"
top_module="$2"
shift 2

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/riscv-soc-verilator.XXXXXX")"
stage_repo="${stage_root}/repo"
obj_name="obj_${build_name}"

cleanup() {
  rm -rf "${stage_root}"
}
trap cleanup EXIT

mkdir -p "${stage_repo}/sim/build"
cp -R "${repo_root}/rtl" "${stage_repo}/rtl"
cp -R "${repo_root}/tb" "${stage_repo}/tb"
cp -R "${repo_root}/filelists" "${stage_repo}/filelists"

cd "${stage_repo}"
verilator -Wall --timing --assert -Irtl/cpu -Irtl/memory \
  --binary --trace "$@" \
  --top-module "${top_module}" -Mdir "sim/build/${obj_name}"

rm -rf "${repo_root}/sim/build/${obj_name}"
cp -R "${stage_repo}/sim/build/${obj_name}" "${repo_root}/sim/build/${obj_name}"

cd "${repo_root}/sim/waveforms"
read -r -a runtime_args <<< "${TEST_ARGS:-}"
"${repo_root}/sim/build/${obj_name}/V${top_module}" "${runtime_args[@]}"
