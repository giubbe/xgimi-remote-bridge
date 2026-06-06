# Changelog

## v1.0.1 - ADB Recovery Stabilization

### Added
- Added `avahi-utils` / `avahi-browse` as a documented requirement for discovering Android Wireless Debugging dynamic ADB ports.
- Added documentation for pairing the Raspberry Pi bridge with Android Wireless Debugging.
- Added troubleshooting steps for ADB recovery failures:
  - stale dynamic ADB ports;
  - TCP-open but unauthorized ADB connections;
  - missing wireless debugging pairing;
  - recovery to stable TCP port `5555`.

### Changed
- Improved ADB recovery documentation.
- Clarified the role of `adb-auto-enable`, dynamic ADB ports and port `5555`.
- Updated LMS/Jivelite feedback documentation for ADB recovery status messages.

### Fixed
- Documented recovery procedure when `adb-auto-enable` reports an old `lastPort`.
- Documented how to re-authorize the Raspberry Pi bridge when the dynamic ADB port is reachable but `adb connect` fails.
