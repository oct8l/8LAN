#!/usr/bin/env bash
# ci-linux-qt6-setup.sh — Install Qt 6 build dependencies on Ubuntu 22.04.
#
# Qt 6 package breakdown (Ubuntu 22.04 / jammy):
#   qt6-base-dev        — Qt6Core, Qt6Network, Qt6Gui, Qt6Widgets; provides qmake6
#   qt6-declarative-dev — Qt6Qml (QJSEngine); replaces qtscript5-dev
#   qt6-l10n-tools      — lrelease6 (translation compiler)
#   protobuf-compiler / libprotobuf-dev — same as Qt 5 builds
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  qt6-base-dev \
  qt6-declarative-dev \
  qt6-l10n-tools \
  protobuf-compiler \
  libprotobuf-dev

# Detect the Qt6 lrelease binary — package name and install path vary by
# distro version (may be 'lrelease6' in /usr/bin or 'lrelease' under /usr/lib/qt6/bin).
LRELEASE_BIN=""
for candidate in lrelease6 /usr/lib/qt6/bin/lrelease /usr/lib/x86_64-linux-gnu/qt6/bin/lrelease; do
  if command -v "${candidate}" >/dev/null 2>&1 || [[ -x "${candidate}" ]]; then
    LRELEASE_BIN="${candidate}"
    break
  fi
done
if [[ -n "${LRELEASE_BIN}" && -n "${GITHUB_ENV:-}" ]]; then
  echo "LRELEASE_BIN=${LRELEASE_BIN}" >> "${GITHUB_ENV}"
fi

echo "qmake6:    $(command -v qmake6 2>/dev/null || echo 'not found')"
echo "lrelease:  ${LRELEASE_BIN:-not found}"
echo "protoc:    $(command -v protoc)"
