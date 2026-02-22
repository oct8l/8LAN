#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  qt5-qmake \
  qtbase5-dev \
  qtdeclarative5-dev \
  qttools5-dev-tools \
  protobuf-compiler \
  libprotobuf-dev
