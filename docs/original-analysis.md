# 0.3MP Camera — static reverse engineering

Analyzed Android 1.5.12, version code 187, package `com.dwsh.o3mp`, arm64-v8a. This is a partial reverse engineering result; the exact proprietary image filter is not yet recovered. No app execution or device installation was performed.

## Download and identity

- Official listing: https://play.google.com/store/apps/details?id=com.dwsh.o3mp
- Download page: https://apkpure.net/0-3mp-camera/com.dwsh.o3mp/download
- Download URL: `https://d.apkpure.net/b/XAPK/com.dwsh.o3mp?nc=arm64-v8a&sv=24&versionCode=187`
- XAPK SHA-256: `18362aeb327f85b4191f5723356571c90d4b7943b6a03d6cb586be6427415e13`
- Base APK SHA-256: `c63ba0fd921cfa0eb04d9fe0e680e60153545c21a23c6ba5e2f4cad2874e83fc`
- APKPure supplies the artifact; it was not acquired directly from Google Play. Signing certificate equivalence to a Play-installed copy has not been independently verified.

The downloaded bundle and extracted APK splits are in `artifacts/`. The decoded base manifest independently confirms version 1.5.12 (187), minimum API 24 and target API 36. Complete local file hashes are in `evidence/sha256.json`.

## REA evidence and tools

REA 6.7.0 CLI successfully ran `inspect-artifact` on the base APK. Full Evidence is preserved in `evidence/rea-artifact.json`:

`ev_7217919a1c35af941ae5dca0e0d7f8ec93becd7eb692b62cabc8059339cacd81`

Its inventory substep is `ev_8a0a796ad2b92ab80118a8f69317923765e4484d5ebbba5cae753d622d60cfbc`. The manifest reports 321 nodes, 399 occurrences and 398 edges. This establishes artifact inventory, not executed behavior.

REA Android code inspection could not run: its required `jadx-headless-mcp 0.7.1` JAR is not configured. The exact error is in `evidence/rea-android.json`. REA doctor finds aligned Codex registration, but no connected MCP tools in this session and no configured native engine. No configuration was changed or engine installed.

Additional findings below come from the installed standalone JADX, ZIP extraction, native symbol/string inspection and an isolated string decoder, rather than REA Android Evidence. JADX emitted 25 errors; the output is incomplete decompiler reconstruction, not original source.

## Findings

| Question | Result | Evidence and limits |
|---|---|---|
| What is the implementation stack? | Kotlin/Jetpack Compose UI and an OpenGL renderer are present. | Compose source markers survive in the decoded string pool; `ya/f.java` implements `GLSurfaceView.Renderer`. Exact runtime flow remains unobserved. |
| How is the main app logic protected? | Many method bodies are JNI stubs backed by a native VM layer. | `MainActivity.onCreate/onDestroy` and renderer callbacks are native. `com/google/firebase/crashlytics/internal/R.java` loads `crashlytics-ndk` and declares registration methods. That library imports `vmInterpret`, `getCacheClass` and `cacheInitial` from the native layer. Do not assume its role is standard Firebase telemetry from its filename. |
| Is there a low-resolution render size? | `ya.f` constructs a `Size(480, 640)` and a separate `Size(1440, 1920)`. | Direct constructor observation. Which output modes select each size has not been recovered. |
| How does rendering appear organized? | Multiple rendering pass objects, rescaling and shader lists are present. | `ya.f`, `ab.a`, `bb.a`, `cb.a`, `db.a`, `eb.a`, `fb.a`; decoded constructor labels identify source/destination sizes, viewport and rescale state. Pass order is unknown. |
| Is halation implemented? | The pool contains explicit high-pass, blur and merge parameter names. | Pool indices 2556657–2557126 include `halationBlurTempTexture`, `halationBlurResInv`, `redHalationOffset`, per-channel hue values, merge textures/intensity, `halationIntensity`, and `halationCuttoff`. These strongly suggest a highlight extraction → blur → merge design, but order and formulas are inference. |
| Is bokeh represented? | `bokeh_value` and `bokeh_ratio` are present. | Pool indices 2558062 and 2558074. No recovered formula or demonstrated feature activation. |
| How is crop/rescale represented? | Post scaling, center, dimensions and orientation controls are named. | Pool indices 2558558–2558620: `post_scaleX/Y`, `post_centerX/Y`, `post_dimens`, `post_orientation`. |
| Does image processing use a model? | A valid TFLite-header artifact is bundled and referenced by an app class. | `assets/aarchimodel.tflite`, 4,005,951 bytes, starts with the `TFL3` identifier; `ya/g.java` references its name. `found ML score`, `day`, `night` and EXIF ISO strings suggest exposure/scene classification, but model input/output semantics and its actual role are unverified. |
| What video path is suggested? | Codec/muxer code and AVC/3GPP media types are present. | Pool region 2554073–2555123 includes `video/avc`, `audio/3gpp`, `createInputSurface`, encoder/drain messages and muxer fields. `.3gp` output name literals also occur. Actual settings and selected container remain unknown. |
| What screens are represented? | Editor/camera, gallery/viewer, image editor, onboarding, purchase and review flows. | Decoded Compose markers and route literals including `gallery`, `viewer?fileName=`, `imageEditor?fileName=`, `purchase`, `review?popToCamera=`. Literal presence does not demonstrate navigation reachability. |

## String and shader recovery

`zd/a.java` contains readable `b(long, String[])` and `d(long)` decoding functions despite other methods being native. The decoder was isolated by removing the native registration initializer and adding an input/output wrapper; no application lifecycle code was run.

The pool uses shared low 32-bit seed values. Inverting the index calculation allows sequential decoding of the pool's length-prefixed strings. This recovered:

- 98,930 primary pool entries, including duplicates, library text and empty strings.
- 311 secondary pool entries.
- 25 GLSL snippets, including library shaders and format templates; this is not 25 proprietary effects.
- 23,837 primary direct source references independently match their sequentially decoded pool values, with zero mismatches.

Artifacts:

- `evidence/string-pool.json`: primary entries, indices and seeds.
- `evidence/string-pool-second.json`: secondary pool entries.
- `evidence/decoded-strings.json`: direct source references and source file paths.
- `recovered/app-strings.json`: a positional slice containing app-related strings; it is not a complete semantic app/library classification.
- `recovered/shaders/`: recovered GLSL snippets, named by pool index. Several are templates with format placeholders.
- `tools/StringDecoder.java`, `tools/DumpPool.java`: isolated decoder and sequential pool walker.
- `evidence/decoder-validation.json`: recovery counts and reference agreement.

Re-run the pool walker after compiling both Java files with the existing JDK:

```sh
javac -d tools tools/StringDecoder.java tools/DumpPool.java
java -cp tools DumpPool > evidence/string-pool.tsv
java -cp tools DumpPool second 2508710722 > evidence/string-pool-second.tsv
```

## Remaining work

The exact CMOS emulation, debayering, noise generation, color transforms, filter coefficients and rendering pass selection are unresolved. The recovered GLSL snippets alone do not establish those algorithms. The opaque 524,304-byte asset `101b73897ec7a7b14459dcbd91f60d6b8a862155` has a decoded reference near `glTexImage2D`; its format and pixel/lookup semantics remain unknown.

The next focused target is native registration ID 521 for renderer `ya.f`, especially `onSurfaceCreated` and `onDrawFrame`, followed by the native string accessors `zd.a.a/c`. This requires native VM analysis using a suitable disassembler or bounded Android runtime observation. REA's missing Android JAR and native provider must be supplied for those REA-specific code operations. The app has not been fully reversed.
