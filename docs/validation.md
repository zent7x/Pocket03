# Validation

Validated on 24 October 2026 with Xcode 26.2 (17C52) and the iOS 26.2 iPhone 17 Pro simulator
(`7D3605DE-6E35-4F96-8248-172DF9D19F06`).

- Simulator Debug build: passed.
- Unsigned arm64 iPhone Release build: passed. The built bundle was checked for architecture
  (`arm64`), `UIAppFonts` registration, the bundled `VT323-Regular.ttf` and portrait-only
  `UISupportedInterfaceOrientations`. This does not establish code signing or installation on a
  physical phone.
- Eleven unit and integration tests: passed. All treatment dimensions; zero-strength source
  colors; bounded grain on flat midtones; EXIF orientation; photo persistence; corrupt-index
  preservation; transaction rollback with source movie preservation; playable portrait H.264
  output without audio; imported video preserving every frame under all three looks at 480×640
  with no audio track; import cancellation surfacing `CancellationError`, reporting progress
  inside 0...1 and leaving no temporary movie behind.
- Two end-to-end UI tests: passed. Photo capture, gallery, silent movie recording, relaunch,
  durable gallery count; all three look names, the Photo/Video/Import tabs and the options menu.

## Imported-video frame count: flake and fix

The imported-video test previously asserted an exact source frame count against a fixture built
with `SilentVideoWriter`. That class is the production *live capture* writer: it sets
`expectsMediaDataInRealTime = true` and deliberately returns without appending whenever the
encoder reports `isReadyForMoreMediaData == false`, and the test paced it with wall-clock
`Task.sleep`. The number of frames such a fixture actually writes therefore depends on machine
load, and one full-suite run decoded 12 frames where 8 were appended, alongside VideoToolbox
`err=-12900` messages from the simulator's software encoder.

The production writer was left unchanged, because dropping frames the live encoder cannot accept
is the correct policy for camera capture. The fixture moved into the test target instead, as
`FixtureMovie`: it is offline (`expectsMediaDataInRealTime = false`), pull driven through
`requestMediaDataWhenReady`, and never drops, so the source frame count is exact and needs no
sleeps. The test now asserts the relationship that actually matters — the importer preserves
exactly the frame count the source has.

Verification: the test passed 25 consecutive iterations with `-run-tests-until-failure` while
eight CPU-saturating background processes ran, and the full suite passes. The original 12-vs-8
event itself was **not** reproducible on demand: neither CPU saturation nor six full-suite
iterations with the old fixture restored in its original position reproduced it. The fix is
therefore justified by removing the nondeterminism structurally, not by a reproduced failure.

## Visual inspection

Captured from the running simulator at rest, with animations allowed to settle before each
screenshot: photo tab, video tab, import tab, options menu, processing/look selector, settings,
gallery, active recording, and post-recording confirmation. Confirmed the pale blue status bar,
VT323 pixel typography, Series 40 soft keys reading Gallery/Capture/Options and Camera/Select/Back
at rest, all three look names with subtitles and a selection check, the `DEMO` label on the
generated scene, the recording state (REC marker, running timer, disabled mode and look controls,
`480×640 · silent video`, `Stop` soft key), and the persistent gallery grid.

The Import tab shows a black viewfinder by design; it carries an explicit "Import a photo or
video" empty state and an **Open gallery** button, and is not an accidental blank preview. No
unintended blank or black viewfinder states were observed.

Screenshots taken by UI automation in the same frame as a soft-key tap can catch SwiftUI mid
transition and show the old and new key labels overlapping (for example `Options` over `Back`).
This is transient; every at-rest capture renders the labels cleanly, so no production rendering
change was made for it.

`preview-phone.png` is the current interface and the image used in the README. `preview.png` is
retained from the earlier dark camera-shell layout that the Series 40 redesign replaced; it no
longer reflects the shipping interface.

## Remaining limits

One nonblocking Xcode metadata message concerns unused App Intents extraction. An
interface-orientation warning applies to compatibility on larger devices; Pocket03 targets iPhone
portrait and does not claim an iPad layout. Neither affects behavior and there are no source
compiler warnings.

Hardware-only checks remain: real camera exposure, rotation and mirroring, torch, camera switching
and zoom, frame rate and thermal performance. Photos permission prompts and native external
sharing require manual confirmation on a device. The picker selection gesture was not automated;
imported-image orientation and filter processing are tested at their image-processing boundary.
Silence is verified by asserting the output asset carries no audio track, on the simulator's
generated scene rather than live microphone input.

