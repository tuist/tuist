import SnapshotTesting
import SwiftUI
import XCTest

@testable import App

final class SnapshotTests: XCTestCase {
    static var attemptCount = 0

    func testContentViewSnapshot() {
        Self.attemptCount += 1
        let attempt = Self.attemptCount

        let view = ContentView()
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.frame = UIScreen.main.bounds

        let renderer = UIGraphicsImageRenderer(bounds: hostingController.view.bounds)
        let image = renderer.image { _ in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }

        let imageData = image.pngData()!
        let imageAttachment = XCTAttachment(data: imageData, uniformTypeIdentifier: "public.png")
        imageAttachment.name = "content-view-attempt-\(attempt).png"
        imageAttachment.lifetime = .keepAlways
        add(imageAttachment)

        let logText = "Attempt \(attempt): status=\(attempt <= 2 ? "failing" : "passing")\nTimestamp: \(Date())"
        let logAttachment = XCTAttachment(string: logText)
        logAttachment.name = "log-attempt-\(attempt).txt"
        logAttachment.lifetime = .keepAlways
        add(logAttachment)

        if attempt <= 2 {
            XCTFail("Intentional failure on attempt \(attempt)")
        }
    }

    static var alwaysFailCount = 0

    func testAlwaysFailingSnapshot() {
        Self.alwaysFailCount += 1
        let attempt = Self.alwaysFailCount

        let view = ContentView()
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.frame = UIScreen.main.bounds

        let renderer = UIGraphicsImageRenderer(bounds: hostingController.view.bounds)
        let image = renderer.image { _ in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }

        let imageData = image.pngData()!
        let imageAttachment = XCTAttachment(data: imageData, uniformTypeIdentifier: "public.png")
        imageAttachment.name = "always-fail-attempt-\(attempt).png"
        imageAttachment.lifetime = .keepAlways
        add(imageAttachment)

        let logText = "Always-fail attempt \(attempt)\nTimestamp: \(Date())"
        let logAttachment = XCTAttachment(string: logText)
        logAttachment.name = "always-fail-log-attempt-\(attempt).txt"
        logAttachment.lifetime = .keepAlways
        add(logAttachment)

        XCTFail("This test always fails on attempt \(attempt)")
    }
}
