import XCTest
import AVFoundation
@testable import Pocket03

final class Pocket03Tests: XCTestCase {
    func testEveryTreatmentProducesPortraitVGA() throws {
        let processor = RetroProcessor()
        for film in Film.allCases {
            let rendered = try XCTUnwrap(processor.process(RetroProcessor.demoScene(), film: film, strength: 0.8))
            XCTAssertEqual(rendered.width, 480)
            XCTAssertEqual(rendered.height, 640)
        }
    }
    func testZeroStrengthPreservesSolidSourceColor() throws {
        let processor = RetroProcessor()
        let source = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 900, height: 400))
        let rendered = try XCTUnwrap(processor.process(source, film: .mono, strength: 0))
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(CIImage(cgImage: rendered), toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 240, y: 320, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        XCTAssertEqual(Int(pixel[0]), 204, accuracy: 3)
        XCTAssertEqual(Int(pixel[1]), 51, accuracy: 3)
        XCTAssertEqual(Int(pixel[2]), 102, accuracy: 3)
    }
    func testGrainDoesNotClipFlatMidtones() throws {
        let processor = RetroProcessor()
        let source = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 480, height: 640))
        let rendered = try XCTUnwrap(processor.process(source, film: .daydream, strength: 1))
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        processor.context.render(CIImage(cgImage: rendered), toBitmap: &pixels, rowBytes: 64 * 4,
            bounds: CGRect(x: 208, y: 288, width: 64, height: 64), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let reds = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) }
        XCTAssertLessThan(try XCTUnwrap(reds.max()) - XCTUnwrap(reds.min()), 70)
        XCTAssertLessThan(reds.reduce(0, +) / reds.count, 170)
    }
    func testImportRespectsEXIFRotation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let rotated = UIImage(cgImage: try XCTUnwrap(source.cgImage), scale: 1, orientation: .right)
        let image = try XCTUnwrap(RetroProcessor.oriented(rotated))
        XCTAssertEqual(image.extent.width, 20)
        XCTAssertEqual(image.extent.height, 40)
    }
    @MainActor func testSavedPhotoSurvivesLibraryReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MediaLibrary(folder: directory)
        let cg = try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .candy, strength: 1))
        let memory = try library.savePhoto(UIImage(cgImage: cg), film: .candy)
        let reloaded = MediaLibrary(folder: directory)
        XCTAssertEqual(reloaded.memories.count, 1)
        XCTAssertEqual(reloaded.memories.first?.id, memory.id)
        let saved = try XCTUnwrap(reloaded.thumbnail(memory))
        XCTAssertEqual(saved.size, CGSize(width: 480, height: 640))
        XCTAssertEqual(reloaded.memories.first?.film, .candy)
    }
    @MainActor func testDeleteRemovesEntryAndFilesAndSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MediaLibrary(folder: directory)
        let cg = try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .dreamy, strength: 1))
        let kept = try library.savePhoto(UIImage(cgImage: cg), film: .dreamy)
        let doomed = try library.savePhoto(UIImage(cgImage: cg), film: .nokia2630)
        XCTAssertNotNil(library.thumbnail(doomed))
        try library.delete(doomed)
        XCTAssertEqual(library.memories.map(\.id), [kept.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.url(doomed).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(kept).path))
        XCTAssertNil(library.thumbnail(doomed))
        let reloaded = MediaLibrary(folder: directory)
        XCTAssertEqual(reloaded.memories.map(\.id), [kept.id])
    }
    @MainActor func testUnreadableManifestIsReported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("index.json"))
        let library = MediaLibrary(folder: directory)
        XCTAssertNotNil(library.loadError)
        let image = UIImage(cgImage: try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .daydream, strength: 1)))
        XCTAssertThrowsError(try library.savePhoto(image, film: .daydream))
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("index.json")), "broken")
    }
    @MainActor func testFailedIndexCommitLeavesNoOrphanAndKeepsSourceMovie() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: source) }
        let library = MediaLibrary(folder: directory)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("index.json"), withIntermediateDirectories: true)
        let image = UIImage(cgImage: try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .daydream, strength: 1)))
        XCTAssertThrowsError(try library.savePhoto(image, film: .daydream))
        try Data("source movie fixture".utf8).write(to: source)
        XCTAssertThrowsError(try library.saveVideo(source, thumbnail: image, film: .daydream))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["index.json"])
        XCTAssertTrue(library.memories.isEmpty)
    }
    func testFilteredVideoIsPlayablePortraitWithoutAudio() async throws {
        let writer = try SilentVideoWriter()
        let cg = try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .dusk, strength: 0.8))
        for frame in 0..<10 {
            try writer.append(cg, at: CMTime(value: Int64(frame), timescale: 15))
            // Allow the encoder to consume buffers; this is a finite integration fixture.
            try await Task.sleep(for: .milliseconds(40))
        }
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            writer.finish { continuation.resume(with: $0) }
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 480, height: 640))
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.2)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
    }
    func testThreePrimaryLooksAndLegacyGalleryIdentifiers() throws {
        XCTAssertEqual(Film.cameraLooks.map(\.rawValue), ["Dreamy (original)", "Nokia 2630 (2007)", "Siemens CX70 (2004)"])
        XCTAssertEqual(try JSONDecoder().decode(Film.self, from: Data("\"DAYDREAM\"".utf8)), .daydream)
        XCTAssertEqual(try JSONDecoder().decode(Film.self, from: Data("\"AFTER HOURS\"".utf8)), .dusk)
        XCTAssertEqual(try JSONDecoder().decode(Film.self, from: Data("\"CANDY CCD\"".utf8)), .candy)
        XCTAssertEqual(try JSONDecoder().decode(Film.self, from: Data("\"MONO 01\"".utf8)), .mono)
    }
    func testImportedVideoUsesEveryLookAndPreservesFrames() async throws {
        let cg = try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .dreamy, strength: 0))
        let source = try await FixtureMovie.write(frames: 8, image: cg)
        defer { try? FileManager.default.removeItem(at: source) }
        // FixtureMovie writes every frame it is handed, so the source count is exact rather
        // than a function of machine load; the importer must then preserve exactly that count.
        let originalFrames = try await frameCount(source)
        XCTAssertEqual(originalFrames, 8)
        for look in Film.cameraLooks {
            let movie = try await VideoImporter().process(url: source, film: look, strength: 0.8) { _ in }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            XCTAssertEqual(movie.thumbnail.size, CGSize(width: 480, height: 640))
            let actualFrames = try await frameCount(movie.url)
            XCTAssertEqual(actualFrames, originalFrames, "\(look.rawValue) did not preserve every frame")
            let audio = try await AVURLAsset(url: movie.url).loadTracks(withMediaType: .audio)
            XCTAssertTrue(audio.isEmpty)
        }
    }
    func testCancelledImportStopsAndRemovesItsTemporaryFile() async throws {
        let cg = try XCTUnwrap(RetroProcessor().process(RetroProcessor.demoScene(), film: .dreamy, strength: 0))
        let source = try await FixtureMovie.write(frames: 48, image: cg)
        defer { try? FileManager.default.removeItem(at: source) }
        let before = Self.temporaryMovieNames()
        let reported = expectation(description: "first progress report")
        reported.assertForOverFulfill = false
        let lock = NSLock()
        var observed: [Double] = []
        let task = Task {
            try await VideoImporter().process(url: source, film: .nokia2630, strength: 0.8) { value in
                lock.lock(); observed.append(value); lock.unlock()
                reported.fulfill()
            }
        }
        await fulfillment(of: [reported], timeout: 60)
        task.cancel()
        do {
            let finished = try await task.value
            try? FileManager.default.removeItem(at: finished.url)
            XCTFail("The import completed before cancellation could be observed.")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected cancellation, got \(error)")
        }
        lock.lock(); let values = observed; lock.unlock()
        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 <= 1 }, "progress left 0...1: \(values)")
        XCTAssertEqual(Self.temporaryMovieNames().subtracting(before), [], "a cancelled import left a temporary movie behind")
    }
    private static func temporaryMovieNames() -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        return Set((names ?? []).filter { $0.hasSuffix(".mov") })
    }
    private func frameCount(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 480, height: 640))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        while let sample = output.copyNextSampleBuffer() { if CMSampleBufferGetImageBuffer(sample) != nil { count += 1 } }
        XCTAssertEqual(reader.status, .completed)
        return count
    }

}

