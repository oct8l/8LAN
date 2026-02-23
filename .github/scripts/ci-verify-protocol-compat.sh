#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROTO_DIR="${ROOT_DIR}/application/Protos"
ARTIFACTS_DIR="${1:-${ROOT_DIR}/artifacts/protocol}"
PROTOC_BIN="${2:-$(command -v protoc || true)}"
DEFAULT_BASELINE_REF="${PROTO_BASELINE_REF:-origin/1.1}"
BASELINE_REF="${DEFAULT_BASELINE_REF}"
ALLOW_PROTOCOL_BREAK="${ALLOW_PROTOCOL_BREAK:-0}"
SKIP_PROTOCOL_COMPAT_CHECK="${SKIP_PROTOCOL_COMPAT_CHECK:-0}"

PROTOS=(
  common.proto
  core_protocol.proto
  core_settings.proto
  files_cache.proto
  gui_protocol.proto
  gui_settings.proto
  queue.proto
)

SUMMARY_FILE="${ARTIFACTS_DIR}/PROTOCOL_COMPATIBILITY.txt"
DIFF_FILE="${ARTIFACTS_DIR}/PROTOCOL_COMPATIBILITY.diff"

mkdir -p "${ARTIFACTS_DIR}"

if [[ "${SKIP_PROTOCOL_COMPAT_CHECK}" == "1" ]]; then
  {
    echo "status=skipped"
    echo "reason=SKIP_PROTOCOL_COMPAT_CHECK=1"
  } > "${SUMMARY_FILE}"
  echo "Protocol compatibility check skipped"
  exit 0
fi

if [[ -z "${PROTOC_BIN}" ]]; then
  {
    echo "status=error"
    echo "reason=protoc_not_found"
  } > "${SUMMARY_FILE}"
  echo "protoc not found; cannot verify protocol compatibility"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  {
    echo "status=error"
    echo "reason=git_not_found"
  } > "${SUMMARY_FILE}"
  echo "git not found; cannot verify protocol compatibility"
  exit 1
fi

