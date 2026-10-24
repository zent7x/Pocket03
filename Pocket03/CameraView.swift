import SwiftUI
import PhotosUI
import AVKit

private enum PhonePage { case camera, options, looks, settings, gallery, viewer }

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @StateObject private var library = MediaLibrary()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedCameraLook") private var selectedLook = Film.dreamy.rawValue
    @AppStorage("effectStrength") private var strength = 0.8
    @State private var mode: CaptureMode = .photo
    @State private var page: PhonePage = .camera
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerPresented = false
    @State private var importOriginal: UIImage?
    @State private var importPreview: UIImage?
    @State private var importTask: Task<Void, Never>?
    @State private var importProgress = 0.0
    @State private var importing = false
    @State private var importingMovie = false
    @State private var renderingImport = false
    @State private var importGeneration = 0
    @State private var pendingMovie: (URL, UIImage, Film)?
    @State private var selectedMemory: Memory?
    @State private var player: AVPlayer?
    @State private var movieHandlerSet = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var flashing = false
    @State private var exporting = false

    private let ink = Color(red: 0.06, green: 0.11, blue: 0.17)
    private let paper = Color(red: 0.82, green: 0.89, blue: 0.93)
    private let highlight = Color(red: 0.09, green: 0.30, blue: 0.60)
    // A warm second colour: counts, indices and state read differently from labels.
    private let accent = Color(red: 0.74, green: 0.36, blue: 0.06)
    private let live = Color(red: 0.13, green: 0.50, blue: 0.16)
    private var film: Film { Film(rawValue: selectedLook).flatMap { Film.cameraLooks.contains($0) ? $0 : nil } ?? .dreamy }
    private var busy: Bool { camera.isRecording || camera.isFinishing || importing || pendingMovie != nil }
    private var centerTitle: String {
        if page != .camera {
            switch page {
            case .viewer: return "Save"
            case .gallery: return "Open"
            case .settings: return "Done"
            default: return "Select"
            }
        }
        if camera.isRecording { return "Stop" }
        if mode == .video { return "Record" }
        if mode == .imported { return importOriginal == nil ? "Open" : "Save" }
        return "Capture"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusBar
                if page == .camera {
                    modeBar
                    viewfinder.frame(maxWidth: .infinity, maxHeight: .infinity)
                    lookSelector
                    infoBar
                } else {
                    titleBar
                    pageContents.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                softKeys
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(paper, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1).allowsHitTesting(false))
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if page != .camera, let toast {
                Text(toast).font(pixel(27)).foregroundStyle(ink).padding(13).background(paper).overlay(Rectangle().stroke(highlight, lineWidth: 2))
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.light)
        .photosPicker(isPresented: $pickerPresented, selection: $pickerItem, matching: .any(of: [.images, .videos]))
        .alert("Pocket03", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            if let movie = pendingMovie {
                Button("Retry saving movie") { camera.error = nil; saveMovie(movie.0, thumbnail: movie.1, film: movie.2) }
            }
            Button("OK") { camera.error = nil }
        } message: { Text(camera.error ?? "") }
        .onAppear {
            camera.update(film: film, strength: strength)
            if !movieHandlerSet {
                camera.onMovie = { url, thumbnail, film in saveMovie(url, thumbnail: thumbnail, film: film) }
                movieHandlerSet = true
                if let error = library.loadError { camera.error = "Could not load gallery: \(error)" }
            }
            camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else if phase == .background { camera.stop() }
        }
        .onChange(of: selectedLook) { _, _ in applyTreatment() }
        .onChange(of: strength) { _, _ in applyTreatment() }
        .onChange(of: pickerItem) { _, item in if let item { loadImport(item) } }
        .onChange(of: page) { _, newPage in if newPage != .viewer { player?.pause(); player = nil } }
        .onDisappear { importTask?.cancel() }
    }

    private func pixel(_ size: CGFloat) -> Font { .custom("VT323-Regular", size: size) }
    private var chrome: LinearGradient { LinearGradient(colors: [Color(red: 0.91, green: 0.96, blue: 0.98), paper, Color(red: 0.70, green: 0.81, blue: 0.87)], startPoint: .topLeading, endPoint: .bottomTrailing) }

    private var statusBar: some View {
        HStack(spacing: 7) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { i in Rectangle().fill(ink).frame(width: 3, height: CGFloat(4 + i * 3)) }
            }.accessibilityHidden(true)
            HStack(spacing: 1) { ForEach(0..<4) { _ in Rectangle().fill(live).frame(width: 3, height: 8) } }
                .padding(2).overlay(Rectangle().stroke(ink, lineWidth: 1)).accessibilityHidden(true)
            Image(systemName: camera.torchOn ? "bolt.fill" : "camera.fill").font(.system(size: 11)).accessibilityHidden(true)
            if camera.isRecording { Text("REC").foregroundStyle(accent) }
            Spacer()
            if camera.isDemo { Text("DEMO").font(pixel(16)).foregroundStyle(accent) }
            Text(Date(), format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).font(pixel(26))
        }
        .font(pixel(19)).foregroundStyle(ink).padding(.horizontal, 10).frame(height: 31).background(chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.6)).frame(height: 1) }
    }
    private var modeBar: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases) { item in
                Button { setMode(item) } label: {
                    Text(item.rawValue).font(pixel(23)).frame(maxWidth: .infinity).frame(height: 33)
                        .background(mode == item ? highlight : .clear).foregroundStyle(mode == item ? .white : ink)
                }.buttonStyle(.plain).disabled(busy || renderingImport)
                    .accessibilityIdentifier("mode-\(item.rawValue.lowercased())")
                    .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }.background(paper)
            .overlay(alignment: .bottom) { Rectangle().fill(highlight.opacity(0.22)).frame(height: 1) }
    }
    private var lookSelector: some View {
        HStack(spacing: 0) {
            Button { cycleLook(-1) } label: { Text("◀").font(pixel(22)).frame(width: 42, height: 43) }.accessibilityLabel("Previous camera look")
            Button { page = .looks } label: {
                HStack(spacing: 9) {
                    PhoneGlyph(film: film).frame(height: 36)
                    VStack(spacing: 0) {
                        Text(film.rawValue).font(pixel(26)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("LOOK \((Film.cameraLooks.firstIndex(of: film) ?? 0) + 1) / 3").font(pixel(15)).foregroundStyle(accent)
                    }
                }.frame(maxWidth: .infinity, minHeight: 46)
            }.accessibilityIdentifier("look-selector")
            Button { cycleLook(1) } label: { Text("▶").font(pixel(22)).frame(width: 42, height: 43) }.accessibilityLabel("Next camera look")
        }.foregroundStyle(ink).background(chrome).disabled(busy)
    }
    private var infoBar: some View {
        HStack {
            Text(mode == .video ? "480×640 · silent video" : mode == .imported ? "Photo & video import" : "0.3 MP · 480×640")
            Spacer()
            Text(String(format: "%03d", library.memories.count)).foregroundStyle(accent).accessibilityIdentifier("gallery-count")
        }.font(pixel(17)).foregroundStyle(highlight).padding(.horizontal, 10).frame(height: 23).background(paper)
    }
    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = mode == .imported ? importPreview : camera.preview {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: mode == .imported ? "photo.on.rectangle.angled" : "camera").font(.system(size: 32, weight: .light))
                        Text(mode == .imported ? "Import a photo or video\nChoose a look. Make it a memory." : camera.cameraMessage ?? "Starting camera…")
                            .font(pixel(24)).multilineTextAlignment(.center)
                        if mode == .imported {
                            Button("Open gallery") { pickerPresented = true }.font(pixel(25)).padding(10).background(highlight)
                        } else if camera.cameraMessage != nil {
                            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(pixel(23))
                        }
                    }.padding(25).foregroundStyle(.white)
                }
                if camera.isRecording {
                    VStack { HStack {
                        Text(String(format: "%02d:%02d", camera.recordingSeconds / 60, camera.recordingSeconds % 60))
                            .font(pixel(28)).padding(5).background(.black.opacity(0.6)).accessibilityIdentifier("recording-time")
                        Spacer(); Text("● REC").foregroundStyle(.red).font(pixel(24))
                    }; Spacer() }.padding(12).foregroundStyle(.white)
                }
                if importing {
                    VStack(spacing: 14) {
                        Text(importingMovie ? "Processing video… \(Int(importProgress * 100))%" : "Loading photo…").font(pixel(25))
                        ProgressView(value: importProgress).tint(.white)
                        Text(importingMovie ? "\(film.rawValue) · silent output" : film.rawValue).font(pixel(18))
                        Button("Cancel") { importTask?.cancel() }.font(pixel(24)).padding(8)
                    }.padding(25).foregroundStyle(.white).background(highlight.opacity(0.95))
                } else if renderingImport || camera.isFinishing {
                    Text(camera.isFinishing ? "Saving video…" : "Processing…").font(pixel(25)).padding(15).foregroundStyle(ink).background(paper)
                }
                if let toast { Text(toast).font(pixel(27)).foregroundStyle(ink).padding(13).background(paper).overlay(Rectangle().stroke(highlight, lineWidth: 2)).transition(.opacity) }
                if let movie = pendingMovie {
                    Button("Retry saving video") { saveMovie(movie.0, thumbnail: movie.1, film: movie.2) }.font(pixel(25)).padding(15).foregroundStyle(ink).background(paper)
                }
                if flashing { Color.white.opacity(0.85) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
    private var titleBar: some View {
        Text(page == .options ? "Options" : page == .looks ? "Processing" : page == .settings ? "Settings" : page == .gallery ? "Gallery" : "Memory")
            .font(pixel(29)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 38)
            .background(LinearGradient(colors: [highlight, Color(red: 0.23, green: 0.43, blue: 0.65)], startPoint: .top, endPoint: .bottom))
    }
    @ViewBuilder private var pageContents: some View {
        switch page {
        case .options:
            VStack(spacing: 0) {
                menuRow("1", "Photo camera", icon: "camera") { setMode(.photo); page = .camera }
                menuRow("2", "Video camera", icon: "video") { setMode(.video); page = .camera }
                menuRow("3", "Import photo / video", icon: "square.and.arrow.down") { setMode(.imported); page = .camera; pickerPresented = true }
                menuRow("4", "Processing", icon: "slider.horizontal.3") { page = .looks }
                menuRow("5", "Settings", icon: "gearshape") { page = .settings }
                menuRow("6", "Gallery", icon: "photo.on.rectangle") { page = .gallery }
                Spacer()
                Text("Pocket03\nSmall pictures. Long memories.").font(pixel(21)).multilineTextAlignment(.center).foregroundStyle(highlight).padding(24)
            }
        case .looks:
            VStack(spacing: 0) {
                ForEach(Array(Film.cameraLooks.enumerated()), id: \.element.id) { index, look in
                    Button { selectedLook = look.rawValue; page = .camera } label: {
                        HStack(alignment: .center, spacing: 11) {
                            Text("\(index + 1)").foregroundStyle(film == look ? .white : accent).frame(width: 20)
                            PhoneGlyph(film: look).frame(height: 58)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(look.rawValue).font(pixel(27))
                                Text(look.subtitle).font(pixel(18)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(film == look ? .white.opacity(0.85) : highlight)
                            }
                            Spacer(minLength: 0)
                            if film == look { Text("✓") }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(film == look ? .white : ink).background(film == look ? highlight : .clear)
                    }.buttonStyle(.plain).accessibilityIdentifier("look-\(index)")
                }
                Spacer()
                Text("Recreated looks, inspired by early phone cameras.").font(pixel(20)).foregroundStyle(highlight).multilineTextAlignment(.center).padding(22)
            }.font(pixel(26))
        case .settings:
            VStack(spacing: 0) {
                menuRow("1", "Switch camera", icon: "arrow.triangle.2.circlepath.camera") { camera.flip(); page = .camera }.disabled(camera.isDemo)
                menuRow("2", camera.torchOn ? "Torch: On" : "Torch: Off", icon: "bolt") { camera.toggleTorch() }.disabled(camera.isDemo)
                menuRow("3", "Zoom: \(Int(camera.zoom))×", icon: "plus.magnifyingglass") { camera.setZoom(camera.zoom >= 3 ? 1 : camera.zoom + 1) }.disabled(camera.isDemo)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 0) {
                        Text("Effect strength: ").font(pixel(25))
                        Text("\(Int(strength * 100))%").font(pixel(25)).foregroundStyle(accent)
                    }
                    Slider(value: $strength, in: 0...1).tint(highlight).accessibilityLabel("Effect strength")
                }.padding(17)
                Spacer()
                Text("Video is recorded without sound.\nPhotos stay on your iPhone until you share them.").font(pixel(21)).foregroundStyle(highlight).multilineTextAlignment(.center).padding(22)
            }
        case .gallery:
            if library.memories.isEmpty {
                VStack(spacing: 20) { Image(systemName: "photo.on.rectangle").font(.system(size: 40)); Text("No images or videos.\nCapture or import a memory.").font(pixel(25)).multilineTextAlignment(.center) }.padding(.top, 80).foregroundStyle(highlight)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(library.memories) { memory in
                            Button { openMemory(memory) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let image = library.thumbnail(memory) { Image(uiImage: image).resizable().interpolation(.none).aspectRatio(3 / 4, contentMode: .fit).border(.white, width: 2) }
                                    HStack(spacing: 5) {
                                        Text(memory.isVideo ? "▶" : "▣").font(pixel(22)).foregroundStyle(accent)
                                        Text(memory.isVideo ? "Video" : "Image").font(pixel(22))
                                    }
                                    Text(memory.date, format: .dateTime.day().month()).font(pixel(18)).foregroundStyle(highlight)
                                }.foregroundStyle(ink)
                            }.buttonStyle(.plain).accessibilityIdentifier("memory-\(memory.id)")
                        }
                    }.padding(12)
                }
            }
        case .viewer:
            if let memory = selectedMemory {
                VStack(spacing: 12) {
                    if memory.isVideo { VideoPlayer(player: player).aspectRatio(3 / 4, contentMode: .fit) }
                    else if let image = library.thumbnail(memory) { Image(uiImage: image).resizable().interpolation(.none).aspectRatio(3 / 4, contentMode: .fit) }
                    Text(memory.film.rawValue).font(pixel(25)).foregroundStyle(accent)
                    Text(memory.isVideo ? "480×640 · silent video" : "480×640 · JPEG").font(pixel(19)).foregroundStyle(highlight)
                    ShareLink(item: library.url(memory)) { Text("Send / Share").font(pixel(26)).padding(10) }
                    Spacer(minLength: 0)
                }.padding(12).foregroundStyle(ink)
            }
        case .camera: EmptyView()
        }
    }
    private func menuRow(_ number: String, _ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(number).font(pixel(25)).foregroundStyle(accent).frame(width: 20)
                Image(systemName: icon).font(.system(size: 17)).frame(width: 23)
                Text(title).font(pixel(27)); Spacer(minLength: 0)
                Text("›").font(pixel(27))
            }.foregroundStyle(ink).padding(.horizontal, 12).frame(minHeight: 53)
                .background(Color.white.opacity(0.3))
                .overlay(alignment: .bottom) { Rectangle().fill(highlight.opacity(0.18)).frame(height: 1) }
        }.buttonStyle(.plain)
    }
    private var softKeys: some View {
        HStack(spacing: 0) {
            Button { leftKey() } label: { Text(page == .camera ? "Gallery" : "Camera").font(pixel(26)).frame(maxWidth: .infinity, minHeight: 54) }
                .accessibilityIdentifier("memories").disabled(busy || renderingImport)
            Button { centerKey() } label: { Text(centerTitle).font(pixel(32)).frame(maxWidth: .infinity, minHeight: 54) }
                .accessibilityIdentifier("shutter").disabled(centerDisabled)
            Button { rightKey() } label: { Text(page == .camera ? "Options" : "Back").font(pixel(26)).frame(maxWidth: .infinity, minHeight: 54) }
                .accessibilityIdentifier("options").disabled(busy || renderingImport)
        }.buttonStyle(.plain).foregroundStyle(ink).background(chrome)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.7)).frame(height: 1) }
    }
    private var centerDisabled: Bool {
        if page == .viewer { return exporting }
        if page != .camera { return busy || renderingImport || (page == .gallery && library.memories.isEmpty) }
        if camera.isRecording { return false }
        return busy || renderingImport || (mode != .imported && camera.preview == nil)
    }
    private func leftKey() { page = page == .camera ? .gallery : .camera }
    private func rightKey() { page = page == .camera ? .options : page == .viewer ? .gallery : .camera }
    private func setMode(_ newMode: CaptureMode) { guard !busy, !renderingImport else { return }; mode = newMode }
    private func cycleLook(_ direction: Int) {
        guard !busy else { return }
        let current = Film.cameraLooks.firstIndex(of: film) ?? 0
        selectedLook = Film.cameraLooks[(current + direction + 3) % 3].rawValue
    }
    private func centerKey() {
        if page == .viewer, let memory = selectedMemory {
            guard !exporting else { return }
            exporting = true
            Task {
                defer { exporting = false }
                do { try await library.export(memory); showToast("Saved to Photos") }
                catch { camera.error = error.localizedDescription }
            }
            return
        }
        if page == .gallery, let memory = library.memories.first { openMemory(memory); return }
        if page == .options { setMode(.photo); page = .camera; return }
        if page == .looks || page == .settings { page = .camera; return }
        guard page == .camera else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if mode == .video { camera.toggleRecording() }
        else if mode == .imported {
            if let image = importPreview { savePhoto(image) }
            else { pickerPresented = true }
        } else {
            flashing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashing = false }
            camera.capture { image in if let image { savePhoto(image) } else { camera.error = "The camera is not ready. Please try again." } }
        }
    }
    private func openMemory(_ memory: Memory) {
        selectedMemory = memory
        if memory.isVideo { player = AVPlayer(url: library.url(memory)); player?.play() }
        page = .viewer
    }
    private func applyTreatment() {
        camera.update(film: film, strength: strength)
        guard let image = importOriginal else { return }
        importGeneration += 1
        let generation = importGeneration
        renderingImport = true
        camera.importPhoto(image) { result in
            guard generation == importGeneration else { return }
            renderingImport = false
            importPreview = result
            if result == nil { camera.error = "This photo could not be processed." }
        }
    }
    private func loadImport(_ item: PhotosPickerItem) {
        guard !busy else { return }
        mode = .imported; page = .camera
        let chosenFilm = film, chosenStrength = strength
        importing = true; importProgress = 0
        importingMovie = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
        importTask = Task {
            defer { importing = false; pickerItem = nil; importTask = nil }
            do {
                if importingMovie {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw CocoaError(.fileReadCorruptFile) }
                    defer { try? FileManager.default.removeItem(at: movie.url) }
                    let result = try await VideoImporter().process(url: movie.url, film: chosenFilm, strength: chosenStrength) { importProgress = $0 }
                    importOriginal = nil; importPreview = nil
                    saveMovie(result.url, thumbnail: result.thumbnail, film: chosenFilm)
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    try Task.checkCancellation()
                    importOriginal = image
                    applyTreatment()
                }
            } catch is CancellationError { showToast("Import cancelled") }
            catch { camera.error = "Import failed. " + error.localizedDescription }
        }
    }
    private func savePhoto(_ image: UIImage) {
        do { try library.savePhoto(image, film: film); showToast("MEMORY SAVED") }
        catch { camera.error = error.localizedDescription }
    }
    private func saveMovie(_ url: URL, thumbnail: UIImage, film: Film) {
        do {
            try library.saveVideo(url, thumbnail: thumbnail, film: film)
            pendingMovie = nil
            try? FileManager.default.removeItem(at: url)
            showToast("MOVIE SAVED")
        } catch {
            pendingMovie = (url, thumbnail, film)
            camera.error = "Your movie is kept temporarily. Free some space, then retry saving. " + error.localizedDescription
        }
    }
    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}
