import XCTest

final class CameraFlowTests: XCTestCase {
    func testCaptureMovieAndPersistentGallery() throws {
        let app = XCUIApplication()
        app.launch()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        shutter.tap()
        XCTAssertTrue(app.staticTexts["MEMORY SAVED"].waitForExistence(timeout: 10))
        app.buttons["memories"].tap()
        let memories = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memory-"))
        XCTAssertTrue(memories.firstMatch.waitForExistence(timeout: 5))
        let count = memories.count
        app.buttons["Done"].tap()
        app.buttons["mode"].tap()
        shutter.tap()
        XCTAssertTrue(app.staticTexts["00:02"].waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(app.staticTexts["MOVIE SAVED"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        app.buttons["memories"].tap()
        XCTAssertTrue(memories.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(memories.count, count + 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Persistent photo and video gallery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        let camera = XCTAttachment(screenshot: app.screenshot())
        camera.name = "Pocket03 camera"
        camera.lifetime = .keepAlways
        add(camera)
    }
}
