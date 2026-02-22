#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${ROOT_DIR}/application"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts/linux"
LOG_DIR="${ARTIFACTS_DIR}/logs"
BUILD_LOG="${LOG_DIR}/build.log"
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
LRELEASE_BIN="${LRELEASE_BIN:-$(find_first_command lrelease-qt5 lrelease || true)}"
PROTOC_BIN="${PROTOC_BIN:-$(find_first_command protoc || true)}"
HASH_BIN="${HASH_BIN:-$(find_first_command sha256sum shasum || true)}"

setup_artifact_logging() {
  mkdir -p "${ARTIFACTS_DIR}" "${LOG_DIR}"
  : > "${BUILD_LOG}"

  # Try mirrored logging to both console and file; fall back to file-only
  # in restricted shells where process substitution is unavailable.
  set +e
  exec > >(tee -a "${BUILD_LOG}") 2>&1
  local tee_rc=$?
  set -e
  if [[ "${tee_rc}" -ne 0 ]]; then
    exec >> "${BUILD_LOG}" 2>&1
    echo "tee stream unavailable; logging to file only"
  fi
}

finalize_artifacts() {
  local exit_code=$?
  local result="failure"
  if [[ "${exit_code}" -eq 0 ]]; then
    result="success"
  fi

  mkdir -p "${ARTIFACTS_DIR}" "${LOG_DIR}"
  {
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "exit_code=${exit_code}"
    echo "result=${result}"
  } > "${ARTIFACTS_DIR}/BUILD_STATUS.txt"

  if [[ "${exit_code}" -ne 0 ]]; then
    echo "Build failed before artifact packaging completed. See logs/build.log for details." > "${ARTIFACTS_DIR}/FAILURE_SUMMARY.txt"
  fi
}

trap finalize_artifacts EXIT
setup_artifact_logging

if [[ -z "${QMAKE_BIN}" ]]; then
  echo "qmake was not found in PATH"
  exit 1
fi

if [[ -z "${MAKE_BIN}" ]]; then
  echo "make was not found in PATH"
  exit 1
fi

if [[ -z "${PROTOC_BIN}" ]]; then
  echo "protoc not found in PATH"
  exit 1
fi

if [[ -z "${HASH_BIN}" ]]; then
  echo "sha256 tool not found in PATH (expected sha256sum or shasum)"
  exit 1
fi

bash "${ROOT_DIR}/.github/scripts/ci-verify-deps.sh" \
  linux \
  "${ARTIFACTS_DIR}" \
  "${QMAKE_BIN}" \
  "${PROTOC_BIN}"

hash_files() {
  if [[ "$(basename "${HASH_BIN}")" == "sha256sum" ]]; then
    "${HASH_BIN}" "$@"
  else
    "${HASH_BIN}" -a 256 "$@"
  fi
}

build_component() {
  local project="$1"
  local config="$2"
  local opposite="$3"
  local makefile="Makefile-${project}-${config}"

  echo "Building ${project} (${config})"
  pushd "${APP_DIR}" >/dev/null
  # shellcheck disable=SC2086  # QMAKE_EXTRA_FLAGS is intentionally word-split
  "${QMAKE_BIN}" -o "${makefile}" "${project}.pro" "CONFIG+=${config}" "CONFIG-=${opposite}" ${QMAKE_EXTRA_FLAGS:-}
  "${MAKE_BIN}" -f "${makefile}" -j"${JOBS}"
  popd >/dev/null
}

build_all() {
  local config
  local opposite
  local project
  for config in release debug; do
    if [[ "${config}" == "release" ]]; then
      opposite="debug"
    else
      opposite="release"
    fi

    for project in Core GUI Client; do
      if [[ -f "${APP_DIR}/${project}.pro" ]]; then
        build_component "${project}" "${config}" "${opposite}"
      fi
    done
  done
}

