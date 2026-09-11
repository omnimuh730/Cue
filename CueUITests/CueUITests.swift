import XCTest

final class CueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAccessoryApp() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5) || app.state == .runningBackground)
    }
}
