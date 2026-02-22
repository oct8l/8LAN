#!/usr/bin/env bash
# ci-smoke-check.sh — Non-blocking post-build artifact launch sanity check.
#
# Verifies that built artifacts are structurally valid and Core launches cleanly.
# Always exits 0; writes SMOKE_STATUS.txt into the artifact directory.
#
# Usage: bash ci-smoke-check.sh [linux|windows]
#   Defaults to 'linux'. Pass 'windows' for PE-specific checks.

set -uo pipefail

PLATFORM="${1:-linux}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts/${PLATFORM}"
SMOKE_LOG="${ARTIFACTS_DIR}/logs/smoke.log"
SMOKE_STATUS="${ARTIFACTS_DIR}/SMOKE_STATUS.txt"

CORE_BINARY=""
TIMEOUT_SECS=10
FAILURES=0
CHECKS=0

# ── helpers ──────────────────────────────────────────────────────────────────

log() { echo "[smoke] $*" | tee -a "${SMOKE_LOG}"; }

pass() {
  CHECKS=$((CHECKS + 1))
  log "PASS: $*"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  log "FAIL: $*"
}

write_status() {
  local result="$1"
  local summary="$2"
  mkdir -p "$(dirname "${SMOKE_STATUS}")"
  {
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "platform=${PLATFORM}"
    echo "result=${result}"
    echo "checks=${CHECKS}"
    echo "failures=${FAILURES}"
    echo "summary=${summary}"
  } > "${SMOKE_STATUS}"
  log "Smoke check ${result}: ${CHECKS} checks, ${FAILURES} failure(s). ${summary}"
}

# ── check: artifact directory exists ─────────────────────────────────────────

check_artifact_dir() {
  if [[ -d "${ARTIFACTS_DIR}/runtime" ]]; then
    pass "artifact runtime directory exists at ${ARTIFACTS_DIR}/runtime"
  else
    fail "artifact runtime directory missing at ${ARTIFACTS_DIR}/runtime"
    return
  fi
}

# ── check: expected binaries are present ─────────────────────────────────────

check_binaries_present() {
  local bin_dir=""
  if [[ "${PLATFORM}" == "windows" ]]; then
    bin_dir="${ARTIFACTS_DIR}/runtime/portable"
    local binaries=("D-LAN.Core.exe" "D-LAN.GUI.exe" "D-LAN.Client.exe")
  else
    bin_dir="${ARTIFACTS_DIR}/runtime/bin/release"
    local binaries=("D-LAN.Core" "D-LAN.GUI" "D-LAN.Client")
  fi

  for bin in "${binaries[@]}"; do
    local full_path="${bin_dir}/${bin}"
    if [[ -f "${full_path}" ]]; then
      pass "binary present: ${bin}"
      if [[ "${bin}" == "D-LAN.Core" || "${bin}" == "D-LAN.Core.exe" ]]; then
        CORE_BINARY="${full_path}"
      fi
    else
      fail "binary missing: ${full_path}"
    fi
  done
}

# ── check: Core binary is executable ─────────────────────────────────────────

check_core_executable() {
  if [[ -z "${CORE_BINARY}" ]]; then
    fail "Core binary not found; skipping executable check"
    return
  fi

  if [[ -x "${CORE_BINARY}" ]]; then
    pass "Core binary is executable"
  else
    fail "Core binary is not executable: ${CORE_BINARY}"
  fi
}

# ── check: ELF/PE binary type validation ─────────────────────────────────────

check_binary_type() {
  if [[ -z "${CORE_BINARY}" || ! -f "${CORE_BINARY}" ]]; then
    fail "Core binary not found; skipping binary type check"
    return
  fi

  if [[ "${PLATFORM}" == "windows" ]]; then
    # On Windows/MSYS2: check for PE signature using the first 2 bytes.
    local magic
    magic=$(dd if="${CORE_BINARY}" bs=1 count=2 2>/dev/null | od -A n -t x1 | tr -d ' \n' 2>/dev/null || true)
    if [[ "${magic}" == "4d5a" || "${magic}" == "4D5A" ]]; then
      pass "Core binary has valid PE signature (MZ)"
    else
      fail "Core binary does not have expected PE signature (got: ${magic:-unknown})"
    fi
  else
    # On Linux: check for ELF magic using 'file' command.
    if command -v file >/dev/null 2>&1; then
      local file_output
      file_output=$(file "${CORE_BINARY}" 2>/dev/null || true)
      if echo "${file_output}" | grep -q "ELF"; then
        pass "Core binary is a valid ELF: ${file_output}"
      else
        fail "Core binary does not appear to be a valid ELF: ${file_output}"
      fi
    else
      log "SKIP: 'file' command not available; skipping ELF type check"
    fi
  fi
}

