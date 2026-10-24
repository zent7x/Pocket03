import SwiftUI
import PhotosUI

private let phosphor = Color(red: 0.78, green: 0.87, blue: 0.65)
private let ink = Color(red: 0.12, green: 0.19, blue: 0.16)

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @StateObject private var library = MediaLibrary()
    @Environment(\.scenePhase) private var scenePhase
    @State private var film: Film = .daydream
    @State private var strength = 0.8
    @State private var videoMode = false
    @State private var gallery = false
    @State private var options = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var toast: String?
    @State private var flashing = false
    @State private var importing = false
    @State private var movieHandlerSet = false
    @State private var toastTask: Task<Void, Never>?

    private var busy: Bool { camera.isRecording || camera.isFinishing || importing }
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 730
            VStack(spacing: compact ? 14 : 23) {
                masthead
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(camera.isDemo ? "DEMO / NO CAMERA" : "POCKET NETWORK")
                        Spacer()
                        Text(Date(), style: .time)
                        Image(systemName: "battery.100percent")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 13).frame(height: 31)
                    .foregroundStyle(ink).background(phosphor)
                    viewfinder
                    HStack {
                        Text(videoMode ? "MOVIE · SILENT" : "PHOTO · 480 × 640")
                        Spacer()
                        Text(String(format: "%03d", library.memories.count))
                        Image(systemName: "square.stack")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink).padding(.horizontal, 13).frame(height: 34).background(phosphor)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black, lineWidth: 3))
                .padding(7).background(RoundedRectangle(cornerRadius: 15).fill(Color.black.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.08)))

                HStack {
                    Button { withAnimation { videoMode.toggle() } } label: {
                        Label(videoMode ? "VIDEO" : "PHOTO", systemImage: videoMode ? "video" : "camera")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }.disabled(busy).accessibilityIdentifier("mode")
                    Spacer()
                    Button { options = true } label: {
                        HStack(spacing: 6) { Circle().fill(phosphor).frame(width: 5, height: 5); Text(film.rawValue); Image(systemName: "chevron.down") }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }.disabled(busy)
                }.foregroundStyle(phosphor).padding(.horizontal, 7)

                HStack(spacing: 0) {
                    Button { gallery = true } label: {
                        VStack(spacing: 9) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.05)).frame(width: 49, height: 42)
                                if let last = library.memories.first, let image = library.thumbnail(last) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 41, height: 34).clipped().clipShape(RoundedRectangle(cornerRadius: 3))
                                } else { Image(systemName: "square.stack").font(.system(size: 19)) }
                            }
                            Text("MEMORIES").font(.system(size: 9, weight: .medium, design: .monospaced))
                        }.frame(maxWidth: .infinity)
                    }.disabled(camera.isRecording || camera.isFinishing).accessibilityIdentifier("memories")
                    Button(action: shutter) {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Color(white: 0.40), Color(white: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 91, height: 91)
                            Circle().stroke(.black.opacity(0.8), lineWidth: 2).frame(width: 83, height: 83)
                            Circle().fill(camera.isRecording ? Color(red: 0.9, green: 0.27, blue: 0.17) : phosphor).frame(width: 69, height: 69)
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 3)
                            if camera.isRecording { RoundedRectangle(cornerRadius: 3).fill(ink).frame(width: 23, height: 23) }
                            else { Image(systemName: videoMode ? "video.fill" : "camera.aperture").font(.system(size: 28, weight: .light)).foregroundStyle(ink) }
                        }
                    }.buttonStyle(.plain).disabled(camera.preview == nil || camera.isFinishing || importing)
                        .accessibilityLabel(camera.isRecording ? "Stop recording" : videoMode ? "Record silent video" : "Capture photo").accessibilityIdentifier("shutter")
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        VStack(spacing: 9) {
                            Image(systemName: "arrow.down.to.line.compact").font(.system(size: 24, weight: .light)).frame(height: 42)
                            Text(importing ? "IMPORTING" : "IMPORT").font(.system(size: 9, weight: .medium, design: .monospaced))
                        }.frame(maxWidth: .infinity)
                    }.disabled(busy).accessibilityIdentifier("import")
                }.foregroundStyle(Color(white: 0.72))
                HStack(spacing: 10) {
                    Capsule().fill(.white.opacity(0.12)).frame(width: 35, height: 3)
                    Text("LIFE LOOKED GOOD IN LOW RES.").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.7)
                    Capsule().fill(.white.opacity(0.12)).frame(width: 35, height: 3)
                }.foregroundStyle(Color(white: 0.42))
            }
            .padding(.horizontal, 23).padding(.top, compact ? 8 : 14).padding(.bottom, 12)
            .frame(maxWidth: 500).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.075)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .sheet(isPresented: $gallery) { GalleryView(library: library) }
        .sheet(isPresented: $options) { filmSheet.presentationDetents([.height(390)]) }
        .alert("Pocket03", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            Button("OK") { camera.error = nil }
        } message: { Text(camera.error ?? "") }
        .onAppear {
            if !movieHandlerSet {
                camera.onMovie = { url, thumbnail, film in
                    do { try library.saveVideo(url, thumbnail: thumbnail, film: film); showToast("MOVIE SAVED") }
                    catch { camera.error = error.localizedDescription }
                    // Only the writer-owned temporary file is removed after copying.
                    try? FileManager.default.removeItem(at: url)
                }
                movieHandlerSet = true
                if let error = library.loadError { camera.error = "Could not load memories: \(error)" }
            }
            camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else if phase == .background { camera.stop() }
        }
        .onChange(of: film) { _, _ in camera.update(film: film, strength: strength) }
        .onChange(of: strength) { _, _ in camera.update(film: film, strength: strength) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importing = true
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    camera.importPhoto(image) { processed in
                        defer { importing = false; pickerItem = nil }
                        save(processed)
                    }
                } catch { importing = false; pickerItem = nil; camera.error = error.localizedDescription }
            }
        }
    }

    private var masthead: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("pocket").font(.system(size: 26, weight: .black, design: .rounded)).tracking(-1.4)
                Text("03").font(.system(size: 26, weight: .ultraLight, design: .monospaced)).foregroundStyle(phosphor)
            }.foregroundStyle(Color(white: 0.88))
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("DIGITAL PRIMITIVISM").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1.5)
                HStack(spacing: 3) { ForEach(0..<6) { _ in Capsule().fill(.black.opacity(0.55)).frame(width: 3, height: 12) } }
            }.foregroundStyle(Color(white: 0.5))
        }.padding(.horizontal, 7)
    }

    private var viewfinder: some View {
        ZStack {
            Color.black
            if let image = camera.preview {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "camera.aperture").font(.system(size: 34, weight: .ultraLight))
                    Text(camera.cameraMessage ?? "WAKING UP THE CAMERA…")
                        .font(.system(size: 12, design: .monospaced)).multilineTextAlignment(.center)
                    if camera.cameraMessage != nil {
                        Button("OPEN SETTINGS") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }.padding(30).foregroundStyle(phosphor)
            }
            VStack {
                HStack {
                    if camera.isRecording {
                        Label(String(format: "%02d:%02d", camera.recordingSeconds / 60, camera.recordingSeconds % 60), systemImage: "record.circle.fill").foregroundStyle(.red)
                    } else { Text("[ \(film.rawValue) ]") }
                    Spacer()
                    Button { camera.toggleTorch() } label: { Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash") }
                        .disabled(camera.isDemo).accessibilityLabel("Toggle torch")
                }
                Spacer()
                HStack {
                    Button { camera.setZoom(camera.zoom >= 3 ? 1 : camera.zoom + 1) } label: { Text(String(format: "%.0f×", camera.zoom)).padding(9).background(.black.opacity(0.35), in: Circle()) }
                        .disabled(camera.isDemo).accessibilityLabel("Digital zoom")
                    Spacer()
                    if camera.isDemo { Text("SIMULATOR SCENE").font(.system(size: 8, design: .monospaced)) }
                    Spacer()
                    Button { camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 19)).padding(7).background(.black.opacity(0.35), in: Circle()) }
                        .disabled(camera.isDemo || camera.isRecording).accessibilityLabel("Switch camera")
                }
            }.font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.6), radius: 2).padding(13)
            // A focus reticle is decorative; it does not pretend to be autofocus control.
            Rectangle().stroke(.white.opacity(0.38), lineWidth: 0.7).frame(width: 43, height: 43)
            if let toast {
                Text(toast).font(.system(size: 11, weight: .bold, design: .monospaced)).padding(14).foregroundStyle(ink).background(phosphor).transition(.opacity)
            }
            if importing || camera.isFinishing { ProgressView().tint(phosphor).padding(20).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8)) }
            if flashing { Color.white.opacity(0.8) }
        }.aspectRatio(3 / 4, contentMode: .fit).clipped()
    }
    private var filmSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("CHOOSE YOUR MEMORY").font(.system(size: 13, weight: .bold, design: .monospaced)); Spacer(); Button("Done") { options = false } }
            ForEach(Film.allCases) { item in
                Button { film = item } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.rawValue).font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: film == item ? "largecircle.fill.circle" : "circle")
                    }.foregroundStyle(film == item ? phosphor : .white)
                }
            }
            HStack { Text("CHARACTER"); Spacer(); Text("\(Int(strength * 100))%") }.font(.system(size: 10, design: .monospaced))
            Slider(value: $strength, in: 0...1).tint(phosphor).accessibilityLabel("Effect strength")
        }.padding(25).presentationDragIndicator(.visible)
    }
    private func shutter() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if videoMode { camera.toggleRecording() }
        else {
            flashing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { flashing = false }
            camera.capture { save($0) }
        }
    }
    private func save(_ image: UIImage?) {
        guard let image else { camera.error = "The image could not be processed. Please try again."; return }
        do { try library.savePhoto(image, film: film); showToast("MEMORY SAVED") }
        catch { camera.error = error.localizedDescription }
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
