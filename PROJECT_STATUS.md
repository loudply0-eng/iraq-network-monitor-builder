# Iraq Network Monitor — Active Build and Release Status

Last repository audit: 2026-11-27 (Asia/Baghdad).

This is the canonical hand-off document for future development sessions. The public repository below is the active application source, CI, signing, and production-release path. Do not switch production builds to another repository or create a parallel release path without an explicit migration plan.

## Active repository

- Repository: `loudply0-eng/iraq-network-monitor-builder`
- Default branch: `main`
- Audited main HEAD: `caa01f557828f3598d4cd10081209c1d5ea8cde3` (2026-11-27).
- App version recorded in `pubspec.yaml`, `release_notes.json`, and `changelog.json`: `1.0.28+31`.
- Android application ID: `com.example.abrj_iraq`.
- Flutter SDK: `3.50.0`, pinned to official source commit `ab2912035e160d9cad6306df307576da6128ebdb`.
- Java: 17.
- All active CI/build/release operations are intended to run from this public repository. The private repository's Actions quota was exhausted; do not trigger its workflows or move builds back there.

## Confirmed release history

### Production release — 1.0.28+31

- Public builder Actions run #148, run ID `46055474146`, source commit `caa01f557828f3598d4cd10081209c1d5ea8cde3`.
- Completed successfully on 2026-11-27.
- The run passed Flutter analysis and tests, the release gate, original Android keystore validation, separate OTA signing-key validation, signed release APK build, APK signer identity validation, Ed25519 manifest signing, SFTP publication, and public download/manifest verification.
- APK filename: `iraq-network-monitor-1.0.28-31.apk`.
- APK size: approximately 50.9 MB.
- Published direct APK: `https://mahmoudaljuorany.store/iraq-network-monitor-1.0.28-31.apk`.
- Published app-specific OTA APK: `https://mahmoudaljuorany.store/updates/iraq-network-monitor/iraq-network-monitor-1.0.28-31.apk`.
- Legacy manifest: `https://mahmoudaljuorany.store/version.json`.
- App-specific manifest: `https://mahmoudaljuorany.store/updates/iraq-network-monitor/version.json`.
- App-specific Ed25519 signature: `https://mahmoudaljuorany.store/updates/iraq-network-monitor/version.json.sig`.
- Published APK SHA-256: `0ac456daaae8447a216bacfcd451057344714458eee64689a8f0b7ea3010d6f3`.
- The APK certificate matched the established production certificate fingerprint below. The workflow also verified the signed manifest and downloaded APK hashes from both public paths.
- Treat run #148 as the current confirmed production release.

### CI run for the release change — not a release

- Public builder Actions run #147, run ID `46052313302`, pull request #23.
- Completed successfully as a pull-request CI run.
- This run performed CI/debug validation only; it did not build or publish a production-signed release APK.

### Previous production release — 1.0.27+30

- Public builder Actions run #119, run ID `45017175457`, source commit `05cb09f61d565ca1abffd85b8078d7d9fa794767`.
- Completed successfully on 2026-11-22.
- Superseded by production release `1.0.28+31`.

## Current release pipeline behavior

The workflow `.github/workflows/build.yml` is the canonical release workflow.

1. It checks out this repository and installs the pinned Flutter SDK and Java 17.
2. It runs `flutter pub get --enforce-lockfile`, `flutter analyze --no-fatal-infos`, and `flutter test --reporter expanded`.
3. For trusted pushes/dispatches on `main`, it compares the app version against the public production `version.json`. A same or older version is not released unless an explicit repair-publish dispatch is requested.
4. For a real release, it retrieves the original Android signing key from GitHub Actions secrets, validates the established production certificate, and validates the separate Ed25519 OTA private key against the configured public-key repository variable.
5. It builds the signed APK with obfuscation and split debug information, verifies the APK signing certificate, and stores a short-retention Actions artifact.
6. It generates both a legacy-compatible manifest and a dedicated app-specific OTA manifest, signs the dedicated manifest with Ed25519, and publishes APK/manifests over restricted SFTP when all required SFTP secrets are configured.
7. It verifies the published manifest/signature bytes and checks the SHA-256 of the APK downloaded from both public paths.

A green CI run does not necessarily mean a new signed APK was built or published. Always inspect the release-gate, signing, APK-build, SFTP, and public-verification steps separately.

## Release identity and signing invariants

