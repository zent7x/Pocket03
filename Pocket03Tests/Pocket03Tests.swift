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
}
