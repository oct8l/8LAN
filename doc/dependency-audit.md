# D-LAN Vendored Dependency Audit

Last updated (UTC): 2026-02-21T01:45:00Z

This document records upgrade/replacement candidates for vendored and legacy dependencies
identified during post-baseline hardening (Step 5).

---

## 1. MersenneTwister.h

**Location**: `application/Libs/MersenneTwister.h`
**Version**: Wagner v1.1 (September 2009)
**Purpose**: Non-cryptographic pseudo-random number generation (PRNG) for peer ID and salt generation.

### Current Usage
- `Hash::rand()` — generates random peer IDs (`application/Common/Hash.cpp:207-224`)
- `Hash::hashWithRandomSalt()` — generates salt for password hashing (`Hash.cpp:355-365`)

### Issues
- Mersenne Twister state is fully recoverable after 624 consecutive output observations.
- The library header explicitly warns: *"Do NOT use for CRYPTOGRAPHY without securely hashing several returned values together."*
- Peer IDs are not strictly cryptographic but predictability is undesirable.

### Recommendation: Replace
**Replacement**: `QRandomGenerator::global()->generate()` (Qt 5.10+, available on all platforms).
Sources from OS CSPRNG (`/dev/urandom` on Linux/macOS, `CryptGenRandom` on Windows).

**Effort**: Low — two call sites in `Hash.cpp`. No protocol break (peer IDs are local-generated).
**Priority**: Medium — safe for LAN context today; should precede any non-LAN use case.

---

## 2. QtService (vendored)

**Location**: `application/Libs/qtservice/`
**Version**: Qt Solutions QtService 2.6 (last released ~2010, Qt4-era)
**Purpose**: Windows service and Unix daemon integration for `D-LAN.Core`.

### Current Usage
- `CoreService` (Windows) — runs Core as a Windows service.
- `CoreService` (Unix) — runs Core as a Unix daemon.
- `RemoteControlServer` — uses `QtServiceBase` for lifecycle control.

### Issues
- Qt4-era codebase; required compatibility patches during Phase 4 migration:
  - `QCoreApplication::setEventFilter` → `QAbstractNativeEventFilter` (Windows)
  - `TRUE` → `true` (Unix)
  - `qInstallMsgHandler` → `qInstallMessageHandler`
  - `toAscii()` → `toLatin1()`
- Not compatible with Qt 6 without further patching.
- No upstream maintenance; fork/patch-only path going forward.

### Recommendation: Replace (post Qt 6 audit)
**Replacement options**:
1. **Qt 6 path**: Use `QCoreApplication` lifecycle directly + platform-specific service wrappers
   (`sc.exe` on Windows, systemd unit on Linux). Eliminates the dependency entirely.
2. **Short-term**: Continue patch-only maintenance on vendored copy for Qt 5.15 lifetime.

**Effort**: High (requires testing Windows service and Unix daemon launch paths).
**Priority**: Low for Qt 5.15 baseline; Medium when Qt 6 migration begins.

---

## 3. Nvwa (debug_new)

**Location**: `application/Libs/Nvwa/`
**Version**: 4.7 (2010/01/08, by Wu Yongwei)
**Purpose**: Debug memory allocation tracking (overrides `new`/`delete` with leak detection).

### Current Usage
- `#include "debug_new.h"` in debug builds only.
- No runtime impact in release builds.

### Issues
- 2005-2011 vintage; no upstream releases since.
- C++17 and modern allocator patterns may interact unexpectedly with global `new`/`delete` overrides.
- Adds noise to ASAN/LSAN builds if those are ever enabled.

### Recommendation: Evaluate for removal
**Replacement**: AddressSanitizer (`-fsanitize=address`) and LeakSanitizer (`-fsanitize=leak`)
are standard in GCC/Clang and provide superior coverage with no vendored code required.

**Effort**: Low to remove; medium to add ASAN/LSAN CI step.
**Priority**: Low — debug-only, no release impact. Evaluate when adding ASAN to CI.

---

## 4. Abseil (transitive, via protobuf)

**Location**: Not vendored — linked via MSYS2 `mingw-w64-x86_64-protobuf` package.
**Purpose**: Modern protobuf (3.21+) pulls in Abseil as a link dependency.

### Current State
- Abseil DLLs (`libabsl_*.dll`) are included in the Windows portable bundle.
- Link flags in `application/Libs/protobuf.pri` list the required Abseil libs.
- Not pinned to a specific version; tracks whatever MSYS2 ships.

### Issues
- Abseil ABI is not stable across versions; any MSYS2 package update could break the link.
- Current explicit Abseil libs in `protobuf.pri` may become stale if protobuf adds new Abseil deps.

### Recommendation: Document + automate
- Add a `ci-verify-deps.sh` check that lists the actual Abseil libs linked by the built binary
  (`objdump -p` / `ldd`) and records them in `DEPENDENCY_POLICY.txt`.
- Consider pinning the MSYS2 protobuf package version in the workflow when stability is needed.

**Effort**: Low.
**Priority**: Medium — currently working, but fragile on MSYS2 package updates.

---

## 5. Proto syntax declarations (missing `syntax` field)

**Location**: `application/Protos/*.proto`
**Purpose**: All `.proto` files lack explicit `syntax = "proto2"` or `syntax = "proto3"` declarations.

### Issues
- Modern `protoc` emits a deprecation warning on every generation run.
- Future protoc major versions may reject files without `syntax`.
- Current behavior defaults to proto2 semantics.

### Recommendation: Add `syntax = "proto2";` to all .proto files
**Files affected**: `common.proto`, `core_protocol.proto`, `gui_protocol.proto`,
`settings.proto`, `files_cache.proto`, `queue.proto`.

**Effort**: Very low — one-line addition per file. Zero wire format change.
**Priority**: High — straightforward, clears residual CI warning noise.

---

## Summary Table

| Dependency | Version | Risk | Effort | Priority | Action |
|---|---|---|---|---|---|
| MersenneTwister.h | v1.1 (2009) | Medium | Low | Medium | Replace with `QRandomGenerator` |
| QtService | 2.6 (2010) | Low | High | Low/Medium | Patch-only now; replace for Qt 6 |
| Nvwa debug_new | 4.7 (2010) | Low | Low | Low | Remove; add ASAN/LSAN CI step |
| Abseil (transitive) | MSYS2-latest | Medium | Low | Medium | Document + automate version capture |
| Proto syntax decls | n/a | Low | Very low | High | Add `syntax = "proto2"` to all .proto |
