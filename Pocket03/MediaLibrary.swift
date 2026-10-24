import AVFoundation
import Photos
import SwiftUI

struct Memory: Identifiable, Codable {
    let id: UUID
    let date: Date
    let filename: String
    let thumbnail: String
    let film: Film
    let isVideo: Bool
}

@MainActor final class MediaLibrary: ObservableObject {
    @Published private(set) var memories: [Memory] = []
    let folder: URL
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Memories", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
            let manifest = self.folder.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                memories = try JSONDecoder().decode([Memory].self, from: Data(contentsOf: manifest))
            }
        } catch { loadError = error.localizedDescription }
    }
    private(set) var loadError: String?
    func url(_ memory: Memory) -> URL { folder.appendingPathComponent(memory.filename) }
    func thumbnail(_ memory: Memory) -> UIImage? { UIImage(contentsOfFile: folder.appendingPathComponent(memory.thumbnail).path) }
    @discardableResult func savePhoto(_ image: UIImage, film: Film) throws -> Memory {
        try ensureWritable()
        guard let data = image.jpegData(compressionQuality: 0.72) else { throw CocoaError(.fileWriteUnknown) }
        let id = UUID(), name = UUID().uuidString + ".jpg"
        let memory = Memory(id: id, date: Date(), filename: name, thumbnail: name, film: film, isVideo: false)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        do { try insert(memory) }
        catch { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)); throw error }
        return memory
    }
    @discardableResult func saveVideo(_ source: URL, thumbnail: UIImage, film: Film) throws -> Memory {
        try ensureWritable()
        let name = UUID().uuidString, filename = name + ".mov", thumb = name + ".jpg"
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(filename))
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(thumb))
            }
        }
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(filename))
        guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: folder.appendingPathComponent(thumb), options: .atomic)
        let memory = Memory(id: UUID(), date: Date(), filename: filename, thumbnail: thumb, film: film, isVideo: true)
        try insert(memory)
        committed = true
        return memory
    }
    private func ensureWritable() throws {
        if let loadError { throw NSError(domain: "Pocket03", code: 4, userInfo: [NSLocalizedDescriptionKey: "The memory index could not be read. Existing files were preserved: \(loadError)"]) }
    }
    private func insert(_ memory: Memory) throws {
        let updated = [memory] + memories
        try JSONEncoder().encode(updated).write(to: folder.appendingPathComponent("index.json"), options: .atomic)
        memories = updated
    }
    func export(_ memory: Memory) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "Pocket03", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow Photos access in Settings to save this memory."])
        }
        let source = url(memory)
        try await PHPhotoLibrary.shared().performChanges {
            if memory.isVideo { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: source) }
            else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: source) }
        }
    }
}

// Called only from CameraEngine's serial frame queue.
final class SilentVideoWriter {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var firstTime: CMTime?
    private let context = CIContext()
    init() throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 480, AVVideoHeightKey: 640,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000, AVVideoMaxKeyFrameIntervalKey: 30]])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 640,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(input) else { throw CocoaError(.coderInvalidValue) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
    func append(_ image: CGImage, at time: CMTime) throws {
        if firstTime == nil { firstTime = time; writer.startSession(atSourceTime: time) }
        guard writer.status == .writing else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { throw CocoaError(.fileWriteUnknown) }
        context.render(CIImage(cgImage: image), to: pixel)
        guard adaptor.append(pixel, withPresentationTime: time) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
    func finish(_ completion: @escaping (Result<URL, Error>) -> Void) {
        guard firstTime != nil else {
            writer.cancelWriting()
            completion(.failure(NSError(domain: "Pocket03", code: 2, userInfo: [NSLocalizedDescriptionKey: "No video frames were captured. Try recording a little longer."])))
            return
        }
        input.markAsFinished()
        writer.finishWriting { [self] in
            if writer.status == .completed { completion(.success(url)) }
            else { completion(.failure(writer.error ?? CocoaError(.fileWriteUnknown))) }
        }
    }
}