refresh_generated_protos() {
  if compgen -G "${APP_DIR}/Protos/*.pb.cc" >/dev/null || compgen -G "${APP_DIR}/Protos/*.pb.h" >/dev/null; then
    echo "Refreshing generated protobuf sources"
    local attempt
    for attempt in 1 2 3; do
      if rm -f "${APP_DIR}"/Protos/*.pb.cc "${APP_DIR}"/Protos/*.pb.h; then
        return 0
      fi
      echo "Generated protobuf cleanup attempt ${attempt}/3 failed; retrying"
      sleep 1
    done
    echo "Warning: unable to delete one or more generated protobuf files; continuing with protoc regeneration"
  fi
}

generate_protos() {
  echo "Generating protobuf sources"
  pushd "${APP_DIR}/Protos" >/dev/null
  local proto
  for proto in \
    common.proto \
    core_protocol.proto \
    core_settings.proto \
    files_cache.proto \
    gui_protocol.proto \
    gui_settings.proto \
    queue.proto; do
    "${PROTOC_BIN}" --cpp_out . "${proto}"
  done
  popd >/dev/null
}

verify_generated_protos_idempotent() {
  local before_hashes
  local after_hashes
  before_hashes="$(mktemp)"
  after_hashes="$(mktemp)"
  trap 'rm -f "${before_hashes}" "${after_hashes}"' RETURN

  (
    cd "${APP_DIR}/Protos"
    hash_files ./*.pb.cc ./*.pb.h | sort > "${before_hashes}"
  )

  generate_protos

  (
    cd "${APP_DIR}/Protos"
    hash_files ./*.pb.cc ./*.pb.h | sort > "${after_hashes}"
  )

  local before_digest
  local after_digest
  before_digest="$(git hash-object "${before_hashes}")"
  after_digest="$(git hash-object "${after_hashes}")"

  if [[ "${before_digest}" == "${after_digest}" ]]; then
    rm -f "${ARTIFACTS_DIR}/PROTO_REGEN.diff"
    {
      echo "status=deterministic"
      echo "generator=protoc"
    } > "${ARTIFACTS_DIR}/PROTO_REGEN_STATUS.txt"
    echo "Generated protobuf outputs are deterministic"
    return
  fi

  if command -v diff >/dev/null 2>&1; then
    diff -u "${before_hashes}" "${after_hashes}" > "${ARTIFACTS_DIR}/PROTO_REGEN.diff" || true
  else
    git --no-pager diff --no-index -- "${before_hashes}" "${after_hashes}" > "${ARTIFACTS_DIR}/PROTO_REGEN.diff" || true
  fi

  {
    echo "status=non_deterministic"
    echo "diff_file=PROTO_REGEN.diff"
  } > "${ARTIFACTS_DIR}/PROTO_REGEN_STATUS.txt"
  echo "Generated protobuf outputs changed on immediate regeneration"
  exit 1
}

verify_protocol_compatibility() {
  bash "${ROOT_DIR}/.github/scripts/ci-verify-protocol-compat.sh" "${ARTIFACTS_DIR}" "${PROTOC_BIN}"
}

generate_translations() {
  if [[ -z "${LRELEASE_BIN}" ]]; then
    echo "lrelease not found; skipping translation compilation"
    return
  fi

  echo "Compiling translations"
  pushd "${APP_DIR}/translations" >/dev/null
  rm -f ./*.qm
  "${LRELEASE_BIN}" d_lan_core.*.ts d_lan_gui.*.ts
  popd >/dev/null
}

collect_artifacts() {
  echo "Collecting Linux artifacts"
  rm -rf "${ARTIFACTS_DIR}/runtime" "${ARTIFACTS_DIR}/SHA256SUMS"

  mkdir -p "${ARTIFACTS_DIR}/runtime/bin/release"
  mkdir -p "${ARTIFACTS_DIR}/runtime/bin/debug"
  mkdir -p "${ARTIFACTS_DIR}/runtime/languages"
  mkdir -p "${ARTIFACTS_DIR}/runtime/Emoticons"

  cp "${APP_DIR}/Core/output/release/D-LAN.Core" "${ARTIFACTS_DIR}/runtime/bin/release/"
  cp "${APP_DIR}/GUI/output/release/D-LAN.GUI" "${ARTIFACTS_DIR}/runtime/bin/release/"
  cp "${APP_DIR}/Client/output/release/D-LAN.Client" "${ARTIFACTS_DIR}/runtime/bin/release/"

  if [[ -f "${APP_DIR}/Core/output/debug/D-LAN.Core" ]]; then
    cp "${APP_DIR}/Core/output/debug/D-LAN.Core" "${ARTIFACTS_DIR}/runtime/bin/debug/"
  fi
  if [[ -f "${APP_DIR}/GUI/output/debug/D-LAN.GUI" ]]; then
    cp "${APP_DIR}/GUI/output/debug/D-LAN.GUI" "${ARTIFACTS_DIR}/runtime/bin/debug/"
  fi
  if [[ -f "${APP_DIR}/Client/output/debug/D-LAN.Client" ]]; then
    cp "${APP_DIR}/Client/output/debug/D-LAN.Client" "${ARTIFACTS_DIR}/runtime/bin/debug/"
  fi

  cp -R "${APP_DIR}/styles" "${ARTIFACTS_DIR}/runtime/"
  if [[ -d "${APP_DIR}/GUI/ressources/emoticons" ]]; then
    cp -R "${APP_DIR}/GUI/ressources/emoticons/." "${ARTIFACTS_DIR}/runtime/Emoticons/"
  else
    echo "Emoticons directory not found; skipping emoticon asset copy"
  fi

  if compgen -G "${APP_DIR}/translations/*.qm" >/dev/null; then
    cp "${APP_DIR}/translations/"*.qm "${ARTIFACTS_DIR}/runtime/languages/"
  fi

  (
    cd "${ARTIFACTS_DIR}"
    find runtime -type f -print0 | sort -z | while IFS= read -r -d '' file; do
      hash_files "${file}"
    done > SHA256SUMS
  )
}

package_artifacts() {
  local packages_dir="${ARTIFACTS_DIR}/packages"
  local archive_path="${packages_dir}/d-lan-linux-portable.tar.gz"

  echo "Packaging Linux installable artifacts"
  rm -rf "${packages_dir}"
  mkdir -p "${packages_dir}"

  tar -C "${ARTIFACTS_DIR}" -czf "${archive_path}" runtime

  {
    echo "portable_archive=$(basename "${archive_path}")"
    echo "format=tar.gz"
  } > "${packages_dir}/PACKAGES.txt"
}

refresh_generated_protos
generate_protos
verify_generated_protos_idempotent
verify_protocol_compatibility
generate_translations
build_all
collect_artifacts
package_artifacts

echo "Linux build completed"
