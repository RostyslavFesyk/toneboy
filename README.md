# toneboy

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

On first launch, allow system audio access. If access is denied, use **Open System Settings** and enable toneboy in the audio recording privacy settings. The app rechecks permission and retries startup automatically. The top-right switch stops processing and restores normal playback.

The legacy bundle identifier `app.tonebar.local` and internal Swift target name `Tonebar` are retained to preserve development settings. The app is called **toneboy**.

## Tests

```sh
bash test-stability.sh
```

The suite currently includes 24 tests:

- 7 DSP tests: flat transparency, stereo independence, bell/shelf response, headroom, bypass, limiter, and analyzer queue behavior.
- 17 lifecycle tests: consent, denial, regrant, revocation, cancellation, retries, output changes, sleep/wake, and 250 on/off cycles.

Lifecycle tests exercise the production model with a simulated engine and permission provider. They use isolated preferences and do not request permission, capture audio, change outputs, or put the Mac to sleep. Real Bluetooth reconnection, tap cleanup, dropouts, latency, CPU, and memory still need hardware testing.

GitHub Actions runs the tests and a release build on pushes and pull requests.

## Architecture

| Component | Location |
| --- | --- |
| Core Audio tap, aggregate device, and cleanup | `Sources/Tonebar/AudioEngine.swift` |
| Real-time C DSP, biquad EQ, limiter, and analysis queue | `Sources/AudioDSP/` |
| FFT spectrum analysis | `Sources/Tonebar/Spectrum.swift` |
| UI and interaction | `Sources/Tonebar/EQView.swift` |
| Audio lifecycle and persistent settings | `Sources/Tonebar/EQModel.swift` |
| System audio permission adapter | `Sources/Tonebar/SystemAudioPermission.swift` |

The audio route uses a private temporary Core Audio tap and aggregate device. It does not change the default output device. Audio stays in memory.

## Distribution and limitations

The permission adapter uses private TCC functions (`TCCAccessPreflight` and `TCCAccessRequest`). It checks permission before creating a muting tap, fails closed on unknown results, and does not read or modify the TCC database. Private API availability may change between macOS versions.

**This build is not eligible for Mac App Store submission.** An App Store edition needs a public-API permission flow, working App Sandbox support, and separate distribution validation. See [Apple’s review requirements](https://developer.apple.com/app-store/review/guidelines/#software-requirements).

Other current limitations:

- Stereo only; multichannel and unsupported formats are rejected.
- Output changes are polled once per second and may cause a brief interruption.
- Capture-protected audio may not be processed.
- The limiter is not a mastering or true-peak limiter.
- No launch-at-login setting, auto-updater, dynamic EQ, mid/side, or linear phase mode yet.

## Roadmap

- Test extended playback, sleep/wake, and speaker/AirPods/USB switching on real devices.
- Add launch at login.
- Configure Developer ID signing, notarization, and a DMG release.
- Add automatic updates.
- Investigate an App Store-compatible audio and permission implementation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Small, focused changes with reproducible validation are welcome.

## References

- [Apple Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
- [W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/) for filter coefficient formulas.
- [AudioCap](https://github.com/insidegui/AudioCap) for reference documentation of the TCC permission ABI. The adapter is implemented here; AudioCap is not bundled.

## License

Copyright (C) 2026 Rostyslav Fesyk.

Licensed under the **GNU General Public License, version 3 only** (`GPL-3.0-only`). See [LICENSE](LICENSE). This software comes without warranty.

A potential separately licensed App Store edition is not included in this license grant. Any such edition must have appropriate rights for all included code, including third-party contributions.
