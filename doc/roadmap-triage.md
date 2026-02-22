# D-LAN P3 Roadmap Triage

Last updated (UTC): 2026-02-21T08:00:00Z

## Sources
- GitHub wiki (47 pages, Wayback-scraped from Redmine): https://github.com/oct8l/D-LAN/wiki/
- Wiki sections consulted: Brainstorming, Changelog, Constraints, Security, Architecture, Libraries

## Classification Key
- `compatibility` — required for builds, interop, or platform support
- `security` — vulnerability, crypto weakness, or safety improvement
- `performance` — runtime efficiency, memory, throughput
- `UX` — user-visible feature or interface improvement

---

## Top 10 Triage Items

### 1. Peer ID Theft Vulnerability  `security` ✓ Assessed (H10)
**Source**: [Security wiki](https://github.com/oct8l/D-LAN/wiki/Security)

The security wiki explicitly documents this as a known vulnerability with no mitigation:
> "A peer steals the peerID from an other peer" — listed but no solution provided.

Peer IDs were generated with Mersenne Twister (now replaced with CSPRNG in H2). There is no
cryptographic proof-of-identity; any peer can claim any ID.

**Status**: Assessed in H10. See `doc/peer-id-security-assessment.md` for full analysis.

**Summary**: Risk accepted for v1.x (LAN-only scope; requires local LAN presence). Recommended
path: HMAC-signed IMAlive as an additive v1.x improvement; Ed25519 keypair ID (Option B)
deferred to v2.0 alongside the SHA-1 → SHA-256 protocol version bump.

---

### 2. Mersenne Twister → CSPRNG for Peer ID / Salt Generation  `security` ✓ Done (H2)
**Source**: `application/Libs/MersenneTwister.h:92-94`, `application/Common/Hash.cpp:207-224`

MT state is recoverable after 624 observed outputs. Peer IDs and hash salts are generated with it.
`QRandomGenerator::global()->generate()` (Qt 5.10+) sources from the OS CSPRNG on all platforms.

**Status**: Completed in H2. All 7 production call sites replaced (`Hash.cpp`, `Core.cpp`,
`UDPListener.cpp`, `Search.cpp`, `FileDownload.cpp`, `RemoteConnection.cpp`,
`InternalCoreConnection.cpp`). `MersenneTwister.h` retained in `Libs/` for test helpers only.

---

### 3. Chunk Hash Algorithm: SHA-1 → SHA-256  `security`
**Source**: Changelog (SHA-1 chunk verification noted), `application/Common/Hash.cpp:259`

SHA-1 is deprecated for collision resistance. D-LAN uses it for chunk verification hashes.
Upgrading to SHA-256 is a **protocol break** (wire format and cache format change).

**Action**: Flag as a post-1.x protocol versioning milestone. Define a protocol version bump that
updates `HASH_SIZE` and the hash algorithm, with a migration path for existing caches.
Do not block near-term releases on this; track as a v2.0 protocol concern.

---

### 4. Missing `syntax` Declarations in `.proto` Files  `compatibility` ✓ Done (H1)
**Source**: `application/Protos/*.proto`, CI warning floor

All `.proto` files lack explicit `syntax = "proto2"` or `syntax = "proto3"` declarations.
Modern `protoc` warns on every generation run. Future protoc major versions may error.

**Status**: Completed in H1. `syntax = "proto2";` added to all 7 `.proto` files
(`common`, `core_protocol`, `core_settings`, `files_cache`, `gui_protocol`, `gui_settings`,
`queue`). CI proto-idempotency check confirmed byte-identical generated output before and after.

---

### 5. Qt 6 Migration Readiness  `compatibility` ✓ Done (H6 + H9)
**Source**: `doc/dependency-policy.md`, modernization decisions log

**Status**: Audit completed in H6; all low-effort migration items completed in H9.
See `doc/qt6-delta.md` for the full delta list.

Summary of what was found (H6) and resolved (H9):
- **Removed in Qt 6 — resolved:** `QtScript` replaced with `QJSEngine` (Client.pro +
  D-LAN_Client.h/cpp; no version guards needed — QJSEngine is available Qt 5.0+).
  `QtWinExtras` guarded out with `lessThan(QT_MAJOR_VERSION, 6)` in GUI.pro;
  `QtWin::fromHICON` replaced with `QImage::fromHICON` under Qt6 version guard in `IconProvider.cpp`.
- **Already guarded:** `QTextCodec` in all three `main.cpp` files — no action needed.
- **Deprecated macros — all converted:** All 42 `SIGNAL()`/`SLOT()` macros in tests/tools
  converted to typed function-pointer `connect()` syntax. Pre-existing type mismatch bug in
  `NetworkListener/Tests/Tests.cpp` fixed as a side effect.
- **`foreach()` loops — converted:** 62 of 63 converted to C++11 range-based `for`. 1 remaining
  in vendored `qtservice_unix.cpp` (intentionally left alone).
- **Vendored `qtservice`:** grep confirmed zero `QSysInfo::windowsVersion`/`macVersion` calls —
  already clean, no changes needed.
- **Everything else:** confirmed stable — no action needed.

**Result (H9):** First-party D-LAN code has zero `SIGNAL()`/`SLOT()` macros, zero `foreach()` loops,
and both Qt6 hard-removal blockers are resolved. A Qt 6 build is now feasible.

---

### 6. macOS Build Support  `compatibility` ✓ Done (H5)
**Source**: Constraints wiki (platform requirements: Windows, Linux, macOS)

macOS is a declared target platform (`.dmg` artifact required per constraints) but is absent from
CI. The `modernize-1.1` branch has no macOS CI job and no macOS-specific build verification.

**Status**: Completed in H5. Non-blocking `macos-build` job added to `phase1-build.yml` using
`macos-latest` (Apple Silicon arm64) + Homebrew `qt@5` + `protobuf`. Core/GUI/Client all compile
and link. Required platform fixes: `Q_OS_LINUX` → `Q_OS_UNIX` in two source files,
`unix:!macx` guards in `FileManager.pro`, Homebrew keg/Abseil include and link paths in
`protobuf.pri`. Smoke artifact uploaded each run as `d-lan-macos-phase1-{N}`.

---

### 7. ARM / Raspberry Pi Build Support  `compatibility` ✓ Done (H11)
**Source**: Changelog (1.1.0 Beta 15: "First release on Raspberry Pi (Rasbian)")

The last upstream release notes Pi support, but there is no CI validation and no documented
cross-compile or native Pi build path in the current modernization branch.

**Status**: Completed in H11. See `doc/raspberry-pi-build.md` for native and cross-compile
instructions. The Linux codebase builds on Raspberry Pi OS without platform-specific changes.
A dedicated ARM64 CI job is tracked for when GitHub ARM64 hosted runners are broadly available.

---

### 8. IMAlive Flood Rate Limiting  `security` ✓ Done (H8)
**Source**: [Security wiki](https://github.com/oct8l/D-LAN/wiki/Security)

IP-based banning for excessive IMAlive messages is the documented mitigation. Audit (H4) found
**the feature did not exist in the 1.1 codebase**. Implemented in H8.

**Status**: Completed in H8.
- `core_settings.proto` fields 92 (`imalive_max_per_ip_per_min`, default 30) and 93
  (`imalive_ban_duration_ms`, default 60000 ms) expose the thresholds.
- `Core::checkSettingsIntegrity()` range-guards both fields.
- `UDPListener::processPendingMulticastDatagrams()` maintains a `QHash<QHostAddress, ImAliveIpStats>`
  with a rolling 60-second count window. Sources exceeding `imalive_max_per_ip_per_min` are
  silently dropped and banned for `imalive_ban_duration_ms`, logged at WARN.
- Check is placed before `ParseFromArray` to avoid CPU amplification from flood payloads.
- Map is purged of non-banned entries on each window rollover to bound memory usage.

---

### 9. Download/Upload Rate Graph  `UX`
**Source**: [Brainstorming wiki](https://github.com/oct8l/D-LAN/wiki/Brainstorming) (v1.3 planned)

Upstream planned a time-series graph of download/upload rates with data persistence and CSV export.
This was targeted for v1.3 but never shipped.

**Action**: Defer until after build/protocol stabilization. Mark as a post-baseline UX enhancement.
Relevant hook point: `TransfertRateCalculator` in `Common`.

---

### 10. Shareable File/Chat Links (Custom Protocol URL Scheme)  `UX`
**Source**: [Brainstorming wiki](https://github.com/oct8l/D-LAN/wiki/Brainstorming) (v1.4 planned)

Upstream planned URL handling for chat, logs, and file sharing using a custom `d-lan://` scheme,
enabling copy-paste-able peer/file references.

**Action**: Defer until after protocol stabilization. Could be implemented as a `d-lan://` URI
scheme registered on Windows/Linux/macOS, parsed by the Client or GUI. Low effort for UX gain
once protocol is stable.

---

## Items Explicitly Not Planned (from upstream wiki)

The following were explicitly called out as out-of-scope in the original project; carry that
decision forward unless user requirements change:

- Bandwidth/CPU limitation toggles
- Duplicate file detection
- Tag/comment systems for shares
- Virtual folder aggregation across peers
- IPv6 as default (IPv4 default retained; IPv6 remains optional)
- Plugin architecture
- Lucene-based advanced search
- Peer voting/reputation system
- IRC chat bridging

---

## Summary Table

| # | Item | Class | Effort | Protocol Break? | Status |
|---|------|--------|--------|----------------|--------|
| 1 | Peer ID theft vulnerability assessment | security | medium | no (assessment only) | **done (H10)** |
| 2 | MT RNG → QRandomGenerator | security | low | no | **done (H2)** |
| 3 | SHA-1 → SHA-256 chunk hashes | security | high | yes (v2.0 protocol) | deferred |
| 4 | Add `syntax` to `.proto` files | compatibility | low | no | **done (H1)** |
| 5 | Qt 6 migration readiness | compatibility | medium | no | **done (H6 + H9)** |
| 6 | macOS CI smoke build | compatibility | low | no | **done (H5)** |
| 7 | Raspberry Pi build docs/CI | compatibility | medium | no | **done (H11)** |
| 8 | IMAlive rate-limit implementation | security | medium | no | **done (H8)** |
| 9 | Download/upload rate graph | UX | high | no | deferred |
| 10 | Shareable d-lan:// URL scheme | UX | medium | no | deferred |
