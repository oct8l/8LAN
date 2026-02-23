#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${ROOT_DIR}/application"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts/windows"
LOG_DIR="${ARTIFACTS_DIR}/logs"
BUILD_LOG="${LOG_DIR}/build.log"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 2)}"
BUILD_CONFIGS="${BUILD_CONFIGS:-release}"

export PATH="/mingw64/bin:${PATH}"

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
MAKE_BIN="${MAKE_BIN:-$(find_first_command mingw32-make make || true)}"
LRELEASE_BIN="${LRELEASE_BIN:-$(find_first_command lrelease-qt5 lrelease || true)}"
PROTOC_BIN="${PROTOC_BIN:-$(find_first_command protoc || true)}"
WINDEPLOYQT_BIN="${WINDEPLOYQT_BIN:-$(find_first_command windeployqt-qt5 windeployqt || true)}"
OBJDUMP_BIN="${OBJDUMP_BIN:-$(find_first_command x86_64-w64-mingw32-objdump objdump || true)}"
HASH_BIN="${HASH_BIN:-$(find_first_command sha256sum shasum || true)}"
CYGPATH_BIN="${CYGPATH_BIN:-$(find_first_command cygpath || true)}"

# Detect Qt major version so we can set ACCEPT_QT6 and use correct tool flags.
QT_MAJOR=""
if [[ -n "${QMAKE_BIN}" ]]; then
  _qt_ver="$("${QMAKE_BIN}" -query QT_VERSION 2>/dev/null || true)"
  QT_MAJOR="${_qt_ver%%.*}"
fi
ACCEPT_QT6="${ACCEPT_QT6:-0}"
[[ "${QT_MAJOR}" == "6" ]] && ACCEPT_QT6="1"
export ACCEPT_QT6

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
  echo "mingw32-make was not found in PATH"
  exit 1
fi

if [[ -z "${PROTOC_BIN}" ]]; then
  echo "protoc was not found in PATH"
  exit 1
fi

if [[ -z "${HASH_BIN}" ]]; then
  echo "sha256 tool not found in PATH (expected sha256sum or shasum)"
  exit 1
fi

if [[ -z "${CYGPATH_BIN}" ]]; then
  echo "cygpath was not found in PATH"
  exit 1
fi

bash "${ROOT_DIR}/.github/scripts/ci-verify-deps.sh" \
  windows \
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

