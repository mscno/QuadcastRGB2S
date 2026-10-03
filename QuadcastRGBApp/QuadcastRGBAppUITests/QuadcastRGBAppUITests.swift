import XCTest

final class QuadcastRGBAppUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testModesExposeAppropriateControlsAndAccessibleColors() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(app.sliders["slider-Brightness"].exists)
        XCTAssertFalse(app.sliders["slider-Speed"].exists)
        XCTAssertTrue(app.buttons["color-Blue"].exists)
        app.buttons["color-Blue"].click()
        XCTAssertEqual(app.buttons["color-Blue"].value as? String, "Selected")
        app.staticTexts["Blink"].click()
        XCTAssertTrue(app.sliders["slider-Speed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["slider-Delay"].exists)
        app.staticTexts["Wave"].click()
        XCTAssertTrue(app.sliders["slider-Speed"].exists)
        XCTAssertFalse(app.sliders["slider-Delay"].exists)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Liquid Glass – Wave"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
