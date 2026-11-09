# Mac App Store release

Use the `toneboy-store` scheme in `Toneboy.xcodeproj`. It builds the full app with App Sandbox, the approved AppIcon, and the app privacy manifest. The Swift package and Developer ID packaging scripts still support direct distribution.

The store target uses `com.rostyslavfesyk.toneboy`. Register that explicit ID under the publishing team and use the same ID in App Store Connect. Select the team under Signing & Capabilities and archive for **Any Mac**. Use **TestFlight & App Store** in Organizer to upload the build. Keep release set to manual for the first submission.

## Listing draft

| Field | Value |
| --- | --- |
| Name | toneboy |
| Subtitle | System Audio Equalizer |
| Primary category | Music |
| Version | 0.1.1 |
| Keywords | equalizer,eq,sound,audio,bass,treble,spectrum,menu bar,presets |
| Privacy policy | https://github.com/RostyslavFesyk/toneboy/blob/main/docs/PRIVACY.md |
| Support | https://github.com/RostyslavFesyk/toneboy/blob/main/docs/SUPPORT.md |
| App Privacy | Data Not Collected |

### Description

Shape your Mac’s sound from the menu bar. toneboy gives you a four-band equalizer, a live spectrum, and quick presets for music, videos, and other system audio.

- Drag four EQ bands to shape lows, mids, and highs.
- Watch the live spectrum while you listen.
- Switch between Flat, Warm, Bass, Vocal, and Soft presets.
- Pick a color theme and save your settings for the next launch.
- Turn the EQ off from the panel to restore normal playback.

toneboy requires macOS 14.2 or later, a supported stereo output, and permission to capture system audio. Processing stays on your Mac. Audio is not saved or transmitted.

### Notes for App Review

1. Launch toneboy and open its icon in the macOS menu bar.
2. Allow system audio recording when macOS requests it. If access was denied, choose **Audio Access Settings…** from the toneboy menu, enable access in System Settings, and return to toneboy. Choose **Try Again** if needed.
3. Play audio through the built-in speakers or stereo headphones. Enable the EQ and switch between Flat and Bass or drag one of the four bands. The spectrum should respond to playback. Switch the EQ off to bypass it.

No account or sign-in is needed to use the app. toneboy uses a documented Core Audio process tap. It processes audio in memory and may play a short quiet test signal when the output is idle.

## Before submitting

- Install the signed store build through TestFlight. Test the first permission grant, denial, recovery, and bypass on a fresh install, then test built-in speakers and Bluetooth output switching.
- Export three actual-app screenshots at 2560 × 1600 px as PNG. The approved icon is packaged with the target.
- Complete the age rating and review contact fields in App Store Connect. Verify distribution rights for the store binary and its assets before public release.
