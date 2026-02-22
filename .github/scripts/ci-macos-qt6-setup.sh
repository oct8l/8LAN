#!/usr/bin/env bash
# ci-macos-qt6-setup.sh — Install Qt 6 build dependencies on macOS via Homebrew.
#
# On modern Homebrew, 'qt' is Qt 6 (qt@5 is the keg-only Qt 5 formula).
# Qt 6 is not keg-only, so its binaries are linked into the Homebrew prefix bin.
# We still export QMAKE_BIN explicitly to prevent the build script from accidentally
# picking up a system or previously-cached Qt 5 qmake.
#
# protobuf.pri reads PROTOBUF_PREFIX and HOMEBREW_PREFIX from the environment;
# those env vars are identical in layout to the Qt 5 macOS setup.
set -euo pipefail

brew install qt protobuf

HOMEBREW_PREFIX="$(brew --prefix)"
QT6_PREFIX="$(brew --prefix qt)"
PROTOBUF_PREFIX="$(brew --prefix protobuf)"

echo "${QT6_PREFIX}/bin" >> "${GITHUB_PATH}"
echo "HOMEBREW_PREFIX=${HOMEBREW_PREFIX}" >> "${GITHUB_ENV}"
echo "QT6_PREFIX=${QT6_PREFIX}" >> "${GITHUB_ENV}"
echo "PROTOBUF_PREFIX=${PROTOBUF_PREFIX}" >> "${GITHUB_ENV}"
# Export explicit tool paths so ci-linux-build.sh uses Qt 6 even if another
# qmake is already on PATH from a cached runner image.
echo "QMAKE_BIN=${QT6_PREFIX}/bin/qmake" >> "${GITHUB_ENV}"
echo "LRELEASE_BIN=${QT6_PREFIX}/bin/lrelease" >> "${GITHUB_ENV}"

echo "Homebrew prefix: ${HOMEBREW_PREFIX}"
echo "Qt 6 prefix:     ${QT6_PREFIX}"
echo "Protobuf prefix: ${PROTOBUF_PREFIX}"
echo "qmake:           ${QT6_PREFIX}/bin/qmake"
echo "protoc:          $(command -v protoc)"
