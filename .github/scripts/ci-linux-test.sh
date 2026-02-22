#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${ROOT_DIR}/application"
LOG_DIR="${ROOT_DIR}/artifacts/linux/test-logs"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 2)}"

find_first_command() {
  local cmd
  for cmd in "$@"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      command -v "${cmd}"
      return 0
    fi
  done
  return 1
}

QMAKE_BIN="${QMAKE_BIN:-$(find_first_command qmake-qt5 qmake || true)}"
MAKE_BIN="${MAKE_BIN:-$(find_first_command make || true)}"

if [[ -z "${QMAKE_BIN}" ]]; then
  echo "qmake was not found in PATH"
  exit 1
fi

if [[ -z "${MAKE_BIN}" ]]; then
  echo "make was not found in PATH"
  exit 1
fi

mkdir -p "${LOG_DIR}"

run_with_timeout() {
  local binary="$1"
  local log_file="$2"
  local timeout_seconds=300

  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM --kill-after=30s "${timeout_seconds}" "${binary}" >"${log_file}" 2>&1
  else
    "${binary}" >"${log_file}" 2>&1
  fi
}

build_and_run_test() {
  local rel_dir="$1"
  local pro_file="$2"
  local binary_rel_path="$3"
  local log_name="$4"

  echo "Building test ${rel_dir}/${pro_file}"
  pushd "${APP_DIR}/${rel_dir}" >/dev/null
  "${QMAKE_BIN}" "${pro_file}" "CONFIG+=release" "CONFIG-=debug"
  "${MAKE_BIN}" -j"${JOBS}"

  echo "Running test ${binary_rel_path}"
  run_with_timeout "./${binary_rel_path}" "${LOG_DIR}/${log_name}.log"
  popd >/dev/null
}

# Start with the test projects that were already part of the historical run_all_tests.sh.
build_and_run_test "Common/TestsCommon" "TestsCommon.pro" "output/release/TestsCommon" "TestsCommon"
build_and_run_test "Common/LogManager/TestsLogManager" "TestsLogManager.pro" "output/release/TestsLogManager" "TestsLogManager"
build_and_run_test "Core/FileManager/TestsFileManager" "TestsFileManager.pro" "output/release/TestsFileManager" "TestsFileManager"
build_and_run_test "Core/PeerManager/TestsPeerManager" "TestsPeerManager.pro" "output/release/TestsPeerManager" "TestsPeerManager"

echo "Linux tests completed"
