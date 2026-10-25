import XCTest

final class AtlasLiveActivityUITests: XCTestCase {
    @MainActor func testRealActivityStartsUpdatesAndEndsWithDemoData() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--live-activity"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Start Live Activity"].waitForExistence(timeout: 10))
        app.buttons["Start Live Activity"].tap()
        XCTAssertTrue(app.staticTexts["Live Activity started · Demo data"].waitForExistence(timeout: 8))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        capture(springboard, "atlas-live-activity-compact-single-demo")
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 30))
        island.press(forDuration: 1.5)
        let firstTitle = NSPredicate(format: "label CONTAINS %@", "Plan the Lisbon offsite")
        XCTAssertTrue(springboard.staticTexts.matching(firstTitle).firstMatch.waitForExistence(timeout: 5))
        capture(springboard, "atlas-live-activity-expanded-single-demo")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        try setCount(2, in: app)
        try app.visibleElement("Update Live Activity", type: .button).tap()
        XCUIDevice.shared.press(.home)
        island.press(forDuration: 1.5)
        XCTAssertTrue(springboard.staticTexts["2 active"].waitForExistence(timeout: 5))
        capture(springboard, "atlas-live-activity-expanded-two-demo")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        try setCount(5, in: app)
        try app.visibleElement("Update Live Activity", type: .button).tap()
        XCTAssertTrue(app.staticTexts["Live Activity updated · Demo data"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        island.press(forDuration: 1.5)
        XCTAssertTrue(springboard.staticTexts["5 active"].waitForExistence(timeout: 5))
        XCTAssertTrue(springboard.staticTexts.matching(firstTitle).firstMatch.exists)
        let secondTitle = NSPredicate(format: "label CONTAINS %@", "Review the launch checklist")
        XCTAssertTrue(springboard.staticTexts.matching(secondTitle).firstMatch.exists)
        XCTAssertTrue(springboard.staticTexts["+3 more in Orbit"].exists)
        capture(springboard, "atlas-live-activity-expanded-multiple-demo")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let stale = try app.visibleElement("Stale", type: .switch)
        stale.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let staleEnabled = NSPredicate(format: "value == %@", "1")
        expectation(for: staleEnabled, evaluatedWith: stale)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(stale.value as? String, "1")
        try app.visibleElement("Update Live Activity", type: .button).tap()
        XCUIDevice.shared.press(.home)
        island.press(forDuration: 1.5)
        XCTAssertTrue(springboard.staticTexts["Updates unavailable · Open Atlas"].waitForExistence(timeout: 5))
        capture(springboard, "atlas-live-activity-stale-demo")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        try app.visibleElement("End Live Activity", type: .button).tap()
        XCTAssertTrue(app.staticTexts["Live Activity ended · Demo data"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertFalse(springboard.staticTexts["5 active"].exists)
        capture(springboard, "atlas-live-activity-ended-demo")
    }

    @MainActor func testLargeTextKeepsStaleAndAdditionalWorkVisible() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--live-activity", "--long-activity-title", "--dark", "--large-text"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.steppers["activity-count"].waitForExistence(timeout: 10))
        try setCount(3, in: app)
        XCTAssertTrue(app.staticTexts["+2 more in Orbit"].exists)
        capture(app, "atlas-live-activity-large-text-demo")
    }

    @MainActor func testLongTitleInRealExpandedActivity() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--live-activity", "--long-activity-title"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start Live Activity"].waitForExistence(timeout: 10))
        app.buttons["Start Live Activity"].tap()
        XCTAssertTrue(app.staticTexts["Live Activity started · Demo data"].waitForExistence(timeout: 8))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 30))
        island.press(forDuration: 1.5)
        let title = NSPredicate(format: "label CONTAINS %@", "compare travel options for the whole team")
        XCTAssertTrue(springboard.staticTexts.matching(title).firstMatch.waitForExistence(timeout: 5))
        capture(springboard, "atlas-live-activity-expanded-long-title-demo")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        try app.visibleElement("End Live Activity", type: .button).tap()
        XCTAssertTrue(app.staticTexts["Live Activity ended · Demo data"].waitForExistence(timeout: 5))
    }

    @MainActor private func setCount(_ count: Int, in app: XCUIApplication) throws {
        let stepper = app.steppers["activity-count"]
        let current = try XCTUnwrap(Int(stepper.value as? String ?? ""))
        guard current < count else { return }
        for value in (current + 1)...count {
            let increment = stepper.buttons.element(boundBy: 1)
            for _ in 0..<8 {
                if increment.isHittable, app.frame.contains(increment.frame) { break }
                app.scrollContent()
            }
            XCTAssertTrue(increment.isHittable)
            increment.tap()
            let changed = NSPredicate(format: "value == %@", String(value))
            expectation(for: changed, evaluatedWith: stepper)
            waitForExpectations(timeout: 3)
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
