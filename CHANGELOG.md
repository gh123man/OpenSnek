# Changelog

All notable changes to this project are documented in this file.

## [2026-03-08]

### Fixed
- BLE DPI stage value parsing no longer drops the last stage when read payload length is short by one byte.
- Active-stage selection now maps correctly to the stage actually selected on-device during mouse-button stage cycling.
- Removed unstable BLE active-stage nudge/toggle write behavior that caused stage-value collapse in some multi-stage transitions.

### Changed
- `OpenSnekMac` and `OpenSnekProbe` now decode BLE active stage using stage-id mapping from the current payload entries.
- BLE stage-table writes in Swift now preserve stage IDs from the current snapshot to keep UI stage selection aligned with hardware cycling.
- BLE protocol documentation now distinguishes protocol observations from per-client implementation behavior.

### Added
- Hardware BLE DPI reliability test (`OPEN_SNEK_HW=1 swift test --package-path OpenSnekMac --filter HardwareDpiReliabilityTests`).
- Regression-focused validation workflow in `README.md`, `OpenSnekMac/README.md`, and `AGENTS.md` including CLI, hardware, and log-based checks.
