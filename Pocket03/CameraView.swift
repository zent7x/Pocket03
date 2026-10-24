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

    private var film: Film { Film(rawValue: selectedLook).flatMap { Film.cameraLooks.contains($0) ? $0 : nil } ?? .dreamy }
    private var busy: Bool { camera.isRecording || camera.isFinishing || importing || pendingMovie != nil }
    private var modeIcon: PixelIcon { mode == .video ? .video : mode == .imported ? .importTray : .camera }
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
            .background(LCD.shell)
        }
        .background(LCD.shell.ignoresSafeArea())
        .overlay {
            if page != .camera, let toast { toastChip(toast) }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .tint(LCD.ink)
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

    // MARK: - Panels

    private var statusBar: some View {
        HStack(spacing: 9) {
            LCDMeter(kind: .signal).frame(width: 15, height: 11)
            LCDMeter(kind: .battery).frame(width: 22, height: 11)
            PixelGlyph(icon: camera.torchOn ? .bolt : modeIcon, tint: camera.torchOn ? LCD.inkBright : LCD.inkDim)
                .frame(height: 11)
            if camera.isRecording {
                Text("REC").font(LCD.type(17)).foregroundStyle(LCD.alert)
            }
            Spacer(minLength: 4)
            if camera.isDemo {
                Text("DEMO").font(LCD.type(16)).foregroundStyle(LCD.shell)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(LCD.inkDim)
            }
            Text(Date(), format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(LCD.type(24)).foregroundStyle(LCD.ink)
        }
        .padding(.horizontal, 11).frame(height: 32)
        .background(LCD.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(LCD.inkFaint).frame(height: 1) }
        .scanlined(0.18)
    }

    private var modeBar: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases) { item in
                let active = mode == item
                Button { setMode(item) } label: {
                    VStack(spacing: 3) {
                        Text(item.rawValue.uppercased())
                            .font(LCD.type(21))
                            .foregroundStyle(active ? LCD.inkBright : LCD.inkDim)
                        Rectangle().fill(active ? LCD.ink : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity).frame(height: 31)
                }
                .buttonStyle(.plain).disabled(busy || renderingImport)
                .accessibilityIdentifier("mode-\(item.rawValue.lowercased())")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(LCD.shell)
    }

    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = mode == .imported ? importPreview : camera.preview {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 16) {
                        PixelGlyph(icon: mode == .imported ? .importTray : .camera, tint: LCD.inkDim)
                            .frame(height: 30)
                        Text(mode == .imported ? "Import a photo or video\nChoose a look. Make it a memory." : camera.cameraMessage ?? "Starting camera…")
                            .font(LCD.type(23)).foregroundStyle(LCD.ink).multilineTextAlignment(.center)
                        if mode == .imported {
                            Button("Open gallery") { pickerPresented = true }
                                .font(LCD.type(24)).foregroundStyle(LCD.shell)
                                .padding(.horizontal, 14).padding(.vertical, 7).background(LCD.ink)
                        } else if camera.cameraMessage != nil {
                            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                .font(LCD.type(22)).foregroundStyle(LCD.ink)
                        }
                    }.padding(24)
                }
                reticle
                if camera.isRecording {
                    VStack {
                        HStack {
                            Text(String(format: "%02d:%02d", camera.recordingSeconds / 60, camera.recordingSeconds % 60))
                                .font(LCD.type(26)).foregroundStyle(LCD.inkBright)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(LCD.shell.opacity(0.72))
                                .accessibilityIdentifier("recording-time")
                            Spacer()
                            HStack(spacing: 5) {
                                Circle().fill(LCD.alert).frame(width: 9, height: 9)
                                Text("REC").font(LCD.type(22)).foregroundStyle(LCD.alert)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(LCD.shell.opacity(0.72))
                        }
                        Spacer()
                    }.padding(13)
                }
                if importing {
                    VStack(spacing: 13) {
                        Text(importingMovie ? "PROCESSING \(Int(importProgress * 100))%" : "LOADING PHOTO")
                            .font(LCD.type(25)).foregroundStyle(LCD.inkBright)
                        meter(importProgress)
                        Text(importingMovie ? "\(film.rawValue) · silent output" : film.rawValue)
                            .font(LCD.type(18)).foregroundStyle(LCD.inkDim)
                        Button("Cancel") { importTask?.cancel() }
                            .font(LCD.type(23)).foregroundStyle(LCD.shell)
                            .padding(.horizontal, 13).padding(.vertical, 5).background(LCD.ink)
                    }
                    .padding(26).background(LCD.shell.opacity(0.94))
                    .overlay(Rectangle().stroke(LCD.ink, lineWidth: 1))
                } else if renderingImport || camera.isFinishing {
                    Text(camera.isFinishing ? "SAVING VIDEO…" : "PROCESSING…")
                        .font(LCD.type(24)).foregroundStyle(LCD.inkBright)
                        .padding(15).background(LCD.shell.opacity(0.94))
                        .overlay(Rectangle().stroke(LCD.ink, lineWidth: 1))
                }
                if let toast { toastChip(toast) }
                if let movie = pendingMovie {
                    Button("Retry saving video") { saveMovie(movie.0, thumbnail: movie.1, film: movie.2) }
                        .font(LCD.type(24)).foregroundStyle(LCD.shell)
                        .padding(14).background(LCD.ink)
                }
                if flashing { LCD.inkBright.opacity(0.9) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .scanlined(0.1)
        }
    }

    // Corner ticks instead of a drawn bezel: it frames the image without imitating a phone screen.
    private var reticle: some View {
        GeometryReader { geo in
            let length = min(geo.size.width, geo.size.height) * 0.07
            let inset: CGFloat = 7
            Path { path in
                let rect = CGRect(x: inset, y: inset,
                                  width: geo.size.width - inset * 2, height: geo.size.height - inset * 2)
                for corner in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                               (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
                    let (x, y, dx, dy) = (corner.0, corner.1, CGFloat(corner.2), CGFloat(corner.3))
                    path.move(to: CGPoint(x: x + dx * length, y: y))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + dy * length))
                }
            }
            .stroke(LCD.ink.opacity(0.65), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lookSelector: some View {
        HStack(spacing: 0) {
            Button { cycleLook(-1) } label: {
                PixelGlyph(icon: .arrowLeft, tint: LCD.ink).frame(height: 13).frame(width: 40, height: 48)
            }.accessibilityLabel("Previous camera look")
            Button { page = .looks } label: {
                HStack(spacing: 10) {
                    handsetChip(film, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(film.rawValue)
                            .font(LCD.type(23)).foregroundStyle(LCD.inkBright)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("LOOK \((Film.cameraLooks.firstIndex(of: film) ?? 0) + 1) OF 3")
                            .font(LCD.type(15)).foregroundStyle(LCD.inkDim)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityIdentifier("look-selector")
            Button { cycleLook(1) } label: {
                PixelGlyph(icon: .arrowRight, tint: LCD.ink).frame(height: 13).frame(width: 40, height: 48)
            }.accessibilityLabel("Next camera look")
        }
        .background(LCD.panel)
        .overlay(alignment: .top) { Rectangle().fill(LCD.inkFaint).frame(height: 1) }
        .disabled(busy)
        .scanlined(0.18)
    }

    private var infoBar: some View {
        HStack {
            Text(mode == .video ? "480×640 · SILENT" : mode == .imported ? "PHOTO & VIDEO IMPORT" : "0.3 MP · 480×640")
            Spacer()
            Text(String(format: "%03d", library.memories.count)).accessibilityIdentifier("gallery-count")
        }
        .font(LCD.type(16)).foregroundStyle(LCD.inkDim)
        .padding(.horizontal, 11).frame(height: 22)
        .background(LCD.shell)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(page == .options ? "OPTIONS" : page == .looks ? "PROCESSING" : page == .settings ? "SETTINGS" : page == .gallery ? "GALLERY" : "MEMORY")
                .font(LCD.type(26)).foregroundStyle(LCD.inkBright)
            Spacer()
        }
        .padding(.horizontal, 13).frame(height: 36)
        .background(LCD.panel)
        .overlay(alignment: .bottom) {
            VStack(spacing: 1) {
                Rectangle().fill(LCD.ink).frame(height: 1)
                Rectangle().fill(LCD.inkFaint).frame(height: 1)
            }
        }
        .scanlined(0.18)
    }

    @ViewBuilder private var pageContents: some View {
        switch page {
        case .options:
            VStack(spacing: 0) {
                menuRow("1", "Photo camera", icon: .camera) { setMode(.photo); page = .camera }
                menuRow("2", "Video camera", icon: .video) { setMode(.video); page = .camera }
                menuRow("3", "Import photo / video", icon: .importTray) { setMode(.imported); page = .camera; pickerPresented = true }
                menuRow("4", "Processing", icon: .sliders) { page = .looks }
                menuRow("5", "Settings", icon: .gear) { page = .settings }
                menuRow("6", "Gallery", icon: .grid) { page = .gallery }
                Spacer()
                Text("POCKET03\nSmall pictures. Long memories.")
                    .font(LCD.type(19)).foregroundStyle(LCD.inkDim)
                    .multilineTextAlignment(.center).padding(22)
            }
        case .looks:
            VStack(spacing: 0) {
                ForEach(Array(Film.cameraLooks.enumerated()), id: \.element.id) { index, look in
                    let active = film == look
                    Button { selectedLook = look.rawValue; page = .camera } label: {
                        HStack(alignment: .center, spacing: 11) {
                            Text("\(index + 1)")
                                .font(LCD.type(24))
                                .foregroundStyle(active ? LCD.shell : LCD.inkDim).frame(width: 16)
                            handsetChip(look, height: 56, inverted: active)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(look.rawValue).font(LCD.type(26))
                                    .foregroundStyle(active ? LCD.shell : LCD.inkBright)
                                Text(look.subtitle).font(LCD.type(17))
                                    .foregroundStyle(active ? LCD.shell.opacity(0.8) : LCD.inkDim)
                            }
                            Spacer(minLength: 0)
                            if active { PixelGlyph(icon: .check, tint: LCD.shell).frame(height: 15) }
                        }
                        .padding(.horizontal, 13).padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(active ? LCD.ink : LCD.shell)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("look-\(index)")
                    Rectangle().fill(LCD.inkFaint).frame(height: 1)
                }
                Spacer()
                Text("Recreated looks, inspired by early phone cameras.")
                    .font(LCD.type(18)).foregroundStyle(LCD.inkDim)
                    .multilineTextAlignment(.center).padding(20)
            }
        case .settings:
            VStack(spacing: 0) {
                menuRow("1", "Switch camera", icon: .camera) { camera.flip(); page = .camera }.disabled(camera.isDemo)
                menuRow("2", camera.torchOn ? "Torch: On" : "Torch: Off", icon: .bolt) { camera.toggleTorch() }.disabled(camera.isDemo)
                menuRow("3", "Zoom: \(Int(camera.zoom))×", icon: .sliders) { camera.setZoom(camera.zoom >= 3 ? 1 : camera.zoom + 1) }.disabled(camera.isDemo)
                VStack(alignment: .leading, spacing: 10) {
                    Text("EFFECT STRENGTH  \(Int(strength * 100))%")
                        .font(LCD.type(22)).foregroundStyle(LCD.inkBright)
                    meter(strength)
                    Slider(value: $strength, in: 0...1).tint(LCD.ink).accessibilityLabel("Effect strength")
                }.padding(.horizontal, 13).padding(.vertical, 15)
                Spacer()
                Text("Video is recorded without sound.\nPhotos stay on your iPhone until you share them.")
                    .font(LCD.type(18)).foregroundStyle(LCD.inkDim)
                    .multilineTextAlignment(.center).padding(20)
            }
        case .gallery:
            if library.memories.isEmpty {
                VStack(spacing: 17) {
                    PixelGlyph(icon: .grid, tint: LCD.inkFaint).frame(height: 34)
                    Text("No images or videos.\nCapture or import a memory.")
                        .font(LCD.type(23)).foregroundStyle(LCD.inkDim).multilineTextAlignment(.center)
                }.padding(.top, 70).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
                        ForEach(library.memories) { memory in
                            Button { openMemory(memory) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    if let image = library.thumbnail(memory) {
                                        Image(uiImage: image).resizable().interpolation(.none)
                                            .aspectRatio(3 / 4, contentMode: .fit)
                                            .overlay(Rectangle().stroke(LCD.inkDim, lineWidth: 1))
                                    }
                                    HStack(spacing: 5) {
                                        PixelGlyph(icon: memory.isVideo ? .play : .still, tint: LCD.ink).frame(height: 11)
                                        Text(memory.isVideo ? "VIDEO" : "IMAGE")
                                            .font(LCD.type(19)).foregroundStyle(LCD.ink)
                                    }
                                    Text(memory.date, format: .dateTime.day().month())
                                        .font(LCD.type(16)).foregroundStyle(LCD.inkDim)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("memory-\(memory.id)")
                        }
                    }.padding(13)
                }
            }
        case .viewer:
            if let memory = selectedMemory {
                VStack(spacing: 11) {
                    if memory.isVideo {
                        VideoPlayer(player: player).aspectRatio(3 / 4, contentMode: .fit)
                    } else if let image = library.thumbnail(memory) {
                        Image(uiImage: image).resizable().interpolation(.none).aspectRatio(3 / 4, contentMode: .fit)
                    }
                    Text(memory.film.rawValue).font(LCD.type(24)).foregroundStyle(LCD.inkBright)
                    Text(memory.isVideo ? "480×640 · SILENT VIDEO" : "480×640 · JPEG")
                        .font(LCD.type(17)).foregroundStyle(LCD.inkDim)
                    ShareLink(item: library.url(memory)) {
                        Text("Send / Share").font(LCD.type(24)).foregroundStyle(LCD.shell)
                            .padding(.horizontal, 15).padding(.vertical, 7).background(LCD.ink)
                    }
                    Spacer(minLength: 0)
                }.padding(13)
            }
        case .camera: EmptyView()
        }
    }

    private var softKeys: some View {
        HStack(spacing: 0) {
            let leftTitle = page == .camera ? "Gallery" : "Camera"
            Button { leftKey() } label: { softKeyLabel(leftTitle, emphasis: false) }
                .accessibilityIdentifier("memories").accessibilityLabel(leftTitle)
                .disabled(busy || renderingImport)
            Rectangle().fill(LCD.inkFaint).frame(width: 1, height: 30)
            Button { centerKey() } label: { softKeyLabel(centerTitle, emphasis: true) }
                .accessibilityIdentifier("shutter").accessibilityLabel(centerTitle)
                .disabled(centerDisabled)
            Rectangle().fill(LCD.inkFaint).frame(width: 1, height: 30)
            let rightTitle = page == .camera ? "Options" : "Back"
            Button { rightKey() } label: { softKeyLabel(rightTitle, emphasis: false) }
                .accessibilityIdentifier("options").accessibilityLabel(rightTitle)
                .disabled(busy || renderingImport)
        }
        .buttonStyle(.plain)
        .background(LCD.panel)
        .overlay(alignment: .top) { Rectangle().fill(LCD.inkFaint).frame(height: 1) }
        .scanlined(0.18)
    }

    // MARK: - Pieces

    private func softKeyLabel(_ text: String, emphasis: Bool) -> some View {
        Text(text.uppercased())
            .font(LCD.type(emphasis ? 28 : 22))
            .foregroundStyle(emphasis ? LCD.inkBright : LCD.ink)
            .frame(maxWidth: .infinity).frame(height: 52)
    }

    private func menuRow(_ number: String, _ title: String, icon: PixelIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(number).font(LCD.type(23)).foregroundStyle(LCD.inkDim).frame(width: 16)
                PixelGlyph(icon: icon, tint: LCD.ink).frame(height: 15)
                Text(title).font(LCD.type(25)).foregroundStyle(LCD.inkBright)
                Spacer(minLength: 0)
                PixelGlyph(icon: .chevron, tint: LCD.inkFaint).frame(height: 13)
            }
            .padding(.horizontal, 13).frame(minHeight: 50)
            .background(LCD.shell)
            .overlay(alignment: .bottom) { Rectangle().fill(LCD.inkFaint).frame(height: 1) }
        }.buttonStyle(.plain)
    }

    // The handset picture sits on a lifted plate so a dark phone still reads against the panel.
    private func handsetChip(_ look: Film, height: CGFloat, inverted: Bool = false) -> some View {
        PhoneGlyph(film: look)
            .frame(height: height - 8)
            .padding(4)
            .background(inverted ? LCD.shell.opacity(0.18) : LCD.panelLift)
            .overlay(Rectangle().stroke(inverted ? LCD.shell.opacity(0.35) : LCD.inkFaint, lineWidth: 1))
            .frame(height: height)
    }

    private func meter(_ value: Double) -> some View {
        GeometryReader { geo in
            let cells = 20
            let gap: CGFloat = 2
            let cellWidth = (geo.size.width - gap * CGFloat(cells - 1)) / CGFloat(cells)
            let filled = Int((Double(cells) * min(1, max(0, value))).rounded())
            HStack(spacing: gap) {
                ForEach(0..<cells, id: \.self) { index in
                    Rectangle().fill(index < filled ? LCD.ink : LCD.inkFaint).frame(width: cellWidth)
                }
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    private func toastChip(_ text: String) -> some View {
        Text(text).font(LCD.type(25)).foregroundStyle(LCD.shell)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(LCD.ink)
            .transition(.opacity)
    }

    private var centerDisabled: Bool {
        if page == .viewer { return exporting }
        if page != .camera { return busy || renderingImport || (page == .gallery && library.memories.isEmpty) }
        if camera.isRecording { return false }
        return busy || renderingImport || (mode != .imported && camera.preview == nil)
    }

    // MARK: - Actions

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
