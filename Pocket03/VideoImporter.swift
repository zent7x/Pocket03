@preconcurrency import AVFoundation
import CoreImage
import UIKit

struct ImportedVideo {
    let url: URL
    let thumbnail: UIImage
}

private final class ImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

// An offline reader/writer processes every frame without live-capture backpressure drops.
final class VideoImporter {
    func process(url: URL, film: Film, strength: Double,
                 progress: @escaping (Double) -> Void) async throws -> ImportedVideo {
        let cancelled = ImportCancellation()
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Pocket03", code: 10, userInfo: [NSLocalizedDescriptionKey: "This file has no readable video track."])
        }
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let queue = DispatchQueue(label: "studio.pocket03.import", qos: .userInitiated)
                queue.async {
                    do {
                        let job = try VideoImportJob(asset: asset, track: track, transform: transform,
                            duration: duration.seconds, film: film, strength: strength, cancelled: cancelled,
                            queue: queue, progress: progress, completion: { continuation.resume(with: $0) })
                        job.start()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancelled.cancel() }
    }
}

private final class VideoImportJob {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    private let processor = RetroProcessor()
    private let transform: CGAffineTransform
    private let duration: Double
    private let film: Film
    private let strength: Double
    private let cancelled: ImportCancellation
    private let queue: DispatchQueue
    private let progress: (Double) -> Void
    private let completion: (Result<ImportedVideo, Error>) -> Void
    private var firstTime: CMTime?
    private var thumbnail: UIImage?
    private var done = false
    // Own the job until reader/writer finalization; the input callback remains weak.
    private var keepAlive: VideoImportJob?
    private var lastProgress = -1

    init(asset: AVAsset, track: AVAssetTrack, transform: CGAffineTransform, duration: Double,
         film: Film, strength: Double, cancelled: ImportCancellation, queue: DispatchQueue,
         progress: @escaping (Double) -> Void, completion: @escaping (Result<ImportedVideo, Error>) -> Void) throws {
        self.transform = transform; self.duration = duration; self.film = film; self.strength = strength
        self.cancelled = cancelled; self.queue = queue; self.progress = progress; self.completion = completion
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 480, AVVideoHeightKey: 640,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000]])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 640,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard reader.canAdd(output), writer.canAdd(input) else { throw CocoaError(.featureUnsupported) }
        reader.add(output); writer.add(input)
    }
    func start() {
        keepAlive = self
        guard writer.startWriting(), reader.startReading() else {
            fail(writer.error ?? reader.error ?? CocoaError(.fileReadUnknown)); return
        }
        writer.startSession(atSourceTime: .zero)
        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self else { return }
            while input.isReadyForMoreMediaData && !done {
                if cancelled.isCancelled { fail(CancellationError()); return }
                do {
                    let hasFrame = try autoreleasepool { try self.appendNextFrame() }
                    if !hasFrame { finish(); return }
                } catch { fail(error); return }
            }
        }
    }
    private func appendNextFrame() throws -> Bool {
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
            return false
        }
        guard let source = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool,
              let image = processor.process(CIImage(cvPixelBuffer: source).transformed(by: transform), film: film, strength: strength) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if thumbnail == nil { thumbnail = UIImage(cgImage: image) }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        if firstTime == nil { firstTime = timestamp }
        let time = CMTimeSubtract(timestamp, firstTime!)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
            throw CocoaError(.fileWriteUnknown)
        }
        processor.context.render(CIImage(cgImage: image), to: buffer)
        guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        let percent = duration.isFinite && duration > 0 ? min(99, max(0, Int(time.seconds / duration * 100))) : 0
        if percent != lastProgress { lastProgress = percent; DispatchQueue.main.async { self.progress(Double(percent) / 100) } }
        return true
    }
    private func finish() {
        guard !done else { return }; done = true
        guard let thumbnail else { failAfterStopping(CocoaError(.fileReadCorruptFile)); return }
        input.markAsFinished()
        writer.finishWriting { [self] in
            if writer.status == .completed && !cancelled.isCancelled {
                DispatchQueue.main.async { self.progress(1) }
                completion(.success(ImportedVideo(url: url, thumbnail: thumbnail)))
                keepAlive = nil
            } else { failAfterStopping(cancelled.isCancelled ? CancellationError() : writer.error ?? CocoaError(.fileWriteUnknown)) }
        }
    }
    private func fail(_ error: Error) {
        guard !done else { return }; done = true
        failAfterStopping(error)
    }
    private func failAfterStopping(_ error: Error) {
        reader.cancelReading()
        if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
        completion(.failure(error))
        keepAlive = nil
    }
}
