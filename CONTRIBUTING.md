# Contributing to toneboy

Please open an issue describing a bug or proposed change before starting a large rewrite. Include macOS version, output device, reproduction steps, and expected behavior. Do not attach private recordings, credentials, or unredacted system logs.

## Development

Open `Package.swift` in Xcode, or use the scripts:

```sh
bash test-stability.sh
bash build.sh
```

Keep changes focused. Describe the user-visible behavior, how you verified it, and any hardware-dependent checks you could not run. Audio callback changes must avoid allocation, blocking, and UI work. Lifecycle changes should include regression tests using the injected engine and permission provider.

## Licensing

Contributions are submitted under GPL-3.0-only. Only submit code you have the right to contribute, and preserve third-party license notices.

A separately licensed App Store edition is being considered. Submitting a pull request does **not** transfer your copyright or automatically grant a right to relicense your contribution. Before including external contributions in any differently licensed edition, the maintainer must obtain explicit permission from the relevant copyright holders or exclude those contributions. No contributor license agreement is currently in place.

## Hardware validation

Automated tests simulate device and permission transitions. For changes to the audio route, also report which real checks were completed: consent denial/regrant, speaker/headphone switching, sleep/wake, and extended playback. Do not describe simulated tests as proof that physical devices work.
