# toneboy

> Audio startup uses a public-API functional self-test. See [App Store feasibility results and remaining validation](docs/APP_STORE_FEASIBILITY.md).

A native macOS menu bar equalizer for your whole Mac. Shape the sound of music, videos, games, and notifications with a four-band EQ, a live spectrum, and audio-reactive gradients.

**Early development.** The current build is for direct distribution, not the Mac App Store. Release signing and notarization are not configured yet.

## Features

- Four parametric bands: low shelf, two bells, and high shelf; 20 Hz–20 kHz, ±18 dB.
- Drag points to adjust frequency and gain; scroll over the graph to adjust width or shelf slope.
- Flat, Warm, Bass, Vocal, and Soft presets, with settings saved between launches.
- Live input spectrum, animated menu bar waveform, and Ocean, Iris, Rose, and Forest palettes.
- Automatic headroom compensation and a simple output peak limiter.
- Automatic startup when audio permission is available, permission recovery, output reconnection, and sleep/wake handling.
- Local audio processing. No audio files, analytics, accounts, or network requests.

## Requirements

- macOS 14.2 or later.
- Xcode 15.3 or later with the macOS SDK and Swift 5.10 or later.
- Stereo output with a supported 32-bit float capture format.

Local development has been tested on Apple Silicon. Other devices and macOS releases still need hardware testing.

## Build and run

```sh
git clone https://github.com/RostyslavFesyk/toneboy.git
cd toneboy
bash build.sh
open ../toneboy.app
```

The build script produces an ad-hoc signed `toneboy.app` beside the repository. It does not produce a notarized public release. Override the build cache location with `TONEBAR_BUILD_DIR` if needed.

You can also open `Package.swift` in Xcode to edit and debug the Swift package. Use the packaged `.app` for permission and end-user testing; it includes the audio usage description in `Info.plist`.

On first launch, allow system audio access. If access is denied, use **Open System Settings** and enable toneboy in the audio recording privacy settings. On returning, the app retries a short, quiet audio self-test and starts EQ only after observing sustained incoming audio or recognizing its test signal. The pilot is used when the route is quiet, with one bounded retry for output startup. A failed check can also indicate an output problem; it is not a definitive permission status. The top-right switch stops processing and restores normal playback.

The legacy bundle identifier `app.tonebar.local` and internal Swift target name `Tonebar` are retained to preserve development settings. The app is called **toneboy**.

## Tests

```sh
bash test-stability.sh
```

The suite currently includes 42 tests:

- 9 DSP tests: flat transparency, stereo independence, bell/shelf response, headroom, bypass, limiter, analyzer queue behavior, and unmuted verification output gating.
- 18 lifecycle tests: verification success/failure, stale callbacks, cancellation, retries, output changes, sleep/wake, and 250 on/off cycles.
- 4 login-item tests: registration, approval, external state changes, and error handling.
- 2 single-instance tests: duplicate exclusion and lock release without deleting the lock file.
- 4 capture-activity tests: sustained audio, denied zeros, DC, isolated spikes, short transients, and invalid data.
- 5 signal tests: sample rates, low amplitude, silence, unrelated audio, louder synthetic background audio, and fades.

Lifecycle tests exercise the production model with a simulated engine and capture verifier. They use isolated preferences and do not request permission, capture audio, change outputs, or put the Mac to sleep. Real Bluetooth reconnection, tap cleanup, dropouts, latency, CPU, and memory still need hardware testing.

GitHub Actions runs the tests and a release build on pushes and pull requests.

## Architecture

| Component | Location |
| --- | --- |
| Core Audio tap, aggregate device, and cleanup | `Sources/Tonebar/AudioEngine.swift` |
| Real-time C DSP, biquad EQ, limiter, and analysis queue | `Sources/AudioDSP/` |
| FFT spectrum analysis | `Sources/Tonebar/Spectrum.swift` |
| UI and interaction | `Sources/Tonebar/EQView.swift` |
| Audio lifecycle and persistent settings | `Sources/Tonebar/EQModel.swift` |
| Audio capture verification | `Sources/Tonebar/CaptureVerifier.swift`, `Sources/CaptureVerification` |

The audio route uses a private temporary Core Audio tap and aggregate device. It does not change the default output device. Audio stays in memory.

## Distribution and limitations

Startup creates an unmuted capture route with rendering disabled, then plays a quiet randomized two-tone challenge. The app enables muting and EQ output only after recognizing the challenge through that route. Failure tears down capture and leaves normal system playback intact. The app uses no private TCC entry points. Manual bypass cancels any pending verification.

**This build is not yet an App Store release.** The normal app retains its existing non-sandbox packaging and preferences. The separate sandbox probe validates public-API feasibility; sandbox migration, signing, hardware coverage, and review remain outstanding. See [Apple’s review requirements](https://developer.apple.com/app-store/review/guidelines/#software-requirements).

Other current limitations:

- Stereo only; multichannel and unsupported formats are rejected.
- Output changes are polled once per second and may cause a brief interruption.
- Capture-protected audio may not be processed.
- The limiter is not a mastering or true-peak limiter.
- No auto-updater, dynamic EQ, mid/side, or linear phase mode yet.

## Roadmap

- Test extended playback, sleep/wake, and speaker/AirPods/USB switching on real devices.
- Validate Launch at Login on a signed build through a real logout/login.
- Configure Developer ID signing, notarization, and a DMG release.
- Add automatic updates.
- Validate the public-API self-test across output devices and finish App Store packaging.

## Beta packaging

The menu includes **Launch at Login**, using macOS Service Management. If approval is required, it offers the system settings page. A second instance exits before creating an audio route.

See [signed beta setup](docs/BETA_RELEASE.md) for Developer ID signing and notarization. A Developer account alone does not install a signing certificate on this Mac.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Small, focused changes with reproducible validation are welcome.

## References

- [Apple Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
- [W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/) for filter coefficient formulas.
- [AudioCap](https://github.com/insidegui/AudioCap) provided reference documentation for the earlier permission adapter, which has now been removed. AudioCap is not bundled.

## License

Copyright (C) 2026 Rostyslav Fesyk.

Licensed under the **GNU General Public License, version 3 only** (`GPL-3.0-only`). See [LICENSE](LICENSE). This software comes without warranty.

A potential separately licensed App Store edition is not included in this license grant. Any such edition must have appropriate rights for all included code, including third-party contributions.
