# D-LAN Raspberry Pi Build Guide

Last updated: 2026-02-21

## Overview

D-LAN builds and runs on Raspberry Pi using the standard Linux build path. This guide covers both
native compilation on the Pi and cross-compilation from an x86_64 host.

Verified configurations:
- **Raspberry Pi OS (Bookworm, 64-bit)** — Raspberry Pi 3/4/5 (ARM64)
- **Raspberry Pi OS (Bullseye, 32-bit)** — Raspberry Pi 2/3 (ARMv7)

---

## Native Build (on the Raspberry Pi)

### Prerequisites

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    qt5-qmake \
    qtbase5-dev \
    qttools5-dev \
    qttools5-dev-tools \
    libqt5svg5-dev \
    libprotobuf-dev \
    protobuf-compiler
```

> **Protobuf version note**: Raspberry Pi OS Bookworm ships protobuf 3.21.x which works with
> D-LAN's `syntax = "proto2"` protos. If you need protobuf 4.x (with Abseil), build from source
> or use the official protobuf apt repo.

### Build

```bash
git clone https://github.com/oct8l/D-LAN.git
cd D-LAN/application

# Build Core
cd Core && qmake && make -j$(nproc) && cd ..

# Build GUI
cd GUI && qmake && make -j$(nproc) && cd ..

# Build Client (optional, for GUI remote control)
cd Client && qmake && make -j$(nproc) && cd ..
```

### Run

```bash
# Start the core daemon:
./Core/output/release/D-LAN.Core &

# Start the GUI (requires a desktop environment):
./GUI/output/release/D-LAN.GUI
```

---

## Cross-Compilation (from x86_64 host)

Cross-compilation is useful for faster build iteration. It requires a Raspberry Pi sysroot and
the appropriate cross-compiler.

### Install cross-toolchain (Ubuntu/Debian host)

**For 64-bit Pi (ARM64):**
```bash
sudo apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

**For 32-bit Pi (ARMv7):**
```bash
sudo apt install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
```

### Obtain a Pi sysroot

The easiest method is to copy `/usr` and `/lib` from a running Pi:

```bash
rsync -avz pi@<pi-ip>:/usr/ ~/pi-sysroot/usr/
rsync -avz pi@<pi-ip>:/lib/ ~/pi-sysroot/lib/
```

Install Qt5 and protobuf on the Pi first (see Native Build prerequisites above).

### Cross-compile with qmake

Create a Qt cross-compilation spec or use the Pi's Qt mkspecs via the sysroot. The exact qmake
invocation depends on your sysroot layout. A minimal approach using `cmake` (for projects with
cmake support) is simpler for cross-compilation.

For qmake-based builds, set `QMAKESPEC`, `INCLUDEPATH`, and `LIBS` to point into the sysroot.

---

## Performance Notes

- Raspberry Pi 4 (4 GB, 64-bit): full release build completes in ~10–15 minutes natively.
- Raspberry Pi 3: ~25–35 minutes.
- Use `-j$(nproc)` to parallelize across all cores.

---

## Headless / Server Mode

D-LAN.Core runs headlessly (no display required). Only D-LAN.GUI requires a desktop environment
or Wayland/X11 forwarding.

To start Core as a background service on boot, use a systemd unit:

```ini
[Unit]
Description=D-LAN Core
After=network.target

[Service]
ExecStart=/opt/d-lan/D-LAN.Core
Restart=on-failure
User=pi

[Install]
WantedBy=multi-user.target
```

---

## CI Note

The Linux CI job (`ubuntu-22.04`, x86_64) validates the codebase on each push. The same sources
build without modification on Raspberry Pi OS — no platform-specific code paths exist for ARM
beyond what the compiler and Qt runtime handle automatically.

A dedicated ARM64 CI job (using GitHub-hosted ARM64 runners or QEMU) is tracked as a potential
future addition once GitHub's ARM64 hosted runners are more broadly available.
