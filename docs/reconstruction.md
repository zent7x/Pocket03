# Evidence and reconstruction decisions

The investigation artifacts remain at `../03mp-reverse/`. A copy is preserved in [original-analysis.md](original-analysis.md), which documents package hashes, source locations and unresolved questions.

REA artifact Evidence: `ev_7217919a1c35af941ae5dca0e0d7f8ec93becd7eb692b62cabc8059339cacd81`. This is inventory evidence. Android decompilation and string decoding were performed separately with the existing standalone JADX and isolated Java decoder. REA's Android provider requires a missing `jadx-headless-mcp 0.7.1` JAR; its native engines are also unconfigured. This project does not claim a complete reversal.

| Artifact observation | Pocket03 decision |
| --- | --- |
| Renderer `ya.f` constructs `Size(480,640)` and `Size(1440,1920)`. | Fixed 480×640 portrait images and movies. No claim that all original output uses this size. |
| Shader/pass constructor labels include viewport, source/destination sizes and rescale state. | Core Image aspect-fill crop to an explicit output rectangle. |
| Decoded strings name halation high source, blur and merge textures, cutoffs and hue/intensity controls. | Original bloom treatment using CIBloom. This does not reproduce those native pass formulas. |
| Product description refers to old sensor artifacts; native formulas remain unknown. | Newly designed color posterization, grayscale grain, row noise, soft blur and vignette. No claim of exact Bayer reconstruction. |
| Compose route strings expose gallery, image editor, onboarding, purchase and review flows. | Independent SwiftUI camera/gallery/import/export flow. No commerce or review solicitation. |
| String pool contains AVC/3GPP encoder identifiers and muxer references. | New portrait H.264 MOV writer, using processed frames; silent recording is an intentional limitation. |
| TFLite model and opaque image asset occur in package. | Neither is copied or used; their semantics remain unresolved. |

All four preset names, coefficients, interface design and artwork are new. The original Android payload contains JNI registration stubs and imports `vmInterpret`, which prevents an honest claim that its complete filter is available as readable source. The 98,930 decoded primary pool entries include library strings and duplicates. The 25 extracted GLSL snippets include templates and library shaders, not 25 verified proprietary filters.

Apple references used to check the platform APIs:

- https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle
- https://developer.apple.com/documentation/avfoundation/avassetwriterinput/requestmediadatawhenready(on:using:)
- https://developer.apple.com/documentation/photosui/photospickeritem/loadtransferable(type:)
