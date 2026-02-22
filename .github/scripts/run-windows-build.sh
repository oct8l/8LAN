#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

ENV_FILE="${WIN_ENV_FILE:-${ROOT_DIR}/.env}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

REMOTE_USER="${WIN_USER:-}"
REMOTE_HOST="${WIN_HOST:-}"
REMOTE_PASS="${WIN_PASS:-}"
REMOTE_DIR="${WIN_DIR:-/c/dlan-work}"
JOBS="${JOBS:-8}"
BUILD_CONFIGS="${BUILD_CONFIGS:-release}"
DEPLOY_DESKTOP="${DEPLOY_DESKTOP:-0}"
DESKTOP_DIR="${WIN_DESKTOP_DIR:-/c/Users/${REMOTE_USER}/Desktop}"
DESKTOP_NAME="${WIN_DESKTOP_NAME:-D-LAN-portable}"

DO_SYNC=1
SYNC_MODE="changed"

LOG_DIR="${WIN_LOG_DIR:-${TMPDIR:-/tmp}/dlan-windows-build-logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${WIN_LOG_FILE:-${LOG_DIR}/build-${TIMESTAMP}.log}"

usage() {
  cat <<'EOF'
Usage:
  .github/scripts/run-windows-build.sh [options]

Options:
  --all-sync     Sync full tree before build (default syncs changed files only)
  --no-sync      Skip sync step
  --jobs N       Parallel build jobs (default: 8)
  --configs L    Build config list passed to CI script (default: "release")
  --deploy-desktop
                 Copy built portable runtime to remote Desktop after successful build
  --desktop-dir P
                 Remote Desktop path (default: /c/Users/<user>/Desktop)
  --desktop-name N
                 Output folder name on Desktop (default: D-LAN-portable)
  --log-file P   Write build log to path P
  -h, --help     Show this help

Environment overrides:
  WIN_ENV_FILE, WIN_USER, WIN_HOST, WIN_PASS, WIN_DIR, WIN_LOG_DIR, WIN_LOG_FILE, JOBS, BUILD_CONFIGS
  DEPLOY_DESKTOP, WIN_DESKTOP_DIR, WIN_DESKTOP_NAME

Credential loading:
  If present, ${ROOT_DIR}/.env is sourced automatically.
  Set WIN_ENV_FILE to use a different file.

Expected .env keys for remote access:
  WIN_USER, WIN_HOST, WIN_PASS, WIN_DIR, WIN_LOG_DIR, WIN_LOG_FILE, JOBS, BUILD_CONFIGS
  DEPLOY_DESKTOP, WIN_DESKTOP_DIR, WIN_DESKTOP_NAME
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 2
  fi
}

require_value() {
  local key="$1"
  local value="${!key:-}"
  if [[ -z "${value}" ]]; then
    echo "Missing required setting: ${key}" >&2
    echo "Set it in ${ENV_FILE} (or via environment)." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-sync)
      SYNC_MODE="all"
      shift
      ;;
    --no-sync)
      DO_SYNC=0
      shift
      ;;
    --jobs)
      if [[ $# -lt 2 ]]; then
        echo "--jobs requires a value" >&2
        exit 2
      fi
      JOBS="$2"
      shift 2
      ;;
    --configs)
      if [[ $# -lt 2 ]]; then
        echo "--configs requires a value" >&2
        exit 2
      fi
      BUILD_CONFIGS="$2"
      shift 2
      ;;
    --deploy-desktop)
      DEPLOY_DESKTOP=1
      shift
      ;;
    --desktop-dir)
      if [[ $# -lt 2 ]]; then
        echo "--desktop-dir requires a value" >&2
        exit 2
      fi
      DESKTOP_DIR="$2"
      shift 2
      ;;
    --desktop-name)
      if [[ $# -lt 2 ]]; then
        echo "--desktop-name requires a value" >&2
        exit 2
      fi
      DESKTOP_NAME="$2"
      shift 2
      ;;
    --log-file)
      if [[ $# -lt 2 ]]; then
        echo "--log-file requires a path" >&2
        exit 2
      fi
      LOG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

require_value REMOTE_USER
require_value REMOTE_HOST
require_value REMOTE_PASS

require_command sshpass
require_command ssh
require_command tee

mkdir -p "$(dirname "${LOG_FILE}")"

remote_has_build_prereqs() {
  sshpass -p "${REMOTE_PASS}" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=8 \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "C:/msys64/usr/bin/bash.exe -lc \"cd '${REMOTE_DIR}' && [[ -f .github/scripts/ci-windows-build.sh && -f .github/scripts/ci-verify-deps.sh ]]\"" \
    >/dev/null 2>&1
}

ensure_remote_build_prereqs() {
  if remote_has_build_prereqs; then
    return 0
  fi

  if [[ "${DO_SYNC}" -eq 1 && "${SYNC_MODE}" != "all" ]]; then
    echo "Remote build scripts are missing; running full sync to repair workspace drift"
    ./.github/scripts/sync-windows-workdir.sh --all
    if remote_has_build_prereqs; then
      return 0
    fi
  fi

  echo "Remote workspace missing required build scripts (.github/scripts/ci-windows-build.sh, ci-verify-deps.sh)." >&2
  echo "Run with --all-sync once to bootstrap the remote workspace." >&2
  return 2
}

if [[ "${DO_SYNC}" -eq 1 ]]; then
  if [[ "${SYNC_MODE}" == "all" ]]; then
    ./.github/scripts/sync-windows-workdir.sh --all
  else
    ./.github/scripts/sync-windows-workdir.sh
  fi
fi

ensure_remote_build_prereqs

echo "Running remote Windows build on ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
echo "Capturing log to ${LOG_FILE}"

set +e
sshpass -p "${REMOTE_PASS}" ssh \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=8 \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "C:/msys64/usr/bin/bash.exe -lc \"set -euo pipefail; cd '${REMOTE_DIR}'; JOBS='${JOBS}' BUILD_CONFIGS='${BUILD_CONFIGS}' bash .github/scripts/ci-windows-build.sh\"" \
  2>&1 | tee "${LOG_FILE}"
ssh_status=${PIPESTATUS[0]}
set -e

echo "Build exit code: ${ssh_status}"
echo "Log: ${LOG_FILE}"

if [[ "${ssh_status}" -eq 0 && "${DEPLOY_DESKTOP}" -eq 1 ]]; then
  desktop_root="${DESKTOP_DIR%/}"
  desktop_target="${desktop_root}/${DESKTOP_NAME}"
  portable_src="${REMOTE_DIR}/artifacts/windows/runtime/portable"

  echo "Deploying portable runtime to ${REMOTE_USER}@${REMOTE_HOST}:${desktop_target}"
  sshpass -p "${REMOTE_PASS}" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=8 \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "C:/msys64/usr/bin/bash.exe -lc \"set -euo pipefail; if [[ ! -d '${portable_src}' ]]; then echo 'Portable runtime not found at ${portable_src}'; exit 1; fi; mkdir -p '${desktop_root}'; rm -rf '${desktop_target}'; mkdir -p '${desktop_target}'; cp -a '${portable_src}/.' '${desktop_target}/'; printf 'Deployed portable runtime to %s\\n' '${desktop_target}'\""
fi

exit "${ssh_status}"
