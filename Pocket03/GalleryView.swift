import SwiftUI
import AVKit

struct GalleryView: View {
    @ObservedObject var library: MediaLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Memory?
    var body: some View {
        NavigationStack {
            Group {
                if library.memories.isEmpty {
                    ContentUnavailableView("Small moments go here.", systemImage: "camera.aperture", description: Text("Take a photo or import one to start your pocket collection."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 17) {
                            ForEach(library.memories) { memory in
                                Button { selected = memory } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        ZStack(alignment: .bottomTrailing) {
                                            if let image = library.thumbnail(memory) {
                                                Image(uiImage: image).resizable().interpolation(.none).aspectRatio(3 / 4, contentMode: .fit)
                                            }
                                            if memory.isVideo { Image(systemName: "play.fill").padding(10).foregroundStyle(.white) }
                                        }
                                        Text(memory.film.rawValue).font(.system(size: 9, weight: .bold, design: .monospaced))
                                        Text(memory.date, format: .dateTime.day().month().year()).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    }.padding(8).background(Color(white: 0.15)).foregroundStyle(.white)
                                }.buttonStyle(.plain).accessibilityIdentifier("memory-\(memory.id)")
                            }
                        }.padding(20)
                    }
                }
            }
            .background(Color(white: 0.08))
            .navigationTitle("Memories").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $selected) { MemoryDetail(memory: $0, library: library) }
        }.tint(Color(red: 0.78, green: 0.87, blue: 0.65))
    }
}

struct MemoryDetail: View {
    let memory: Memory
    @ObservedObject var library: MediaLibrary
    @State private var player: AVPlayer?
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(memory.film.rawValue).font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Text(memory.isVideo ? "SILENT MOVIE" : "480 × 640").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            if memory.isVideo {
                VideoPlayer(player: player).aspectRatio(3 / 4, contentMode: .fit)
            } else if let image = library.thumbnail(memory) {
                Image(uiImage: image).resizable().interpolation(.none).aspectRatio(3 / 4, contentMode: .fit)
            }
            HStack(spacing: 30) {
                Button {
                    saving = true
                    Task {
                        do { try await library.export(memory); saved = true }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                } label: { Label(saving ? "Saving…" : saved ? "Saved to Photos" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down") }
                    .disabled(saving || saved)
                ShareLink(item: library.url(memory)) { Label("Share", systemImage: "square.and.arrow.up") }
            }.font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
        }.padding(23).padding(.top, 18).presentationDragIndicator(.visible)
            .onAppear { if memory.isVideo { player = AVPlayer(url: library.url(memory)); player?.play() } }
            .onDisappear { player?.pause(); player = nil }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
