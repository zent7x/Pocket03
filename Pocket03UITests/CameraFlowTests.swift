import XCTest

final class CameraFlowTests: XCTestCase {
    private func readyCamera(_ app: XCUIApplication) {
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        app.buttons["mode-photo"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shutter)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }
    func testCaptureMovieAndPersistentGallery() throws {
        let app = XCUIApplication(); app.launch(); readyCamera(app)
        let initialCount = try XCTUnwrap(Int(app.staticTexts["gallery-count"].label))
        let shutter = app.buttons["shutter"]
        shutter.tap()
        XCTAssertTrue(app.staticTexts["MEMORY SAVED"].waitForExistence(timeout: 10))
        app.buttons["memories"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memory-")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["options"].tap()
        app.buttons["mode-video"].tap()
        shutter.tap()
        XCTAssertTrue(app.staticTexts["00:02"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mode-photo"].isEnabled)
        XCTAssertFalse(app.buttons["look-selector"].isEnabled)
        shutter.tap()
        XCTAssertTrue(app.staticTexts["MOVIE SAVED"].waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["gallery-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(Int(app.staticTexts["gallery-count"].label), initialCount + 2)
        app.buttons["memories"].tap()
        let gallery = XCTAttachment(screenshot: app.screenshot()); gallery.name = "Phone gallery"; gallery.lifetime = .keepAlways; add(gallery)
        app.buttons["options"].tap()
        let camera = XCTAttachment(screenshot: app.screenshot()); camera.name = "Series 40 style camera"; camera.lifetime = .keepAlways; add(camera)
    }
    func testAllThreeLooksAndWorkflowTabs() throws {
        let app = XCUIApplication(); app.launch(); readyCamera(app)
        for index in 0..<3 {
            app.buttons["look-selector"].tap()
            app.buttons["look-\(index)"].tap()
            let expected = ["Dreamy (original)", "Nokia 2630 (2007)", "Siemens CX70 (2004)"][index]
            XCTAssertTrue(app.staticTexts[expected].exists)
        }
        app.buttons["mode-import"].tap()
        XCTAssertTrue(app.buttons["Open gallery"].exists)
        XCTAssertEqual(app.buttons["shutter"].label, "Open")
        app.buttons["mode-video"].tap()
        XCTAssertEqual(app.buttons["shutter"].label, "Record")
        app.buttons["mode-photo"].tap()
        XCTAssertEqual(app.buttons["shutter"].label, "Capture")
        app.buttons["options"].tap()
        XCTAssertTrue(app.buttons["3 Import photo / video"].exists || app.staticTexts["Import photo / video"].exists)
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "Phone options"; menu.lifetime = .keepAlways; add(menu)
        app.buttons["options"].tap()
    }
}
