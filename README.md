# VitalSnap

VitalSnap is an iPhone app that photographs a home health display, reads the digits on the device, and writes the reading you confirm into Apple Health.

It supports two kinds of screens:

- A digital scale, saved as body mass
- A blood pressure cuff, saved as a blood pressure correlation, with pulse as heart rate when a pulse is visible

Recognition uses Apple's Vision framework (`VNRecognizeTextRequest`). Nothing is uploaded. There is no account, backend, or Bluetooth pairing.

## Requirements

- Mac with Xcode 15.4 or later (Xcode 16 or later recommended)
- iOS 17 or later
- A physical iPhone for the full path. The simulator has no camera and HealthKit is unavailable there
- An Apple Developer Program membership to run HealthKit on a device. A free Personal Team can compile many apps, but it cannot sign the HealthKit entitlement

## Open and run

1. Open `VitalSnap.xcodeproj` in Xcode.
2. Select the VitalSnap target, then Signing & Capabilities.
3. Choose your Team.
4. Confirm the HealthKit capability is present. The entitlement is already in `VitalSnap/VitalSnap.entitlements`. If Xcode does not show HealthKit, click + Capability and add HealthKit. Leave clinical-record access off.
5. Connect an iPhone running iOS 17 or later, select it as the run destination, and press Run.
6. On first launch, read the short introduction. Camera access is requested when you take a photo. Apple Health is requested when you save.
7. Photograph a scale or cuff, or tap Sample to walk through a known reading. Check the numbers, edit anything that is wrong, then save.
8. In the Health app, look under Browse, Body Measurements, Weight, or under Heart, Blood Pressure. VitalSnap is the source. Samples are marked as entered by you, because you confirmed them.

The first install on a device may ask you to trust the developer certificate in Settings, General, VPN & Device Management.

## Change the bundle identifier

The project ships as `com.webnettricks.vitalsnap`.

1. Select the VitalSnap target.
2. Open Signing & Capabilities, or the Build Settings tab.
3. Change **Product Bundle Identifier**.
4. Let Xcode register the new App ID. The App ID must include the HealthKit capability, which automatic signing does for a paid team.

The display name is VitalSnap. Change `CFBundleDisplayName` in `VitalSnap/Resources/Info.plist` if you want a different name on the Home Screen.

## Project layout

```
VitalSnap.xcodeproj          Xcode project and shared scheme
VitalSnap/
  App/                       SwiftUI entry and app model
  Camera/                    AVFoundation session and preview
  OCR/                       On-device Vision text recognition
  Health/                    HealthKit authorization and writes
  Storage/                   Local list of confirmed readings
  UI/                        Onboarding, home, capture, review
  Resources/                 Info.plist, privacy manifest, asset catalog
  VitalSnap.entitlements     HealthKit entitlement
Packages/VitalSnapCore/      Parsers and validation, with unit tests
```

`VitalSnapCore` is a local Swift package linked by the app. It has no UIKit, Vision, or HealthKit imports, so the parsers can be tested on their own:

```bash
cd Packages/VitalSnapCore
swift test
```

## What the parsers accept

They are heuristics, not a catalog of every monitor.

Weight:

- A number next to `kg`, `lb` / `lbs`, or a stone reading such as `11 st 4 lb` (stored as pounds)
- A large number on one line and the unit on the next
- European decimals such as `83,4 kg`
- A few OCR mix-ups, such as `k9` for `kg` or a letter O inside a number

Blood pressure:

- `128/82`, `118 over 76`, or a slash the camera read as `I` or `|`
- Digits stuck together when the slash is missing, such as `12882` or `1288274`
- `SYS` / `DIA` / `PULSE` labels, including a header row (`SYS` `DIA` `PUL` above `128` `82` `74`), digits on the next line, or side-by-side columns
- Seven-segment mix-ups such as `O`/`0`, `B`/`8`, `S`/`5`, `G`/`6`, and `I`/`1` inside a number, plus label mix-ups such as `5Y5` or `D1A`
- A stack of large digits when labels are missing. Smaller debris is ignored when the big digits are visibly taller

Lines that look like a clock, BMI, body fat, or a percentage are ignored. If the unit is missing, a weight of 120 or more is treated as pounds and a lighter number as kilograms, and the confirm screen asks you to check the unit. Switching pounds and kilograms converts the value.

If the photo does not match the type you picked, the review screen says so and the segmented control can read it the other way.

## Permissions

| Key | Why |
| --- | --- |
| `NSCameraUsageDescription` | Photograph the device screen |
| `NSHealthShareUsageDescription` | Required by HealthKit, even though VitalSnap does not read other records |
| `NSHealthUpdateUsageDescription` | Write the confirmed reading |

Choosing an existing photo uses the system photo picker and does not request photo-library access. There are no API keys or other secrets in this project.

## Known limitations

- Glare and odd fonts still defeat Vision sometimes. If the first read does not parse, VitalSnap retries a higher-contrast image, a sharpened image, and an inverted image. The confirm screen is still the check. You can type the numbers with no photo.
- Parsers will not understand every brand. Extend `WeightParser` and `BloodPressureParser` in `Packages/VitalSnapCore` when you have a transcript that fails. `swift test` covers the layouts already handled.
- The local list is only a reminder of what you confirmed. Deleting a row does not delete the Apple Health sample.
- Saving again writes a new Health sample. It does not edit the previous one.
- Pulse is stored as a separate heart-rate sample, not inside the blood pressure correlation. That is how HealthKit models it.
- HealthKit and the camera need a real iPhone. On the simulator, use Sample, a photo, or manual entry. Those readings stay in the in-app list.
- This is not a medical device. VitalSnap does not diagnose or interpret a reading.
- Not in this version: App Store submission, accounts, cloud sync, Bluetooth pairing, Android.

## Privacy

Photos and OCR stay on the phone. Confirmed values are written to Apple Health and to a JSON file in the app's local storage. The privacy manifest reports health data used for app functionality, with no tracking.
