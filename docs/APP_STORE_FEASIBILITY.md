# App Store feasibility experiment

The diagnostic sandbox probe established the public-API self-test approach. The normal toneboy app now uses that approach too; neither package is an App Store-ready release.

## What was built

`SandboxProbe` is a separate executable target sharing `AudioDSP` and `CaptureVerification` with `Tonebar`. Neither target contains a private permission adapter. The probe retains its separate audio-engine copy for diagnostic isolation.

The bundle is `app.toneboy.sandboxprobe`, with App Sandbox and the Audio Input entitlement enabled. It uses the documented Core Audio process tap APIs and `NSAudioCaptureUsageDescription`. No private TCC framework is loaded, and no permission database is read or changed.

```sh
bash build-sandbox-probe.sh
bash verify-sandbox-probe.sh
open '../toneboy Sandbox Probe.app' --args --start-capture
```

The build is ad-hoc signed by default. Set `TONEBOY_SIGN_IDENTITY` for a suitable local signing identity. This is not an App Store-signed or notarized release.

## Main-app integration

- Removed the private TCC permission adapter; CI now audits the main binary as well as the probe.
- Startup remains unmuted until verification succeeds. Manual stop cancels the verifier before destroying its DSP pointer; generation checks reject stale completions.
- Returning from Settings retries verification. Returning during a pending check permits one bounded retry if that check fails. This is not a permission-state query or an automatic relaunch service.
- Existing sleep/wake and output reconnection reverify the new route. Silence after successful verification does not disable EQ.
- Detection now uses windowed two-tone correlation against neighboring frequency bins, allowing unrelated louder audio without requiring the test signal to dominate total energy.
- 32 automated tests pass, including a louder synthetic audio mixture, stale completion, failed enable, bounded retry, and cancellation scenarios. Real music/device coverage remains outstanding.
- On this Mac, the rebuilt normal toneboy app automatically enabled EQ with existing access, and manual off/on successfully repeated verification. Existing identity and preferences remain unchanged. Main-app denial was not retested; denial was tested in the isolated sandbox probe as recorded below.
- The normal build remains non-sandboxed. Sandbox preference migration, signing, distribution, and review are separate remaining tasks.

## Current experiment: in-app verification sound

The probe now verifies capture automatically using a quiet, 0.7-second two-tone challenge generated in memory with AVAudioEngine. The two frequencies are randomized per attempt. No driver, helper installation, audio file, or ScreenCaptureKit permission is needed.

Initially the global tap includes the app itself, stays unmuted, and has its processed output disabled. The detector requires both challenge frequencies to dominate captured audio; arbitrary nonzero samples are not enough. If matched, playback of the test signal stops, the tap excludes the app's own process, and EQ routing starts automatically. Ordinary silence no longer disables processing.

If verification fails, the route is destroyed and the UI offers Settings and retry. Failure is **not** labeled as definitive permission denial: muted output, competing audio, or an unsupported route may also prevent the challenge being recognized. Verification does not persist a claimed permission grant across launches.

This remains a feasibility implementation. Runtime revocation while already processing, first-ever consent that takes a long time, silent/muted output, simultaneous music, Bluetooth route latency, and automatic restart after macOS terminates the app still require broader validation before release. The integrated flow is available for local testing.

Starting the tap triggers macOS's own consent request; no private permission preflight is used. Returning from Settings retries capture if the process survived. Route changes, sleep, and missing callbacks stop the experimental route. This is not a complete production reconnect policy.

## In-app self-test observations — 2026-11-08

- With audio access already granted, the app played its own challenge, detected it through the system tap, and automatically entered processing. No external player or music was needed.
- The user then revoked **only the probe's** system audio permission in Settings. After relaunch, the same self-test received zero captured input, failed verification, destroyed the route, and left EQ activation disabled.
- The own-process signal did not bypass the revoked system-audio permission in this tested global-tap configuration.
- 30 local tests passed: the original 26 plus four tests for challenge recognition across sample rates/volumes, rejection of silence/invalid samples, rejection of other frequencies, and signal duration/amplitude/fades.
- Static audit still passed: App Sandbox and Audio Input entitlements, separate bundle identity, and no private TCC markers in the probe binary.
- A first-ever denial from the consent dialog and consent-recovery in the new automatic flow are not yet tested. The earlier manual probe verified regrant after relaunch, as recorded below.

The tone is deliberately quiet but can be audible. This experiment does not claim a silent or interruption-free verification mechanism.

## Earlier manual-probe observations — 2026-11-08

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

1. Validate the in-app challenge flow across muted outputs, concurrent audio, delayed first consent, runtime permission revocation, and Bluetooth latency. A functional self-test verifies the route, not an official permission status.
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

## Related implementations researched

- [SoundDial setup](https://sounddial.eu/uses/setup-and-permission-mac-audio): documents an audio permission flow, real functionality checks, and a quiet test sound; its precise implementation is not public. The toneboy experiment is independently implemented.
- [CoreEQ permission adapter](https://github.com/AndreyPudov/core-eq/blob/main/CoreEQ/Audio/Capture/AudioCapturePermission.swift): uses private TCC entry points, so it is not a public-API permission example for this experiment.
- [eqMac architecture](https://github.com/bitgapp/eqMac#technology): describes an audio-driver path.
- [OBS ScreenCaptureKit audio capture](https://github.com/obsproject/obs-studio/blob/master/plugins/mac-capture/mac-sck-audio-capture.m): useful for recording, but capture alone does not replace the EQ routing/muting path.