## Handset pictures (24 October 2026)

The look selector and the Processing menu now carry a handset picture per look. The Nokia 2630
uses a real photograph released under CC0, re-cut for the app; Dreamy and the Siemens CX70 use
original handset drawings rendered at runtime, because no freely licensed CX70 photograph exists
and Dreamy is not a real phone. Attribution and the trademark position are in
[credits.md](credits.md).

Matting the photograph needed measurement rather than threshold guessing: on that source the gold
soft keys are colorimetrically identical to the brightly lit wall behind the phone (yellowness 155
against 149), and the shadow band hugging the handset matches the silver bezel. Keying on hue
alone therefore either ate the keypad or kept the halo. The working approach keys only the bright
lit wall, takes the largest connected component, and erodes the remaining shadow band. The source
also carries EXIF orientation 6 and must be transposed before any cropping.

Verified after the change: full suite green (11 unit/integration, 2 UI), and the selector and
Processing list were inspected at rest in the simulator.

## Interface: reverted, then recoloured (24 October 2026)

The amber dot-matrix rebuild was reverted at the user's request -- the Series 40 interface was
preferred -- and the pale blue design was then given a colour and text pass rather than replaced:

- Palette: deeper ink, lighter paper for contrast, a richer highlight blue, and a new warm accent
  plus a shared green, so the interface is no longer a single blue.
- The accent carries readouts and state: the gallery count, the look index, menu row numbers, the
  effect percentage, the gallery type marker, the viewer's look name, and the DEMO and REC tags.
- Text: the look index now reads "LOOK 1 / 3"; subtitles and dates drop back to the highlight blue
  so titles lead; look subtitles are held to one line so the rows keep an even height.
- The first Options row no longer gets an arbitrary lighter plate; rows are uniform with a
  hairline separator, and the mode bar gained a hairline so it reads as a band.

The gallery count label is still digits only, because the UI test parses it as an integer. Look
names, soft-key titles, menu row titles and the saved-memory toasts are unchanged for the same
reason. Verified: full suite green (11 unit/integration, 2 UI), unsigned arm64 Release device
build succeeds, and the camera, options, processing, settings and gallery screens were inspected
at rest. `preview-phone.png` regenerated.

## Hardening for personal device use (24 October 2026)

Three gaps mattered for daily use on a real phone rather than in the simulator:

- **The gallery was write-only.** There was no way to remove a memory, so storage only grew. The
  viewer now has a Delete action behind a confirmation. `MediaLibrary.delete` commits the index
  first and removes files afterwards, so a failed file removal can never leave the gallery
  pointing at a file that is already gone.
- **Thumbnails were decoded per cell per redraw.** The grid called `UIImage(contentsOfFile:)` on
  every SwiftUI body evaluation. Decoded thumbnails are now held in an `NSCache` bounded to 150
  entries, and the cache is invalidated on delete.
- **The camera never recovered from an interruption.** A phone call, another app taking the
  camera, or a media-services reset left the preview black until the app was backgrounded and
  reopened. `CameraEngine` now observes `wasInterrupted`, `interruptionEnded` and `runtimeError`,
  stops any recording cleanly, explains the cause in the viewfinder, and restarts the session when
  the interruption ends. A media-services reset recovers silently; other runtime errors surface.

### iOS support

The deployment target is iOS 17.0, so the app cannot run on iOS 16 or earlier. Because the project
builds cleanly at that target, the compiler guarantees no API newer than iOS 17.0 is used without a
guard. Runtime behaviour has been exercised only on the iOS 26.2 simulator; it is not verified on
every intermediate release.

### Install status

The target phone is an iPhone 16 Pro on iOS 18.3.1, paired, with Developer Mode enabled. A valid
`Apple Development` certificate is in the keychain, but Xcode has no Apple ID signed in, so no
provisioning profile can be created and the signed build fails with `No Account for Team`. Signing
in once under **Xcode → Settings → Accounts** is the only remaining step; after that the app builds,
signs and installs from the command line. Device behaviour -- real camera exposure, rotation,
mirroring, torch, zoom, thermals, Photos permission prompts and the share sheet -- stays unverified
until it runs there.
