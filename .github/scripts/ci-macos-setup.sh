#!/usr/bin/env bash
set -euo pipefail

# Install Qt 5 and protobuf via Homebrew.
# qt@5 is a keg-only formula; binaries are not linked into /usr/local/bin
# automatically, so we export the path for callers to source.

brew install qt@5 protobuf

# Determine the Homebrew prefix for qt@5 (works on both Intel and Apple Silicon).
HOMEBREW_PREFIX="$(brew --prefix)"
QT5_PREFIX="$(brew --prefix qt@5)"
PROTOBUF_PREFIX="$(brew --prefix protobuf)"

# Add qt@5 bin dir to PATH for the duration of this CI run.
echo "${QT5_PREFIX}/bin" >> "${GITHUB_PATH}"
echo "HOMEBREW_PREFIX=${HOMEBREW_PREFIX}" >> "${GITHUB_ENV}"
echo "QT5_PREFIX=${QT5_PREFIX}" >> "${GITHUB_ENV}"
echo "PROTOBUF_PREFIX=${PROTOBUF_PREFIX}" >> "${GITHUB_ENV}"

echo "Homebrew prefix: ${HOMEBREW_PREFIX}"
echo "Qt5 prefix: ${QT5_PREFIX}"
echo "Protobuf prefix: ${PROTOBUF_PREFIX}"
echo "qmake: $(command -v qmake 2>/dev/null || echo 'not in PATH yet (added to GITHUB_PATH for next steps)')"
echo "protoc: $(command -v protoc)"