try_resolve_baseline_ref() {
  local candidate_ref="$1"

  if [[ -z "${candidate_ref}" ]]; then
    return 1
  fi

  if git cat-file -e "${candidate_ref}^{commit}" 2>/dev/null; then
    BASELINE_REF="${candidate_ref}"
    return 0
  fi

  if [[ "${candidate_ref}" == origin/* ]]; then
    local branch_ref="${candidate_ref#origin/}"
    echo "Baseline ref ${candidate_ref} not found locally; fetching origin/${branch_ref}"

    if git fetch --no-tags --depth=1 origin "${branch_ref}" >/dev/null 2>&1; then
      if git cat-file -e "${candidate_ref}^{commit}" 2>/dev/null; then
        BASELINE_REF="${candidate_ref}"
        return 0
      fi

      if git cat-file -e "FETCH_HEAD^{commit}" 2>/dev/null; then
        BASELINE_REF="FETCH_HEAD"
        return 0
      fi
    fi
  fi

  return 1
}

resolve_baseline_ref() {
  local candidates=("${DEFAULT_BASELINE_REF}")

  # In PRs, this is typically the branch we actually want to compare against.
  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    candidates+=("origin/${GITHUB_BASE_REF}")
  fi

  # Fresh repos (like 8LAN) may not carry origin/1.1. Fall back to active defaults.
  candidates+=("origin/main" "origin/master" "HEAD^")

  local candidate
  for candidate in "${candidates[@]}"; do
    if try_resolve_baseline_ref "${candidate}"; then
      return 0
    fi
  done

  return 1
}

if ! resolve_baseline_ref; then
  if [[ "${ALLOW_PROTOCOL_BREAK}" == "1" ]]; then
    {
      echo "status=skipped"
      echo "reason=baseline_ref_missing_allow_protocol_break"
      echo "requested_baseline_ref=${DEFAULT_BASELINE_REF}"
      echo "allow_protocol_break=${ALLOW_PROTOCOL_BREAK}"
    } > "${SUMMARY_FILE}"

    rm -f "${DIFF_FILE}"
    echo "Unable to resolve protocol baseline ref ${DEFAULT_BASELINE_REF}; ALLOW_PROTOCOL_BREAK=1 so compatibility diff is skipped"
    exit 0
  fi

  {
    echo "status=error"
    echo "reason=baseline_ref_missing"
    echo "requested_baseline_ref=${DEFAULT_BASELINE_REF}"
  } > "${SUMMARY_FILE}"
  echo "Unable to resolve protocol baseline ref ${DEFAULT_BASELINE_REF}"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${WORK_DIR}/current" "${WORK_DIR}/baseline"

for proto in "${PROTOS[@]}"; do
  if [[ ! -f "${PROTO_DIR}/${proto}" ]]; then
    {
      echo "status=error"
      echo "reason=missing_proto_file"
      echo "file=${proto}"
    } > "${SUMMARY_FILE}"
    echo "Missing proto file: ${PROTO_DIR}/${proto}"
    exit 1
  fi

  cp -f "${PROTO_DIR}/${proto}" "${WORK_DIR}/current/${proto}"

  if ! git show "${BASELINE_REF}:application/Protos/${proto}" > "${WORK_DIR}/baseline/${proto}"; then
    {
      echo "status=error"
      echo "reason=missing_baseline_proto"
      echo "file=${proto}"
      echo "baseline_ref=${BASELINE_REF}"
    } > "${SUMMARY_FILE}"
    echo "Missing baseline proto ${proto} in ${BASELINE_REF}"
    exit 1
  fi
done

(
  cd "${WORK_DIR}/current"
  "${PROTOC_BIN}" --include_imports --descriptor_set_out "${WORK_DIR}/current.desc" "${PROTOS[@]}"
)
(
  cd "${WORK_DIR}/baseline"
  if ! "${PROTOC_BIN}" --include_imports --descriptor_set_out "${WORK_DIR}/baseline.desc" "${PROTOS[@]}" 2> "${WORK_DIR}/baseline-protoc.stderr"; then
    cat "${WORK_DIR}/baseline-protoc.stderr" >&2
    exit 1
  fi
)

"${PROTOC_BIN}" --decode=google.protobuf.FileDescriptorSet google/protobuf/descriptor.proto < "${WORK_DIR}/current.desc" > "${WORK_DIR}/current.txt"
"${PROTOC_BIN}" --decode=google.protobuf.FileDescriptorSet google/protobuf/descriptor.proto < "${WORK_DIR}/baseline.desc" > "${WORK_DIR}/baseline.txt"

# Dependency/import lists are not wire-compatibility relevant.
normalize() {
  sed -E '/^[[:space:]]*(dependency|public_dependency|weak_dependency):/d' "$1"
}

normalize "${WORK_DIR}/current.txt" > "${WORK_DIR}/current.norm"
normalize "${WORK_DIR}/baseline.txt" > "${WORK_DIR}/baseline.norm"

BASELINE_DIGEST="$(git hash-object "${WORK_DIR}/baseline.norm")"
CURRENT_DIGEST="$(git hash-object "${WORK_DIR}/current.norm")"

if [[ "${BASELINE_DIGEST}" == "${CURRENT_DIGEST}" ]]; then
  {
    echo "status=compatible"
    echo "baseline_ref=${BASELINE_REF}"
    echo "allow_protocol_break=${ALLOW_PROTOCOL_BREAK}"
  } > "${SUMMARY_FILE}"
  rm -f "${DIFF_FILE}"
  echo "Protocol compatibility check passed against ${BASELINE_REF}"
  exit 0
fi

if command -v diff >/dev/null 2>&1; then
  diff -u "${WORK_DIR}/baseline.norm" "${WORK_DIR}/current.norm" > "${DIFF_FILE}" || true
else
  git --no-pager diff --no-index -- "${WORK_DIR}/baseline.norm" "${WORK_DIR}/current.norm" > "${DIFF_FILE}" || true
fi

if [[ "${ALLOW_PROTOCOL_BREAK}" == "1" ]]; then
  {
    echo "status=breaking_change_allowed"
    echo "baseline_ref=${BASELINE_REF}"
    echo "allow_protocol_break=${ALLOW_PROTOCOL_BREAK}"
    echo "diff_file=$(basename "${DIFF_FILE}")"
  } > "${SUMMARY_FILE}"
  echo "Protocol differences detected but ALLOW_PROTOCOL_BREAK=1; continuing"
  exit 0
fi

{
  echo "status=breaking_change_detected"
  echo "baseline_ref=${BASELINE_REF}"
  echo "allow_protocol_break=${ALLOW_PROTOCOL_BREAK}"
  echo "diff_file=$(basename "${DIFF_FILE}")"
} > "${SUMMARY_FILE}"

echo "Protocol compatibility check failed; see ${DIFF_FILE}"
exit 1
