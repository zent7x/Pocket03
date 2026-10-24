# Pocket03 iPhone camera

Build an independently branded native iPhone camera inspired by the analyzed 0.3MP Android artifact. Use SwiftUI, AVFoundation and Core Image, with no third party packages. iOS 17+.

Provide filtered live camera preview, front/back camera, torch, digital zoom, photo capture, imported photos, selectable retro treatments, adjustable effect strength, local persistent gallery, sharing and explicit export to Photos. Include filtered silent video capture with an obvious silent label. On the simulator, supply a clearly marked demo scene so the interface and capture/gallery flow can be exercised without a physical camera. Handle permissions, denied access and capture errors visibly.

Use original branding and interface artwork with a dark physical-camera shell and pale green LCD display. Portrait capture outputs 480x640. Preserve the reverse engineering report and separate evidence-backed facts from new filter design. Do not claim exact proprietary filter reproduction: native VM formulas are unresolved.

Validate with an iOS simulator build, simulator launch and visual inspection. Verify image dimensions, persistent capture, import processing and filtered video where feasible; state hardware-only checks. No App Store publication or signing identity configuration.

## Follow-up: button-phone interface and three looks

User clarified “both”: support Photo, Video and Import workflows, plus the three recognizable looks Dreamy (original), Nokia 2630 (2007), and Siemens CX70 (2004). Use independently implemented approximations, clearly documented. Preserve decoding of existing saved film identifiers.

Replace the camera-like shell with a Series 40 style screen: pale blue status bar, pixel typography, large viewfinder, Gallery / Capture-or-Record / Options soft keys, and phone-style list menus. Provide visible Photo / Video / Import switching and a three-look selector; preserve settings, front/back, torch and zoom. Import should accept photos and videos. Video recording and processed imported videos remain explicitly silent. Persist the selected look and strength; never switch workflow/look while recording or processing.

Validate all three looks for photo output and imported video processing, preserve old gallery entries, exercise the mode/look/menu UI and recording flow, build for simulator and unsigned physical iPhone, and update the source bundle and preview.

## Status — 24 October 2026

Feature work is complete and verified on the simulator and as an unsigned device build.

The last open defect was the imported-video frame-count test. It was flaky, not wrong about the
product: the fixture reused the production live-capture writer (`SilentVideoWriter`), which is
real-time and drops frames the encoder is not ready for, paced by wall-clock sleeps. Production
behavior was left alone; the test now builds its source with an offline, pull-driven
`FixtureMovie` and asserts that the importer preserves exactly the source frame count. Verified
over 25 iterations under CPU saturation. Added coverage for import cancellation, progress bounds
and temporary-file cleanup.

Verified: Photo/Video/Import tabs, all three looks, options and processing menus, settings,
gallery persistence across relaunch, phone-style soft keys, VT323 pixel typography, recording
start/stop with silent output, 480×640 portrait output, no accidental blank viewfinder states.

Still hardware-only: real camera exposure, rotation, mirroring, torch, switching, zoom, frame rate
and thermals; Photos permission prompts; native share sheet; picker selection gesture.

Unchanged boundary: the original app's native VM filter formulas remain unrecovered. All looks,
coefficients and artwork here are original; no pixel-perfect reproduction is claimed.