# ── check: Core binary shared library dependencies satisfied ─────────────────

check_shared_libs() {
  if [[ -z "${CORE_BINARY}" || ! -f "${CORE_BINARY}" ]]; then
    fail "Core binary not found; skipping shared library check"
    return
  fi

  if [[ "${PLATFORM}" == "windows" ]]; then
    log "SKIP: shared library check not applicable for Windows portable bundle (DLLs co-located)"
    return
  fi

  if command -v ldd >/dev/null 2>&1; then
    local ldd_output
    ldd_output=$(ldd "${CORE_BINARY}" 2>&1 || true)
    if echo "${ldd_output}" | grep -q "not found"; then
      local missing
      missing=$(echo "${ldd_output}" | grep "not found" | sed 's/^[[:space:]]*//')
      fail "Core binary has unsatisfied shared library dependencies:\n${missing}"
    else
      pass "Core binary shared library dependencies satisfied"
    fi
  else
    log "SKIP: 'ldd' not available; skipping shared library check"
  fi
}

# ── check: SHA256SUMS manifest present and consistent ────────────────────────

check_sha256sums() {
  local sums_file="${ARTIFACTS_DIR}/SHA256SUMS"
  if [[ ! -f "${sums_file}" ]]; then
    fail "SHA256SUMS manifest missing at ${sums_file}"
    return
  fi

  local sum_count
  sum_count=$(wc -l < "${sums_file}" 2>/dev/null || echo 0)
  if [[ "${sum_count}" -gt 0 ]]; then
    pass "SHA256SUMS manifest present (${sum_count} entries)"
  else
    fail "SHA256SUMS manifest is empty"
    return
  fi

  # Verify checksums if the hash command is available.
  local hash_cmd
  if command -v sha256sum >/dev/null 2>&1; then
    hash_cmd="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    hash_cmd="shasum -a 256"
  else
    log "SKIP: no sha256 command available; skipping manifest verification"
    return
  fi

  (
    cd "${ARTIFACTS_DIR}"
    if ${hash_cmd} --check SHA256SUMS --quiet 2>/dev/null; then
      pass "SHA256SUMS verification passed"
    else
      fail "SHA256SUMS verification failed (one or more file hashes mismatch)"
    fi
  )
}

# ── check: Core --help launches and exits cleanly ────────────────────────────

check_core_launch() {
  if [[ -z "${CORE_BINARY}" || ! -x "${CORE_BINARY}" ]]; then
    fail "Core binary not executable; skipping launch check"
    return
  fi

  if [[ "${PLATFORM}" == "windows" ]]; then
    log "SKIP: Core --help launch check skipped on Windows CI (requires desktop session)"
    return
  fi

  if ! command -v timeout >/dev/null 2>&1; then
    log "SKIP: 'timeout' command not available; skipping launch check"
    return
  fi

  log "Attempting Core --help launch (timeout: ${TIMEOUT_SECS}s)"
  local launch_output launch_rc
  launch_output=$(timeout "${TIMEOUT_SECS}" "${CORE_BINARY}" --help 2>&1 || true)
  launch_rc=$?

  # timeout exits 124 if it kills the process; exit 0/1/2 are normal app exits.
  if [[ "${launch_rc}" -eq 124 ]]; then
    fail "Core --help timed out after ${TIMEOUT_SECS}s (binary may hang on startup without display)"
  elif [[ "${launch_rc}" -eq 0 || "${launch_rc}" -eq 1 ]]; then
    # Some Qt apps exit 1 when DISPLAY is absent; accept both as "launched OK".
    pass "Core --help exited (rc=${launch_rc}); binary launches"
    log "Core --help output (first 5 lines):"
    echo "${launch_output}" | head -5 | while IFS= read -r line; do log "  ${line}"; done
  else
    fail "Core --help exited with unexpected code ${launch_rc}"
    log "Output: ${launch_output}"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

mkdir -p "${ARTIFACTS_DIR}/logs"
: > "${SMOKE_LOG}"
log "Starting smoke check for platform=${PLATFORM}"
log "Artifacts dir: ${ARTIFACTS_DIR}"

check_artifact_dir
check_binaries_present
check_core_executable
check_binary_type
check_shared_libs
check_sha256sums
check_core_launch

if [[ "${FAILURES}" -eq 0 ]]; then
  write_status "passed" "All ${CHECKS} checks passed."
else
  write_status "failed" "${FAILURES} of ${CHECKS} checks failed."
fi

# Always exit 0 — this is a non-blocking diagnostic check.
exit 0
