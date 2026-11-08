# App Store feasibility experiment

Branch: `experiment/app-store-sandbox`. This is an isolated diagnostic app, not an App Store-ready edition or a replacement for toneboy's permission UI.

## What was built

`SandboxProbe` is a separate executable target that depends only on `AudioDSP`. It does not compile or link the production `Tonebar` target or its private permission adapter. The copied audio-engine implementation is intentionally local to this spike; consolidate it only after deciding on a production approach.

The bundle is `app.toneboy.sandboxprobe`, with App Sandbox and the Audio Input entitlement enabled. It uses the documented Core Audio process tap APIs and `NSAudioCaptureUsageDescription`. No private TCC framework is loaded, and no permission database is read or changed.

```sh
bash build-sandbox-probe.sh
bash verify-sandbox-probe.sh
open '../toneboy Sandbox Probe.app' --args --start-capture
```

The build is ad-hoc signed by default. Set `TONEBOY_SIGN_IDENTITY` for a suitable local signing identity. This is not an App Store-signed or notarized release.

## Startup and permission semantics

Starting the tap/aggregate triggers macOS's own system audio permission request. There is no permission preflight in this probe.

The tap starts **unmuted**, with rendering disabled in the DSP callback. This prevents silence or doubled playback while checking capture. Callback success alone is never treated as permission approval. Real nonzero input enables the manual EQ test button, which changes the tap's mute behavior and enables the processed output.

No input is deliberately reported as unknown: it can mean silence, access denial, a protected source, or an unsupported route. The probe cannot automatically identify which. It never stores a fabricated permission grant.

For this experiment, processing is stopped after three seconds without input, after five seconds without callbacks, on route changes, and on sleep. These are diagnostic safety rules, **not a shippable final UX**: valid silence would also stop EQ. Opening Settings and returning restarts capture, but if macOS terminates the process during a permission change, the app has to be reopened.

## Local observations — 2026-11-08

Environment: macOS 26.2, Apple Silicon, built-in stereo speakers at 48 kHz. No microphone stream was intentionally enabled; physical input streams are disabled before capture starts.

| Check | Result |
| --- | --- |
| Signature contains App Sandbox and Audio Input entitlements | Passed |
| Probe binary contains private TCC entry points or framework path | None found |
| Launch inside a sandbox container | Observed; diagnostic report was written inside the app container |
| First capture triggers the system audio consent prompt | Confirmed by user; Allow selected |
| Capture external test audio | Nonzero input observed, peak approximately 0.03494, callbacks advancing |
| Switch existing tap to muted processing and select a −12 dB bass cut | Public API call succeeded; processing state and continuing input observed |
| User revokes probe access in Settings, followed by relaunch | Callbacks continued but all captured samples were zero during an external test tone; EQ activation stayed disabled |
| User restores probe access, followed by relaunch | Nonzero capture resumed, peak approximately 0.03493 |
| DSP and lifecycle suite | 26 tests passed locally, including two new output-gating/silent-callback tests |

The EQ test verified route setup and callback operation, not acoustic output fidelity or latency. There was no independent loopback measurement or explicit listening confirmation of the bass cut. The initial consent denial button was not tested separately from revocation in Settings. No sleep, AirPods, USB, Intel, long-duration, or older macOS hardware test was performed in this experiment.

A user reported that the probe was no longer open after changing access; reopening restored the test. The cause of termination was not independently traced. Automatic recovery while the process remains alive must not be presented as automatic relaunch after macOS terminates it.

## Conclusion and remaining work

Core Audio process-tap capture and the tested EQ routing operations can run inside App Sandbox on this machine using public APIs. This removes one feasibility concern; it does **not** establish Mac App Store acceptance or solve the permission UX.

Before an App Store edition:

1. Decide how to handle unknown permission during silence without false active states or a muted Mac. Investigate a public permission flow with a reliable result; do not silently substitute screen/microphone permission for system-audio permission.
2. Validate the same route and failure recovery across supported macOS versions and physical outputs.
3. Configure appropriate signing, provisioning, entitlements, and App Store packaging.
4. Resolve distribution rights for all included code and contributions. This repository is GPL-3.0-only; no extra licensing rights are implied by this experiment.
5. Complete review preparation; only Apple can decide acceptance.

## References

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [Apple: Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)
- [Apple: App Review software requirements](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
- The installed macOS SDK documents `kAudioTapPropertyDescription` as supporting changes to an existing tap description.

The app writes a local `report.json` under its sandbox Application Support directory. It contains counters, current input peak, phase, device name, and process metadata, but no audio samples. Do not publish raw reports without reviewing local paths and device names.
