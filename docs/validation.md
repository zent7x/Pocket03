# Validation

Validated on 24 October 2026 with Xcode 26.2 and the iOS 26.2 iPhone 17 Pro simulator.

- Simulator build: passed.
- Unsigned arm64 iPhone Release build: passed. This does not establish code signing or installation on a physical phone.
- Eight unit/integration tests: passed. All treatment dimensions; zero-strength source colors; bounded grain on flat midtones; EXIF orientation; photo persistence; corrupt-index preservation; transaction rollback with source movie preservation; playable portrait H.264 output without audio.
- One end-to-end UI test: passed. Photo capture, gallery, silent movie recording, relaunch, durable gallery count. Screenshot attachments are retained in the local Xcode result bundle.
- Visual inspection: simulator camera and generated demo scene, original app icon and layout. Demo mode is explicitly labeled.
- Final `git diff --check`: passed.

One nonblocking Xcode metadata message concerns unused App Intents extraction. An interface-orientation warning applies to compatibility on larger devices; Pocket03 targets iPhone portrait and does not claim an iPad layout.

Hardware-only checks remain: real camera exposure/rotation/mirroring, torch, camera switching and zoom, frame rate and thermal performance. Photos permission prompts and native external sharing require manual confirmation. The picker selection gesture was not automated; imported-image orientation and filter processing are tested at their image-processing boundary.
