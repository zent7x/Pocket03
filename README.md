# Pocket03

A native iPhone camera for small, imperfect memories — 480 × 640 photos and silent video, through
looks that emulate what early phone cameras actually did to an image.

SwiftUI + AVFoundation + Core Image. iOS 17+. No third-party dependencies, accounts, analytics or
network calls of any kind.

![Pocket03 camera](preview-phone.png)

## Looks

Three cameras, each a different kind of degradation rather than a different colour tint:

| Look | Character |
| --- | --- |
| **Dreamy (original)** | Soft and warm, highlights blown out, low contrast |
| **Nokia 2630 (2007)** | Crushed blacks, cool cast, heaviest grain, high contrast |
| **Siemens CX70 (2004)** | Softest and most posterised, loud saturated colour |

Each look throws real information away: it downsamples 1.5–2.7×, scales back up so detail cannot
return, clips both ends of the tone curve the way a sensor with no dynamic range would, posterises
down to as few as 8 levels, and lays grain over the result with an overlay blend so the shadows
stay black instead of fogging.

These are original approximations. They are not the original app's formulas, which were never
recovered — see the boundary note below.

## Features

- Series 40 style interface: pixel type, pale blue status and menu bars, a warm accent for counts
  and state, and **Gallery / Capture / Options** soft keys.
- **Photo / Video / Import** workflow tabs. Every look applies to live capture, recordings,
  imported photos and imported clips alike.
- Portrait 480 × 640 output with adjustable effect strength. The selected look and strength persist.
- Front/back camera, torch and 1–4× zoom in Options → Settings, hardware permitting.
- Photo imports preview before saving and can switch looks and strength. Video import processes
  frame by frame with progress and cancellation, and writes a new silent clip without touching the
  original.
- Filtered **silent** H.264 movies for both recording and import. Audio is intentionally absent and
  labelled in the interface.
- A persistent phone-style gallery with delete, native sharing and explicit save to Photos.
- A labelled generated landscape on the simulator, so the whole flow is usable without a camera.

## Run

Open `Pocket03.xcodeproj`, pick an iPhone simulator and Run. The project file is checked in;
XcodeGen is only needed after editing `project.yml`.

```sh
xcodegen generate   # only after changing project.yml

xcodebuild -project Pocket03.xcodeproj -scheme Pocket03 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Pocket03.xcodeproj -scheme Pocket03 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

### On a real iPhone

```sh
tools/install-device.sh          # Debug; pass Release for an optimised build
```

The script finds the connected physical device, builds with automatic provisioning and installs
over `devicectl`. One-time setup: sign in to your Apple ID under **Xcode → Settings → Accounts**,
and enable Developer Mode on the phone.

Set `DEVELOPMENT_TEAM` in `project.yml` to your own team ID — it is the **OU** field of your
signing certificate, not the identifier inside the certificate's name:

```sh
security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -subject
```

Change `studio.pocket03.camera` too if that bundle ID is taken. A free Apple ID works, but the
signature expires after seven days and the app must be reinstalled; a paid account lasts a year.
No distribution signing is configured.

## Validation

Twelve unit and integration tests and two end-to-end UI tests pass on the simulator, covering every
treatment dimension, zero-strength colour preservation, bounded grain, EXIF rotation, photo
persistence, delete, corrupt-index protection, storage-failure rollback, portrait silent video,
imported-video frame preservation across all three looks, and import cancellation with temporary
file cleanup.

Pocket03 runs on a physical iPhone 16 Pro (iOS 18.3.1). Camera exposure, rotation, mirroring,
torch, zoom and thermal behaviour are exercised there rather than in automation. See
[docs/validation.md](docs/validation.md) for what is measured versus what is merely observed.

## Reverse engineering boundary

Pocket03 was written after a static analysis of the Android app that inspired it, recorded in
[docs/original-analysis.md](docs/original-analysis.md) and
[docs/reconstruction.md](docs/reconstruction.md). That analysis did **not** recover the original
filter: its image pipeline sits behind a native VM and its formulas remain unknown.

Nothing from the original is bundled here — no source, no assets, no model, no libraries, no
shaders. The looks, coefficients, interface and artwork are all new, and no claim of pixel-accurate
reproduction is made.

## Credits

See [docs/credits.md](docs/credits.md). VT323 © 2011 The VT323 Project Authors (Peter Hull) under
the SIL Open Font License 1.1, bundled with its licence in `Pocket03/Fonts/`. The Nokia 2630
handset picture is derived from a CC0 photograph from Wikimedia Commons.

"Nokia" and "Siemens" are trademarks of their respective owners. Pocket03 is not affiliated with,
sponsored by or endorsed by them; the model names describe which era of handset camera each look
reaches for.