refresh_generated_protos() {
  # Keep ad-hoc branch switching deterministic: stale generated protobuf
  # files can survive in a reused workspace and mismatch current .proto files.
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

build_component() {
  local project="$1"
  local config="$2"
  local opposite="$3"
  local makefile="Makefile-${project}-${config}"

  echo "Building ${project} (${config})"
  pushd "${APP_DIR}" >/dev/null
  "${QMAKE_BIN}" -o "${makefile}" "${project}.pro" "CONFIG+=${config}" "CONFIG-=${opposite}"
  "${MAKE_BIN}" -f "${makefile}" -j"${JOBS}"
  popd >/dev/null
}

build_all() {
  local config
  local opposite
  local project
  for config in ${BUILD_CONFIGS}; do
    if [[ "${config}" == "release" ]]; then
      opposite="debug"
    elif [[ "${config}" == "debug" ]]; then
      opposite="release"
    else
      echo "Unsupported build config: ${config}"
      exit 1
    fi

    for project in Core GUI Client; do
      if [[ -f "${APP_DIR}/${project}.pro" ]]; then
        build_component "${project}" "${config}" "${opposite}"
      fi
    done
  done
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

copy_mingw_runtime_deps() {
  local target_dir="$1"
  shift
  local queue=("$@")

  if [[ -z "${OBJDUMP_BIN}" ]]; then
    echo "objdump not found; runtime dependency auto-copy skipped"
    return
  fi

  declare -A seen=()
  local item dep dep_key dep_path

  while ((${#queue[@]} > 0)); do
    item="${queue[0]}"
    queue=("${queue[@]:1}")

    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      dep_key="${dep,,}"
      if [[ -n "${seen[${dep_key}]+x}" ]]; then
        continue
      fi
      seen["${dep_key}"]=1

      dep_path="/mingw64/bin/${dep}"
      if [[ -f "${dep_path}" ]]; then
        cp -f "${dep_path}" "${target_dir}/"
        queue+=("${dep_path}")
      fi
    done < <("${OBJDUMP_BIN}" -p "${item}" 2>/dev/null | awk '/DLL Name:/{print $3}')
  done
}

collect_artifacts() {
  local runtime_dir="${ARTIFACTS_DIR}/runtime"
  local portable_dir="${runtime_dir}/portable"
  local release_dir="${runtime_dir}/bin/release"
  local debug_dir="${runtime_dir}/bin/debug"
  local release_bins=()
  local debug_bins=()

  echo "Collecting Windows artifacts"
  rm -rf "${runtime_dir}" "${ARTIFACTS_DIR}/SHA256SUMS"

  mkdir -p "${release_dir}"
  mkdir -p "${debug_dir}"
  mkdir -p "${portable_dir}/languages"
  mkdir -p "${portable_dir}/Emoticons"

  cp "${APP_DIR}/Core/output/release/D-LAN.Core.exe" "${release_dir}/"
  cp "${APP_DIR}/GUI/output/release/D-LAN.GUI.exe" "${release_dir}/"
  cp "${APP_DIR}/Client/output/release/D-LAN.Client.exe" "${release_dir}/"
  release_bins=(
    "${release_dir}/D-LAN.Core.exe"
    "${release_dir}/D-LAN.GUI.exe"
    "${release_dir}/D-LAN.Client.exe"
  )

  if [[ -f "${APP_DIR}/Core/output/debug/D-LAN.Core.exe" ]]; then
    cp "${APP_DIR}/Core/output/debug/D-LAN.Core.exe" "${debug_dir}/"
    debug_bins+=("${debug_dir}/D-LAN.Core.exe")
  fi
  if [[ -f "${APP_DIR}/GUI/output/debug/D-LAN.GUI.exe" ]]; then
    cp "${APP_DIR}/GUI/output/debug/D-LAN.GUI.exe" "${debug_dir}/"
    debug_bins+=("${debug_dir}/D-LAN.GUI.exe")
  fi
  if [[ -f "${APP_DIR}/Client/output/debug/D-LAN.Client.exe" ]]; then
    cp "${APP_DIR}/Client/output/debug/D-LAN.Client.exe" "${debug_dir}/"
    debug_bins+=("${debug_dir}/D-LAN.Client.exe")
  fi

  cp "${release_bins[@]}" "${portable_dir}/"
  cp -R "${APP_DIR}/styles" "${portable_dir}/"
  if [[ -d "${APP_DIR}/GUI/ressources/emoticons" ]]; then
    cp -R "${APP_DIR}/GUI/ressources/emoticons/." "${portable_dir}/Emoticons/"
  else
    echo "Emoticons directory not found; skipping emoticon asset copy"
  fi

  if compgen -G "${APP_DIR}/translations/*.qm" >/dev/null; then
    cp "${APP_DIR}/translations/"*.qm "${portable_dir}/languages/"
  fi

  if [[ -n "${WINDEPLOYQT_BIN}" ]]; then
    # --no-angle is Qt5-only; Qt6's windeployqt does not support it.
    local windeployqt_extra=()
    [[ "${QT_MAJOR}" != "6" ]] && windeployqt_extra+=(--no-angle)
    if ! "${WINDEPLOYQT_BIN}" --release --compiler-runtime "${windeployqt_extra[@]}" --no-translations "${portable_dir}/D-LAN.GUI.exe"; then
      echo "windeployqt failed; retrying without extra flags"
      if ! "${WINDEPLOYQT_BIN}" --release --compiler-runtime --no-translations "${portable_dir}/D-LAN.GUI.exe"; then
        echo "windeployqt failed; continuing without full Qt runtime auto-deployment"
      fi
    fi
  else
    echo "windeployqt was not found; Qt runtime DLL auto-deployment skipped"
  fi

  # Ensure each launch directory has all MinGW runtime DLL dependencies.
  copy_mingw_runtime_deps "${release_dir}" "${release_bins[@]}"
  copy_mingw_runtime_deps "${portable_dir}" "${portable_dir}/D-LAN.Core.exe" "${portable_dir}/D-LAN.GUI.exe" "${portable_dir}/D-LAN.Client.exe"
  if ((${#debug_bins[@]} > 0)); then
    copy_mingw_runtime_deps "${debug_dir}" "${debug_bins[@]}"
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
  local portable_dir="${ARTIFACTS_DIR}/runtime/portable"
  local archive_path="${packages_dir}/d-lan-windows-portable.zip"
  local portable_win_path
  local archive_win_path

  echo "Packaging Windows installable artifacts"
  rm -rf "${packages_dir}"
  mkdir -p "${packages_dir}"

  if [[ ! -d "${portable_dir}" ]]; then
    echo "Portable runtime directory not found at ${portable_dir}"
    exit 1
  fi

  portable_win_path="$("${CYGPATH_BIN}" -w "${portable_dir}")"
  archive_win_path="$("${CYGPATH_BIN}" -w "${archive_path}")"

  powershell.exe -NoProfile -Command "Compress-Archive -Path '${portable_win_path}\\\\*' -DestinationPath '${archive_win_path}' -Force"

  {
    echo "portable_archive=$(basename "${archive_path}")"
    echo "format=zip"
  } > "${packages_dir}/PACKAGES.txt"
}

clean_stale_makefiles() {
  # Remove qmake-generated sub-project Makefiles so that the configured
  # QMAKE_BIN will regenerate them rather than reusing stale ones from a
  # previous Qt version.  The top-level "Makefile-<project>-<config>" files
  # produced by build_component are always regenerated; only the sub-project
  # ones need purging.
  echo "Removing stale sub-project Makefiles"
  find "${APP_DIR}" \( -name "Makefile" -o -name "Makefile.Debug" -o -name "Makefile.Release" \) -delete 2>/dev/null || true
  # Also wipe compiled object files so linking picks up the correct Qt version.
  find "${APP_DIR}" -type d -name ".tmp" | while IFS= read -r d; do rm -rf "${d}"; done
}

refresh_generated_protos
generate_protos
verify_generated_protos_idempotent
verify_protocol_compatibility
generate_translations
clean_stale_makefiles
build_all
collect_artifacts
package_artifacts

echo "Windows build completed"
