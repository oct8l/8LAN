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

usage() {
  cat <<'EOF'
Usage:
  .github/scripts/sync-windows-workdir.sh [--all]

Default behavior:
  Sync only changed/untracked git files (excluding TODO) to the remote Windows workdir.

Options:
  --all    Sync the whole repository (excluding .git and TODO).

Environment overrides:
  WIN_ENV_FILE, WIN_USER, WIN_HOST, WIN_PASS, WIN_DIR

Credential loading:
  If present, ${ROOT_DIR}/.env is sourced automatically.
  Set WIN_ENV_FILE to use a different file.
EOF
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

tar_supports_option() {
  local option="$1"
  tar "${option}" -cf /dev/null --files-from /dev/null >/dev/null 2>&1
}

build_tar_create_flags() {
  local -a flags=()
  local option
  for option in --no-mac-metadata --no-xattrs --no-acls; do
    if tar_supports_option "${option}"; then
      flags+=("${option}")
    fi
  done
  printf '%s\n' "${flags[@]}"
}

sync_changed() {
  local -a changed_files=()
  mapfile -t changed_files < <(
    git status --porcelain=1 --untracked-files=all \
      | sed -E 's/^.. //' \
      | sed -E 's#^\"##; s#\"$##' \
      | grep -v '^TODO$' \
      || true
  )

  # Keep remote CI helper scripts in sync even when they are not part of the
  # current git-status delta (prevents stale remote script dependencies).
  while IFS= read -r helper_script; do
    changed_files+=("${helper_script}")
  done < <(git ls-files .github/scripts/*.sh)

  # De-duplicate while preserving order.
  local -A seen=()
  local -a files_to_sync=()
  local file
  for file in "${changed_files[@]}"; do
    [[ -z "${file}" ]] && continue
    if [[ -n "${seen[${file}]+x}" ]]; then
      continue
    fi
    seen["${file}"]=1
    files_to_sync+=("${file}")
  done

  if [[ "${#files_to_sync[@]}" -eq 0 ]]; then
    echo "No changed files to sync."
    return 0
  fi

  printf "Syncing %d changed file(s) to %s@%s:%s\n" \
    "${#files_to_sync[@]}" "${REMOTE_USER}" "${REMOTE_HOST}" "${REMOTE_DIR}"

  local -a tar_flags=()
  mapfile -t tar_flags < <(build_tar_create_flags)
  COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 tar "${tar_flags[@]}" -cf - "${files_to_sync[@]}" \
    | sshpass -p "${REMOTE_PASS}" ssh \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=8 \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "C:/msys64/usr/bin/bash.exe -lc \"mkdir -p '${REMOTE_DIR}' && cd '${REMOTE_DIR}' && tar -xf -\""
}

sync_all() {
  printf "Syncing full tree to %s@%s:%s\n" \
    "${REMOTE_USER}" "${REMOTE_HOST}" "${REMOTE_DIR}"

  local -a tar_flags=()
  mapfile -t tar_flags < <(build_tar_create_flags)
  COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 tar "${tar_flags[@]}" -cf - --exclude .git --exclude TODO . \
    | sshpass -p "${REMOTE_PASS}" ssh \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=8 \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "C:/msys64/usr/bin/bash.exe -lc \"mkdir -p '${REMOTE_DIR}' && cd '${REMOTE_DIR}' && tar -xf -\""
}

case "${1:-}" in
  "")
    require_value REMOTE_USER
    require_value REMOTE_HOST
    require_value REMOTE_PASS
    sync_changed
    ;;
  --all)
    require_value REMOTE_USER
    require_value REMOTE_HOST
    require_value REMOTE_PASS
    sync_all
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown option: ${1}" >&2
    usage
    exit 2
    ;;
esac