- Android application ID: `com.example.abrj_iraq`.
- Established production APK certificate SHA-256 (hex, no separators):
  `f29ff0e87eabbe89ce0664727652e870eddca3acbfbfe9fab18505e0340b62b8`.
- Never regenerate, replace, or rotate the original Android keystore as part of ordinary app development.
- The Android APK signing key and the Ed25519 OTA manifest signing key are distinct and must remain separate.
- Secret names referenced by the canonical workflow include:
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
  - `MONITOR_UPDATE_PRIVATE_KEY_PEM`
  - `UPDATE_SFTP_HOST`
  - `UPDATE_SFTP_PORT`
  - `UPDATE_SFTP_USER`
  - `UPDATE_SFTP_PRIVATE_KEY`
  - `UPDATE_SFTP_KNOWN_HOSTS`
  - `UPDATE_SFTP_PATH`
- The public key for OTA validation is stored as repository variable `MONITOR_UPDATE_PUBLIC_KEY_BASE64`.
- Never write secret values, private keys, passwords, tokens, or keystore data to the repository, issue comments, logs, or chat.

## Implemented application features

The current audited application source includes:

### Cellular and Wi-Fi monitoring
- Cellular signal and radio data: RSRP, RSRQ, RSSI, SINR, band/channel identifiers, cell identity, serving and neighboring cells, and SIM details where Android/device support exposes them.
- Wi-Fi analyzer with nearby scan results and channel occupancy suggestions limited to the networks Android allows the app to scan.
- Optional in-app alerts, while the app is open, for signal loss/degradation, cell changes, and 5G detection.
- Configurable RSRP weak-signal alert threshold from `-120` to `-90 dBm`, with default `-110 dBm`, saved across app restarts.
- A 5 dB hysteresis rule to reduce repeated weak-signal alerts from small fluctuations.
- LTE EARFCN/channel calculations and field tools.

### Mapping and field measurements
- Street, satellite, and terrain map layers with map attribution.
- GPS measurement route and signal heatmap.
- Signal history and measurement records.
- CSV copy/export and KML export for Google Earth.
- Path-loss and TCP-latency measurement tools.

### User interface and app maintenance
- Arabic and English UI.
- Dark/light themes and selectable accent colors.
- Dedicated Network, Map, History, and Tools sections.
- Settings, About page, and in-app change history.
- In-app update check and automatic update notification.

### Secure OTA updates
- Dedicated signed update channel.
- Ed25519 signature verification and SHA-256 verification.
- APK signer-certificate identity checks before installation.
- Rejection of manifest redirects and oversized responses/downloads.
- Resumable APK downloads after transient network failures.
- Regression tests for malformed/invalid signed update manifests.

Device-dependent cellular fields are not guaranteed on every Android build, modem, handset, or carrier. Preserve truthful availability indicators and do not claim unsupported radio readings.

## Build and source-control hygiene

- Documentation-only pushes to `main` should not start Android build jobs; the workflow filters `PROJECT_STATUS.md`, `README.md`, `SECURITY.md`, and `docs/**` on `push`. Pull-request checks remain enabled for every PR so the required `build` status is never left pending.
- Keep application code, Android configuration, tests, dependency locks, and workflow changes under CI.
- Pull requests must be built without production signing or deployment secrets.
- Do not use force-publish as a substitute for fixing a source/version mismatch.
- Keep `pubspec.yaml`, `release_notes.json`, and `changelog.json` synchronized for each real app release.
- Increment the app version/build number only for a reviewed app change or a deliberately approved repair release.
- Before claiming an update can install over an existing app, verify the package ID and production signing certificate; preserve existing app data and settings.
- Avoid redundant builds of an already-published version. A tests-only success is not an APK release.

## Next engineering priorities

1. Continue all development, CI, signing, and production releases exclusively through this public repository while the private Actions quota is exhausted.
2. Preserve the current feature set and production signing identities.
3. Reconcile any proposed application-source changes against the current `main` before editing; do not import an older application snapshot over the active code.
4. For the next real app release, update the app, tests, `pubspec.yaml`, Arabic/English release notes, and changelog together, then run the full trusted release pipeline.
5. Inspect the final Actions run and publicly downloaded APK/manifest checks before declaring a release complete.

## Resume instructions

At the start of a new development chat, read this file and then inspect live `main`, `pubspec.yaml`, `release_notes.json`, `changelog.json`, the latest Actions runs, and both public update manifests. Continue from the live repository state. Do not ask the user to re-explain existing features, do not rebuild the older private snapshot, and do not publish a test APK.
