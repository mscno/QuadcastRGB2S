import XCTest

final class QuadcastRGBAppUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testModesExposeAppropriateControlsAndAccessibleColors() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
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
    @MainActor
    func testAudioControlsMeterRecordingPlaybackAndPrivacyLifecycle() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        app.staticTexts["Audio"].click()
        XCTAssertTrue(app.sliders["mic-volume"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["headphone-volume"].exists)
        XCTAssertTrue(app.sliders["monitor-volume"].exists)
        app.buttons["audio-mute"].click()
        XCTAssertTrue(app.buttons["Unmute in macOS"].waitForExistence(timeout: 3))
        app.buttons["pattern-stereo"].click()
        XCTAssertEqual(app.buttons["pattern-stereo"].value as? String, "Selected")
        let controls = XCTAttachment(screenshot: window.screenshot())
        controls.name = "Liquid Glass – Audio controls"
        controls.lifetime = .keepAlways
        add(controls)
        let scroll = app.scrollViews["audio-content"]
        scroll.swipeUp()
        app.buttons["start-meter"].click()
        XCTAssertTrue(app.buttons["Stop meter"].waitForExistence(timeout: 3))
        app.buttons["record-test"].click()
        XCTAssertTrue(app.buttons["Stop test"].exists)
        app.buttons["record-test"].click()
        XCTAssertTrue(app.buttons["play-test"].isEnabled)
        app.buttons["play-test"].click()
        XCTAssertTrue(app.buttons["Stop playback"].exists)
        app.buttons["discard-test"].click()
        XCTAssertFalse(app.buttons["play-test"].isEnabled)
        app.buttons["start-meter"].click()
        app.staticTexts["Solid"].click()
        app.staticTexts["Audio"].click()
        scroll.swipeUp()
        XCTAssertTrue(app.buttons["Start meter"].exists)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Liquid Glass – Audio"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testUnsupportedHardwareControlsAreClearlyUnavailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-audio-unavailable"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Audio"].click()
        XCTAssertTrue(app.sliders["mic-volume"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.sliders["headphone-volume"].isEnabled)
        XCTAssertFalse(app.sliders["monitor-volume"].exists)
        for pattern in ["cardioid", "omnidirectional", "bidirectional", "stereo"] {
            XCTAssertFalse(app.buttons["pattern-\(pattern)"].exists)
        }
        XCTAssertTrue(app.staticTexts["Tap-to-mute: awaiting device"].exists)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Liquid Glass – Audio hardware capabilities"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
