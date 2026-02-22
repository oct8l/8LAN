# Dependency Policy (Phase 2)

Last updated (UTC): 2026-02-19T13:02:27Z

## Objective
Lock a practical, low-risk dependency baseline so modernization can proceed without reopening toolchain drift on every change.

## Decisions
- Qt track: stay on Qt `5.15.x` for the active modernization line.
- Protobuf policy: require `protoc` major `>= 3` and regenerate `.pb.*` sources in CI.
- qtservice strategy: keep vendored `application/Libs/qtservice` for now, patch for compatibility as needed, defer replacement/removal decision until after core API migrations are stable.

## Rationale
- Qt 6 migration is significantly larger (widgets, signals/slots, deprecated APIs) and would slow stabilization of the 1.1 line.
- Current Windows/Linux builds are already viable on modern Qt5 + protobuf3 toolchains.
- Keeping qtservice in-place minimizes platform service-management churn during dependency and API migration work.

## CI Enforcement
- `.github/scripts/ci-verify-deps.sh` enforces:
  - Qt major `5` and minor `>= 15`
  - `protoc` major `>= 3`
- Both Linux and Windows build scripts call this check and publish `DEPENDENCY_POLICY.txt` in artifacts.

## Out of Scope for Phase 2
- Removing legacy fallback paths in all packaging/installers.
- Full Qt 6 migration.
- Replacing qtservice with native service wrappers.

## Phase 3 Entry Criteria
- Dependency policy checks remain green in CI.
- Proceed to dependency wiring cleanup and packaging metadata refresh:
  - remove machine-local protobuf path assumptions,
  - refresh installer/runtime dependency declarations,
  - align distro package metadata.
