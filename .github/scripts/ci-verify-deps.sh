#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
OUT_DIR="${2:-}"
QMAKE_BIN="${3:-}"
PROTOC_BIN="${4:-}"

if [[ -z "${TARGET}" || -z "${OUT_DIR}" || -z "${QMAKE_BIN}" || -z "${PROTOC_BIN}" ]]; then
  echo "Usage: $0 <target> <out_dir> <qmake_bin> <protoc_bin>" >&2
  exit 2
fi

qt_version="$("${QMAKE_BIN}" -query QT_VERSION 2>/dev/null || true)"
if [[ -z "${qt_version}" ]]; then
  qt_version="$("${QMAKE_BIN}" --version 2>/dev/null | awk '{print $NF}' | rg -m1 '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || true)"
fi

if [[ -z "${qt_version}" ]]; then
  echo "Unable to determine Qt version from qmake: ${QMAKE_BIN}" >&2
  exit 1
fi

qt_major="${qt_version%%.*}"
qt_minor="$(echo "${qt_version}" | cut -d. -f2)"

# ACCEPT_QT6=1 allows Qt 6.x builds (experimental / non-blocking CI jobs).
# When unset or 0, the policy strictly requires Qt 5.15.x (the production baseline).
ACCEPT_QT6="${ACCEPT_QT6:-0}"

if [[ "${ACCEPT_QT6}" == "1" ]]; then
  if [[ "${qt_major}" != "5" && "${qt_major}" != "6" ]]; then
    echo "Dependency policy: Qt must be 5 or 6, found ${qt_version}" >&2
    exit 1
  fi
  if [[ "${qt_major}" == "5" && ( -z "${qt_minor}" || "${qt_minor}" -lt 15 ) ]]; then
    echo "Dependency policy: Qt 5 must be >= 5.15, found ${qt_version}" >&2
    exit 1
  fi
else
  if [[ "${qt_major}" != "5" ]]; then
    echo "Dependency policy violation: Qt major must be 5, found ${qt_version}" >&2
    exit 1
  fi
  if [[ -z "${qt_minor}" || "${qt_minor}" -lt 15 ]]; then
    echo "Dependency policy violation: Qt must be >= 5.15, found ${qt_version}" >&2
    exit 1
  fi
fi

protoc_version="$("${PROTOC_BIN}" --version 2>/dev/null | awk '{print $2}')"
if [[ -z "${protoc_version}" ]]; then
  echo "Unable to determine protoc version from: ${PROTOC_BIN}" >&2
  exit 1
fi

protoc_major="${protoc_version%%.*}"
if [[ -z "${protoc_major}" || "${protoc_major}" -lt 3 ]]; then
  echo "Dependency policy violation: protoc major must be >= 3, found ${protoc_version}" >&2
  exit 1
fi

POLICY_QT="5.15.x"
[[ "${ACCEPT_QT6}" == "1" ]] && POLICY_QT="5.15.x or 6.x"

mkdir -p "${OUT_DIR}"
{
  echo "target=${TARGET}"
  echo "qt_version=${qt_version}"
  echo "protoc_version=${protoc_version}"
  echo "policy_qt=${POLICY_QT}"
  echo "policy_protoc=>=3.x"
} > "${OUT_DIR}/DEPENDENCY_POLICY.txt"

echo "Dependency policy check passed for ${TARGET}: Qt ${qt_version}, protoc ${protoc_version}"