// A deterministic movie fixture. The production SilentVideoWriter is a live-capture writer: it is
// real-time and deliberately drops frames the encoder is not ready for, so the frame count it
// actually writes varies with machine load. A fixture has to be exact, so this one is offline and
// pull driven -- it hands over a frame only when the encoder asks for one, and never drops.
enum FixtureMovie {
    static func write(frames: Int, image: CGImage, fps: Int32 = 15) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 480, AVVideoHeightKey: 640])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 640,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(input) else { throw CocoaError(.featureUnsupported) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        let source = CIImage(cgImage: image)
        let queue = DispatchQueue(label: "studio.pocket03.fixture")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var next = 0
            var settled = false
            input.requestMediaDataWhenReady(on: queue) {
                while !settled && input.isReadyForMoreMediaData {
                    guard next < frames else {
                        settled = true
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed { continuation.resume() }
                            else { continuation.resume(throwing: writer.error ?? CocoaError(.fileWriteUnknown)) }
                        }
                        return
                    }
                    do {
                        guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
                        var buffer: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                              let buffer else { throw CocoaError(.fileWriteUnknown) }
                        context.render(source, to: buffer)
                        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(next), timescale: fps))
                        else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                        next += 1
                    } catch {
                        settled = true
                        writer.cancelWriting()
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(throwing: error)
                        return
                    }
                }
            }
        }
        return url
    }
}
