import XCTest

final class QuadcastRGBAppUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    @MainActor
    func testLaunchWithoutDeviceShowsUsableSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["custom-color"].exists)
        XCTAssertTrue(app.buttons["reconnect"].exists)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Liquid Glass – Launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
