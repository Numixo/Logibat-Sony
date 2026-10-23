# Logibat Sony 1.1.0

Sony WH-1000XM5 battery and sound mode alongside your Logitech MX keyboard and mouse — in one small native macOS menu bar app.

![Logibat Sony interface illustration](https://raw.githubusercontent.com/Numixo/Logibat-Sony/main/docs/sony-preview.svg)

## New in this derivative

- Sony WH-1000XM5 battery percentage and NC / AMB / OFF status.
- Full sound-mode name and ambient level in the menu.
- Saved **Show in menu bar** checkboxes for keyboard, mouse, and headphones.
- Independent headphone battery and sound-mode visibility.
- An accessible LB settings item when every device is hidden.
- Existing Logitech MX battery monitoring over a Logi Bolt USB receiver.

Free and open source under the MIT license. Based on [Numixo/Logibat](https://github.com/Numixo/Logibat), with MIT-licensed Sony framing credited in THIRD_PARTY_NOTICES.

## Download and install

Download **Logibat-Sony-1.1.0-macOS-AppleSilicon.zip**, unzip it, and move **Logibat.app** into **Applications**. Quit the old Logibat before replacing it; the two builds use the same app identity and should not run at the same time.

**Requires macOS 13+ and an Apple silicon Mac (M-series). No Intel binary is provided.** Under 100 KB compressed; approximately 272 KB for the app bundle.

Locally signed, not notarized by Apple: macOS may show an unidentified developer warning. See [installation and permissions](https://github.com/Numixo/Logibat-Sony#download-and-install). Bluetooth access may be requested for Sony monitoring.

## Hardware checks

Verified on macOS 15.7.9 with a WH-1000XM5 on firmware 2.4.1: 33% battery, Ambient Sound, level 20. Logitech MX Keys S and MX Master 3S over Logi Bolt continued to return their battery readings. NC/Ambient/Off payload parsing, stream framing, and preference persistence are covered by automated checks.

Only WH-1000XM5 is targeted for Sony support. Other Sony models, Logitech Unifying, and direct Logitech Bluetooth connections have not been verified on hardware.

This release reads status only; it does not change headphone settings or record audio. The banner is an illustration, not a desktop screenshot.

Download SHA256SUMS.txt beside the ZIP and verify with:

```sh
shasum -a 256 -c SHA256SUMS.txt
```
