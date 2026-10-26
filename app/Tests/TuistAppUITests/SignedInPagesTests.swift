import XCTest

final class SignedInPagesTests: XCTestCase {
    @MainActor
    func test_signedInPagesRemainReachableAfterRotation() throws {
        let app = XCUIApplication()
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        let profile = app.buttons["Profile"].firstMatch
        try XCTSkipUnless(
            profile.waitForExistence(timeout: 10),
            "Sign in on the simulator before running the live-account screenshot test."
        )

        let projectSelector = app.buttons["preview-project-selector"]
        XCTAssertTrue(projectSelector.waitForExistence(timeout: 30))
        projectSelector.tap()
        let project = app.buttons["tuist/wikipedia"].firstMatch
        for _ in 0 ..< 10 {
            if project.isHittable { break }
            app.swipeUp()
        }
        try XCTSkipUnless(project.isHittable, "The demo account must have access to tuist/wikipedia.")
        project.tap()
        capture("03-previews-portrait", app: app)
        let previewRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "preview-row-")).firstMatch
        XCTAssertTrue(previewRow.waitForExistence(timeout: 30))
        if previewRow.exists {
            previewRow.tap()
            XCTAssertTrue(app.staticTexts["Details"].waitForExistence(timeout: 30))
            capture("04-preview-detail-portrait", app: app)
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.staticTexts["Details"].exists)
            capture("05-preview-detail-after-rotation", app: app)
            XCUIDevice.shared.orientation = .portrait
        }

        profile.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 10))
        capture("06-profile-portrait", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.swipeUp()
        XCTAssertTrue(app.buttons["Sign out"].isHittable)
        capture("07-profile-actions-after-rotation", app: app)
        XCUIDevice.shared.orientation = .portrait

        app.buttons["Previews"].firstMatch.tap()
        capture("08-previews-return", app: app)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let idle = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.activityIndicators.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 30), .completed)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
